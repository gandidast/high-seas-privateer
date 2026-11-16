class_name WorldMap
extends Node
## Deterministic world manager wrapping Contracts water depth, 8 named islands,
## 3 safe harbor zones, 5 wild coastal fort islands, shoals, ship hull collision checks,
## global wind state, and dynamic weather (Clear, Fog, Storm).

const HULL_SAMPLE_ANGLES: int = 8
const WIND_EMIT_INTERVAL: float = 0.20
const WEATHER_EMIT_INTERVAL: float = 0.35
const BAD_WEATHER_ENABLED: bool = false

var world_seed: int = Contracts.DEFAULT_WORLD_SEED
var islands: Array[Contracts.IslandData] = []
var wind_direction: Vector2 = Vector2.RIGHT
var wind_strength: float = 1.0
var wind_time: float = 0.0

var current_weather: int = Contracts.WeatherState.CLEAR
var weather_intensity: float = 0.0
var weather_timer: float = 45.0

var _base_wind_angle: float = 0.45
var _wind_emit_accum: float = 0.0
var _weather_emit_accum: float = 0.0
var _target_weather: int = Contracts.WeatherState.CLEAR
var _target_intensity: float = 0.0
var _lightning_cooldown: float = 6.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	if islands.is_empty():
		setup(world_seed)


func setup(p_seed: int = Contracts.DEFAULT_WORLD_SEED) -> void:
	world_seed = p_seed
	islands = Contracts.get_islands(world_seed)
	wind_time = 0.0
	_wind_emit_accum = 0.0
	_weather_emit_accum = 0.0
	_base_wind_angle = fmod(absf(float(world_seed % 100000) * 0.137), TAU)
	_rng.seed = world_seed + 7919

	current_weather = Contracts.WeatherState.CLEAR
	_target_weather = Contracts.WeatherState.CLEAR
	weather_intensity = 0.0
	_target_intensity = 0.0
	weather_timer = 45.0
	_lightning_cooldown = 5.5

	_evaluate_wind()
	Contracts.bus().world_initialized.emit(world_seed, islands)
	Contracts.bus().wind_changed.emit(wind_direction, wind_strength)
	Contracts.bus().weather_changed.emit(current_weather, weather_intensity)


func set_weather(state: int, intensity: float = 1.0) -> void:
	var clamped_state: int = clampi(state, Contracts.WeatherState.CLEAR, Contracts.WeatherState.STORM)
	var clamped_intensity: float = clampf(intensity, 0.0, 1.0)
	if not BAD_WEATHER_ENABLED:
		clamped_state = Contracts.WeatherState.CLEAR
		clamped_intensity = 0.0
	elif clamped_state == Contracts.WeatherState.CLEAR and intensity >= 1.0:
		clamped_intensity = 0.0

	current_weather = clamped_state
	_target_weather = clamped_state
	weather_intensity = clamped_intensity
	_target_intensity = clamped_intensity
	weather_timer = 45.0 if clamped_state == Contracts.WeatherState.CLEAR else 32.0
	_lightning_cooldown = _rng.randf_range(3.5, 7.5)

	_evaluate_wind()
	Contracts.bus().weather_changed.emit(current_weather, weather_intensity)
	Contracts.bus().wind_changed.emit(wind_direction, wind_strength)


func _evaluate_wind() -> void:
	var angle: float = _base_wind_angle + sin(wind_time * 0.045) * 0.65 + wind_time * 0.018
	wind_direction = Vector2.from_angle(angle).normalized()
	var base_strength: float = clampf(0.90 + 0.22 * sin(wind_time * 0.07 + 1.1), 0.60, 1.25)
	if current_weather == Contracts.WeatherState.STORM:
		var storm_blend: float = clampf(weather_intensity, 0.0, 1.0)
		wind_strength = lerpf(base_strength, 1.15, maxf(0.55, storm_blend))
	elif current_weather == Contracts.WeatherState.FOG:
		var fog_blend: float = clampf(weather_intensity, 0.0, 1.0)
		wind_strength = lerpf(base_strength, 0.78, fog_blend * 0.65)
	else:
		wind_strength = base_strength


func step_wind(delta: float) -> void:
	if delta <= 0.0:
		return
	_step_weather(delta)

	var prev_dir: Vector2 = wind_direction
	var prev_str: float = wind_strength
	wind_time += delta
	_evaluate_wind()
	_wind_emit_accum += delta
	var angle_delta: float = absf(prev_dir.angle_to(wind_direction))
	var str_delta: float = absf(prev_str - wind_strength)
	if _wind_emit_accum >= WIND_EMIT_INTERVAL or angle_delta > 0.008 or str_delta > 0.01:
		_wind_emit_accum = 0.0
		Contracts.bus().wind_changed.emit(wind_direction, wind_strength)


func _step_weather(delta: float) -> void:
	if not BAD_WEATHER_ENABLED:
		var was_active: bool = (
			current_weather != Contracts.WeatherState.CLEAR
			or weather_intensity > 0.0
		)
		current_weather = Contracts.WeatherState.CLEAR
		_target_weather = Contracts.WeatherState.CLEAR
		weather_intensity = 0.0
		_target_intensity = 0.0
		if was_active:
			Contracts.bus().weather_changed.emit(current_weather, weather_intensity)
		return

	weather_timer -= delta
	if weather_timer <= 0.0:
		_advance_weather_cycle()

	var prev_intensity: float = weather_intensity
	var prev_weather: int = current_weather

	if _target_weather != current_weather:
		# Smoothly fade out current weather before switching to target state
		weather_intensity = move_toward(weather_intensity, 0.0, delta * 0.25)
		if weather_intensity <= 0.01:
			current_weather = _target_weather
			weather_intensity = 0.0
	else:
		weather_intensity = move_toward(weather_intensity, _target_intensity, delta * 0.20)

	if current_weather == Contracts.WeatherState.STORM and weather_intensity >= 0.35:
		_lightning_cooldown -= delta
		if _lightning_cooldown <= 0.0:
			_lightning_cooldown = _rng.randf_range(3.8, 8.5)
			var extent: float = Contracts.WORLD_HALF_EXTENT * 0.65
			var flash_pos := Vector2(
				_rng.randf_range(-extent, extent),
				_rng.randf_range(-extent, extent)
			)
			Contracts.bus().lightning_flash.emit(flash_pos)

	_weather_emit_accum += delta
	if (
		prev_weather != current_weather
		or absf(prev_intensity - weather_intensity) > 0.04
		or _weather_emit_accum >= WEATHER_EMIT_INTERVAL
	):
		if prev_weather != current_weather or absf(prev_intensity - weather_intensity) > 0.005:
			_weather_emit_accum = 0.0
			Contracts.bus().weather_changed.emit(current_weather, weather_intensity)


func _advance_weather_cycle() -> void:
	if _target_weather == Contracts.WeatherState.CLEAR:
		var roll: float = _rng.randf()
		if roll < 0.55:
			_target_weather = Contracts.WeatherState.FOG
			_target_intensity = _rng.randf_range(0.75, 1.0)
			weather_timer = _rng.randf_range(26.0, 38.0)
		else:
			_target_weather = Contracts.WeatherState.STORM
			_target_intensity = _rng.randf_range(0.80, 1.0)
			weather_timer = _rng.randf_range(28.0, 40.0)
	elif _target_weather == Contracts.WeatherState.FOG:
		if _rng.randf() < 0.45:
			_target_weather = Contracts.WeatherState.STORM
			_target_intensity = 1.0
			weather_timer = _rng.randf_range(26.0, 38.0)
		else:
			_target_weather = Contracts.WeatherState.CLEAR
			_target_intensity = 0.0
			weather_timer = _rng.randf_range(38.0, 52.0)
	else:
		_target_weather = Contracts.WeatherState.CLEAR
		_target_intensity = 0.0
		weather_timer = _rng.randf_range(40.0, 55.0)


func get_fort_positions() -> Array[Dictionary]:
	if islands.is_empty():
		islands = Contracts.get_islands(world_seed)

	var result: Array[Dictionary] = []
	for isl in islands:
		if isl.has_harbor:
			continue
		var best_theta: float = wrapf(isl.harbor_angle + PI, -PI, PI)
		var best_coast_r: float = -1.0
		const SAMPLES: int = 24
		for s in range(SAMPLES):
			var theta: float = -PI + (float(s) / float(SAMPLES)) * TAU
			var angle_from_harbor: float = absf(wrapf(theta - isl.harbor_angle, -PI, PI))
			# Keep fort on a headland well clear of the sheltered harbor entrance
			if angle_from_harbor < 1.15:
				continue
			var coast_r: float = Contracts.get_island_coast_radius(isl.index, theta, world_seed)
			if coast_r > best_coast_r:
				best_coast_r = coast_r
				best_theta = theta

		if best_coast_r <= 0.0:
			best_coast_r = Contracts.get_island_coast_radius(isl.index, best_theta, world_seed)

		var dir := Vector2(cos(best_theta), sin(best_theta))
		var fort_pos: Vector2 = isl.center + dir * maxf(20.0, best_coast_r - 12.0)
		result.append({
			"fort_id": isl.index + 1,
			"island_index": isl.index,
			"world_pos": fort_pos,
			"name": "Fort %s" % isl.name
		})
	return result


func get_water_depth(world_pos: Vector2) -> float:
	return Contracts.get_water_depth(world_pos, world_seed)


func is_land(world_pos: Vector2) -> bool:
	return Contracts.is_land(world_pos, world_seed)


func is_shallow(world_pos: Vector2) -> bool:
	return Contracts.is_shallow(world_pos, world_seed)


func check_hull_collision(world_pos: Vector2, hull_radius: float = 14.0) -> Dictionary:
	var center_depth: float = get_water_depth(world_pos)
	var min_depth: float = center_depth
	var deepest_pos: Vector2 = world_pos
	var collided: bool = center_depth <= Contracts.LAND_THRESHOLD

	for i in range(HULL_SAMPLE_ANGLES):
		var theta: float = float(i) * (TAU / float(HULL_SAMPLE_ANGLES))
		var sample_pos: Vector2 = world_pos + Vector2.from_angle(theta) * hull_radius
		var d: float = get_water_depth(sample_pos)
		if d < min_depth:
			min_depth = d
			deepest_pos = sample_pos
		if d <= Contracts.LAND_THRESHOLD:
			collided = true

	var shallow_flag: bool = (not collided) and (min_depth < Contracts.SHALLOW_THRESHOLD)
	var normal: Vector2 = Vector2.ZERO
	var penetration: float = 0.0

	if collided:
		normal = Contracts.get_coast_normal(deepest_pos, world_seed)
		if center_depth <= Contracts.LAND_THRESHOLD:
			penetration = (-center_depth * 140.0) + hull_radius * 0.5
		else:
			penetration = maxf(0.75, (-min_depth * 140.0) + 0.5)

	return {
		"collided": collided,
		"depth": min_depth,
		"normal": normal,
		"is_shallow": shallow_flag,
		"penetration": penetration
	}


func get_harbor_at(world_pos: Vector2) -> int:
	for isl in islands:
		if not isl.has_harbor or isl.harbor_radius <= 0.0:
			continue
		if world_pos.distance_to(isl.harbor_pos) <= isl.harbor_radius:
			return isl.index
	return -1


func get_nearest_safe_harbor(world_pos: Vector2) -> Contracts.IslandData:
	var best: Contracts.IslandData = null
	var best_dist_sq: float = INF
	for isl in islands:
		if not isl.has_harbor:
			continue
		var dist_sq: float = world_pos.distance_squared_to(isl.harbor_pos)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = isl
	return best


func get_island(index: int) -> Contracts.IslandData:
	if index >= 0 and index < islands.size():
		return islands[index]
	return null


func get_nearest_island(world_pos: Vector2) -> Contracts.IslandData:
	var best: Contracts.IslandData = null
	var best_dist_sq: float = INF
	for isl in islands:
		var dist_sq: float = world_pos.distance_squared_to(isl.center)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = isl
	return best


func find_open_water_near(target_pos: Vector2, min_depth: float = 0.20) -> Vector2:
	var max_bound: float = Contracts.WORLD_HALF_EXTENT - 40.0
	var clamped_target := Vector2(
		clampf(target_pos.x, -max_bound, max_bound),
		clampf(target_pos.y, -max_bound, max_bound)
	)
	if get_water_depth(clamped_target) >= min_depth:
		return clamped_target

	const ANGLE_STEPS: int = 16
	for ring in range(1, 32):
		var radius: float = float(ring) * 24.0
		for step in range(ANGLE_STEPS):
			var angle: float = float(step) * (TAU / float(ANGLE_STEPS))
			var candidate := clamped_target + Vector2.from_angle(angle) * radius
			if absf(candidate.x) > max_bound or absf(candidate.y) > max_bound:
				continue
			if get_water_depth(candidate) >= min_depth:
				return candidate

	return Vector2.ZERO

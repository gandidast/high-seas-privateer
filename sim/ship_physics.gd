class_name ShipPhysics
extends Node
## Snappy arcade sailing physics ("Privateers"-feel) with 6 ship classes,
## 3 sail states, forgiving upwind handling, rudder inertia, shallow-water damping,
## tangential coastline scraping, passive hull repair, burn DoT, and safe-harbor protection.

var ship_id: int = 1
var faction: int = Contracts.ShipFaction.PLAYER
var ship_name: String = "Schaluppe"
var hull_tier: int = Contracts.ShipClass.SLOOP

var world_pos: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var heading: float = 0.0
var speed: float = 0.0
var angular_velocity: float = 0.0

var sail_state: int = Contracts.SailState.ANCHORED
var hp: float = 120.0
var max_hp: float = 120.0
var is_sunk: bool = false

var stats: Contracts.ShipStats = Contracts.ShipStats.new()
var current_harbor_index: int = -1
var chain_slow_timer: float = 0.0
var chain_slow_strength: float = 0.0
var burn_timer: float = 0.0
var burn_dps: float = 0.0
var hull_radius: float = 14.0

var _burn_emit_accum: float = 0.0
var _burn_dmg_accum: float = 0.0


func setup(
	p_ship_id: int,
	p_pos: Vector2,
	p_heading: float = 0.0,
	p_faction: int = Contracts.ShipFaction.PLAYER,
	p_name: String = "Schaluppe"
) -> void:
	ship_id = p_ship_id
	world_pos = p_pos
	heading = wrapf(p_heading, -PI, PI)
	faction = p_faction
	ship_name = p_name
	hull_tier = clampi(stats.hull_tier, Contracts.ShipClass.SLOOP, Contracts.ShipClass.WAR_GALLEON)
	_sync_hull_radius_for_tier()
	velocity = Vector2.ZERO
	speed = 0.0
	angular_velocity = 0.0
	sail_state = Contracts.SailState.ANCHORED
	is_sunk = false
	chain_slow_timer = 0.0
	chain_slow_strength = 0.0
	burn_timer = 0.0
	burn_dps = 0.0
	_burn_emit_accum = 0.0
	_burn_dmg_accum = 0.0
	current_harbor_index = -1
	max_hp = maxf(10.0, stats.max_hp)
	hp = max_hp


func get_class_title() -> String:
	var spec: Dictionary = Contracts.get_ship_class_spec(hull_tier)
	return str(spec.get("name", "Schaluppe"))


func _sync_hull_radius_for_tier() -> void:
	var spec: Dictionary = Contracts.get_ship_class_spec(hull_tier)
	hull_radius = float(spec.get("hull_radius", 14.0))


func is_harbor_protected() -> bool:
	return faction == Contracts.ShipFaction.PLAYER and (current_harbor_index >= 0 or bool(get_meta("harbor_ui_open", false)))


func upgrade_ship_class(new_tier: int) -> void:
	var clamped_tier: int = clampi(new_tier, Contracts.ShipClass.SLOOP, Contracts.ShipClass.WAR_GALLEON)
	var old_spec: Dictionary = Contracts.get_ship_class_spec(hull_tier)
	var new_spec: Dictionary = Contracts.get_ship_class_spec(clamped_tier)
	var old_max: float = maxf(1.0, max_hp)
	var ratio: float = clampf(hp / old_max, 0.0, 1.0)

	hull_tier = clamped_tier
	_sync_hull_radius_for_tier()

	if stats == null:
		stats = Contracts.ShipStats.new()

	var old_base_hp: float = stats.base_max_hp
	var old_base_speed: float = stats.base_max_speed
	var old_base_armor: float = float(old_spec.get("armor", 0.0))
	var old_base_turn: float = float(old_spec.get("turn_speed", 1.75))
	stats.hull_tier = hull_tier

	stats.base_max_hp = float(new_spec.get("base_hp", 120.0))
	stats.base_max_speed = float(new_spec.get("base_speed", 95.0))
	stats.max_safe_weight = float(new_spec.get("max_weight", 45.0))
	stats.rudder_inertia = float(new_spec.get("inertia", 6.5))
	stats.acceleration = float(new_spec.get("accel", 48.0))

	var hp_delta: float = stats.base_max_hp - old_base_hp
	var speed_delta: float = stats.base_max_speed - old_base_speed
	var armor_delta: float = float(new_spec.get("armor", 0.0)) - old_base_armor
	var turn_delta: float = float(new_spec.get("turn_speed", 1.75)) - old_base_turn
	stats.max_hp = maxf(40.0, stats.max_hp + hp_delta)
	stats.max_speed = maxf(35.0, stats.max_speed + speed_delta)
	stats.armor = maxf(0.0, stats.armor + armor_delta)
	stats.turn_speed = maxf(0.85, stats.turn_speed + turn_delta)
	max_hp = stats.max_hp
	if not is_sunk:
		hp = clampf(ratio * max_hp, 1.0, max_hp)

	Contracts.bus().ship_class_upgraded.emit(ship_id, hull_tier, get_class_title())
	Contracts.bus().ship_state_updated.emit(ship_id, world_pos, heading, speed, sail_state, hp, max_hp)


func apply_stats(new_stats: Contracts.ShipStats) -> void:
	if new_stats == null:
		return
	var old_max: float = maxf(1.0, max_hp)
	var ratio: float = clampf(hp / old_max, 0.0, 1.0)
	stats = new_stats
	hull_tier = clampi(stats.hull_tier, Contracts.ShipClass.SLOOP, Contracts.ShipClass.WAR_GALLEON)
	_sync_hull_radius_for_tier()
	max_hp = maxf(10.0, stats.max_hp)
	if not is_sunk:
		hp = clampf(ratio * max_hp, 1.0, max_hp)


func change_sail_state(delta_step: int) -> void:
	set_sail_state(sail_state + delta_step)


func set_sail_state(new_state: int) -> void:
	sail_state = clampi(new_state, Contracts.SailState.ANCHORED, Contracts.SailState.FULL_SAIL)


func apply_chain_slow(duration: float, slow_strength: float = 0.4) -> void:
	if is_harbor_protected():
		return
	chain_slow_timer = maxf(chain_slow_timer, duration)
	chain_slow_strength = clampf(maxf(chain_slow_strength, slow_strength), 0.0, 0.85)


func apply_burn(duration: float, dps: float) -> void:
	if is_sunk or is_harbor_protected():
		return
	burn_timer = maxf(burn_timer, maxf(0.0, duration))
	burn_dps = maxf(burn_dps, maxf(0.0, dps))


func _clear_status_effects() -> void:
	burn_timer = 0.0
	burn_dps = 0.0
	_burn_emit_accum = 0.0
	_burn_dmg_accum = 0.0
	chain_slow_timer = 0.0
	chain_slow_strength = 0.0


func step_physics(delta: float, steer_input: float, world_map: WorldMap) -> void:
	if delta <= 0.0:
		return

	if is_sunk:
		velocity = velocity.move_toward(Vector2.ZERO, 60.0 * delta)
		speed = velocity.length()
		world_pos += velocity * delta
		Contracts.bus().ship_state_updated.emit(ship_id, world_pos, heading, speed, sail_state, hp, max_hp)
		return

	if is_harbor_protected():
		_clear_status_effects()

	# Passive hull repair (e.g. Carpenter Workshop)
	if stats != null and stats.passive_repair_rate > 0.0 and hp > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + stats.passive_repair_rate * delta)

	# Burn damage over time (Greek Fire / Alchemist Powder)
	if burn_timer > 0.0 and burn_dps > 0.0:
		var burn_dt: float = minf(delta, burn_timer)
		burn_timer = maxf(0.0, burn_timer - delta)
		var dmg: float = burn_dps * burn_dt
		hp = maxf(0.0, hp - dmg)
		_burn_dmg_accum += dmg
		_burn_emit_accum += delta
		if _burn_emit_accum >= 0.45 or burn_timer <= 0.0 or hp <= 0.0:
			if _burn_dmg_accum > 0.05:
				Contracts.bus().ship_damaged.emit(ship_id, _burn_dmg_accum, hp, max_hp, world_pos)
			_burn_emit_accum = 0.0
			_burn_dmg_accum = 0.0
		if burn_timer <= 0.0:
			burn_dps = 0.0
		if hp <= 0.0 and not is_sunk:
			is_sunk = true
			Contracts.bus().ship_sunk.emit(ship_id, world_pos, faction, -1)
			Contracts.bus().ship_state_updated.emit(ship_id, world_pos, heading, speed, sail_state, hp, max_hp)
			return

	if chain_slow_timer > 0.0:
		chain_slow_timer = maxf(0.0, chain_slow_timer - delta)
		if chain_slow_timer <= 0.0:
			chain_slow_strength = 0.0

	var clamped_steer: float = clampf(steer_input, -1.0, 1.0)

	var sail_thrust: float = 0.0
	var sail_turn_mult: float = 0.55
	match sail_state:
		Contracts.SailState.HALF_SAIL:
			sail_thrust = 0.58
			sail_turn_mult = 1.18
		Contracts.SailState.FULL_SAIL:
			sail_thrust = 1.00
			sail_turn_mult = 0.95
		_:
			sail_thrust = 0.0
			sail_turn_mult = 0.55

	var forward: Vector2 = Vector2.from_angle(heading)
	var wind_dir: Vector2 = Vector2.RIGHT
	var wind_str: float = 1.0
	if world_map != null:
		if world_map.wind_direction.length_squared() > 0.0001:
			wind_dir = world_map.wind_direction.normalized()
		wind_str = world_map.wind_strength

	var wind_dot: float = forward.dot(wind_dir)
	var min_upwind: float = maxf(0.42, stats.min_upwind_factor)
	# Smooth curve: forgiving minimum upwind speed, peaking at 115% on broad reach / downwind
	var reach_t: float = clampf((wind_dot + 1.0) / 1.45, 0.0, 1.0)
	var wind_angle_factor: float = lerpf(min_upwind, 1.15, reach_t)
	var wind_str_factor: float = clampf(0.88 + 0.12 * wind_str, 0.80, 1.12)

	var is_shallow_water: bool = world_map != null and world_map.is_shallow(world_pos)
	var shallow_mult: float = 0.80 if is_shallow_water else 1.0
	var chain_mult: float = (1.0 - chain_slow_strength) if chain_slow_timer > 0.0 else 1.0

	var effective_max_speed: float = stats.max_speed * wind_angle_factor * wind_str_factor * shallow_mult * chain_mult
	var target_speed: float = effective_max_speed * sail_thrust

	# Rudder inertia + responsive low-speed turning
	var speed_ratio: float = clampf(speed / maxf(1.0, stats.max_speed), 0.0, 1.2)
	var speed_turn_factor: float = clampf(0.62 + 0.38 * speed_ratio, 0.62, 1.08)
	var target_ang_vel: float = clamped_steer * stats.turn_speed * sail_turn_mult * speed_turn_factor * chain_mult
	angular_velocity = lerpf(angular_velocity, target_ang_vel, 1.0 - exp(-stats.rudder_inertia * delta))
	heading = wrapf(heading + angular_velocity * delta, -PI, PI)

	# Forward acceleration and keel grip
	var new_forward: Vector2 = Vector2.from_angle(heading)
	var new_right: Vector2 = Vector2(-new_forward.y, new_forward.x)
	var current_forward_speed: float = velocity.dot(new_forward)
	var accel_rate: float = stats.acceleration * (1.20 if target_speed > current_forward_speed else 1.45)
	if sail_state == Contracts.SailState.ANCHORED:
		accel_rate = maxf(accel_rate, 68.0)

	var next_forward_speed: float = move_toward(current_forward_speed, target_speed, accel_rate * delta)
	var lateral_speed: float = velocity.dot(new_right) * exp(-7.5 * delta)
	velocity = new_forward * next_forward_speed + new_right * lateral_speed
	world_pos += velocity * delta

	# Keep within navigable world extent
	var max_bound: float = Contracts.WORLD_HALF_EXTENT - 24.0
	if world_pos.x < -max_bound:
		world_pos.x = -max_bound
		if velocity.x < 0.0:
			velocity.x = 0.0
	elif world_pos.x > max_bound:
		world_pos.x = max_bound
		if velocity.x > 0.0:
			velocity.x = 0.0
	if world_pos.y < -max_bound:
		world_pos.y = -max_bound
		if velocity.y < 0.0:
			velocity.y = 0.0
	elif world_pos.y > max_bound:
		world_pos.y = max_bound
		if velocity.y > 0.0:
			velocity.y = 0.0

	# Coastline collision & tangential scraping
	if world_map != null:
		var col: Dictionary = world_map.check_hull_collision(world_pos, hull_radius)
		if bool(col.get("collided", false)):
			var normal: Vector2 = col.get("normal", Vector2.UP)
			if normal.length_squared() < 0.0001:
				normal = Vector2.UP
			else:
				normal = normal.normalized()
			var penetration: float = float(col.get("penetration", 1.0))
			world_pos += normal * (penetration + 0.5)

			var inward_dot: float = velocity.dot(normal)
			var impact_speed: float = maxf(0.0, -inward_dot)
			if inward_dot < 0.0:
				velocity -= normal * inward_dot
			velocity *= 0.85
			Contracts.bus().ship_coast_scraped.emit(ship_id, world_pos, normal, impact_speed)

	speed = velocity.length()

	# Safe harbor zone detection
	if world_map != null:
		var new_harbor: int = world_map.get_harbor_at(world_pos)
		if new_harbor != current_harbor_index:
			if current_harbor_index >= 0:
				Contracts.bus().harbor_exited.emit(ship_id, current_harbor_index)
			current_harbor_index = new_harbor
			if current_harbor_index >= 0:
				var isl: Contracts.IslandData = world_map.get_island(current_harbor_index)
				var isl_name: String = isl.name if isl != null else ""
				Contracts.bus().harbor_entered.emit(ship_id, current_harbor_index, isl_name)
		if is_harbor_protected():
			_clear_status_effects()

	Contracts.bus().ship_state_updated.emit(ship_id, world_pos, heading, speed, sail_state, hp, max_hp)


func to_sync_dict() -> Dictionary:
	return {
		"ship_id": ship_id,
		"faction": faction,
		"ship_name": ship_name,
		"hull_tier": hull_tier,
		"x": world_pos.x,
		"y": world_pos.y,
		"vx": velocity.x,
		"vy": velocity.y,
		"heading": heading,
		"speed": speed,
		"angular_velocity": angular_velocity,
		"sail_state": sail_state,
		"hp": hp,
		"max_hp": max_hp,
		"is_sunk": is_sunk,
		"current_harbor_index": current_harbor_index,
		"chain_slow_timer": chain_slow_timer,
		"burn_timer": burn_timer
	}


func apply_sync_dict(d: Dictionary) -> void:
	ship_id = int(d.get("ship_id", ship_id))
	faction = int(d.get("faction", faction))
	ship_name = str(d.get("ship_name", ship_name))
	hull_tier = clampi(int(d.get("hull_tier", hull_tier)), Contracts.ShipClass.SLOOP, Contracts.ShipClass.WAR_GALLEON)
	_sync_hull_radius_for_tier()
	world_pos = Vector2(float(d.get("x", world_pos.x)), float(d.get("y", world_pos.y)))
	velocity = Vector2(float(d.get("vx", velocity.x)), float(d.get("vy", velocity.y)))
	heading = float(d.get("heading", heading))
	speed = float(d.get("speed", velocity.length()))
	angular_velocity = float(d.get("angular_velocity", angular_velocity))
	sail_state = int(d.get("sail_state", sail_state))
	hp = float(d.get("hp", hp))
	max_hp = float(d.get("max_hp", max_hp))
	is_sunk = bool(d.get("is_sunk", is_sunk))
	current_harbor_index = int(d.get("current_harbor_index", current_harbor_index))
	chain_slow_timer = float(d.get("chain_slow_timer", chain_slow_timer))
	burn_timer = float(d.get("burn_timer", burn_timer))

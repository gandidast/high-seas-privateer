class_name WorldEntitiesRenderer
extends RefCounted
## Manages and draws Coastal Forts and Giant Kraken sea monsters with
## camera-viewport culling and zero per-frame tentacle allocations.

const OUTLINE_COLOR := Color(0.094, 0.078, 0.145, 1.0) # #181425
const FORT_BAR_BG := Color(0.18, 0.11, 0.13, 0.94)
const FORT_BAR_FILL := Color(0.92, 0.30, 0.24)
const KRAKEN_BAR_BG := Color(0.18, 0.10, 0.16, 0.94)
const KRAKEN_BAR_FILL := Color(0.84, 0.24, 0.56)
const FIRE_FLASH_OUTER := Color(1.0, 0.62, 0.16, 0.95)
const FIRE_FLASH_INNER := Color(1.0, 0.96, 0.72, 1.0)
const KRAKEN_FOAM_COL := Color(0.45, 0.94, 0.86, 0.58)
const TENTACLE_COUNT: int = 8

var forts: Dictionary = {}        # fort_id -> { pos, island_index, hp, max_hp, aim_angle, hit_flash, fire_flash }
var sea_monsters: Dictionary = {} # monster_id -> { pos, hp, max_hp, phase, hit_flash, foam_timer }
var _time_accum: float = 0.0

# Preallocated scratch buffers for Kraken tentacles (avoids per-frame array/dict churn)
var _tent_pos: Array[Vector2] = []
var _tent_frame: PackedInt32Array = PackedInt32Array()
var _tent_flip: PackedFloat32Array = PackedFloat32Array()
var _tent_tilt: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	_tent_pos.resize(TENTACLE_COUNT)
	_tent_frame.resize(TENTACLE_COUNT)
	_tent_flip.resize(TENTACLE_COUNT)
	_tent_tilt.resize(TENTACLE_COUNT)


func has_active_entities() -> bool:
	return not forts.is_empty() or not sea_monsters.is_empty()


func has_visible_entities(cam_rect: Rect2, has_cam: bool) -> bool:
	if not has_cam:
		return has_active_entities()
	var fort_rect: Rect2 = cam_rect.grow(56.0)
	for fid in forts.keys():
		if fort_rect.has_point(forts[fid]["pos"] as Vector2):
			return true
	var kraken_rect: Rect2 = cam_rect.grow(84.0)
	for mid in sea_monsters.keys():
		if kraken_rect.has_point(sea_monsters[mid]["pos"] as Vector2):
			return true
	return false


func on_fort_spawned(fort_id: int, world_pos: Vector2, island_index: int, max_hp: float) -> void:
	forts[fort_id] = {
		"pos": world_pos,
		"island_index": island_index,
		"hp": max_hp,
		"max_hp": maxf(1.0, max_hp),
		"aim_angle": 0.0,
		"hit_flash": 0.0,
		"fire_flash": 0.0
	}


func on_fort_damaged(fort_id: int, hp: float, max_hp: float, world_pos: Vector2) -> void:
	if not forts.has(fort_id):
		on_fort_spawned(fort_id, world_pos, -1, max_hp)
	var f: Dictionary = forts[fort_id]
	f["hp"] = hp
	f["max_hp"] = maxf(1.0, max_hp)
	f["pos"] = world_pos
	f["hit_flash"] = 0.14


func on_fort_destroyed(fort_id: int) -> void:
	forts.erase(fort_id)


func notify_cannonball_origin(origin: Vector2, vel: Vector2) -> void:
	for fid in forts.keys():
		var fort: Dictionary = forts[fid]
		if (fort["pos"] as Vector2).distance_squared_to(origin) < 28.0 * 28.0:
			fort["aim_angle"] = vel.angle()
			fort["fire_flash"] = 0.18


func on_sea_monster_spawned(monster_id: int, world_pos: Vector2, max_hp: float) -> void:
	sea_monsters[monster_id] = {
		"pos": world_pos,
		"hp": max_hp,
		"max_hp": maxf(1.0, max_hp),
		"phase": 0,
		"hit_flash": 0.0,
		"foam_timer": 0.0
	}


func on_sea_monster_updated(monster_id: int, world_pos: Vector2, hp: float, max_hp: float, phase: int) -> bool:
	if not sea_monsters.has(monster_id):
		on_sea_monster_spawned(monster_id, world_pos, max_hp)
	var m: Dictionary = sea_monsters[monster_id]
	var prev_hp: float = float(m["hp"])
	m["pos"] = world_pos
	m["hp"] = hp
	m["max_hp"] = maxf(1.0, max_hp)
	m["phase"] = phase
	if hp < prev_hp - 0.5:
		m["hit_flash"] = 0.14
		return true
	return false


func on_sea_monster_defeated(monster_id: int) -> void:
	sea_monsters.erase(monster_id)


func update_entities(delta: float, ship_positions: Dictionary, rings_out: Array[Dictionary], cam_rect: Rect2, has_cam: bool) -> void:
	_time_accum += delta

	for fid in forts.keys():
		var fort: Dictionary = forts[fid]
		if float(fort["hit_flash"]) > 0.0:
			fort["hit_flash"] = maxf(0.0, float(fort["hit_flash"]) - delta)
		if float(fort["fire_flash"]) > 0.0:
			fort["fire_flash"] = maxf(0.0, float(fort["fire_flash"]) - delta)

		var fpos: Vector2 = fort["pos"]
		if has_cam and not cam_rect.grow(160.0).has_point(fpos):
			continue

		var nearest_dist_sq: float = 340.0 * 340.0
		var has_target := false
		var target_ang: float = float(fort["aim_angle"])
		for sid in ship_positions.keys():
			var sp: Vector2 = ship_positions[sid]
			var d2: float = fpos.distance_squared_to(sp)
			if d2 < nearest_dist_sq:
				nearest_dist_sq = d2
				target_ang = (sp - fpos).angle()
				has_target = true
		if has_target:
			fort["aim_angle"] = lerp_angle(float(fort["aim_angle"]), target_ang, minf(1.0, delta * 3.0))
		else:
			fort["aim_angle"] = wrapf(float(fort["aim_angle"]) + delta * 0.35, -PI, PI)

	for mid in sea_monsters.keys():
		var m: Dictionary = sea_monsters[mid]
		if float(m["hit_flash"]) > 0.0:
			m["hit_flash"] = maxf(0.0, float(m["hit_flash"]) - delta)
		m["foam_timer"] = float(m["foam_timer"]) + delta
		if float(m["foam_timer"]) >= 0.42:
			m["foam_timer"] = 0.0
			var mpos: Vector2 = m["pos"]
			if not has_cam or cam_rect.grow(96.0).has_point(mpos):
				rings_out.append({
					"pos": mpos,
					"r_start": 10.0,
					"r_end": 28.0 + float(int(m["phase"])) * 4.0,
					"age": 0.0,
					"max_age": 0.85,
					"color": KRAKEN_FOAM_COL
				})


func draw_entities(canvas: CanvasItem, cam_rect: Rect2, has_cam: bool) -> void:
	if not forts.is_empty():
		_draw_forts(canvas, cam_rect, has_cam)
	if not sea_monsters.is_empty():
		_draw_sea_monsters(canvas, cam_rect, has_cam)


func _draw_forts(canvas: CanvasItem, cam_rect: Rect2, has_cam: bool) -> void:
	var cull_rect: Rect2 = cam_rect.grow(56.0)
	for fid in forts.keys():
		var fort: Dictionary = forts[fid]
		var fpos: Vector2 = fort["pos"]
		if has_cam and not cull_rect.has_point(fpos):
			continue

		var aim_ang: float = float(fort["aim_angle"])
		var hp: float = float(fort["hp"])
		var max_hp: float = maxf(1.0, float(fort["max_hp"]))
		var hit_flash: bool = float(fort["hit_flash"]) > 0.0
		var fire_flash: bool = float(fort["fire_flash"]) > 0.0

		var fort_tex: ImageTexture = ProceduralShipBaker.bake_fort_texture(hit_flash)
		canvas.draw_set_transform(fpos.round(), aim_ang, Vector2.ONE)
		canvas.draw_texture(fort_tex, Vector2(-24.0, -24.0))
		if fire_flash:
			canvas.draw_rect(Rect2(Vector2(19.0, -3.5), Vector2(7.0, 7.0)), FIRE_FLASH_OUTER)
			canvas.draw_rect(Rect2(Vector2(20.5, -2.0), Vector2(4.0, 4.0)), FIRE_FLASH_INNER)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		var bar_w: float = 34.0
		var bar_h: float = 4.0
		var bar_pos: Vector2 = (fpos + Vector2(-bar_w * 0.5, -29.0)).round()
		var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
		canvas.draw_rect(Rect2(bar_pos - Vector2.ONE, Vector2(bar_w + 2.0, bar_h + 2.0)), OUTLINE_COLOR)
		canvas.draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), FORT_BAR_BG)
		canvas.draw_rect(Rect2(bar_pos, Vector2(floor(bar_w * ratio), bar_h)), FORT_BAR_FILL)


func _draw_sea_monsters(canvas: CanvasItem, cam_rect: Rect2, has_cam: bool) -> void:
	var cull_rect: Rect2 = cam_rect.grow(84.0)
	for mid in sea_monsters.keys():
		var m: Dictionary = sea_monsters[mid]
		var mpos: Vector2 = m["pos"]
		if has_cam and not cull_rect.has_point(mpos):
			continue

		var hp: float = float(m["hp"])
		var max_hp: float = maxf(1.0, float(m["max_hp"]))
		var phase: int = int(m["phase"])
		var hit_flash: bool = float(m["hit_flash"]) > 0.0

		var anim_rate: float = 4.2 + float(phase) * 1.4
		var frame_base: int = int(floor(_time_accum * anim_rate))
		var orbit_speed: float = 0.20 + float(phase) * 0.08
		var tilt_speed: float = 2.5 + float(phase) * 0.9

		for t_i in range(TENTACLE_COUNT):
			var base_ang: float = (float(t_i) / float(TENTACLE_COUNT)) * TAU + _time_accum * orbit_speed
			var cos_a: float = cos(base_ang)
			var rx: float = 25.0 + sin(_time_accum * 2.1 + float(t_i) * 1.3) * 2.5
			var ry: float = 14.5 + cos(_time_accum * 1.9 + float(t_i) * 1.1) * 2.0
			_tent_pos[t_i] = (mpos + Vector2(cos_a * rx, sin(base_ang) * ry + 5.0)).round()
			_tent_frame[t_i] = (frame_base + t_i) % 3
			_tent_flip[t_i] = -1.0 if cos_a < 0.0 else 1.0
			_tent_tilt[t_i] = sin(_time_accum * tilt_speed + float(t_i) * 1.4) * 0.16

		# 1. Back tentacles behind Kraken head
		var split_y: float = mpos.y + 4.0
		for t_i in range(TENTACLE_COUNT):
			if _tent_pos[t_i].y < split_y:
				var t_tex: ImageTexture = ProceduralShipBaker.bake_kraken_tentacle_texture(_tent_frame[t_i], hit_flash)
				canvas.draw_set_transform(_tent_pos[t_i], _tent_tilt[t_i], Vector2(_tent_flip[t_i], 1.0))
				canvas.draw_texture(t_tex, Vector2(-16.0, -26.0))

		# 2. Central 64x64 pixel-art Kraken head / mantle emerging from foam vortex
		var bob_y: float = sin(_time_accum * 2.3 + float(int(mid) % 7)) * 2.0 - 4.0
		var body_tilt: float = sin(_time_accum * 1.4) * 0.055
		var body_tex: ImageTexture = ProceduralShipBaker.bake_kraken_body_texture(hit_flash)
		canvas.draw_set_transform((mpos + Vector2(0.0, bob_y)).round(), body_tilt, Vector2.ONE)
		canvas.draw_texture(body_tex, Vector2(-32.0, -32.0))

		# 3. Front tentacles in front of Kraken waterline
		for t_i in range(TENTACLE_COUNT):
			if _tent_pos[t_i].y >= split_y:
				var t_tex: ImageTexture = ProceduralShipBaker.bake_kraken_tentacle_texture(_tent_frame[t_i], hit_flash)
				canvas.draw_set_transform(_tent_pos[t_i], _tent_tilt[t_i], Vector2(_tent_flip[t_i], 1.0))
				canvas.draw_texture(t_tex, Vector2(-16.0, -26.0))

		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# 4. Crisp Kraken HP bar
		var bar_w: float = 46.0
		var bar_h: float = 5.0
		var bar_pos: Vector2 = (mpos + Vector2(-bar_w * 0.5, -39.0)).round()
		var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
		canvas.draw_rect(Rect2(bar_pos - Vector2.ONE, Vector2(bar_w + 2.0, bar_h + 2.0)), OUTLINE_COLOR)
		canvas.draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), KRAKEN_BAR_BG)
		canvas.draw_rect(Rect2(bar_pos, Vector2(floor(bar_w * ratio), bar_h)), KRAKEN_BAR_FILL)

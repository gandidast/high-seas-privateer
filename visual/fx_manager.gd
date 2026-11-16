class_name FxManager
extends Node2D
## Handles 2D pixel-art combat FX (cannonballs, Greek Fire, Harpoon Ballista ropes,
## water splashes, wood splinters, powder crits, sinking debris), floating loot crates,
## broadside targeting cone, and lightning bolts, delegating Forts & Kraken to
## WorldEntitiesRenderer.

const OUTLINE_COLOR := Color(0.094, 0.078, 0.145, 1.0) # #181425
const MAX_PARTICLES: int = 360
const P2 := Vector2(2.0, 2.0)
const P3 := Vector2(3.0, 3.0)
const P4 := Vector2(4.0, 4.0)
const P5 := Vector2(5.0, 5.0)
const P6 := Vector2(6.0, 6.0)
const COL_SHADOW := Color(0.06, 0.10, 0.20, 0.52)
const COL_FIRE_OUTER := Color(1.0, 0.42, 0.12)
const COL_FIRE_INNER := Color(1.0, 0.94, 0.50)
const COL_BALL_BODY := Color(0.26, 0.28, 0.34)
const COL_BALL_HI := Color(0.84, 0.88, 0.94)

var _time_accum: float = 0.0
var _hitstop_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _entities_renderer := WorldEntitiesRenderer.new()
var _projectiles: Array[Dictionary] = []
var _particles: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _loot_crates: Dictionary = {} # drop_id -> { "sprite": Sprite2D, "pos": Vector2, "salvage": bool }
var _ship_positions: Dictionary = {} # ship_id -> Vector2
var _burning_ships: Dictionary = {} # ship_id -> { "timer": float, "emit_accum": float }
var _harpoon_tethers: Array[Dictionary] = []
var _lightning_bolts: Array[Dictionary] = []

var _aim_cone_active: bool = false
var _aim_origin: Vector2 = Vector2.ZERO
var _aim_dir: Vector2 = Vector2.RIGHT
var _aim_range: float = 240.0
var _aim_half_angle: float = 0.35
var _cone_poly := PackedVector2Array()
var _bow_cone_active: bool = false
var _bow_origin: Vector2 = Vector2.ZERO
var _bow_dir: Vector2 = Vector2.RIGHT
var _bow_range: float = 300.0
var _bow_half_angle: float = 0.14
var _bow_poly := PackedVector2Array()
var _cam_rect: Rect2 = Rect2()
var _has_cam_rect: bool = false
var _had_visible_fx: bool = false

func _ready() -> void:
	_rng.randomize()
	z_index = 25
	_connect_signals()

func _connect_signals() -> void:
	var bus: Contracts = Contracts.bus()
	if bus == null:
		return
	for pair in [
		[bus.broadside_fired, _on_broadside_fired], [bus.cannonball_spawned, _on_cannonball_spawned],
		[bus.cannonball_impact, _on_cannonball_impact], [bus.ship_state_updated, _on_ship_state_updated],
		[bus.ship_damaged, _on_ship_damaged], [bus.ship_sunk, _on_ship_sunk],
		[bus.loot_spawned, _on_loot_spawned], [bus.loot_collected, _on_loot_collected],
		[bus.sea_monster_spawned, _on_sea_monster_spawned], [bus.sea_monster_updated, _on_sea_monster_updated],
		[bus.sea_monster_defeated, _on_sea_monster_defeated], [bus.fort_spawned, _on_fort_spawned],
		[bus.fort_damaged, _on_fort_damaged], [bus.fort_destroyed, _on_fort_destroyed],
		[bus.lightning_flash, _on_lightning_flash]
	]:
		if not (pair[0] as Signal).is_connected(pair[1] as Callable):
			(pair[0] as Signal).connect(pair[1] as Callable)

func set_broadside_aim_cone(origin: Vector2, dir: Vector2, range_px: float, half_angle_rad: float, active: bool) -> void:
	_aim_cone_active = active
	_aim_origin = origin
	_aim_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	_aim_range = maxf(24.0, range_px)
	_aim_half_angle = clampf(half_angle_rad, 0.05, 1.45)
	queue_redraw()


func set_bow_aim_cone(origin: Vector2, dir: Vector2, range_px: float, half_angle_rad: float, active: bool) -> void:
	_bow_cone_active = active
	_bow_origin = origin
	_bow_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	_bow_range = maxf(24.0, range_px)
	_bow_half_angle = clampf(half_angle_rad, 0.03, 0.85)
	queue_redraw()

func _refresh_camera_rect() -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_2d() if vp != null else null
	if vp == null or cam == null:
		_has_cam_rect = false
		return
	var vp_size: Vector2 = vp.get_visible_rect().size
	if vp is SubViewport and (vp as SubViewport).size.x > 0 and (vp as SubViewport).size.y > 0:
		vp_size = Vector2((vp as SubViewport).size)
	var zoom_safe := Vector2(maxf(0.25, cam.zoom.x), maxf(0.25, cam.zoom.y))
	var world_size: Vector2 = vp_size / zoom_safe
	_cam_rect = Rect2(cam.get_screen_center_position() - world_size * 0.5, world_size)
	_has_cam_rect = true

func _is_near_camera(world_pos: Vector2, margin: float) -> bool:
	return (not _has_cam_rect) or _cam_rect.grow(margin).has_point(world_pos)

func _emit_particle(pos: Vector2, vel: Vector2, z: float, vz: float, gravity: float, max_age: float, size: float, col: Color, outline: bool) -> void:
	if _particles.size() < MAX_PARTICLES:
		_particles.append({ "pos": pos, "vel": vel, "z": z, "vz": vz, "gravity": gravity, "age": 0.0, "max_age": max_age, "size": size, "color": col, "outline": outline })

func _emit_ring(pos: Vector2, r_start: float, r_end: float, max_age: float, col: Color) -> void:
	_rings.append({ "pos": pos, "r_start": r_start, "r_end": r_end, "age": 0.0, "max_age": max_age, "color": col })

func _emit_burst(pos: Vector2, count: int, jitter: float, spd_min: float, spd_max: float, z: float, vz_min: float, vz_max: float, grav: float, age_min: float, age_max: float, sz_even: float, sz_odd: float, col_even: Color, col_odd: Color, outline: bool, even_mod: int = 2) -> void:
	for i in range(count):
		if _particles.size() >= MAX_PARTICLES:
			return
		var ang: float = _rng.randf_range(0.0, TAU)
		var p: Vector2 = pos + Vector2(_rng.randf_range(-jitter, jitter), _rng.randf_range(-jitter, jitter)) if jitter > 0.0 else pos
		var is_primary: bool = (i % even_mod == 0)
		_emit_particle(
			p, Vector2(cos(ang), sin(ang)) * _rng.randf_range(spd_min, spd_max), z,
			_rng.randf_range(vz_min, vz_max), grav, _rng.randf_range(age_min, age_max),
			sz_even if is_primary else sz_odd, col_even if is_primary else col_odd, outline
		)

func _process(delta: float) -> void:
	_time_accum += delta
	_refresh_camera_rect()
	if _hitstop_timer > 0.0:
		_hitstop_timer = maxf(0.0, _hitstop_timer - delta)
		_update_loot_bobbing()
		queue_redraw()
		return

	_update_projectiles(delta)
	_update_particles(delta)
	_tick_aged(_rings, delta)
	var has_visible_loot: bool = _update_loot_bobbing()
	_entities_renderer.update_entities(delta, _ship_positions, _rings, _cam_rect, _has_cam_rect)
	_update_burning_ships(delta)
	_update_harpoon_tethers(delta)
	_tick_aged(_lightning_bolts, delta)

	var has_fx: bool = (
		_aim_cone_active or _bow_cone_active or not _projectiles.is_empty() or not _particles.is_empty()
		or not _rings.is_empty() or not _harpoon_tethers.is_empty() or not _lightning_bolts.is_empty()
		or has_visible_loot or _entities_renderer.has_visible_entities(_cam_rect, _has_cam_rect)
	)
	if has_fx or _had_visible_fx:
		_had_visible_fx = has_fx
		queue_redraw()

func _tick_aged(arr: Array[Dictionary], delta: float) -> void:
	var idx: int = arr.size() - 1
	while idx >= 0:
		var new_age: float = float(arr[idx]["age"]) + delta
		if new_age >= float(arr[idx]["max_age"]):
			arr.remove_at(idx)
		else:
			arr[idx]["age"] = new_age
		idx -= 1

func _update_projectiles(delta: float) -> void:
	var smoke_rect: Rect2 = _cam_rect.grow(140.0)
	var idx: int = _projectiles.size() - 1
	while idx >= 0:
		var proj: Dictionary = _projectiles[idx]
		var vel: Vector2 = proj["vel"]
		var new_pos: Vector2 = (proj["pos"] as Vector2) + vel * delta
		var new_traveled: float = float(proj["traveled"]) + vel.length() * delta
		var new_age: float = float(proj["age"]) + delta
		proj["pos"] = new_pos
		proj["traveled"] = new_traveled
		proj["age"] = new_age
		var max_r: float = maxf(1.0, float(proj["max_range"]))
		var smoke_accum: float = float(proj["smoke_accum"]) + delta
		if smoke_accum >= 0.032:
			smoke_accum = 0.0
			if not _has_cam_rect or smoke_rect.has_point(new_pos):
				var arc_y: float = -sin(clampf(new_traveled / max_r, 0.0, 1.0) * PI) * float(proj["arc_height"])
				var is_fire: bool = bool(proj["is_fire"])
				_emit_particle(new_pos + Vector2(0.0, arc_y), Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-16.0, -4.0)), 0.0, 0.0, 0.0, 0.34 if is_fire else 0.28, 3.0 if is_fire else 2.0, Color(1.0, 0.56, 0.14, 0.92) if is_fire else Color(0.92, 0.92, 0.94, 0.72), false)
		proj["smoke_accum"] = smoke_accum
		if new_traveled >= max_r + 12.0 or new_age > 3.5:
			_projectiles.remove_at(idx)
		idx -= 1

func _update_particles(delta: float) -> void:
	var drag: float = maxf(0.0, 1.0 - delta * 2.2)
	var idx: int = _particles.size() - 1
	while idx >= 0:
		var pt: Dictionary = _particles[idx]
		var new_age: float = float(pt["age"]) + delta
		if new_age >= float(pt["max_age"]):
			_particles.remove_at(idx)
		else:
			pt["age"] = new_age
			var vel: Vector2 = pt["vel"]
			pt["pos"] = (pt["pos"] as Vector2) + vel * delta
			pt["vel"] = vel * drag
			var vz: float = float(pt["vz"]) - float(pt["gravity"]) * delta
			var z: float = float(pt["z"]) + vz * delta
			pt["vz"] = 0.0 if z < 0.0 else vz
			pt["z"] = maxf(0.0, z)
		idx -= 1

func _update_loot_bobbing() -> bool:
	var any_visible: bool = false
	var cull_rect: Rect2 = _cam_rect.grow(64.0)
	for drop_id in _loot_crates.keys():
		var entry: Dictionary = _loot_crates[drop_id]
		var spr: Sprite2D = entry["sprite"]
		if not is_instance_valid(spr):
			continue
		var base_pos: Vector2 = entry["pos"]
		var in_view: bool = (not _has_cam_rect) or cull_rect.has_point(base_pos)
		if spr.visible != in_view:
			spr.visible = in_view
		if not in_view:
			continue
		any_visible = true
		spr.position = (base_pos + Vector2(0.0, sin(_time_accum * 2.6 + float(int(drop_id) % 17)) * 1.5)).round()
		if bool(entry["salvage"]):
			var pulse: float = 0.90 + 0.15 * sin(_time_accum * 4.2)
			spr.modulate = Color(pulse, 1.0, pulse, 1.0)
	return any_visible

func _update_burning_ships(delta: float) -> void:
	var to_erase: Array = []
	for sid in _burning_ships.keys():
		var b: Dictionary = _burning_ships[sid]
		b["timer"] = float(b["timer"]) - delta
		if float(b["timer"]) <= 0.0 or not _ship_positions.has(sid):
			to_erase.append(sid)
			continue
		b["emit_accum"] = float(b["emit_accum"]) + delta
		if float(b["emit_accum"]) >= 0.06:
			b["emit_accum"] = 0.0
			var spos: Vector2 = _ship_positions[sid]
			if _is_near_camera(spos, 120.0):
				var flame_col := Color(1.0, 0.54, 0.14, 0.95) if _rng.randf() < 0.6 else Color(1.0, 0.88, 0.30, 0.95)
				_emit_particle(spos + Vector2(_rng.randf_range(-9.0, 9.0), _rng.randf_range(-5.0, 5.0)), Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-24.0, -12.0)), 6.0, _rng.randf_range(8.0, 18.0), 0.0, _rng.randf_range(0.28, 0.48), _rng.randf_range(2.0, 4.0), flame_col, true)
	for sid in to_erase:
		_burning_ships.erase(sid)

func _update_harpoon_tethers(delta: float) -> void:
	var idx: int = _harpoon_tethers.size() - 1
	while idx >= 0:
		var t: Dictionary = _harpoon_tethers[idx]
		var new_age: float = float(t["age"]) + delta
		if new_age >= float(t["max_age"]):
			_harpoon_tethers.remove_at(idx)
		else:
			t["age"] = new_age
			var s_id: int = int(t["start_ship_id"])
			var e_id: int = int(t["end_ship_id"])
			if s_id >= 0 and _ship_positions.has(s_id):
				t["start_pos"] = _ship_positions[s_id]
			if e_id >= 0 and _ship_positions.has(e_id):
				t["end_pos"] = _ship_positions[e_id]
		idx -= 1

func _draw() -> void:
	if _aim_cone_active:
		_draw_broadside_cone()
	if _bow_cone_active:
		_draw_bow_cone()
	_draw_rings_and_loot()
	_entities_renderer.draw_entities(self, _cam_rect, _has_cam_rect)
	_draw_tethers_and_projectiles()
	_draw_particles_and_bolts()

func _draw_rings_and_loot() -> void:
	for ring in _rings:
		var t: float = clampf(float(ring["age"]) / float(ring["max_age"]), 0.0, 1.0)
		var r: float = lerpf(float(ring["r_start"]), float(ring["r_end"]), t)
		var center: Vector2 = ring["pos"]
		if _has_cam_rect and not _cam_rect.grow(r + 8.0).has_point(center):
			continue
		var col: Color = ring["color"]
		col.a *= (1.0 - t)
		var steps: int = int(clampf(r * 1.4, 12.0, 36.0))
		for i in range(0, steps, 2 if t > 0.35 else 1):
			var ang: float = (float(i) / float(steps)) * TAU
			draw_rect(Rect2((center + Vector2(cos(ang), sin(ang) * 0.72) * r).round(), P2), col)

	var loot_rect: Rect2 = _cam_rect.grow(24.0)
	var loot_rot: float = _time_accum * 0.5
	for drop_id in _loot_crates.keys():
		var entry: Dictionary = _loot_crates[drop_id]
		var base_pos: Vector2 = entry["pos"]
		if _has_cam_rect and not loot_rect.has_point(base_pos):
			continue
		var pulse_r: float = 11.0 + sin(_time_accum * 2.4 + float(int(drop_id))) * 2.0
		var ring_col := Color(0.35, 0.95, 0.78, 0.55) if bool(entry["salvage"]) else Color(0.94, 0.98, 1.0, 0.32)
		for i in range(0, 12, 2):
			var ang: float = (float(i) / 12.0) * TAU + loot_rot
			draw_rect(Rect2((base_pos + Vector2(cos(ang), sin(ang) * 0.75) * pulse_r).round(), P2), ring_col)

func _draw_tethers_and_projectiles() -> void:
	var tether_rect: Rect2 = _cam_rect.grow(32.0)
	for tether in _harpoon_tethers:
		var p0: Vector2 = (tether["start_pos"] as Vector2).round()
		var p1: Vector2 = (tether["end_pos"] as Vector2).round()
		if _has_cam_rect and not tether_rect.has_point(p0) and not tether_rect.has_point(p1):
			continue
		var alpha: float = 1.0 - clampf(float(tether["age"]) / float(tether["max_age"]), 0.0, 1.0)
		draw_line(p0, p1, Color(0.10, 0.08, 0.14, alpha * 0.85), 3.0, false)
		draw_line(p0, p1, Color(0.90, 0.82, 0.60, alpha), 1.5, false)

	var proj_rect: Rect2 = _cam_rect.grow(48.0)
	for proj in _projectiles:
		var ground_pos: Vector2 = proj["pos"]
		if _has_cam_rect and not proj_rect.has_point(ground_pos):
			continue
		var sin_p: float = sin(clampf(float(proj["traveled"]) / maxf(1.0, float(proj["max_range"])), 0.0, 1.0) * PI)
		var ball_pos: Vector2 = (ground_pos + Vector2(0.0, -sin_p * float(proj["arc_height"]))).round()
		var shadow_w: float = lerpf(5.0, 3.0, sin_p)
		draw_rect(Rect2(ground_pos.round() - Vector2(shadow_w * 0.5, 1.0), Vector2(shadow_w, 2.0)), COL_SHADOW)
		if bool(proj["is_harpoon"]):
			draw_line((proj["origin"] as Vector2).round(), ball_pos, Color(0.86, 0.78, 0.56, 0.85), 1.0, false)
			var dir_v: Vector2 = (proj["vel"] as Vector2).normalized()
			var tail: Vector2 = (ball_pos - dir_v * 6.0).round()
			var tip: Vector2 = (ball_pos + dir_v * 5.0).round()
			draw_line(tail, tip, OUTLINE_COLOR, 3.0, false)
			draw_line(tail, tip, Color(0.82, 0.88, 0.96, 1.0), 1.5, false)
		elif bool(proj["is_fire"]):
			draw_rect(Rect2(ball_pos - P3, P6), OUTLINE_COLOR)
			draw_rect(Rect2(ball_pos - P2, P4), COL_FIRE_OUTER)
			draw_rect(Rect2(ball_pos - Vector2.ONE, P2), COL_FIRE_INNER)
		elif bool(proj["is_chain"]):
			var perp: Vector2 = (proj["vel"] as Vector2).normalized().orthogonal() * 3.0
			var b1: Vector2 = (ball_pos + perp).round()
			var b2: Vector2 = (ball_pos - perp).round()
			draw_line(b1, b2, Color(0.75, 0.80, 0.88, 1.0), 1.0, false)
			for bp in [b1, b2]:
				draw_rect(Rect2(bp - P2, P4), OUTLINE_COLOR)
				draw_rect(Rect2(bp - Vector2.ONE, P2), Color(0.55, 0.62, 0.72))
		else:
			draw_rect(Rect2(ball_pos - P2, P5), OUTLINE_COLOR)
			draw_rect(Rect2(ball_pos - Vector2.ONE, P3), COL_BALL_BODY)
			draw_rect(Rect2(ball_pos - Vector2.ONE, Vector2.ONE), COL_BALL_HI)

func _draw_particles_and_bolts() -> void:
	var pt_rect: Rect2 = _cam_rect.grow(24.0)
	for pt in _particles:
		var draw_pos: Vector2 = ((pt["pos"] as Vector2) + Vector2(0.0, -float(pt["z"]))).round()
		if _has_cam_rect and not pt_rect.has_point(draw_pos):
			continue
		var t: float = clampf(float(pt["age"]) / float(pt["max_age"]), 0.0, 1.0)
		var col: Color = pt["color"]
		col.a *= (1.0 - t * t)
		var sz: float = float(pt["size"])
		if bool(pt["outline"]):
			var ol := OUTLINE_COLOR
			ol.a = col.a
			draw_rect(Rect2(draw_pos - Vector2.ONE, Vector2(sz + 2.0, sz + 2.0)), ol)
		draw_rect(Rect2(draw_pos, Vector2(sz, sz)), col)

	var bolt_rect: Rect2 = _cam_rect.grow(48.0)
	for lb in _lightning_bolts:
		var segs: Array = lb["segments"]
		if segs.is_empty() or (_has_cam_rect and not bolt_rect.has_point(segs[segs.size() - 1] as Vector2)):
			continue
		var alpha: float = 1.0 - clampf(float(lb["age"]) / float(lb["max_age"]), 0.0, 1.0)
		var outer_col := Color(0.45, 0.82, 1.0, alpha * 0.7)
		var inner_col := Color(0.96, 0.99, 1.0, alpha)
		for i in range(segs.size() - 1):
			draw_line(segs[i], segs[i + 1], outer_col, 4.0, false)
			draw_line(segs[i], segs[i + 1], inner_col, 1.5, false)

func _draw_broadside_cone() -> void:
	_draw_aim_arc(_cone_poly, _aim_origin, _aim_dir, _aim_range, _aim_half_angle, 14, Color(0.98, 0.85, 0.42, 0.14), Color(0.98, 0.88, 0.48, 0.58), Color(1.0, 0.92, 0.62, 0.72))


func _draw_bow_cone() -> void:
	_draw_aim_arc(_bow_poly, _bow_origin, _bow_dir, _bow_range, _bow_half_angle, 8, Color(0.42, 0.92, 0.96, 0.12), Color(0.54, 0.94, 0.98, 0.54), Color(0.76, 0.98, 1.0, 0.68))


func _draw_aim_arc(poly: PackedVector2Array, origin: Vector2, dir: Vector2, range_px: float, half_angle: float, arc_steps: int, fill_col: Color, edge_col: Color, arc_col: Color) -> void:
	var base_ang: float = dir.angle()
	var a0: float = base_ang - half_angle
	var a1: float = base_ang + half_angle
	poly.resize(arc_steps + 2)
	poly[0] = origin.round()
	for i in range(arc_steps + 1):
		var ang: float = lerpf(a0, a1, float(i) / float(arc_steps))
		poly[i + 1] = (origin + Vector2(cos(ang), sin(ang)) * range_px).round()
	draw_colored_polygon(poly, fill_col)
	draw_line(poly[0], poly[1], edge_col, 1.0, false)
	draw_line(poly[0], poly[arc_steps + 1], edge_col, 1.0, false)
	for i in range(0, arc_steps, 2):
		draw_line(poly[i + 1], poly[i + 2], arc_col, 1.5, false)

func _on_broadside_fired(_ship_id: int, _is_starboard: bool, origin: Vector2, dir: Vector2, _cannons: Array) -> void:
	if _is_near_camera(origin, 160.0):
		var n_dir: Vector2 = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
		for i in range(7):
			var sd: Vector2 = n_dir.rotated(_rng.randf_range(-0.45, 0.45))
			_emit_particle(origin + sd * _rng.randf_range(2.0, 8.0), sd * _rng.randf_range(18.0, 42.0), 6.0, _rng.randf_range(4.0, 14.0), 10.0, _rng.randf_range(0.32, 0.55), _rng.randf_range(3.0, 5.0), Color(0.92, 0.90, 0.86, 0.85), false)
	_trigger_camera_trauma_if_near(origin, 0.18, 420.0)

func _on_cannonball_spawned(shot_data: Dictionary) -> void:
	var origin: Vector2 = shot_data.get("origin", shot_data.get("pos", shot_data.get("start_pos", Vector2.ZERO)))
	var vel: Vector2 = shot_data.get("velocity", shot_data.get("vel", Vector2.ZERO))
	if vel.length_squared() < 0.01:
		vel = (shot_data.get("dir", Vector2.RIGHT) as Vector2).normalized() * float(shot_data.get("speed", 220.0))
	var max_range: float = float(shot_data.get("max_range", shot_data.get("range", 260.0)))
	var item_id_str: String = str(shot_data.get("item_id", ""))
	var is_fire: bool = bool(shot_data.get("is_greek_fire", float(shot_data.get("burn_dps", 0.0)) > 0.0 or item_id_str.contains("greek_fire") or item_id_str.contains("pitch_mortar")))
	var is_harpoon: bool = bool(shot_data.get("is_harpoon", float(shot_data.get("harpoon_pull", 0.0)) > 0.0 or item_id_str.contains("harpoon")))
	var is_chain: bool = bool(shot_data.get("is_chain_shot", float(shot_data.get("chain_slow", shot_data.get("chain_shot_slow", 0.0))) > 0.0 and not is_harpoon))
	if bool(shot_data.get("is_bow", false)) and _is_near_camera(origin, 160.0):
		var n_dir: Vector2 = vel.normalized() if vel.length_squared() > 0.0001 else Vector2.RIGHT
		_emit_particle(origin + n_dir * 3.0, n_dir * 26.0, 6.0, 4.0, 0.0, 0.16, 4.0, Color(1.0, 0.88, 0.42, 0.95), false)
		for _i in range(4):
			var sd: Vector2 = n_dir.rotated(_rng.randf_range(-0.28, 0.28))
			_emit_particle(origin + sd * _rng.randf_range(2.0, 6.0), sd * _rng.randf_range(16.0, 36.0), 6.0, _rng.randf_range(4.0, 10.0), 8.0, _rng.randf_range(0.24, 0.44), _rng.randf_range(2.5, 4.0), Color(0.92, 0.90, 0.86, 0.82), false)
		_trigger_camera_trauma_if_near(origin, 0.12, 380.0)
	_entities_renderer.notify_cannonball_origin(origin, vel)
	_projectiles.append({
		"id": int(shot_data.get("id", shot_data.get("shot_id", -1))), "shooter_id": int(shot_data.get("shooter_id", shot_data.get("owner_id", -1))),
		"origin": origin, "pos": origin, "vel": vel, "traveled": 0.0, "max_range": max_range,
		"arc_height": float(shot_data.get("arc_height", clampf(max_range * 0.085, 12.0, 28.0))),
		"age": 0.0, "smoke_accum": 0.0, "is_chain": is_chain, "is_fire": is_fire, "is_harpoon": is_harpoon
	})

func _on_cannonball_impact(world_pos: Vector2, hit_ship_id: int, _damage: float, is_water_splash: bool, is_powder_crit: bool) -> void:
	var consumed: Dictionary = _consume_nearest_projectile(world_pos)
	var was_fire: bool = bool(consumed.get("is_fire", false))
	var was_harpoon: bool = bool(consumed.get("is_harpoon", false))
	if is_water_splash:
		if _is_near_camera(world_pos, 140.0):
			_spawn_water_splash(world_pos)
			if was_fire:
				_spawn_fire_burst(world_pos, 6)
		return
	if _is_near_camera(world_pos, 180.0):
		_spawn_ship_impact(world_pos, is_powder_crit)
		if was_fire:
			_spawn_fire_burst(world_pos, 14)
	if was_fire and hit_ship_id >= 0:
		_burning_ships[hit_ship_id] = { "timer": 4.0, "emit_accum": 0.0 }
	if was_harpoon and hit_ship_id >= 0:
		_harpoon_tethers.append({ "start_ship_id": int(consumed.get("shooter_id", -1)), "end_ship_id": hit_ship_id, "start_pos": consumed.get("origin", world_pos), "end_pos": world_pos, "age": 0.0, "max_age": 0.55 })

func _on_ship_state_updated(ship_id: int, world_pos: Vector2, _h: float, _s: float, _ss: int, _hp: float, _mhp: float) -> void:
	_ship_positions[ship_id] = world_pos

func _on_ship_damaged(_ship_id: int, damage: float, _new_hp: float, _max_hp: float, world_pos: Vector2) -> void:
	if damage > 0.0 and _is_near_camera(world_pos, 140.0):
		var c := Color(0.98, 0.72, 0.28, 0.95)
		_emit_burst(world_pos, 4, 0.0, 16.0, 38.0, 6.0, 18.0, 34.0, 95.0, 0.35, 0.35, 2.0, 2.0, c, c, true)

func _on_ship_sunk(ship_id: int, world_pos: Vector2, _faction: int, _killer_ship_id: int) -> void:
	_burning_ships.erase(ship_id)
	_ship_positions.erase(ship_id)
	if _is_near_camera(world_pos, 220.0):
		_emit_ring(world_pos, 6.0, 44.0, 0.95, Color(0.95, 0.98, 1.0, 0.92))
		_emit_ring(world_pos, 3.0, 28.0, 0.65, Color(1.0, 0.65, 0.25, 0.90))
		_emit_burst(world_pos, 22, 8.0, 18.0, 62.0, 4.0, 26.0, 68.0, 115.0, 0.55, 0.95, 4.0, 3.0, Color(1.0, 0.56, 0.16, 1.0), Color(0.56, 0.34, 0.23, 1.0), true, 3)
	_trigger_camera_trauma_if_near(world_pos, 0.48, 550.0)

func _on_loot_spawned(loot_data: Contracts.LootDropData) -> void:
	if loot_data == null:
		return
	if _loot_crates.has(loot_data.drop_id):
		var old_spr: Sprite2D = _loot_crates[loot_data.drop_id]["sprite"]
		if is_instance_valid(old_spr):
			old_spr.queue_free()
	var spr := Sprite2D.new()
	spr.name = "LootCrate_%d" % loot_data.drop_id
	spr.texture = ProceduralShipBaker.bake_loot_crate_texture(loot_data.is_salvage_target)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.centered = true
	spr.position = loot_data.world_pos.round()
	spr.z_index = -1
	add_child(spr)
	_loot_crates[loot_data.drop_id] = { "sprite": spr, "pos": loot_data.world_pos, "salvage": loot_data.is_salvage_target }

func _on_loot_collected(drop_id: int, _collector_ship_id: int, loot_data: Contracts.LootDropData) -> void:
	var burst_pos: Vector2 = loot_data.world_pos if loot_data != null else Vector2.ZERO
	if _loot_crates.has(drop_id):
		burst_pos = _loot_crates[drop_id]["pos"]
		var spr: Sprite2D = _loot_crates[drop_id]["sprite"]
		if is_instance_valid(spr):
			spr.queue_free()
		_loot_crates.erase(drop_id)
	if _is_near_camera(burst_pos, 160.0):
		_emit_ring(burst_pos, 4.0, 22.0, 0.45, Color(0.98, 0.82, 0.25, 0.90))
		var c := Color(1.0, 0.88, 0.35, 1.0)
		_emit_burst(burst_pos, 10, 0.0, 18.0, 34.0, 4.0, 24.0, 44.0, 90.0, 0.42, 0.42, 2.0, 2.0, c, c, true)

func _on_sea_monster_spawned(monster_id: int, world_pos: Vector2, max_hp: float) -> void:
	_entities_renderer.on_sea_monster_spawned(monster_id, world_pos, max_hp)
	if _is_near_camera(world_pos, 200.0):
		_emit_ring(world_pos, 8.0, 48.0, 0.85, Color(0.36, 0.94, 0.86, 0.92))

func _on_sea_monster_updated(monster_id: int, world_pos: Vector2, hp: float, max_hp: float, phase: int) -> void:
	if _entities_renderer.on_sea_monster_updated(monster_id, world_pos, hp, max_hp, phase) and _is_near_camera(world_pos, 160.0):
		var c := Color(0.76, 0.24, 0.52, 0.95)
		_emit_burst(world_pos, 6, 0.0, 16.0, 40.0, 4.0, 20.0, 42.0, 100.0, 0.38, 0.38, 3.0, 3.0, c, c, true)

func _on_sea_monster_defeated(monster_id: int, world_pos: Vector2) -> void:
	_entities_renderer.on_sea_monster_defeated(monster_id)
	if _is_near_camera(world_pos, 240.0):
		_emit_ring(world_pos, 6.0, 58.0, 1.0, Color(0.42, 0.96, 0.88, 0.95))
		_emit_burst(world_pos, 26, 10.0, 22.0, 74.0, 5.0, 28.0, 72.0, 115.0, 0.55, 1.0, 4.0, 3.0, Color(0.42, 0.94, 0.88, 1.0), Color(0.68, 0.22, 0.48, 1.0), true, 3)
	_trigger_camera_trauma_if_near(world_pos, 0.55, 600.0)

func _on_fort_spawned(fort_id: int, world_pos: Vector2, island_index: int, max_hp: float) -> void:
	_entities_renderer.on_fort_spawned(fort_id, world_pos, island_index, max_hp)

func _on_fort_damaged(fort_id: int, hp: float, max_hp: float, world_pos: Vector2) -> void:
	_entities_renderer.on_fort_damaged(fort_id, hp, max_hp, world_pos)
	if _is_near_camera(world_pos, 160.0):
		_emit_burst(world_pos, 6, 0.0, 16.0, 38.0, 6.0, 18.0, 40.0, 110.0, 0.42, 0.42, 3.0, 3.0, Color(0.68, 0.64, 0.70, 1.0), Color(1.0, 0.58, 0.16, 1.0), true)

func _on_fort_destroyed(fort_id: int, world_pos: Vector2) -> void:
	_entities_renderer.on_fort_destroyed(fort_id)
	if _is_near_camera(world_pos, 220.0):
		_emit_ring(world_pos, 6.0, 46.0, 0.85, Color(1.0, 0.62, 0.22, 0.94))
		_spawn_fire_burst(world_pos, 18)
		var c := Color(0.54, 0.50, 0.56, 1.0)
		_emit_burst(world_pos, 14, 0.0, 20.0, 64.0, 6.0, 30.0, 74.0, 120.0, 0.55, 0.95, 4.0, 4.0, c, c, true)
	_trigger_camera_trauma_if_near(world_pos, 0.50, 560.0)

func _on_lightning_flash(world_pos: Vector2) -> void:
	if _is_near_camera(world_pos, 220.0):
		var segs: Array[Vector2] = []
		var cur := world_pos + Vector2(_rng.randf_range(-18.0, 18.0), -140.0)
		segs.append(cur.round())
		for step in range(1, 7):
			segs.append((cur.lerp(world_pos, float(step) / 7.0) + Vector2(_rng.randf_range(-12.0, 12.0), 0.0)).round())
		segs.append(world_pos.round())
		_lightning_bolts.append({ "segments": segs, "age": 0.0, "max_age": 0.28 })
		_emit_ring(world_pos, 3.0, 26.0, 0.45, Color(0.84, 0.96, 1.0, 0.92))
	_trigger_camera_trauma_if_near(world_pos, 0.28, 480.0)

func _spawn_fire_burst(world_pos: Vector2, count: int) -> void:
	_emit_burst(world_pos, count, 4.0, 12.0, 44.0, 4.0, 16.0, 42.0, 35.0, 0.32, 0.58, 3.5, 2.8, Color(1.0, 0.42, 0.12, 1.0), Color(1.0, 0.86, 0.28, 1.0), true)

func _spawn_water_splash(world_pos: Vector2) -> void:
	_emit_ring(world_pos, 2.0, 18.0, 0.55, Color(0.95, 0.99, 1.0, 0.88))
	_emit_ring(world_pos, 1.0, 11.0, 0.40, Color(0.45, 0.89, 0.88, 0.80))
	_emit_burst(world_pos, 10, 0.0, 8.0, 26.0, 1.0, 34.0, 62.0, 165.0, 0.32, 0.52, 2.0, 2.0, Color(0.95, 0.98, 1.0, 0.95), Color(0.55, 0.90, 0.92, 0.90), false)

func _spawn_ship_impact(world_pos: Vector2, is_powder_crit: bool) -> void:
	_emit_ring(world_pos, 3.0, 30.0 if is_powder_crit else 16.0, 0.50 if is_powder_crit else 0.32, Color(1.0, 0.45, 0.16, 0.95) if is_powder_crit else Color(1.0, 0.78, 0.38, 0.85))
	var fire_c := Color(1.0, 0.42, 0.14, 1.0) if is_powder_crit else Color(1.0, 0.76, 0.28, 1.0)
	var sz: float = 3.0 if is_powder_crit else 2.0
	_emit_burst(world_pos, 20 if is_powder_crit else 10, 0.0, 24.0, 72.0 if is_powder_crit else 46.0, 5.0, 22.0, 58.0, 115.0, 0.32, 0.65, sz, sz, fire_c, Color(0.72, 0.44, 0.31, 1.0), true)
	for j in range(4 if is_powder_crit else 2):
		_emit_particle(world_pos + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-4.0, 4.0)), Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-16.0, -6.0)), 7.0, 6.0, 0.0, 0.55, 5.0 if is_powder_crit else 4.0, Color(0.24, 0.22, 0.25, 0.78), false)
	_hitstop_timer = 0.045 if is_powder_crit else 0.022
	_trigger_camera_trauma_if_near(world_pos, 0.42 if is_powder_crit else 0.16, 520.0 if is_powder_crit else 420.0)

func _consume_nearest_projectile(world_pos: Vector2) -> Dictionary:
	var best_idx: int = -1
	var best_dist_sq: float = 34.0 * 34.0
	for i in range(_projectiles.size()):
		var d2: float = (_projectiles[i]["pos"] as Vector2).distance_squared_to(world_pos)
		if d2 < best_dist_sq:
			best_dist_sq = d2
			best_idx = i
	if best_idx >= 0:
		var popped: Dictionary = _projectiles[best_idx]
		_projectiles.remove_at(best_idx)
		return popped
	return {}

func _trigger_camera_trauma_if_near(world_pos: Vector2, amount: float, max_dist: float) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_2d() if vp != null else null
	if cam != null and cam.global_position.distance_squared_to(world_pos) <= max_dist * max_dist and cam.has_method("add_trauma"):
		cam.add_trauma(amount)

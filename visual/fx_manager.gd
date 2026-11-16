class_name FxManager
extends Node2D
## Handles 2D pixel-art combat FX (cannonballs, Greek Fire, Harpoon Ballista ropes,
## water splashes, wood splinters, powder crits, sinking debris), floating loot crates,
## broadside targeting cone, Coastal Forts, Giant Kraken boss, and lightning bolts.

const OUTLINE_COLOR := Color(0.094, 0.078, 0.145, 1.0) # #181425

var _time_accum: float = 0.0
var _hitstop_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

var _projectiles: Array[Dictionary] = []
var _particles: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _loot_crates: Dictionary = {}      # drop_id -> { "sprite": Sprite2D, "pos": Vector2, "salvage": bool }
var _sea_monsters: Dictionary = {}     # monster_id -> { "pos": Vector2, "hp": float, "max_hp": float, "phase": int, "hit_flash": float, "foam_timer": float }
var _forts: Dictionary = {}            # fort_id -> { "pos": Vector2, "island_index": int, "hp": float, "max_hp": float, "aim_angle": float, "hit_flash": float, "fire_flash": float }
var _ship_positions: Dictionary = {}   # ship_id -> Vector2
var _burning_ships: Dictionary = {}    # ship_id -> { "timer": float, "emit_accum": float }
var _harpoon_tethers: Array[Dictionary] = [] # { "start_ship_id": int, "end_ship_id": int, "start_pos": Vector2, "end_pos": Vector2, "age": float, "max_age": float }
var _lightning_bolts: Array[Dictionary] = [] # { "segments": Array[Vector2], "age": float, "max_age": float }

var _aim_cone_active: bool = false
var _aim_origin: Vector2 = Vector2.ZERO
var _aim_dir: Vector2 = Vector2.RIGHT
var _aim_range: float = 240.0
var _aim_half_angle: float = 0.35


func _ready() -> void:
	_rng.randomize()
	z_index = 25
	_connect_signals()


func _connect_signals() -> void:
	var bus: Contracts = Contracts.bus()
	if bus == null:
		return
	if not bus.broadside_fired.is_connected(_on_broadside_fired):
		bus.broadside_fired.connect(_on_broadside_fired)
	if not bus.cannonball_spawned.is_connected(_on_cannonball_spawned):
		bus.cannonball_spawned.connect(_on_cannonball_spawned)
	if not bus.cannonball_impact.is_connected(_on_cannonball_impact):
		bus.cannonball_impact.connect(_on_cannonball_impact)
	if not bus.ship_state_updated.is_connected(_on_ship_state_updated):
		bus.ship_state_updated.connect(_on_ship_state_updated)
	if not bus.ship_damaged.is_connected(_on_ship_damaged):
		bus.ship_damaged.connect(_on_ship_damaged)
	if not bus.ship_sunk.is_connected(_on_ship_sunk):
		bus.ship_sunk.connect(_on_ship_sunk)
	if not bus.loot_spawned.is_connected(_on_loot_spawned):
		bus.loot_spawned.connect(_on_loot_spawned)
	if not bus.loot_collected.is_connected(_on_loot_collected):
		bus.loot_collected.connect(_on_loot_collected)
	if not bus.sea_monster_spawned.is_connected(_on_sea_monster_spawned):
		bus.sea_monster_spawned.connect(_on_sea_monster_spawned)
	if not bus.sea_monster_updated.is_connected(_on_sea_monster_updated):
		bus.sea_monster_updated.connect(_on_sea_monster_updated)
	if not bus.sea_monster_defeated.is_connected(_on_sea_monster_defeated):
		bus.sea_monster_defeated.connect(_on_sea_monster_defeated)
	if not bus.fort_spawned.is_connected(_on_fort_spawned):
		bus.fort_spawned.connect(_on_fort_spawned)
	if not bus.fort_damaged.is_connected(_on_fort_damaged):
		bus.fort_damaged.connect(_on_fort_damaged)
	if not bus.fort_destroyed.is_connected(_on_fort_destroyed):
		bus.fort_destroyed.connect(_on_fort_destroyed)
	if not bus.lightning_flash.is_connected(_on_lightning_flash):
		bus.lightning_flash.connect(_on_lightning_flash)


func set_broadside_aim_cone(origin: Vector2, dir: Vector2, range_px: float, half_angle_rad: float, active: bool) -> void:
	_aim_cone_active = active
	_aim_origin = origin
	_aim_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	_aim_range = maxf(24.0, range_px)
	_aim_half_angle = clampf(half_angle_rad, 0.05, 1.45)
	queue_redraw()


func _process(delta: float) -> void:
	_time_accum += delta

	if _hitstop_timer > 0.0:
		_hitstop_timer = maxf(0.0, _hitstop_timer - delta)
		_update_loot_bobbing()
		queue_redraw()
		return

	_update_projectiles(delta)
	_update_particles(delta)
	_update_rings(delta)
	_update_loot_bobbing()
	_update_forts(delta)
	_update_sea_monsters(delta)
	_update_burning_ships(delta)
	_update_harpoon_tethers(delta)
	_update_lightning_bolts(delta)
	queue_redraw()


func _update_projectiles(delta: float) -> void:
	var idx: int = _projectiles.size() - 1
	while idx >= 0:
		var proj: Dictionary = _projectiles[idx]
		var vel: Vector2 = proj["vel"]
		var step_dist: float = vel.length() * delta
		proj["pos"] = (proj["pos"] as Vector2) + vel * delta
		proj["traveled"] = float(proj["traveled"]) + step_dist
		proj["age"] = float(proj["age"]) + delta

		var max_r: float = maxf(1.0, float(proj["max_range"]))
		var progress: float = clampf(float(proj["traveled"]) / max_r, 0.0, 1.0)
		var arc_y: float = -sin(progress * PI) * float(proj["arc_height"])

		proj["smoke_accum"] = float(proj["smoke_accum"]) + delta
		if float(proj["smoke_accum"]) >= 0.032:
			proj["smoke_accum"] = 0.0
			var is_fire: bool = bool(proj["is_fire"])
			_particles.append({
				"pos": (proj["pos"] as Vector2) + Vector2(0.0, arc_y),
				"vel": Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-16.0, -4.0)),
				"z": 0.0,
				"vz": 0.0,
				"gravity": 0.0,
				"age": 0.0,
				"max_age": 0.28 if not is_fire else 0.34,
				"size": 3.0 if is_fire else 2.0,
				"color": Color(1.0, 0.56, 0.14, 0.92) if is_fire else Color(0.92, 0.92, 0.94, 0.72),
				"outline": false
			})

		if float(proj["traveled"]) >= max_r + 12.0 or float(proj["age"]) > 3.5:
			_projectiles.remove_at(idx)
		idx -= 1


func _update_particles(delta: float) -> void:
	var idx: int = _particles.size() - 1
	while idx >= 0:
		var pt: Dictionary = _particles[idx]
		pt["age"] = float(pt["age"]) + delta
		if float(pt["age"]) >= float(pt["max_age"]):
			_particles.remove_at(idx)
			idx -= 1
			continue

		pt["pos"] = (pt["pos"] as Vector2) + (pt["vel"] as Vector2) * delta
		pt["vel"] = (pt["vel"] as Vector2) * maxf(0.0, 1.0 - delta * 2.2)

		var vz: float = float(pt["vz"]) - float(pt["gravity"]) * delta
		var z: float = float(pt["z"]) + vz * delta
		if z < 0.0:
			z = 0.0
			vz = 0.0
		pt["vz"] = vz
		pt["z"] = z
		idx -= 1


func _update_rings(delta: float) -> void:
	var idx: int = _rings.size() - 1
	while idx >= 0:
		var ring: Dictionary = _rings[idx]
		ring["age"] = float(ring["age"]) + delta
		if float(ring["age"]) >= float(ring["max_age"]):
			_rings.remove_at(idx)
		idx -= 1


func _update_loot_bobbing() -> void:
	for drop_id in _loot_crates.keys():
		var entry: Dictionary = _loot_crates[drop_id]
		var spr: Sprite2D = entry["sprite"]
		if not is_instance_valid(spr):
			continue
		var base_pos: Vector2 = entry["pos"]
		var bob: float = sin(_time_accum * 2.6 + float(int(drop_id) % 17)) * 1.5
		spr.position = (base_pos + Vector2(0.0, bob)).round()
		if bool(entry["salvage"]):
			var pulse: float = 0.90 + 0.15 * sin(_time_accum * 4.2)
			spr.modulate = Color(pulse, 1.0, pulse, 1.0)


func _update_forts(delta: float) -> void:
	for fid in _forts.keys():
		var fort: Dictionary = _forts[fid]
		if float(fort["hit_flash"]) > 0.0:
			fort["hit_flash"] = maxf(0.0, float(fort["hit_flash"]) - delta)
		if float(fort["fire_flash"]) > 0.0:
			fort["fire_flash"] = maxf(0.0, float(fort["fire_flash"]) - delta)
		# Gently sweep turret toward nearest ship or slow patrol scan
		var fpos: Vector2 = fort["pos"]
		var nearest_dist_sq: float = 340.0 * 340.0
		var has_target := false
		var target_ang: float = float(fort["aim_angle"])
		for sid in _ship_positions.keys():
			var sp: Vector2 = _ship_positions[sid]
			var d2: float = fpos.distance_squared_to(sp)
			if d2 < nearest_dist_sq:
				nearest_dist_sq = d2
				target_ang = (sp - fpos).angle()
				has_target = true
		if has_target:
			fort["aim_angle"] = lerp_angle(float(fort["aim_angle"]), target_ang, minf(1.0, delta * 3.0))
		else:
			fort["aim_angle"] = wrapf(float(fort["aim_angle"]) + delta * 0.35, -PI, PI)


func _update_sea_monsters(delta: float) -> void:
	for mid in _sea_monsters.keys():
		var m: Dictionary = _sea_monsters[mid]
		if float(m["hit_flash"]) > 0.0:
			m["hit_flash"] = maxf(0.0, float(m["hit_flash"]) - delta)
		m["foam_timer"] = float(m["foam_timer"]) + delta
		if float(m["foam_timer"]) >= 0.42:
			m["foam_timer"] = 0.0
			_rings.append({
				"pos": m["pos"],
				"r_start": 10.0,
				"r_end": 28.0 + float(int(m["phase"])) * 4.0,
				"age": 0.0,
				"max_age": 0.85,
				"color": Color(0.45, 0.94, 0.86, 0.58)
			})


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
			var flame_col := Color(1.0, 0.54, 0.14, 0.95) if _rng.randf() < 0.6 else Color(1.0, 0.88, 0.30, 0.95)
			_particles.append({
				"pos": spos + Vector2(_rng.randf_range(-9.0, 9.0), _rng.randf_range(-5.0, 5.0)),
				"vel": Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-24.0, -12.0)),
				"z": 6.0,
				"vz": _rng.randf_range(8.0, 18.0),
				"gravity": 0.0,
				"age": 0.0,
				"max_age": _rng.randf_range(0.28, 0.48),
				"size": _rng.randf_range(2.0, 4.0),
				"color": flame_col,
				"outline": true
			})
	for sid in to_erase:
		_burning_ships.erase(sid)


func _update_harpoon_tethers(delta: float) -> void:
	var idx: int = _harpoon_tethers.size() - 1
	while idx >= 0:
		var t: Dictionary = _harpoon_tethers[idx]
		t["age"] = float(t["age"]) + delta
		var s_id: int = int(t["start_ship_id"])
		var e_id: int = int(t["end_ship_id"])
		if s_id >= 0 and _ship_positions.has(s_id):
			t["start_pos"] = _ship_positions[s_id]
		if e_id >= 0 and _ship_positions.has(e_id):
			t["end_pos"] = _ship_positions[e_id]
		if float(t["age"]) >= float(t["max_age"]):
			_harpoon_tethers.remove_at(idx)
		idx -= 1


func _update_lightning_bolts(delta: float) -> void:
	var idx: int = _lightning_bolts.size() - 1
	while idx >= 0:
		var lb: Dictionary = _lightning_bolts[idx]
		lb["age"] = float(lb["age"]) + delta
		if float(lb["age"]) >= float(lb["max_age"]):
			_lightning_bolts.remove_at(idx)
		idx -= 1


func _draw() -> void:
	# 1. Broadside targeting cone on the water surface
	if _aim_cone_active:
		_draw_broadside_cone()

	# 2. Concentric pixel water foam / shockwave rings
	for ring in _rings:
		var t: float = clampf(float(ring["age"]) / float(ring["max_age"]), 0.0, 1.0)
		var r: float = lerpf(float(ring["r_start"]), float(ring["r_end"]), t)
		var center: Vector2 = ring["pos"]
		var col: Color = ring["color"]
		col.a *= (1.0 - t)
		var steps: int = int(clampf(r * 1.4, 12.0, 36.0))
		for i in range(steps):
			if i % 2 == 1 and t > 0.35:
				continue
			var ang: float = (float(i) / float(steps)) * TAU
			var p: Vector2 = (center + Vector2(cos(ang), sin(ang) * 0.72) * r).round()
			draw_rect(Rect2(p, Vector2(2.0, 2.0)), col)

	# 3. Salvage / Loot subtle water rings
	for drop_id in _loot_crates.keys():
		var entry: Dictionary = _loot_crates[drop_id]
		var base_pos: Vector2 = entry["pos"]
		var is_salvage: bool = bool(entry["salvage"])
		var pulse_r: float = 11.0 + sin(_time_accum * 2.4 + float(int(drop_id))) * 2.0
		var ring_col := Color(0.35, 0.95, 0.78, 0.55) if is_salvage else Color(0.94, 0.98, 1.0, 0.32)
		for i in range(12):
			if i % 2 != 0:
				continue
			var ang: float = (float(i) / 12.0) * TAU + _time_accum * 0.5
			var pt: Vector2 = (base_pos + Vector2(cos(ang), sin(ang) * 0.75) * pulse_r).round()
			draw_rect(Rect2(pt, Vector2(2.0, 2.0)), ring_col)

	# 4. Coastal Forts / Pirate Watchtowers (turret, flickering torches, cannon barrel)
	_draw_forts()

	# 5. Giant Kraken Sea Monsters (animated tentacles + foam vortex + HP bar)
	_draw_sea_monsters()

	# 6. Taut Harpoon Ballista ropes
	for tether in _harpoon_tethers:
		var alpha: float = 1.0 - clampf(float(tether["age"]) / float(tether["max_age"]), 0.0, 1.0)
		var p0: Vector2 = (tether["start_pos"] as Vector2).round()
		var p1: Vector2 = (tether["end_pos"] as Vector2).round()
		draw_line(p0, p1, Color(0.10, 0.08, 0.14, alpha * 0.85), 3.0, false)
		draw_line(p0, p1, Color(0.90, 0.82, 0.60, alpha), 1.5, false)

	# 7. Flying 2D projectiles (standard, chain shot, Greek Fire, Harpoon spear)
	for proj in _projectiles:
		var ground_pos: Vector2 = proj["pos"]
		var max_r: float = maxf(1.0, float(proj["max_range"]))
		var progress: float = clampf(float(proj["traveled"]) / max_r, 0.0, 1.0)
		var arc_h: float = float(proj["arc_height"])
		var height_offset: float = -sin(progress * PI) * arc_h
		var ball_pos: Vector2 = (ground_pos + Vector2(0.0, height_offset)).round()
		var shadow_pos: Vector2 = ground_pos.round()

		var shadow_w: float = lerpf(5.0, 3.0, sin(progress * PI))
		draw_rect(
			Rect2(shadow_pos - Vector2(shadow_w * 0.5, 1.0), Vector2(shadow_w, 2.0)),
			Color(0.06, 0.10, 0.20, 0.52)
		)

		if bool(proj["is_harpoon"]):
			var origin_p: Vector2 = (proj["origin"] as Vector2).round()
			draw_line(origin_p, ball_pos, Color(0.86, 0.78, 0.56, 0.85), 1.0, false)
			var dir_v: Vector2 = (proj["vel"] as Vector2).normalized()
			var tail: Vector2 = (ball_pos - dir_v * 6.0).round()
			var tip: Vector2 = (ball_pos + dir_v * 5.0).round()
			draw_line(tail, tip, OUTLINE_COLOR, 3.0, false)
			draw_line(tail, tip, Color(0.82, 0.88, 0.96, 1.0), 1.5, false)
		elif bool(proj["is_fire"]):
			draw_rect(Rect2(ball_pos - Vector2(3, 3), Vector2(6, 6)), OUTLINE_COLOR)
			draw_rect(Rect2(ball_pos - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 0.42, 0.12))
			draw_rect(Rect2(ball_pos - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 0.94, 0.50))
		elif bool(proj["is_chain"]):
			var perp: Vector2 = (proj["vel"] as Vector2).normalized().orthogonal() * 3.0
			var b1: Vector2 = (ball_pos + perp).round()
			var b2: Vector2 = (ball_pos - perp).round()
			draw_line(b1, b2, Color(0.75, 0.80, 0.88, 1.0), 1.0, false)
			for bp in [b1, b2]:
				draw_rect(Rect2(bp - Vector2(2, 2), Vector2(4, 4)), OUTLINE_COLOR)
				draw_rect(Rect2(bp - Vector2(1, 1), Vector2(2, 2)), Color(0.55, 0.62, 0.72))
		else:
			draw_rect(Rect2(ball_pos - Vector2(2, 2), Vector2(5, 5)), OUTLINE_COLOR)
			draw_rect(Rect2(ball_pos - Vector2(1, 1), Vector2(3, 3)), Color(0.26, 0.28, 0.34))
			draw_rect(Rect2(ball_pos - Vector2(1, 1), Vector2(1, 1)), Color(0.84, 0.88, 0.94))

	# 8. Pixel particles (water fountains, wood splinters, fire sparks, smoke)
	for pt in _particles:
		var t: float = clampf(float(pt["age"]) / float(pt["max_age"]), 0.0, 1.0)
		var col: Color = pt["color"]
		col.a *= (1.0 - t * t)
		var sz: float = float(pt["size"])
		var draw_pos: Vector2 = ((pt["pos"] as Vector2) + Vector2(0.0, -float(pt["z"]))).round()
		if bool(pt["outline"]):
			draw_rect(Rect2(draw_pos - Vector2(1, 1), Vector2(sz + 2.0, sz + 2.0)), Color(OUTLINE_COLOR.r, OUTLINE_COLOR.g, OUTLINE_COLOR.b, col.a))
		draw_rect(Rect2(draw_pos, Vector2(sz, sz)), col)

	# 9. Jagged pixel lightning bolts
	for lb in _lightning_bolts:
		var alpha: float = 1.0 - clampf(float(lb["age"]) / float(lb["max_age"]), 0.0, 1.0)
		var segs: Array = lb["segments"]
		for i in range(segs.size() - 1):
			draw_line(segs[i], segs[i + 1], Color(0.45, 0.82, 1.0, alpha * 0.7), 4.0, false)
			draw_line(segs[i], segs[i + 1], Color(0.96, 0.99, 1.0, alpha), 1.5, false)


func _draw_forts() -> void:
	for fid in _forts.keys():
		var fort: Dictionary = _forts[fid]
		var fpos: Vector2 = fort["pos"]
		var aim_ang: float = float(fort["aim_angle"])
		var hp: float = float(fort["hp"])
		var max_hp: float = maxf(1.0, float(fort["max_hp"]))
		var hit_flash: bool = float(fort["hit_flash"]) > 0.0
		var fire_flash: bool = float(fort["fire_flash"]) > 0.0

		var fort_tex: ImageTexture = ProceduralShipBaker.bake_fort_texture(hit_flash)
		draw_set_transform(fpos.round(), aim_ang, Vector2.ONE)
		draw_texture(fort_tex, Vector2(-24.0, -24.0))
		if fire_flash:
			draw_rect(Rect2(Vector2(19.0, -3.5), Vector2(7.0, 7.0)), Color(1.0, 0.62, 0.16, 0.95))
			draw_rect(Rect2(Vector2(20.5, -2.0), Vector2(4.0, 4.0)), Color(1.0, 0.96, 0.72, 1.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# Crisp pixel HP bar above bastion
		var bar_w: float = 34.0
		var bar_h: float = 4.0
		var bar_pos: Vector2 = (fpos + Vector2(-bar_w * 0.5, -29.0)).round()
		var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
		draw_rect(Rect2(bar_pos - Vector2(1, 1), Vector2(bar_w + 2.0, bar_h + 2.0)), OUTLINE_COLOR)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.18, 0.11, 0.13, 0.94))
		draw_rect(Rect2(bar_pos, Vector2(floor(bar_w * ratio), bar_h)), Color(0.92, 0.30, 0.24))


func _draw_sea_monsters() -> void:
	for mid in _sea_monsters.keys():
		var m: Dictionary = _sea_monsters[mid]
		var mpos: Vector2 = m["pos"]
		var hp: float = float(m["hp"])
		var max_hp: float = maxf(1.0, float(m["max_hp"]))
		var phase: int = int(m["phase"])
		var hit_flash: bool = float(m["hit_flash"]) > 0.0

		var tent_list: Array[Dictionary] = []
		var anim_rate: float = 4.2 + float(phase) * 1.4
		for t_i in range(8):
			var base_ang: float = (float(t_i) / 8.0) * TAU + _time_accum * (0.20 + float(phase) * 0.08)
			var rx: float = 25.0 + sin(_time_accum * 2.1 + float(t_i) * 1.3) * 2.5
			var ry: float = 14.5 + cos(_time_accum * 1.9 + float(t_i) * 1.1) * 2.0
			var t_pos: Vector2 = mpos + Vector2(cos(base_ang) * rx, sin(base_ang) * ry + 5.0)
			var frame: int = (int(floor(_time_accum * anim_rate)) + t_i) % 3
			var flip_x: float = -1.0 if cos(base_ang) < 0.0 else 1.0
			var tilt: float = sin(_time_accum * (2.5 + float(phase) * 0.9) + float(t_i) * 1.4) * 0.16
			tent_list.append({
				"pos": t_pos.round(),
				"frame": frame,
				"flip_x": flip_x,
				"tilt": tilt
			})

		# 1. Back tentacles behind Kraken head
		for td in tent_list:
			if (td["pos"] as Vector2).y < mpos.y + 4.0:
				var t_tex: ImageTexture = ProceduralShipBaker.bake_kraken_tentacle_texture(int(td["frame"]), hit_flash)
				draw_set_transform(td["pos"], float(td["tilt"]), Vector2(float(td["flip_x"]), 1.0))
				draw_texture(t_tex, Vector2(-16.0, -26.0))

		# 2. Central 64x64 pixel-art Kraken head / mantle emerging from foam vortex
		var bob_y: float = sin(_time_accum * 2.3 + float(int(mid) % 7)) * 2.0 - 4.0
		var body_tilt: float = sin(_time_accum * 1.4) * 0.055
		var body_tex: ImageTexture = ProceduralShipBaker.bake_kraken_body_texture(hit_flash)
		draw_set_transform((mpos + Vector2(0.0, bob_y)).round(), body_tilt, Vector2.ONE)
		draw_texture(body_tex, Vector2(-32.0, -32.0))

		# 3. Front tentacles in front of Kraken waterline
		for td in tent_list:
			if (td["pos"] as Vector2).y >= mpos.y + 4.0:
				var t_tex: ImageTexture = ProceduralShipBaker.bake_kraken_tentacle_texture(int(td["frame"]), hit_flash)
				draw_set_transform(td["pos"], float(td["tilt"]), Vector2(float(td["flip_x"]), 1.0))
				draw_texture(t_tex, Vector2(-16.0, -26.0))

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# 4. Crisp Kraken HP bar
		var bar_w: float = 46.0
		var bar_h: float = 5.0
		var bar_pos: Vector2 = (mpos + Vector2(-bar_w * 0.5, -39.0)).round()
		var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
		draw_rect(Rect2(bar_pos - Vector2(1, 1), Vector2(bar_w + 2.0, bar_h + 2.0)), OUTLINE_COLOR)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.18, 0.10, 0.16, 0.94))
		draw_rect(Rect2(bar_pos, Vector2(floor(bar_w * ratio), bar_h)), Color(0.84, 0.24, 0.56))


func _draw_broadside_cone() -> void:
	var base_ang: float = _aim_dir.angle()
	var a0: float = base_ang - _aim_half_angle
	var a1: float = base_ang + _aim_half_angle
	var arc_steps: int = 14

	var poly := PackedVector2Array()
	poly.append(_aim_origin.round())
	for i in range(arc_steps + 1):
		var frac: float = float(i) / float(arc_steps)
		var ang: float = lerpf(a0, a1, frac)
		poly.append((_aim_origin + Vector2(cos(ang), sin(ang)) * _aim_range).round())

	draw_colored_polygon(poly, Color(0.98, 0.85, 0.42, 0.14))

	var edge_col := Color(0.98, 0.88, 0.48, 0.58)
	var left_end: Vector2 = (_aim_origin + Vector2(cos(a0), sin(a0)) * _aim_range).round()
	var right_end: Vector2 = (_aim_origin + Vector2(cos(a1), sin(a1)) * _aim_range).round()
	draw_line(_aim_origin.round(), left_end, edge_col, 1.0, false)
	draw_line(_aim_origin.round(), right_end, edge_col, 1.0, false)

	for i in range(arc_steps):
		if i % 2 == 1:
			continue
		var ang_a: float = lerpf(a0, a1, float(i) / float(arc_steps))
		var ang_b: float = lerpf(a0, a1, float(i + 1) / float(arc_steps))
		var p_a: Vector2 = (_aim_origin + Vector2(cos(ang_a), sin(ang_a)) * _aim_range).round()
		var p_b: Vector2 = (_aim_origin + Vector2(cos(ang_b), sin(ang_b)) * _aim_range).round()
		draw_line(p_a, p_b, Color(1.0, 0.92, 0.62, 0.72), 1.5, false)


# ==============================================================================
# SIGNAL HANDLERS
# ==============================================================================

func _on_broadside_fired(_ship_id: int, _is_starboard: bool, origin: Vector2, dir: Vector2, _cannons: Array) -> void:
	var n_dir: Vector2 = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	for i in range(7):
		var spread_dir: Vector2 = n_dir.rotated(_rng.randf_range(-0.45, 0.45))
		_particles.append({
			"pos": origin + spread_dir * _rng.randf_range(2.0, 8.0),
			"vel": spread_dir * _rng.randf_range(18.0, 42.0),
			"z": 6.0,
			"vz": _rng.randf_range(4.0, 14.0),
			"gravity": 10.0,
			"age": 0.0,
			"max_age": _rng.randf_range(0.32, 0.55),
			"size": _rng.randf_range(3.0, 5.0),
			"color": Color(0.92, 0.90, 0.86, 0.85),
			"outline": false
		})
	_trigger_camera_trauma_if_near(origin, 0.18, 420.0)


func _on_cannonball_spawned(shot_data: Dictionary) -> void:
	var origin: Vector2 = shot_data.get("origin", shot_data.get("pos", shot_data.get("start_pos", Vector2.ZERO)))
	var vel: Vector2 = shot_data.get("velocity", shot_data.get("vel", Vector2.ZERO))
	if vel.length_squared() < 0.01:
		var dir: Vector2 = shot_data.get("dir", Vector2.RIGHT)
		var spd: float = float(shot_data.get("speed", 220.0))
		vel = dir.normalized() * spd
	var max_range: float = float(shot_data.get("max_range", shot_data.get("range", 260.0)))
	var arc_h: float = float(shot_data.get("arc_height", clampf(max_range * 0.085, 12.0, 28.0)))
	var chain_val: float = float(shot_data.get("chain_slow", shot_data.get("chain_shot_slow", 0.0)))
	var burn_val: float = float(shot_data.get("burn_dps", 0.0))
	var harpoon_val: float = float(shot_data.get("harpoon_pull", 0.0))
	var item_id_str: String = str(shot_data.get("item_id", ""))
	var is_fire: bool = bool(shot_data.get("is_greek_fire", burn_val > 0.0 or item_id_str.contains("greek_fire")))
	var is_harpoon: bool = bool(shot_data.get("is_harpoon", harpoon_val > 0.0 or item_id_str.contains("harpoon")))
	var is_chain: bool = bool(shot_data.get("is_chain_shot", chain_val > 0.0 and not is_harpoon))

	# Rotate nearby fort turret if shot originates from a fort
	for fid in _forts.keys():
		var fort: Dictionary = _forts[fid]
		if (fort["pos"] as Vector2).distance_to(origin) < 28.0:
			fort["aim_angle"] = vel.angle()
			fort["fire_flash"] = 0.18

	_projectiles.append({
		"id": int(shot_data.get("id", shot_data.get("shot_id", -1))),
		"shooter_id": int(shot_data.get("shooter_id", shot_data.get("owner_id", -1))),
		"origin": origin,
		"pos": origin,
		"vel": vel,
		"traveled": 0.0,
		"max_range": max_range,
		"arc_height": arc_h,
		"age": 0.0,
		"smoke_accum": 0.0,
		"is_chain": is_chain,
		"is_fire": is_fire,
		"is_harpoon": is_harpoon
	})


func _on_cannonball_impact(world_pos: Vector2, hit_ship_id: int, _damage: float, is_water_splash: bool, is_powder_crit: bool) -> void:
	var consumed: Dictionary = _consume_nearest_projectile(world_pos)
	var was_fire: bool = bool(consumed.get("is_fire", false))
	var was_harpoon: bool = bool(consumed.get("is_harpoon", false))

	if is_water_splash:
		_spawn_water_splash(world_pos)
		if was_fire:
			_spawn_fire_burst(world_pos, 6)
	else:
		_spawn_ship_impact(world_pos, is_powder_crit)
		if was_fire:
			_spawn_fire_burst(world_pos, 14)
			if hit_ship_id >= 0:
				_burning_ships[hit_ship_id] = { "timer": 4.0, "emit_accum": 0.0 }
		if was_harpoon and hit_ship_id >= 0:
			_harpoon_tethers.append({
				"start_ship_id": int(consumed.get("shooter_id", -1)),
				"end_ship_id": hit_ship_id,
				"start_pos": consumed.get("origin", world_pos),
				"end_pos": world_pos,
				"age": 0.0,
				"max_age": 0.55
			})


func _on_ship_state_updated(
	ship_id: int,
	world_pos: Vector2,
	_heading: float,
	_speed: float,
	_sail_state: int,
	_hp: float,
	_max_hp: float
) -> void:
	_ship_positions[ship_id] = world_pos


func _on_ship_damaged(_ship_id: int, damage: float, _new_hp: float, _max_hp: float, world_pos: Vector2) -> void:
	if damage <= 0.0:
		return
	for i in range(4):
		var ang: float = _rng.randf_range(0.0, TAU)
		_particles.append({
			"pos": world_pos,
			"vel": Vector2(cos(ang), sin(ang)) * _rng.randf_range(16.0, 38.0),
			"z": 6.0,
			"vz": _rng.randf_range(18.0, 34.0),
			"gravity": 95.0,
			"age": 0.0,
			"max_age": 0.35,
			"size": 2.0,
			"color": Color(0.98, 0.72, 0.28, 0.95),
			"outline": true
		})


func _on_ship_sunk(ship_id: int, world_pos: Vector2, _faction: int, _killer_ship_id: int) -> void:
	_burning_ships.erase(ship_id)
	_ship_positions.erase(ship_id)
	_rings.append({
		"pos": world_pos,
		"r_start": 6.0,
		"r_end": 44.0,
		"age": 0.0,
		"max_age": 0.95,
		"color": Color(0.95, 0.98, 1.0, 0.92)
	})
	_rings.append({
		"pos": world_pos,
		"r_start": 3.0,
		"r_end": 28.0,
		"age": 0.0,
		"max_age": 0.65,
		"color": Color(1.0, 0.65, 0.25, 0.90)
	})
	for i in range(22):
		var ang: float = _rng.randf_range(0.0, TAU)
		var is_wood: bool = (i % 3 != 0)
		_particles.append({
			"pos": world_pos + Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-8.0, 8.0)),
			"vel": Vector2(cos(ang), sin(ang)) * _rng.randf_range(18.0, 62.0),
			"z": 4.0,
			"vz": _rng.randf_range(26.0, 68.0),
			"gravity": 115.0,
			"age": 0.0,
			"max_age": _rng.randf_range(0.55, 0.95),
			"size": 3.0 if is_wood else 4.0,
			"color": Color(0.56, 0.34, 0.23, 1.0) if is_wood else Color(1.0, 0.56, 0.16, 1.0),
			"outline": is_wood
		})
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

	_loot_crates[loot_data.drop_id] = {
		"sprite": spr,
		"pos": loot_data.world_pos,
		"salvage": loot_data.is_salvage_target
	}


func _on_loot_collected(drop_id: int, _collector_ship_id: int, loot_data: Contracts.LootDropData) -> void:
	var burst_pos: Vector2 = loot_data.world_pos if loot_data != null else Vector2.ZERO
	if _loot_crates.has(drop_id):
		var entry: Dictionary = _loot_crates[drop_id]
		burst_pos = entry["pos"]
		var spr: Sprite2D = entry["sprite"]
		if is_instance_valid(spr):
			spr.queue_free()
		_loot_crates.erase(drop_id)

	_rings.append({
		"pos": burst_pos,
		"r_start": 4.0,
		"r_end": 22.0,
		"age": 0.0,
		"max_age": 0.45,
		"color": Color(0.98, 0.82, 0.25, 0.90)
	})
	for i in range(10):
		var ang: float = (float(i) / 10.0) * TAU
		_particles.append({
			"pos": burst_pos,
			"vel": Vector2(cos(ang), sin(ang)) * _rng.randf_range(18.0, 34.0),
			"z": 4.0,
			"vz": _rng.randf_range(24.0, 44.0),
			"gravity": 90.0,
			"age": 0.0,
			"max_age": 0.42,
			"size": 2.0,
			"color": Color(1.0, 0.88, 0.35, 1.0),
			"outline": true
		})


func _on_sea_monster_spawned(monster_id: int, world_pos: Vector2, max_hp: float) -> void:
	_sea_monsters[monster_id] = {
		"pos": world_pos,
		"hp": max_hp,
		"max_hp": maxf(1.0, max_hp),
		"phase": 0,
		"hit_flash": 0.0,
		"foam_timer": 0.0
	}
	_rings.append({
		"pos": world_pos,
		"r_start": 8.0,
		"r_end": 48.0,
		"age": 0.0,
		"max_age": 0.85,
		"color": Color(0.36, 0.94, 0.86, 0.92)
	})


func _on_sea_monster_updated(monster_id: int, world_pos: Vector2, hp: float, max_hp: float, phase: int) -> void:
	if not _sea_monsters.has(monster_id):
		_on_sea_monster_spawned(monster_id, world_pos, max_hp)
	var m: Dictionary = _sea_monsters[monster_id]
	var prev_hp: float = float(m["hp"])
	m["pos"] = world_pos
	m["hp"] = hp
	m["max_hp"] = maxf(1.0, max_hp)
	m["phase"] = phase
	if hp < prev_hp - 0.5:
		m["hit_flash"] = 0.14
		for i in range(6):
			var ang: float = _rng.randf_range(0.0, TAU)
			_particles.append({
				"pos": world_pos,
				"vel": Vector2(cos(ang), sin(ang)) * _rng.randf_range(16.0, 40.0),
				"z": 4.0,
				"vz": _rng.randf_range(20.0, 42.0),
				"gravity": 100.0,
				"age": 0.0,
				"max_age": 0.38,
				"size": 3.0,
				"color": Color(0.76, 0.24, 0.52, 0.95),
				"outline": true
			})


func _on_sea_monster_defeated(monster_id: int, world_pos: Vector2) -> void:
	_sea_monsters.erase(monster_id)
	_rings.append({
		"pos": world_pos,
		"r_start": 6.0,
		"r_end": 58.0,
		"age": 0.0,
		"max_age": 1.0,
		"color": Color(0.42, 0.96, 0.88, 0.95)
	})
	for i in range(26):
		var ang: float = _rng.randf_range(0.0, TAU)
		_particles.append({
			"pos": world_pos + Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-10.0, 10.0)),
			"vel": Vector2(cos(ang), sin(ang)) * _rng.randf_range(22.0, 74.0),
			"z": 5.0,
			"vz": _rng.randf_range(28.0, 72.0),
			"gravity": 115.0,
			"age": 0.0,
			"max_age": _rng.randf_range(0.55, 1.0),
			"size": 4.0 if (i % 2 == 0) else 3.0,
			"color": Color(0.68, 0.22, 0.48, 1.0) if (i % 3 != 0) else Color(0.42, 0.94, 0.88, 1.0),
			"outline": true
		})
	_trigger_camera_trauma_if_near(world_pos, 0.55, 600.0)


func _on_fort_spawned(fort_id: int, world_pos: Vector2, island_index: int, max_hp: float) -> void:
	_forts[fort_id] = {
		"pos": world_pos,
		"island_index": island_index,
		"hp": max_hp,
		"max_hp": maxf(1.0, max_hp),
		"aim_angle": 0.0,
		"hit_flash": 0.0,
		"fire_flash": 0.0
	}


func _on_fort_damaged(fort_id: int, hp: float, max_hp: float, world_pos: Vector2) -> void:
	if not _forts.has(fort_id):
		_on_fort_spawned(fort_id, world_pos, -1, max_hp)
	var f: Dictionary = _forts[fort_id]
	f["hp"] = hp
	f["max_hp"] = maxf(1.0, max_hp)
	f["pos"] = world_pos
	f["hit_flash"] = 0.14
	for i in range(6):
		var ang: float = _rng.randf_range(0.0, TAU)
		_particles.append({
			"pos": world_pos,
			"vel": Vector2(cos(ang), sin(ang)) * _rng.randf_range(16.0, 38.0),
			"z": 6.0,
			"vz": _rng.randf_range(18.0, 40.0),
			"gravity": 110.0,
			"age": 0.0,
			"max_age": 0.42,
			"size": 3.0,
			"color": Color(0.68, 0.64, 0.70, 1.0) if (i % 2 == 0) else Color(1.0, 0.58, 0.16, 1.0),
			"outline": true
		})


func _on_fort_destroyed(fort_id: int, world_pos: Vector2) -> void:
	_forts.erase(fort_id)
	_rings.append({
		"pos": world_pos,
		"r_start": 6.0,
		"r_end": 46.0,
		"age": 0.0,
		"max_age": 0.85,
		"color": Color(1.0, 0.62, 0.22, 0.94)
	})
	_spawn_fire_burst(world_pos, 18)
	for i in range(14):
		var ang: float = _rng.randf_range(0.0, TAU)
		_particles.append({
			"pos": world_pos,
			"vel": Vector2(cos(ang), sin(ang)) * _rng.randf_range(20.0, 64.0),
			"z": 6.0,
			"vz": _rng.randf_range(30.0, 74.0),
			"gravity": 120.0,
			"age": 0.0,
			"max_age": _rng.randf_range(0.55, 0.95),
			"size": 4.0,
			"color": Color(0.54, 0.50, 0.56, 1.0),
			"outline": true
		})
	_trigger_camera_trauma_if_near(world_pos, 0.50, 560.0)


func _on_lightning_flash(world_pos: Vector2) -> void:
	var segs: Array[Vector2] = []
	var cur := world_pos + Vector2(_rng.randf_range(-18.0, 18.0), -140.0)
	segs.append(cur.round())
	for step in range(1, 7):
		var t: float = float(step) / 7.0
		var next_p: Vector2 = cur.lerp(world_pos, t) + Vector2(_rng.randf_range(-12.0, 12.0), 0.0)
		segs.append(next_p.round())
	segs.append(world_pos.round())

	_lightning_bolts.append({
		"segments": segs,
		"age": 0.0,
		"max_age": 0.28
	})
	_rings.append({
		"pos": world_pos,
		"r_start": 3.0,
		"r_end": 26.0,
		"age": 0.0,
		"max_age": 0.45,
		"color": Color(0.84, 0.96, 1.0, 0.92)
	})
	_trigger_camera_trauma_if_near(world_pos, 0.28, 480.0)


func _spawn_fire_burst(world_pos: Vector2, count: int) -> void:
	for i in range(count):
		var ang: float = _rng.randf_range(0.0, TAU)
		var fcol := Color(1.0, 0.42, 0.12, 1.0) if (i % 2 == 0) else Color(1.0, 0.86, 0.28, 1.0)
		_particles.append({
			"pos": world_pos + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-4.0, 4.0)),
			"vel": Vector2(cos(ang), sin(ang)) * _rng.randf_range(12.0, 44.0),
			"z": 4.0,
			"vz": _rng.randf_range(16.0, 42.0),
			"gravity": 35.0,
			"age": 0.0,
			"max_age": _rng.randf_range(0.32, 0.58),
			"size": _rng.randf_range(2.5, 4.0),
			"color": fcol,
			"outline": true
		})


func _spawn_water_splash(world_pos: Vector2) -> void:
	_rings.append({
		"pos": world_pos,
		"r_start": 2.0,
		"r_end": 18.0,
		"age": 0.0,
		"max_age": 0.55,
		"color": Color(0.95, 0.99, 1.0, 0.88)
	})
	_rings.append({
		"pos": world_pos,
		"r_start": 1.0,
		"r_end": 11.0,
		"age": 0.0,
		"max_age": 0.40,
		"color": Color(0.45, 0.89, 0.88, 0.80)
	})
	for i in range(10):
		var ang: float = _rng.randf_range(0.0, TAU)
		_particles.append({
			"pos": world_pos,
			"vel": Vector2(cos(ang), sin(ang)) * _rng.randf_range(8.0, 26.0),
			"z": 1.0,
			"vz": _rng.randf_range(34.0, 62.0),
			"gravity": 165.0,
			"age": 0.0,
			"max_age": _rng.randf_range(0.32, 0.52),
			"size": 2.0,
			"color": Color(0.95, 0.98, 1.0, 0.95) if (i % 2 == 0) else Color(0.55, 0.90, 0.92, 0.90),
			"outline": false
		})


func _spawn_ship_impact(world_pos: Vector2, is_powder_crit: bool) -> void:
	var count: int = 20 if is_powder_crit else 10
	_rings.append({
		"pos": world_pos,
		"r_start": 3.0,
		"r_end": 30.0 if is_powder_crit else 16.0,
		"age": 0.0,
		"max_age": 0.50 if is_powder_crit else 0.32,
		"color": Color(1.0, 0.45, 0.16, 0.95) if is_powder_crit else Color(1.0, 0.78, 0.38, 0.85)
	})

	for i in range(count):
		var ang: float = _rng.randf_range(0.0, TAU)
		var is_fire: bool = (i % 2 == 0)
		var spd: float = _rng.randf_range(24.0, 72.0 if is_powder_crit else 46.0)
		var p_col := Color(0.72, 0.44, 0.31, 1.0)
		if is_fire:
			p_col = Color(1.0, 0.42, 0.14, 1.0) if is_powder_crit else Color(1.0, 0.76, 0.28, 1.0)
		_particles.append({
			"pos": world_pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"z": 5.0,
			"vz": _rng.randf_range(22.0, 58.0),
			"gravity": 115.0,
			"age": 0.0,
			"max_age": _rng.randf_range(0.32, 0.65),
			"size": 3.0 if is_powder_crit else 2.0,
			"color": p_col,
			"outline": true
		})

	for j in range(4 if is_powder_crit else 2):
		_particles.append({
			"pos": world_pos + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-4.0, 4.0)),
			"vel": Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-16.0, -6.0)),
			"z": 7.0,
			"vz": 6.0,
			"gravity": 0.0,
			"age": 0.0,
			"max_age": 0.55,
			"size": 5.0 if is_powder_crit else 4.0,
			"color": Color(0.24, 0.22, 0.25, 0.78),
			"outline": false
		})

	if is_powder_crit:
		_hitstop_timer = 0.045
		_trigger_camera_trauma_if_near(world_pos, 0.42, 520.0)
	else:
		_hitstop_timer = 0.022
		_trigger_camera_trauma_if_near(world_pos, 0.16, 420.0)


func _consume_nearest_projectile(world_pos: Vector2) -> Dictionary:
	var best_idx: int = -1
	var best_dist_sq: float = 34.0 * 34.0
	for i in range(_projectiles.size()):
		var p: Vector2 = _projectiles[i]["pos"]
		var d2: float = p.distance_squared_to(world_pos)
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
	if vp == null:
		return
	var cam := vp.get_camera_2d()
	if cam == null:
		return
	if cam.global_position.distance_to(world_pos) <= max_dist:
		if cam.has_method("add_trauma"):
			cam.add_trauma(amount)

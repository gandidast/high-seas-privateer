class_name ShipStackRenderer
extends Node2D
## Renders a ship in crisp 2D pixel-art diorama style using 24 tightly stacked Sprite2D layers,
## 3 distinct ship classes (Sloop / Brigantine / Frigate), waterline foam, bow wave,
## stern wake trail, and 360-degree rotating deck modules.

const LAYER_COUNT: int = 24
const LAYER_Y_STEP: float = -0.75
const LAYER_SCALE: float = 1.0
const OUTLINE_COLOR := Color(0.094, 0.078, 0.145, 1.0) # #181425

var ship_id: int = 0
var faction: int = Contracts.ShipFaction.PLAYER
var ship_name: String = ""
var hull_tier: int = Contracts.ShipClass.SLOOP

var _world_pos: Vector2 = Vector2.ZERO
var _heading: float = 0.0
var _prev_heading: float = 0.0
var _speed: float = 0.0
var _sail_state: int = Contracts.SailState.ANCHORED
var _hp: float = 100.0
var _max_hp: float = 100.0

var _time_accum: float = 0.0
var _bob_phase: float = 0.0
var _roll_amount: float = 0.0
var _hit_flash_timer: float = 0.0
var _muzzle_flashes: Array[Dictionary] = []

var _stack_root: Node2D
var _layer_sprites: Array[Sprite2D] = []
var _modules_root: Node2D
var _module_entries: Array[Dictionary] = []
var _sail_layer_range: Vector2i = ProceduralShipBaker.get_sail_layer_range(LAYER_COUNT)

var _wake_line: Line2D
var _wake_world_points: Array[Vector2] = []
var _wake_sample_timer: float = 0.0
var _foam_dots: Array[Dictionary] = []
var _foam_spawn_timer: float = 0.0

var _name_label: Label


func _ready() -> void:
	_ensure_nodes()
	_connect_signals()


func _connect_signals() -> void:
	var bus: Contracts = Contracts.bus()
	if bus == null:
		return
	if not bus.ship_class_upgraded.is_connected(_on_ship_class_upgraded):
		bus.ship_class_upgraded.connect(_on_ship_class_upgraded)
	if not bus.ship_stats_compiled.is_connected(_on_ship_stats_compiled):
		bus.ship_stats_compiled.connect(_on_ship_stats_compiled)


func _ensure_nodes() -> void:
	if _stack_root != null:
		return

	_wake_line = Line2D.new()
	_wake_line.name = "WakeLine"
	_wake_line.width = 4.5
	_wake_line.default_color = Color(0.753, 0.941, 0.949, 0.45)
	_wake_line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_wake_line.joint_mode = Line2D.LINE_JOINT_SHARP
	_wake_line.begin_cap_mode = Line2D.LINE_CAP_BOX
	_wake_line.end_cap_mode = Line2D.LINE_CAP_BOX
	_wake_line.z_index = -2
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.97, 0.98, 0.0))
	grad.set_color(1, Color(0.95, 0.99, 1.0, 0.55))
	_wake_line.gradient = grad
	add_child(_wake_line)

	_stack_root = Node2D.new()
	_stack_root.name = "SpriteStack"
	add_child(_stack_root)

	_modules_root = Node2D.new()
	_modules_root.name = "DeckModules"
	add_child(_modules_root)

	_name_label = Label.new()
	_name_label.name = "ShipNameplate"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.08, 0.90))
	_name_label.add_theme_constant_override("outline_size", 1)
	_name_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.03, 0.06, 0.75))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.position = Vector2(-58.0, -37.0)
	_name_label.custom_minimum_size = Vector2(116.0, 15.0)
	_name_label.z_index = 32
	add_child(_name_label)


func setup_ship(p_ship_id: int, p_faction: int, p_name: String = "", p_hull_tier: int = 0) -> void:
	_ensure_nodes()
	ship_id = p_ship_id
	faction = p_faction
	ship_name = p_name
	hull_tier = clampi(p_hull_tier, 0, 2)
	_bob_phase = float(p_ship_id % 97) * 0.73
	_rebuild_layer_stack()
	_update_nameplate()


func set_hull_tier(tier: int) -> void:
	var clamped: int = clampi(tier, 0, 2)
	if clamped == hull_tier and not _layer_sprites.is_empty():
		return
	hull_tier = clamped
	_ensure_nodes()
	_rebuild_layer_stack()
	_apply_stack_transforms(0.0)


func _rebuild_layer_stack() -> void:
	for spr in _layer_sprites:
		if is_instance_valid(spr):
			spr.queue_free()
	_layer_sprites.clear()

	_sail_layer_range = ProceduralShipBaker.get_sail_layer_range(LAYER_COUNT)
	var textures: Array[ImageTexture] = ProceduralShipBaker.bake_ship_layers(faction, LAYER_COUNT, hull_tier)
	for i in range(textures.size()):
		var spr := Sprite2D.new()
		spr.name = "Layer_%02d" % i
		spr.texture = textures[i]
		spr.centered = true
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(LAYER_SCALE, LAYER_SCALE)
		spr.z_index = i
		spr.position = Vector2(0.0, float(i) * LAYER_Y_STEP).round()
		_stack_root.add_child(spr)
		_layer_sprites.append(spr)


func update_transform_state(world_pos: Vector2, heading: float, speed: float, sail_state: int, hp: float = 100.0, max_hp: float = 100.0) -> void:
	_ensure_nodes()
	_world_pos = world_pos
	position = world_pos.round()
	_prev_heading = _heading
	_heading = heading
	_speed = speed
	_sail_state = sail_state
	_hp = hp
	_max_hp = maxf(1.0, max_hp)
	_update_nameplate()


func update_equipped_modules(equipped_items: Array) -> void:
	_ensure_nodes()
	for entry in _module_entries:
		var spr: Sprite2D = entry["sprite"]
		if is_instance_valid(spr):
			spr.queue_free()
	_module_entries.clear()

	var hull_len_span: float = [11.5, 15.0, 18.5][clampi(hull_tier, 0, 2)]
	var rail_y: float = [5.8, 7.4, 9.0][clampi(hull_tier, 0, 2)]
	var deck_layer: float = round(0.42 * float(LAYER_COUNT - 1))

	for raw_item in equipped_items:
		var cat: int = Contracts.ItemCategory.CARGO
		var rarity: int = Contracts.ItemRarity.COMMON
		var affix: int = Contracts.ItemAffix.STANDARD
		var gx: int = 3
		var gy: int = 2
		var eff_w: int = 1
		var eff_h: int = 1
		var slot_type: int = -1

		if raw_item is Dictionary:
			var d: Dictionary = raw_item
			cat = int(d.get("category", Contracts.ItemCategory.CARGO))
			rarity = int(d.get("rarity", Contracts.ItemRarity.COMMON))
			affix = int(d.get("affix", Contracts.ItemAffix.STANDARD))
			gx = int(d.get("grid_x", d.get("x", 3)))
			gy = int(d.get("grid_y", d.get("y", 2)))
			eff_w = maxi(1, int(d.get("width", 1)))
			eff_h = maxi(1, int(d.get("height", 1)))
			if bool(d.get("rotated", false)):
				var tmp := eff_w
				eff_w = eff_h
				eff_h = tmp
			slot_type = int(d.get("slot_type", -1))
		elif raw_item is Contracts.GridItemData:
			var item: Contracts.GridItemData = raw_item
			cat = item.category
			rarity = item.rarity
			affix = item.affix
			gx = item.grid_pos.x
			gy = item.grid_pos.y
			var sz: Vector2i = item.get_effective_size()
			eff_w = maxi(1, sz.x)
			eff_h = maxi(1, sz.y)
		else:
			continue

		if gx < 0 or gy < 0:
			continue

		var cx: float = float(gx) + float(eff_w - 1) * 0.5
		var cy: float = float(gy) + float(eff_h - 1) * 0.5
		var local_x: float = lerpf(-hull_len_span, hull_len_span, clampf(cx / 7.0, 0.0, 1.0))
		var local_y: float = 0.0
		var local_rot: float = 0.0
		var stack_layer: float = deck_layer

		var on_port: bool = (slot_type == Contracts.SlotType.DECK_PORT) or (gy == 0)
		var on_starboard: bool = (slot_type == Contracts.SlotType.DECK_STARBOARD) or (gy + eff_h - 1 >= 5)
		var on_mast: bool = (slot_type == Contracts.SlotType.MAST) or (cat == Contracts.ItemCategory.SAIL)

		if on_port and not on_starboard:
			local_y = -rail_y
			stack_layer = deck_layer + 1.0
			if cat == Contracts.ItemCategory.CANNON:
				local_rot = -PI * 0.5
		elif on_starboard and not on_port:
			local_y = rail_y
			stack_layer = deck_layer + 1.0
			if cat == Contracts.ItemCategory.CANNON:
				local_rot = PI * 0.5
		elif on_mast:
			local_y = 0.0
			stack_layer = float(_sail_layer_range.x)
		else:
			local_y = lerpf(-rail_y * 0.45, rail_y * 0.45, clampf((cy - 1.0) / 3.0, 0.0, 1.0))
			stack_layer = deck_layer - 1.0

		var tex: ImageTexture = ProceduralShipBaker.bake_module_texture(cat, rarity, affix)
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.centered = true
		spr.scale = Vector2(0.56, 0.56)
		spr.z_index = int(round(stack_layer))
		_modules_root.add_child(spr)

		_module_entries.append({
			"sprite": spr,
			"local_offset": Vector2(local_x, local_y),
			"local_rot": local_rot,
			"stack_layer": stack_layer
		})

	_apply_stack_transforms(0.0)


func trigger_muzzle_flash(is_starboard: bool) -> void:
	var side_sign: float = 1.0 if is_starboard else -1.0
	var rail_dist: float = [8.5, 10.5, 12.5][clampi(hull_tier, 0, 2)]
	for offset_x in [-7.0, 2.0, 10.0]:
		_muzzle_flashes.append({
			"local_pos": Vector2(offset_x, side_sign * rail_dist),
			"side_sign": side_sign,
			"age": 0.0,
			"duration": 0.22
		})
	_roll_amount = clampf(_roll_amount - side_sign * 1.5, -2.4, 2.4)
	queue_redraw()


func trigger_hit_flash() -> void:
	_hit_flash_timer = 0.14


func _process(delta: float) -> void:
	_time_accum += delta
	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)

	var turn_delta: float = wrapf(_heading - _prev_heading, -PI, PI)
	_prev_heading = _heading
	var target_roll: float = clampf(turn_delta * 18.0, -1.8, 1.8) + sin(_time_accum * 2.1 + _bob_phase) * 0.65
	_roll_amount = lerpf(_roll_amount, target_roll, minf(1.0, delta * 8.0))

	var bob_y: float = sin(_time_accum * 2.8 + _bob_phase) * 0.65
	_apply_stack_transforms(bob_y)
	_update_wake_and_foam(delta)
	_update_muzzle_flashes(delta)
	queue_redraw()


func _apply_stack_transforms(bob_y: float) -> void:
	var perp := Vector2(-sin(_heading), cos(_heading))
	var sail_scale_x: float = 1.0
	if _sail_state == Contracts.SailState.ANCHORED:
		sail_scale_x = 0.48
	elif _sail_state == Contracts.SailState.HALF_SAIL:
		sail_scale_x = 0.78
	elif _sail_state == Contracts.SailState.FULL_SAIL:
		sail_scale_x = 1.06

	var flash_tint: Color = Color(1.9, 1.4, 1.1, 1.0) if _hit_flash_timer > 0.0 else Color.WHITE

	for i in range(_layer_sprites.size()):
		var spr: Sprite2D = _layer_sprites[i]
		var height_frac: float = float(i) / float(maxi(1, _layer_sprites.size() - 1))
		var roll_shift: Vector2 = perp * (_roll_amount * height_frac * 0.85)
		spr.rotation = _heading
		spr.position = Vector2(roll_shift.x, float(i) * LAYER_Y_STEP + bob_y + roll_shift.y).round()
		spr.modulate = flash_tint
		if i >= _sail_layer_range.x and i <= _sail_layer_range.y:
			spr.scale = Vector2(LAYER_SCALE * sail_scale_x, LAYER_SCALE)
		else:
			spr.scale = Vector2(LAYER_SCALE, LAYER_SCALE)

	for entry in _module_entries:
		var mspr: Sprite2D = entry["sprite"]
		if not is_instance_valid(mspr):
			continue
		var local_off: Vector2 = entry["local_offset"]
		var stack_layer: float = float(entry["stack_layer"])
		var height_frac: float = stack_layer / float(maxi(1, LAYER_COUNT - 1))
		var roll_shift: Vector2 = perp * (_roll_amount * height_frac * 0.85)
		var world_off: Vector2 = local_off.rotated(_heading)
		mspr.position = Vector2(
			world_off.x + roll_shift.x,
			world_off.y + stack_layer * LAYER_Y_STEP + bob_y + roll_shift.y
		).round()
		mspr.rotation = _heading + float(entry["local_rot"])
		mspr.modulate = flash_tint


func _hull_size_factor() -> float:
	return [0.90, 1.10, 1.32][clampi(hull_tier, 0, 2)]


func _update_wake_and_foam(delta: float) -> void:
	var scale_f: float = _hull_size_factor()
	var forward := Vector2(cos(_heading), sin(_heading))
	var stern_world: Vector2 = _world_pos - forward * (21.0 * scale_f)

	_wake_sample_timer += delta
	if _wake_sample_timer >= 0.06:
		_wake_sample_timer = 0.0
		if _speed > 4.0:
			_wake_world_points.append(stern_world)
			if _wake_world_points.size() > 18:
				_wake_world_points.pop_front()
		elif _wake_world_points.size() > 0:
			_wake_world_points.pop_front()

	if _wake_line != null:
		var local_pts := PackedVector2Array()
		for wp in _wake_world_points:
			local_pts.append((wp - position).round())
		_wake_line.points = local_pts

	_foam_spawn_timer += delta
	if _speed > 8.0 and _foam_spawn_timer >= 0.055:
		_foam_spawn_timer = 0.0
		var perp := Vector2(-forward.y, forward.x)
		var bow_world: Vector2 = _world_pos + forward * (22.0 * scale_f)
		for side in [-1.0, 1.0]:
			_foam_dots.append({
				"world_pos": bow_world + perp * (side * 2.5 * scale_f),
				"vel": (-forward * 8.0 + perp * side * 12.0),
				"age": 0.0,
				"max_age": 0.45,
				"size": 2.0
			})
		_foam_dots.append({
			"world_pos": stern_world + perp * randf_range(-3.0, 3.0),
			"vel": -forward * 4.0,
			"age": 0.0,
			"max_age": 0.65,
			"size": 2.0
		})

	var idx: int = _foam_dots.size() - 1
	while idx >= 0:
		var dot: Dictionary = _foam_dots[idx]
		dot["age"] = float(dot["age"]) + delta
		dot["world_pos"] = (dot["world_pos"] as Vector2) + (dot["vel"] as Vector2) * delta
		if float(dot["age"]) >= float(dot["max_age"]):
			_foam_dots.remove_at(idx)
		idx -= 1


func _update_muzzle_flashes(delta: float) -> void:
	var idx: int = _muzzle_flashes.size() - 1
	while idx >= 0:
		var mf: Dictionary = _muzzle_flashes[idx]
		mf["age"] = float(mf["age"]) + delta
		if float(mf["age"]) >= float(mf["duration"]):
			_muzzle_flashes.remove_at(idx)
		idx -= 1


func _draw() -> void:
	var scale_f: float = _hull_size_factor()
	var forward := Vector2(cos(_heading), sin(_heading))
	var perp := Vector2(-forward.y, forward.x)

	# 1. Animated Layer 0 waterline pixel foam ring
	var ring_steps: int = 22
	var pulse: float = 0.75 + 0.25 * sin(_time_accum * 3.2 + _bob_phase)
	for i in range(ring_steps):
		var t: float = (float(i) / float(ring_steps)) * TAU
		var lx: float = cos(t) * (22.0 * scale_f)
		var ly: float = sin(t) * (9.0 * scale_f)
		if (i + int(_time_accum * 4.0)) % 2 == 0:
			var pt: Vector2 = (forward * lx + perp * ly).round()
			draw_rect(Rect2(pt, Vector2(2.0, 2.0)), Color(0.92, 0.98, 0.99, 0.45 * pulse))

	# 2. Crisp V-shaped bow wave when sailing
	if _speed > 6.0:
		var speed_ratio: float = clampf(_speed / 95.0, 0.2, 1.2)
		var bow_tip: Vector2 = forward * (22.0 * scale_f)
		var left_wing: Vector2 = bow_tip - forward * (9.0 * speed_ratio) - perp * (7.5 * speed_ratio * scale_f)
		var right_wing: Vector2 = bow_tip - forward * (9.0 * speed_ratio) + perp * (7.5 * speed_ratio * scale_f)
		var bow_col := Color(0.96, 0.99, 1.0, 0.85)
		draw_line(bow_tip.round(), left_wing.round(), bow_col, 1.5, false)
		draw_line(bow_tip.round(), right_wing.round(), bow_col, 1.5, false)

	# 3. Pixel foam dots in wake
	for dot in _foam_dots:
		var alpha: float = 1.0 - float(dot["age"]) / float(dot["max_age"])
		var local_p: Vector2 = ((dot["world_pos"] as Vector2) - position).round()
		var sz: float = float(dot["size"])
		draw_rect(Rect2(local_p, Vector2(sz, sz)), Color(0.93, 0.98, 1.0, alpha * 0.75))

	# 4. Muzzle flashes & smoke puffs on deck layer
	for mf in _muzzle_flashes:
		var t: float = float(mf["age"]) / float(mf["duration"])
		var local_p: Vector2 = (mf["local_pos"] as Vector2).rotated(_heading) + Vector2(0.0, -7.0)
		var out_dir: Vector2 = perp * float(mf["side_sign"])
		if t < 0.45:
			var flash_pos: Vector2 = (local_p + out_dir * (t * 10.0)).round()
			draw_rect(Rect2(flash_pos - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.62, 0.16, 0.95))
			draw_rect(Rect2(flash_pos - Vector2(1, 1), Vector2(3, 3)), Color(1.0, 0.96, 0.78, 1.0))
		var smoke_pos: Vector2 = (local_p + out_dir * (3.0 + t * 18.0) + Vector2(0.0, -t * 6.0)).round()
		var smoke_sz: float = 4.0 + t * 5.0
		draw_rect(
			Rect2(smoke_pos - Vector2(smoke_sz * 0.5, smoke_sz * 0.5), Vector2(smoke_sz, smoke_sz)),
			Color(0.86, 0.86, 0.88, (1.0 - t) * 0.72)
		)

	# 5. Crisp pixel HP bar above ship when damaged or enemy/NPC
	if _hp < _max_hp or faction != Contracts.ShipFaction.PLAYER:
		var bar_w: float = 30.0 if hull_tier == 0 else (34.0 if hull_tier == 1 else 38.0)
		var bar_h: float = 3.0
		var bar_pos := Vector2(-bar_w * 0.5, -24.0).round()
		var ratio: float = clampf(_hp / _max_hp, 0.0, 1.0)
		draw_rect(Rect2(bar_pos - Vector2(1, 1), Vector2(bar_w + 2.0, bar_h + 2.0)), OUTLINE_COLOR)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.22, 0.14, 0.16, 0.92))
		var fill_col := Color(0.32, 0.82, 0.36) if faction == Contracts.ShipFaction.PLAYER else Color(0.86, 0.25, 0.25)
		if faction == Contracts.ShipFaction.MERCHANT:
			fill_col = Color(0.95, 0.78, 0.25)
		elif faction == Contracts.ShipFaction.NAVY:
			fill_col = Color(0.38, 0.66, 0.98)
		draw_rect(Rect2(bar_pos, Vector2(floor(bar_w * ratio), bar_h)), fill_col)


func _update_nameplate() -> void:
	if _name_label == null:
		return
	if ship_name.is_empty():
		_name_label.visible = false
		return
	_name_label.visible = true
	_name_label.text = ship_name
	match faction:
		Contracts.ShipFaction.PIRATE:
			_name_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.48, 1.0))
		Contracts.ShipFaction.MERCHANT:
			_name_label.add_theme_color_override("font_color", Color(0.99, 0.90, 0.48, 1.0))
		Contracts.ShipFaction.NAVY:
			_name_label.add_theme_color_override("font_color", Color(0.60, 0.82, 1.0, 1.0))
		_:
			_name_label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.90, 1.0))


func _on_ship_class_upgraded(p_ship_id: int, new_hull_tier: int, _class_title: String) -> void:
	if p_ship_id == ship_id:
		set_hull_tier(new_hull_tier)


func _on_ship_stats_compiled(p_ship_id: int, stats: Contracts.ShipStats) -> void:
	if p_ship_id == ship_id and stats != null and stats.hull_tier != hull_tier:
		set_hull_tier(stats.hull_tier)

class_name MinimapRenderer
extends Control
## Crisp chart-style Minimap widget for HudOverlay.
## Covers the full world (2 * WORLD_HALF_EXTENT), distinguishes Safe Harbors from Wild Islands,
## bakes static ocean/islands once per seed, and toggles WorldMapOverlay on click.

signal world_map_toggle_requested

const CARD_SIZE: Vector2 = Vector2(270.0, 316.0)
const MAP_RECT: Rect2 = Rect2(11.0, 11.0, 248.0, 240.0)
const MAP_W: int = 248
const MAP_H: int = 240
const MAP_CENTER: Vector2 = Vector2(124.0, 120.0)

var player_ship: Node = null
var combat_system_ref: CombatSystem = null
var loot_system_ref: LootSystem = null
var all_ships_ref: Dictionary = {}
var tracked_forts: Dictionary = {}
var tracked_sea_monster: Dictionary = {}
var active_quests: Array = []
var pulse_time: float = 0.0

var _baked_seed: int = -999999
var _baked_island_count: int = -1
var _baked_extent: float = -1.0
var _baked_map_tex: ImageTexture = null
var _fort_tex: ImageTexture = null
var _player_tex: ImageTexture = null
var _kraken_poly: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	_ensure_icons()
	_build_legend_labels()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			world_map_toggle_requested.emit()
			accept_event()


static func _get_scale_f() -> float:
	return minf(float(MAP_W), float(MAP_H)) * 0.47 / Contracts.WORLD_HALF_EXTENT


func bake_static_map(world_seed: int, islands: Array) -> void:
	if _baked_map_tex != null and _baked_seed == world_seed and _baked_island_count == islands.size() and is_equal_approx(_baked_extent, Contracts.WORLD_HALF_EXTENT):
		return
	_baked_seed = world_seed
	_baked_island_count = islands.size()
	_baked_extent = Contracts.WORLD_HALF_EXTENT
	var scale_f: float = _get_scale_f()

	var img := Image.create(MAP_W, MAP_H, false, Image.FORMAT_RGBA8)
	var ocean_col := Color(0.06, 0.14, 0.24, 0.96)
	img.fill(ocean_col)
	var cross_col := ocean_col.lerp(Color(0.28, 0.48, 0.66, 0.96), 0.22)
	for x in range(4, MAP_W - 4):
		img.set_pixel(x, int(MAP_CENTER.y), cross_col)
	for y in range(4, MAP_H - 4):
		img.set_pixel(int(MAP_CENTER.x), y, cross_col)

	for isl_var in islands:
		var isl: Contracts.IslandData = isl_var
		if isl == null:
			continue
		var ic: Vector2 = MAP_CENTER + isl.center * scale_f
		var r_px: int = int(ceil((isl.radius * 1.35 + 140.0) * scale_f))
		for py in range(maxi(0, int(floor(ic.y)) - r_px), mini(MAP_H - 1, int(ceil(ic.y)) + r_px) + 1):
			for px in range(maxi(0, int(floor(ic.x)) - r_px), mini(MAP_W - 1, int(ceil(ic.x)) + r_px) + 1):
				var d: float = Contracts.get_water_depth((Vector2(float(px) + 0.5, float(py) + 0.5) - MAP_CENTER) / scale_f, world_seed)
				if d <= -0.55:
					img.set_pixel(px, py, Color(0.20, 0.40, 0.24, 1.0))
				elif d <= -0.18:
					img.set_pixel(px, py, Color(0.24, 0.52, 0.26, 1.0))
				elif d <= 0.0:
					img.set_pixel(px, py, Color(0.84, 0.72, 0.46, 1.0))
				elif d <= 0.22:
					img.set_pixel(px, py, Color(0.11, 0.34, 0.44, 0.96))

	# Distinct Safe Harbor anchor/diamond marker ONLY on safe harbors
	var harbor_emerald := Color(0.26, 0.90, 0.56, 1.0)
	for isl_var in islands:
		var isl: Contracts.IslandData = isl_var
		if isl == null or not isl.has_harbor:
			continue
		var hp: Vector2 = (MAP_CENTER + isl.harbor_pos * scale_f).round()
		for dy_off in range(-3, 4):
			for dx_off in range(-3, 4):
				var manhattan: int = absi(dx_off) + absi(dy_off)
				if manhattan > 3:
					continue
				var dx: int = int(hp.x) + dx_off
				var dy: int = int(hp.y) + dy_off
				if dx < 0 or dx >= MAP_W or dy < 0 or dy >= MAP_H:
					continue
				if manhattan <= 1:
					img.set_pixel(dx, dy, UIThemeHelper.COL_GOLD)
				elif manhattan == 2:
					img.set_pixel(dx, dy, harbor_emerald)
				else:
					img.set_pixel(dx, dy, UIThemeHelper.COL_OUTLINE)

	_baked_map_tex = ImageTexture.create_from_image(img)
	queue_redraw()


func _ensure_icons() -> void:
	if _fort_tex != null and _player_tex != null:
		return
	var fort_img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	fort_img.fill(Color(0, 0, 0, 0))
	for y in range(1, 6):
		for x in range(1, 6):
			var corner: bool = (x == 1 or x == 5) and (y == 1 or y == 5)
			var border: bool = (x == 1 or x == 5 or y == 1 or y == 5) and not corner
			fort_img.set_pixel(x, y, UIThemeHelper.COL_OUTLINE if border else Color(0.98, 0.54, 0.20))
	_fort_tex = ImageTexture.create_from_image(fort_img)

	var p_img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	p_img.fill(Color(0, 0, 0, 0))
	for y in range(2, 5):
		for x in range(2, 5):
			p_img.set_pixel(x, y, Color.WHITE)
	for pt in [Vector2i(3, 0), Vector2i(3, 6), Vector2i(0, 3), Vector2i(6, 3)]:
		p_img.set_pixel(pt.x, pt.y, UIThemeHelper.COL_OUTLINE)
	_player_tex = ImageTexture.create_from_image(p_img)


func _build_legend_labels() -> void:
	var lx: float = MAP_RECT.position.x
	var ly1: float = MAP_RECT.end.y + 7.0
	var ly2: float = ly1 + 20.0
	for entry in [
		[Vector2(lx + 12.0, ly1), "Du"], [Vector2(lx + 72.0, ly1), "Hafen"], [Vector2(lx + 158.0, ly1), "Pirat"],
		[Vector2(lx + 12.0, ly2), "Handel"], [Vector2(lx + 84.0, ly2), "Fort"], [Vector2(lx + 158.0, ly2), "Ziel"]
	]:
		var lbl: Label = UIThemeHelper.make_label(entry[1], 14, UIThemeHelper.COL_IVORY)
		lbl.position = (entry[0] as Vector2).round()
		add_child(lbl)

	var hint := UIThemeHelper.make_label("[M / Klick] Seekarte", 14, UIThemeHelper.COL_GOLD)
	hint.position = Vector2(lx, ly2 + 19.0).round()
	hint.size = Vector2(MAP_RECT.size.x, 20.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)


func _draw() -> void:
	_ensure_icons()
	UIThemeHelper.draw_chamfered_panel(self, Rect2(Vector2.ZERO, CARD_SIZE), UIThemeHelper.COL_HUD_PANEL_BG, UIThemeHelper.COL_BRASS, UIThemeHelper.COL_BRASS_DIM, 8.0)
	if _baked_map_tex != null:
		draw_texture_rect(_baked_map_tex, MAP_RECT, false)
	else:
		draw_rect(MAP_RECT, Color(0.06, 0.14, 0.24, 0.96), true)

	var mc: Vector2 = MAP_RECT.get_center()
	_draw_dynamic_forts_and_loot(mc)
	_draw_dynamic_ships(mc)
	_draw_dynamic_markers(mc)
	draw_rect(MAP_RECT, UIThemeHelper.COL_BRASS_DIM, false, 1.5)

	var lx: float = MAP_RECT.position.x
	var ly1: float = MAP_RECT.end.y + 11.0
	var ly2: float = ly1 + 20.0
	for entry in [
		[Vector2(lx, ly1), Color.WHITE],
		[Vector2(lx + 60.0, ly1), Color(0.26, 0.90, 0.56)],
		[Vector2(lx + 146.0, ly1), Color(0.94, 0.28, 0.26)],
		[Vector2(lx, ly2), Color(0.38, 0.76, 0.98)],
		[Vector2(lx + 72.0, ly2), Color(0.98, 0.54, 0.20)],
		[Vector2(lx + 146.0, ly2), UIThemeHelper.COL_TURQUOISE]
	]:
		var r := Rect2(entry[0] as Vector2, Vector2(8.0, 8.0))
		draw_rect(r, entry[1] as Color, true)
		draw_rect(r, UIThemeHelper.COL_OUTLINE, false, 1.0)


func _draw_dynamic_forts_and_loot(mc: Vector2) -> void:
	var scale_f: float = _get_scale_f()
	var has_combat_forts: bool = combat_system_ref != null and not combat_system_ref.forts.is_empty()
	var fort_list: Array = combat_system_ref.forts.values() if has_combat_forts else tracked_forts.values()
	for f_info_var in fort_list:
		var f_info: Dictionary = f_info_var
		if bool(f_info.get("destroyed", false)):
			continue
		var pos_val: Vector2 = f_info.get("world_pos", f_info.get("pos", Vector2.ZERO))
		var fp: Vector2 = (mc + pos_val * scale_f).round()
		if MAP_RECT.has_point(fp) and _fort_tex != null:
			draw_texture_rect(_fort_tex, Rect2((fp - Vector2(3.5, 3.5)).round(), Vector2(7.0, 7.0)), false)

	if loot_system_ref != null:
		for drop_var in loot_system_ref.drops.values():
			var d: Contracts.LootDropData = drop_var
			if d == null:
				continue
			var lp: Vector2 = (mc + d.world_pos * scale_f).round()
			if MAP_RECT.has_point(lp):
				var lcol: Color = Color(0.76, 0.44, 0.98) if d.quest_id == "ghost_wreck" else (UIThemeHelper.COL_TURQUOISE if d.is_salvage_target else Color(0.95, 0.68, 0.22))
				draw_rect(Rect2(lp - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), lcol)


func _draw_dynamic_ships(mc: Vector2) -> void:
	var scale_f: float = _get_scale_f()
	for ship_var in all_ships_ref.values():
		var s: Node = ship_var
		if s == null or s == player_ship or bool(s.get("is_sunk")):
			continue
		var sp: Vector2 = (mc + s.get("world_pos") * scale_f).round()
		if not MAP_RECT.has_point(sp):
			continue
		var fac: int = int(s.get("faction"))
		var scol: Color = Color(0.94, 0.28, 0.26)
		var dot_size: float = 5.0
		if fac == Contracts.ShipFaction.MERCHANT:
			var is_galleon: bool = bool(s.get_meta("is_treasure_galleon", false))
			scol = UIThemeHelper.COL_GOLD if is_galleon else Color(0.38, 0.76, 0.98)
			dot_size = 7.0 if is_galleon else 5.0
		elif fac == Contracts.ShipFaction.NAVY:
			scol = Color(0.32, 0.56, 0.98)
			dot_size = 6.0
		elif fac == Contracts.ShipFaction.PLAYER:
			scol = Color(0.45, 0.95, 0.48)
		var half_d: float = floor(dot_size * 0.5)
		draw_rect(Rect2(sp - Vector2(half_d + 1.0, half_d + 1.0), Vector2(dot_size + 2.0, dot_size + 2.0)), UIThemeHelper.COL_OUTLINE)
		draw_rect(Rect2(sp - Vector2(half_d, half_d), Vector2(dot_size, dot_size)), scol)


func _draw_dynamic_markers(mc: Vector2) -> void:
	var scale_f: float = _get_scale_f()
	if bool(tracked_sea_monster.get("active", false)):
		var mp: Vector2 = (mc + tracked_sea_monster.get("pos", Vector2.ZERO) * scale_f).round().clamp(MAP_RECT.position + Vector2(9.0, 9.0), MAP_RECT.end - Vector2(9.0, 9.0))
		draw_arc(mp, 8.0 + 3.0 * sin(pulse_time * 6.0), 0.0, TAU, 18, Color(0.98, 0.30, 0.75, 0.85), 1.5)
		_kraken_poly[0] = mp + Vector2(0.0, -7.0); _kraken_poly[1] = mp + Vector2(7.0, 0.0)
		_kraken_poly[2] = mp + Vector2(0.0, 7.0); _kraken_poly[3] = mp + Vector2(-7.0, 0.0)
		draw_colored_polygon(_kraken_poly, Color(0.96, 0.22, 0.62))

	if not active_quests.is_empty():
		var q: Contracts.QuestData = active_quests[0]
		var tpos: Vector2 = q.target_pos
		if q.quest_type == Contracts.QuestType.BOUNTY and q.target_ship_id != -1 and all_ships_ref.has(q.target_ship_id):
			var boss: Node = all_ships_ref[q.target_ship_id]
			if boss != null and not bool(boss.get("is_sunk")):
				tpos = boss.get("world_pos")
		var qp: Vector2 = (mc + tpos * scale_f).round().clamp(MAP_RECT.position + Vector2(6.0, 6.0), MAP_RECT.end - Vector2(6.0, 6.0))
		draw_rect(Rect2(qp - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), Color(1.0, 0.90, 0.20, 0.55 + 0.45 * sin(pulse_time * 5.0)), false, 2.0)

	if player_ship != null:
		var pp: Vector2 = (mc + player_ship.get("world_pos") * scale_f).round().clamp(MAP_RECT.position + Vector2(4.0, 4.0), MAP_RECT.end - Vector2(4.0, 4.0))
		if _player_tex != null:
			draw_texture_rect(_player_tex, Rect2((pp - Vector2(3.5, 3.5)).round(), Vector2(7.0, 7.0)), false)
		draw_line(pp, (pp + Vector2.from_angle(float(player_ship.get("heading"))) * 11.0).round(), UIThemeHelper.COL_GOLD, 2.0)

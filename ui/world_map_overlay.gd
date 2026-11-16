class_name WorldMapOverlay
extends Control
## Fullscreen toggleable Nautical Sea Chart Overlay ([M] or Minimap click).
## Renders the entire 7200x7200 sea, all 8 islands with Safe Harbor vs Wild/Fort
## badges, live ships, active forts, Kraken, loot/ghost wrecks, quest routes,
## coordinate grid, compass rose, and island directory legend.

signal map_toggled(open: bool)

const PANEL_SIZE: Vector2 = Vector2(880.0, 648.0)
const MAP_REL: Rect2 = Rect2(14.0, 52.0, 580.0, 580.0)
const SIDEBAR_REL: Rect2 = Rect2(608.0, 52.0, 258.0, 580.0)
const CLOSE_BTN_REL: Rect2 = Rect2(716.0, 7.0, 150.0, 30.0)
const MAP_PX: int = 580

var player_ship: Node = null
var combat_system_ref: CombatSystem = null
var loot_system_ref: LootSystem = null
var all_ships_ref: Dictionary = {}
var tracked_forts: Dictionary = {}
var tracked_sea_monster: Dictionary = {}
var active_quests: Array = []
var islands_ref: Array = []
var pulse_time: float = 0.0

var _baked_seed: int = -999999
var _baked_island_count: int = -1
var _baked_tex: ImageTexture = null
var _hover_close: bool = false
var _cursor_screen_pos: Vector2 = Vector2(-9999.0, -9999.0)
var _ship_tri: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _kraken_poly: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false


func set_open(open: bool) -> void:
	if visible == open:
		return
	visible = open
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	map_toggled.emit(visible)
	if visible:
		queue_redraw()


func toggle_map() -> void:
	set_open(not visible)


func _unhandled_input(event: InputEvent) -> void:
	var toggle_pressed: bool = false
	if InputMap.has_action("toggle_world_map") and event.is_action_pressed("toggle_world_map"):
		toggle_pressed = true
	elif event is InputEventKey and event.pressed and not event.echo:
		var kev := event as InputEventKey
		if kev.keycode == KEY_M:
			toggle_pressed = true
		elif visible and kev.keycode == KEY_ESCAPE:
			set_open(false)
			get_viewport().set_input_as_handled()
			return

	if visible and not toggle_pressed and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
		return

	if toggle_pressed:
		toggle_map()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	var panel_pos: Vector2 = _get_panel_pos()
	if event is InputEventMouseMotion:
		_cursor_screen_pos = (event as InputEventMouseMotion).position
		_hover_close = Rect2(panel_pos + CLOSE_BTN_REL.position, CLOSE_BTN_REL.size).has_point(_cursor_screen_pos)
		queue_redraw()
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var close_rect := Rect2(panel_pos + CLOSE_BTN_REL.position, CLOSE_BTN_REL.size)
			var panel_rect := Rect2(panel_pos, PANEL_SIZE)
			if close_rect.has_point(mb.position) or not panel_rect.has_point(mb.position):
				set_open(false)
			accept_event()


func bake_static_map(world_seed: int, islands: Array) -> void:
	islands_ref = islands.duplicate()
	if _baked_tex != null and _baked_seed == world_seed and _baked_island_count == islands.size():
		return
	_baked_seed = world_seed
	_baked_island_count = islands.size()

	var scale_f: float = float(MAP_PX) / (Contracts.WORLD_HALF_EXTENT * 2.0)
	var center_px := Vector2(float(MAP_PX) * 0.5, float(MAP_PX) * 0.5)

	var img := Image.create(MAP_PX, MAP_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.055, 0.135, 0.235, 1.0))

	# Subtle open-sea depth bands
	for isl_var in islands:
		var isl: Contracts.IslandData = isl_var
		if isl == null:
			continue
		var ic: Vector2 = center_px + isl.center * scale_f
		var r_px: int = int(ceil((isl.radius * 1.40 + 165.0) * scale_f))
		for py in range(maxi(0, int(floor(ic.y)) - r_px), mini(MAP_PX - 1, int(ceil(ic.y)) + r_px) + 1):
			for px in range(maxi(0, int(floor(ic.x)) - r_px), mini(MAP_PX - 1, int(ceil(ic.x)) + r_px) + 1):
				var wpos: Vector2 = (Vector2(float(px) + 0.5, float(py) + 0.5) - center_px) / scale_f
				var d: float = Contracts.get_water_depth(wpos, world_seed)
				if d <= -0.55:
					img.set_pixel(px, py, Color(0.20, 0.38, 0.23, 1.0))
				elif d <= -0.18:
					img.set_pixel(px, py, Color(0.25, 0.52, 0.27, 1.0))
				elif d <= 0.0:
					img.set_pixel(px, py, Color(0.84, 0.72, 0.46, 1.0))
				elif d <= 0.10:
					img.set_pixel(px, py, Color(0.18, 0.48, 0.56, 1.0))
				elif d <= 0.22:
					img.set_pixel(px, py, Color(0.10, 0.30, 0.42, 1.0))

	_baked_tex = ImageTexture.create_from_image(img)
	if visible:
		queue_redraw()


func _get_vp_size() -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return Vector2(1280.0, 720.0)
	return vp


func _get_panel_pos() -> Vector2:
	return ((_get_vp_size() - PANEL_SIZE) * 0.5).floor()


func _world_to_chart(wpos: Vector2, map_rect: Rect2) -> Vector2:
	var scale_f: float = map_rect.size.x / (Contracts.WORLD_HALF_EXTENT * 2.0)
	return map_rect.get_center() + wpos * scale_f


func _chart_to_world(cpos: Vector2, map_rect: Rect2) -> Vector2:
	var scale_f: float = map_rect.size.x / (Contracts.WORLD_HALF_EXTENT * 2.0)
	return (cpos - map_rect.get_center()) / scale_f


func _draw() -> void:
	if not visible:
		return
	var vp_size: Vector2 = _get_vp_size()
	var panel_pos: Vector2 = _get_panel_pos()
	var font: Font = UIThemeHelper.get_font()

	draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.02, 0.03, 0.06, 0.78), true)
	UIThemeHelper.draw_framed_panel(self, Rect2(panel_pos, PANEL_SIZE), UIThemeHelper.COL_PANEL_BG, UIThemeHelper.COL_BRASS, UIThemeHelper.COL_BRASS_DIM)

	# Header
	var header_rect := Rect2(panel_pos + Vector2(4.0, 4.0), Vector2(PANEL_SIZE.x - 8.0, 40.0))
	draw_rect(header_rect, UIThemeHelper.COL_HEADER_BG, true)
	draw_line(Vector2(header_rect.position.x, header_rect.end.y), Vector2(header_rect.end.x, header_rect.end.y), UIThemeHelper.COL_BRASS_DIM, 1.5)
	UIThemeHelper.draw_sharp_text(self, font, panel_pos + Vector2(16.0, 31.0), "SEEKARTE DER KARIBIK (7200 × 7200)", 19, UIThemeHelper.COL_GOLD)

	var close_rect := Rect2(panel_pos + CLOSE_BTN_REL.position, CLOSE_BTN_REL.size)
	var close_bg: Color = Color(0.64, 0.23, 0.21, 1.0) if _hover_close else Color(0.42, 0.17, 0.16, 0.95)
	UIThemeHelper.draw_clean_box(self, close_rect, close_bg, UIThemeHelper.COL_BRASS)
	UIThemeHelper.draw_sharp_text(self, font, close_rect.position + Vector2(0.0, 21.0), "[M / ESC] Schließen", 14, UIThemeHelper.COL_IVORY, HORIZONTAL_ALIGNMENT_CENTER, int(close_rect.size.x))

	var map_rect := Rect2((panel_pos + MAP_REL.position).round(), MAP_REL.size)
	var side_rect := Rect2((panel_pos + SIDEBAR_REL.position).round(), SIDEBAR_REL.size)

	_draw_chart(map_rect, font)
	_draw_sidebar(side_rect, map_rect, font)


func _draw_chart(map_rect: Rect2, font: Font) -> void:
	if _baked_tex != null:
		draw_texture_rect(_baked_tex, map_rect, false)
	else:
		draw_rect(map_rect, Color(0.055, 0.135, 0.235, 1.0), true)

	# Coordinate grid every 1200 world units
	var grid_col := Color(0.36, 0.56, 0.74, 0.22)
	var axis_col := Color(0.48, 0.70, 0.86, 0.34)
	for coord in [-2400.0, -1200.0, 0.0, 1200.0, 2400.0]:
		var p_h: Vector2 = _world_to_chart(Vector2(0.0, coord), map_rect)
		var p_v: Vector2 = _world_to_chart(Vector2(coord, 0.0), map_rect)
		var col: Color = axis_col if is_zero_approx(coord) else grid_col
		draw_line(Vector2(map_rect.position.x, p_h.y), Vector2(map_rect.end.x, p_h.y), col, 1.0)
		draw_line(Vector2(p_v.x, map_rect.position.y), Vector2(p_v.x, map_rect.end.y), col, 1.0)
		if not is_zero_approx(coord):
			UIThemeHelper.draw_sharp_text(self, font, Vector2(p_v.x + 3.0, map_rect.position.y + 14.0), "%d" % int(coord), 14, Color(0.64, 0.78, 0.88, 0.65), HORIZONTAL_ALIGNMENT_LEFT, -1, 1)
			UIThemeHelper.draw_sharp_text(self, font, Vector2(map_rect.position.x + 4.0, p_h.y - 4.0), "%d" % int(coord), 14, Color(0.64, 0.78, 0.88, 0.65), HORIZONTAL_ALIGNMENT_LEFT, -1, 1)

	# Compass rose in top-right corner of chart
	var rose_c := Vector2(map_rect.end.x - 32.0, map_rect.position.y + 32.0)
	draw_circle(rose_c, 20.0, Color(0.05, 0.07, 0.12, 0.78))
	draw_arc(rose_c, 20.0, 0.0, TAU, 24, UIThemeHelper.COL_BRASS_DIM, 1.5)
	draw_line(rose_c + Vector2(0.0, -16.0), rose_c + Vector2(0.0, 16.0), UIThemeHelper.COL_BRASS_DIM, 1.0)
	draw_line(rose_c + Vector2(-16.0, 0.0), rose_c + Vector2(16.0, 0.0), UIThemeHelper.COL_BRASS_DIM, 1.0)
	UIThemeHelper.draw_sharp_text(self, font, rose_c + Vector2(-5.0, -7.0), "N", 14, UIThemeHelper.COL_GOLD)

	# Fort status lookup by island_index
	var fort_sources: Dictionary = _collect_forts()
	var island_fort_alive: Dictionary = {}
	for f_info_var in fort_sources.values():
		var f_info: Dictionary = f_info_var
		var idx: int = int(f_info.get("island_index", -1))
		if idx >= 0 and not bool(f_info.get("destroyed", false)):
			island_fort_alive[idx] = true

	# Safe Harbor circles & Wild Island badges + Island Names
	var scale_f: float = map_rect.size.x / (Contracts.WORLD_HALF_EXTENT * 2.0)
	for isl_var in islands_ref:
		var isl: Contracts.IslandData = isl_var
		if isl == null:
			continue
		var ic: Vector2 = _world_to_chart(isl.center, map_rect)
		if isl.has_harbor:
			var hp: Vector2 = _world_to_chart(isl.harbor_pos, map_rect)
			var hr: float = maxf(9.0, isl.harbor_radius * scale_f)
			draw_circle(hp, hr, Color(0.24, 0.88, 0.54, 0.16))
			draw_arc(hp, hr, 0.0, TAU, 20, Color(0.28, 0.94, 0.58, 0.85), 1.5)
			draw_rect(Rect2(hp - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), UIThemeHelper.COL_GOLD, true)
			draw_rect(Rect2(hp - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), UIThemeHelper.COL_OUTLINE, false, 1.0)

		var badge_col: Color = Color(0.26, 0.90, 0.56) if isl.has_harbor else Color(0.95, 0.44, 0.34)
		var sub_txt: String = "SICHERER HAFEN" if isl.has_harbor else ("WILDNIS / FORT" if bool(island_fort_alive.get(isl.index, false)) else "WILDNIS")
		var label_pos: Vector2 = (ic + Vector2(-72.0, -maxf(18.0, isl.radius * scale_f) - 24.0)).clamp(map_rect.position + Vector2(6.0, 6.0), map_rect.end - Vector2(150.0, 38.0)).round()
		var pill_rect := Rect2(label_pos, Vector2(144.0, 32.0))
		UIThemeHelper.draw_clean_box(self, pill_rect, Color(0.06, 0.07, 0.11, 0.84), badge_col)
		UIThemeHelper.draw_sharp_text(self, font, label_pos + Vector2(4.0, 15.0), isl.name, 14, UIThemeHelper.COL_IVORY, HORIZONTAL_ALIGNMENT_CENTER, 136)
		UIThemeHelper.draw_sharp_text(self, font, label_pos + Vector2(4.0, 29.0), sub_txt, 14, badge_col, HORIZONTAL_ALIGNMENT_CENTER, 136)

	# Active forts
	for f_info_var in fort_sources.values():
		var f_info: Dictionary = f_info_var
		var fp: Vector2 = _world_to_chart(f_info.get("pos", Vector2.ZERO), map_rect)
		if not map_rect.has_point(fp):
			continue
		if bool(f_info.get("destroyed", false)):
			draw_rect(Rect2(fp - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), Color(0.45, 0.42, 0.40, 0.70), true)
		else:
			draw_rect(Rect2(fp - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), Color(0.98, 0.52, 0.20), true)
			draw_rect(Rect2(fp - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), UIThemeHelper.COL_OUTLINE, false, 1.5)

	# Loot & Ghost Wrecks
	if loot_system_ref != null:
		for drop_var in loot_system_ref.drops.values():
			var d: Contracts.LootDropData = drop_var
			if d == null:
				continue
			var lp: Vector2 = _world_to_chart(d.world_pos, map_rect)
			if not map_rect.has_point(lp):
				continue
			var lcol: Color = Color(0.76, 0.44, 0.98) if d.quest_id == "ghost_wreck" else (UIThemeHelper.COL_TURQUOISE if d.is_salvage_target else Color(0.95, 0.68, 0.22))
			draw_rect(Rect2(lp - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), lcol, true)
			draw_rect(Rect2(lp - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), UIThemeHelper.COL_OUTLINE, false, 1.0)

	# Active quest routes & target rings
	var player_chart_pos: Vector2 = _world_to_chart(player_ship.get("world_pos"), map_rect) if player_ship != null else Vector2.ZERO
	for qi in range(active_quests.size()):
		var q: Contracts.QuestData = active_quests[qi]
		if q == null:
			continue
		var tpos: Vector2 = q.target_pos
		if q.quest_type == Contracts.QuestType.BOUNTY and q.target_ship_id != -1 and all_ships_ref.has(q.target_ship_id):
			var boss: Node = all_ships_ref[q.target_ship_id]
			if boss != null and not bool(boss.get("is_sunk")):
				tpos = boss.get("world_pos")
		var qp: Vector2 = _world_to_chart(tpos, map_rect).clamp(map_rect.position + Vector2(8.0, 8.0), map_rect.end - Vector2(8.0, 8.0))
		if player_ship != null:
			_draw_dashed_line(player_chart_pos.clamp(map_rect.position, map_rect.end), qp, Color(1.0, 0.88, 0.30, 0.72), 2.0, 10.0)
		var ring_r: float = 9.0 + 3.0 * sin(pulse_time * 5.0 + float(qi))
		draw_arc(qp, ring_r, 0.0, TAU, 24, UIThemeHelper.COL_GOLD, 2.0)
		UIThemeHelper.draw_sharp_text(self, font, (qp + Vector2(10.0, -4.0)).clamp(map_rect.position, map_rect.end - Vector2(120.0, 18.0)), q.title.left(18), 14, UIThemeHelper.COL_GOLD)

	# Other ships
	for ship_var in all_ships_ref.values():
		var s: Node = ship_var
		if s == null or s == player_ship or bool(s.get("is_sunk")):
			continue
		var sp: Vector2 = _world_to_chart(s.get("world_pos"), map_rect)
		if not map_rect.has_point(sp):
			continue
		var fac: int = int(s.get("faction"))
		var scol: Color = Color(0.94, 0.28, 0.26)
		var r_sz: float = 4.0
		if fac == Contracts.ShipFaction.MERCHANT:
			var is_gal: bool = bool(s.get_meta("is_treasure_galleon", false))
			scol = UIThemeHelper.COL_GOLD if is_gal else Color(0.38, 0.76, 0.98)
			r_sz = 5.0 if is_gal else 4.0
		elif fac == Contracts.ShipFaction.NAVY:
			scol = Color(0.32, 0.56, 0.98)
			r_sz = 4.5
		elif fac == Contracts.ShipFaction.PLAYER:
			scol = Color(0.45, 0.95, 0.48)
			r_sz = 4.5
		var fwd := Vector2.from_angle(float(s.get("heading")))
		draw_line(sp, sp + fwd * (r_sz + 5.0), scol, 1.5)
		draw_circle(sp, r_sz + 1.0, UIThemeHelper.COL_OUTLINE)
		draw_circle(sp, r_sz, scol)

	# Kraken
	if bool(tracked_sea_monster.get("active", false)):
		var mp: Vector2 = _world_to_chart(tracked_sea_monster.get("pos", Vector2.ZERO), map_rect).clamp(map_rect.position + Vector2(10.0, 10.0), map_rect.end - Vector2(10.0, 10.0))
		draw_arc(mp, 11.0 + 3.0 * sin(pulse_time * 6.0), 0.0, TAU, 22, Color(0.98, 0.30, 0.75, 0.9), 2.0)
		_kraken_poly[0] = mp + Vector2(0.0, -8.0); _kraken_poly[1] = mp + Vector2(8.0, 0.0)
		_kraken_poly[2] = mp + Vector2(0.0, 8.0); _kraken_poly[3] = mp + Vector2(-8.0, 0.0)
		draw_colored_polygon(_kraken_poly, Color(0.96, 0.22, 0.62))
		UIThemeHelper.draw_sharp_text(self, font, mp + Vector2(10.0, 5.0), "KRAKEN", 14, Color(1.0, 0.52, 0.84))

	# Player ship with heading arrow
	if player_ship != null:
		var pp: Vector2 = player_chart_pos.clamp(map_rect.position + Vector2(8.0, 8.0), map_rect.end - Vector2(8.0, 8.0))
		var hdg: float = float(player_ship.get("heading"))
		var fwd := Vector2.from_angle(hdg)
		var side := fwd.rotated(PI * 0.5)
		draw_arc(pp, 11.0 + 2.0 * sin(pulse_time * 4.0), 0.0, TAU, 20, Color(1.0, 0.95, 0.70, 0.55), 1.5)
		_ship_tri[0] = pp + fwd * 10.0
		_ship_tri[1] = pp - fwd * 6.0 + side * 6.0
		_ship_tri[2] = pp - fwd * 6.0 - side * 6.0
		draw_colored_polygon(_ship_tri, Color.WHITE)
		draw_line(_ship_tri[0], _ship_tri[1], UIThemeHelper.COL_OUTLINE, 1.5)
		draw_line(_ship_tri[1], _ship_tri[2], UIThemeHelper.COL_OUTLINE, 1.5)
		draw_line(_ship_tri[2], _ship_tri[0], UIThemeHelper.COL_OUTLINE, 1.5)
		UIThemeHelper.draw_sharp_text(self, font, pp + Vector2(10.0, 5.0), "DU", 14, UIThemeHelper.COL_GOLD)

	draw_rect(map_rect, UIThemeHelper.COL_BRASS, false, 2.0)


func _draw_sidebar(side_rect: Rect2, map_rect: Rect2, font: Font) -> void:
	UIThemeHelper.draw_framed_panel(self, side_rect, UIThemeHelper.COL_PANEL_INSET, UIThemeHelper.COL_BRASS_DIM, Color(0.22, 0.18, 0.14, 0.55))
	var x: float = side_rect.position.x + 12.0
	var y: float = side_rect.position.y + 24.0
	var w: float = side_rect.size.x - 24.0

	UIThemeHelper.draw_sharp_text(self, font, Vector2(x, y), "LEGENDE", 16, UIThemeHelper.COL_GOLD)
	y += 18.0
	var legend_items: Array = [
		[Color.WHITE, "Dein Schiff (Kurs)"],
		[Color(0.26, 0.90, 0.56), "Sicherer Hafen (3)"],
		[Color(0.98, 0.52, 0.20), "Wildes Fort / Insel (5)"],
		[Color(0.94, 0.28, 0.26), "Piratenschiff"],
		[Color(0.38, 0.76, 0.98), "Händler / Gold-Galeone"],
		[Color(0.32, 0.56, 0.98), "Königliche Marine"],
		[Color(0.96, 0.22, 0.62), "Riesenkrake"],
		[UIThemeHelper.COL_GOLD, "Aktive Quest-Route"],
		[Color(0.76, 0.44, 0.98), "Geisterwrack / Beute"]
	]
	for entry in legend_items:
		draw_rect(Rect2(x, y - 9.0, 10.0, 10.0), entry[0] as Color, true)
		draw_rect(Rect2(x, y - 9.0, 10.0, 10.0), UIThemeHelper.COL_OUTLINE, false, 1.0)
		UIThemeHelper.draw_sharp_text(self, font, Vector2(x + 18.0, y), entry[1], 14, UIThemeHelper.COL_IVORY)
		y += 20.0

	y += 6.0
	draw_line(Vector2(x, y), Vector2(x + w, y), UIThemeHelper.COL_BRASS_DIM, 1.5)
	y += 22.0
	UIThemeHelper.draw_sharp_text(self, font, Vector2(x, y), "INSELN & HÄFEN (8)", 16, UIThemeHelper.COL_GOLD)
	y += 20.0

	for isl_var in islands_ref:
		var isl: Contracts.IslandData = isl_var
		if isl == null:
			continue
		var col: Color = Color(0.26, 0.90, 0.56) if isl.has_harbor else Color(0.95, 0.52, 0.36)
		var tag: String = "HAFEN" if isl.has_harbor else "WILD"
		UIThemeHelper.draw_sharp_text(self, font, Vector2(x, y), isl.name, 14, UIThemeHelper.COL_IVORY)
		UIThemeHelper.draw_sharp_text(self, font, Vector2(x, y), tag, 14, col, HORIZONTAL_ALIGNMENT_RIGHT, int(w))
		y += 20.0

	var footer_y: float = side_rect.end.y - 38.0
	draw_line(Vector2(x, footer_y - 14.0), Vector2(x + w, footer_y - 14.0), UIThemeHelper.COL_BRASS_DIM, 1.0)
	if player_ship != null:
		var ppos: Vector2 = player_ship.get("world_pos")
		UIThemeHelper.draw_sharp_text(self, font, Vector2(x, footer_y + 4.0), "Position: (%d, %d)" % [int(round(ppos.x)), int(round(ppos.y))], 14, UIThemeHelper.COL_TURQUOISE)
	if map_rect.has_point(_cursor_screen_pos):
		var cw: Vector2 = _chart_to_world(_cursor_screen_pos, map_rect)
		UIThemeHelper.draw_sharp_text(self, font, Vector2(x, footer_y + 24.0), "Cursor: (%d, %d)" % [int(round(cw.x)), int(round(cw.y))], 14, UIThemeHelper.COL_MUTED)
	else:
		UIThemeHelper.draw_sharp_text(self, font, Vector2(x, footer_y + 24.0), "Maus über Karte: Koord.", 14, UIThemeHelper.COL_MUTED)


func _collect_forts() -> Dictionary:
	var fort_sources: Dictionary = tracked_forts.duplicate(true)
	if combat_system_ref != null and not combat_system_ref.forts.is_empty():
		for fid_var in combat_system_ref.forts.keys():
			var f: Dictionary = combat_system_ref.forts[fid_var]
			fort_sources[int(fid_var)] = {
				"pos": f.get("world_pos", Vector2.ZERO),
				"destroyed": bool(f.get("destroyed", false)),
				"island_index": int(f.get("island_index", -1))
			}
	return fort_sources


func _draw_dashed_line(from: Vector2, to: Vector2, col: Color, width: float, seg_len: float) -> void:
	var diff: Vector2 = to - from
	var dist: float = diff.length()
	if dist < 2.0:
		return
	var dir: Vector2 = diff / dist
	var cur: float = 0.0
	while cur < dist:
		var next_end: float = minf(dist, cur + seg_len)
		draw_line(from + dir * cur, from + dir * next_end, col, width)
		cur += seg_len * 1.7

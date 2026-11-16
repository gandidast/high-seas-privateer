class_name HudOverlay
extends Control
## Crisp 1280x720+ HD nautical HUD (rendered outside the 640x360 SubViewport):
## - Top-left: Ship class, gold, hull HP bar, 3-stage sail bar (Anker / Halbe / Volle Segel),
##   and Port/Starboard reload bars.
## - Top-center: Weather, Royal Navy wanted stars, and active quest directional tracker.
## - Top-right: Chart-style Minimap with pixel-art icons and clear legend.
## - Bottom-center: Brass Compass & Windrose medallion with wind strength & heading readout.

const DEFAULT_VIEWPORT_W: float = 1280.0
const DEFAULT_VIEWPORT_H: float = 720.0
const COMPASS_RADIUS: float = 44.0

# Cohesive Navy / Mahogany / Brass / Ivory / Turquoise Palette
const COL_PANEL_BG: Color = Color(0.10, 0.09, 0.14, 0.90)
const COL_PANEL_INSET: Color = Color(0.07, 0.07, 0.11, 0.94)
const COL_BRASS: Color = Color(0.85, 0.66, 0.29, 0.95)       # #d8a94b
const COL_BRASS_DIM: Color = Color(0.46, 0.35, 0.18, 0.72)
const OUTLINE_COLOR: Color = Color(0.05, 0.04, 0.08, 0.85)
const SHADOW_COLOR: Color = Color(0.03, 0.03, 0.06, 0.72)
const COL_IVORY: Color = Color(0.97, 0.94, 0.88, 1.0)        # #f7f0e0
const COL_MUTED: Color = Color(0.75, 0.72, 0.68, 1.0)
const COL_GOLD: Color = Color(0.96, 0.79, 0.27, 1.0)         # #f6c945
const COL_TURQUOISE: Color = Color(0.40, 0.88, 0.92, 1.0)

var player_ship: Node = null
var world_map_ref: Node = null
var combat_system_ref: CombatSystem = null
var loot_system_ref: LootSystem = null
var all_ships_ref: Dictionary = {}

var wind_dir: Vector2 = Vector2(1.0, 0.25).normalized()
var wind_strength: float = 0.7
var _display_wind_angle: float = 0.0
var gold_amount: int = 120
var current_harbor_idx: int = -1
var current_harbor_name: String = ""
var active_quests: Array = []

var current_weather: int = Contracts.WeatherState.CLEAR
var wanted_level: int = 0
var _player_class_title: String = "Schaluppe"
var _tracked_forts: Dictionary = {}       # fort_id -> { "pos": Vector2, "destroyed": bool }
var _tracked_sea_monster: Dictionary = {} # { "pos": Vector2, "hp": float, "max_hp": float, "active": bool }

var _toast_text: String = ""
var _toast_timer: float = 0.0
var _pulse_time: float = 0.0

var _lbl_sail: Label = null
var _lbl_gold: Label = null
var _lbl_class: Label = null
var _lbl_hp: Label = null
var _lbl_broadsides: Label = null
var _lbl_weather: Label = null
var _lbl_wanted: Label = null
var _lbl_quest: Label = null
var _lbl_harbor: Label = null
var _lbl_toast: Label = null
var _lbl_controls: Label = null
var _lbl_controls_right: Label = null
var _minimap_icons: Dictionary = {}


func _bus() -> Contracts:
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		return st.root.get_node_or_null("EventBus") as Contracts
	return null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_minimap_icons()
	_build_labels()
	_sync_dynamic_layout()
	_connect_signals()


func setup(
	p_player_ship: Node,
	p_world_map: Node,
	p_combat_system: CombatSystem,
	p_loot_system: LootSystem,
	p_all_ships: Dictionary,
	p_starting_gold: int = 120
) -> void:
	player_ship = p_player_ship
	world_map_ref = p_world_map
	combat_system_ref = p_combat_system
	loot_system_ref = p_loot_system
	all_ships_ref = p_all_ships
	gold_amount = p_starting_gold
	_tracked_forts.clear()
	_tracked_sea_monster.clear()
	wanted_level = 0
	current_weather = Contracts.WeatherState.CLEAR

	if world_map_ref != null:
		var wd: Variant = world_map_ref.get("wind_direction")
		var ws: Variant = world_map_ref.get("wind_strength")
		if wd is Vector2:
			wind_dir = wd
		if ws is float or ws is int:
			wind_strength = float(ws)
		var cw: Variant = world_map_ref.get("current_weather")
		if cw is int:
			current_weather = cw

	if combat_system_ref != null:
		for fid_var in combat_system_ref.forts.keys():
			var f: Dictionary = combat_system_ref.forts[fid_var]
			_tracked_forts[int(fid_var)] = {
				"pos": f.get("world_pos", Vector2.ZERO),
				"destroyed": bool(f.get("destroyed", false))
			}

	_display_wind_angle = wind_dir.angle()


func set_ships_dict(p_ships: Dictionary) -> void:
	all_ships_ref = p_ships


func _process(delta: float) -> void:
	_pulse_time += delta
	var target_ang: float = wind_dir.angle()
	_display_wind_angle = lerp_angle(_display_wind_angle, target_ang, clampf(delta * 4.5, 0.0, 1.0))

	if _toast_timer > 0.0:
		_toast_timer = maxf(0.0, _toast_timer - delta)
		if _lbl_toast != null:
			_lbl_toast.visible = _toast_timer > 0.0
			_lbl_toast.modulate.a = clampf(_toast_timer, 0.0, 1.0)

	_sync_dynamic_layout()
	_update_labels()
	queue_redraw()


func _get_hud_size() -> Vector2:
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		vp_size = size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		return Vector2(DEFAULT_VIEWPORT_W, DEFAULT_VIEWPORT_H)
	return vp_size


func _get_top_bar_rect(vp_size: Vector2) -> Rect2:
	var bar_w: float = minf(520.0, maxf(320.0, vp_size.x - 696.0))
	var bar_x: float = clampf(round(vp_size.x * 0.5 - bar_w * 0.5), 436.0, maxf(436.0, vp_size.x - 248.0 - bar_w))
	return Rect2(bar_x, 16.0, bar_w, 44.0)


func _get_minimap_card_rect(vp_size: Vector2) -> Rect2:
	return Rect2(vp_size.x - 232.0, 16.0, 216.0, 268.0)


func _get_minimap_rect(card: Rect2) -> Rect2:
	return Rect2(card.position.x + 12.0, card.position.y + 12.0, 192.0, 184.0)


func _get_compass_center(vp_size: Vector2) -> Vector2:
	return Vector2(round(vp_size.x * 0.5), vp_size.y - 68.0)


func _draw() -> void:
	var vp_size: Vector2 = _get_hud_size()
	_draw_ship_panel()
	_draw_weather_wanted_bar(vp_size)
	_draw_quest_arrow(vp_size)
	_draw_minimap_and_legend(vp_size)
	_draw_bottom_compass_and_windrose(vp_size)
	_draw_toast_bg(vp_size)
	_draw_harbor_banner_bg(vp_size)


func _draw_chamfered_panel(rect: Rect2, fill: Color, border: Color = COL_BRASS, inner_border: Color = COL_BRASS_DIM, chamfer: float = 4.0) -> void:
	var x0: float = rect.position.x
	var y0: float = rect.position.y
	var x1: float = rect.end.x
	var y1: float = rect.end.y
	var c: float = minf(chamfer, minf(rect.size.x, rect.size.y) * 0.25)

	var poly := PackedVector2Array([
		Vector2(x0 + c, y0),
		Vector2(x1 - c, y0),
		Vector2(x1, y0 + c),
		Vector2(x1, y1 - c),
		Vector2(x1 - c, y1),
		Vector2(x0 + c, y1),
		Vector2(x0, y1 - c),
		Vector2(x0, y0 + c)
	])
	draw_colored_polygon(poly, fill)

	var closed := poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, border, 1.0, true)

	if rect.size.x > 10.0 and rect.size.y > 10.0:
		var ix0: float = x0 + 2.0
		var iy0: float = y0 + 2.0
		var ix1: float = x1 - 2.0
		var iy1: float = y1 - 2.0
		var ic: float = maxf(1.0, c - 1.0)
		var inner_poly := PackedVector2Array([
			Vector2(ix0 + ic, iy0),
			Vector2(ix1 - ic, iy0),
			Vector2(ix1, iy0 + ic),
			Vector2(ix1, iy1 - ic),
			Vector2(ix1 - ic, iy1),
			Vector2(ix0 + ic, iy1),
			Vector2(ix0, iy1 - ic),
			Vector2(ix0, iy0 + ic),
			Vector2(ix0 + ic, iy0)
		])
		draw_polyline(inner_poly, inner_border, 1.0, true)


func _draw_hud_text(
	font: Font,
	pos: Vector2,
	text: String,
	font_size: int,
	color: Color,
	align: int = HORIZONTAL_ALIGNMENT_LEFT,
	width: int = -1
) -> void:
	var p: Vector2 = pos.round()
	draw_string(font, p + Vector2(1.0, 2.0), text, align, width, font_size, SHADOW_COLOR)
	draw_string_outline(font, p, text, align, width, font_size, 2, OUTLINE_COLOR)
	draw_string(font, p, text, align, width, font_size, color)


func _draw_ship_panel() -> void:
	var box := Rect2(16.0, 16.0, 404.0, 156.0)
	_draw_chamfered_panel(box, COL_PANEL_BG, COL_BRASS, COL_BRASS_DIM, 8.0)
	var font: Font = ThemeDB.fallback_font

	var hp: float = 0.0
	var max_hp: float = 120.0
	var port_ready: float = 0.0
	var sb_ready: float = 0.0
	var sail_state: int = Contracts.SailState.ANCHORED

	if player_ship != null:
		hp = float(player_ship.get("hp"))
		max_hp = maxf(1.0, float(player_ship.get("max_hp")))
		sail_state = int(player_ship.get("sail_state"))
		var sid: int = int(player_ship.get("ship_id"))
		if combat_system_ref != null:
			var c_pt: Dictionary = combat_system_ref.get_broadside_cone(sid, false)
			var c_sb: Dictionary = combat_system_ref.get_broadside_cone(sid, true)
			port_ready = float(c_pt.get("ready_ratio", 0.0))
			sb_ready = float(c_sb.get("ready_ratio", 0.0))

	# Row 2: Hull HP Bar
	_draw_hud_text(font, Vector2(30.0, 67.0), "Rumpf", 15, COL_MUTED)
	var hp_rect := Rect2(96.0, 54.0, 212.0, 16.0)
	var hp_ratio: float = clampf(hp / max_hp, 0.0, 1.0)
	draw_rect(hp_rect, Color(0.14, 0.08, 0.09, 0.95), true)
	var hp_col: Color = Color(0.28, 0.80, 0.44) if hp_ratio > 0.35 else Color(0.92, 0.28, 0.26)
	var hp_fill_w: float = floor(hp_rect.size.x * hp_ratio)
	if hp_fill_w > 0.0:
		draw_rect(Rect2(hp_rect.position, Vector2(hp_fill_w, hp_rect.size.y)), hp_col, true)
		draw_rect(Rect2(hp_rect.position, Vector2(hp_fill_w, 3.0)), Color(1.0, 1.0, 1.0, 0.25), true)
	draw_rect(hp_rect, Color(0.36, 0.30, 0.24, 0.90), false, 1.5)

	# Row 3: 3-Stage Sail Bar (Anker | Halbe Segel | Volle Segel)
	var seg_x0: float = 240.0
	var seg_y: float = 84.0
	var seg_w: float = 50.0
	var seg_h: float = 16.0
	var seg_gap: float = 6.0
	for i in range(3):
		var sr := Rect2(seg_x0 + float(i) * (seg_w + seg_gap), seg_y, seg_w, seg_h)
		var active: bool = (i <= sail_state)
		var seg_col: Color = Color(0.14, 0.13, 0.19, 0.95)
		var seg_border: Color = Color(0.32, 0.28, 0.24, 0.80)
		if active:
			if sail_state == Contracts.SailState.ANCHORED:
				seg_col = Color(0.56, 0.46, 0.28, 0.95)
				seg_border = COL_BRASS
			elif sail_state == Contracts.SailState.HALF_SAIL:
				seg_col = Color(0.26, 0.68, 0.76, 0.95)
				seg_border = COL_TURQUOISE
			else:
				seg_col = Color(0.88, 0.68, 0.22, 0.95)
				seg_border = COL_GOLD
		draw_rect(sr, seg_col, true)
		draw_rect(sr, seg_border, false, 1.5)

	# Row 4: Port (Q) & Starboard (E) Broadside Reload Bars
	var pt_rect := Rect2(30.0, 140.0, 182.0, 14.0)
	var sb_rect := Rect2(224.0, 140.0, 182.0, 14.0)

	_draw_hud_text(font, Vector2(30.0, 132.0), "[Q] Backbord", 14, Color(0.62, 0.86, 1.0) if port_ready >= 0.99 else COL_MUTED)
	_draw_hud_text(font, Vector2(224.0, 132.0), "[E] Steuerbord", 14, Color(0.98, 0.68, 0.56) if sb_ready >= 0.99 else COL_MUTED)

	draw_rect(pt_rect, Color(0.11, 0.11, 0.16, 0.95), true)
	var pt_col: Color = COL_GOLD if port_ready >= 0.99 else Color(0.34, 0.64, 0.84)
	var pt_w: float = floor(pt_rect.size.x * clampf(port_ready, 0.0, 1.0))
	if pt_w > 0.0:
		draw_rect(Rect2(pt_rect.position, Vector2(pt_w, pt_rect.size.y)), pt_col, true)
		draw_rect(Rect2(pt_rect.position, Vector2(pt_w, 2.0)), Color(1.0, 1.0, 1.0, 0.25), true)
	draw_rect(pt_rect, COL_GOLD if port_ready >= 0.99 else Color(0.34, 0.30, 0.25), false, 1.5)

	draw_rect(sb_rect, Color(0.11, 0.11, 0.16, 0.95), true)
	var sb_col: Color = COL_GOLD if sb_ready >= 0.99 else Color(0.84, 0.44, 0.30)
	var sb_w: float = floor(sb_rect.size.x * clampf(sb_ready, 0.0, 1.0))
	if sb_w > 0.0:
		draw_rect(Rect2(sb_rect.position, Vector2(sb_w, sb_rect.size.y)), sb_col, true)
		draw_rect(Rect2(sb_rect.position, Vector2(sb_w, 2.0)), Color(1.0, 1.0, 1.0, 0.25), true)
	draw_rect(sb_rect, COL_GOLD if sb_ready >= 0.99 else Color(0.34, 0.30, 0.25), false, 1.5)


func _draw_weather_wanted_bar(vp_size: Vector2) -> void:
	var bar := _get_top_bar_rect(vp_size)
	_draw_chamfered_panel(bar, COL_PANEL_BG, COL_BRASS, COL_BRASS_DIM, 7.0)


func _draw_quest_arrow(vp_size: Vector2) -> void:
	if active_quests.is_empty() or player_ship == null:
		return
	var q: Contracts.QuestData = active_quests[0]
	var target_pos: Vector2 = _resolve_quest_target_pos(q)
	var player_pos: Vector2 = player_ship.get("world_pos")
	var to_target: Vector2 = target_pos - player_pos
	var dir: Vector2 = to_target.normalized() if to_target.length_squared() > 1.0 else Vector2.RIGHT

	var top_bar := _get_top_bar_rect(vp_size)
	var q_box := Rect2(top_bar.position.x, 68.0, top_bar.size.x, 46.0)
	_draw_chamfered_panel(q_box, COL_PANEL_BG, COL_BRASS, COL_BRASS_DIM, 7.0)

	var arrow_c := Vector2(q_box.position.x + 28.0, q_box.position.y + 23.0)
	draw_circle(arrow_c, 14.0, COL_PANEL_INSET)
	draw_arc(arrow_c, 14.0, 0.0, TAU, 24, COL_BRASS_DIM, 1.5)
	var tip: Vector2 = arrow_c + dir * 11.0
	var tail: Vector2 = arrow_c - dir * 8.0
	var perp: Vector2 = dir.rotated(PI * 0.5) * 5.5
	draw_line(tail, tip, COL_GOLD, 2.5)
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip - dir * 8.0 + perp,
		tip - dir * 8.0 - perp
	]), Color(1.0, 0.94, 0.65))


func _build_minimap_icons() -> void:
	_minimap_icons.clear()

	# 7x7 crisp pixel-art icons drawn with TEXTURE_FILTER_NEAREST
	var harbor_img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	harbor_img.fill(Color(0, 0, 0, 0))
	for y in range(1, 6):
		for x in range(1, 6):
			if absi(x - 3) + absi(y - 3) <= 2:
				var c: Color = COL_GOLD if (absi(x - 3) + absi(y - 3) <= 1) else OUTLINE_COLOR
				harbor_img.set_pixel(x, y, c)
	_minimap_icons["harbor"] = ImageTexture.create_from_image(harbor_img)

	var fort_img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	fort_img.fill(Color(0, 0, 0, 0))
	for y in range(1, 6):
		for x in range(1, 6):
			var border: bool = (x == 1 or x == 5 or y == 1 or y == 5)
			fort_img.set_pixel(x, y, OUTLINE_COLOR if border else Color(0.98, 0.54, 0.20))
	fort_img.set_pixel(1, 1, Color(0.98, 0.54, 0.20))
	fort_img.set_pixel(5, 1, Color(0.98, 0.54, 0.20))
	fort_img.set_pixel(1, 5, Color(0.98, 0.54, 0.20))
	fort_img.set_pixel(5, 5, Color(0.98, 0.54, 0.20))
	_minimap_icons["fort"] = ImageTexture.create_from_image(fort_img)

	var player_img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	player_img.fill(Color(0, 0, 0, 0))
	for y in range(1, 6):
		for x in range(1, 6):
			if absi(x - 3) <= 1 and absi(y - 3) <= 1:
				player_img.set_pixel(x, y, Color.WHITE)
	player_img.set_pixel(3, 0, OUTLINE_COLOR)
	player_img.set_pixel(3, 6, OUTLINE_COLOR)
	player_img.set_pixel(0, 3, OUTLINE_COLOR)
	player_img.set_pixel(6, 3, OUTLINE_COLOR)
	_minimap_icons["player"] = ImageTexture.create_from_image(player_img)


func _draw_minimap_pixel_icon(icon_key: String, center_pos: Vector2, scale_px: float = 2.0, modulate_col: Color = Color.WHITE) -> void:
	var tex: ImageTexture = _minimap_icons.get(icon_key, null)
	if tex == null:
		return
	var sz := Vector2(float(tex.get_width()) * scale_px, float(tex.get_height()) * scale_px).round()
	var top_left: Vector2 = (center_pos - sz * 0.5).round()
	draw_texture_rect(tex, Rect2(top_left, sz), false, modulate_col)


func _draw_minimap_and_legend(vp_size: Vector2) -> void:
	var minimap_card := _get_minimap_card_rect(vp_size)
	var minimap_rect := _get_minimap_rect(minimap_card)

	_draw_chamfered_panel(minimap_card, COL_PANEL_BG, COL_BRASS, COL_BRASS_DIM, 8.0)
	draw_rect(minimap_rect, Color(0.06, 0.14, 0.24, 0.96), true)

	# Subtle nautical chart grid crosshairs
	var mc: Vector2 = minimap_rect.get_center()
	draw_line(Vector2(minimap_rect.position.x + 4.0, mc.y), Vector2(minimap_rect.end.x - 4.0, mc.y), Color(0.28, 0.48, 0.66, 0.22), 1.0)
	draw_line(Vector2(mc.x, minimap_rect.position.y + 4.0), Vector2(mc.x, minimap_rect.end.y - 4.0), Color(0.28, 0.48, 0.66, 0.22), 1.0)

	var scale_f: float = (minimap_rect.size.x * 0.46) / 1150.0

	# Islands & Harbors
	var islands: Array = _get_islands()
	for isl_var in islands:
		var isl: Contracts.IslandData = isl_var
		var p: Vector2 = (mc + isl.center * scale_f).round()
		var r: float = maxf(6.0, isl.radius * scale_f)
		if minimap_rect.has_point(p):
			draw_circle(p, r + 2.0, Color(0.84, 0.72, 0.46))
			draw_circle(p, maxf(4.0, r - 3.0), Color(0.24, 0.52, 0.26))
		var hp_pos: Vector2 = (mc + isl.harbor_pos * scale_f).round()
		if minimap_rect.has_point(hp_pos):
			_draw_minimap_pixel_icon("harbor", hp_pos, 1.0)

	# Coastal Forts
	var fort_sources: Dictionary = _tracked_forts
	if combat_system_ref != null and not combat_system_ref.forts.is_empty():
		for fid_var in combat_system_ref.forts.keys():
			var f: Dictionary = combat_system_ref.forts[fid_var]
			fort_sources[int(fid_var)] = {
				"pos": f.get("world_pos", Vector2.ZERO),
				"destroyed": bool(f.get("destroyed", false))
			}

	for f_info_var in fort_sources.values():
		var f_info: Dictionary = f_info_var
		if bool(f_info.get("destroyed", false)):
			continue
		var fp: Vector2 = (mc + f_info.get("pos", Vector2.ZERO) * scale_f).round()
		if minimap_rect.has_point(fp):
			_draw_minimap_pixel_icon("fort", fp, 1.0)

	# Loot Drops
	if loot_system_ref != null:
		for drop_var in loot_system_ref.drops.values():
			var d: Contracts.LootDropData = drop_var
			if d == null:
				continue
			var lp: Vector2 = (mc + d.world_pos * scale_f).round()
			if minimap_rect.has_point(lp):
				var lcol: Color = COL_TURQUOISE if d.is_salvage_target else Color(0.95, 0.68, 0.22)
				if d.quest_id == "ghost_wreck":
					lcol = Color(0.76, 0.44, 0.98)
				draw_rect(Rect2(lp - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), lcol)

	# AI & Remote Ships
	for ship_var in all_ships_ref.values():
		var s: Node = ship_var
		if s == null or s == player_ship or bool(s.get("is_sunk")):
			continue
		var sp: Vector2 = (mc + s.get("world_pos") * scale_f).round()
		if not minimap_rect.has_point(sp):
			continue
		var fac: int = int(s.get("faction"))
		var scol: Color = Color(0.94, 0.28, 0.26)
		var dot_size: float = 6.0
		if fac == Contracts.ShipFaction.MERCHANT:
			var is_galleon: bool = bool(s.get_meta("is_treasure_galleon", false))
			scol = COL_GOLD if is_galleon else Color(0.38, 0.76, 0.98)
			dot_size = 8.0 if is_galleon else 6.0
		elif fac == Contracts.ShipFaction.NAVY:
			scol = Color(0.32, 0.56, 0.98)
			dot_size = 7.0
		elif fac == Contracts.ShipFaction.PLAYER:
			scol = Color(0.45, 0.95, 0.48)
		var half_d: float = floor(dot_size * 0.5)
		draw_rect(Rect2(sp - Vector2(half_d + 1.0, half_d + 1.0), Vector2(dot_size + 2.0, dot_size + 2.0)), OUTLINE_COLOR)
		draw_rect(Rect2(sp - Vector2(half_d, half_d), Vector2(dot_size, dot_size)), scol)

	# Giant Kraken Sea Monster Marker
	if bool(_tracked_sea_monster.get("active", false)):
		var mp: Vector2 = (mc + _tracked_sea_monster.get("pos", Vector2.ZERO) * scale_f).round()
		mp.x = clampf(mp.x, minimap_rect.position.x + 9.0, minimap_rect.end.x - 9.0)
		mp.y = clampf(mp.y, minimap_rect.position.y + 9.0, minimap_rect.end.y - 9.0)
		var k_pulse: float = 8.0 + 3.0 * sin(_pulse_time * 6.0)
		draw_arc(mp, k_pulse, 0.0, TAU, 18, Color(0.98, 0.30, 0.75, 0.85), 1.5)
		draw_colored_polygon(PackedVector2Array([
			mp + Vector2(0.0, -7.0),
			mp + Vector2(7.0, 0.0),
			mp + Vector2(0.0, 7.0),
			mp + Vector2(-7.0, 0.0)
		]), Color(0.96, 0.22, 0.62))

	# Active Quest Target
	if not active_quests.is_empty():
		var q: Contracts.QuestData = active_quests[0]
		var qp: Vector2 = (mc + _resolve_quest_target_pos(q) * scale_f).round()
		qp.x = clampf(qp.x, minimap_rect.position.x + 6.0, minimap_rect.end.x - 6.0)
		qp.y = clampf(qp.y, minimap_rect.position.y + 6.0, minimap_rect.end.y - 6.0)
		var blink: float = 0.55 + 0.45 * sin(_pulse_time * 5.0)
		draw_rect(Rect2(qp - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), Color(1.0, 0.90, 0.20, blink), false, 2.0)

	# Player Ship
	if player_ship != null:
		var pp: Vector2 = (mc + player_ship.get("world_pos") * scale_f).round()
		pp.x = clampf(pp.x, minimap_rect.position.x + 4.0, minimap_rect.end.x - 4.0)
		pp.y = clampf(pp.y, minimap_rect.position.y + 4.0, minimap_rect.end.y - 4.0)
		var h_vec: Vector2 = Vector2.from_angle(float(player_ship.get("heading")))
		_draw_minimap_pixel_icon("player", pp, 1.0)
		draw_line(pp, (pp + h_vec * 11.0).round(), COL_GOLD, 2.0)

	draw_rect(minimap_rect, COL_BRASS_DIM, false, 1.5)

	# Crystal-clear Minimap Legend below map
	var font: Font = ThemeDB.fallback_font
	var lx: float = minimap_rect.position.x
	var ly1: float = minimap_rect.end.y + 24.0
	var ly2: float = ly1 + 24.0

	_draw_legend_item(Vector2(lx, ly1), Color(1.0, 1.0, 1.0), "Du", font)
	_draw_legend_item(Vector2(lx + 46.0, ly1), COL_GOLD, "Hafen", font)
	_draw_legend_item(Vector2(lx + 118.0, ly1), Color(0.94, 0.28, 0.26), "Pirat", font)

	_draw_legend_item(Vector2(lx, ly2), Color(0.38, 0.76, 0.98), "Handel", font)
	_draw_legend_item(Vector2(lx + 76.0, ly2), Color(0.98, 0.54, 0.20), "Fort", font)
	_draw_legend_item(Vector2(lx + 132.0, ly2), COL_TURQUOISE, "Ziel", font)


func _draw_legend_item(pos: Vector2, dot_col: Color, label: String, font: Font) -> void:
	draw_rect(Rect2(pos.x, pos.y - 10.0, 8.0, 8.0), dot_col, true)
	draw_rect(Rect2(pos.x, pos.y - 10.0, 8.0, 8.0), OUTLINE_COLOR, false, 1.0)
	_draw_hud_text(font, pos + Vector2(12.0, 0.0), label, 14, COL_IVORY)


func _draw_bottom_compass_and_windrose(vp_size: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	var compass_center := _get_compass_center(vp_size)

	# Flanking Wind & Course wings behind center compass medallion
	var wing_rect := Rect2(compass_center.x - 196.0, compass_center.y - 34.0, 392.0, 68.0)
	_draw_chamfered_panel(wing_rect, COL_PANEL_BG, COL_BRASS, COL_BRASS_DIM, 8.0)

	# Left Wing: Wind strength
	var w_pct: int = int(round(clampf(wind_strength, 0.0, 1.0) * 100.0))
	_draw_hud_text(font, Vector2(wing_rect.position.x + 14.0, wing_rect.position.y + 24.0), "WIND", 14, COL_TURQUOISE)
	_draw_hud_text(font, Vector2(wing_rect.position.x + 14.0, wing_rect.position.y + 52.0), "%d%%" % w_pct, 18, COL_IVORY)
	var wb_rect := Rect2(wing_rect.position.x + 70.0, wing_rect.position.y + 39.0, 72.0, 10.0)
	draw_rect(wb_rect, COL_PANEL_INSET, true)
	draw_rect(Rect2(wb_rect.position, Vector2(floor(wb_rect.size.x * clampf(wind_strength, 0.0, 1.0)), wb_rect.size.y)), COL_TURQUOISE, true)
	draw_rect(wb_rect, COL_BRASS_DIM, false, 1.5)

	# Right Wing: Course / Heading readout
	var deg: int = 0
	var cardinal: String = "O"
	if player_ship != null:
		var h_deg: float = fposmod(rad_to_deg(float(player_ship.get("heading"))) + 90.0, 360.0)
		deg = int(round(h_deg)) % 360
		var dirs: Array[String] = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
		cardinal = dirs[int(round(h_deg / 45.0)) % 8]
	_draw_hud_text(font, Vector2(compass_center.x + 56.0, wing_rect.position.y + 24.0), "KURS", 14, COL_GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 126)
	_draw_hud_text(font, Vector2(compass_center.x + 56.0, wing_rect.position.y + 52.0), "%03d° %s" % [deg, cardinal], 18, COL_IVORY, HORIZONTAL_ALIGNMENT_RIGHT, 126)

	# Center Circular Brass Compass & Windrose Medallion
	draw_circle(compass_center, COMPASS_RADIUS + 5.0, Color(0.09, 0.08, 0.13, 0.98))
	draw_arc(compass_center, COMPASS_RADIUS + 5.0, 0.0, TAU, 48, COL_BRASS, 2.0, true)
	draw_arc(compass_center, COMPASS_RADIUS, 0.0, TAU, 40, COL_BRASS_DIM, 1.5, true)

	# 8 Compass Rose Ticks
	for i in range(8):
		var a: float = float(i) * PI * 0.25
		var inner_r: float = COMPASS_RADIUS - (9.0 if i % 2 == 0 else 5.0)
		var p1: Vector2 = compass_center + Vector2.from_angle(a) * inner_r
		var p2: Vector2 = compass_center + Vector2.from_angle(a) * COMPASS_RADIUS
		draw_line(p1, p2, COL_BRASS if i % 2 == 0 else COL_BRASS_DIM, 1.5)

	# Cardinal Letters N, O, S, W
	_draw_hud_text(font, compass_center + Vector2(-5.0, -COMPASS_RADIUS + 16.0), "N", 14, COL_GOLD)
	_draw_hud_text(font, compass_center + Vector2(COMPASS_RADIUS - 17.0, 5.0), "O", 14, COL_MUTED)
	_draw_hud_text(font, compass_center + Vector2(-5.0, COMPASS_RADIUS - 6.0), "S", 14, COL_MUTED)
	_draw_hud_text(font, compass_center + Vector2(-COMPASS_RADIUS + 5.0, 5.0), "W", 14, COL_MUTED)

	# Windrose Vane (Turquoise)
	var wind_vec: Vector2 = Vector2.from_angle(_display_wind_angle)
	var wind_tip: Vector2 = compass_center + wind_vec * (COMPASS_RADIUS - 10.0)
	var wind_tail: Vector2 = compass_center - wind_vec * 13.0
	var wind_perp: Vector2 = wind_vec.rotated(PI * 0.5) * 6.5
	draw_line(wind_tail, wind_tip, COL_TURQUOISE, 3.0)
	draw_colored_polygon(PackedVector2Array([
		wind_tip,
		wind_tip - wind_vec * 10.0 + wind_perp,
		wind_tip - wind_vec * 10.0 - wind_perp
	]), Color(0.78, 0.98, 1.0))

	# Ship Heading Needle (Gold)
	if player_ship != null:
		var h_vec: Vector2 = Vector2.from_angle(float(player_ship.get("heading")))
		var h_tip: Vector2 = compass_center + h_vec * 24.0
		draw_line(compass_center, h_tip, COL_GOLD, 3.0)
		draw_circle(h_tip, 3.0, Color(1.0, 0.95, 0.72))

	# Brass Center Pivot Cap
	draw_circle(compass_center, 4.5, COL_BRASS)
	draw_circle(compass_center, 2.0, COL_IVORY)


func _draw_toast_bg(vp_size: Vector2) -> void:
	if _toast_timer <= 0.0 or _toast_text.is_empty():
		return
	var alpha: float = clampf(_toast_timer, 0.0, 1.0)
	var box_w: float = minf(620.0, vp_size.x - 40.0)
	var box := Rect2(round(vp_size.x * 0.5 - box_w * 0.5), vp_size.y - 220.0, box_w, 40.0)
	_draw_chamfered_panel(
		box,
		Color(COL_PANEL_BG.r, COL_PANEL_BG.g, COL_PANEL_BG.b, 0.92 * alpha),
		Color(COL_BRASS.r, COL_BRASS.g, COL_BRASS.b, alpha),
		Color(COL_BRASS_DIM.r, COL_BRASS_DIM.g, COL_BRASS_DIM.b, 0.7 * alpha),
		7.0
	)


func _draw_harbor_banner_bg(vp_size: Vector2) -> void:
	if current_harbor_idx < 0:
		return
	var box_w: float = minf(600.0, vp_size.x - 40.0)
	var banner := Rect2(round(vp_size.x * 0.5 - box_w * 0.5), vp_size.y - 170.0, box_w, 44.0)
	_draw_chamfered_panel(banner, Color(0.13, 0.10, 0.11, 0.94), COL_GOLD, COL_BRASS_DIM, 7.0)


func _build_labels() -> void:
	_lbl_class = _make_hud_label(Vector2(30.0, 22.0), 18, COL_TURQUOISE)
	_lbl_gold = _make_hud_label(Vector2(216.0, 22.0), 18, COL_GOLD)
	_lbl_gold.size = Vector2(190.0, 24.0)
	_lbl_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_lbl_hp = _make_hud_label(Vector2(314.0, 50.0), 15, COL_IVORY)
	_lbl_hp.size = Vector2(92.0, 22.0)
	_lbl_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_lbl_sail = _make_hud_label(Vector2(30.0, 80.0), 15, COL_IVORY)

	_lbl_broadsides = _make_hud_label(Vector2(30.0, 114.0), 14, COL_MUTED)
	_lbl_broadsides.visible = false

	_lbl_weather = _make_hud_label(Vector2(450.0, 25.0), 16, COL_TURQUOISE)
	_lbl_wanted = _make_hud_label(Vector2(700.0, 25.0), 16, COL_MUTED)
	_lbl_wanted.size = Vector2(240.0, 24.0)
	_lbl_wanted.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_lbl_quest = _make_hud_label(Vector2(480.0, 79.0), 15, Color(0.98, 0.90, 0.58))
	_lbl_quest.size = Vector2(450.0, 24.0)
	_lbl_quest.visible = false

	_lbl_harbor = _make_hud_label(Vector2(340.0, 558.0), 18, COL_GOLD)
	_lbl_harbor.size = Vector2(600.0, 30.0)
	_lbl_harbor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_harbor.visible = false

	_lbl_toast = _make_hud_label(Vector2(330.0, 507.0), 16, COL_IVORY)
	_lbl_toast.size = Vector2(620.0, 28.0)
	_lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_toast.visible = false

	_lbl_controls = _make_hud_label(Vector2(18.0, 686.0), 14, COL_MUTED)
	_lbl_controls.text = "A/D Ruder • W/S Segel • Q/E Schuss"

	_lbl_controls_right = _make_hud_label(Vector2(900.0, 686.0), 14, COL_MUTED)
	_lbl_controls_right.size = Vector2(362.0, 24.0)
	_lbl_controls_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lbl_controls_right.text = "Tab Schiffs-Grid • F Hafen"


func _sync_dynamic_layout() -> void:
	if _lbl_weather == null:
		return
	var vp_size: Vector2 = _get_hud_size()
	var top_bar := _get_top_bar_rect(vp_size)

	_lbl_weather.position = Vector2(top_bar.position.x + 14.0, top_bar.position.y + 10.0).round()
	_lbl_wanted.position = Vector2(top_bar.end.x - 254.0, top_bar.position.y + 10.0).round()
	_lbl_wanted.size = Vector2(240.0, 24.0)

	_lbl_quest.position = Vector2(top_bar.position.x + 52.0, 79.0).round()
	_lbl_quest.size = Vector2(maxf(120.0, top_bar.size.x - 66.0), 24.0)

	var harbor_w: float = minf(600.0, vp_size.x - 40.0)
	_lbl_harbor.position = Vector2(round(vp_size.x * 0.5 - harbor_w * 0.5), vp_size.y - 162.0).round()
	_lbl_harbor.size = Vector2(harbor_w, 30.0)

	var toast_w: float = minf(620.0, vp_size.x - 40.0)
	_lbl_toast.position = Vector2(round(vp_size.x * 0.5 - toast_w * 0.5), vp_size.y - 213.0).round()
	_lbl_toast.size = Vector2(toast_w, 28.0)

	_lbl_controls.position = Vector2(18.0, vp_size.y - 34.0).round()
	_lbl_controls_right.position = Vector2(vp_size.x - 380.0, vp_size.y - 34.0).round()


func _make_hud_label(pos: Vector2, font_size: int, col: Color) -> Label:
	var lbl := Label.new()
	lbl.position = pos.round()
	lbl.add_theme_font_size_override("font_size", maxi(14, font_size))
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	add_child(lbl)
	return lbl


func _update_labels() -> void:
	if player_ship != null:
		var s_state: int = int(player_ship.get("sail_state"))
		var sail_name: String = "Anker"
		if s_state == Contracts.SailState.HALF_SAIL:
			sail_name = "Halbe Segel"
		elif s_state == Contracts.SailState.FULL_SAIL:
			sail_name = "Volle Segel"
		var spd: int = int(round(float(player_ship.get("speed"))))
		var knots: int = int(round(float(spd) * 0.14))
		_lbl_sail.text = "%s (%d kn)" % [sail_name, knots]

		var tier_val: Variant = player_ship.get("hull_tier")
		var tier: int = int(tier_val) if tier_val != null else 0
		match tier:
			Contracts.ShipClass.BRIGANTINE:
				_player_class_title = "Brigg"
			Contracts.ShipClass.FRIGATE:
				_player_class_title = "Fregatte"
			_:
				_player_class_title = "Schaluppe"
		_lbl_class.text = _player_class_title

		var hp: int = int(round(float(player_ship.get("hp"))))
		var max_hp: int = int(round(float(player_ship.get("max_hp"))))
		_lbl_hp.text = "%d/%d" % [hp, max_hp]

	_lbl_gold.text = "%d Gold" % gold_amount

	match current_weather:
		Contracts.WeatherState.FOG:
			_lbl_weather.text = "Wetter: Nebel"
			_lbl_weather.add_theme_color_override("font_color", Color(0.76, 0.84, 0.90))
		Contracts.WeatherState.STORM:
			_lbl_weather.text = "Wetter: Sturm"
			_lbl_weather.add_theme_color_override("font_color", Color(0.98, 0.72, 0.36))
		_:
			_lbl_weather.text = "Wetter: Klar"
			_lbl_weather.add_theme_color_override("font_color", COL_TURQUOISE)

	if wanted_level <= 0:
		_lbl_wanted.text = "Marine: Ruhig"
		_lbl_wanted.add_theme_color_override("font_color", COL_MUTED)
	else:
		var stars: String = ""
		for i in range(3):
			stars += "★" if i < wanted_level else "☆"
		_lbl_wanted.text = "Fahndung: " + stars
		_lbl_wanted.add_theme_color_override("font_color", Color(0.98, 0.38, 0.34))

	if not active_quests.is_empty() and player_ship != null:
		var q: Contracts.QuestData = active_quests[0]
		var target_pos: Vector2 = _resolve_quest_target_pos(q)
		var dist: int = int(round(player_ship.get("world_pos").distance_to(target_pos)))
		_lbl_quest.visible = true
		_lbl_quest.text = "%s (%dm)" % [q.title.left(26), dist]
	else:
		_lbl_quest.visible = false

	if current_harbor_idx >= 0:
		_lbl_harbor.visible = true
		_lbl_harbor.text = "[F / Space] Hafen von %s betreten" % current_harbor_name
	else:
		_lbl_harbor.visible = false


func _resolve_quest_target_pos(q: Contracts.QuestData) -> Vector2:
	if q.quest_type == Contracts.QuestType.BOUNTY and q.target_ship_id != -1:
		if all_ships_ref.has(q.target_ship_id):
			var boss: Node = all_ships_ref[q.target_ship_id]
			if boss != null and not bool(boss.get("is_sunk")):
				return boss.get("world_pos")
	return q.target_pos


func _get_islands() -> Array:
	if world_map_ref != null:
		var arr: Variant = world_map_ref.get("islands")
		if arr is Array and not arr.is_empty():
			return arr
	return Contracts.get_islands()


func _connect_signals() -> void:
	var bus := _bus()
	if bus == null:
		return
	if not bus.wind_changed.is_connected(_on_wind_changed):
		bus.wind_changed.connect(_on_wind_changed)
	if not bus.gold_changed.is_connected(_on_gold_changed):
		bus.gold_changed.connect(_on_gold_changed)
	if not bus.harbor_entered.is_connected(_on_harbor_entered):
		bus.harbor_entered.connect(_on_harbor_entered)
	if not bus.harbor_exited.is_connected(_on_harbor_exited):
		bus.harbor_exited.connect(_on_harbor_exited)
	if not bus.quest_list_updated.is_connected(_on_quest_list_updated):
		bus.quest_list_updated.connect(_on_quest_list_updated)
	if not bus.quest_accepted.is_connected(_on_quest_accepted):
		bus.quest_accepted.connect(_on_quest_accepted)
	if not bus.quest_completed.is_connected(_on_quest_completed):
		bus.quest_completed.connect(_on_quest_completed)
	if not bus.notification_posted.is_connected(_on_notification_posted):
		bus.notification_posted.connect(_on_notification_posted)
	if not bus.weather_changed.is_connected(_on_weather_changed):
		bus.weather_changed.connect(_on_weather_changed)
	if not bus.wanted_level_changed.is_connected(_on_wanted_level_changed):
		bus.wanted_level_changed.connect(_on_wanted_level_changed)
	if not bus.ship_class_upgraded.is_connected(_on_ship_class_upgraded):
		bus.ship_class_upgraded.connect(_on_ship_class_upgraded)
	if not bus.fort_spawned.is_connected(_on_fort_spawned):
		bus.fort_spawned.connect(_on_fort_spawned)
	if not bus.fort_destroyed.is_connected(_on_fort_destroyed):
		bus.fort_destroyed.connect(_on_fort_destroyed)
	if not bus.sea_monster_spawned.is_connected(_on_sea_monster_spawned):
		bus.sea_monster_spawned.connect(_on_sea_monster_spawned)
	if not bus.sea_monster_updated.is_connected(_on_sea_monster_updated):
		bus.sea_monster_updated.connect(_on_sea_monster_updated)
	if not bus.sea_monster_defeated.is_connected(_on_sea_monster_defeated):
		bus.sea_monster_defeated.connect(_on_sea_monster_defeated)


func _on_wind_changed(direction: Vector2, strength: float) -> void:
	wind_dir = direction.normalized()
	wind_strength = strength


func _on_gold_changed(new_gold: int, _delta: int) -> void:
	gold_amount = new_gold


func _on_harbor_entered(ship_id: int, island_index: int, island_name: String) -> void:
	if player_ship != null and ship_id == int(player_ship.get("ship_id")):
		current_harbor_idx = island_index
		current_harbor_name = island_name


func _on_harbor_exited(ship_id: int, _island_index: int) -> void:
	if player_ship != null and ship_id == int(player_ship.get("ship_id")):
		current_harbor_idx = -1
		current_harbor_name = ""


func _on_quest_list_updated(quests: Array) -> void:
	active_quests = quests.duplicate()


func _on_quest_accepted(quest: Contracts.QuestData) -> void:
	if quest != null and not active_quests.has(quest):
		active_quests.append(quest)


func _on_quest_completed(quest: Contracts.QuestData) -> void:
	if quest == null:
		return
	for i in range(active_quests.size() - 1, -1, -1):
		if active_quests[i].id == quest.id:
			active_quests.remove_at(i)


func _on_notification_posted(message: String, _category: String) -> void:
	_toast_text = message
	_toast_timer = 3.2
	if _lbl_toast != null:
		_lbl_toast.text = message
		_lbl_toast.visible = true


func _on_weather_changed(weather_state: int, _intensity: float) -> void:
	current_weather = weather_state


func _on_wanted_level_changed(new_level: int) -> void:
	wanted_level = new_level


func _on_ship_class_upgraded(ship_id: int, _new_hull_tier: int, class_title: String) -> void:
	if player_ship != null and ship_id == int(player_ship.get("ship_id")):
		_player_class_title = class_title


func _on_fort_spawned(fort_id: int, world_pos: Vector2, _island_index: int, _max_hp: float) -> void:
	_tracked_forts[fort_id] = { "pos": world_pos, "destroyed": false }


func _on_fort_destroyed(fort_id: int, world_pos: Vector2) -> void:
	_tracked_forts[fort_id] = { "pos": world_pos, "destroyed": true }


func _on_sea_monster_spawned(monster_id: int, world_pos: Vector2, max_hp: float) -> void:
	_tracked_sea_monster = {
		"monster_id": monster_id,
		"pos": world_pos,
		"hp": max_hp,
		"max_hp": max_hp,
		"active": true
	}


func _on_sea_monster_updated(monster_id: int, world_pos: Vector2, hp: float, max_hp: float, _phase: int) -> void:
	_tracked_sea_monster = {
		"monster_id": monster_id,
		"pos": world_pos,
		"hp": hp,
		"max_hp": max_hp,
		"active": hp > 0.0
	}


func _on_sea_monster_defeated(_monster_id: int, _world_pos: Vector2) -> void:
	_tracked_sea_monster["active"] = false

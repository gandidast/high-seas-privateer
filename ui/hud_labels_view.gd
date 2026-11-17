class_name HudLabelsView
extends RefCounted
## Manages cached Label nodes for HudOverlay so static/infrequent HUD strings
## are never re-outlined via draw_string_outline inside _draw().

const CARDINAL_DIRS: Array[String] = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]

var lbl_sail: Label = null
var lbl_gold: Label = null
var lbl_class: Label = null
var lbl_hp: Label = null
var lbl_hull_title: Label = null
var lbl_port: Label = null
var lbl_starboard: Label = null
var lbl_bow: Label = null
var lbl_coords: Label = null
var lbl_weather: Label = null
var lbl_wanted: Label = null
var lbl_quest: Label = null
var lbl_harbor: Label = null
var lbl_toast: Label = null
var lbl_death_banner: Label = null
var lbl_controls: Label = null
var lbl_controls_right: Label = null
var lbl_wind_title: Label = null
var lbl_wind_pct: Label = null
var lbl_course_title: Label = null
var lbl_course_val: Label = null
var lbl_card_n: Label = null
var lbl_card_o: Label = null
var lbl_card_s: Label = null
var lbl_card_w: Label = null

var _last_sail_state: int = -1
var _last_knots: int = -1
var _last_gold: int = -1
var _last_weather: int = -1
var _last_wanted: int = -1
var _last_harbor: int = -2
var _last_wind_pct: int = -1
var _last_quest_key: String = ""
var _last_port_rdy: bool = false
var _last_sb_rdy: bool = false
var _last_bow_rdy: int = -1
var _last_death_key: String = ""
var _last_coords_txt: String = ""
var _last_coords_y: float = -1.0


func build(parent: Control) -> void:
	lbl_class = _make(parent, Vector2(30.0, 22.0), 18, UIThemeHelper.COL_TURQUOISE)
	lbl_gold = _make(parent, Vector2(216.0, 22.0), 18, UIThemeHelper.COL_GOLD, 190.0, HORIZONTAL_ALIGNMENT_RIGHT)
	lbl_hull_title = _make(parent, Vector2(30.0, 50.0), 15, UIThemeHelper.COL_MUTED)
	lbl_hull_title.text = "Rumpf"
	lbl_hp = _make(parent, Vector2(314.0, 50.0), 15, UIThemeHelper.COL_IVORY, 92.0, HORIZONTAL_ALIGNMENT_RIGHT)
	lbl_sail = _make(parent, Vector2(30.0, 80.0), 15, UIThemeHelper.COL_IVORY)
	lbl_port = _make(parent, Vector2(30.0, 116.0), 14, UIThemeHelper.COL_MUTED)
	lbl_port.text = "[Q] Backbord"
	lbl_starboard = _make(parent, Vector2(224.0, 116.0), 14, UIThemeHelper.COL_MUTED)
	lbl_starboard.text = "[E] Steuerbord"
	lbl_bow = _make(parent, Vector2(30.0, 160.0), 14, UIThemeHelper.COL_MUTED)
	lbl_bow.text = "[Space] Bug-Geschütz"
	lbl_bow.visible = false
	lbl_coords = _make(parent, Vector2(16.0, 176.0), 14, UIThemeHelper.COL_TURQUOISE)
	var coords_style := UIThemeHelper.make_box_style(UIThemeHelper.COL_HUD_PANEL_BG, UIThemeHelper.COL_BRASS_DIM, 4, 1, 6)
	coords_style.content_margin_top = 2.0
	coords_style.content_margin_bottom = 2.0
	coords_style.content_margin_left = 8.0
	coords_style.content_margin_right = 8.0
	lbl_coords.add_theme_stylebox_override("normal", coords_style)
	lbl_coords.text = "POS: X +0  Y +0"
	_last_coords_txt = lbl_coords.text
	_last_coords_y = 176.0

	lbl_weather = _make(parent, Vector2(450.0, 25.0), 16, UIThemeHelper.COL_TURQUOISE)
	lbl_wanted = _make(parent, Vector2(700.0, 25.0), 16, UIThemeHelper.COL_MUTED, 240.0, HORIZONTAL_ALIGNMENT_RIGHT)
	lbl_quest = _make(parent, Vector2(480.0, 79.0), 15, Color(0.98, 0.90, 0.58), 450.0)
	lbl_quest.visible = false
	lbl_death_banner = _make(parent, Vector2(330.0, 144.0), 18, Color(1.0, 0.88, 0.72), 620.0, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_death_banner.visible = false
	lbl_harbor = _make(parent, Vector2(340.0, 558.0), 18, UIThemeHelper.COL_GOLD, 600.0, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_harbor.visible = false
	lbl_toast = _make(parent, Vector2(330.0, 507.0), 16, UIThemeHelper.COL_IVORY, 620.0, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_toast.visible = false

	lbl_controls = _make(parent, Vector2(18.0, 686.0), 14, UIThemeHelper.COL_MUTED)
	lbl_controls.text = "A/D Ruder • W/S Segel • Q/E Schuss"
	lbl_controls_right = _make(parent, Vector2(802.0, 686.0), 14, UIThemeHelper.COL_MUTED, 460.0, HORIZONTAL_ALIGNMENT_RIGHT)
	lbl_controls_right.text = "Tab Grid • F Hafen • M Seekarte • Space Bug"

	lbl_wind_title = _make(parent, Vector2.ZERO, 14, UIThemeHelper.COL_TURQUOISE)
	lbl_wind_title.text = "WIND"
	lbl_wind_pct = _make(parent, Vector2.ZERO, 18, UIThemeHelper.COL_IVORY)
	lbl_course_title = _make(parent, Vector2.ZERO, 14, UIThemeHelper.COL_GOLD, 126.0, HORIZONTAL_ALIGNMENT_RIGHT)
	lbl_course_title.text = "KURS"
	lbl_course_val = _make(parent, Vector2.ZERO, 18, UIThemeHelper.COL_IVORY, 126.0, HORIZONTAL_ALIGNMENT_RIGHT)

	lbl_card_n = _make(parent, Vector2.ZERO, 14, UIThemeHelper.COL_GOLD); lbl_card_n.text = "N"
	lbl_card_o = _make(parent, Vector2.ZERO, 14, UIThemeHelper.COL_MUTED); lbl_card_o.text = "O"
	lbl_card_s = _make(parent, Vector2.ZERO, 14, UIThemeHelper.COL_MUTED); lbl_card_s.text = "S"
	lbl_card_w = _make(parent, Vector2.ZERO, 14, UIThemeHelper.COL_MUTED); lbl_card_w.text = "W"


func _make(parent: Control, pos: Vector2, sz: int, col: Color, w: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lbl := UIThemeHelper.make_label("", sz, col)
	lbl.position = pos.round()
	if w > 0.0:
		lbl.size = Vector2(w, 26.0)
		lbl.horizontal_alignment = align
	parent.add_child(lbl)
	return lbl


func sync_layout(vp_size: Vector2, top_bar: Rect2, cc: Vector2, compass_radius: float) -> void:
	if lbl_weather == null:
		return
	lbl_weather.position = Vector2(top_bar.position.x + 14.0, top_bar.position.y + 10.0).round()
	lbl_wanted.position = Vector2(top_bar.end.x - 254.0, top_bar.position.y + 10.0).round()
	lbl_quest.position = Vector2(top_bar.position.x + 52.0, 79.0).round()
	lbl_quest.size = Vector2(maxf(120.0, top_bar.size.x - 66.0), 24.0)

	var death_w: float = minf(620.0, vp_size.x - 40.0)
	lbl_death_banner.position = Vector2(round(vp_size.x * 0.5 - death_w * 0.5), 144.0).round()
	lbl_death_banner.size = Vector2(death_w, 30.0)

	var harbor_w: float = minf(600.0, vp_size.x - 40.0)
	lbl_harbor.position = Vector2(round(vp_size.x * 0.5 - harbor_w * 0.5), vp_size.y - 162.0).round()
	lbl_harbor.size = Vector2(harbor_w, 30.0)

	var toast_w: float = minf(620.0, vp_size.x - 40.0)
	lbl_toast.position = Vector2(round(vp_size.x * 0.5 - toast_w * 0.5), vp_size.y - 213.0).round()
	lbl_toast.size = Vector2(toast_w, 28.0)

	lbl_controls.position = Vector2(18.0, vp_size.y - 34.0).round()
	lbl_controls_right.position = Vector2(vp_size.x - 478.0, vp_size.y - 34.0).round()
	lbl_controls_right.size = Vector2(460.0, 26.0)

	var wing_pos := Vector2(cc.x - 196.0, cc.y - 34.0)
	lbl_wind_title.position = (wing_pos + Vector2(14.0, 8.0)).round()
	lbl_wind_pct.position = (wing_pos + Vector2(14.0, 32.0)).round()
	lbl_course_title.position = Vector2(cc.x + 56.0, wing_pos.y + 8.0).round()
	lbl_course_val.position = Vector2(cc.x + 56.0, wing_pos.y + 32.0).round()
	lbl_card_n.position = (cc + Vector2(-5.0, -compass_radius + 1.0)).round()
	lbl_card_o.position = (cc + Vector2(compass_radius - 17.0, -10.0)).round()
	lbl_card_s.position = (cc + Vector2(-5.0, compass_radius - 21.0)).round()
	lbl_card_w.position = (cc + Vector2(-compass_radius + 5.0, -10.0)).round()


func update(
	player_ship: Node,
	reloads: Vector2,
	wind_strength: float,
	gold_amount: int,
	current_weather: int,
	wanted_level: int,
	active_quests: Array,
	quest_target_pos: Vector2,
	current_harbor_idx: int,
	current_harbor_name: String,
	bow_ready: float = -1.0,
	death_active: bool = false,
	death_gold: int = 20,
	death_seconds: float = 0.0
) -> String:
	var class_title: String = "Schaluppe"
	if player_ship != null:
		var s_state: int = int(player_ship.get("sail_state"))
		var knots: int = int(round(float(player_ship.get("speed")) * 0.14))
		if s_state != _last_sail_state or knots != _last_knots:
			_last_sail_state = s_state
			_last_knots = knots
			var sname := "Anker" if s_state == Contracts.SailState.ANCHORED else ("Halbe Segel" if s_state == Contracts.SailState.HALF_SAIL else "Volle Segel")
			lbl_sail.text = "%s (%d kn)" % [sname, knots]

		var tier_val: Variant = player_ship.get("hull_tier")
		var tier: int = int(tier_val) if tier_val != null else 0
		var spec: Dictionary = Contracts.get_ship_class_spec(tier)
		class_title = str(spec.get("name", "Schaluppe"))
		if lbl_class.text != class_title:
			lbl_class.text = class_title

		var hp_txt := "%d/%d" % [int(round(float(player_ship.get("hp")))), int(round(float(player_ship.get("max_hp"))))]
		if lbl_hp.text != hp_txt:
			lbl_hp.text = hp_txt

		var h_deg: float = fposmod(rad_to_deg(float(player_ship.get("heading"))) + 90.0, 360.0)
		var course_txt := "%03d° %s" % [int(round(h_deg)) % 360, CARDINAL_DIRS[int(round(h_deg / 45.0)) % 8]]
		if lbl_course_val.text != course_txt:
			lbl_course_val.text = course_txt
	elif lbl_course_val.text != "000° O":
		lbl_course_val.text = "000° O"

	var pt_rdy: bool = reloads.x >= 0.99
	if pt_rdy != _last_port_rdy:
		_last_port_rdy = pt_rdy
		lbl_port.add_theme_color_override("font_color", Color(0.62, 0.86, 1.0) if pt_rdy else UIThemeHelper.COL_MUTED)
	var sb_rdy: bool = reloads.y >= 0.99
	if sb_rdy != _last_sb_rdy:
		_last_sb_rdy = sb_rdy
		lbl_starboard.add_theme_color_override("font_color", Color(0.98, 0.68, 0.56) if sb_rdy else UIThemeHelper.COL_MUTED)

	var bow_state: int = -1 if bow_ready < 0.0 else (2 if bow_ready >= 0.99 else 1)
	if bow_state != _last_bow_rdy:
		_last_bow_rdy = bow_state
		lbl_bow.visible = bow_state >= 0
		if bow_state == 2:
			lbl_bow.text = "[Space] Bug-Geschütz (Bereit)"
			lbl_bow.add_theme_color_override("font_color", UIThemeHelper.COL_GOLD)
		elif bow_state == 1:
			lbl_bow.text = "[Space] Bug-Geschütz (Lädt...)"
			lbl_bow.add_theme_color_override("font_color", UIThemeHelper.COL_MUTED)
	sync_coords_pos(bow_state >= 0)

	var w_pct: int = int(round(clampf(wind_strength, 0.0, 1.0) * 100.0))
	if w_pct != _last_wind_pct:
		_last_wind_pct = w_pct
		lbl_wind_pct.text = "%d%%" % w_pct

	if gold_amount != _last_gold:
		_last_gold = gold_amount
		lbl_gold.text = "%d Gold" % gold_amount

	if current_weather != _last_weather:
		_last_weather = current_weather
		if current_weather == Contracts.WeatherState.FOG:
			lbl_weather.text = "Wetter: Nebel"; lbl_weather.add_theme_color_override("font_color", Color(0.76, 0.84, 0.90))
		elif current_weather == Contracts.WeatherState.STORM:
			lbl_weather.text = "Wetter: Sturm"; lbl_weather.add_theme_color_override("font_color", Color(0.98, 0.72, 0.36))
		else:
			lbl_weather.text = "Wetter: Klar"; lbl_weather.add_theme_color_override("font_color", UIThemeHelper.COL_TURQUOISE)

	if wanted_level != _last_wanted:
		_last_wanted = wanted_level
		if wanted_level <= 0:
			lbl_wanted.text = "Marine: Ruhig"; lbl_wanted.add_theme_color_override("font_color", UIThemeHelper.COL_MUTED)
		else:
			var stars := ""
			for i in range(3):
				stars += "★" if i < wanted_level else "☆"
			lbl_wanted.text = "Fahndung: " + stars
			lbl_wanted.add_theme_color_override("font_color", Color(0.98, 0.38, 0.34))

	if not active_quests.is_empty() and player_ship != null:
		var q: Contracts.QuestData = active_quests[0]
		var dist: int = int(round(player_ship.get("world_pos").distance_to(quest_target_pos)))
		var q_key := "%s (%dm)" % [q.title.left(26), dist]
		lbl_quest.visible = true
		if _last_quest_key != q_key:
			_last_quest_key = q_key
			lbl_quest.text = q_key
	else:
		lbl_quest.visible = false
		_last_quest_key = ""

	if death_active:
		var sec_disp: int = maxi(0, int(ceil(death_seconds)))
		var d_key := "SCHIFF VERSENKT! (-%d Gold) • Rückkehr zum Hafen in %ds" % [death_gold, sec_disp]
		lbl_death_banner.visible = true
		if _last_death_key != d_key:
			_last_death_key = d_key
			lbl_death_banner.text = d_key
	else:
		lbl_death_banner.visible = false
		_last_death_key = ""

	if current_harbor_idx != _last_harbor:
		_last_harbor = current_harbor_idx
		lbl_harbor.visible = current_harbor_idx >= 0
		if lbl_harbor.visible:
			lbl_harbor.text = "[F] Hafen von %s betreten" % current_harbor_name

	return class_title


func sync_coords_pos(has_bow: bool) -> void:
	if lbl_coords == null:
		return
	var panel_bottom: float = 16.0 + (178.0 if has_bow else 156.0)
	var target_y: float = panel_bottom + 4.0
	if not is_equal_approx(target_y, _last_coords_y):
		_last_coords_y = target_y
		lbl_coords.position = Vector2(16.0, target_y).round()


func update_coords(world_pos: Vector2) -> void:
	if lbl_coords == null:
		return
	var cx: int = int(round(world_pos.x))
	var cy: int = int(round(world_pos.y))
	var sx: String = "+%d" % cx if cx >= 0 else "%d" % cx
	var sy: String = "+%d" % cy if cy >= 0 else "%d" % cy
	var txt: String = "POS: X %s  Y %s" % [sx, sy]
	if _last_coords_txt != txt:
		_last_coords_txt = txt
		lbl_coords.text = txt

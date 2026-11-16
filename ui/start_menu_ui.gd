class_name StartMenuUI
extends Control
## Start menu overlay for Solo & One-World Multiplayer selection, captain profile
## persistence, and local/public server tunnel launcher.

signal solo_requested(captain_name: String, server_url: String)
signal join_multiplayer_requested(url: String, captain_name: String)
signal reconnect_requested()

const ServerConfigScript := preload("res://net/server_config.gd")

var _url_input: LineEdit = null
var _name_input: LineEdit = null
var _status_label: Label = null
var _join_btn: Button = null
var _reconnect_btn: Button = null
var _public_btn: Button = null
var _public_tunnel_watch_timer: float = -1.0
var _public_tunnel_poll_accum: float = 0.0
var _live_url_file_path: String = ""


func _ready() -> void:
	name = "StartScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _process(delta: float) -> void:
	if _public_tunnel_watch_timer > 0.0:
		_public_tunnel_watch_timer -= delta
		_public_tunnel_poll_accum += delta
		if _public_tunnel_poll_accum >= 0.45:
			_public_tunnel_poll_accum = 0.0
			_check_live_tunnel_url_file()


func get_captain_name() -> String:
	var cap: String = _name_input.text.strip_edges() if _name_input != null else ""
	return "Käpt'n Rotbart" if cap.is_empty() else cap


func get_url_text() -> String:
	return _url_input.text.strip_edges() if _url_input != null else ""


func set_status(text: String, color: Color = Color(0.95, 0.78, 0.42)) -> void:
	if _status_label != null:
		_status_label.add_theme_color_override("font_color", color)
		_status_label.text = text


func set_reconnect_visible(is_visible: bool) -> void:
	if _reconnect_btn != null:
		_reconnect_btn.visible = is_visible


func show_disconnected(reason: String) -> void:
	visible = true
	set_reconnect_visible(true)
	set_status(reason, Color(0.98, 0.48, 0.42))


func hide_menu() -> void:
	visible = false
	set_reconnect_visible(false)
	if get_viewport() != null:
		get_viewport().gui_release_focus()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.05, 0.09, 0.62)
	add_child(dim)

	var outer_panel := PanelContainer.new()
	outer_panel.anchor_left = 0.5
	outer_panel.anchor_top = 0.5
	outer_panel.anchor_right = 0.5
	outer_panel.anchor_bottom = 0.5
	outer_panel.offset_left = -340.0
	outer_panel.offset_top = -250.0
	outer_panel.offset_right = 340.0
	outer_panel.offset_bottom = 250.0
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color(0.14, 0.10, 0.07, 0.98)
	outer_style.border_color = Color(0.87, 0.69, 0.32, 0.95)
	outer_style.set_border_width_all(2)
	outer_style.set_corner_radius_all(8)
	outer_style.set_content_margin_all(6)
	outer_style.shadow_color = Color(0.0, 0.0, 0.0, 0.60)
	outer_style.shadow_size = 10
	outer_panel.add_theme_stylebox_override("panel", outer_style)
	add_child(outer_panel)

	var inner_panel := PanelContainer.new()
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color(0.075, 0.085, 0.13, 0.97)
	inner_style.border_color = Color(0.58, 0.45, 0.22, 0.90)
	inner_style.set_border_width_all(1)
	inner_style.set_corner_radius_all(5)
	inner_style.content_margin_left = 24
	inner_style.content_margin_right = 24
	inner_style.content_margin_top = 18
	inner_style.content_margin_bottom = 18
	inner_panel.add_theme_stylebox_override("panel", inner_style)
	outer_panel.add_child(inner_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	inner_panel.add_child(vbox)

	var title := _make_label("HIGH SEAS PIXEL PRIVATEER", 25, Color(0.98, 0.85, 0.36), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(title)
	var sub := _make_label("2D Segel-Diorama  •  Dredge-Frachtgrid  •  One-World Multiplayer", 14, Color(0.86, 0.83, 0.74), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(sub)
	vbox.add_child(_make_label("SOLO-ABENTEUER", 14, Color(0.46, 0.86, 0.76)))

	var solo_btn := _make_menu_button("Lokal / Solo Spielen", Color(0.16, 0.41, 0.26), 16)
	solo_btn.pressed.connect(_on_solo_btn_pressed)
	vbox.add_child(solo_btn)
	vbox.add_child(_make_gold_divider(0.65))
	vbox.add_child(_make_label("ONE-WORLD MULTIPLAYER (AUTO-HOST & ONLINE)", 14, Color(0.95, 0.78, 0.40)))

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 10)
	vbox.add_child(input_row)

	_name_input = LineEdit.new()
	_name_input.text = ServerConfigScript.load_captain_name("Käpt'n Rotbart")
	_name_input.placeholder_text = "Kapitänsname..."
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.size_flags_stretch_ratio = 0.38
	_style_line_edit(_name_input)
	input_row.add_child(_name_input)

	_url_input = LineEdit.new()
	_url_input.text = ServerConfigScript.get_initial_server_url()
	_url_input.placeholder_text = "ws://localhost:8080 oder wss://..."
	_url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_input.size_flags_stretch_ratio = 0.62
	_style_line_edit(_url_input)
	input_row.add_child(_url_input)

	var mp_action_row := HBoxContainer.new()
	mp_action_row.add_theme_constant_override("separation", 10)
	vbox.add_child(mp_action_row)

	_join_btn = _make_menu_button("One-World Beitreten", Color(0.16, 0.34, 0.54), 16)
	_join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_btn.pressed.connect(_on_join_btn_pressed)
	mp_action_row.add_child(_join_btn)

	_reconnect_btn = _make_menu_button("Erneut verbinden", Color(0.56, 0.31, 0.14), 15)
	_reconnect_btn.visible = false
	_reconnect_btn.pressed.connect(func(): reconnect_requested.emit())
	mp_action_row.add_child(_reconnect_btn)

	_public_btn = _make_menu_button("Öffentlichen Server / Browser-Link starten", Color(0.42, 0.26, 0.14), 14)
	_public_btn.pressed.connect(_on_public_server_pressed)
	vbox.add_child(_public_btn)

	_status_label = _make_label("1 Klick startet lokalen Server automatisch oder verbindet online.", 14, Color(0.95, 0.78, 0.42), HORIZONTAL_ALIGNMENT_CENTER)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0.0, 38.0)
	vbox.add_child(_status_label)

	vbox.add_child(_make_gold_divider(0.45))

	var legend_box := PanelContainer.new()
	var legend_style := StyleBoxFlat.new()
	legend_style.bg_color = Color(0.045, 0.055, 0.09, 0.90)
	legend_style.border_color = Color(0.42, 0.34, 0.20, 0.75)
	legend_style.set_border_width_all(1)
	legend_style.set_corner_radius_all(4)
	legend_style.content_margin_left = 12
	legend_style.content_margin_right = 12
	legend_style.content_margin_top = 6
	legend_style.content_margin_bottom = 6
	legend_box.add_theme_stylebox_override("panel", legend_style)
	vbox.add_child(legend_box)
	legend_box.add_child(_make_label("WASD: Segel & Ruder  •  Q/E: Breitseite  •  Space: Bug  •  Tab/I: Schiffs-Grid  •  F: Hafen & Beute  •  M: Seekarte", 14, Color(0.84, 0.82, 0.75), HORIZONTAL_ALIGNMENT_CENTER))


func _on_solo_btn_pressed() -> void:
	var cap_name: String = _name_input.text.strip_edges() if _name_input != null else ""
	var url_val: String = get_url_text()
	if not cap_name.is_empty() or not url_val.is_empty():
		ServerConfigScript.save_profile(cap_name, url_val)
	solo_requested.emit(cap_name, url_val)


func _on_join_btn_pressed() -> void:
	var url: String = get_url_text()
	var cap_name: String = get_captain_name()
	ServerConfigScript.save_profile(cap_name, url)
	set_reconnect_visible(false)
	if ServerConfigScript.is_placeholder_url(url):
		set_status("Platzhalter-URL erkannt – weiche auf %s (Auto-Host) aus..." % ServerConfigScript.LOCAL_SERVER_URL)
	else:
		set_status("Verbinde mit One-World (%s)..." % NetworkManager.normalize_ws_url(url))
	join_multiplayer_requested.emit(url, cap_name)


func _on_public_server_pressed() -> void:
	if OS.has_feature("web"):
		set_status("Im Browser läuft bereits der Client – nutze die wss://-Adresse oben.")
		return

	var target_url: String = get_url_text()
	var port: int = NetworkManager.extract_port_from_url(target_url, Contracts.SERVER_DEFAULT_PORT)
	if not NetworkManager.is_local_url(target_url):
		port = Contracts.SERVER_DEFAULT_PORT

	if OS.get_name() == "Windows":
		var script_path: String = _resolve_script(["tools/host_local.ps1", "deploy/start_live_multiplayer.ps1"])
		if script_path.is_empty():
			set_status("tools/host_local.ps1 und deploy/start_live_multiplayer.ps1 nicht gefunden.")
			return
		_live_url_file_path = _get_live_url_temp_path()
		if FileAccess.file_exists(_live_url_file_path):
			DirAccess.remove_absolute(_live_url_file_path)
		var args := PackedStringArray(["-NoExit", "-ExecutionPolicy", "Bypass", "-File", script_path, "-Port", str(port)])
		var pid: int = OS.create_process("powershell.exe", args, true)
		if pid > 0:
			_public_tunnel_watch_timer = 25.0
			_public_tunnel_poll_accum = 0.0
			set_status("Server & wss://-Tunnel starten im Konsolenfenster (Port %d)..." % port)
		else:
			set_status("Konnte PowerShell für Tunnel nicht starten.", Color(0.98, 0.48, 0.42))
	else:
		var sh_path: String = _resolve_script(["deploy/start_server.sh"])
		if sh_path.is_empty():
			set_status("deploy/start_server.sh nicht gefunden.")
			return
		var pid: int = OS.create_process("bash", PackedStringArray([sh_path]), true)
		set_status("Headless-Server auf Port %d gestartet (PID %d)." % [port, pid] if pid > 0 else "Starte deploy/start_server.sh manuell im Terminal.")


func _resolve_script(rel_paths: Array[String]) -> String:
	var exe_dir: String = OS.get_executable_path().get_base_dir()
	for rel in rel_paths:
		var res_p: String = ProjectSettings.globalize_path("res://" + rel)
		if not res_p.is_empty() and FileAccess.file_exists(res_p):
			return res_p
		var exe_p: String = exe_dir.path_join(rel)
		if FileAccess.file_exists(exe_p):
			return exe_p
	return ""


func _get_live_url_temp_path() -> String:
	var tmp_dir: String = OS.get_environment("TEMP")
	if tmp_dir.is_empty():
		tmp_dir = OS.get_user_data_dir()
	return tmp_dir.path_join("pirate_game_live_url.txt")


func _check_live_tunnel_url_file() -> void:
	if _live_url_file_path.is_empty() or not FileAccess.file_exists(_live_url_file_path):
		return
	var f: FileAccess = FileAccess.open(_live_url_file_path, FileAccess.READ)
	if f == null:
		return
	var content: String = f.get_as_text().strip_edges()
	f.close()
	if content.begins_with("ws://") or content.begins_with("wss://"):
		_public_tunnel_watch_timer = -1.0
		if _url_input != null:
			_url_input.text = content
		set_status("Öffentliche URL bereit: %s" % content)


func _make_label(txt: String, font_size: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.horizontal_alignment = align
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.07, 0.88))
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	return lbl


func _make_gold_divider(alpha: float = 0.6) -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.color = Color(0.75, 0.58, 0.28, alpha)
	return line


func _style_line_edit(le: LineEdit) -> void:
	le.add_theme_font_size_override("font_size", 15)
	le.add_theme_color_override("font_color", Color(0.96, 0.93, 0.85))
	le.add_theme_color_override("font_placeholder_color", Color(0.60, 0.58, 0.52))
	le.add_theme_color_override("caret_color", Color(0.96, 0.82, 0.36))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.04, 0.05, 0.09, 0.95)
	normal.border_color = Color(0.54, 0.43, 0.24, 0.9)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.92, 0.74, 0.34, 1.0)
	le.add_theme_stylebox_override("normal", normal)
	le.add_theme_stylebox_override("focus", focus)


func _make_menu_button(txt: String, bg: Color, font_size: int = 15) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color(0.98, 0.94, 0.85))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.90))
	btn.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.07, 0.9))
	btn.add_theme_constant_override("outline_size", 1)
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = Color(0.84, 0.66, 0.34, 0.95)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.14)
	hover.border_color = Color(0.98, 0.82, 0.44, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.15)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn

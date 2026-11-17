class_name StartMenuUI
extends Control
## Start menu overlay for Solo (with local save/resume) & One-World Multiplayer
## with simple Username + Password registration/login and session persistence.

signal solo_requested(captain_name: String, server_url: String)
signal solo_new_requested(captain_name: String, server_url: String)
signal join_multiplayer_requested(url: String, captain_name: String)
signal join_multiplayer_auth_requested(url: String, username: String, secret: String, auth_mode: String)
signal reconnect_requested()
signal creative_requested()

const ServerConfigScript := preload("res://net/server_config.gd")
const SaveStoreScript := preload("res://sim/save_store.gd")

var _save_store: SaveStoreScript = SaveStoreScript.new()
var _local_store: SaveStoreScript = SaveStoreScript.new(SaveStoreScript.DEFAULT_LOCAL_ACCOUNTS_DIR)
var _local_auth_expanded: bool = false

var _outer_panel: PanelContainer = null
var _solo_info_label: Label = null
var _solo_continue_btn: Button = null
var _solo_new_btn: Button = null
var _solo_account_btn: Button = null
var _local_auth_box: VBoxContainer = null
var _local_username_input: LineEdit = null
var _local_password_input: LineEdit = null

var _url_input: LineEdit = null
var _auth_form_box: VBoxContainer = null
var _username_input: LineEdit = null
var _password_input: LineEdit = null
var _login_btn: Button = null
var _register_btn: Button = null

var _logged_in_box: VBoxContainer = null
var _account_label: Label = null
var _logout_btn: Button = null
var _join_saved_btn: Button = null

var _status_label: Label = null
var _reconnect_btn: Button = null
var _public_btn: Button = null
var _creative_box: HBoxContainer = null
var _creative_code_input: LineEdit = null
var _creative_start_btn: Button = null
var _public_tunnel_watch_timer: float = -1.0
var _public_tunnel_poll_accum: float = 0.0
var _live_url_file_path: String = ""


func _ready() -> void:
	name = "StartScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	refresh_menu_state()


func _process(delta: float) -> void:
	if _public_tunnel_watch_timer > 0.0:
		_public_tunnel_watch_timer -= delta
		_public_tunnel_poll_accum += delta
		if _public_tunnel_poll_accum >= 0.45:
			_public_tunnel_poll_accum = 0.0
			_check_live_tunnel_url_file()


func get_captain_name() -> String:
	if ServerConfigScript.has_local_auth():
		var local_u: String = ServerConfigScript.load_local_username()
		if not local_u.is_empty():
			return local_u
	if ServerConfigScript.has_mp_auth_for_url(get_url_text()):
		var saved_u: String = ServerConfigScript.load_mp_username()
		if not saved_u.is_empty():
			return saved_u
	var cap: String = _username_input.text.strip_edges() if _username_input != null else ""
	if not cap.is_empty():
		return cap
	return ServerConfigScript.load_captain_name("Käpt'n Rotbart")


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
	refresh_menu_state()
	set_reconnect_visible(true)
	set_status(reason, Color(0.98, 0.48, 0.42))


func show_auth_error(reason: String, clear_saved_auth: bool = false) -> void:
	if clear_saved_auth:
		ServerConfigScript.clear_mp_auth(true)
	visible = true
	refresh_menu_state()
	set_reconnect_visible(false)
	set_status(reason, Color(0.98, 0.48, 0.42))


func hide_menu() -> void:
	visible = false
	set_reconnect_visible(false)
	if _creative_box != null:
		_creative_box.visible = false
	if _creative_code_input != null:
		_creative_code_input.text = ""
	_update_panel_bounds()
	if get_viewport() != null:
		get_viewport().gui_release_focus()


func refresh_menu_state() -> void:
	_refresh_solo_section()
	_refresh_auth_section()


func _refresh_solo_section() -> void:
	var has_local_account: bool = false
	var local_user: String = ""
	var local_summary: Dictionary = {}
	if ServerConfigScript.has_local_auth():
		var res: Dictionary = _local_store.login_with_token(ServerConfigScript.load_local_username(), ServerConfigScript.load_local_session_token())
		if bool(res.get("ok", false)):
			has_local_account = true
			local_user = str(res["username"])
			local_summary = _local_store.get_account_save_summary(str(res["username_key"]))
		else:
			ServerConfigScript.clear_local_auth(true)

	if has_local_account:
		_local_auth_expanded = false
		var tier: int = clampi(int(local_summary.get("hull_tier", 0)), 0, Contracts.ShipClass.MAN_O_WAR)
		var cname: String = str(Contracts.get_ship_class_spec(tier).get("name", "Schaluppe"))
		var gold: int = int(local_summary.get("gold", SaveStoreScript.DEFAULT_GOLD))
		if _solo_info_label != null:
			_solo_info_label.visible = true
			_solo_info_label.add_theme_color_override("font_color", Color(0.55, 0.90, 0.68))
			_solo_info_label.text = "Lokal-Konto '%s': %s • %d Gold" % [local_user, cname, gold]
		if _solo_continue_btn != null:
			_solo_continue_btn.text = "Als '%s' Solo Laden" % local_user
		if _solo_new_btn != null:
			_solo_new_btn.visible = true
		if _solo_account_btn != null:
			_solo_account_btn.text = "Lokal Abmelden"
	elif _save_store.has_solo_save():
		var data: Dictionary = _save_store.load_solo()
		var tier: int = clampi(int(data.get("hull_tier", 0)), 0, Contracts.ShipClass.MAN_O_WAR)
		var cname: String = str(Contracts.get_ship_class_spec(tier).get("name", "Schaluppe"))
		var gold: int = int(data.get("gold", SaveStoreScript.DEFAULT_GOLD))
		if _solo_info_label != null:
			_solo_info_label.visible = true
			_solo_info_label.add_theme_color_override("font_color", Color(0.75, 0.92, 0.82))
			_solo_info_label.text = "Standard-Spielstand: %s • %d Gold (ohne Login)" % [cname, gold]
		if _solo_continue_btn != null:
			_solo_continue_btn.text = "Solo Fortsetzen"
		if _solo_new_btn != null:
			_solo_new_btn.visible = true
		if _solo_account_btn != null:
			_solo_account_btn.text = "Konto laden (Optional)"
	else:
		if _solo_info_label != null:
			_solo_info_label.visible = true
			_solo_info_label.add_theme_color_override("font_color", Color(0.76, 0.80, 0.84))
			_solo_info_label.text = "Ohne Login spielen oder optional lokalen Konto-Spielstand laden."
		if _solo_continue_btn != null:
			_solo_continue_btn.text = "Lokal / Solo Spielen"
		if _solo_new_btn != null:
			_solo_new_btn.visible = false
		if _solo_account_btn != null:
			_solo_account_btn.text = "Konto laden (Optional)"

	if _local_auth_box != null:
		_local_auth_box.visible = (not has_local_account) and _local_auth_expanded
		if _local_auth_box.visible and _local_username_input != null and _local_username_input.text.strip_edges().is_empty():
			var prev_u: String = ServerConfigScript.load_local_username()
			if not prev_u.is_empty():
				_local_username_input.text = prev_u
	_update_panel_bounds()


func _update_panel_bounds() -> void:
	if _outer_panel == null:
		return
	var half_h: float = 284.0
	if _local_auth_box != null and _local_auth_box.visible:
		half_h += 34.0
	if _creative_box != null and _creative_box.visible:
		half_h += 38.0
	_outer_panel.offset_top = -half_h
	_outer_panel.offset_bottom = half_h


func _refresh_auth_section() -> void:
	var url: String = get_url_text()
	var has_auth: bool = ServerConfigScript.has_mp_auth_for_url(url)
	var saved_user: String = ServerConfigScript.load_mp_username()
	if _auth_form_box != null:
		_auth_form_box.visible = not has_auth
	if _logged_in_box != null:
		_logged_in_box.visible = has_auth
	if has_auth:
		if _account_label != null:
			_account_label.text = "Angemeldet als: %s" % saved_user
		if _join_saved_btn != null:
			_join_saved_btn.text = "Als '%s' One-World Beitreten" % saved_user
		set_status("Konto '%s' bereit – Spielstand wird auf dem Server gespeichert." % saved_user, Color(0.55, 0.90, 0.68))
	else:
		if _username_input != null and _username_input.text.strip_edges().is_empty() and not saved_user.is_empty():
			_username_input.text = saved_user
		set_status("Erster Multiplayer-Start: Bitte kurz anmelden oder neues Konto registrieren.", Color(0.95, 0.78, 0.42))


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.05, 0.09, 0.62)
	add_child(dim)

	_outer_panel = PanelContainer.new()
	_outer_panel.anchor_left = 0.5
	_outer_panel.anchor_top = 0.5
	_outer_panel.anchor_right = 0.5
	_outer_panel.anchor_bottom = 0.5
	_outer_panel.offset_left = -365.0
	_outer_panel.offset_top = -284.0
	_outer_panel.offset_right = 365.0
	_outer_panel.offset_bottom = 284.0
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color(0.14, 0.10, 0.07, 0.98)
	outer_style.border_color = Color(0.87, 0.69, 0.32, 0.95)
	outer_style.set_border_width_all(2)
	outer_style.set_corner_radius_all(8)
	outer_style.set_content_margin_all(6)
	outer_style.shadow_color = Color(0.0, 0.0, 0.0, 0.60)
	outer_style.shadow_size = 10
	_outer_panel.add_theme_stylebox_override("panel", outer_style)
	add_child(_outer_panel)

	var inner_panel := PanelContainer.new()
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color(0.075, 0.085, 0.13, 0.97)
	inner_style.border_color = Color(0.58, 0.45, 0.22, 0.90)
	inner_style.set_border_width_all(1)
	inner_style.set_corner_radius_all(5)
	inner_style.content_margin_left = 24
	inner_style.content_margin_right = 24
	inner_style.content_margin_top = 16
	inner_style.content_margin_bottom = 16
	inner_panel.add_theme_stylebox_override("panel", inner_style)
	_outer_panel.add_child(inner_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 9)
	inner_panel.add_child(vbox)

	var title := _make_label("HIGH SEAS PIXEL PRIVATEER", 25, Color(0.98, 0.85, 0.36), HORIZONTAL_ALIGNMENT_CENTER)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_creative_trigger_gui_input)
	vbox.add_child(title)
	var sub := _make_label("2D Segel-Diorama  •  Dredge-Frachtgrid  •  One-World Multiplayer", 14, Color(0.86, 0.83, 0.74), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(sub)
	vbox.add_child(_make_label("SOLO-ABENTEUER (LOKALER SPIELSTAND)", 14, Color(0.46, 0.86, 0.76)))

	_solo_info_label = _make_label("", 13, Color(0.75, 0.92, 0.82))
	_solo_info_label.visible = false
	vbox.add_child(_solo_info_label)

	var solo_row := HBoxContainer.new()
	solo_row.add_theme_constant_override("separation", 10)
	vbox.add_child(solo_row)

	_solo_continue_btn = _make_menu_button("Lokal / Solo Spielen", Color(0.16, 0.41, 0.26), 16)
	_solo_continue_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_solo_continue_btn.pressed.connect(_on_solo_btn_pressed)
	solo_row.add_child(_solo_continue_btn)

	_solo_new_btn = _make_menu_button("Neues Solo", Color(0.40, 0.25, 0.14), 14)
	_solo_new_btn.visible = false
	_solo_new_btn.pressed.connect(_on_solo_new_pressed)
	solo_row.add_child(_solo_new_btn)

	_solo_account_btn = _make_menu_button("Konto laden (Optional)", Color(0.20, 0.30, 0.38), 13)
	_solo_account_btn.pressed.connect(_on_solo_account_btn_pressed)
	solo_row.add_child(_solo_account_btn)

	_local_auth_box = VBoxContainer.new()
	_local_auth_box.visible = false
	_local_auth_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_local_auth_box)

	var local_cred_row := HBoxContainer.new()
	local_cred_row.add_theme_constant_override("separation", 8)
	_local_auth_box.add_child(local_cred_row)

	_local_username_input = LineEdit.new()
	_local_username_input.placeholder_text = "Lokaler Benutzername (3-20)..."
	_local_username_input.max_length = 20
	_local_username_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_line_edit(_local_username_input)
	local_cred_row.add_child(_local_username_input)

	_local_password_input = LineEdit.new()
	_local_password_input.placeholder_text = "Passwort (min. 3 Zeichen)..."
	_local_password_input.secret = true
	_local_password_input.secret_character = "*"
	_local_password_input.max_length = 64
	_local_password_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_local_password_input.text_submitted.connect(func(_t: String): _submit_local_credentials(false))
	_style_line_edit(_local_password_input)
	local_cred_row.add_child(_local_password_input)

	var local_btn_row := HBoxContainer.new()
	local_btn_row.add_theme_constant_override("separation", 8)
	_local_auth_box.add_child(local_btn_row)

	var local_login_btn := _make_menu_button("Lokal Spielstand Laden", Color(0.18, 0.38, 0.32), 14)
	local_login_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	local_login_btn.pressed.connect(func(): _submit_local_credentials(false))
	local_btn_row.add_child(local_login_btn)

	var local_reg_btn := _make_menu_button("Lokal Konto Anlegen", Color(0.24, 0.34, 0.44), 14)
	local_reg_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	local_reg_btn.pressed.connect(func(): _submit_local_credentials(true))
	local_btn_row.add_child(local_reg_btn)

	vbox.add_child(_make_gold_divider(0.65))
	vbox.add_child(_make_label("ONE-WORLD MULTIPLAYER (KONTO & ONLINE-SPEICHERUNG)", 14, Color(0.95, 0.78, 0.40)))

	var url_row := HBoxContainer.new()
	url_row.add_theme_constant_override("separation", 8)
	vbox.add_child(url_row)
	var url_lbl := _make_label("Server:", 14, Color(0.82, 0.80, 0.72))
	url_row.add_child(url_lbl)
	_url_input = LineEdit.new()
	_url_input.text = ServerConfigScript.get_initial_server_url()
	_url_input.placeholder_text = "wss://... oder ws://localhost:8080"
	_url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_input.text_changed.connect(func(_new_txt: String): _refresh_auth_section())
	_style_line_edit(_url_input)
	url_row.add_child(_url_input)

	# State A: First start / logged-out Username + Password form
	_auth_form_box = VBoxContainer.new()
	_auth_form_box.add_theme_constant_override("separation", 8)
	vbox.add_child(_auth_form_box)

	var cred_row := HBoxContainer.new()
	cred_row.add_theme_constant_override("separation", 10)
	_auth_form_box.add_child(cred_row)

	_username_input = LineEdit.new()
	_username_input.placeholder_text = "Benutzername (min. 3 Zeichen)..."
	_username_input.max_length = 20
	_username_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_line_edit(_username_input)
	cred_row.add_child(_username_input)

	_password_input = LineEdit.new()
	_password_input.placeholder_text = "Passwort (min. 3 Zeichen)..."
	_password_input.secret = true
	_password_input.secret_character = "*"
	_password_input.max_length = 64
	_password_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_password_input.text_submitted.connect(func(_t: String): _submit_credentials("login"))
	_style_line_edit(_password_input)
	cred_row.add_child(_password_input)

	var auth_btn_row := HBoxContainer.new()
	auth_btn_row.add_theme_constant_override("separation", 10)
	_auth_form_box.add_child(auth_btn_row)

	_login_btn = _make_menu_button("Anmelden & Beitreten", Color(0.16, 0.34, 0.54), 15)
	_login_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_login_btn.pressed.connect(func(): _submit_credentials("login"))
	auth_btn_row.add_child(_login_btn)

	_register_btn = _make_menu_button("Registrieren & Beitreten", Color(0.14, 0.44, 0.40), 15)
	_register_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_register_btn.pressed.connect(func(): _submit_credentials("register"))
	auth_btn_row.add_child(_register_btn)

	# State B: Remembered session box
	_logged_in_box = VBoxContainer.new()
	_logged_in_box.visible = false
	_logged_in_box.add_theme_constant_override("separation", 8)
	vbox.add_child(_logged_in_box)

	var acct_row := HBoxContainer.new()
	acct_row.add_theme_constant_override("separation", 10)
	_logged_in_box.add_child(acct_row)

	_account_label = _make_label("Angemeldet als: Käpt'n", 15, Color(0.55, 0.90, 0.68))
	_account_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acct_row.add_child(_account_label)

	_logout_btn = _make_menu_button("Abmelden / Konto wechseln", Color(0.42, 0.22, 0.20), 13)
	_logout_btn.pressed.connect(_on_logout_pressed)
	acct_row.add_child(_logout_btn)

	_join_saved_btn = _make_menu_button("One-World Beitreten", Color(0.16, 0.34, 0.54), 16)
	_join_saved_btn.pressed.connect(_on_join_saved_pressed)
	_logged_in_box.add_child(_join_saved_btn)

	var mp_extra_row := HBoxContainer.new()
	mp_extra_row.add_theme_constant_override("separation", 10)
	vbox.add_child(mp_extra_row)

	_public_btn = _make_menu_button("Öffentlichen Server / Browser-Link starten", Color(0.42, 0.26, 0.14), 14)
	_public_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_public_btn.visible = not OS.has_feature("web")
	_public_btn.pressed.connect(_on_public_server_pressed)
	mp_extra_row.add_child(_public_btn)

	_reconnect_btn = _make_menu_button("Erneut verbinden", Color(0.56, 0.31, 0.14), 14)
	_reconnect_btn.visible = false
	_reconnect_btn.pressed.connect(func(): reconnect_requested.emit())
	mp_extra_row.add_child(_reconnect_btn)

	_status_label = _make_label("", 14, Color(0.95, 0.78, 0.42), HORIZONTAL_ALIGNMENT_CENTER)
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
	legend_box.add_child(_make_label("WASD: Segel & Ruder  •  Q/E: Breitseite  •  Space: Bug  •  Tab/I: Schiffs-Grid  •  F: Hafen & Beute  •  M: Seekarte", 13, Color(0.84, 0.82, 0.75), HORIZONTAL_ALIGNMENT_CENTER))

	_creative_box = HBoxContainer.new()
	_creative_box.visible = false
	_creative_box.add_theme_constant_override("separation", 8)
	vbox.add_child(_creative_box)

	_creative_code_input = LineEdit.new()
	_creative_code_input.placeholder_text = "Test-Code..."
	_creative_code_input.max_length = 24
	_creative_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creative_code_input.text_submitted.connect(func(_t: String): _submit_creative_code())
	_style_line_edit(_creative_code_input)
	_creative_box.add_child(_creative_code_input)

	_creative_start_btn = _make_menu_button("Start", Color(0.28, 0.22, 0.44), 14)
	_creative_start_btn.pressed.connect(_submit_creative_code)
	_creative_box.add_child(_creative_start_btn)

	var footer_row := HBoxContainer.new()
	vbox.add_child(footer_row)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(footer_spacer)
	var version_lbl := _make_label("v1.3", 11, Color(0.56, 0.55, 0.52, 0.62), HORIZONTAL_ALIGNMENT_RIGHT)
	version_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	version_lbl.gui_input.connect(_on_creative_trigger_gui_input)
	footer_row.add_child(version_lbl)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var kev := event as InputEventKey
		if kev.pressed and not kev.echo and kev.keycode == KEY_F9:
			toggle_creative_box()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()


func toggle_creative_box(force_open: int = -1) -> void:
	if _creative_box == null:
		return
	var next_vis: bool = (not _creative_box.visible) if force_open < 0 else (force_open > 0)
	_creative_box.visible = next_vis
	_update_panel_bounds()
	if next_vis and _creative_code_input != null and _creative_code_input.is_inside_tree():
		_creative_code_input.grab_focus()


func _on_creative_trigger_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			toggle_creative_box()


func _submit_creative_code() -> void:
	var code: String = _creative_code_input.text.strip_edges().to_lower() if _creative_code_input != null else ""
	if code in ["777", "dev", "pirat"]:
		if _creative_code_input != null:
			_creative_code_input.text = ""
		if _creative_box != null:
			_creative_box.visible = false
		_update_panel_bounds()
		creative_requested.emit()
	else:
		set_status("Ungültiger Code.", Color(0.75, 0.72, 0.68))


func _on_solo_btn_pressed() -> void:
	var cap_name: String = get_captain_name()
	var url_val: String = get_url_text()
	ServerConfigScript.save_profile(cap_name, url_val)
	solo_requested.emit(cap_name, url_val)


func _on_solo_new_pressed() -> void:
	var cap_name: String = get_captain_name()
	var url_val: String = get_url_text()
	ServerConfigScript.save_profile(cap_name, url_val)
	solo_new_requested.emit(cap_name, url_val)


func _on_solo_account_btn_pressed() -> void:
	if ServerConfigScript.has_local_auth():
		ServerConfigScript.clear_local_auth(true)
		_local_auth_expanded = false
		_refresh_solo_section()
		set_status("Vom lokalen Konto abgemeldet – Solo nutzt wieder Standard-Spielstand.", Color(0.95, 0.78, 0.42))
		return
	_local_auth_expanded = not _local_auth_expanded
	_refresh_solo_section()


func _submit_local_credentials(is_register: bool) -> void:
	var raw_user: String = _local_username_input.text if _local_username_input != null else ""
	var raw_pass: String = _local_password_input.text if _local_password_input != null else ""
	var res: Dictionary = _local_store.register_account(raw_user, raw_pass) if is_register else _local_store.login_account(raw_user, raw_pass)
	if not bool(res.get("ok", false)):
		set_status(str(res.get("error", "Lokale Anmeldung fehlgeschlagen.")), Color(0.98, 0.48, 0.42))
		return
	var clean_user: String = str(res["username"])
	var token: String = str(res["session_token"])
	ServerConfigScript.save_local_auth(clean_user, token)
	if _local_password_input != null:
		_local_password_input.text = ""
	_local_auth_expanded = false
	_refresh_solo_section()
	var msg: String = "Lokales Konto '%s' erstellt!" % clean_user if is_register else "Lokaler Spielstand für '%s' geladen!" % clean_user
	set_status(msg + " Klicke oben auf Laden/Fortsetzen.", Color(0.55, 0.90, 0.68))


func _submit_credentials(auth_mode: String) -> void:
	var url: String = get_url_text()
	var raw_user: String = _username_input.text if _username_input != null else ""
	var raw_pass: String = _password_input.text if _password_input != null else ""
	var uv: Dictionary = SaveStoreScript.validate_username(raw_user)
	if not bool(uv["ok"]):
		set_status(str(uv["error"]), Color(0.98, 0.48, 0.42))
		return
	var pv: Dictionary = SaveStoreScript.validate_password(raw_pass)
	if not bool(pv["ok"]):
		set_status(str(pv["error"]), Color(0.98, 0.48, 0.42))
		return

	var clean_user: String = str(uv["clean"])
	ServerConfigScript.save_profile(clean_user, url)
	set_reconnect_visible(false)
	var action_txt: String = "Registriere '%s'" if auth_mode == "register" else "Melde '%s' an"
	if ServerConfigScript.is_placeholder_url(url):
		set_status("%s auf %s (Auto-Host)..." % [action_txt % clean_user, ServerConfigScript.LOCAL_SERVER_URL])
	else:
		set_status("%s auf %s..." % [action_txt % clean_user, NetworkManager.normalize_ws_url(url)])
	join_multiplayer_auth_requested.emit(url, clean_user, raw_pass, auth_mode)


func _on_join_saved_pressed() -> void:
	var url: String = get_url_text()
	if not ServerConfigScript.has_mp_auth_for_url(url):
		_refresh_auth_section()
		return
	var saved_user: String = ServerConfigScript.load_mp_username()
	var saved_token: String = ServerConfigScript.load_mp_session_token()
	ServerConfigScript.save_profile(saved_user, url)
	set_reconnect_visible(false)
	set_status("Verbinde als '%s' mit One-World..." % saved_user)
	join_multiplayer_auth_requested.emit(url, saved_user, saved_token, "token")


func _on_logout_pressed() -> void:
	ServerConfigScript.clear_mp_auth(true)
	if _password_input != null:
		_password_input.text = ""
	set_reconnect_visible(false)
	_refresh_auth_section()


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
		_refresh_auth_section()
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

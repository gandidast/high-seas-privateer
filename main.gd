class_name Main
extends Node
## Main game orchestrator for High Seas Pixel Privateer.
## Handles Headless Dedicated Server (--server) without loading visual/UI scripts,
## as well as Solo and WebSocket Client ("One-World") modes with 2D pixel visuals and UI.

const WORLD_MAP_PATH: String = "res://sim/world_map.gd"
const SHIP_PHYSICS_PATH: String = "res://sim/ship_physics.gd"
const DREDGE_GRID_PATH: String = "res://sim/dredge_grid.gd"

const OCEAN_RENDERER_PATH: String = "res://visual/ocean_renderer.gd"
const SHIP_RENDERER_PATH: String = "res://visual/ship_stack_renderer.gd"
const PIXEL_CAMERA_PATH: String = "res://visual/pixel_camera.gd"
const FX_MANAGER_PATH: String = "res://visual/fx_manager.gd"
const CARGO_GRID_UI_PATH: String = "res://ui/cargo_grid_ui.gd"
const ServerConfigScript := preload("res://net/server_config.gd")

var is_headless_server: bool = false
var game_started: bool = false
var world_seed: int = Contracts.DEFAULT_WORLD_SEED

# Core Simulation
var world_map: Node = null
var combat_system: CombatSystem = null
var loot_system: LootSystem = null
var ai_director: AIDirector = null
var network_manager: NetworkManager = null

# Ships & Local Player
var all_ships: Dictionary = {}       # ship_id (int) -> ShipPhysics Node
var ship_renderers: Dictionary = {}  # ship_id (int) -> ShipStackRenderer Node2D
var player_ship: Node = null
var player_grid: Node = null
var player_ship_id: int = 1
var _respawn_timer: float = -1.0
var _client_desired_sail_state: int = Contracts.SailState.ANCHORED
var _has_initial_player_snapshot: bool = false
var _remote_extrap_age: Dictionary = {} # ship_id (int) -> float
var _server_respawn_timers: Dictionary = {} # peer_id (int) -> float

# Visuals & UI (only instantiated in non-server mode)
# Hybrid pipeline: 2D world runs inside a 640x360 SubViewport (stretched 2x Nearest),
# while UILayer (CanvasLayer) renders outside at crisp 1280x720+ HD resolution.
var world_viewport_container: SubViewportContainer = null
var world_subviewport: SubViewport = null
var world_root: Node2D = null
var ocean_renderer: Node2D = null
var fx_manager: Node2D = null
var pixel_camera: Camera2D = null
var ui_layer: CanvasLayer = null
var hud_overlay: HudOverlay = null
var harbor_ui: HarborUI = null
var cargo_grid_ui: Control = null

# Start Screen UI
var _start_screen: Control = null
var _url_input: LineEdit = null
var _name_input: LineEdit = null
var _status_label: Label = null
var _join_btn: Button = null
var _reconnect_btn: Button = null
var _public_btn: Button = null
var _public_tunnel_watch_timer: float = -1.0
var _public_tunnel_poll_accum: float = 0.0
var _live_url_file_path: String = ""

var _ship_physics_script: Script = null
var _ship_renderer_script: Script = null


func _bus() -> Contracts:
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		return st.root.get_node_or_null("EventBus") as Contracts
	return null


func _ready() -> void:
	name = "Main"
	_ship_physics_script = load(SHIP_PHYSICS_PATH) as Script

	network_manager = NetworkManager.new()
	network_manager.name = "NetworkManager"
	add_child(network_manager)

	var is_headless_display: bool = DisplayServer.get_name() == "headless"
	var server_flag: bool = NetworkManager.is_server_mode_requested()

	if server_flag or (is_headless_display and server_flag):
		is_headless_server = true
		_boot_headless_server()
	else:
		is_headless_server = false
		_boot_client_or_solo_menu()


# ==============================================================================
# HEADLESS SERVER BOOT & LOOP (Zero visual / UI dependencies)
# ==============================================================================

func _boot_headless_server() -> void:
	var port: int = NetworkManager.get_cli_port(Contracts.SERVER_DEFAULT_PORT)
	world_seed = NetworkManager.get_cli_seed(Contracts.DEFAULT_WORLD_SEED)

	_init_simulation(world_seed, true)
	ai_director.populate_initial_fleet(4, 4)
	loot_system.spawn_initial_flotsam(world_map, 10)

	network_manager.bind_simulation(world_map, combat_system, loot_system, ai_director, all_ships)
	network_manager.peer_ship_joined.connect(_on_server_peer_joined)
	network_manager.peer_ship_left.connect(_on_server_peer_left)

	var err: int = network_manager.start_server(port, world_seed)
	if err != OK:
		push_error("[Main] Dedicated server failed to bind port %d." % port)
		return

	game_started = true
	print("[Main] Dedicated server running (Port %d, Seed %d)." % [port, world_seed])


func _on_server_peer_joined(peer_id: int, captain_name: String) -> void:
	var angle: float = float(peer_id % 12) * (TAU / 12.0)
	var spawn_pos: Vector2 = Vector2(cos(angle), sin(angle)) * 90.0
	if world_map != null and world_map.has_method("find_open_water_near"):
		spawn_pos = world_map.call("find_open_water_near", spawn_pos, 0.22)

	var ship: Node = _create_ship_node(
		peer_id,
		spawn_pos,
		0.0,
		Contracts.ShipFaction.PLAYER,
		captain_name
	)
	var default_stats := Contracts.ShipStats.new()
	default_stats.port_cannons = [
		{ "damage": 14.0, "reload_time": 2.4, "range": 260.0, "projectile_speed": 220.0, "spread_angle_deg": 6.0, "deck_offset_x": -6.0 },
		{ "damage": 14.0, "reload_time": 2.4, "range": 260.0, "projectile_speed": 220.0, "spread_angle_deg": 6.0, "deck_offset_x": 6.0 }
	]
	default_stats.starboard_cannons = [
		{ "damage": 14.0, "reload_time": 2.4, "range": 260.0, "projectile_speed": 220.0, "spread_angle_deg": 6.0, "deck_offset_x": -6.0 },
		{ "damage": 14.0, "reload_time": 2.4, "range": 260.0, "projectile_speed": 220.0, "spread_angle_deg": 6.0, "deck_offset_x": 6.0 }
	]
	ship.call("apply_stats", default_stats)

	all_ships[peer_id] = ship
	combat_system.register_ship(ship)
	var bus := _bus()
	if bus != null:
		bus.ship_spawned.emit(peer_id, {
			"ship_id": peer_id,
			"faction": Contracts.ShipFaction.PLAYER,
			"name": captain_name,
			"world_pos": spawn_pos,
			"heading": 0.0
		})


func _on_server_peer_left(peer_id: int) -> void:
	combat_system.unregister_ship(peer_id)
	var ship: Node = all_ships.get(peer_id, null)
	all_ships.erase(peer_id)
	if is_instance_valid(ship):
		ship.queue_free()
	var bus := _bus()
	if bus != null:
		bus.ship_despawned.emit(peer_id)


# ==============================================================================
# CLIENT / SOLO BOOT & START SCREEN
# ==============================================================================

func _boot_client_or_solo_menu() -> void:
	_ship_renderer_script = load(SHIP_RENDERER_PATH) as Script

	world_viewport_container = SubViewportContainer.new()
	world_viewport_container.name = "GameViewportContainer"
	world_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world_viewport_container.stretch = true
	world_viewport_container.stretch_shrink = 2
	world_viewport_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(world_viewport_container)

	world_subviewport = SubViewport.new()
	world_subviewport.name = "GameSubViewport"
	world_subviewport.size = Vector2i(640, 360)
	world_subviewport.snap_2d_transforms_to_pixel = true
	world_subviewport.snap_2d_vertices_to_pixel = false
	world_subviewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	world_subviewport.handle_input_locally = false
	world_viewport_container.add_child(world_subviewport)

	world_root = Node2D.new()
	world_root.name = "WorldRoot"
	world_Root_configure(world_root)
	world_subviewport.add_child(world_root)

	var ocean_script: Script = load(OCEAN_RENDERER_PATH) as Script
	if ocean_script != null:
		ocean_renderer = ocean_script.new()
		ocean_renderer.name = "OceanRenderer"
		ocean_renderer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		world_root.add_child(ocean_renderer)
		ocean_renderer.call("setup", world_seed)

	var fx_script: Script = load(FX_MANAGER_PATH) as Script
	if fx_script != null:
		fx_manager = fx_script.new()
		fx_manager.name = "FxManager"
		fx_manager.z_index = 20
		fx_manager.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		world_root.add_child(fx_manager)

	var cam_script: Script = load(PIXEL_CAMERA_PATH) as Script
	if cam_script != null:
		pixel_camera = cam_script.new()
		pixel_camera.name = "PixelCamera"
		world_root.add_child(pixel_camera)
		pixel_camera.call("snap_to_pos", Vector2.ZERO)

	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	ui_layer.layer = 10
	add_child(ui_layer)

	_build_start_screen()
	_connect_visual_and_network_signals()


func world_Root_configure(node: Node2D) -> void:
	if node != null:
		node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _build_start_screen() -> void:
	_start_screen = Control.new()
	_start_screen.name = "StartScreen"
	_start_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_start_screen)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.05, 0.09, 0.62)
	_start_screen.add_child(dim)

	# Outer brass/gold frame panel (680x500 for 1280x720 HD resolution)
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
	_start_screen.add_child(outer_panel)

	# Inner marine-slate / mahogany panel (double gold border effect)
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

	var title := Label.new()
	title.text = "HIGH SEAS PIXEL PRIVATEER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color(0.98, 0.85, 0.36))
	_apply_clean_label_font_shadow(title)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "2D Segel-Diorama  •  Dredge-Frachtgrid  •  One-World Multiplayer"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.86, 0.83, 0.74))
	_apply_clean_label_font_shadow(sub)
	vbox.add_child(sub)

	var solo_header := Label.new()
	solo_header.text = "SOLO-ABENTEUER"
	solo_header.add_theme_font_size_override("font_size", 14)
	solo_header.add_theme_color_override("font_color", Color(0.46, 0.86, 0.76))
	_apply_clean_label_font_shadow(solo_header)
	vbox.add_child(solo_header)

	var solo_btn := _make_menu_button("Lokal / Solo Spielen", Color(0.16, 0.41, 0.26), 16)
	solo_btn.pressed.connect(_on_solo_pressed)
	vbox.add_child(solo_btn)

	vbox.add_child(_make_gold_divider(0.65))

	var mp_title := Label.new()
	mp_title.text = "ONE-WORLD MULTIPLAYER (AUTO-HOST & ONLINE)"
	mp_title.add_theme_font_size_override("font_size", 14)
	mp_title.add_theme_color_override("font_color", Color(0.95, 0.78, 0.40))
	_apply_clean_label_font_shadow(mp_title)
	vbox.add_child(mp_title)

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
	_url_input.text = _get_default_multiplayer_url()
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
	_join_btn.pressed.connect(_on_join_multiplayer_pressed)
	mp_action_row.add_child(_join_btn)

	_reconnect_btn = _make_menu_button("Erneut verbinden", Color(0.56, 0.31, 0.14), 15)
	_reconnect_btn.visible = false
	_reconnect_btn.pressed.connect(_on_reconnect_pressed)
	mp_action_row.add_child(_reconnect_btn)

	_public_btn = _make_menu_button("Öffentlichen Server / Browser-Link starten", Color(0.42, 0.26, 0.14), 14)
	_public_btn.pressed.connect(_on_public_server_pressed)
	vbox.add_child(_public_btn)

	_status_label = Label.new()
	_status_label.text = "1 Klick startet lokalen Server automatisch oder verbindet online."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0.0, 38.0)
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.42))
	_apply_clean_label_font_shadow(_status_label)
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

	var legend_lbl := Label.new()
	legend_lbl.text = "WASD: Segel & Ruder  •  Q/E: Breitseite  •  I/Tab: Schiffs-Grid  •  F/Space: Hafen & Beute"
	legend_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend_lbl.add_theme_font_size_override("font_size", 14)
	legend_lbl.add_theme_color_override("font_color", Color(0.84, 0.82, 0.75))
	_apply_clean_label_font_shadow(legend_lbl)
	legend_box.add_child(legend_lbl)


func _process(delta: float) -> void:
	if _public_tunnel_watch_timer > 0.0:
		_public_tunnel_watch_timer -= delta
		_public_tunnel_poll_accum += delta
		if _public_tunnel_poll_accum >= 0.45:
			_public_tunnel_poll_accum = 0.0
			_check_live_tunnel_url_file()


func _on_solo_pressed() -> void:
	var cap_name: String = _name_input.text.strip_edges() if _name_input != null else ""
	var url_val: String = _url_input.text.strip_edges() if _url_input != null else ""
	if not cap_name.is_empty() or not url_val.is_empty():
		ServerConfigScript.save_profile(cap_name, url_val)
	if _start_screen != null:
		_start_screen.visible = false
	if get_viewport() != null:
		get_viewport().gui_release_focus()
	if network_manager == null:
		network_manager = NetworkManager.new()
		network_manager.name = "NetworkManager"
		add_child(network_manager)
	if _ship_physics_script == null:
		_ship_physics_script = load(SHIP_PHYSICS_PATH) as Script
	network_manager.start_solo()
	_start_local_solo_game()


func _on_join_multiplayer_pressed() -> void:
	var url: String = _url_input.text.strip_edges() if _url_input != null else ""
	var cap_name: String = _name_input.text.strip_edges() if _name_input != null else "Käpt'n Rotbart"
	if cap_name.is_empty():
		cap_name = "Käpt'n Rotbart"
	ServerConfigScript.save_profile(cap_name, url)
	if _reconnect_btn != null:
		_reconnect_btn.visible = false
	if _status_label != null:
		_status_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.42))
		if ServerConfigScript.is_placeholder_url(url):
			_status_label.text = "Platzhalter-URL erkannt – weiche auf %s (Auto-Host) aus..." % ServerConfigScript.LOCAL_SERVER_URL
		else:
			_status_label.text = "Verbinde mit One-World (%s)..." % NetworkManager.normalize_ws_url(url)
	network_manager.connect_or_autostart(url, cap_name)


func _on_reconnect_pressed() -> void:
	if _reconnect_btn != null:
		_reconnect_btn.visible = false
	if _status_label != null:
		_status_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.42))
		_status_label.text = "Verbinde erneut mit One-World..."
	if network_manager != null and network_manager.reconnect_last():
		return
	_on_join_multiplayer_pressed()


func _on_public_server_pressed() -> void:
	if OS.has_feature("web"):
		if _status_label != null:
			_status_label.text = "Im Browser läuft bereits der Client – nutze die wss://-Adresse oben."
		return

	var target_url: String = _url_input.text.strip_edges() if _url_input != null else ""
	var port: int = NetworkManager.extract_port_from_url(target_url, Contracts.SERVER_DEFAULT_PORT)
	if not NetworkManager.is_local_url(target_url):
		port = Contracts.SERVER_DEFAULT_PORT

	if OS.get_name() == "Windows":
		var script_path: String = _resolve_host_ps1_script()
		if script_path.is_empty():
			if _status_label != null:
				_status_label.text = "tools/host_local.ps1 und deploy/start_live_multiplayer.ps1 nicht gefunden."
			return
		_live_url_file_path = _get_live_url_temp_path()
		if FileAccess.file_exists(_live_url_file_path):
			DirAccess.remove_absolute(_live_url_file_path)
		var args := PackedStringArray([
			"-NoExit",
			"-ExecutionPolicy", "Bypass",
			"-File", script_path,
			"-Port", str(port)
		])
		var pid: int = OS.create_process("powershell.exe", args, true)
		if pid > 0:
			_public_tunnel_watch_timer = 25.0
			_public_tunnel_poll_accum = 0.0
			if _status_label != null:
				_status_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.42))
				_status_label.text = "Server & wss://-Tunnel starten im Konsolenfenster (Port %d)..." % port
		else:
			if _status_label != null:
				_status_label.add_theme_color_override("font_color", Color(0.98, 0.48, 0.42))
				_status_label.text = "Konnte PowerShell für Tunnel nicht starten."
	else:
		var sh_path: String = _resolve_deploy_script("start_server.sh")
		if sh_path.is_empty():
			if _status_label != null:
				_status_label.text = "deploy/start_server.sh nicht gefunden."
			return
		var pid: int = OS.create_process("bash", PackedStringArray([sh_path]), true)
		if _status_label != null:
			if pid > 0:
				_status_label.text = "Headless-Server auf Port %d gestartet (PID %d)." % [port, pid]
			else:
				_status_label.text = "Starte deploy/start_server.sh manuell im Terminal."


func _on_network_status_changed(status_text: String) -> void:
	if _status_label != null:
		_status_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.42))
		_status_label.text = status_text


func _get_default_multiplayer_url() -> String:
	return ServerConfigScript.get_initial_server_url()


func _resolve_host_ps1_script() -> String:
	var candidates: Array[String] = [
		ProjectSettings.globalize_path("res://tools/host_local.ps1"),
		OS.get_executable_path().get_base_dir().path_join("tools/host_local.ps1"),
		ProjectSettings.globalize_path("res://deploy/start_live_multiplayer.ps1"),
		OS.get_executable_path().get_base_dir().path_join("deploy/start_live_multiplayer.ps1")
	]
	for cand in candidates:
		if not cand.is_empty() and FileAccess.file_exists(cand):
			return cand
	return ""


func _resolve_deploy_script(filename: String) -> String:
	var candidate_res: String = ProjectSettings.globalize_path("res://deploy/" + filename)
	if not candidate_res.is_empty() and FileAccess.file_exists(candidate_res):
		return candidate_res
	var exe_dir: String = OS.get_executable_path().get_base_dir()
	var candidate_exe: String = exe_dir.path_join("deploy/" + filename)
	if FileAccess.file_exists(candidate_exe):
		return candidate_exe
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
		if _status_label != null:
			_status_label.text = "Öffentliche URL bereit: %s" % content


func _start_local_solo_game() -> void:
	_clear_game_world()
	world_seed = Contracts.DEFAULT_WORLD_SEED

	_init_simulation(world_seed, true)
	if ocean_renderer != null:
		ocean_renderer.call("setup", world_seed)

	player_ship_id = 1
	_spawn_local_player(player_ship_id, "Schaluppe Morgenstern", true)

	ai_director.populate_initial_fleet(4, 4)
	loot_system.spawn_initial_flotsam(world_map, 10)

	_init_ui_layers()
	game_started = true
	var bus := _bus()
	if bus != null:
		bus.notification_posted.emit("Leinen los! W/S Segel, A/D Ruder, Q/E Breitseite.", "system")


func _on_network_client_joined(assigned_ship_id: int, server_seed: int) -> void:
	_clear_game_world()
	_client_desired_sail_state = Contracts.SailState.ANCHORED
	_has_initial_player_snapshot = false
	_remote_extrap_age.clear()
	if _reconnect_btn != null:
		_reconnect_btn.visible = false
	if _start_screen != null:
		_start_screen.visible = false
	if get_viewport() != null:
		get_viewport().gui_release_focus()
	if get_viewport() != null:
		get_viewport().gui_release_focus()

	world_seed = server_seed
	player_ship_id = assigned_ship_id

	# Client simulation runs non-authoritatively (world_map for visuals/queries, loot_system synced)
	_init_simulation(world_seed, false)
	if ocean_renderer != null:
		ocean_renderer.call("setup", world_seed)

	var cap_name: String = network_manager.local_captain_name
	_spawn_local_player(player_ship_id, cap_name, true)

	_init_ui_layers()
	if player_grid != null and player_grid.has_method("compile_stats"):
		var stats: Contracts.ShipStats = player_grid.call("compile_stats")
		network_manager.send_player_stats(stats)

	game_started = true
	var bus := _bus()
	if bus != null:
		bus.notification_posted.emit("Mit One-World verbunden (Schiff #%d)!" % player_ship_id, "net")


func _on_network_client_disconnected(reason: String) -> void:
	game_started = false
	_clear_game_world()
	if _start_screen != null:
		_start_screen.visible = true
	if _reconnect_btn != null:
		_reconnect_btn.visible = true
	if _status_label != null:
		_status_label.add_theme_color_override("font_color", Color(0.98, 0.48, 0.42))
		_status_label.text = reason


# ==============================================================================
# SIMULATION, PLAYER & UI WIRING
# ==============================================================================

func _init_simulation(p_seed: int, authoritative: bool) -> void:
	var wm_script: Script = load(WORLD_MAP_PATH) as Script
	world_map = wm_script.new()
	world_map.name = "WorldMap"
	add_child(world_map)
	world_map.call("setup", p_seed)

	combat_system = CombatSystem.new()
	combat_system.name = "CombatSystem"
	add_child(combat_system)
	if authoritative:
		combat_system.setup_island_forts(world_map)

	loot_system = LootSystem.new()
	loot_system.name = "LootSystem"
	add_child(loot_system)
	loot_system.setup(world_map, authoritative)

	ai_director = AIDirector.new()
	ai_director.name = "AIDirector"
	add_child(ai_director)
	ai_director.setup(world_map, combat_system)


func _spawn_local_player(p_ship_id: int, p_name: String, register_combat: bool) -> void:
	var start_pos: Vector2 = Vector2.ZERO
	if world_map != null and world_map.has_method("find_open_water_near"):
		start_pos = world_map.call("find_open_water_near", Vector2.ZERO, 0.22)

	player_ship = _create_ship_node(p_ship_id, start_pos, -0.35, Contracts.ShipFaction.PLAYER, p_name)
	all_ships[p_ship_id] = player_ship

	var grid_script: Script = load(DREDGE_GRID_PATH) as Script
	if grid_script != null:
		player_grid = grid_script.new()
		player_grid.name = "PlayerDredgeGrid"
		player_grid.set("ship_id", p_ship_id)
		add_child(player_grid)
		player_grid.call("populate_starter_loadout")
		var stats: Contracts.ShipStats = player_grid.call("compile_stats")
		player_ship.call("apply_stats", stats)
		player_ship.set("hp", stats.max_hp)

	if register_combat and combat_system != null:
		combat_system.register_ship(player_ship)

	_ensure_ship_renderer(p_ship_id, Contracts.ShipFaction.PLAYER, p_name, start_pos, -0.35)
	if player_grid != null:
		var compiled: Variant = player_grid.get("current_stats")
		if compiled is Contracts.ShipStats:
			var r: Node2D = ship_renderers.get(p_ship_id, null)
			if r != null:
				r.call("update_equipped_modules", compiled.visual_equipped_items)

	if pixel_camera != null and ship_renderers.has(p_ship_id):
		var target_node: Node2D = ship_renderers[p_ship_id]
		pixel_camera.call("set_follow_target", target_node)
		pixel_camera.call("snap_to_pos", start_pos)


func _init_ui_layers() -> void:
	if hud_overlay == null:
		hud_overlay = HudOverlay.new()
		hud_overlay.name = "HudOverlay"
		ui_layer.add_child(hud_overlay)
	hud_overlay.setup(player_ship, world_map, combat_system, loot_system, _combined_ships_dict(), 120)

	if cargo_grid_ui == null:
		var cg_script: Script = load(CARGO_GRID_UI_PATH) as Script
		if cg_script != null:
			cargo_grid_ui = cg_script.new()
			cargo_grid_ui.name = "CargoGridUI"
			ui_layer.add_child(cargo_grid_ui)
	if cargo_grid_ui != null:
		cargo_grid_ui.call("setup", player_grid, player_ship)

	if harbor_ui == null:
		harbor_ui = HarborUI.new()
		harbor_ui.name = "HarborUI"
		ui_layer.add_child(harbor_ui)
	harbor_ui.setup(player_ship, player_grid, world_map, ai_director, loot_system, 120)


# ==============================================================================
# RUNTIME SIMULATION & RENDERING LOOP
# ==============================================================================

func _physics_process(delta: float) -> void:
	if not game_started:
		return

	if is_headless_server:
		world_map.call("step_wind", delta)
		if world_map.has_method("step_weather"):
			world_map.call("step_weather", delta)
		for sid_var in all_ships.keys():
			var ship: Node = all_ships[sid_var]
			if ship == null:
				continue
			if bool(ship.get("is_sunk")):
				var pid: int = int(sid_var)
				var r_timer: float = float(_server_respawn_timers.get(pid, 3.0)) - delta
				if r_timer <= 0.0:
					_server_respawn_timers.erase(pid)
					var islands: Array = Contracts.get_islands(world_seed)
					var respawn_pos: Vector2 = islands[0].harbor_pos if not islands.is_empty() else Vector2.ZERO
					ship.set("world_pos", respawn_pos)
					ship.set("velocity", Vector2.ZERO)
					ship.set("speed", 0.0)
					ship.set("sail_state", Contracts.SailState.ANCHORED)
					ship.set("is_sunk", false)
					var mhp: float = float(ship.get("max_hp"))
					ship.set("hp", mhp)
				else:
					_server_respawn_timers[pid] = r_timer
				continue
			var steer: float = float(ship.get_meta("net_steer", 0.0))
			ship.call("step_physics", delta, steer, world_map)
		var merged_srv: Dictionary = _combined_ships_dict()
		ai_director.step_ai(delta, merged_srv)
		ai_director.step_sea_monster(delta, merged_srv)
		combat_system.step_ship_collisions(delta, merged_srv)
		combat_system.step_forts(delta, merged_srv)
		combat_system.step_projectiles(delta, world_map)
		loot_system.step_loot(delta, merged_srv, null)
		network_manager.step_network(delta)
		return

	# Solo or Client Mode
	var ui_blocking: bool = _is_ui_open()
	var steer_input: float = 0.0
	if not ui_blocking:
		if Input.is_action_pressed("steer_left"):
			steer_input -= 1.0
		if Input.is_action_pressed("steer_right"):
			steer_input += 1.0

	if network_manager.current_mode == NetworkManager.Mode.SOLO:
		if world_map != null:
			world_map.call("step_wind", delta)
			if world_map.has_method("step_weather"):
				world_map.call("step_weather", delta)

		if player_ship != null:
			if bool(player_ship.get("is_sunk")):
				_step_player_respawn(delta)
			else:
				player_ship.call("step_physics", delta, steer_input, world_map)

		var merged_ships: Dictionary = _combined_ships_dict()
		if ai_director != null:
			ai_director.step_ai(delta, merged_ships)
			ai_director.step_sea_monster(delta, merged_ships)
		if combat_system != null:
			combat_system.step_ship_collisions(delta, merged_ships)
			combat_system.step_forts(delta, merged_ships)
			combat_system.step_projectiles(delta, world_map)
		if loot_system != null:
			var interact_just: bool = not ui_blocking and Input.is_action_just_pressed("interact")
			loot_system.step_loot(delta, merged_ships, player_grid, interact_just)

		if hud_overlay != null:
			hud_overlay.set_ships_dict(merged_ships)
	else:
		# Multiplayer client: 60Hz local ship prediction + remote dead-reckoning for butter-smooth movement
		network_manager.step_network(delta, steer_input, _client_desired_sail_state)
		if world_map != null:
			world_map.call("step_wind", delta)
		if player_ship != null and not bool(player_ship.get("is_sunk")):
			if int(player_ship.get("sail_state")) != _client_desired_sail_state:
				player_ship.call("set_sail_state", _client_desired_sail_state)
			player_ship.call("step_physics", delta, steer_input, world_map)
		_step_client_remote_extrapolation(delta)
		if combat_system != null:
			combat_system.step_reloads(delta)
		if hud_overlay != null:
			hud_overlay.set_ships_dict(all_ships)

	_update_ocean_and_aim_cone()


func _unhandled_input(event: InputEvent) -> void:
	if is_headless_server or not game_started:
		return
	if _is_ui_open():
		return
	if player_ship == null or bool(player_ship.get("is_sunk")):
		return

	if event.is_action_pressed("sail_up"):
		if network_manager.current_mode == NetworkManager.Mode.CLIENT:
			_client_desired_sail_state = clampi(_client_desired_sail_state + 1, Contracts.SailState.ANCHORED, Contracts.SailState.FULL_SAIL)
			player_ship.call("set_sail_state", _client_desired_sail_state)
			network_manager.send_input_immediately(_get_current_steer_input(), _client_desired_sail_state)
		else:
			player_ship.call("change_sail_state", 1)
	elif event.is_action_pressed("sail_down"):
		if network_manager.current_mode == NetworkManager.Mode.CLIENT:
			_client_desired_sail_state = clampi(_client_desired_sail_state - 1, Contracts.SailState.ANCHORED, Contracts.SailState.FULL_SAIL)
			player_ship.call("set_sail_state", _client_desired_sail_state)
			network_manager.send_input_immediately(_get_current_steer_input(), _client_desired_sail_state)
		else:
			player_ship.call("change_sail_state", -1)
	elif event.is_action_pressed("fire_port"):
		_trigger_player_broadside(false)
	elif event.is_action_pressed("fire_starboard"):
		_trigger_player_broadside(true)
	elif event.is_action_pressed("interact"):
		var h_idx: int = int(player_ship.get("current_harbor_index"))
		if h_idx >= 0:
			var open_now: bool = harbor_ui == null or not harbor_ui.visible
			var bus := _bus()
			if bus != null:
				bus.harbor_ui_requested.emit(open_now, h_idx)


func _get_current_steer_input() -> float:
	if _is_ui_open():
		return 0.0
	var s: float = 0.0
	if Input.is_action_pressed("steer_left"):
		s -= 1.0
	if Input.is_action_pressed("steer_right"):
		s += 1.0
	return s


func _trigger_player_broadside(is_starboard: bool) -> void:
	if network_manager.current_mode == NetworkManager.Mode.CLIENT:
		network_manager.send_fire_request(is_starboard)
	elif combat_system != null:
		combat_system.fire_broadside(player_ship_id, is_starboard)


func _update_ocean_and_aim_cone() -> void:
	if ocean_renderer != null and pixel_camera != null:
		ocean_renderer.call("set_camera_center", pixel_camera.global_position)

	if fx_manager == null or player_ship == null or combat_system == null or _is_ui_open():
		if fx_manager != null:
			fx_manager.call("set_broadside_aim_cone", Vector2.ZERO, Vector2.RIGHT, 0.0, 0.0, false)
		return

	# Show broadside cone on the side the mouse cursor points toward (when moving mouse over ocean)
	var mouse_world: Vector2 = _get_world_mouse_position()
	var ship_pos: Vector2 = player_ship.get("world_pos")
	var heading: float = float(player_ship.get("heading"))
	var local_mouse: Vector2 = (mouse_world - ship_pos).rotated(-heading)
	if local_mouse.length() > 14.0 and local_mouse.length() < 320.0 and absf(local_mouse.y) > 8.0:
		var is_sb: bool = local_mouse.y > 0.0
		var cone: Dictionary = combat_system.get_broadside_cone(player_ship_id, is_sb)
		if int(cone.get("total_count", 0)) > 0:
			fx_manager.call(
				"set_broadside_aim_cone",
				cone["origin"],
				cone["dir"],
				float(cone["range"]),
				float(cone["half_angle_rad"]),
				true
			)
			return

	fx_manager.call("set_broadside_aim_cone", Vector2.ZERO, Vector2.RIGHT, 0.0, 0.0, false)


func _get_world_mouse_position() -> Vector2:
	if pixel_camera == null:
		return Vector2.ZERO
	if pixel_camera.has_method("get_world_mouse_pos"):
		return pixel_camera.call("get_world_mouse_pos")
	if world_subviewport != null and world_viewport_container != null and world_viewport_container.is_inside_tree():
		var shrink: float = float(maxi(1, world_viewport_container.stretch_shrink))
		var sv_mouse: Vector2 = world_viewport_container.get_local_mouse_position() / shrink
		return world_subviewport.get_canvas_transform().affine_inverse() * sv_mouse
	return pixel_camera.get_global_mouse_position()


func _step_player_respawn(delta: float) -> void:
	if _respawn_timer < 0.0:
		_respawn_timer = 2.5
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = -1.0
		var islands: Array = Contracts.get_islands(world_seed)
		var respawn_pos: Vector2 = islands[0].harbor_pos if not islands.is_empty() else Vector2.ZERO
		player_ship.set("world_pos", respawn_pos)
		player_ship.set("velocity", Vector2.ZERO)
		player_ship.set("speed", 0.0)
		player_ship.set("sail_state", Contracts.SailState.ANCHORED)
		player_ship.set("is_sunk", false)
		var mhp: float = float(player_ship.get("max_hp"))
		player_ship.set("hp", mhp)
		var bus := _bus()
		if bus != null:
			bus.ship_state_updated.emit(
				player_ship_id, respawn_pos, float(player_ship.get("heading")), 0.0,
				Contracts.SailState.ANCHORED, mhp, mhp
			)
			bus.notification_posted.emit("In Port Tortuga wieder flottgemacht!", "system")


# ==============================================================================
# SNAPSHOT & EVENTBUS VISUAL SYNC
# ==============================================================================

func _connect_visual_and_network_signals() -> void:
	network_manager.client_joined.connect(_on_network_client_joined)
	network_manager.client_disconnected_from_server.connect(_on_network_client_disconnected)
	network_manager.snapshot_received.connect(_on_snapshot_received)
	network_manager.connection_status_changed.connect(_on_network_status_changed)

	var bus := _bus()
	if bus == null:
		return
	bus.ship_spawned.connect(_on_ship_spawned)
	bus.ship_despawned.connect(_on_ship_despawned)
	bus.ship_state_updated.connect(_on_ship_state_updated)
	bus.ship_stats_compiled.connect(_on_ship_stats_compiled)
	bus.ship_grid_updated.connect(_on_ship_grid_updated)
	bus.ship_class_upgraded.connect(_on_ship_class_upgraded)
	bus.ship_repaired.connect(_on_ship_repaired)
	bus.broadside_fired.connect(_on_broadside_fired)
	bus.ship_damaged.connect(_on_ship_damaged)
	bus.ship_sunk.connect(_on_ship_sunk)


func _on_snapshot_received(snapshot: Dictionary) -> void:
	var bus := _bus()
	if world_map != null and snapshot.has("wind_x") and snapshot.has("wind_y"):
		var wd := Vector2(float(snapshot["wind_x"]), float(snapshot["wind_y"])).normalized()
		var ws: float = float(snapshot.get("wind_strength", 0.7))
		world_map.set("wind_direction", wd)
		world_map.set("wind_strength", ws)
		if bus != null:
			bus.wind_changed.emit(wd, ws)

	if bus != null and snapshot.has("weather_state"):
		var wst: int = int(snapshot["weather_state"])
		var wint: float = float(snapshot.get("weather_intensity", 0.0))
		if world_map != null:
			world_map.set("current_weather", wst)
			world_map.set("weather_intensity", wint)
		bus.weather_changed.emit(wst, wint)

	if bus != null and snapshot.has("wanted_level"):
		bus.wanted_level_changed.emit(int(snapshot["wanted_level"]))

	if combat_system != null and snapshot.has("forts"):
		combat_system.apply_fort_sync_array(snapshot["forts"])

	if bus != null and snapshot.has("sea_monster"):
		var md: Variant = snapshot["sea_monster"]
		if md is Dictionary and not md.is_empty():
			var mid: int = int(md.get("monster_id", 5000))
			var mpos := Vector2(float(md.get("x", 0.0)), float(md.get("y", 0.0)))
			var mhp: float = float(md.get("hp", 0.0))
			var mmax: float = float(md.get("max_hp", 320.0))
			var mphase: int = int(md.get("phase", 0))
			var mdef: bool = bool(md.get("defeated", true))
			if not mdef and mhp > 0.0:
				bus.sea_monster_updated.emit(mid, mpos, mhp, mmax, mphase)

	if loot_system != null and snapshot.has("drops"):
		loot_system.apply_sync_array(snapshot["drops"])

	var raw_ships: Array = snapshot.get("ships", [])
	var seen_ids: Dictionary = {}

	for sd_var in raw_ships:
		if not (sd_var is Dictionary):
			continue
		var sd: Dictionary = sd_var
		var sid: int = int(sd.get("ship_id", -1))
		if sid < 0:
			continue
		seen_ids[sid] = true
		_remote_extrap_age[sid] = 0.0

		var ship: Node = all_ships.get(sid, null)
		var is_new_ship: bool = (ship == null)
		if ship == null:
			var fac: int = int(sd.get("faction", Contracts.ShipFaction.PIRATE))
			var sname: String = str(sd.get("ship_name", sd.get("name", "Schiff #%d" % sid)))
			var pos := Vector2(float(sd.get("x", 0.0)), float(sd.get("y", 0.0)))
			var hdg: float = float(sd.get("heading", 0.0))
			ship = _create_ship_node(sid, pos, hdg, fac, sname)
			all_ships[sid] = ship
			_ensure_ship_renderer(sid, fac, sname, pos, hdg)

		var pre_pos: Vector2 = ship.get("world_pos")
		var pre_hdg: float = float(ship.get("heading"))
		var rend: Node2D = ship_renderers.get(sid, null)

		if sid == player_ship_id:
			var was_sunk: bool = bool(ship.get("is_sunk"))
			var srv_is_sunk: bool = bool(sd.get("is_sunk", false))
			var srv_pos := Vector2(float(sd.get("x", pre_pos.x)), float(sd.get("y", pre_pos.y)))
			var srv_hdg: float = float(sd.get("heading", pre_hdg))
			var srv_vel := Vector2(float(sd.get("vx", 0.0)), float(sd.get("vy", 0.0)))
			var srv_speed: float = float(sd.get("speed", srv_vel.length()))

			if not _has_initial_player_snapshot or is_new_ship or srv_is_sunk or was_sunk or pre_pos.distance_to(srv_pos) > 85.0:
				ship.call("apply_sync_dict", sd)
				if rend != null and is_instance_valid(rend) and rend.has_method("clear_visual_offset"):
					rend.call("clear_visual_offset")
				if not _has_initial_player_snapshot and pixel_camera != null:
					pixel_camera.call("snap_to_pos", srv_pos)
				_has_initial_player_snapshot = true
				if srv_is_sunk:
					_client_desired_sail_state = Contracts.SailState.ANCHORED
			else:
				_apply_authoritative_non_kinematic(ship, sd)
				var err_vec: Vector2 = srv_pos - pre_pos
				var err_len: float = err_vec.length()
				var both_idle: bool = (_client_desired_sail_state == Contracts.SailState.ANCHORED and srv_speed < 4.0 and float(ship.get("speed")) < 4.0)
				if both_idle:
					if err_len > 1.0:
						var next_p: Vector2 = pre_pos.lerp(srv_pos, 0.25)
						ship.set("world_pos", next_p)
						ship.set("velocity", (ship.get("velocity") as Vector2).lerp(srv_vel, 0.25))
						if rend != null and is_instance_valid(rend) and rend.has_method("add_visual_offset"):
							rend.call("add_visual_offset", pre_pos - next_p, 0.0)
				elif err_len > 18.0:
					var corr: Vector2 = err_vec.normalized() * ((err_len - 18.0) * 0.35)
					ship.set("world_pos", pre_pos + corr)
					if rend != null and is_instance_valid(rend) and rend.has_method("add_visual_offset"):
						rend.call("add_visual_offset", -corr, 0.0)

				var hdg_diff: float = wrapf(srv_hdg - pre_hdg, -PI, PI)
				if absf(hdg_diff) > 0.16:
					var hdg_corr: float = hdg_diff * 0.25
					ship.set("heading", wrapf(pre_hdg + hdg_corr, -PI, PI))
					if rend != null and is_instance_valid(rend) and rend.has_method("add_visual_offset"):
						rend.call("add_visual_offset", Vector2.ZERO, -hdg_corr)

			player_ship = ship
			if harbor_ui != null:
				harbor_ui.player_ship = ship
			if hud_overlay != null:
				hud_overlay.player_ship = ship
		else:
			ship.call("apply_sync_dict", sd)
			var next_remote_pos: Vector2 = ship.get("world_pos")
			var next_remote_hdg: float = float(ship.get("heading"))
			if not is_new_ship and pre_pos.distance_to(next_remote_pos) < 95.0:
				if rend != null and is_instance_valid(rend) and rend.has_method("add_visual_offset"):
					rend.call("add_visual_offset", pre_pos - next_remote_pos, wrapf(pre_hdg - next_remote_hdg, -PI, PI))
			elif rend != null and is_instance_valid(rend) and rend.has_method("clear_visual_offset"):
				rend.call("clear_visual_offset")

		if sd.has("hull_tier") and rend != null and is_instance_valid(rend) and rend.has_method("set_hull_tier"):
			rend.call("set_hull_tier", int(sd["hull_tier"]))

		if bus != null:
			bus.ship_state_updated.emit(
				sid,
				ship.get("world_pos"),
				float(ship.get("heading")),
				float(ship.get("speed")),
				int(ship.get("sail_state")),
				float(ship.get("hp")),
				float(ship.get("max_hp"))
			)

	# Remove despawned ships from client view
	var to_remove: Array[int] = []
	for existing_var in all_ships.keys():
		var eid: int = int(existing_var)
		if not seen_ids.has(eid) and eid != player_ship_id:
			to_remove.append(eid)
	for eid in to_remove:
		_remote_extrap_age.erase(eid)
		var old_ship: Node = all_ships.get(eid, null)
		all_ships.erase(eid)
		if is_instance_valid(old_ship):
			old_ship.queue_free()
		_on_ship_despawned(eid)


func _step_client_remote_extrapolation(delta: float) -> void:
	var bus := _bus()
	for sid_var in all_ships.keys():
		var sid: int = int(sid_var)
		if sid == player_ship_id:
			continue
		var r_ship: Node = all_ships[sid_var]
		if r_ship == null or not is_instance_valid(r_ship) or bool(r_ship.get("is_sunk")):
			continue
		var age: float = float(_remote_extrap_age.get(sid, 0.0)) + delta
		_remote_extrap_age[sid] = age
		if age > 0.25:
			continue
		var decay_w: float = 1.0 if age < 0.12 else clampf(1.0 - (age - 0.12) / 0.13, 0.0, 1.0)
		var r_pos: Vector2 = r_ship.get("world_pos")
		var r_vel: Vector2 = r_ship.get("velocity")
		var r_hdg: float = float(r_ship.get("heading"))
		var r_ang_vel: float = float(r_ship.get("angular_velocity"))
		r_pos += r_vel * (delta * decay_w)
		r_hdg = wrapf(r_hdg + r_ang_vel * (delta * decay_w), -PI, PI)
		r_ship.set("world_pos", r_pos)
		r_ship.set("heading", r_hdg)
		if bus != null:
			bus.ship_state_updated.emit(
				sid,
				r_pos,
				r_hdg,
				float(r_ship.get("speed")),
				int(r_ship.get("sail_state")),
				float(r_ship.get("hp")),
				float(r_ship.get("max_hp"))
			)


func _apply_authoritative_non_kinematic(ship: Node, sd: Dictionary) -> void:
	ship.set("faction", int(sd.get("faction", ship.get("faction"))))
	ship.set("ship_name", str(sd.get("ship_name", ship.get("ship_name"))))
	var new_tier: int = int(sd.get("hull_tier", ship.get("hull_tier")))
	if new_tier != int(ship.get("hull_tier")):
		ship.set("hull_tier", new_tier)
		if ship.has_method("_sync_hull_radius_for_tier"):
			ship.call("_sync_hull_radius_for_tier")
	ship.set("hp", float(sd.get("hp", ship.get("hp"))))
	ship.set("max_hp", float(sd.get("max_hp", ship.get("max_hp"))))
	ship.set("is_sunk", bool(sd.get("is_sunk", ship.get("is_sunk"))))
	ship.set("chain_slow_timer", float(sd.get("chain_slow_timer", ship.get("chain_slow_timer"))))
	ship.set("burn_timer", float(sd.get("burn_timer", ship.get("burn_timer"))))


func _on_ship_spawned(sid: int, ship_data: Dictionary) -> void:
	if is_headless_server:
		return
	var fac: int = int(ship_data.get("faction", Contracts.ShipFaction.PIRATE))
	var sname: String = str(ship_data.get("name", "Schiff"))
	var pos: Vector2 = ship_data.get("world_pos", Vector2.ZERO)
	var hdg: float = float(ship_data.get("heading", 0.0))
	_ensure_ship_renderer(sid, fac, sname, pos, hdg)
	if ship_data.has("hull_tier") and ship_renderers.has(sid):
		var r: Node2D = ship_renderers[sid]
		if r != null and r.has_method("set_hull_tier"):
			r.call("set_hull_tier", int(ship_data["hull_tier"]))


func _on_ship_despawned(sid: int) -> void:
	if ship_renderers.has(sid):
		var r: Node2D = ship_renderers[sid]
		ship_renderers.erase(sid)
		if is_instance_valid(r):
			r.queue_free()


func _on_ship_state_updated(
	sid: int,
	world_pos: Vector2,
	heading: float,
	speed: float,
	sail_state: int,
	hp: float,
	max_hp: float
) -> void:
	var r: Node2D = ship_renderers.get(sid, null)
	if r != null and is_instance_valid(r):
		r.call("update_transform_state", world_pos, heading, speed, sail_state, hp, max_hp)


func _on_ship_stats_compiled(sid: int, stats: Contracts.ShipStats) -> void:
	if sid == player_ship_id and player_ship != null:
		player_ship.call("apply_stats", stats)
		if network_manager != null and network_manager.current_mode == NetworkManager.Mode.CLIENT:
			network_manager.send_player_stats(stats)


func _on_ship_grid_updated(sid: int, equipped_items: Array) -> void:
	var r: Node2D = ship_renderers.get(sid, null)
	if r != null and is_instance_valid(r):
		r.call("update_equipped_modules", equipped_items)


func _on_ship_class_upgraded(sid: int, new_hull_tier: int, _class_title: String) -> void:
	var r: Node2D = ship_renderers.get(sid, null)
	if r != null and is_instance_valid(r) and r.has_method("set_hull_tier"):
		r.call("set_hull_tier", new_hull_tier)
	if sid == player_ship_id and network_manager != null and network_manager.current_mode == NetworkManager.Mode.CLIENT:
		network_manager.send_ship_class_upgrade(new_hull_tier)


func _on_ship_repaired(sid: int, new_hp: float, _max_hp: float, _cost: int) -> void:
	if sid == player_ship_id and network_manager != null and network_manager.current_mode == NetworkManager.Mode.CLIENT:
		network_manager.send_ship_repair(new_hp)


func _on_broadside_fired(
	sid: int,
	is_starboard: bool,
	_origin: Vector2,
	_dir: Vector2,
	_cannons: Array
) -> void:
	var r: Node2D = ship_renderers.get(sid, null)
	if r != null and is_instance_valid(r):
		r.call("trigger_muzzle_flash", is_starboard)
	if sid == player_ship_id and pixel_camera != null:
		pixel_camera.call("add_trauma", 0.25)
	if sid == player_ship_id and network_manager != null and network_manager.current_mode == NetworkManager.Mode.CLIENT and combat_system != null:
		combat_system.trigger_client_reload_visual(sid, is_starboard)


func _on_ship_damaged(
	sid: int,
	_damage: float,
	_new_hp: float,
	_max_hp: float,
	_world_pos: Vector2
) -> void:
	var r: Node2D = ship_renderers.get(sid, null)
	if r != null and is_instance_valid(r):
		r.call("trigger_hit_flash")
	if sid == player_ship_id and pixel_camera != null:
		pixel_camera.call("add_trauma", 0.34)


func _on_ship_sunk(sid: int, _world_pos: Vector2, _faction: int, _killer_ship_id: int) -> void:
	if sid == player_ship_id:
		var bus := _bus()
		if bus != null:
			bus.notification_posted.emit("Dein Schiff ist gesunken! Rückkehr nach Port Tortuga...", "combat")


# ==============================================================================
# HELPERS
# ==============================================================================

func _create_ship_node(
	sid: int,
	pos: Vector2,
	heading: float,
	faction: int,
	ship_name: String
) -> Node:
	var ship: Node = _ship_physics_script.new()
	ship.name = "Ship_%d" % sid
	ship.call("setup", sid, pos, heading, faction, ship_name)
	add_child(ship)
	return ship


func _ensure_ship_renderer(
	sid: int,
	faction: int,
	ship_name: String,
	pos: Vector2,
	heading: float
) -> void:
	if is_headless_server or world_root == null or _ship_renderer_script == null:
		return
	if ship_renderers.has(sid) and is_instance_valid(ship_renderers[sid]):
		return
	var r: Node2D = _ship_renderer_script.new()
	r.name = "ShipRenderer_%d" % sid
	r.z_index = 5
	world_root.add_child(r)
	r.call("setup_ship", sid, faction, ship_name)
	r.call("update_transform_state", pos, heading, 0.0, Contracts.SailState.ANCHORED, 120.0, 120.0)
	ship_renderers[sid] = r


func _combined_ships_dict() -> Dictionary:
	var merged: Dictionary = all_ships.duplicate()
	if ai_director != null:
		for k in ai_director.ai_ships.keys():
			merged[k] = ai_director.ai_ships[k]
	return merged


func _is_ui_open() -> bool:
	var grid_open: bool = cargo_grid_ui != null and cargo_grid_ui.visible
	var harbor_open: bool = harbor_ui != null and harbor_ui.visible
	return grid_open or harbor_open


func _clear_game_world() -> void:
	if ai_director != null:
		ai_director.clear_all()
		ai_director.queue_free()
		ai_director = null
	if loot_system != null:
		loot_system.clear_all()
		loot_system.queue_free()
		loot_system = null
	if combat_system != null:
		combat_system.clear_all()
		combat_system.queue_free()
		combat_system = null
	if world_map != null:
		world_map.queue_free()
		world_map = null
	if player_grid != null:
		player_grid.queue_free()
		player_grid = null
	for sid_var in all_ships.keys():
		var s: Node = all_ships[sid_var]
		if is_instance_valid(s):
			s.queue_free()
	all_ships.clear()
	player_ship = null
	for sid_var in ship_renderers.keys():
		var r: Node2D = ship_renderers[sid_var]
		if is_instance_valid(r):
			r.queue_free()
	ship_renderers.clear()


func _apply_clean_label_font_shadow(lbl: Label) -> void:
	lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.07, 0.88))
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)


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

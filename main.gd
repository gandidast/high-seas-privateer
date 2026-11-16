class_name Main
extends Node
## Main game orchestrator for High Seas Pixel Privateer.
## Handles Headless Dedicated Server (--server) without loading visual/UI scripts,
## as well as Solo and WebSocket Client ("One-World") modes with 2D pixel visuals and UI.

const WORLD_MAP_PATH: String = "res://sim/world_map.gd"
const SHIP_PHYSICS_PATH: String = "res://sim/ship_physics.gd"
const DREDGE_GRID_PATH: String = "res://sim/dredge_grid.gd"
const OCEAN_RENDERER_PATH: String = "res://visual/ocean_renderer.gd"
const PIXEL_CAMERA_PATH: String = "res://visual/pixel_camera.gd"
const FX_MANAGER_PATH: String = "res://visual/fx_manager.gd"
const CARGO_GRID_UI_PATH: String = "res://ui/cargo_grid_ui.gd"
const ServerConfigScript := preload("res://net/server_config.gd")
const SaveStoreScript := preload("res://sim/save_store.gd")

var is_headless_server: bool = false
var game_started: bool = false
var world_seed: int = Contracts.DEFAULT_WORLD_SEED

var world_map: Node = null
var combat_system: CombatSystem = null
var loot_system: LootSystem = null
var ai_director: AIDirector = null
var network_manager: NetworkManager = null

var all_ships: Dictionary = {}       # ship_id (int) -> ShipPhysics Node
var ship_renderers: Dictionary = {}  # ship_id (int) -> ShipStackRenderer Node2D
var player_ship: Node = null
var player_grid: Node = null
var player_ship_id: int = 1
var _respawn_timer: float = -1.0
var _server_respawn_timers: Dictionary = {}

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

var _start_screen: StartMenuUI = null
var _client_sync: ClientSyncController = ClientSyncController.new()
var _ship_physics_script: Script = null
var _save_store: SaveStoreScript = SaveStoreScript.new()
var _local_account_store: SaveStoreScript = SaveStoreScript.new(SaveStoreScript.DEFAULT_LOCAL_ACCOUNTS_DIR)
var _active_local_account_key: String = ""
var _save_dirty: bool = false
var _save_debounce_timer: float = -1.0
var _solo_autosave_accum: float = 0.0
var _save_signals_bound: bool = false
var _client_welcome_handled: bool = false


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

	_client_sync.bind_callbacks(Callable(self, "_create_ship_node"), Callable(self, "_set_player_ship_ref"))

	if NetworkManager.is_server_mode_requested():
		is_headless_server = true
		_boot_headless_server()
	else:
		is_headless_server = false
		_boot_client_or_solo_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if is_headless_server and network_manager != null:
			network_manager.save_all_connected_accounts()
		elif game_started and not is_headless_server:
			_flush_local_save(true)


func _boot_headless_server() -> void:
	var port: int = NetworkManager.get_cli_port(Contracts.SERVER_DEFAULT_PORT)
	world_seed = NetworkManager.get_cli_seed(Contracts.DEFAULT_WORLD_SEED)
	_init_simulation(world_seed, true)
	ai_director.populate_initial_fleet(3, 3)
	loot_system.spawn_initial_flotsam(world_map, 3)

	network_manager.bind_simulation(world_map, combat_system, loot_system, ai_director, all_ships)
	network_manager.peer_ship_joined.connect(_on_server_peer_joined)
	network_manager.peer_ship_joined_with_save.connect(_on_server_peer_joined_with_save)
	network_manager.peer_ship_left.connect(_on_server_peer_left)

	if network_manager.start_server(port, world_seed) != OK:
		push_error("[Main] Dedicated server failed to bind port %d." % port)
		return
	game_started = true
	print("[Main] Dedicated server running (Port %d, Seed %d)." % [port, world_seed])


func _on_server_peer_joined(peer_id: int, captain_name: String) -> void:
	_on_server_peer_joined_with_save(peer_id, captain_name, {})


func _on_server_peer_joined_with_save(peer_id: int, captain_name: String, save_data: Dictionary) -> void:
	var has_saved_pos: bool = bool(save_data.get("has_saved_pos", false))
	var spawn_pos: Vector2
	var spawn_heading: float = 0.0
	if has_saved_pos:
		spawn_pos = Vector2(float(save_data.get("world_x", 0.0)), float(save_data.get("world_y", 0.0)))
		if world_map != null and world_map.has_method("is_land") and bool(world_map.call("is_land", spawn_pos)):
			spawn_pos = world_map.call("find_open_water_near", spawn_pos, 0.22)
		spawn_heading = float(save_data.get("heading", -0.35))
	else:
		var angle: float = float(peer_id % 12) * (TAU / 12.0)
		spawn_pos = Vector2(cos(angle), sin(angle)) * 90.0
		if world_map != null and world_map.has_method("find_open_water_near"):
			spawn_pos = world_map.call("find_open_water_near", spawn_pos, 0.22)

	var ship: Node = _create_ship_node(peer_id, spawn_pos, spawn_heading, Contracts.ShipFaction.PLAYER, captain_name)
	var applied_stats: Contracts.ShipStats = null
	var saved_grid: Variant = save_data.get("grid", {})
	if saved_grid is Dictionary and not (saved_grid as Dictionary).is_empty():
		var grid_script: Script = load(DREDGE_GRID_PATH) as Script
		if grid_script != null:
			var temp_grid: Node = grid_script.new()
			temp_grid.set("ship_id", peer_id)
			temp_grid.call("from_dict", saved_grid)
			var compiled: Variant = temp_grid.get("current_stats")
			if compiled is Contracts.ShipStats:
				applied_stats = compiled
			temp_grid.free()

	if applied_stats == null:
		applied_stats = Contracts.ShipStats.new()
		applied_stats.port_cannons = [
			{ "damage": 14.0, "reload_time": 2.4, "range": 260.0, "projectile_speed": 220.0, "spread_angle_deg": 6.0, "deck_offset_x": -6.0 },
			{ "damage": 14.0, "reload_time": 2.4, "range": 260.0, "projectile_speed": 220.0, "spread_angle_deg": 6.0, "deck_offset_x": 6.0 }
		]
		applied_stats.starboard_cannons = [
			{ "damage": 14.0, "reload_time": 2.4, "range": 260.0, "projectile_speed": 220.0, "spread_angle_deg": 6.0, "deck_offset_x": -6.0 },
			{ "damage": 14.0, "reload_time": 2.4, "range": 260.0, "projectile_speed": 220.0, "spread_angle_deg": 6.0, "deck_offset_x": 6.0 }
		]
	ship.call("apply_stats", applied_stats)
	if save_data.has("hull_tier") and int(ship.get("hull_tier")) != int(save_data["hull_tier"]):
		ship.call("upgrade_ship_class", clampi(int(save_data["hull_tier"]), Contracts.ShipClass.SLOOP, Contracts.ShipClass.WAR_GALLEON))
	if has_saved_pos and float(save_data.get("hp", -1.0)) > 0.0:
		ship.set("hp", clampf(float(save_data["hp"]), 1.0, float(ship.get("max_hp"))))

	all_ships[peer_id] = ship
	combat_system.register_ship(ship)
	if _bus() != null:
		_bus().ship_spawned.emit(peer_id, {
			"ship_id": peer_id, "faction": Contracts.ShipFaction.PLAYER,
			"name": captain_name, "world_pos": spawn_pos, "heading": spawn_heading,
			"hull_tier": int(ship.get("hull_tier"))
		})


func _on_server_peer_left(peer_id: int) -> void:
	_server_respawn_timers.erase(peer_id)
	combat_system.unregister_ship(peer_id)
	var ship: Node = all_ships.get(peer_id, null)
	all_ships.erase(peer_id)
	if is_instance_valid(ship):
		ship.queue_free()
	if _bus() != null:
		_bus().ship_despawned.emit(peer_id)


func _boot_client_or_solo_menu() -> void:
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
	world_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world_subviewport.add_child(world_root)

	ocean_renderer = _spawn_world_node(OCEAN_RENDERER_PATH, "OceanRenderer")
	if ocean_renderer != null:
		ocean_renderer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ocean_renderer.call("setup", world_seed)

	fx_manager = _spawn_world_node(FX_MANAGER_PATH, "FxManager")
	if fx_manager != null:
		fx_manager.z_index = 20
		fx_manager.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	pixel_camera = _spawn_world_node(PIXEL_CAMERA_PATH, "PixelCamera") as Camera2D
	if pixel_camera != null:
		pixel_camera.call("snap_to_pos", Vector2.ZERO)

	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	ui_layer.layer = 10
	add_child(ui_layer)

	_start_screen = StartMenuUI.new()
	_start_screen.solo_requested.connect(func(_cap: String, _url: String): _on_solo_pressed(true))
	_start_screen.solo_new_requested.connect(func(_cap: String, _url: String): _on_solo_pressed(false))
	_start_screen.join_multiplayer_requested.connect(func(url: String, cap_name: String):
		_client_welcome_handled = false
		network_manager.connect_or_autostart(url, cap_name))
	_start_screen.join_multiplayer_auth_requested.connect(func(url: String, username: String, secret: String, auth_mode: String):
		_client_welcome_handled = false
		network_manager.connect_with_auth(url, username, secret, auth_mode))
	_start_screen.reconnect_requested.connect(_on_reconnect_pressed)
	ui_layer.add_child(_start_screen)

	network_manager.client_joined_with_save.connect(_on_network_client_joined_with_save)
	network_manager.client_joined.connect(_on_network_client_joined)
	network_manager.auth_failed.connect(_on_network_auth_failed)
	network_manager.client_disconnected_from_server.connect(_on_network_client_disconnected)
	network_manager.snapshot_received.connect(_on_network_snapshot_received)
	network_manager.connection_status_changed.connect(func(txt: String): if _start_screen != null: _start_screen.set_status(txt))
	_client_sync.connect_visual_signals()
	_sync_client_controller_refs()
	_bind_save_dirty_signals()


func _spawn_world_node(script_path: String, node_name: String) -> Node2D:
	var s: Script = load(script_path) as Script
	if s == null:
		return null
	var n: Node2D = s.new()
	n.name = node_name
	world_root.add_child(n)
	return n


func _on_solo_pressed(continue_save: bool = true) -> void:
	if _start_screen != null:
		_start_screen.hide_menu()
	if network_manager == null:
		network_manager = NetworkManager.new()
		network_manager.name = "NetworkManager"
		add_child(network_manager)
	if _ship_physics_script == null:
		_ship_physics_script = load(SHIP_PHYSICS_PATH) as Script
	network_manager.start_solo()

	var loaded_save: Dictionary = {}
	_active_local_account_key = ""
	var cap_title: String = ServerConfigScript.load_captain_name("Schaluppe Morgenstern")
	if ServerConfigScript.has_local_auth():
		var local_res: Dictionary = _local_account_store.login_with_token(ServerConfigScript.load_local_username(), ServerConfigScript.load_local_session_token())
		if bool(local_res.get("ok", false)):
			_active_local_account_key = str(local_res["username_key"])
			cap_title = str(local_res["username"])
			if continue_save:
				loaded_save = SaveStoreScript.sanitize_save_data(local_res.get("save_data", {}))
			else:
				_local_account_store.clear_account_save(_active_local_account_key)
		else:
			ServerConfigScript.clear_local_auth(true)

	if _active_local_account_key.is_empty():
		if continue_save and _save_store.has_solo_save():
			loaded_save = _save_store.load_solo()
		elif not continue_save:
			_save_store.clear_solo_save()

	_clear_game_world()
	world_seed = Contracts.DEFAULT_WORLD_SEED
	_init_simulation(world_seed, true)
	if ocean_renderer != null:
		ocean_renderer.call("setup", world_seed)

	player_ship_id = 1
	_spawn_local_player(player_ship_id, cap_title, true, loaded_save)
	ai_director.populate_initial_fleet(3, 3)
	loot_system.spawn_initial_flotsam(world_map, 3)
	_init_ui_layers(loaded_save)
	_bind_save_dirty_signals()
	_solo_autosave_accum = 0.0
	_save_dirty = false
	game_started = true
	if _bus() != null:
		if loaded_save.is_empty():
			_bus().notification_posted.emit("Leinen los! W/S Segel, A/D Ruder, Q/E Breitseite, Space Bug.", "system")
		else:
			_bus().notification_posted.emit("Solo-Spielstand geladen (%d Gold)!" % int(loaded_save.get("gold", 120)), "system")


func _on_reconnect_pressed() -> void:
	_client_welcome_handled = false
	if _start_screen != null:
		_start_screen.set_reconnect_visible(false)
		_start_screen.set_status("Verbinde erneut mit One-World...")
	if network_manager != null and network_manager.reconnect_last():
		return
	if _start_screen != null:
		var url: String = _start_screen.get_url_text()
		if ServerConfigScript.has_mp_auth_for_url(url):
			network_manager.connect_with_auth(url, ServerConfigScript.load_mp_username(), ServerConfigScript.load_mp_session_token(), "token")
		else:
			_start_screen.show_auth_error("Bitte zuerst anmelden oder registrieren.", false)


func _on_network_auth_failed(reason: String, clear_saved_auth: bool) -> void:
	game_started = false
	_client_welcome_handled = false
	_clear_game_world()
	if _start_screen != null:
		_start_screen.show_auth_error(reason, clear_saved_auth)


func _on_network_client_joined_with_save(assigned_ship_id: int, server_seed: int, display_name: String, session_token: String, save_data: Dictionary) -> void:
	_client_welcome_handled = true
	ServerConfigScript.save_mp_auth(display_name, session_token, network_manager.get_last_target_url())
	if _start_screen != null:
		_start_screen.refresh_menu_state()
	_finish_client_join(assigned_ship_id, server_seed, save_data)


func _on_network_client_joined(assigned_ship_id: int, server_seed: int) -> void:
	if _client_welcome_handled:
		return
	_finish_client_join(assigned_ship_id, server_seed, {})


func _finish_client_join(assigned_ship_id: int, server_seed: int, save_data: Dictionary) -> void:
	_clear_game_world()
	_client_sync.reset()
	if _start_screen != null:
		_start_screen.hide_menu()

	world_seed = server_seed
	player_ship_id = assigned_ship_id
	_init_simulation(world_seed, false)
	if ocean_renderer != null:
		ocean_renderer.call("setup", world_seed)

	_spawn_local_player(player_ship_id, network_manager.local_captain_name, true, save_data)
	_init_ui_layers(save_data)
	_sync_client_controller_refs()
	_bind_save_dirty_signals()
	if player_grid != null and player_grid.has_method("compile_stats"):
		network_manager.send_player_stats(player_grid.call("compile_stats"))
	network_manager.send_player_save_state(_build_local_save_data())
	_save_dirty = false

	game_started = true
	if _bus() != null:
		var msg: String = "Willkommen zurück, %s (%d Gold)!" % [network_manager.local_captain_name, int(save_data.get("gold", 120))] if not save_data.is_empty() else "Mit One-World verbunden (Schiff #%d)!" % player_ship_id
		_bus().notification_posted.emit(msg, "net")


func _on_network_client_disconnected(reason: String) -> void:
	game_started = false
	_client_welcome_handled = false
	_clear_game_world()
	if _start_screen != null:
		_start_screen.show_disconnected(reason)


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
	_sync_client_controller_refs()


func _spawn_local_player(p_ship_id: int, p_name: String, register_combat: bool, save_data: Dictionary = {}) -> void:
	var has_saved_pos: bool = bool(save_data.get("has_saved_pos", false))
	var start_pos: Vector2
	var start_heading: float = -0.35
	if has_saved_pos:
		start_pos = Vector2(float(save_data.get("world_x", 0.0)), float(save_data.get("world_y", 0.0)))
		if world_map != null and world_map.has_method("is_land") and bool(world_map.call("is_land", start_pos)):
			start_pos = world_map.call("find_open_water_near", start_pos, 0.22)
		start_heading = float(save_data.get("heading", -0.35))
	else:
		start_pos = world_map.call("find_open_water_near", Vector2.ZERO, 0.22) if (world_map != null and world_map.has_method("find_open_water_near")) else Vector2.ZERO

	player_ship = _create_ship_node(p_ship_id, start_pos, start_heading, Contracts.ShipFaction.PLAYER, p_name)
	all_ships[p_ship_id] = player_ship

	var grid_script: Script = load(DREDGE_GRID_PATH) as Script
	if grid_script != null:
		player_grid = grid_script.new()
		player_grid.name = "PlayerDredgeGrid"
		player_grid.set("ship_id", p_ship_id)
		add_child(player_grid)
		var saved_grid: Variant = save_data.get("grid", {})
		if saved_grid is Dictionary and not (saved_grid as Dictionary).is_empty():
			player_grid.call("from_dict", saved_grid)
		else:
			if save_data.has("hull_tier"):
				player_grid.call("set_hull_tier", clampi(int(save_data["hull_tier"]), Contracts.ShipClass.SLOOP, Contracts.ShipClass.WAR_GALLEON))
			player_grid.call("populate_starter_loadout")
		var stats: Contracts.ShipStats = player_grid.call("compile_stats")
		player_ship.call("apply_stats", stats)
		if has_saved_pos and float(save_data.get("hp", -1.0)) > 0.0:
			player_ship.set("hp", clampf(float(save_data["hp"]), 1.0, stats.max_hp))
		else:
			player_ship.set("hp", stats.max_hp)

	if register_combat and combat_system != null:
		combat_system.register_ship(player_ship)

	_sync_client_controller_refs()
	_client_sync.ensure_ship_renderer(p_ship_id, Contracts.ShipFaction.PLAYER, p_name, start_pos, start_heading)
	if ship_renderers.has(p_ship_id) and is_instance_valid(ship_renderers[p_ship_id]):
		var rend: Node2D = ship_renderers[p_ship_id]
		if rend.has_method("set_hull_tier"):
			rend.call("set_hull_tier", int(player_ship.get("hull_tier")))
	if player_grid != null:
		var compiled: Variant = player_grid.get("current_stats")
		if compiled is Contracts.ShipStats and ship_renderers.has(p_ship_id):
			ship_renderers[p_ship_id].call("update_equipped_modules", compiled.visual_equipped_items)

	if pixel_camera != null and ship_renderers.has(p_ship_id):
		pixel_camera.call("set_follow_target", ship_renderers[p_ship_id])
		pixel_camera.call("snap_to_pos", start_pos)


func _init_ui_layers(save_data: Dictionary = {}) -> void:
	var starting_gold: int = maxi(0, int(save_data.get("gold", SaveStoreScript.DEFAULT_GOLD)))
	if hud_overlay == null:
		hud_overlay = HudOverlay.new()
		hud_overlay.name = "HudOverlay"
		ui_layer.add_child(hud_overlay)
	hud_overlay.setup(player_ship, world_map, combat_system, loot_system, _combined_ships_dict(), starting_gold)

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
	harbor_ui.setup(player_ship, player_grid, world_map, ai_director, loot_system, starting_gold)
	var saved_tiers: Variant = save_data.get("owned_ship_tiers", [])
	if saved_tiers is Array and not (saved_tiers as Array).is_empty():
		harbor_ui.set_owned_ship_tiers(saved_tiers)
	var saved_quests: Variant = save_data.get("active_quests", [])
	if saved_quests is Array and not (saved_quests as Array).is_empty():
		harbor_ui.restore_active_quests(saved_quests, true)


func _physics_process(delta: float) -> void:
	if not game_started:
		return
	if is_headless_server:
		_step_headless_server(delta)
		return

	var ui_blocking: bool = _is_ui_open()
	var steer_input: float = _get_current_steer_input()

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
			loot_system.step_loot(delta, merged_ships, player_grid, not ui_blocking and Input.is_action_just_pressed("interact"))
		if hud_overlay != null:
			hud_overlay.set_ships_dict(merged_ships)
	else:
		_client_sync.flush_pending_snapshot()
		var seq: int = _client_sync.next_input_seq()
		if player_ship != null and not bool(player_ship.get("is_sunk")):
			if int(player_ship.get("sail_state")) != _client_sync.client_desired_sail_state:
				player_ship.call("set_sail_state", _client_sync.client_desired_sail_state)
			player_ship.call("step_physics", delta, steer_input, world_map)
			_client_sync.record_prediction(seq, player_ship.get("world_pos"), float(player_ship.get("heading")))
		network_manager.step_network(delta, steer_input, _client_sync.client_desired_sail_state, seq)
		_client_sync.step_remote_extrapolation(delta)
		if combat_system != null:
			combat_system.step_reloads(delta)
		if hud_overlay != null:
			hud_overlay.set_ships_dict(all_ships)

	_update_ocean_and_aim_cone()
	_step_local_save_sync(delta)


func _bind_save_dirty_signals() -> void:
	if _save_signals_bound:
		return
	var bus := _bus()
	if bus == null:
		return
	_save_signals_bound = true
	bus.gold_changed.connect(func(_ng: int, _d: int): _mark_save_dirty())
	bus.ship_grid_updated.connect(func(sid: int, _eq: Array):
		if sid == player_ship_id:
			_mark_save_dirty())
	bus.ship_class_upgraded.connect(func(sid: int, _t: int, _ct: String):
		if sid == player_ship_id:
			_mark_save_dirty())
	bus.ship_repaired.connect(func(sid: int, _hp: float, _mhp: float, _c: int):
		if sid == player_ship_id:
			_mark_save_dirty())
	bus.quest_list_updated.connect(func(_qs: Array): _mark_save_dirty())


func _mark_save_dirty() -> void:
	if is_headless_server or not game_started:
		return
	_save_dirty = true
	if _save_debounce_timer < 0.0:
		_save_debounce_timer = 0.25


func _step_local_save_sync(delta: float) -> void:
	if _save_dirty and _save_debounce_timer >= 0.0:
		_save_debounce_timer -= delta
		if _save_debounce_timer <= 0.0:
			_save_debounce_timer = -1.0
			_flush_local_save(false)
	if network_manager != null and network_manager.current_mode == NetworkManager.Mode.SOLO:
		_solo_autosave_accum += delta
		if _solo_autosave_accum >= 10.0:
			_solo_autosave_accum = 0.0
			_flush_local_save(true)


func _flush_local_save(force: bool) -> void:
	if is_headless_server or not game_started or player_ship == null or network_manager == null:
		return
	if not force and not _save_dirty:
		return
	_save_dirty = false
	var payload: Dictionary = _build_local_save_data()
	if network_manager.current_mode == NetworkManager.Mode.CLIENT:
		network_manager.send_player_save_state(payload)
	elif network_manager.current_mode == NetworkManager.Mode.SOLO:
		if not _active_local_account_key.is_empty():
			_local_account_store.update_account_save(_active_local_account_key, payload)
		else:
			_save_store.save_solo(payload)


func _build_local_save_data() -> Dictionary:
	var data: Dictionary = SaveStoreScript.create_default_save_data()
	if harbor_ui != null:
		data["gold"] = harbor_ui.current_gold
		data["owned_ship_tiers"] = harbor_ui.get_owned_ship_tiers_array()
		data["active_quests"] = harbor_ui.get_active_quests_dicts()
	if player_grid != null and player_grid.has_method("to_dict"):
		data["grid"] = player_grid.call("to_dict")
		data["hull_tier"] = int(player_grid.get("hull_tier"))
	if player_ship != null and is_instance_valid(player_ship):
		var wp: Variant = player_ship.get("world_pos")
		if wp is Vector2:
			data["world_x"] = snappedf((wp as Vector2).x, 0.1)
			data["world_y"] = snappedf((wp as Vector2).y, 0.1)
			data["has_saved_pos"] = true
		data["heading"] = snappedf(float(player_ship.get("heading")), 0.001)
		data["hull_tier"] = int(player_ship.get("hull_tier"))
		var max_hp: float = maxf(10.0, float(player_ship.get("max_hp")))
		if bool(player_ship.get("is_sunk")) or float(player_ship.get("hp")) <= 0.0:
			data["hp"] = max_hp
			data["has_saved_pos"] = false
		else:
			data["hp"] = clampf(snappedf(float(player_ship.get("hp")), 0.1), 1.0, max_hp)
	return SaveStoreScript.sanitize_save_data(data)


func _step_headless_server(delta: float) -> void:
	world_map.call("step_wind", delta)
	if world_map.has_method("step_weather"):
		world_map.call("step_weather", delta)
	for sid_var in all_ships.keys():
		var ship: Node = all_ships[sid_var]
		if ship == null:
			continue
		if bool(ship.get("is_sunk")):
			var pid: int = int(sid_var)
			if not _server_respawn_timers.has(pid):
				_server_respawn_timers[pid] = 10.0
				if _bus() != null:
					_bus().player_death_penalty.emit(pid, 20, 10.0)
			else:
				var r_timer: float = float(_server_respawn_timers[pid]) - delta
				if r_timer <= 0.0:
					_server_respawn_timers.erase(pid)
					var harbor_info: Dictionary = _get_safe_respawn_harbor(ship.get("world_pos"))
					var respawn_pos: Vector2 = harbor_info["pos"]
					ship.set("world_pos", respawn_pos)
					ship.set("velocity", Vector2.ZERO)
					ship.set("speed", 0.0)
					ship.set("sail_state", Contracts.SailState.ANCHORED)
					ship.set("is_sunk", false)
					ship.set("burn_timer", 0.0)
					ship.set("burn_dps", 0.0)
					ship.set("chain_slow_timer", 0.0)
					ship.set("chain_slow_strength", 0.0)
					ship.set("current_harbor_index", int(harbor_info["index"]))
					ship.set("hp", float(ship.get("max_hp")))
				else:
					_server_respawn_timers[pid] = r_timer
			continue
		ship.call("step_physics", delta, float(ship.get_meta("net_steer", 0.0)), world_map)

	var merged_srv: Dictionary = _combined_ships_dict()
	ai_director.step_ai(delta, merged_srv)
	ai_director.step_sea_monster(delta, merged_srv)
	combat_system.step_ship_collisions(delta, merged_srv)
	combat_system.step_forts(delta, merged_srv)
	combat_system.step_projectiles(delta, world_map)
	loot_system.step_loot(delta, merged_srv, null)
	network_manager.step_network(delta)


func _unhandled_input(event: InputEvent) -> void:
	if is_headless_server or not game_started or _is_ui_open():
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and get_viewport() != null:
		get_viewport().gui_release_focus()
	if player_ship == null or bool(player_ship.get("is_sunk")):
		return

	if event.is_action_pressed("sail_up") or event.is_action_pressed("sail_down"):
		var delta_sail: int = 1 if event.is_action_pressed("sail_up") else -1
		if network_manager.current_mode == NetworkManager.Mode.CLIENT:
			var next_sail: int = clampi(_client_sync.client_desired_sail_state + delta_sail, Contracts.SailState.ANCHORED, Contracts.SailState.FULL_SAIL)
			_client_sync.client_desired_sail_state = next_sail
			player_ship.call("set_sail_state", next_sail)
			var seq: int = _client_sync.next_input_seq()
			_client_sync.record_prediction(seq, player_ship.get("world_pos"), float(player_ship.get("heading")))
			network_manager.send_input_immediately(_get_current_steer_input(), next_sail, seq)
		else:
			player_ship.call("change_sail_state", delta_sail)
	elif event.is_action_pressed("fire_port"):
		_trigger_player_broadside(false)
	elif event.is_action_pressed("fire_starboard"):
		_trigger_player_broadside(true)
	elif event.is_action_pressed("fire_bow"):
		_trigger_player_bow()
	elif event.is_action_pressed("interact"):
		var h_idx: int = int(player_ship.get("current_harbor_index"))
		if h_idx >= 0 and _bus() != null:
			_bus().harbor_ui_requested.emit(harbor_ui == null or not harbor_ui.visible, h_idx)


func _get_current_steer_input() -> float:
	if _is_ui_open():
		return 0.0
	var s: float = 0.0
	if Input.is_action_pressed("steer_left") or Input.is_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		s -= 1.0
	if Input.is_action_pressed("steer_right") or Input.is_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		s += 1.0
	return s


func _trigger_player_broadside(is_starboard: bool) -> void:
	if network_manager.current_mode == NetworkManager.Mode.CLIENT:
		if combat_system != null and float(combat_system.get_broadside_cone(player_ship_id, is_starboard).get("ready_ratio", 0.0)) >= 0.99:
			_client_sync.trigger_local_fire_anticipation(player_ship_id, is_starboard)
		network_manager.send_fire_request(is_starboard)
	elif combat_system != null:
		combat_system.fire_broadside(player_ship_id, is_starboard)


func _trigger_player_bow() -> void:
	if network_manager.current_mode == NetworkManager.Mode.CLIENT:
		if combat_system != null and combat_system.has_method("get_bow_cone"):
			var bow_cone: Dictionary = combat_system.call("get_bow_cone", player_ship_id)
			if int(bow_cone.get("total_count", 0)) > 0 and float(bow_cone.get("ready_ratio", 0.0)) >= 0.99:
				_client_sync.trigger_local_bow_fire_anticipation(player_ship_id)
		network_manager.send_fire_bow_request()
	elif combat_system != null and combat_system.has_method("fire_bow"):
		combat_system.call("fire_bow", player_ship_id)


func _update_ocean_and_aim_cone() -> void:
	if ocean_renderer != null and pixel_camera != null:
		ocean_renderer.call("set_camera_center", pixel_camera.global_position)
	if fx_manager == null or player_ship == null or combat_system == null or _is_ui_open():
		if fx_manager != null:
			fx_manager.call("set_broadside_aim_cone", Vector2.ZERO, Vector2.RIGHT, 0.0, 0.0, false)
		return
	var mouse_world: Vector2 = _get_world_mouse_position()
	var local_mouse: Vector2 = (mouse_world - (player_ship.get("world_pos") as Vector2)).rotated(-float(player_ship.get("heading")))
	if local_mouse.length() > 14.0 and local_mouse.length() < 340.0:
		if local_mouse.x > 12.0 and absf(local_mouse.y) <= local_mouse.x * 0.55 and combat_system.has_method("get_bow_cone"):
			var bow_cone: Dictionary = combat_system.call("get_bow_cone", player_ship_id)
			if int(bow_cone.get("total_count", 0)) > 0:
				fx_manager.call("set_broadside_aim_cone", bow_cone["origin"], bow_cone["dir"], float(bow_cone["range"]), float(bow_cone["half_angle_rad"]), true)
				return
		if absf(local_mouse.y) > 8.0 and local_mouse.length() < 320.0:
			var cone: Dictionary = combat_system.get_broadside_cone(player_ship_id, local_mouse.y > 0.0)
			if int(cone.get("total_count", 0)) > 0:
				fx_manager.call("set_broadside_aim_cone", cone["origin"], cone["dir"], float(cone["range"]), float(cone["half_angle_rad"]), true)
				return
	fx_manager.call("set_broadside_aim_cone", Vector2.ZERO, Vector2.RIGHT, 0.0, 0.0, false)


func _get_world_mouse_position() -> Vector2:
	if pixel_camera == null:
		return Vector2.ZERO
	if pixel_camera.has_method("get_world_mouse_pos"):
		return pixel_camera.call("get_world_mouse_pos")
	if world_subviewport != null and world_viewport_container != null and world_viewport_container.is_inside_tree():
		var sv_mouse: Vector2 = world_viewport_container.get_local_mouse_position() / float(maxi(1, world_viewport_container.stretch_shrink))
		return world_subviewport.get_canvas_transform().affine_inverse() * sv_mouse
	return pixel_camera.get_global_mouse_position()


func _step_player_respawn(delta: float) -> void:
	if _respawn_timer < 0.0:
		_respawn_timer = 10.0
		if _bus() != null:
			_bus().player_death_penalty.emit(player_ship_id, 20, 10.0)
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = -1.0
		var harbor_info: Dictionary = _get_safe_respawn_harbor(player_ship.get("world_pos"))
		var respawn_pos: Vector2 = harbor_info["pos"]
		player_ship.set("world_pos", respawn_pos)
		player_ship.set("velocity", Vector2.ZERO)
		player_ship.set("speed", 0.0)
		player_ship.set("sail_state", Contracts.SailState.ANCHORED)
		player_ship.set("is_sunk", false)
		player_ship.set("burn_timer", 0.0)
		player_ship.set("burn_dps", 0.0)
		player_ship.set("chain_slow_timer", 0.0)
		player_ship.set("chain_slow_strength", 0.0)
		player_ship.set("current_harbor_index", int(harbor_info["index"]))
		var mhp: float = float(player_ship.get("max_hp"))
		player_ship.set("hp", mhp)
		if ship_renderers.has(player_ship_id) and is_instance_valid(ship_renderers[player_ship_id]):
			var r: Node2D = ship_renderers[player_ship_id]
			if r.has_method("set_sunk"):
				r.call("set_sunk", false)
		if _bus() != null:
			_bus().ship_state_updated.emit(player_ship_id, respawn_pos, float(player_ship.get("heading")), 0.0, Contracts.SailState.ANCHORED, mhp, mhp)
			_bus().notification_posted.emit("In %s wieder flottgemacht!" % str(harbor_info["name"]), "system")


func _get_safe_respawn_harbor(from_pos: Vector2) -> Dictionary:
	if world_map != null and world_map.has_method("get_nearest_safe_harbor"):
		var safe_isl: Variant = world_map.call("get_nearest_safe_harbor", from_pos)
		if safe_isl is Contracts.IslandData:
			var isl := safe_isl as Contracts.IslandData
			return { "index": isl.index, "name": isl.name, "pos": isl.harbor_pos }
	var islands: Array = Contracts.get_islands(world_seed)
	if not islands.is_empty():
		var isl0: Contracts.IslandData = islands[0]
		return { "index": isl0.index, "name": isl0.name, "pos": isl0.harbor_pos }
	return { "index": 0, "name": "Port Tortuga", "pos": Vector2.ZERO }


func _on_network_snapshot_received(snapshot: Dictionary) -> void:
	_sync_client_controller_refs()
	_client_sync.queue_snapshot(snapshot)


func _on_snapshot_received(snapshot: Dictionary) -> void:
	_sync_client_controller_refs()
	_client_sync.apply_snapshot(snapshot)


func _sync_client_controller_refs() -> void:
	_client_sync.player_ship_id = player_ship_id
	_client_sync.bind_world_refs(all_ships, ship_renderers, world_map, combat_system, loot_system, network_manager, world_root, pixel_camera, harbor_ui, hud_overlay, is_headless_server)


func _set_player_ship_ref(ship: Node) -> void:
	player_ship = ship


func _create_ship_node(sid: int, pos: Vector2, heading: float, faction: int, ship_name: String) -> Node:
	if _ship_physics_script == null:
		_ship_physics_script = load(SHIP_PHYSICS_PATH) as Script
	var ship: Node = _ship_physics_script.new()
	ship.name = "Ship_%d" % sid
	ship.call("setup", sid, pos, heading, faction, ship_name)
	add_child(ship)
	return ship


func _combined_ships_dict() -> Dictionary:
	var merged: Dictionary = all_ships.duplicate()
	if ai_director != null:
		for k in ai_director.ai_ships.keys():
			merged[k] = ai_director.ai_ships[k]
	return merged


func _is_ui_open() -> bool:
	var map_open: bool = hud_overlay != null and hud_overlay.has_method("is_world_map_open") and bool(hud_overlay.call("is_world_map_open"))
	return map_open or (cargo_grid_ui != null and cargo_grid_ui.visible) or (harbor_ui != null and harbor_ui.visible)


func _clear_game_world() -> void:
	_respawn_timer = -1.0
	_server_respawn_timers.clear()
	_client_sync.reset()
	if fx_manager != null and fx_manager.has_method("clear_all"):
		fx_manager.call("clear_all")
	for node in [ai_director, loot_system, combat_system, world_map, player_grid]:
		if node != null:
			if node.has_method("clear_all"):
				node.call("clear_all")
			node.queue_free()
	ai_director = null
	loot_system = null
	combat_system = null
	world_map = null
	player_grid = null
	for s in all_ships.values():
		if is_instance_valid(s):
			s.queue_free()
	all_ships.clear()
	player_ship = null
	for r in ship_renderers.values():
		if is_instance_valid(r):
			r.queue_free()
	ship_renderers.clear()

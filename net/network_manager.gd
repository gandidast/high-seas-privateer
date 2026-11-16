class_name NetworkManager
extends Node
## WebSocketMultiplayerPeer manager for Solo, Client ("One-World"), and Headless Server modes.
## Must live at a deterministic SceneTree path (e.g. /root/Main/NetworkManager) on both server and client.

signal server_started(port: int)
signal client_joined(local_ship_id: int, world_seed: int)
signal client_disconnected_from_server(reason: String)
signal snapshot_received(snapshot: Dictionary)
signal peer_ship_joined(peer_id: int, captain_name: String)
signal peer_ship_left(peer_id: int)
signal connection_status_changed(status_text: String)

const ServerConfigScript := preload("res://net/server_config.gd")

const SYNC_INTERVAL: float = 0.05 # 20 Hz server snapshot broadcast
const INPUT_INTERVAL: float = 0.05
const LOCAL_PROBE_TIMEOUT_SEC: float = 0.6
const SERVER_BOOT_WAIT_SEC: float = 0.8
const CLIENT_CONNECT_TIMEOUT_SEC: float = 40.0
const MAX_BOOT_CONNECT_RETRIES: int = 3

enum Mode {
	SOLO = 0,
	CLIENT = 1,
	SERVER = 2
}

enum AutoStartState {
	IDLE = 0,
	PROBING = 1,
	WAITING_FOR_BOOT = 2,
	CONNECTING_AFTER_BOOT = 3
}

var current_mode: int = Mode.SOLO
var listen_port: int = Contracts.SERVER_DEFAULT_PORT
var world_seed: int = Contracts.DEFAULT_WORLD_SEED
var local_captain_name: String = "Käpt'n"
var local_peer_id: int = 1

var world_map_ref: Node = null
var combat_system_ref: CombatSystem = null
var loot_system_ref: LootSystem = null
var ai_director_ref: AIDirector = null
var all_ships_ref: Dictionary = {}

var _peer: WebSocketMultiplayerPeer = null
var _sync_accum: float = 0.0
var _input_accum: float = 0.0
var _peer_names: Dictionary = {} # peer_id (int) -> String
var _signals_bound: bool = false

var _auto_state: int = AutoStartState.IDLE
var _tcp_probe: StreamPeerTCP = null
var _state_timer: float = 0.0
var _connect_timeout_timer: float = 0.0
var _pending_url: String = ""
var _pending_captain_name: String = "Käpt'n"
var _pending_port: int = Contracts.SERVER_DEFAULT_PORT
var _autostart_attempted: bool = false
var _connect_retries: int = 0
var _local_server_pid: int = -1
var last_target_url: String = ""
var last_captain_name: String = "Käpt'n"


static func _get_all_cmdline_args() -> PackedStringArray:
	var combined := PackedStringArray()
	combined.append_array(OS.get_cmdline_args())
	combined.append_array(OS.get_cmdline_user_args())
	return combined


static func is_server_mode_requested() -> bool:
	var args: PackedStringArray = _get_all_cmdline_args()
	for arg in args:
		if arg == "--server" or arg == "-server":
			return true
	return false


static func get_cli_port(default_port: int = Contracts.SERVER_DEFAULT_PORT) -> int:
	var args: PackedStringArray = _get_all_cmdline_args()
	for arg in args:
		if arg.begins_with("--port="):
			var val: String = arg.trim_prefix("--port=")
			if val.is_valid_int():
				return clampi(val.to_int(), 1, 65535)
	var env_port: String = OS.get_environment("PORT").strip_edges()
	if not env_port.is_empty() and env_port.is_valid_int():
		return clampi(env_port.to_int(), 1, 65535)
	return default_port


static func get_cli_seed(default_seed: int = Contracts.DEFAULT_WORLD_SEED) -> int:
	var args: PackedStringArray = _get_all_cmdline_args()
	for arg in args:
		if arg.begins_with("--seed="):
			var val: String = arg.trim_prefix("--seed=")
			if val.is_valid_int():
				return val.to_int()
	return default_seed


func _bus() -> Contracts:
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		return st.root.get_node_or_null("EventBus") as Contracts
	return null


static func normalize_ws_url(url: String) -> String:
	var clean: String = url.strip_edges()
	if clean.is_empty():
		return "ws://localhost:%d" % Contracts.SERVER_DEFAULT_PORT
	if clean.begins_with("https://"):
		clean = "wss://" + clean.substr(8)
	elif clean.begins_with("http://"):
		clean = "ws://" + clean.substr(7)
	elif not clean.begins_with("ws://") and not clean.begins_with("wss://"):
		clean = "ws://" + clean
	return clean


static func extract_host_from_url(url: String) -> String:
	var clean: String = normalize_ws_url(url)
	var after_scheme: String = clean.substr(6) if clean.begins_with("wss://") else clean.substr(5)
	var slash_idx: int = after_scheme.find("/")
	var host_port: String = after_scheme.substr(0, slash_idx) if slash_idx >= 0 else after_scheme
	if host_port.begins_with("["):
		var end_bracket: int = host_port.find("]")
		if end_bracket > 0:
			return host_port.substr(1, end_bracket - 1).to_lower()
	var colon_idx: int = host_port.rfind(":")
	if colon_idx >= 0:
		return host_port.substr(0, colon_idx).to_lower()
	return host_port.to_lower()


static func extract_port_from_url(url: String, default_port: int = Contracts.SERVER_DEFAULT_PORT) -> int:
	var clean: String = normalize_ws_url(url)
	var is_wss: bool = clean.begins_with("wss://")
	var after_scheme: String = clean.substr(6) if is_wss else clean.substr(5)
	var slash_idx: int = after_scheme.find("/")
	var host_port: String = after_scheme.substr(0, slash_idx) if slash_idx >= 0 else after_scheme
	var colon_idx: int = host_port.rfind(":")
	if colon_idx >= 0:
		var port_str: String = host_port.substr(colon_idx + 1)
		if port_str.is_valid_int():
			return clampi(port_str.to_int(), 1, 65535)
	return 443 if is_wss else default_port


static func is_local_url(url: String) -> bool:
	var host: String = extract_host_from_url(url)
	return host == "localhost" or host == "127.0.0.1" or host == "0.0.0.0" or host == "::1"


func _ready() -> void:
	name = "NetworkManager"


func _process(delta: float) -> void:
	if _auto_state == AutoStartState.IDLE:
		if current_mode == Mode.CLIENT and _connect_timeout_timer > 0.0:
			if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
				_connect_timeout_timer -= delta
				if _connect_timeout_timer <= 0.0:
					_connect_timeout_timer = 0.0
					_on_connection_timeout()
			else:
				_connect_timeout_timer = 0.0
		return

	_state_timer += delta
	if _auto_state == AutoStartState.PROBING:
		if _tcp_probe != null:
			_tcp_probe.poll()
			var st: int = _tcp_probe.get_status()
			if st == StreamPeerTCP.STATUS_CONNECTED:
				_close_probe()
				_auto_state = AutoStartState.IDLE
				connection_status_changed.emit("Lokaler Server gefunden – verbinde mit One-World...")
				_connect_timeout_timer = CLIENT_CONNECT_TIMEOUT_SEC
				start_client(_pending_url, _pending_captain_name)
				return
			elif st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
				_close_probe()
				_begin_local_server_autostart()
				return
		if _state_timer >= LOCAL_PROBE_TIMEOUT_SEC:
			_close_probe()
			_begin_local_server_autostart()
	elif _auto_state == AutoStartState.WAITING_FOR_BOOT:
		if _state_timer >= SERVER_BOOT_WAIT_SEC:
			_auto_state = AutoStartState.CONNECTING_AFTER_BOOT
			_state_timer = 0.0
			connection_status_changed.emit("Verbinde mit lokalem One-World Server (Port %d)..." % _pending_port)
			_connect_timeout_timer = CLIENT_CONNECT_TIMEOUT_SEC
			var err: int = start_client(_pending_url, _pending_captain_name)
			if err != OK:
				_on_connection_failed()
	elif _auto_state == AutoStartState.CONNECTING_AFTER_BOOT and _connect_timeout_timer > 0.0:
		if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
			_connect_timeout_timer -= delta
			if _connect_timeout_timer <= 0.0:
				_connect_timeout_timer = 0.0
				_on_connection_failed()
		else:
			_connect_timeout_timer = 0.0


func bind_simulation(
	p_world_map: Node,
	p_combat_system: CombatSystem,
	p_loot_system: LootSystem,
	p_ai_director: AIDirector,
	p_all_ships: Dictionary
) -> void:
	world_map_ref = p_world_map
	combat_system_ref = p_combat_system
	loot_system_ref = p_loot_system
	ai_director_ref = p_ai_director
	all_ships_ref = p_all_ships


func start_solo() -> void:
	shutdown()
	current_mode = Mode.SOLO
	local_peer_id = 1
	var bus := _bus()
	if bus != null:
		bus.network_mode_changed.emit("solo", false)


func start_server(p_port: int = -1, p_seed: int = Contracts.DEFAULT_WORLD_SEED) -> int:
	shutdown()
	if p_port <= 0:
		listen_port = get_cli_port(Contracts.SERVER_DEFAULT_PORT)
	else:
		listen_port = p_port
	world_seed = p_seed
	_peer = WebSocketMultiplayerPeer.new()
	var err: Error = _peer.create_server(listen_port)
	if err != OK:
		push_error("[NetworkManager] Failed to start WebSocket server on port %d (err=%d)" % [listen_port, err])
		return err

	multiplayer.multiplayer_peer = _peer
	current_mode = Mode.SERVER
	local_peer_id = 1
	_connect_multiplayer_signals()
	_bind_server_eventbus_relays()
	var bus := _bus()
	if bus != null:
		bus.network_mode_changed.emit("server", true)
	server_started.emit(listen_port)
	print("[NetworkManager] WebSocket server listening on port %d (seed=%d)" % [listen_port, world_seed])
	return OK


func connect_or_autostart(url: String, captain_name: String = "Käpt'n") -> void:
	shutdown()
	var raw_url: String = url.strip_edges()
	var used_placeholder_fallback: bool = false
	if ServerConfigScript.is_placeholder_url(raw_url):
		raw_url = ServerConfigScript.LOCAL_SERVER_URL
		used_placeholder_fallback = true

	_pending_url = normalize_ws_url(raw_url)
	_pending_captain_name = captain_name.strip_edges()
	if _pending_captain_name.is_empty():
		_pending_captain_name = "Freibeuter"
	_pending_port = extract_port_from_url(_pending_url, Contracts.SERVER_DEFAULT_PORT)
	_autostart_attempted = false
	_connect_retries = 0
	last_target_url = _pending_url
	last_captain_name = _pending_captain_name

	if is_local_url(_pending_url) and not OS.has_feature("web"):
		_tcp_probe = StreamPeerTCP.new()
		var probe_err: Error = _tcp_probe.connect_to_host("127.0.0.1", _pending_port)
		if probe_err != OK:
			_close_probe()
			_begin_local_server_autostart()
			return
		_auto_state = AutoStartState.PROBING
		_state_timer = 0.0
		if used_placeholder_fallback:
			connection_status_changed.emit("Platzhalter erkannt – weiche auf %s aus (prüfe Port %d)..." % [_pending_url, _pending_port])
		else:
			connection_status_changed.emit("Prüfe lokalen One-World Server auf Port %d..." % _pending_port)
	else:
		if used_placeholder_fallback:
			connection_status_changed.emit("Platzhalter erkannt – verbinde mit %s ..." % _pending_url)
		elif _pending_url.contains("onrender.com"):
			connection_status_changed.emit("Verbinde mit One-World (%s – Render Free Tier wacht ggf. ~25s auf)..." % _pending_url)
		else:
			connection_status_changed.emit("Verbinde mit One-World (%s)..." % _pending_url)
		_connect_timeout_timer = CLIENT_CONNECT_TIMEOUT_SEC
		var err: int = start_client(_pending_url, _pending_captain_name)
		if err != OK:
			_connect_timeout_timer = 0.0
			client_disconnected_from_server.emit("Verbindungsfehler zu %s (Code %d)." % [_pending_url, err])


func reconnect_last() -> bool:
	if last_target_url.is_empty():
		return false
	connect_or_autostart(last_target_url, last_captain_name)
	return true


func _begin_local_server_autostart() -> void:
	if _autostart_attempted:
		return
	_autostart_attempted = true
	connection_status_changed.emit("Kein Server auf Port %d – starte lokalen One-World Server..." % _pending_port)
	var pid: int = spawn_local_headless_server(_pending_port, world_seed)
	if pid <= 0:
		_auto_state = AutoStartState.IDLE
		client_disconnected_from_server.emit("Lokaler Headless-Server konnte nicht gestartet werden.")
		return
	_local_server_pid = pid
	_auto_state = AutoStartState.WAITING_FOR_BOOT
	_state_timer = 0.0


func spawn_local_headless_server(port: int = Contracts.SERVER_DEFAULT_PORT, p_seed: int = Contracts.DEFAULT_WORLD_SEED) -> int:
	if OS.has_feature("web"):
		return -1
	var exe_path: String = OS.get_executable_path()
	var args := PackedStringArray(["--headless"])
	var proj_dir: String = ProjectSettings.globalize_path("res://")
	if not proj_dir.is_empty() and FileAccess.file_exists(proj_dir.path_join("project.godot")):
		args.append("--path")
		args.append(proj_dir)
	args.append("--")
	args.append("--server")
	args.append("--port=%d" % port)
	args.append("--seed=%d" % p_seed)

	var pid: int = OS.create_process(exe_path, args, false)
	if pid > 0:
		print("[NetworkManager] Auto-started local headless server (PID %d, Port %d)" % [pid, port])
	else:
		push_error("[NetworkManager] OS.create_process failed for headless server on port %d" % port)
	return pid


func _close_probe() -> void:
	if _tcp_probe != null:
		_tcp_probe.disconnect_from_host()
		_tcp_probe = null


func _close_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_peer = null
	_peer_names.clear()
	current_mode = Mode.SOLO


func start_client(url: String, captain_name: String = "Käpt'n") -> int:
	_close_peer()
	local_captain_name = captain_name.strip_edges()
	if local_captain_name.is_empty():
		local_captain_name = "Freibeuter"

	var target_url: String = normalize_ws_url(url)

	_peer = WebSocketMultiplayerPeer.new()
	var err: Error = _peer.create_client(target_url)
	if err != OK:
		push_error("[NetworkManager] Failed to connect to %s (err=%d)" % [target_url, err])
		return err

	multiplayer.multiplayer_peer = _peer
	current_mode = Mode.CLIENT
	_connect_multiplayer_signals()
	var bus := _bus()
	if bus != null:
		bus.network_mode_changed.emit("client", false)
		bus.notification_posted.emit("Verbinde zu %s..." % target_url, "net")
	return OK


func shutdown() -> void:
	_auto_state = AutoStartState.IDLE
	_state_timer = 0.0
	_connect_timeout_timer = 0.0
	_close_probe()
	_close_peer()


func step_network(delta: float, local_steer: float = 0.0, local_sail_state: int = Contracts.SailState.ANCHORED) -> void:
	if current_mode == Mode.SERVER:
		_sync_accum += delta
		if _sync_accum >= SYNC_INTERVAL:
			_sync_accum = 0.0
			_broadcast_world_snapshot()
	elif current_mode == Mode.CLIENT:
		if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_input_accum += delta
			if _input_accum >= INPUT_INTERVAL:
				_input_accum = 0.0
				rpc_id(1, "rpc_send_input", local_steer, local_sail_state)


func send_input_immediately(local_steer: float, local_sail_state: int) -> void:
	if current_mode == Mode.CLIENT and multiplayer.multiplayer_peer != null:
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_input_accum = 0.0
			rpc_id(1, "rpc_send_input", local_steer, local_sail_state)


func send_fire_request(is_starboard: bool) -> void:
	if current_mode == Mode.CLIENT and multiplayer.multiplayer_peer != null:
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			rpc_id(1, "rpc_request_fire", is_starboard)


func send_player_stats(stats: Contracts.ShipStats) -> void:
	if current_mode == Mode.CLIENT and stats != null and multiplayer.multiplayer_peer != null:
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			rpc_id(1, "rpc_sync_player_stats", stats.to_dict())


func send_ship_class_upgrade(new_hull_tier: int) -> void:
	if current_mode == Mode.CLIENT and multiplayer.multiplayer_peer != null:
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			rpc_id(1, "rpc_upgrade_ship_class", new_hull_tier)


# ==============================================================================
# MULTIPLAYER LIFECYCLE CALLBACKS
# ==============================================================================

func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _bind_server_eventbus_relays() -> void:
	if _signals_bound:
		return
	var bus := _bus()
	if bus == null:
		return
	_signals_bound = true
	if not bus.broadside_fired.is_connected(_on_server_broadside_fired):
		bus.broadside_fired.connect(_on_server_broadside_fired)
	if not bus.cannonball_spawned.is_connected(_on_server_cannonball_spawned):
		bus.cannonball_spawned.connect(_on_server_cannonball_spawned)
	if not bus.cannonball_impact.is_connected(_on_server_cannonball_impact):
		bus.cannonball_impact.connect(_on_server_cannonball_impact)
	if not bus.ship_sunk.is_connected(_on_server_ship_sunk):
		bus.ship_sunk.connect(_on_server_ship_sunk)
	if not bus.loot_collected.is_connected(_on_server_loot_collected):
		bus.loot_collected.connect(_on_server_loot_collected)
	if not bus.weather_changed.is_connected(_on_server_weather_changed):
		bus.weather_changed.connect(_on_server_weather_changed)
	if not bus.wanted_level_changed.is_connected(_on_server_wanted_level_changed):
		bus.wanted_level_changed.connect(_on_server_wanted_level_changed)
	if not bus.fort_damaged.is_connected(_on_server_fort_damaged):
		bus.fort_damaged.connect(_on_server_fort_damaged)
	if not bus.fort_destroyed.is_connected(_on_server_fort_destroyed):
		bus.fort_destroyed.connect(_on_server_fort_destroyed)
	if not bus.sea_monster_spawned.is_connected(_on_server_sea_monster_spawned):
		bus.sea_monster_spawned.connect(_on_server_sea_monster_spawned)
	if not bus.sea_monster_defeated.is_connected(_on_server_sea_monster_defeated):
		bus.sea_monster_defeated.connect(_on_server_sea_monster_defeated)


func _on_peer_connected(peer_id: int) -> void:
	if current_mode == Mode.SERVER:
		print("[NetworkManager] Peer connected: %d" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if current_mode == Mode.SERVER:
		print("[NetworkManager] Peer disconnected: %d" % peer_id)
		_peer_names.erase(peer_id)
		peer_ship_left.emit(peer_id)


func _on_connected_to_server() -> void:
	_auto_state = AutoStartState.IDLE
	_state_timer = 0.0
	_connect_timeout_timer = 0.0
	local_peer_id = multiplayer.get_unique_id()
	connection_status_changed.emit("Verbunden! Betrete One-World...")
	rpc_id(1, "rpc_join_world", local_captain_name)


func _on_connection_timeout() -> void:
	if not _autostart_attempted and not _pending_url.is_empty() and is_local_url(_pending_url) and not OS.has_feature("web"):
		_close_peer()
		_begin_local_server_autostart()
		return
	var timed_out_url: String = _pending_url if not _pending_url.is_empty() else "One-World Server"
	shutdown()
	client_disconnected_from_server.emit("Zeitüberschreitung (Timeout): %s antwortet nicht." % timed_out_url)


func _on_connection_failed() -> void:
	_connect_timeout_timer = 0.0
	if _auto_state == AutoStartState.CONNECTING_AFTER_BOOT and _connect_retries < MAX_BOOT_CONNECT_RETRIES:
		_connect_retries += 1
		_close_peer()
		_auto_state = AutoStartState.WAITING_FOR_BOOT
		_state_timer = 0.2
		connection_status_changed.emit("Lokaler Server startet noch (Versuch %d/%d)..." % [_connect_retries, MAX_BOOT_CONNECT_RETRIES])
		return
	if not _autostart_attempted and not _pending_url.is_empty() and is_local_url(_pending_url) and not OS.has_feature("web"):
		_close_peer()
		_begin_local_server_autostart()
		return
	var failed_url: String = _pending_url if not _pending_url.is_empty() else "Server"
	shutdown()
	client_disconnected_from_server.emit("Verbindung zu %s fehlgeschlagen." % failed_url)


func _on_server_disconnected() -> void:
	shutdown()
	client_disconnected_from_server.emit("Verbindung zum One-World Server getrennt.")


# ==============================================================================
# SERVER SNAPSHOT & RPC DEFINITIONS
# ==============================================================================

func _broadcast_world_snapshot() -> void:
	if current_mode != Mode.SERVER:
		return
	if multiplayer.get_peers().is_empty():
		return

	var ships_arr: Array = []
	var seen_ship_ids: Dictionary = {}
	for ship_var in all_ships_ref.values():
		var s: Node = ship_var
		if s != null and s.has_method("to_sync_dict"):
			var sid: int = int(s.get("ship_id"))
			if not seen_ship_ids.has(sid):
				seen_ship_ids[sid] = true
				ships_arr.append(s.call("to_sync_dict"))

	if ai_director_ref != null:
		for ai_ship_var in ai_director_ref.ai_ships.values():
			var ai_s: Node = ai_ship_var
			if ai_s != null and ai_s.has_method("to_sync_dict"):
				var ai_sid: int = int(ai_s.get("ship_id"))
				if not seen_ship_ids.has(ai_sid):
					seen_ship_ids[ai_sid] = true
					ships_arr.append(ai_s.call("to_sync_dict"))

	var drops_arr: Array = []
	if loot_system_ref != null:
		drops_arr = loot_system_ref.to_sync_array()

	var forts_arr: Array = []
	if combat_system_ref != null:
		forts_arr = combat_system_ref.get_fort_sync_array()

	var monster_dict: Dictionary = {}
	if ai_director_ref != null:
		monster_dict = ai_director_ref.get_sea_monster_sync_dict()

	var w_dir := Vector2.RIGHT
	var w_str: float = 0.7
	var w_state: int = Contracts.WeatherState.CLEAR
	var w_int: float = 0.0
	if world_map_ref != null:
		var wd: Variant = world_map_ref.get("wind_direction")
		var ws: Variant = world_map_ref.get("wind_strength")
		var cw: Variant = world_map_ref.get("current_weather")
		var wi: Variant = world_map_ref.get("weather_intensity")
		if wd is Vector2:
			w_dir = wd
		if ws is float or ws is int:
			w_str = float(ws)
		if cw is int:
			w_state = cw
		if wi is float or wi is int:
			w_int = float(wi)

	var wanted: int = ai_director_ref.wanted_level if ai_director_ref != null else 0

	var snapshot: Dictionary = {
		"wind_x": w_dir.x,
		"wind_y": w_dir.y,
		"wind_strength": w_str,
		"weather_state": w_state,
		"weather_intensity": w_int,
		"wanted_level": wanted,
		"ships": ships_arr,
		"drops": drops_arr,
		"forts": forts_arr,
		"sea_monster": monster_dict
	}
	rpc("rpc_world_snapshot", snapshot)


@rpc("any_peer", "reliable")
func rpc_join_world(captain_name: String) -> void:
	if current_mode != Mode.SERVER:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var clean_name: String = captain_name.strip_edges().left(24)
	if clean_name.is_empty():
		clean_name = "Pirat #%d" % sender_id
	_peer_names[sender_id] = clean_name
	peer_ship_joined.emit(sender_id, clean_name)
	rpc_id(sender_id, "rpc_welcome_client", sender_id, world_seed)


@rpc("authority", "reliable")
func rpc_welcome_client(assigned_ship_id: int, server_seed: int) -> void:
	if current_mode != Mode.CLIENT:
		return
	local_peer_id = assigned_ship_id
	world_seed = server_seed
	client_joined.emit(assigned_ship_id, server_seed)


@rpc("any_peer", "unreliable_ordered")
func rpc_send_input(steer_input: float, sail_state: int) -> void:
	if current_mode != Mode.SERVER:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var ship: Node = all_ships_ref.get(sender_id, null)
	if ship == null:
		return
	ship.set_meta("net_steer", clampf(steer_input, -1.0, 1.0))
	if ship.has_method("set_sail_state"):
		ship.call("set_sail_state", clampi(sail_state, Contracts.SailState.ANCHORED, Contracts.SailState.FULL_SAIL))


@rpc("any_peer", "reliable")
func rpc_request_fire(is_starboard: bool) -> void:
	if current_mode != Mode.SERVER or combat_system_ref == null:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	combat_system_ref.fire_broadside(sender_id, is_starboard)


@rpc("any_peer", "reliable")
func rpc_sync_player_stats(stats_dict: Dictionary) -> void:
	if current_mode != Mode.SERVER:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var ship: Node = all_ships_ref.get(sender_id, null)
	if ship == null:
		return
	var stats := Contracts.ShipStats.from_dict(stats_dict)
	if ship.has_method("apply_stats"):
		ship.call("apply_stats", stats)
	var bus := _bus()
	if bus != null:
		bus.ship_stats_compiled.emit(sender_id, stats)


@rpc("any_peer", "reliable")
func rpc_upgrade_ship_class(new_hull_tier: int) -> void:
	if current_mode != Mode.SERVER:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var ship: Node = all_ships_ref.get(sender_id, null)
	if ship != null and ship.has_method("upgrade_ship_class"):
		ship.call("upgrade_ship_class", clampi(new_hull_tier, 0, 2))


@rpc("authority", "unreliable_ordered")
func rpc_world_snapshot(snapshot: Dictionary) -> void:
	if current_mode != Mode.CLIENT:
		return
	snapshot_received.emit(snapshot)


@rpc("authority", "unreliable")
func rpc_client_broadside_fired(ship_id: int, is_starboard: bool, origin: Vector2, dir: Vector2) -> void:
	if current_mode == Mode.CLIENT:
		var bus := _bus()
		if bus != null:
			bus.broadside_fired.emit(ship_id, is_starboard, origin, dir, [])


@rpc("authority", "unreliable")
func rpc_client_cannonball_spawned(shot_data: Dictionary) -> void:
	if current_mode == Mode.CLIENT:
		var bus := _bus()
		if bus != null:
			bus.cannonball_spawned.emit(shot_data)


@rpc("authority", "unreliable")
func rpc_client_cannonball_impact(
	world_pos: Vector2,
	hit_ship_id: int,
	damage: float,
	is_water_splash: bool,
	is_powder_crit: bool
) -> void:
	if current_mode == Mode.CLIENT:
		var bus := _bus()
		if bus != null:
			bus.cannonball_impact.emit(world_pos, hit_ship_id, damage, is_water_splash, is_powder_crit)


@rpc("authority", "reliable")
func rpc_client_ship_sunk(ship_id: int, world_pos: Vector2, faction: int, killer_ship_id: int) -> void:
	if current_mode == Mode.CLIENT:
		var bus := _bus()
		if bus != null:
			bus.ship_sunk.emit(ship_id, world_pos, faction, killer_ship_id)


@rpc("authority", "reliable")
func rpc_client_loot_collected(drop_id: int, collector_ship_id: int, gold: int) -> void:
	if current_mode == Mode.CLIENT and collector_ship_id == local_peer_id and gold > 0:
		var dummy := Contracts.LootDropData.new()
		dummy.drop_id = drop_id
		dummy.gold = gold
		var bus := _bus()
		if bus != null:
			bus.loot_collected.emit(drop_id, collector_ship_id, dummy)


@rpc("authority", "reliable")
func rpc_client_weather_changed(weather_state: int, intensity: float) -> void:
	if current_mode == Mode.CLIENT:
		var bus := _bus()
		if bus != null:
			bus.weather_changed.emit(weather_state, intensity)


@rpc("authority", "reliable")
func rpc_client_wanted_level_changed(new_level: int) -> void:
	if current_mode == Mode.CLIENT:
		var bus := _bus()
		if bus != null:
			bus.wanted_level_changed.emit(new_level)


@rpc("authority", "unreliable")
func rpc_client_fort_damaged(fort_id: int, hp: float, max_hp: float, world_pos: Vector2) -> void:
	if current_mode == Mode.CLIENT:
		var bus := _bus()
		if bus != null:
			bus.fort_damaged.emit(fort_id, hp, max_hp, world_pos)


@rpc("authority", "reliable")
func rpc_client_fort_destroyed(fort_id: int, world_pos: Vector2) -> void:
	if current_mode == Mode.CLIENT:
		var bus := _bus()
		if bus != null:
			bus.fort_destroyed.emit(fort_id, world_pos)


@rpc("authority", "reliable")
func rpc_client_sea_monster_spawned(monster_id: int, world_pos: Vector2, max_hp: float) -> void:
	if current_mode == Mode.CLIENT:
		var bus := _bus()
		if bus != null:
			bus.sea_monster_spawned.emit(monster_id, world_pos, max_hp)


@rpc("authority", "reliable")
func rpc_client_sea_monster_defeated(monster_id: int, world_pos: Vector2) -> void:
	if current_mode == Mode.CLIENT:
		var bus := _bus()
		if bus != null:
			bus.sea_monster_defeated.emit(monster_id, world_pos)


func _on_server_broadside_fired(
	ship_id: int,
	is_starboard: bool,
	origin: Vector2,
	dir: Vector2,
	_cannons: Array
) -> void:
	if current_mode == Mode.SERVER and not multiplayer.get_peers().is_empty():
		rpc("rpc_client_broadside_fired", ship_id, is_starboard, origin, dir)


func _on_server_cannonball_spawned(shot_data: Dictionary) -> void:
	if current_mode == Mode.SERVER and not multiplayer.get_peers().is_empty():
		rpc("rpc_client_cannonball_spawned", shot_data)


func _on_server_cannonball_impact(
	world_pos: Vector2,
	hit_ship_id: int,
	damage: float,
	is_water_splash: bool,
	is_powder_crit: bool
) -> void:
	if current_mode == Mode.SERVER and not multiplayer.get_peers().is_empty():
		rpc("rpc_client_cannonball_impact", world_pos, hit_ship_id, damage, is_water_splash, is_powder_crit)


func _on_server_ship_sunk(ship_id: int, world_pos: Vector2, faction: int, killer_ship_id: int) -> void:
	if current_mode == Mode.SERVER and not multiplayer.get_peers().is_empty():
		rpc("rpc_client_ship_sunk", ship_id, world_pos, faction, killer_ship_id)


func _on_server_loot_collected(drop_id: int, collector_ship_id: int, loot_data: Contracts.LootDropData) -> void:
	if current_mode == Mode.SERVER and not multiplayer.get_peers().is_empty():
		var gold: int = loot_data.gold if loot_data != null else 0
		rpc("rpc_client_loot_collected", drop_id, collector_ship_id, gold)


func _on_server_weather_changed(weather_state: int, intensity: float) -> void:
	if current_mode == Mode.SERVER and not multiplayer.get_peers().is_empty():
		rpc("rpc_client_weather_changed", weather_state, intensity)


func _on_server_wanted_level_changed(new_level: int) -> void:
	if current_mode == Mode.SERVER and not multiplayer.get_peers().is_empty():
		rpc("rpc_client_wanted_level_changed", new_level)


func _on_server_fort_damaged(fort_id: int, hp: float, max_hp: float, world_pos: Vector2) -> void:
	if current_mode == Mode.SERVER and not multiplayer.get_peers().is_empty():
		rpc("rpc_client_fort_damaged", fort_id, hp, max_hp, world_pos)


func _on_server_fort_destroyed(fort_id: int, world_pos: Vector2) -> void:
	if current_mode == Mode.SERVER and not multiplayer.get_peers().is_empty():
		rpc("rpc_client_fort_destroyed", fort_id, world_pos)


func _on_server_sea_monster_spawned(monster_id: int, world_pos: Vector2, max_hp: float) -> void:
	if current_mode == Mode.SERVER and not multiplayer.get_peers().is_empty():
		rpc("rpc_client_sea_monster_spawned", monster_id, world_pos, max_hp)


func _on_server_sea_monster_defeated(monster_id: int, world_pos: Vector2) -> void:
	if current_mode == Mode.SERVER and not multiplayer.get_peers().is_empty():
		rpc("rpc_client_sea_monster_defeated", monster_id, world_pos)

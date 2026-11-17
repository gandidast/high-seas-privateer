class_name NetworkManager
extends Node
## WebSocketMultiplayerPeer manager for Solo, Client ("One-World"), and Headless Server modes.
## Uses 15 Hz delta/revision-compressed world snapshots + 3.0s safety keyframes.
## Must live at a deterministic SceneTree path (e.g. /root/Main/NetworkManager) on both server and client.

signal server_started(port: int)
signal client_joined(local_ship_id: int, world_seed: int)
signal client_joined_with_save(local_ship_id: int, world_seed: int, display_name: String, session_token: String, save_data: Dictionary)
signal auth_failed(reason: String, clear_saved_auth: bool)
signal client_disconnected_from_server(reason: String)
signal snapshot_received(snapshot: Dictionary)
signal peer_ship_joined(peer_id: int, captain_name: String)
signal peer_ship_joined_with_save(peer_id: int, captain_name: String, save_data: Dictionary)
signal peer_ship_left(peer_id: int)
signal connection_status_changed(status_text: String)
signal bounty_spawned(quest_id: String, ship_id: int)
signal salvage_spawned(quest_id: String, drop_id: int, world_pos: Vector2)

const SYNC_INTERVAL: float = 0.058 # Fires cleanly every 2 ticks on 30Hz physics (steady 15 Hz, zero 66/100ms skip)
const KEYFRAME_INTERVAL: float = 10.0 # Safety full-state keyframe interval (WebSocket/TCP is reliable)
const INPUT_INTERVAL: float = 0.05
const AUTOSAVE_INTERVAL: float = 15.0
const AOI_FULL_RATE_DIST_SQ: float = 1250.0 * 1250.0
const SaveStoreScript := preload("res://sim/save_store.gd")

enum Mode { SOLO = 0, CLIENT = 1, SERVER = 2 }

var current_mode: int = Mode.SOLO
var listen_port: int = Contracts.SERVER_DEFAULT_PORT
var world_seed: int = Contracts.DEFAULT_WORLD_SEED
var local_captain_name: String = "Käpt'n"
var local_peer_id: int = 1
var local_auth_mode: String = "guest"
var local_auth_secret: String = ""
var local_session_token: String = ""
var local_saved_profile: Dictionary = {}

var world_map_ref: Node = null
var combat_system_ref: CombatSystem = null
var loot_system_ref: LootSystem = null
var ai_director_ref: AIDirector = null
var all_ships_ref: Dictionary = {}

var _peer: WebSocketMultiplayerPeer = null
var _host_runner: LocalHostRunner = LocalHostRunner.new()
var _account_store: SaveStoreScript = SaveStoreScript.new()
var _sync_accum: float = 0.0
var _keyframe_accum: float = 0.0
var _autosave_accum: float = 0.0
var _server_time: float = 0.0
var _force_full_snapshot: bool = true
var _input_accum: float = 0.0
var _last_sent_steer: float = 0.0
var _last_sent_sail: int = Contracts.SailState.ANCHORED
var _peer_names: Dictionary = {}
var _peer_accounts: Dictionary = {}    # peer_id (int) -> username_key (String)
var _account_peers: Dictionary = {}    # username_key (String) -> peer_id (int)
var _peer_save_states: Dictionary = {} # peer_id (int) -> Dictionary
var _dirty_save_peers: Dictionary = {} # peer_id (int) -> bool
var _signals_bound: bool = false

# Server delta-tracking caches
var _last_sent_ships: Dictionary = {}
var _last_sent_drops_rev: int = -1
var _last_sent_forts_rev: int = -1
var _last_sent_wanted_rev: int = -1
var _last_sent_monster_rev: int = -1
var _last_wind_vec: Vector3 = Vector3(999.0, 999.0, -1.0)
var _last_weather_state: int = -1
var _last_weather_int: float = -1.0
var _snapshot_seq: int = 0
var _peers_needing_full: Dictionary = {}
var _pending_shot_batch: Array = []
var _pending_impact_batch: Array = []


static func _get_all_cmdline_args() -> PackedStringArray:
	var combined := PackedStringArray()
	combined.append_array(OS.get_cmdline_args())
	combined.append_array(OS.get_cmdline_user_args())
	return combined


static func is_server_mode_requested() -> bool:
	for arg in _get_all_cmdline_args():
		if arg == "--server" or arg == "-server":
			return true
	return false


static func get_cli_port(default_port: int = Contracts.SERVER_DEFAULT_PORT) -> int:
	for arg in _get_all_cmdline_args():
		if arg.begins_with("--port="):
			var val: String = arg.trim_prefix("--port=")
			if val.is_valid_int():
				return clampi(val.to_int(), 1, 65535)
	var env_port: String = OS.get_environment("PORT").strip_edges()
	if not env_port.is_empty() and env_port.is_valid_int():
		return clampi(env_port.to_int(), 1, 65535)
	return default_port


static func get_cli_seed(default_seed: int = Contracts.DEFAULT_WORLD_SEED) -> int:
	for arg in _get_all_cmdline_args():
		if arg.begins_with("--seed="):
			var val: String = arg.trim_prefix("--seed=")
			if val.is_valid_int():
				return val.to_int()
	return default_seed


static func normalize_ws_url(url: String) -> String:
	var clean: String = url.strip_edges()
	if clean.is_empty():
		return "ws://localhost:%d" % Contracts.SERVER_DEFAULT_PORT
	if clean.begins_with("https://"):
		return "wss://" + clean.substr(8)
	if clean.begins_with("http://"):
		return "ws://" + clean.substr(7)
	if not clean.begins_with("ws://") and not clean.begins_with("wss://"):
		return "ws://" + clean
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
	return (host_port.substr(0, colon_idx) if colon_idx >= 0 else host_port).to_lower()


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


func _bus() -> Contracts:
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		return st.root.get_node_or_null("EventBus") as Contracts
	return null


func _ready() -> void:
	name = "NetworkManager"


func _process(delta: float) -> void:
	_host_runner.tick(delta, current_mode == Mode.CLIENT, multiplayer, self)


func bind_simulation(p_world_map: Node, p_combat_system: CombatSystem, p_loot_system: LootSystem, p_ai_director: AIDirector, p_all_ships: Dictionary) -> void:
	world_map_ref = p_world_map
	combat_system_ref = p_combat_system
	loot_system_ref = p_loot_system
	ai_director_ref = p_ai_director
	all_ships_ref = p_all_ships


func start_solo() -> void:
	shutdown()
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 0
	current_mode = Mode.SOLO
	local_peer_id = 1
	var bus := _bus()
	if bus != null:
		bus.network_mode_changed.emit("solo", false)


func start_server(p_port: int = -1, p_seed: int = Contracts.DEFAULT_WORLD_SEED) -> int:
	shutdown()
	Engine.physics_ticks_per_second = 30
	Engine.max_fps = 30
	listen_port = get_cli_port(Contracts.SERVER_DEFAULT_PORT) if p_port <= 0 else p_port
	world_seed = p_seed
	_peer = WebSocketMultiplayerPeer.new()
	var err: Error = _peer.create_server(listen_port)
	if err != OK:
		push_error("[NetworkManager] Failed to start WebSocket server on port %d (err=%d)" % [listen_port, err])
		return err

	multiplayer.multiplayer_peer = _peer
	current_mode = Mode.SERVER
	local_peer_id = 1
	_reset_snapshot_caches()
	_connect_multiplayer_signals()
	_bind_server_eventbus_relays()
	var bus := _bus()
	if bus != null:
		bus.network_mode_changed.emit("server", true)
	server_started.emit(listen_port)
	print("[NetworkManager] WebSocket server listening on port %d (seed=%d)" % [listen_port, world_seed])
	return OK


func connect_or_autostart(url: String, captain_name: String = "Käpt'n") -> void:
	connect_with_auth(url, captain_name, "", "guest")


func connect_with_auth(url: String, username: String, secret: String, auth_mode: String = "login") -> void:
	shutdown()
	_host_runner.begin_connect_or_autostart(url, username, self, auth_mode, secret)


func get_last_target_url() -> String:
	return _host_runner.last_target_url


func reconnect_last() -> bool:
	if _host_runner.last_target_url.is_empty():
		return false
	connect_with_auth(_host_runner.last_target_url, _host_runner.last_captain_name, _host_runner.last_auth_secret, _host_runner.last_auth_mode)
	return true


func spawn_local_headless_server(port: int = Contracts.SERVER_DEFAULT_PORT, p_seed: int = Contracts.DEFAULT_WORLD_SEED) -> int:
	return LocalHostRunner.spawn_local_headless_server(port, p_seed)


func close_peer_only() -> void:
	if current_mode == Mode.SERVER:
		save_all_connected_accounts()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_peer = null
	_peer_names.clear()
	_peer_accounts.clear()
	_account_peers.clear()
	_peer_save_states.clear()
	_dirty_save_peers.clear()
	current_mode = Mode.SOLO


func start_client(url: String, captain_name: String = "Käpt'n", auth_mode: String = "guest", auth_secret: String = "") -> int:
	close_peer_only()
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 0
	local_captain_name = captain_name.strip_edges()
	if local_captain_name.is_empty():
		local_captain_name = "Freibeuter"
	local_auth_mode = auth_mode if not auth_mode.is_empty() else "guest"
	local_auth_secret = auth_secret
	local_saved_profile = {}

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
	_host_runner.reset()
	close_peer_only()
	_reset_snapshot_caches()


func step_network(delta: float, local_steer: float = 0.0, local_sail_state: int = Contracts.SailState.ANCHORED, input_seq: int = 0) -> void:
	if current_mode == Mode.SERVER:
		_server_time += delta
		_sync_accum += delta
		_keyframe_accum += delta
		_autosave_accum += delta
		_flush_combat_batches()
		if _sync_accum >= SYNC_INTERVAL:
			_sync_accum = 0.0
			_broadcast_world_snapshot()
		if _autosave_accum >= AUTOSAVE_INTERVAL:
			_autosave_accum = 0.0
			save_all_connected_accounts()
	elif current_mode == Mode.CLIENT:
		if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_input_accum += delta
			var steer_changed: bool = absf(local_steer - _last_sent_steer) > 0.05
			var sail_changed: bool = local_sail_state != _last_sent_sail
			var interval: float = 0.12 if (absf(local_steer) < 0.05 and not sail_changed) else INPUT_INTERVAL
			if steer_changed or sail_changed or _input_accum >= interval:
				_input_accum = 0.0
				_last_sent_steer = local_steer
				_last_sent_sail = local_sail_state
				rpc_id(1, "rpc_send_input", local_steer, local_sail_state, input_seq)


func send_input_immediately(local_steer: float, local_sail_state: int, input_seq: int = 0) -> void:
	if _can_send_client_rpc():
		_input_accum = 0.0
		_last_sent_steer = local_steer
		_last_sent_sail = local_sail_state
		rpc_id(1, "rpc_send_input", local_steer, local_sail_state, input_seq)


func send_fire_request(is_starboard: bool) -> void:
	if _can_send_client_rpc():
		rpc_id(1, "rpc_request_fire", is_starboard)


func send_fire_bow_request() -> void:
	if _can_send_client_rpc():
		rpc_id(1, "rpc_request_fire_bow")


func send_harbor_ui_state(is_open: bool) -> void:
	if _can_send_client_rpc():
		rpc_id(1, "rpc_set_harbor_ui_open", is_open)


func send_bounty_quest_request(target_pos: Vector2, boss_name: String, hull_tier: int = Contracts.ShipClass.BRIGANTINE, quest_id: String = "") -> void:
	if _can_send_client_rpc():
		rpc_id(1, "rpc_request_bounty_spawn", target_pos, boss_name, hull_tier, quest_id)


func send_salvage_quest_request(target_pos: Vector2, quest_id: String) -> void:
	if _can_send_client_rpc():
		rpc_id(1, "rpc_request_salvage_spawn", target_pos, quest_id)


func send_player_stats(stats: Contracts.ShipStats) -> void:
	if stats != null and _can_send_client_rpc():
		rpc_id(1, "rpc_sync_player_stats", stats.to_dict())


func send_ship_class_upgrade(new_hull_tier: int) -> void:
	if _can_send_client_rpc():
		rpc_id(1, "rpc_upgrade_ship_class", new_hull_tier)


func send_ship_repair(new_hp: float) -> void:
	if _can_send_client_rpc():
		rpc_id(1, "rpc_repair_ship", new_hp)


func send_player_save_state(save_dict: Dictionary) -> void:
	if _can_send_client_rpc():
		rpc_id(1, "rpc_sync_player_save_state", save_dict)


func _can_send_client_rpc() -> bool:
	return current_mode == Mode.CLIENT and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _reset_snapshot_caches() -> void:
	_sync_accum = 0.0
	_keyframe_accum = 0.0
	_server_time = 0.0
	_force_full_snapshot = true
	_last_sent_ships.clear()
	_last_sent_drops_rev = -1
	_last_sent_forts_rev = -1
	_last_sent_wanted_rev = -1
	_last_sent_monster_rev = -1
	_last_wind_vec = Vector3(999.0, 999.0, -1.0)
	_last_weather_state = -1
	_last_weather_int = -1.0
	_snapshot_seq = 0
	_peers_needing_full.clear()
	_pending_shot_batch.clear()
	_pending_impact_batch.clear()


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
	bus.broadside_fired.connect(func(sid: int, sb: bool, orig: Vector2, dir: Vector2, _c: Array): _relay_rpc("rpc_client_broadside_fired", [sid, sb, orig, dir]))
	bus.cannonball_spawned.connect(_on_server_cannonball_spawned)
	bus.cannonball_impact.connect(_on_server_cannonball_impact)
	bus.ship_sunk.connect(func(sid: int, pos: Vector2, fac: int, ksid: int): _relay_rpc("rpc_client_ship_sunk", [sid, pos, fac, ksid]))
	bus.player_death_penalty.connect(func(sid: int, gold_lost: int, respawn_sec: float): _relay_rpc("rpc_client_player_death_penalty", [sid, gold_lost, respawn_sec]))
	bus.loot_collected.connect(_on_server_loot_collected)
	bus.weather_changed.connect(func(ws: int, wi: float): _relay_rpc("rpc_client_weather_changed", [ws, wi]))
	bus.wanted_level_changed.connect(func(lvl: int): _relay_rpc("rpc_client_wanted_level_changed", [lvl]))
	bus.fort_damaged.connect(func(fid: int, hp: float, mhp: float, pos: Vector2): _relay_rpc("rpc_client_fort_damaged", [fid, hp, mhp, pos]))
	bus.fort_destroyed.connect(func(fid: int, pos: Vector2): _relay_rpc("rpc_client_fort_destroyed", [fid, pos]))
	bus.sea_monster_spawned.connect(func(mid: int, pos: Vector2, mhp: float): _relay_rpc("rpc_client_sea_monster_spawned", [mid, pos, mhp]))
	bus.sea_monster_defeated.connect(func(mid: int, pos: Vector2): _relay_rpc("rpc_client_sea_monster_defeated", [mid, pos]))


func _on_server_cannonball_spawned(sd: Dictionary) -> void:
	if current_mode != Mode.SERVER or multiplayer.get_peers().is_empty():
		return
	var compact := {
		"shot_id": int(sd.get("shot_id", -1)),
		"shooter_id": int(sd.get("shooter_id", -1)),
		"origin": sd.get("origin", sd.get("pos", Vector2.ZERO)),
		"vel": sd.get("vel", sd.get("velocity", Vector2.ZERO)),
		"max_range": float(sd.get("max_range", 250.0))
	}
	if bool(sd.get("is_bow", false)):
		compact["is_bow"] = true
	if float(sd.get("burn_dps", 0.0)) > 0.0:
		compact["burn_dps"] = float(sd["burn_dps"])
	if float(sd.get("harpoon_pull", 0.0)) > 0.0:
		compact["harpoon_pull"] = float(sd["harpoon_pull"])
	if float(sd.get("chain_slow", 0.0)) > 0.0:
		compact["chain_slow"] = float(sd["chain_slow"])
	var iid: String = str(sd.get("item_id", ""))
	if not iid.is_empty():
		compact["item_id"] = iid
	_pending_shot_batch.append(compact)


func _on_server_cannonball_impact(pos: Vector2, hsid: int, dmg: float, splash: bool, crit: bool) -> void:
	if current_mode != Mode.SERVER or multiplayer.get_peers().is_empty():
		return
	_pending_impact_batch.append([pos, hsid, snappedf(dmg, 0.1), splash, crit])


func _flush_combat_batches() -> void:
	if current_mode != Mode.SERVER or multiplayer.get_peers().is_empty():
		_pending_shot_batch.clear()
		_pending_impact_batch.clear()
		return
	if not _pending_shot_batch.is_empty():
		rpc("rpc_client_cannonball_batch", _pending_shot_batch)
		_pending_shot_batch.clear()
	if not _pending_impact_batch.is_empty():
		rpc("rpc_client_cannonball_impacts", _pending_impact_batch)
		_pending_impact_batch.clear()


func _relay_rpc(method_name: String, args: Array) -> void:
	if current_mode == Mode.SERVER and not multiplayer.get_peers().is_empty():
		callv("rpc", [method_name] + args)


func _on_peer_connected(peer_id: int) -> void:
	if current_mode == Mode.SERVER:
		print("[NetworkManager] Peer connected: %d" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if current_mode == Mode.SERVER:
		print("[NetworkManager] Peer disconnected: %d" % peer_id)
		save_peer_account(peer_id)
		var acct_key: String = str(_peer_accounts.get(peer_id, ""))
		if not acct_key.is_empty() and int(_account_peers.get(acct_key, -1)) == peer_id:
			_account_peers.erase(acct_key)
		_peer_accounts.erase(peer_id)
		_peer_save_states.erase(peer_id)
		_dirty_save_peers.erase(peer_id)
		_peer_names.erase(peer_id)
		_last_sent_ships.erase(peer_id)
		_peers_needing_full.erase(peer_id)
		peer_ship_left.emit(peer_id)


func _on_connected_to_server() -> void:
	_host_runner.on_connected()
	local_peer_id = multiplayer.get_unique_id()
	if local_auth_mode in ["login", "register", "token"]:
		connection_status_changed.emit("Verbunden! Prüfe Konto '%s'..." % local_captain_name)
		rpc_id(1, "rpc_authenticate", local_auth_mode, local_captain_name, local_auth_secret)
	else:
		connection_status_changed.emit("Verbunden! Betrete One-World...")
		rpc_id(1, "rpc_join_world", local_captain_name)


func _on_connection_failed() -> void:
	_host_runner.on_connection_failed(self)


func _on_server_disconnected() -> void:
	shutdown()
	client_disconnected_from_server.emit("Verbindung zum One-World Server getrennt.")


# ==============================================================================
# SERVER DELTA SNAPSHOT & RPC DEFINITIONS
# ==============================================================================

func _broadcast_world_snapshot() -> void:
	if current_mode != Mode.SERVER or multiplayer.get_peers().is_empty():
		return

	_snapshot_seq += 1
	var send_full: bool = _force_full_snapshot or (_keyframe_accum >= KEYFRAME_INTERVAL)
	if send_full:
		_force_full_snapshot = false
		_keyframe_accum = 0.0
		_peers_needing_full.clear()

	var player_positions: Array[Vector2] = []
	for ps_var in all_ships_ref.values():
		var ps: Node = ps_var
		if ps != null and not bool(ps.get("is_sunk")):
			var p_pos: Variant = ps.get("world_pos")
			if p_pos is Vector2:
				player_positions.append(p_pos as Vector2)

	var ships_arr: Array = []
	var seen_ship_ids: Dictionary = {}
	var acks: Dictionary = {}
	for s in all_ships_ref.values():
		if s != null and s.has_method("to_sync_dict"):
			var sid: int = int(s.get("ship_id"))
			if not seen_ship_ids.has(sid):
				seen_ship_ids[sid] = true
				ships_arr.append(_pack_ship_snapshot(s, sid, send_full, false))
				if s.has_meta("last_input_seq"):
					acks[sid] = int(s.get_meta("last_input_seq"))
	if ai_director_ref != null:
		for ai_s in ai_director_ref.ai_ships.values():
			if ai_s != null and ai_s.has_method("to_sync_dict"):
				var ai_sid: int = int(ai_s.get("ship_id"))
				if not seen_ship_ids.has(ai_sid):
					seen_ship_ids[ai_sid] = true
					var is_far: bool = _is_far_from_players(ai_s.get("world_pos") as Vector2, player_positions)
					ships_arr.append(_pack_ship_snapshot(ai_s, ai_sid, send_full, is_far))

	for old_sid in _last_sent_ships.keys():
		if not seen_ship_ids.has(old_sid):
			_last_sent_ships.erase(old_sid)

	var snapshot: Dictionary = { "t": snappedf(_server_time, 0.001), "ships": ships_arr }
	if not acks.is_empty():
		snapshot["acks"] = acks

	if loot_system_ref != null:
		var l_rev: int = loot_system_ref.get_sync_revision()
		if send_full or l_rev != _last_sent_drops_rev:
			_last_sent_drops_rev = l_rev
			snapshot["drops"] = loot_system_ref.to_sync_array()

	if combat_system_ref != null:
		var f_rev: int = combat_system_ref.get_fort_sync_revision()
		if send_full or f_rev != _last_sent_forts_rev:
			_last_sent_forts_rev = f_rev
			snapshot["forts"] = combat_system_ref.get_fort_sync_array()

	if ai_director_ref != null:
		var m_rev: int = ai_director_ref.get_sea_monster_sync_revision()
		if send_full or m_rev != _last_sent_monster_rev:
			_last_sent_monster_rev = m_rev
			snapshot["sea_monster"] = ai_director_ref.get_sea_monster_sync_dict()
		var w_rev: int = ai_director_ref.get_wanted_sync_revision()
		if send_full or w_rev != _last_sent_wanted_rev:
			_last_sent_wanted_rev = w_rev
			snapshot["wanted_level"] = ai_director_ref.wanted_level

	if world_map_ref != null:
		var wd_v: Variant = world_map_ref.get("wind_direction")
		var wd: Vector2 = wd_v if wd_v is Vector2 else Vector2.RIGHT
		var ws: float = snappedf(float(world_map_ref.get("wind_strength")), 0.01)
		var w_vec := Vector3(snappedf(wd.x, 0.01), snappedf(wd.y, 0.01), ws)
		if send_full or w_vec != _last_wind_vec:
			_last_wind_vec = w_vec
			snapshot["wind_x"] = w_vec.x
			snapshot["wind_y"] = w_vec.y
			snapshot["wind_strength"] = w_vec.z

		var cw: int = int(world_map_ref.get("current_weather"))
		var wi: float = snappedf(float(world_map_ref.get("weather_intensity")), 0.01)
		if send_full or cw != _last_weather_state or wi != _last_weather_int:
			_last_weather_state = cw
			_last_weather_int = wi
			snapshot["weather_state"] = cw
			snapshot["weather_intensity"] = wi

	if _peers_needing_full.is_empty():
		rpc("rpc_world_snapshot", snapshot)
	else:
		var full_snap: Dictionary = _build_readonly_full_snapshot(acks)
		for peer_id in multiplayer.get_peers():
			if _peers_needing_full.has(peer_id):
				rpc_id(peer_id, "rpc_world_snapshot", full_snap)
			else:
				rpc_id(peer_id, "rpc_world_snapshot", snapshot)
		_peers_needing_full.clear()


func _is_far_from_players(pos: Vector2, player_positions: Array[Vector2]) -> bool:
	if player_positions.is_empty():
		return false
	for p_pos in player_positions:
		if pos.distance_squared_to(p_pos) <= AOI_FULL_RATE_DIST_SQ:
			return false
	return true


func _build_readonly_full_snapshot(acks: Dictionary) -> Dictionary:
	var full_ships: Array = []
	var seen_ids: Dictionary = {}
	for s in all_ships_ref.values():
		if s != null and s.has_method("to_sync_dict"):
			var sid: int = int(s.get("ship_id"))
			if not seen_ids.has(sid):
				seen_ids[sid] = true
				full_ships.append(_build_ship_full_dict(s, sid))
	if ai_director_ref != null:
		for ai_s in ai_director_ref.ai_ships.values():
			if ai_s != null and ai_s.has_method("to_sync_dict"):
				var ai_sid: int = int(ai_s.get("ship_id"))
				if not seen_ids.has(ai_sid):
					seen_ids[ai_sid] = true
					full_ships.append(_build_ship_full_dict(ai_s, ai_sid))

	var snap: Dictionary = { "t": snappedf(_server_time, 0.001), "ships": full_ships }
	if not acks.is_empty():
		snap["acks"] = acks
	if loot_system_ref != null:
		snap["drops"] = loot_system_ref.to_sync_array()
	if combat_system_ref != null:
		snap["forts"] = combat_system_ref.get_fort_sync_array()
	if ai_director_ref != null:
		snap["sea_monster"] = ai_director_ref.get_sea_monster_sync_dict()
		snap["wanted_level"] = ai_director_ref.wanted_level
	if world_map_ref != null:
		var wd_v: Variant = world_map_ref.get("wind_direction")
		var wd: Vector2 = wd_v if wd_v is Vector2 else Vector2.RIGHT
		snap["wind_x"] = snappedf(wd.x, 0.01)
		snap["wind_y"] = snappedf(wd.y, 0.01)
		snap["wind_strength"] = snappedf(float(world_map_ref.get("wind_strength")), 0.01)
		snap["weather_state"] = int(world_map_ref.get("current_weather"))
		snap["weather_intensity"] = snappedf(float(world_map_ref.get("weather_intensity")), 0.01)
	return snap


func _build_ship_full_dict(s: Node, sid: int) -> Dictionary:
	var wp: Vector2 = s.get("world_pos")
	var vel: Vector2 = s.get("velocity")
	return {
		"ship_id": sid,
		"faction": int(s.get("faction")),
		"ship_name": str(s.get("ship_name")),
		"hull_tier": int(s.get("hull_tier")),
		"x": snappedf(wp.x, 0.05),
		"y": snappedf(wp.y, 0.05),
		"vx": snappedf(vel.x, 0.05),
		"vy": snappedf(vel.y, 0.05),
		"heading": snappedf(float(s.get("heading")), 0.01),
		"speed": snappedf(float(s.get("speed")), 0.05),
		"angular_velocity": snappedf(float(s.get("angular_velocity")), 0.01),
		"sail_state": int(s.get("sail_state")),
		"hp": snappedf(float(s.get("hp")), 0.1),
		"max_hp": snappedf(float(s.get("max_hp")), 0.1),
		"is_sunk": bool(s.get("is_sunk")),
		"current_harbor_index": int(s.get("current_harbor_index")),
		"chain_slow_timer": snappedf(float(s.get("chain_slow_timer")), 0.05),
		"burn_timer": snappedf(float(s.get("burn_timer")), 0.05)
	}


func _pack_ship_snapshot(s: Node, sid: int, send_full: bool, is_far_ai: bool = false) -> Dictionary:
	var cur: Dictionary = _build_ship_full_dict(s, sid)
	var prev: Variant = _last_sent_ships.get(sid, null)
	if send_full or not (prev is Dictionary):
		_last_sent_ships[sid] = cur
		return cur

	var pd: Dictionary = prev
	var meta_changed: bool = (
		pd["faction"] != cur["faction"] or pd["ship_name"] != cur["ship_name"]
		or pd["hull_tier"] != cur["hull_tier"] or pd["max_hp"] != cur["max_hp"]
		or pd["current_harbor_index"] != cur["current_harbor_index"]
	)
	if is_far_ai and (_snapshot_seq % 4 != 0) and not meta_changed and pd["hp"] == cur["hp"] and pd["is_sunk"] == cur["is_sunk"]:
		return { "ship_id": sid }
	var motion_changed: bool = (
		pd["x"] != cur["x"] or pd["y"] != cur["y"] or pd["vx"] != cur["vx"] or pd["vy"] != cur["vy"]
		or pd["heading"] != cur["heading"] or pd["speed"] != cur["speed"]
		or pd["angular_velocity"] != cur["angular_velocity"] or pd["sail_state"] != cur["sail_state"]
		or pd["hp"] != cur["hp"] or pd["is_sunk"] != cur["is_sunk"]
		or pd["chain_slow_timer"] != cur["chain_slow_timer"] or pd["burn_timer"] != cur["burn_timer"]
	)
	if not meta_changed and not motion_changed and absf(float(cur["speed"])) < 0.05 and absf(float(cur["angular_velocity"])) < 0.01:
		return { "ship_id": sid }

	_last_sent_ships[sid] = cur
	if meta_changed:
		return cur
	var delta_d := {
		"ship_id": sid, "x": cur["x"], "y": cur["y"], "vx": cur["vx"], "vy": cur["vy"],
		"heading": cur["heading"], "speed": cur["speed"], "angular_velocity": cur["angular_velocity"],
		"sail_state": cur["sail_state"], "hp": cur["hp"], "is_sunk": cur["is_sunk"]
	}
	if float(cur["chain_slow_timer"]) > 0.0 or float(pd["chain_slow_timer"]) > 0.0:
		delta_d["chain_slow_timer"] = cur["chain_slow_timer"]
	if float(cur["burn_timer"]) > 0.0 or float(pd["burn_timer"]) > 0.0:
		delta_d["burn_timer"] = cur["burn_timer"]
	return delta_d


func save_peer_account(peer_id: int) -> bool:
	if current_mode != Mode.SERVER:
		return false
	var acct_key: String = str(_peer_accounts.get(peer_id, ""))
	if acct_key.is_empty():
		return false
	var state: Dictionary = (_peer_save_states.get(peer_id, SaveStoreScript.create_default_save_data()) as Dictionary).duplicate(true)
	var ship: Node = all_ships_ref.get(peer_id, null)
	if ship != null and is_instance_valid(ship):
		var wp: Variant = ship.get("world_pos")
		if wp is Vector2:
			state["world_x"] = snappedf((wp as Vector2).x, 0.1)
			state["world_y"] = snappedf((wp as Vector2).y, 0.1)
			state["has_saved_pos"] = true
		state["heading"] = snappedf(float(ship.get("heading")), 0.001)
		state["hull_tier"] = clampi(int(ship.get("hull_tier")), Contracts.ShipClass.SLOOP, Contracts.ShipClass.WAR_GALLEON)
		var max_hp: float = maxf(10.0, float(ship.get("max_hp")))
		if bool(ship.get("is_sunk")) or float(ship.get("hp")) <= 0.0:
			state["hp"] = max_hp
			state["has_saved_pos"] = false
		else:
			state["hp"] = clampf(snappedf(float(ship.get("hp")), 0.1), 1.0, max_hp)
	_peer_save_states[peer_id] = state
	_dirty_save_peers.erase(peer_id)
	return _account_store.update_account_save(acct_key, state)


func save_all_connected_accounts() -> void:
	if current_mode != Mode.SERVER:
		return
	for pid_var in _peer_accounts.keys():
		save_peer_account(int(pid_var))


@rpc("any_peer", "reliable")
func rpc_authenticate(auth_mode: String, username: String, secret: String) -> void:
	if current_mode != Mode.SERVER:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var res: Dictionary
	match auth_mode:
		"register":
			res = _account_store.register_account(username, secret)
		"login":
			res = _account_store.login_account(username, secret)
		"token":
			res = _account_store.login_with_token(username, secret)
		_:
			res = { "ok": false, "error": "Unbekannter Anmeldemodus.", "clear_token": false }

	if not bool(res.get("ok", false)):
		rpc_id(sender_id, "rpc_auth_failed", str(res.get("error", "Anmeldung fehlgeschlagen.")), bool(res.get("clear_token", false)))
		return

	var clean_name: String = str(res["username"])
	var acct_key: String = str(res["username_key"])
	var session_token: String = str(res["session_token"])
	var save_data: Dictionary = SaveStoreScript.sanitize_save_data(res.get("save_data", {}))

	# Replace stale connection if same account reconnects (e.g. browser refresh)
	if _account_peers.has(acct_key):
		var old_pid: int = int(_account_peers[acct_key])
		if old_pid != sender_id:
			save_peer_account(old_pid)
			_peer_accounts.erase(old_pid)
			_peer_save_states.erase(old_pid)
			_dirty_save_peers.erase(old_pid)
			_peer_names.erase(old_pid)
			_last_sent_ships.erase(old_pid)
			_peers_needing_full.erase(old_pid)
			peer_ship_left.emit(old_pid)
			if multiplayer.multiplayer_peer != null and old_pid > 1:
				multiplayer.multiplayer_peer.disconnect_peer(old_pid, true)

	_peer_accounts[sender_id] = acct_key
	_account_peers[acct_key] = sender_id
	_peer_save_states[sender_id] = save_data.duplicate(true)
	_peer_names[sender_id] = clean_name
	_peers_needing_full[sender_id] = true
	_sync_accum = SYNC_INTERVAL

	peer_ship_joined_with_save.emit(sender_id, clean_name, save_data)
	rpc_id(sender_id, "rpc_welcome_client_account", sender_id, world_seed, clean_name, session_token, save_data)


@rpc("authority", "reliable")
func rpc_auth_failed(reason: String, clear_saved_auth: bool = false) -> void:
	if current_mode != Mode.CLIENT:
		return
	shutdown()
	auth_failed.emit(reason, clear_saved_auth)


@rpc("authority", "reliable")
func rpc_welcome_client_account(assigned_ship_id: int, server_seed: int, display_name: String, session_token: String, save_data: Dictionary) -> void:
	if current_mode != Mode.CLIENT:
		return
	local_peer_id = assigned_ship_id
	world_seed = server_seed
	local_captain_name = display_name
	local_session_token = session_token
	local_auth_mode = "token"
	local_auth_secret = session_token
	_host_runner.last_captain_name = display_name
	_host_runner.last_auth_mode = "token"
	_host_runner.last_auth_secret = session_token
	local_saved_profile = SaveStoreScript.sanitize_save_data(save_data)
	client_joined_with_save.emit(assigned_ship_id, server_seed, display_name, session_token, local_saved_profile)
	client_joined.emit(assigned_ship_id, server_seed)


@rpc("any_peer", "reliable")
func rpc_sync_player_save_state(profile_state: Dictionary) -> void:
	if current_mode != Mode.SERVER:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if not _peer_accounts.has(sender_id):
		return
	var cur: Dictionary = _peer_save_states.get(sender_id, SaveStoreScript.create_default_save_data())
	var merged: Dictionary = cur.duplicate(true)
	for key in ["gold", "hull_tier", "owned_ship_tiers", "grid", "active_quests"]:
		if profile_state.has(key):
			merged[key] = profile_state[key]
	_peer_save_states[sender_id] = SaveStoreScript.sanitize_save_data(merged)
	_dirty_save_peers[sender_id] = true


@rpc("any_peer", "reliable")
func rpc_join_world(captain_name: String) -> void:
	if current_mode != Mode.SERVER:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var clean_name: String = captain_name.strip_edges().left(24)
	if clean_name.is_empty():
		clean_name = "Pirat #%d" % sender_id
	_peer_names[sender_id] = clean_name
	_peers_needing_full[sender_id] = true
	_sync_accum = SYNC_INTERVAL
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
func rpc_send_input(steer_input: float, sail_state: int, input_seq: int = 0) -> void:
	if current_mode != Mode.SERVER:
		return
	var ship: Node = all_ships_ref.get(multiplayer.get_remote_sender_id(), null)
	if ship == null:
		return
	if input_seq > int(ship.get_meta("last_input_seq", 0)):
		ship.set_meta("last_input_seq", input_seq)
	ship.set_meta("net_steer", clampf(steer_input, -1.0, 1.0))
	if ship.has_method("set_sail_state"):
		ship.call("set_sail_state", clampi(sail_state, Contracts.SailState.ANCHORED, Contracts.SailState.FULL_SAIL))


@rpc("any_peer", "reliable")
func rpc_request_fire(is_starboard: bool) -> void:
	if current_mode == Mode.SERVER and combat_system_ref != null:
		combat_system_ref.fire_broadside(multiplayer.get_remote_sender_id(), is_starboard)


@rpc("any_peer", "reliable")
func rpc_request_fire_bow() -> void:
	if current_mode == Mode.SERVER and combat_system_ref != null and combat_system_ref.has_method("fire_bow"):
		combat_system_ref.call("fire_bow", multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func rpc_set_harbor_ui_open(is_open: bool) -> void:
	if current_mode != Mode.SERVER:
		return
	var ship: Node = all_ships_ref.get(multiplayer.get_remote_sender_id(), null)
	if ship != null:
		ship.set_meta("harbor_ui_open", is_open)


@rpc("any_peer", "reliable")
func rpc_request_bounty_spawn(target_pos: Vector2, boss_name: String, hull_tier: int = Contracts.ShipClass.BRIGANTINE, quest_id: String = "") -> void:
	if current_mode != Mode.SERVER or ai_director_ref == null:
		return
	var clean_name: String = boss_name.strip_edges().left(32)
	var clamped_tier: int = clampi(hull_tier, Contracts.ShipClass.SLOOP, Contracts.ShipClass.WAR_GALLEON)
	var spawned_id: int = ai_director_ref.spawn_ai_ship(Contracts.ShipFaction.PIRATE, target_pos, true, clean_name, clamped_tier, false)
	if spawned_id > 0:
		rpc_id(multiplayer.get_remote_sender_id(), "rpc_client_bounty_spawned", quest_id, spawned_id)


@rpc("authority", "reliable")
func rpc_client_bounty_spawned(quest_id: String, ship_id: int) -> void:
	if current_mode == Mode.CLIENT:
		bounty_spawned.emit(quest_id, ship_id)


@rpc("any_peer", "reliable")
func rpc_request_salvage_spawn(target_pos: Vector2, quest_id: String) -> void:
	if current_mode != Mode.SERVER or loot_system_ref == null:
		return
	var drop: Contracts.LootDropData = loot_system_ref.spawn_salvage_target(target_pos, quest_id)
	if drop != null:
		rpc_id(multiplayer.get_remote_sender_id(), "rpc_client_salvage_spawned", quest_id, drop.drop_id, drop.world_pos)


@rpc("authority", "reliable")
func rpc_client_salvage_spawned(quest_id: String, drop_id: int, world_pos: Vector2) -> void:
	if current_mode == Mode.CLIENT:
		salvage_spawned.emit(quest_id, drop_id, world_pos)


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
	var ship: Node = all_ships_ref.get(multiplayer.get_remote_sender_id(), null)
	if ship != null and ship.has_method("upgrade_ship_class"):
		ship.call("upgrade_ship_class", clampi(new_hull_tier, Contracts.ShipClass.SLOOP, Contracts.ShipClass.WAR_GALLEON))


@rpc("any_peer", "reliable")
func rpc_repair_ship(new_hp: float) -> void:
	if current_mode != Mode.SERVER:
		return
	var ship: Node = all_ships_ref.get(multiplayer.get_remote_sender_id(), null)
	if ship != null and not bool(ship.get("is_sunk")):
		ship.set("hp", clampf(new_hp, 1.0, float(ship.get("max_hp"))))


@rpc("authority", "unreliable_ordered")
func rpc_world_snapshot(snapshot: Dictionary) -> void:
	if current_mode == Mode.CLIENT:
		snapshot_received.emit(snapshot)


@rpc("authority", "unreliable")
func rpc_client_broadside_fired(ship_id: int, is_starboard: bool, origin: Vector2, dir: Vector2) -> void:
	if current_mode == Mode.CLIENT and _bus() != null:
		_bus().broadside_fired.emit(ship_id, is_starboard, origin, dir, [])


@rpc("authority", "unreliable")
func rpc_client_cannonball_spawned(shot_data: Dictionary) -> void:
	if current_mode == Mode.CLIENT and _bus() != null:
		_bus().cannonball_spawned.emit(shot_data)


@rpc("authority", "unreliable")
func rpc_client_cannonball_impact(world_pos: Vector2, hit_ship_id: int, damage: float, is_water_splash: bool, is_powder_crit: bool) -> void:
	if current_mode == Mode.CLIENT and _bus() != null:
		_bus().cannonball_impact.emit(world_pos, hit_ship_id, damage, is_water_splash, is_powder_crit)


@rpc("authority", "unreliable")
func rpc_client_cannonball_batch(shots: Array) -> void:
	if current_mode != Mode.CLIENT:
		return
	var bus := _bus()
	if bus == null:
		return
	for shot_var in shots:
		if shot_var is Dictionary:
			bus.cannonball_spawned.emit(shot_var)


@rpc("authority", "unreliable")
func rpc_client_cannonball_impacts(impacts: Array) -> void:
	if current_mode != Mode.CLIENT:
		return
	var bus := _bus()
	if bus == null:
		return
	for imp_var in impacts:
		if imp_var is Array and (imp_var as Array).size() >= 5:
			var imp: Array = imp_var
			bus.cannonball_impact.emit(imp[0], int(imp[1]), float(imp[2]), bool(imp[3]), bool(imp[4]))


@rpc("authority", "reliable")
func rpc_client_ship_sunk(ship_id: int, world_pos: Vector2, faction: int, killer_ship_id: int) -> void:
	if current_mode == Mode.CLIENT and _bus() != null:
		_bus().ship_sunk.emit(ship_id, world_pos, faction, killer_ship_id)


@rpc("authority", "reliable")
func rpc_client_player_death_penalty(ship_id: int, gold_lost: int, respawn_sec: float) -> void:
	if current_mode == Mode.CLIENT and _bus() != null:
		_bus().player_death_penalty.emit(ship_id, gold_lost, respawn_sec)


func _on_server_loot_collected(drop_id: int, collector_ship_id: int, loot_data: Contracts.LootDropData) -> void:
	if current_mode != Mode.SERVER or multiplayer.get_peers().is_empty():
		return
	var full_dict: Dictionary = loot_data.to_dict() if loot_data != null else {}
	var public_dict: Dictionary = {}
	if loot_data != null:
		public_dict = {
			"drop_id": drop_id,
			"x": loot_data.world_pos.x,
			"y": loot_data.world_pos.y
		}
	for peer_id in multiplayer.get_peers():
		if peer_id == collector_ship_id:
			rpc_id(peer_id, "rpc_client_loot_collected", drop_id, collector_ship_id, full_dict)
		else:
			rpc_id(peer_id, "rpc_client_loot_collected", drop_id, collector_ship_id, public_dict)


@rpc("authority", "reliable")
func rpc_client_loot_collected(drop_id: int, collector_ship_id: int, drop_dict: Dictionary = {}) -> void:
	if current_mode != Mode.CLIENT:
		return
	if loot_system_ref != null:
		loot_system_ref.mark_drop_collected_remote(drop_id)
	var bus := _bus()
	if bus == null:
		return
	if collector_ship_id == local_peer_id:
		var drop: Contracts.LootDropData = Contracts.LootDropData.from_dict(drop_dict) if not drop_dict.is_empty() else Contracts.LootDropData.new()
		drop.drop_id = drop_id
		if drop_dict.is_empty():
			drop.gold = 0
		bus.loot_collected.emit(drop_id, collector_ship_id, drop)
	else:
		var other_drop: Contracts.LootDropData = null
		if not drop_dict.is_empty():
			other_drop = Contracts.LootDropData.new()
			other_drop.drop_id = drop_id
			other_drop.world_pos = Vector2(float(drop_dict.get("x", 0.0)), float(drop_dict.get("y", 0.0)))
			other_drop.gold = 0
		bus.loot_collected.emit(drop_id, collector_ship_id, other_drop)


@rpc("authority", "reliable")
func rpc_client_weather_changed(weather_state: int, intensity: float) -> void:
	if current_mode == Mode.CLIENT and _bus() != null:
		_bus().weather_changed.emit(weather_state, intensity)


@rpc("authority", "reliable")
func rpc_client_wanted_level_changed(new_level: int) -> void:
	if current_mode == Mode.CLIENT and _bus() != null:
		_bus().wanted_level_changed.emit(new_level)


@rpc("authority", "unreliable")
func rpc_client_fort_damaged(fort_id: int, hp: float, max_hp: float, world_pos: Vector2) -> void:
	if current_mode == Mode.CLIENT and _bus() != null:
		_bus().fort_damaged.emit(fort_id, hp, max_hp, world_pos)


@rpc("authority", "reliable")
func rpc_client_fort_destroyed(fort_id: int, world_pos: Vector2) -> void:
	if current_mode == Mode.CLIENT and _bus() != null:
		_bus().fort_destroyed.emit(fort_id, world_pos)


@rpc("authority", "reliable")
func rpc_client_sea_monster_spawned(monster_id: int, world_pos: Vector2, max_hp: float) -> void:
	if current_mode == Mode.CLIENT and _bus() != null:
		_bus().sea_monster_spawned.emit(monster_id, world_pos, max_hp)


@rpc("authority", "reliable")
func rpc_client_sea_monster_defeated(monster_id: int, world_pos: Vector2) -> void:
	if current_mode == Mode.CLIENT and _bus() != null:
		_bus().sea_monster_defeated.emit(monster_id, world_pos)

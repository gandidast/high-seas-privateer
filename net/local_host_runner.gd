class_name LocalHostRunner
extends RefCounted
## Handles local TCP port probing, automatic headless server process spawning,
## connection timeout/retry FSM, and profile reconnect state for NetworkManager.

const ServerConfigScript := preload("res://net/server_config.gd")

const LOCAL_PROBE_TIMEOUT_SEC: float = 0.6
const SERVER_BOOT_WAIT_SEC: float = 0.8
const CLIENT_CONNECT_TIMEOUT_SEC: float = 40.0
const MAX_BOOT_CONNECT_RETRIES: int = 3

enum AutoStartState {
	IDLE = 0,
	PROBING = 1,
	WAITING_FOR_BOOT = 2,
	CONNECTING_AFTER_BOOT = 3
}

var auto_state: int = AutoStartState.IDLE
var last_target_url: String = ""
var last_captain_name: String = "Käpt'n"

var _tcp_probe: StreamPeerTCP = null
var _state_timer: float = 0.0
var _connect_timeout_timer: float = 0.0
var _pending_url: String = ""
var _pending_captain_name: String = "Käpt'n"
var _pending_port: int = Contracts.SERVER_DEFAULT_PORT
var _autostart_attempted: bool = false
var _connect_retries: int = 0
var _local_server_pid: int = -1


func reset() -> void:
	auto_state = AutoStartState.IDLE
	_state_timer = 0.0
	_connect_timeout_timer = 0.0
	close_probe()


func close_probe() -> void:
	if _tcp_probe != null:
		_tcp_probe.disconnect_from_host()
		_tcp_probe = null


func on_connected() -> void:
	auto_state = AutoStartState.IDLE
	_state_timer = 0.0
	_connect_timeout_timer = 0.0


func begin_connect_or_autostart(url: String, captain_name: String, nm: NetworkManager) -> void:
	var raw_url: String = url.strip_edges()
	var used_placeholder: bool = false
	if ServerConfigScript.is_placeholder_url(raw_url):
		raw_url = ServerConfigScript.LOCAL_SERVER_URL
		used_placeholder = true

	_pending_url = NetworkManager.normalize_ws_url(raw_url)
	_pending_captain_name = captain_name.strip_edges()
	if _pending_captain_name.is_empty():
		_pending_captain_name = "Freibeuter"
	_pending_port = NetworkManager.extract_port_from_url(_pending_url, Contracts.SERVER_DEFAULT_PORT)
	_autostart_attempted = false
	_connect_retries = 0
	last_target_url = _pending_url
	last_captain_name = _pending_captain_name

	if NetworkManager.is_local_url(_pending_url) and not OS.has_feature("web"):
		_tcp_probe = StreamPeerTCP.new()
		if _tcp_probe.connect_to_host("127.0.0.1", _pending_port) != OK:
			close_probe()
			_begin_local_server_autostart(nm)
			return
		auto_state = AutoStartState.PROBING
		_state_timer = 0.0
		if used_placeholder:
			nm.connection_status_changed.emit("Platzhalter erkannt – weiche auf %s aus (prüfe Port %d)..." % [_pending_url, _pending_port])
		else:
			nm.connection_status_changed.emit("Prüfe lokalen One-World Server auf Port %d..." % _pending_port)
	else:
		if used_placeholder:
			nm.connection_status_changed.emit("Platzhalter erkannt – verbinde mit %s ..." % _pending_url)
		elif _pending_url.contains("hf.space"):
			nm.connection_status_changed.emit("Verbinde mit Hugging Face One-World (%s)..." % _pending_url)
		elif _pending_url.contains("onrender.com"):
			nm.connection_status_changed.emit("Verbinde mit One-World (%s – Render Free Tier wacht ggf. ~25s auf)..." % _pending_url)
		else:
			nm.connection_status_changed.emit("Verbinde mit One-World (%s)..." % _pending_url)
		_connect_timeout_timer = CLIENT_CONNECT_TIMEOUT_SEC
		var err: int = nm.start_client(_pending_url, _pending_captain_name)
		if err != OK:
			_connect_timeout_timer = 0.0
			nm.client_disconnected_from_server.emit("Verbindungsfehler zu %s (Code %d)." % [_pending_url, err])


func tick(delta: float, is_client_mode: bool, mp: MultiplayerAPI, nm: NetworkManager) -> void:
	if auto_state == AutoStartState.IDLE:
		if is_client_mode and _connect_timeout_timer > 0.0:
			if mp.multiplayer_peer != null and mp.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
				_connect_timeout_timer -= delta
				if _connect_timeout_timer <= 0.0:
					_connect_timeout_timer = 0.0
					on_connection_timeout(nm)
			else:
				_connect_timeout_timer = 0.0
		return

	_state_timer += delta
	if auto_state == AutoStartState.PROBING:
		if _tcp_probe != null:
			_tcp_probe.poll()
			var st: int = _tcp_probe.get_status()
			if st == StreamPeerTCP.STATUS_CONNECTED:
				close_probe()
				auto_state = AutoStartState.IDLE
				nm.connection_status_changed.emit("Lokaler Server gefunden – verbinde mit One-World...")
				_connect_timeout_timer = CLIENT_CONNECT_TIMEOUT_SEC
				nm.start_client(_pending_url, _pending_captain_name)
				return
			elif st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
				close_probe()
				_begin_local_server_autostart(nm)
				return
		if _state_timer >= LOCAL_PROBE_TIMEOUT_SEC:
			close_probe()
			_begin_local_server_autostart(nm)
	elif auto_state == AutoStartState.WAITING_FOR_BOOT:
		if _state_timer >= SERVER_BOOT_WAIT_SEC:
			auto_state = AutoStartState.CONNECTING_AFTER_BOOT
			_state_timer = 0.0
			nm.connection_status_changed.emit("Verbinde mit lokalem One-World Server (Port %d)..." % _pending_port)
			_connect_timeout_timer = CLIENT_CONNECT_TIMEOUT_SEC
			if nm.start_client(_pending_url, _pending_captain_name) != OK:
				on_connection_failed(nm)
	elif auto_state == AutoStartState.CONNECTING_AFTER_BOOT and _connect_timeout_timer > 0.0:
		if mp.multiplayer_peer != null and mp.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
			_connect_timeout_timer -= delta
			if _connect_timeout_timer <= 0.0:
				_connect_timeout_timer = 0.0
				on_connection_failed(nm)
		else:
			_connect_timeout_timer = 0.0


func on_connection_timeout(nm: NetworkManager) -> void:
	if not _autostart_attempted and not _pending_url.is_empty() and NetworkManager.is_local_url(_pending_url) and not OS.has_feature("web"):
		nm.close_peer_only()
		_begin_local_server_autostart(nm)
		return
	var timed_out_url: String = _pending_url if not _pending_url.is_empty() else "One-World Server"
	nm.shutdown()
	nm.client_disconnected_from_server.emit("Zeitüberschreitung (Timeout): %s antwortet nicht." % timed_out_url)


func on_connection_failed(nm: NetworkManager) -> void:
	_connect_timeout_timer = 0.0
	if auto_state == AutoStartState.CONNECTING_AFTER_BOOT and _connect_retries < MAX_BOOT_CONNECT_RETRIES:
		_connect_retries += 1
		nm.close_peer_only()
		auto_state = AutoStartState.WAITING_FOR_BOOT
		_state_timer = 0.2
		nm.connection_status_changed.emit("Lokaler Server startet noch (Versuch %d/%d)..." % [_connect_retries, MAX_BOOT_CONNECT_RETRIES])
		return
	if not _autostart_attempted and not _pending_url.is_empty() and NetworkManager.is_local_url(_pending_url) and not OS.has_feature("web"):
		nm.close_peer_only()
		_begin_local_server_autostart(nm)
		return
	var failed_url: String = _pending_url if not _pending_url.is_empty() else "Server"
	nm.shutdown()
	nm.client_disconnected_from_server.emit("Verbindung zu %s fehlgeschlagen." % failed_url)


func _begin_local_server_autostart(nm: NetworkManager) -> void:
	if _autostart_attempted:
		return
	_autostart_attempted = true
	nm.connection_status_changed.emit("Kein Server auf Port %d – starte lokalen One-World Server..." % _pending_port)
	var pid: int = spawn_local_headless_server(_pending_port, nm.world_seed)
	if pid <= 0:
		auto_state = AutoStartState.IDLE
		nm.client_disconnected_from_server.emit("Lokaler Headless-Server konnte nicht gestartet werden.")
		return
	_local_server_pid = pid
	auto_state = AutoStartState.WAITING_FOR_BOOT
	_state_timer = 0.0


static func spawn_local_headless_server(port: int = Contracts.SERVER_DEFAULT_PORT, p_seed: int = Contracts.DEFAULT_WORLD_SEED) -> int:
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

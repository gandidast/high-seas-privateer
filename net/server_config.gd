class_name ServerConfig
extends RefCounted
## Central server & player profile configuration for High Seas Pixel Privateer.
## Supports 24/7 Oracle Cloud (sslip.io wss://), Render.com, Hugging Face, local localhost fallback,
## HTML5 URL query parameters (?server=wss://...), and persistent captain profile.

const DEFAULT_SERVER_URL := "wss://92.5.97.143.nip.io"
const LOCAL_SERVER_URL := "ws://localhost:8080"
const PROFILE_PATH := "user://player_profile.cfg"
const DEPRECATED_DEFAULT_URLS := [
	"wss://92.5.97.143.sslip.io",
	"wss://high-seas-privateer.onrender.com",
	"wss://fabsipapi-high-seas-privateer.hf.space",
	"wss://DEINE-ORACLE-IP.sslip.io"
]


static func get_initial_server_url() -> String:
	# 1. Check command-line override (--server-url=wss://...)
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--server-url="):
			var cli_url: String = arg.trim_prefix("--server-url=").strip_edges()
			if not cli_url.is_empty():
				return cli_url

	# 2. In Web (HTML5) builds, inspect ?server=wss://... URL query parameter first
	if OS.has_feature("web") and ClassDB.class_exists("JavaScriptBridge"):
		var js_code := "(function(){ try { var p = new URLSearchParams(window.location.search); return p.get('server') || ''; } catch(e){ return ''; } })()"
		var param_val: Variant = JavaScriptBridge.eval(js_code, true)
		var param_str: String = str(param_val).strip_edges()
		if not param_str.is_empty():
			return param_str

	# 3. Check if player saved a custom server URL in user://player_profile.cfg
	var saved_url: String = load_saved_server_url()
	if not saved_url.is_empty():
		return saved_url

	return DEFAULT_SERVER_URL


static func is_placeholder_url(url: String) -> bool:
	return url.contains("DEINE-ORACLE-IP") or url.strip_edges().is_empty()


static func get_effective_connect_url(raw_url: String) -> String:
	var trimmed: String = raw_url.strip_edges()
	if is_placeholder_url(trimmed):
		return LOCAL_SERVER_URL
	return trimmed


static func load_captain_name(default_name: String = "Käpt'n Rotbart") -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		var name_val: String = str(cfg.get_value("profile", "captain_name", default_name)).strip_edges()
		if not name_val.is_empty():
			return name_val
	return default_name


static func load_saved_server_url() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		var saved: String = str(cfg.get_value("profile", "last_server_url", "")).strip_edges()
		if saved in DEPRECATED_DEFAULT_URLS:
			return ""
		return saved
	return ""


static func save_profile(captain_name: String, server_url: String = "") -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE_PATH)
	if not captain_name.strip_edges().is_empty():
		cfg.set_value("profile", "captain_name", captain_name.strip_edges())
	if not server_url.strip_edges().is_empty():
		cfg.set_value("profile", "last_server_url", server_url.strip_edges())
	cfg.save(PROFILE_PATH)


static func normalize_server_key(url: String) -> String:
	var effective: String = get_effective_connect_url(url).strip_edges().to_lower()
	if effective.begins_with("https://"):
		effective = "wss://" + effective.substr(8)
	elif effective.begins_with("http://"):
		effective = "ws://" + effective.substr(7)
	elif not effective.begins_with("ws://") and not effective.begins_with("wss://"):
		effective = "ws://" + effective
	while effective.ends_with("/"):
		effective = effective.left(effective.length() - 1)
	return effective


static func load_mp_username() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		return str(cfg.get_value("auth", "mp_username", "")).strip_edges()
	return ""


static func load_mp_session_token() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		return str(cfg.get_value("auth", "mp_session_token", "")).strip_edges()
	return ""


static func load_mp_auth_server() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		return str(cfg.get_value("auth", "mp_auth_server", "")).strip_edges()
	return ""


static func has_mp_auth_for_url(url: String) -> bool:
	var u: String = load_mp_username()
	var tok: String = load_mp_session_token()
	if u.is_empty() or tok.is_empty():
		return false
	var saved_srv: String = load_mp_auth_server()
	return not saved_srv.is_empty() and saved_srv == normalize_server_key(url)


static func save_mp_auth(username: String, session_token: String, server_url: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE_PATH)
	var clean_user: String = username.strip_edges()
	cfg.set_value("auth", "mp_username", clean_user)
	cfg.set_value("auth", "mp_session_token", session_token.strip_edges())
	cfg.set_value("auth", "mp_auth_server", normalize_server_key(server_url))
	if not clean_user.is_empty():
		cfg.set_value("profile", "captain_name", clean_user)
	if not server_url.strip_edges().is_empty():
		cfg.set_value("profile", "last_server_url", server_url.strip_edges())
	cfg.save(PROFILE_PATH)


static func clear_mp_auth(keep_username: bool = true) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) != OK:
		return
	if not keep_username:
		cfg.set_value("auth", "mp_username", "")
	cfg.set_value("auth", "mp_session_token", "")
	cfg.set_value("auth", "mp_auth_server", "")
	cfg.save(PROFILE_PATH)


static func load_local_username() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		return str(cfg.get_value("local_auth", "username", "")).strip_edges()
	return ""


static func load_local_session_token() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		return str(cfg.get_value("local_auth", "session_token", "")).strip_edges()
	return ""


static func has_local_auth() -> bool:
	return not load_local_username().is_empty() and not load_local_session_token().is_empty()


static func save_local_auth(username: String, session_token: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE_PATH)
	var clean_user: String = username.strip_edges()
	cfg.set_value("local_auth", "username", clean_user)
	cfg.set_value("local_auth", "session_token", session_token.strip_edges())
	if not clean_user.is_empty():
		cfg.set_value("profile", "captain_name", clean_user)
	cfg.save(PROFILE_PATH)


static func clear_local_auth(keep_username: bool = true) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) != OK:
		return
	if not keep_username:
		cfg.set_value("local_auth", "username", "")
	cfg.set_value("local_auth", "session_token", "")
	cfg.save(PROFILE_PATH)

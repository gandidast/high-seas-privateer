class_name ServerConfig
extends RefCounted
## Central server & player profile configuration for High Seas Pixel Privateer.
## Supports Render.com (wss://), Hugging Face Docker Spaces, Oracle Cloud, local localhost fallback,
## HTML5 URL query parameters (?server=wss://...), and persistent captain profile.

const DEFAULT_SERVER_URL := "wss://high-seas-privateer.onrender.com"
const LOCAL_SERVER_URL := "ws://localhost:8080"
const PROFILE_PATH := "user://player_profile.cfg"
const DEPRECATED_DEFAULT_URLS := [
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

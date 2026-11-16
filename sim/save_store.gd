class_name SaveStore
extends RefCounted
## Persistent user account authentication & player progression save store.
## Server accounts live in `PIRATE_DATA_DIR` / `--data-dir` / `user://server_accounts`
## (surviving GitHub Pages static web client reloads & server restarts).
## Local Solo progression lives in `user://solo_save.json`.

const DEFAULT_GOLD: int = 120
const DEFAULT_ACCOUNTS_DIR: String = "user://server_accounts"
const DEFAULT_LOCAL_ACCOUNTS_DIR: String = "user://local_accounts"
const DEFAULT_SOLO_SAVE_PATH: String = "user://solo_save.json"
const MAX_ACTIVE_QUESTS: int = 12
const SAVE_SCHEMA_VERSION: int = 1
const FORBIDDEN_USER_CHARS := ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]

var _data_dir_override: String = ""
var _solo_path_override: String = ""


func _init(p_data_dir: String = "", p_solo_path: String = "") -> void:
	_data_dir_override = p_data_dir.strip_edges()
	_solo_path_override = p_solo_path.strip_edges()


func get_accounts_dir() -> String:
	var dir_path: String = _data_dir_override
	if dir_path.is_empty():
		for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
			if arg.begins_with("--data-dir="):
				dir_path = arg.trim_prefix("--data-dir=").strip_edges()
				break
	if dir_path.is_empty():
		dir_path = OS.get_environment("PIRATE_DATA_DIR").strip_edges()
	if dir_path.is_empty():
		dir_path = DEFAULT_ACCOUNTS_DIR
	_ensure_dir_exists(dir_path)
	return dir_path


func get_solo_save_path() -> String:
	return DEFAULT_SOLO_SAVE_PATH if _solo_path_override.is_empty() else _solo_path_override


static func _ensure_dir_exists(dir_path: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path(dir_path) if dir_path.begins_with("user://") or dir_path.begins_with("res://") else dir_path
	if not abs_path.is_empty():
		DirAccess.make_dir_recursive_absolute(abs_path)


static func validate_username(raw: String) -> Dictionary:
	var clean: String = raw.strip_edges()
	if clean.length() < 3:
		return { "ok": false, "clean": clean, "key": "", "error": "Benutzername muss mindestens 3 Zeichen lang sein." }
	if clean.length() > 20:
		clean = clean.left(20).strip_edges()
		if clean.length() < 3:
			return { "ok": false, "clean": clean, "key": "", "error": "Benutzername muss mindestens 3 Zeichen lang sein." }
	for ch in FORBIDDEN_USER_CHARS:
		if clean.contains(ch):
			return { "ok": false, "clean": clean, "key": "", "error": "Benutzername enthält unzulässige Zeichen (%s)." % ch }
	for i in range(clean.length()):
		if clean.unicode_at(i) < 32:
			return { "ok": false, "clean": clean, "key": "", "error": "Benutzername enthält ungültige Steuerzeichen." }
	return { "ok": true, "clean": clean, "key": clean.to_lower(), "error": "" }


static func validate_password(raw: String) -> Dictionary:
	if raw.length() < 3:
		return { "ok": false, "error": "Passwort muss mindestens 3 Zeichen lang sein." }
	if raw.length() > 64:
		return { "ok": false, "error": "Passwort darf maximal 64 Zeichen lang sein." }
	return { "ok": true, "error": "" }


static func generate_hex_token(num_bytes: int = 16) -> String:
	var crypto := Crypto.new()
	var bytes: PackedByteArray = crypto.generate_random_bytes(num_bytes)
	if bytes.size() == num_bytes:
		return bytes.hex_encode()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out: String = ""
	for _i in range(num_bytes):
		out += "%02x" % rng.randi_range(0, 255)
	return out


static func hash_password(password: String, salt: String) -> String:
	return ("%s::pirate_auth_v1::%s" % [salt, password]).sha256_text()


static func create_default_save_data() -> Dictionary:
	return {
		"version": SAVE_SCHEMA_VERSION,
		"gold": DEFAULT_GOLD,
		"hull_tier": Contracts.ShipClass.SLOOP,
		"owned_ship_tiers": [Contracts.ShipClass.SLOOP],
		"hp": 120.0,
		"world_x": 0.0,
		"world_y": 0.0,
		"heading": -0.35,
		"has_saved_pos": false,
		"grid": {},
		"active_quests": []
	}


static func sanitize_save_data(raw_var: Variant) -> Dictionary:
	var base: Dictionary = create_default_save_data()
	if not (raw_var is Dictionary):
		return base
	var raw: Dictionary = raw_var
	base["version"] = SAVE_SCHEMA_VERSION
	base["gold"] = maxi(0, int(raw.get("gold", DEFAULT_GOLD)))
	var tier: int = clampi(int(raw.get("hull_tier", Contracts.ShipClass.SLOOP)), Contracts.ShipClass.SLOOP, Contracts.ShipClass.WAR_GALLEON)
	base["hull_tier"] = tier

	var tiers_map: Dictionary = { Contracts.ShipClass.SLOOP: true, tier: true }
	var raw_tiers: Variant = raw.get("owned_ship_tiers", [])
	if raw_tiers is Array:
		for t_var in raw_tiers:
			var t_val: int = clampi(int(t_var), Contracts.ShipClass.SLOOP, Contracts.ShipClass.WAR_GALLEON)
			tiers_map[t_val] = true
	var tiers_arr: Array = []
	for k in tiers_map.keys():
		tiers_arr.append(int(k))
	tiers_arr.sort()
	base["owned_ship_tiers"] = tiers_arr

	base["hp"] = maxf(0.0, float(raw.get("hp", 120.0)))
	base["world_x"] = clampf(float(raw.get("world_x", 0.0)), -Contracts.WORLD_HALF_EXTENT, Contracts.WORLD_HALF_EXTENT)
	base["world_y"] = clampf(float(raw.get("world_y", 0.0)), -Contracts.WORLD_HALF_EXTENT, Contracts.WORLD_HALF_EXTENT)
	base["heading"] = wrapf(float(raw.get("heading", -0.35)), -PI, PI)
	base["has_saved_pos"] = bool(raw.get("has_saved_pos", false))

	var raw_grid: Variant = raw.get("grid", {})
	if raw_grid is Dictionary:
		base["grid"] = (raw_grid as Dictionary).duplicate(true)

	var clean_quests: Array = []
	var raw_quests: Variant = raw.get("active_quests", [])
	if raw_quests is Array:
		for q_var in raw_quests:
			if q_var is Dictionary and clean_quests.size() < MAX_ACTIVE_QUESTS:
				clean_quests.append((q_var as Dictionary).duplicate(true))
	base["active_quests"] = clean_quests
	return base


func _account_file_path(username_key: String) -> String:
	var hash_id: String = username_key.sha256_text().left(24)
	return get_accounts_dir().path_join("acct_%s.json" % hash_id)


func has_account(username: String) -> bool:
	var v: Dictionary = validate_username(username)
	if not bool(v["ok"]):
		return false
	return FileAccess.file_exists(_account_file_path(str(v["key"])))


func load_account_record(username_key: String) -> Dictionary:
	var path: String = _account_file_path(username_key.strip_edges().to_lower())
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = _read_json_dict(path)
	if not (parsed is Dictionary):
		return {}
	var rec: Dictionary = parsed
	if str(rec.get("username_key", "")) != username_key.strip_edges().to_lower():
		return {}
	return rec


func _write_account_record(username_key: String, record: Dictionary) -> bool:
	var path: String = _account_file_path(username_key)
	return _write_json_dict(path, record)


func register_account(username: String, password: String) -> Dictionary:
	var uv: Dictionary = validate_username(username)
	if not bool(uv["ok"]):
		return { "ok": false, "error": str(uv["error"]), "clear_token": false }
	var pv: Dictionary = validate_password(password)
	if not bool(pv["ok"]):
		return { "ok": false, "error": str(pv["error"]), "clear_token": false }

	var clean_name: String = str(uv["clean"])
	var key: String = str(uv["key"])
	if not load_account_record(key).is_empty():
		return { "ok": false, "error": "Benutzername '%s' existiert bereits. Bitte anmelden." % clean_name, "clear_token": false }

	var salt: String = generate_hex_token(12)
	var token: String = generate_hex_token(24)
	var now_ts: int = int(Time.get_unix_time_from_system())
	var save_data: Dictionary = create_default_save_data()
	var record := {
		"version": SAVE_SCHEMA_VERSION,
		"username": clean_name,
		"username_key": key,
		"salt": salt,
		"password_hash": hash_password(password, salt),
		"session_token": token,
		"created_at": now_ts,
		"last_login_at": now_ts,
		"save_data": save_data
	}
	if not _write_account_record(key, record):
		return { "ok": false, "error": "Server konnte Konto nicht speichern.", "clear_token": false }

	return {
		"ok": true,
		"username": clean_name,
		"username_key": key,
		"session_token": token,
		"save_data": save_data
	}


func login_account(username: String, password: String) -> Dictionary:
	var uv: Dictionary = validate_username(username)
	if not bool(uv["ok"]):
		return { "ok": false, "error": str(uv["error"]), "clear_token": false }
	var pv: Dictionary = validate_password(password)
	if not bool(pv["ok"]):
		return { "ok": false, "error": str(pv["error"]), "clear_token": false }

	var clean_name: String = str(uv["clean"])
	var key: String = str(uv["key"])
	var record: Dictionary = load_account_record(key)
	if record.is_empty():
		return { "ok": false, "error": "Konto '%s' nicht gefunden. Bitte zuerst registrieren." % clean_name, "clear_token": false }

	var salt: String = str(record.get("salt", ""))
	var expected_hash: String = str(record.get("password_hash", ""))
	if salt.is_empty() or hash_password(password, salt) != expected_hash:
		return { "ok": false, "error": "Falsches Passwort für '%s'." % str(record.get("username", clean_name)), "clear_token": false }

	var token: String = generate_hex_token(24)
	record["session_token"] = token
	record["last_login_at"] = int(Time.get_unix_time_from_system())
	var clean_save: Dictionary = sanitize_save_data(record.get("save_data", {}))
	record["save_data"] = clean_save
	_write_account_record(key, record)

	return {
		"ok": true,
		"username": str(record.get("username", clean_name)),
		"username_key": key,
		"session_token": token,
		"save_data": clean_save
	}


func login_with_token(username: String, session_token: String) -> Dictionary:
	var uv: Dictionary = validate_username(username)
	if not bool(uv["ok"]) or session_token.strip_edges().is_empty():
		return { "ok": false, "error": "Sitzung ungültig – bitte erneut anmelden.", "clear_token": true }

	var key: String = str(uv["key"])
	var record: Dictionary = load_account_record(key)
	if record.is_empty():
		return { "ok": false, "error": "Gespeichertes Konto nicht gefunden – bitte neu anmelden.", "clear_token": true }

	var stored_token: String = str(record.get("session_token", ""))
	if stored_token.is_empty() or stored_token != session_token.strip_edges():
		return { "ok": false, "error": "Sitzung abgelaufen – bitte erneut mit Passwort anmelden.", "clear_token": true }

	record["last_login_at"] = int(Time.get_unix_time_from_system())
	var clean_save: Dictionary = sanitize_save_data(record.get("save_data", {}))
	record["save_data"] = clean_save
	_write_account_record(key, record)

	return {
		"ok": true,
		"username": str(record.get("username", uv["clean"])),
		"username_key": key,
		"session_token": stored_token,
		"save_data": clean_save
	}


func update_account_save(username_key: String, save_data: Dictionary) -> bool:
	var key: String = username_key.strip_edges().to_lower()
	if key.is_empty():
		return false
	var record: Dictionary = load_account_record(key)
	if record.is_empty():
		return false
	record["save_data"] = sanitize_save_data(save_data)
	record["last_saved_at"] = int(Time.get_unix_time_from_system())
	return _write_account_record(key, record)


func clear_account_save(username_key: String) -> bool:
	return update_account_save(username_key, create_default_save_data())


func get_account_save_summary(username_key: String) -> Dictionary:
	var record: Dictionary = load_account_record(username_key)
	if record.is_empty():
		return { "exists": false }
	var save_data: Dictionary = sanitize_save_data(record.get("save_data", {}))
	return {
		"exists": true,
		"username": str(record.get("username", "")),
		"gold": int(save_data.get("gold", DEFAULT_GOLD)),
		"hull_tier": int(save_data.get("hull_tier", Contracts.ShipClass.SLOOP)),
		"has_saved_pos": bool(save_data.get("has_saved_pos", false))
	}


func has_solo_save() -> bool:
	return FileAccess.file_exists(get_solo_save_path())


func save_solo(save_data: Dictionary) -> bool:
	var clean: Dictionary = sanitize_save_data(save_data)
	clean["saved_at"] = int(Time.get_unix_time_from_system())
	return _write_json_dict(get_solo_save_path(), clean)


func load_solo() -> Dictionary:
	var path: String = get_solo_save_path()
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = _read_json_dict(path)
	if not (parsed is Dictionary):
		return {}
	return sanitize_save_data(parsed)


func clear_solo_save() -> void:
	var path: String = get_solo_save_path()
	if FileAccess.file_exists(path):
		var abs_path: String = ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path
		DirAccess.remove_absolute(abs_path)


static func _write_json_dict(path: String, data: Dictionary) -> bool:
	var base_dir: String = path.get_base_dir()
	if not base_dir.is_empty():
		_ensure_dir_exists(base_dir)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SaveStore] Failed to write %s (err=%d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


static func _read_json_dict(path: String) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	if text.strip_edges().is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data

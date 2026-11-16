class_name ClientSyncController
extends RefCounted
## Handles client-side snapshot coalescing (max 1 combined snapshot per frame),
## change-filtered EventBus emissions, local ship prediction reconciliation,
## stationary-culled 60Hz remote extrapolation, and ShipStackRenderer sync.

const SHIP_RENDERER_PATH: String = "res://visual/ship_stack_renderer.gd"
const INTERP_BUFFER_SEC: float = 0.075
const MAX_REMOTE_EXTRAP_SEC: float = 0.16

var all_ships_ref: Dictionary = {}
var ship_renderers_ref: Dictionary = {}
var world_map_ref: Node = null
var combat_system_ref: CombatSystem = null
var loot_system_ref: LootSystem = null
var network_manager_ref: NetworkManager = null
var world_root_ref: Node2D = null
var pixel_camera_ref: Camera2D = null
var harbor_ui_ref: HarborUI = null
var hud_overlay_ref: HudOverlay = null

var player_ship_id: int = 1
var client_desired_sail_state: int = Contracts.SailState.ANCHORED
var has_initial_player_snapshot: bool = false

var _create_ship_cb: Callable = Callable()
var _set_player_ship_cb: Callable = Callable()
var _ship_renderer_script: Script = null
var _is_headless: bool = false

var _remote_extrap_age: Dictionary = {} # ship_id (int) -> float
var _remote_interp: Dictionary = {} # ship_id (int) -> { t0, p0, h0, v0, w0, t1, p1, h1, v1, w1, spd1, sail1 }
var _interp_clock: float = 0.0
var _latest_srv_time: float = 0.0
var _has_srv_time: bool = false
var _pred_history: Dictionary = {} # seq (int) -> { "pos": Vector2, "hdg": float }
var _input_seq: int = 0
var _local_fire_anticipation_msec: Dictionary = {} # bool -> int
var _pending_snapshot: Dictionary = {}
var _has_pending_snapshot: bool = false

var _last_wind_dir: Vector2 = Vector2(999.0, 999.0)
var _last_wind_strength: float = -1.0
var _last_weather_state: int = -1
var _last_weather_intensity: float = -1.0
var _last_wanted_level: int = -1
var _last_monster_state: Dictionary = {}
var _last_ship_visuals: Dictionary = {}


func _bus() -> Contracts:
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		return st.root.get_node_or_null("EventBus") as Contracts
	return null


func bind_callbacks(p_create_ship_cb: Callable, p_set_player_ship_cb: Callable) -> void:
	_create_ship_cb = p_create_ship_cb
	_set_player_ship_cb = p_set_player_ship_cb
	_ship_renderer_script = load(SHIP_RENDERER_PATH) as Script


func bind_world_refs(
	p_all_ships: Dictionary,
	p_ship_renderers: Dictionary,
	p_world_map: Node,
	p_combat_system: CombatSystem,
	p_loot_system: LootSystem,
	p_network_manager: NetworkManager,
	p_world_root: Node2D,
	p_pixel_camera: Camera2D,
	p_harbor_ui: HarborUI,
	p_hud_overlay: HudOverlay,
	p_is_headless: bool = false
) -> void:
	all_ships_ref = p_all_ships
	ship_renderers_ref = p_ship_renderers
	world_map_ref = p_world_map
	combat_system_ref = p_combat_system
	loot_system_ref = p_loot_system
	network_manager_ref = p_network_manager
	world_root_ref = p_world_root
	pixel_camera_ref = p_pixel_camera
	harbor_ui_ref = p_harbor_ui
	hud_overlay_ref = p_hud_overlay
	_is_headless = p_is_headless


func connect_visual_signals() -> void:
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


func reset() -> void:
	has_initial_player_snapshot = false
	client_desired_sail_state = Contracts.SailState.ANCHORED
	_remote_extrap_age.clear()
	_remote_interp.clear()
	_interp_clock = 0.0
	_latest_srv_time = 0.0
	_has_srv_time = false
	_pred_history.clear()
	_input_seq = 0
	_local_fire_anticipation_msec.clear()
	_pending_snapshot.clear()
	_has_pending_snapshot = false
	_last_wind_dir = Vector2(999.0, 999.0)
	_last_wind_strength = -1.0
	_last_weather_state = -1
	_last_weather_intensity = -1.0
	_last_wanted_level = -1
	_last_monster_state.clear()
	_last_ship_visuals.clear()


func next_input_seq() -> int:
	_input_seq += 1
	return _input_seq


func record_prediction(seq: int, pos: Vector2, hdg: float) -> void:
	_pred_history[seq] = { "pos": pos, "hdg": hdg }
	if _pred_history.size() > 110:
		var cutoff: int = seq - 90
		for old_k in _pred_history.keys():
			if int(old_k) < cutoff:
				_pred_history.erase(old_k)


func trigger_local_fire_anticipation(sid: int, is_starboard: bool) -> void:
	_local_fire_anticipation_msec[is_starboard] = Time.get_ticks_msec()
	var r: Node2D = ship_renderers_ref.get(sid, null)
	if r != null and is_instance_valid(r):
		r.call("trigger_muzzle_flash", is_starboard)
	if pixel_camera_ref != null:
		pixel_camera_ref.call("add_trauma", 0.22)
	if combat_system_ref != null:
		combat_system_ref.trigger_client_reload_visual(sid, is_starboard)


func ensure_ship_renderer(sid: int, faction: int, ship_name: String, pos: Vector2, heading: float) -> void:
	if _is_headless or world_root_ref == null or _ship_renderer_script == null:
		return
	if ship_renderers_ref.has(sid) and is_instance_valid(ship_renderers_ref[sid]):
		return
	var r: Node2D = _ship_renderer_script.new()
	r.name = "ShipRenderer_%d" % sid
	r.z_index = 5
	world_root_ref.add_child(r)
	r.call("setup_ship", sid, faction, ship_name)
	r.call("update_transform_state", pos, heading, 0.0, Contracts.SailState.ANCHORED, 120.0, 120.0)
	ship_renderers_ref[sid] = r


## Coalesces multiple snapshots arriving within the same frame into one merged payload
## so browser tab switches or micro-stalls never cause catch-up freeze loops.
func queue_snapshot(snapshot: Dictionary) -> void:
	if not _has_pending_snapshot:
		_pending_snapshot = snapshot.duplicate(false)
		_has_pending_snapshot = true
		return

	for key in ["t", "acks", "wind_x", "wind_y", "wind_strength", "weather_state", "weather_intensity", "wanted_level", "forts", "sea_monster", "drops"]:
		if snapshot.has(key):
			_pending_snapshot[key] = snapshot[key]

	if snapshot.has("ships"):
		var prev_by_id: Dictionary = {}
		for old_sd_var in _pending_snapshot.get("ships", []):
			if old_sd_var is Dictionary and old_sd_var.has("ship_id"):
				prev_by_id[int(old_sd_var["ship_id"])] = old_sd_var
		var merged_ships: Array = []
		for new_sd_var in snapshot.get("ships", []):
			if not (new_sd_var is Dictionary):
				continue
			var new_sd: Dictionary = new_sd_var
			var sid: int = int(new_sd.get("ship_id", -1))
			if sid >= 0 and prev_by_id.has(sid):
				var combined: Dictionary = (prev_by_id[sid] as Dictionary).duplicate(false)
				for k in new_sd.keys():
					combined[k] = new_sd[k]
				merged_ships.append(combined)
			else:
				merged_ships.append(new_sd)
		_pending_snapshot["ships"] = merged_ships


func flush_pending_snapshot() -> void:
	if not _has_pending_snapshot:
		return
	var snap: Dictionary = _pending_snapshot
	_pending_snapshot = {}
	_has_pending_snapshot = false
	apply_snapshot(snap)


func apply_snapshot(snapshot: Dictionary) -> void:
	_has_pending_snapshot = false
	_pending_snapshot = {}
	var bus := _bus()

	_apply_environment_diff(snapshot, bus)
	_apply_sea_monster_diff(snapshot, bus)

	if combat_system_ref != null and snapshot.has("forts"):
		combat_system_ref.apply_fort_sync_array(snapshot["forts"])
	if loot_system_ref != null and snapshot.has("drops"):
		loot_system_ref.apply_sync_array(snapshot["drops"])

	if snapshot.has("t"):
		var srv_t: float = float(snapshot["t"])
		_latest_srv_time = maxf(_latest_srv_time, srv_t)
		var desired_clk: float = _latest_srv_time - INTERP_BUFFER_SEC
		if not _has_srv_time or absf(desired_clk - _interp_clock) > 0.25:
			_interp_clock = desired_clk
		_has_srv_time = true
	else:
		_latest_srv_time += 0.066
		if not _has_srv_time:
			_interp_clock = _latest_srv_time - INTERP_BUFFER_SEC
			_has_srv_time = true

	var acks_dict: Dictionary = snapshot.get("acks", {})
	var player_ack: int = int(acks_dict.get(player_ship_id, 0))
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

		var ship: Node = all_ships_ref.get(sid, null)
		var is_new_ship: bool = (ship == null)
		if ship == null and _create_ship_cb.is_valid():
			var fac: int = int(sd.get("faction", Contracts.ShipFaction.PIRATE))
			var sname: String = str(sd.get("ship_name", sd.get("name", "Schiff #%d" % sid)))
			var pos := Vector2(float(sd.get("x", 0.0)), float(sd.get("y", 0.0)))
			var hdg: float = float(sd.get("heading", 0.0))
			ship = _create_ship_cb.call(sid, pos, hdg, fac, sname)
			all_ships_ref[sid] = ship
			ensure_ship_renderer(sid, fac, sname, pos, hdg)
		if ship == null:
			continue

		var rend: Node2D = ship_renderers_ref.get(sid, null)
		if sid == player_ship_id:
			_reconcile_local_player(ship, rend, sd, is_new_ship, player_ack)
		elif sd.size() > 1:
			_sync_remote_ship(sid, ship, rend, sd, is_new_ship, _latest_srv_time)

		if sd.has("hull_tier") and rend != null and is_instance_valid(rend) and rend.has_method("set_hull_tier"):
			rend.call("set_hull_tier", int(sd["hull_tier"]))
		if bus != null and (is_new_ship or _ship_visual_changed(sid, ship)):
			_emit_ship_state(bus, sid, ship)

	var to_remove: Array[int] = []
	for existing_var in all_ships_ref.keys():
		var eid: int = int(existing_var)
		if not seen_ids.has(eid) and eid != player_ship_id:
			to_remove.append(eid)
	for eid in to_remove:
		_remote_extrap_age.erase(eid)
		_remote_interp.erase(eid)
		_last_ship_visuals.erase(eid)
		var old_ship: Node = all_ships_ref.get(eid, null)
		all_ships_ref.erase(eid)
		if is_instance_valid(old_ship):
			old_ship.queue_free()
		_on_ship_despawned(eid)


func step_remote_extrapolation(delta: float) -> void:
	if _has_srv_time:
		_interp_clock += delta
		var target_clk: float = _latest_srv_time - INTERP_BUFFER_SEC
		var clk_err: float = target_clk - _interp_clock
		if absf(clk_err) > 0.015:
			_interp_clock += clk_err * minf(1.0, delta * 4.0)

	var bus := _bus()
	for sid_var in all_ships_ref.keys():
		var sid: int = int(sid_var)
		if sid == player_ship_id:
			continue
		var r_ship: Node = all_ships_ref[sid_var]
		if r_ship == null or not is_instance_valid(r_ship) or bool(r_ship.get("is_sunk")):
			continue

		var buf_var: Variant = _remote_interp.get(sid, null)
		if buf_var is Dictionary:
			var buf: Dictionary = buf_var
			var t0: float = float(buf["t0"])
			var t1: float = float(buf["t1"])
			var p0: Vector2 = buf["p0"]
			var p1: Vector2 = buf["p1"]
			var h0: float = float(buf["h0"])
			var h1: float = float(buf["h1"])
			var v1: Vector2 = buf["v1"]
			var w1: float = float(buf["w1"])
			var next_pos: Vector2 = p1
			var next_hdg: float = h1
			if _interp_clock <= t1 and t1 > t0 + 0.001:
				var alpha: float = clampf((_interp_clock - t0) / (t1 - t0), 0.0, 1.0)
				next_pos = p0.lerp(p1, alpha)
				next_hdg = lerp_angle(h0, h1, alpha)
			else:
				var extra: float = clampf(_interp_clock - t1, 0.0, MAX_REMOTE_EXTRAP_SEC)
				next_pos = p1 + v1.rotated(w1 * extra * 0.5) * extra
				next_hdg = wrapf(h1 + w1 * extra, -PI, PI)
			r_ship.set("world_pos", next_pos)
			r_ship.set("heading", next_hdg)
			if bus != null and _ship_visual_changed(sid, r_ship):
				_emit_ship_state(bus, sid, r_ship)
			continue

		var age: float = float(_remote_extrap_age.get(sid, 0.0)) + delta
		_remote_extrap_age[sid] = age
		if age > 0.25:
			continue
		var r_vel: Vector2 = r_ship.get("velocity")
		var r_ang_vel: float = float(r_ship.get("angular_velocity"))
		if r_vel.length_squared() < 0.01 and absf(r_ang_vel) < 0.001:
			continue
		var r_pos: Vector2 = (r_ship.get("world_pos") as Vector2) + r_vel.rotated(r_ang_vel * delta * 0.5) * delta
		var r_hdg: float = wrapf(float(r_ship.get("heading")) + r_ang_vel * delta, -PI, PI)
		r_ship.set("world_pos", r_pos)
		r_ship.set("heading", r_hdg)
		if bus != null and _ship_visual_changed(sid, r_ship):
			_emit_ship_state(bus, sid, r_ship)


func _apply_environment_diff(snapshot: Dictionary, bus: Contracts) -> void:
	if world_map_ref != null and snapshot.has("wind_x") and snapshot.has("wind_y"):
		var wd := Vector2(float(snapshot["wind_x"]), float(snapshot["wind_y"])).normalized()
		var ws: float = float(snapshot.get("wind_strength", 0.7))
		if wd.distance_squared_to(_last_wind_dir) > 0.0001 or absf(ws - _last_wind_strength) > 0.005:
			_last_wind_dir = wd
			_last_wind_strength = ws
			world_map_ref.set("wind_direction", wd)
			world_map_ref.set("wind_strength", ws)
			if bus != null:
				bus.wind_changed.emit(wd, ws)

	if snapshot.has("weather_state"):
		var wst: int = int(snapshot["weather_state"])
		var wint: float = float(snapshot.get("weather_intensity", 0.0))
		if wst != _last_weather_state or absf(wint - _last_weather_intensity) > 0.005:
			_last_weather_state = wst
			_last_weather_intensity = wint
			if world_map_ref != null:
				world_map_ref.set("current_weather", wst)
				world_map_ref.set("weather_intensity", wint)
			if bus != null:
				bus.weather_changed.emit(wst, wint)

	if bus != null and snapshot.has("wanted_level"):
		var wanted: int = int(snapshot["wanted_level"])
		if wanted != _last_wanted_level:
			_last_wanted_level = wanted
			bus.wanted_level_changed.emit(wanted)


func _apply_sea_monster_diff(snapshot: Dictionary, bus: Contracts) -> void:
	if bus == null or not snapshot.has("sea_monster"):
		return
	var md: Variant = snapshot["sea_monster"]
	if not (md is Dictionary) or md.is_empty():
		return
	var mid: int = int(md.get("monster_id", 5000))
	var mpos := Vector2(float(md.get("x", 0.0)), float(md.get("y", 0.0)))
	var mhp: float = float(md.get("hp", 0.0))
	var mmax: float = float(md.get("max_hp", 320.0))
	var mphase: int = int(md.get("phase", 0))
	if bool(md.get("defeated", true)) or mhp <= 0.0:
		_last_monster_state.clear()
		return
	var changed: bool = (
		_last_monster_state.is_empty() or int(_last_monster_state.get("id", -1)) != mid
		or (_last_monster_state.get("pos", Vector2.ZERO) as Vector2).distance_squared_to(mpos) > 0.25
		or absf(float(_last_monster_state.get("hp", -1.0)) - mhp) > 0.1
		or int(_last_monster_state.get("phase", -1)) != mphase
	)
	if changed:
		_last_monster_state = { "id": mid, "pos": mpos, "hp": mhp, "phase": mphase }
		bus.sea_monster_updated.emit(mid, mpos, mhp, mmax, mphase)


func _reconcile_local_player(ship: Node, rend: Node2D, sd: Dictionary, is_new_ship: bool, ack_seq: int = 0) -> void:
	if sd.size() > 1:
		var pre_pos: Vector2 = ship.get("world_pos")
		var pre_hdg: float = float(ship.get("heading"))
		var was_sunk: bool = bool(ship.get("is_sunk"))
		var srv_is_sunk: bool = bool(sd.get("is_sunk", false))
		var srv_pos := Vector2(float(sd.get("x", pre_pos.x)), float(sd.get("y", pre_pos.y)))
		var srv_hdg: float = float(sd.get("heading", pre_hdg))
		var srv_vel := Vector2(float(sd.get("vx", 0.0)), float(sd.get("vy", 0.0)))
		var srv_speed: float = float(sd.get("speed", srv_vel.length()))

		if not has_initial_player_snapshot or is_new_ship or srv_is_sunk or was_sunk or pre_pos.distance_to(srv_pos) > 110.0:
			ship.call("apply_sync_dict", sd)
			_pred_history.clear()
			if rend != null and is_instance_valid(rend) and rend.has_method("clear_visual_offset"):
				rend.call("clear_visual_offset")
			if not has_initial_player_snapshot and pixel_camera_ref != null:
				pixel_camera_ref.call("snap_to_pos", srv_pos)
			has_initial_player_snapshot = true
			if srv_is_sunk:
				client_desired_sail_state = Contracts.SailState.ANCHORED
		else:
			_apply_authoritative_non_kinematic(ship, sd)
			var both_idle: bool = (client_desired_sail_state == Contracts.SailState.ANCHORED and srv_speed < 4.0 and float(ship.get("speed")) < 4.0)
			var ref_pos: Vector2 = pre_pos
			var ref_hdg: float = pre_hdg
			var has_ack: bool = ack_seq > 0 and _pred_history.has(ack_seq)
			if has_ack:
				var pred: Dictionary = _pred_history[ack_seq]
				ref_pos = pred["pos"]
				ref_hdg = float(pred["hdg"])
				for k in _pred_history.keys():
					if int(k) <= ack_seq:
						_pred_history.erase(k)

			var err_vec: Vector2 = srv_pos - ref_pos
			var err_len: float = err_vec.length()
			var deadband: float = 4.0 if both_idle else (10.0 if has_ack else 26.0)
			if err_len > deadband:
				var corr_gain: float = 0.25 if has_ack else 0.22
				var corr: Vector2 = err_vec.normalized() * ((err_len - deadband) * corr_gain)
				ship.set("world_pos", pre_pos + corr)
				if rend != null and is_instance_valid(rend) and rend.has_method("add_visual_offset"):
					rend.call("add_visual_offset", -corr, 0.0)

			var hdg_diff: float = wrapf(srv_hdg - ref_hdg, -PI, PI)
			var hdg_deadband: float = 0.14 if has_ack else 0.24
			if absf(hdg_diff) > hdg_deadband:
				var hdg_corr: float = hdg_diff * 0.22
				ship.set("heading", wrapf(pre_hdg + hdg_corr, -PI, PI))
				if rend != null and is_instance_valid(rend) and rend.has_method("add_visual_offset"):
					rend.call("add_visual_offset", Vector2.ZERO, -hdg_corr)

	if _set_player_ship_cb.is_valid():
		_set_player_ship_cb.call(ship)
	if harbor_ui_ref != null:
		harbor_ui_ref.player_ship = ship
	if hud_overlay_ref != null:
		hud_overlay_ref.player_ship = ship


func _sync_remote_ship(sid: int, ship: Node, rend: Node2D, sd: Dictionary, is_new_ship: bool, srv_time: float) -> void:
	var pre_pos: Vector2 = ship.get("world_pos")
	var pre_hdg: float = float(ship.get("heading"))
	ship.call("apply_sync_dict", sd)
	var next_pos: Vector2 = ship.get("world_pos")
	var next_hdg: float = float(ship.get("heading"))
	var next_vel: Vector2 = ship.get("velocity")
	var next_ang: float = float(ship.get("angular_velocity"))

	if is_new_ship or pre_pos.distance_to(next_pos) > 110.0 or not _remote_interp.has(sid):
		_remote_interp[sid] = {
			"t0": srv_time, "p0": next_pos, "h0": next_hdg,
			"t1": srv_time, "p1": next_pos, "h1": next_hdg,
			"v1": next_vel, "w1": next_ang
		}
		if rend != null and is_instance_valid(rend) and rend.has_method("clear_visual_offset"):
			rend.call("clear_visual_offset")
		return

	var prev_buf: Dictionary = _remote_interp[sid]
	_remote_interp[sid] = {
		"t0": maxf(float(prev_buf["t1"]), _interp_clock),
		"p0": pre_pos,
		"h0": pre_hdg,
		"t1": maxf(srv_time, _interp_clock + 0.02),
		"p1": next_pos,
		"h1": next_hdg,
		"v1": next_vel,
		"w1": next_ang
	}
	# Restore smoothed pre_pos so interpolation glides cleanly without 1-frame snap
	ship.set("world_pos", pre_pos)
	ship.set("heading", pre_hdg)


func _apply_authoritative_non_kinematic(ship: Node, sd: Dictionary) -> void:
	ship.set("faction", int(sd.get("faction", ship.get("faction"))))
	ship.set("ship_name", str(sd.get("ship_name", ship.get("ship_name"))))
	var new_tier: int = int(sd.get("hull_tier", ship.get("hull_tier")))
	if new_tier != int(ship.get("hull_tier")):
		ship.set("hull_tier", new_tier)
		if ship.has_method("_sync_hull_radius_for_tier"):
			ship.call("_sync_hull_radius_for_tier")
	for prop in ["hp", "max_hp", "chain_slow_timer", "burn_timer"]:
		ship.set(prop, float(sd.get(prop, ship.get(prop))))
	ship.set("is_sunk", bool(sd.get("is_sunk", ship.get("is_sunk"))))


func _ship_visual_changed(sid: int, ship: Node) -> bool:
	var prev: Variant = _last_ship_visuals.get(sid, null)
	if not (prev is Dictionary):
		return true
	var p: Dictionary = prev
	return (
		(p["pos"] as Vector2).distance_squared_to(ship.get("world_pos")) > 0.0025
		or absf(wrapf(float(p["hdg"]) - float(ship.get("heading")), -PI, PI)) > 0.002
		or absf(float(p["spd"]) - float(ship.get("speed"))) > 0.05
		or int(p["sail"]) != int(ship.get("sail_state"))
		or absf(float(p["hp"]) - float(ship.get("hp"))) > 0.05
		or absf(float(p["mhp"]) - float(ship.get("max_hp"))) > 0.05
	)


func _emit_ship_state(bus: Contracts, sid: int, ship: Node) -> void:
	var pos: Vector2 = ship.get("world_pos")
	var hdg: float = float(ship.get("heading"))
	var spd: float = float(ship.get("speed"))
	var sail: int = int(ship.get("sail_state"))
	var hp: float = float(ship.get("hp"))
	var mhp: float = float(ship.get("max_hp"))
	_last_ship_visuals[sid] = { "pos": pos, "hdg": hdg, "spd": spd, "sail": sail, "hp": hp, "mhp": mhp }
	var r: Node2D = ship_renderers_ref.get(sid, null)
	if r != null and is_instance_valid(r) and r.has_method("set_kinematic_velocity"):
		r.call("set_kinematic_velocity", ship.get("velocity"), float(ship.get("angular_velocity")))
	bus.ship_state_updated.emit(sid, pos, hdg, spd, sail, hp, mhp)


func _on_ship_spawned(sid: int, ship_data: Dictionary) -> void:
	if _is_headless:
		return
	ensure_ship_renderer(sid, int(ship_data.get("faction", Contracts.ShipFaction.PIRATE)), str(ship_data.get("name", "Schiff")), ship_data.get("world_pos", Vector2.ZERO), float(ship_data.get("heading", 0.0)))
	if ship_data.has("hull_tier") and ship_renderers_ref.has(sid):
		var r: Node2D = ship_renderers_ref[sid]
		if r != null and r.has_method("set_hull_tier"):
			r.call("set_hull_tier", int(ship_data["hull_tier"]))


func _on_ship_despawned(sid: int) -> void:
	if ship_renderers_ref.has(sid):
		var r: Node2D = ship_renderers_ref[sid]
		ship_renderers_ref.erase(sid)
		if is_instance_valid(r):
			r.queue_free()


func _on_ship_state_updated(sid: int, world_pos: Vector2, heading: float, speed: float, sail_state: int, hp: float, max_hp: float) -> void:
	var r: Node2D = ship_renderers_ref.get(sid, null)
	if r != null and is_instance_valid(r):
		var ship: Node = all_ships_ref.get(sid, null)
		var vel: Vector2 = ship.get("velocity") if ship != null else Vector2.ZERO
		var ang_vel: float = float(ship.get("angular_velocity")) if ship != null else 0.0
		r.call("update_transform_state", world_pos, heading, speed, sail_state, hp, max_hp, vel, ang_vel)


func _on_ship_stats_compiled(sid: int, stats: Contracts.ShipStats) -> void:
	var ps: Node = all_ships_ref.get(player_ship_id, null)
	if sid == player_ship_id and ps != null:
		ps.call("apply_stats", stats)
		if network_manager_ref != null and network_manager_ref.current_mode == NetworkManager.Mode.CLIENT:
			network_manager_ref.send_player_stats(stats)


func _on_ship_grid_updated(sid: int, equipped_items: Array) -> void:
	var r: Node2D = ship_renderers_ref.get(sid, null)
	if r != null and is_instance_valid(r):
		r.call("update_equipped_modules", equipped_items)


func _on_ship_class_upgraded(sid: int, new_hull_tier: int, _class_title: String) -> void:
	var r: Node2D = ship_renderers_ref.get(sid, null)
	if r != null and is_instance_valid(r) and r.has_method("set_hull_tier"):
		r.call("set_hull_tier", new_hull_tier)
	if sid == player_ship_id and network_manager_ref != null and network_manager_ref.current_mode == NetworkManager.Mode.CLIENT:
		network_manager_ref.send_ship_class_upgrade(new_hull_tier)


func _on_ship_repaired(sid: int, new_hp: float, _max_hp: float, _cost: int) -> void:
	if sid == player_ship_id and network_manager_ref != null and network_manager_ref.current_mode == NetworkManager.Mode.CLIENT:
		network_manager_ref.send_ship_repair(new_hp)


func _on_broadside_fired(sid: int, is_starboard: bool, _origin: Vector2, _dir: Vector2, _cannons: Array) -> void:
	if sid == player_ship_id and network_manager_ref != null and network_manager_ref.current_mode == NetworkManager.Mode.CLIENT:
		if _local_fire_anticipation_msec.has(is_starboard):
			var elapsed: int = Time.get_ticks_msec() - int(_local_fire_anticipation_msec[is_starboard])
			_local_fire_anticipation_msec.erase(is_starboard)
			if elapsed < 400:
				return
	var r: Node2D = ship_renderers_ref.get(sid, null)
	if r != null and is_instance_valid(r):
		r.call("trigger_muzzle_flash", is_starboard)
	if sid == player_ship_id and pixel_camera_ref != null:
		pixel_camera_ref.call("add_trauma", 0.25)
	if sid == player_ship_id and network_manager_ref != null and network_manager_ref.current_mode == NetworkManager.Mode.CLIENT and combat_system_ref != null:
		combat_system_ref.trigger_client_reload_visual(sid, is_starboard)


func _on_ship_damaged(sid: int, _damage: float, _new_hp: float, _max_hp: float, _world_pos: Vector2) -> void:
	var r: Node2D = ship_renderers_ref.get(sid, null)
	if r != null and is_instance_valid(r):
		r.call("trigger_hit_flash")
	if sid == player_ship_id and pixel_camera_ref != null:
		pixel_camera_ref.call("add_trauma", 0.34)


func _on_ship_sunk(sid: int, _world_pos: Vector2, _faction: int, _killer_ship_id: int) -> void:
	if sid == player_ship_id and _bus() != null:
		_bus().notification_posted.emit("Dein Schiff ist gesunken! Rückkehr nach Port Tortuga...", "combat")

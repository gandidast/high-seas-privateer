class_name FortDefenseSystem
extends RefCounted
## Manages coastal pirate forts / watchtowers: placement on island headlands,
## cooldowns, target acquisition, lead-predicted cannon fire, hit resolution,
## and revision-tracked network synchronization. 100% headless-safe.

const FORT_HIT_RADIUS: float = 22.0
const FORT_MAX_HP: float = 260.0
const FORT_RANGE: float = 270.0
const FORT_FIRE_INTERVAL: float = 3.8
const MAX_COASTAL_FORTS: int = 14

var forts: Dictionary = {} # fort_id (int) -> Dictionary
var sync_revision: int = 1


func _bus() -> Contracts:
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		return st.root.get_node_or_null("EventBus") as Contracts
	return null


func clear() -> void:
	if not forts.is_empty():
		sync_revision += 1
	forts.clear()


## Places hostile pirate coastal forts / watchtowers on wild island headlands (never on safe harbors).
func setup_island_forts(world_map: Node, rng: RandomNumberGenerator) -> void:
	forts.clear()
	var candidates: Array = []
	if world_map != null and world_map.has_method("get_fort_positions"):
		var raw: Variant = world_map.call("get_fort_positions")
		if raw is Array:
			candidates = raw

	if candidates.is_empty():
		var w_seed: int = Contracts.DEFAULT_WORLD_SEED
		if world_map != null and world_map.get("world_seed") != null:
			w_seed = int(world_map.get("world_seed"))
		var islands: Array = Contracts.get_islands(w_seed)
		for isl in islands:
			if isl.has_harbor or isl.index == 0 or (isl.index in Contracts.SAFE_HARBOR_INDICES):
				continue
			var fort_angle: float = isl.harbor_angle + PI * 0.72
			var coast_r: float = Contracts.get_island_coast_radius(isl.index, fort_angle, w_seed)
			var fpos: Vector2 = isl.center + Vector2.from_angle(fort_angle) * maxf(24.0, coast_r - 18.0)
			candidates.append({
				"fort_id": 8000 + isl.index,
				"island_index": isl.index,
				"world_pos": fpos,
				"name": "Piraten-Bastion %s" % isl.name
			})

	var bus := _bus()
	var placed: int = 0
	for entry_var in candidates:
		if placed >= MAX_COASTAL_FORTS:
			break
		if not (entry_var is Dictionary):
			continue
		var entry: Dictionary = entry_var
		var isl_idx: int = int(entry.get("island_index", placed))
		# Keep all safe harbor islands (and island 0) free of hostile coastal forts
		if isl_idx == 0 or (isl_idx in Contracts.SAFE_HARBOR_INDICES):
			continue
		if world_map != null and world_map.has_method("get_island"):
			var isl_data: Variant = world_map.call("get_island", isl_idx)
			if isl_data != null and bool(isl_data.get("has_harbor")):
				continue
		var fid: int = int(entry.get("fort_id", 8000 + isl_idx))
		var pos: Vector2 = entry.get("world_pos", Vector2.ZERO)
		var fname: String = str(entry.get("name", "Küsten-Fort #%d" % (placed + 1)))
		forts[fid] = {
			"fort_id": fid,
			"island_index": isl_idx,
			"name": fname,
			"world_pos": pos,
			"hp": FORT_MAX_HP,
			"max_hp": FORT_MAX_HP,
			"armor": 3.0,
			"fire_cooldown": rng.randf_range(1.2, 3.4),
			"fire_interval": FORT_FIRE_INTERVAL,
			"range": FORT_RANGE,
			"faction": Contracts.ShipFaction.PIRATE,
			"destroyed": false
		}
		placed += 1
		if bus != null:
			bus.fort_spawned.emit(fid, pos, isl_idx, FORT_MAX_HP)

	sync_revision += 1


## Advances fort cannon cooldowns and returns newly fired lead-predicted shot dictionaries.
func step_forts(delta: float, active_ships: Dictionary) -> Array[Dictionary]:
	var spawned_shots: Array[Dictionary] = []

	for fid_var in forts.keys():
		var fort: Dictionary = forts[fid_var]
		if bool(fort.get("destroyed", false)):
			continue

		var cd: float = float(fort.get("fire_cooldown", 0.0)) - delta
		if cd > 0.0:
			fort["fire_cooldown"] = cd
			continue

		var fpos: Vector2 = fort["world_pos"]
		var frange: float = float(fort.get("range", FORT_RANGE))
		var frange_sq: float = frange * frange
		var fort_faction: int = int(fort.get("faction", Contracts.ShipFaction.PIRATE))
		var isl_idx: int = int(fort.get("island_index", -1))

		var best_target: Node = null
		var best_dist_sq: float = frange_sq

		for s_var in active_ships.values():
			var ship: Node = s_var
			if ship == null or bool(ship.get("is_sunk")):
				continue
			var s_fac: int = int(ship.get("faction"))
			if s_fac == fort_faction:
				continue
			if ship.has_method("is_harbor_protected") and bool(ship.call("is_harbor_protected")):
				continue
			if s_fac == Contracts.ShipFaction.PLAYER and int(ship.get("current_harbor_index")) >= 0:
				continue
			var spos: Vector2 = ship.get("world_pos")
			var d_sq: float = fpos.distance_squared_to(spos)
			var weighted_sq: float = d_sq * (0.75 if s_fac == Contracts.ShipFaction.PLAYER else 1.0)
			if d_sq <= frange_sq and weighted_sq < best_dist_sq:
				best_dist_sq = weighted_sq
				best_target = ship

		if best_target == null:
			fort["fire_cooldown"] = 0.6
			continue

		fort["fire_cooldown"] = float(fort.get("fire_interval", FORT_FIRE_INTERVAL))
		var tpos: Vector2 = best_target.get("world_pos")
		var tvel: Vector2 = best_target.get("velocity")
		var proj_speed: float = 215.0
		var aim_dir: Vector2 = CombatSystem.compute_intercept_direction(fpos, Vector2.ZERO, tpos, tvel, proj_speed)
		var shot_vel: Vector2 = aim_dir * proj_speed
		var muzzle_pos: Vector2 = fpos + aim_dir * 16.0

		spawned_shots.append({
			"shooter_id": -1000 - int(fid_var),
			"faction": fort_faction,
			"origin": muzzle_pos,
			"pos": muzzle_pos,
			"vel": shot_vel,
			"velocity": shot_vel,
			"dir": aim_dir,
			"speed": shot_vel.length(),
			"damage": 18.0,
			"max_range": frange + 20.0,
			"traveled": 0.0,
			"flight_time": (frange + 20.0) / maxf(1.0, shot_vel.length()),
			"chain_slow": 0.0,
			"burn_dps": 0.0,
			"harpoon_pull": 0.0,
			"is_starboard": true
		})

	return spawned_shots


func check_fort_hit(proj: Dictionary, prev_pos: Vector2, next_pos: Vector2) -> bool:
	if forts.is_empty():
		return false
	var shooter_id: int = int(proj.get("shooter_id", -1))
	if shooter_id < 0:
		return false
	var shooter_faction: int = int(proj.get("faction", Contracts.ShipFaction.PLAYER))
	var mid_pos: Vector2 = (prev_pos + next_pos) * 0.5
	var hit_rad_sq: float = FORT_HIT_RADIUS * FORT_HIT_RADIUS

	for fid_var in forts.keys():
		var fort: Dictionary = forts[fid_var]
		if bool(fort.get("destroyed", false)):
			continue
		if shooter_faction == int(fort.get("faction", Contracts.ShipFaction.PIRATE)):
			continue
		var fpos: Vector2 = fort["world_pos"]
		if fpos.distance_squared_to(next_pos) <= hit_rad_sq or fpos.distance_squared_to(mid_pos) <= hit_rad_sq:
			var base_dmg: float = float(proj.get("damage", 15.0))
			var burn_bonus: float = float(proj.get("burn_dps", 0.0)) * 1.5
			var armor: float = float(fort.get("armor", 3.0))
			var dmg: float = maxf(3.0, base_dmg + burn_bonus - armor * 0.5)
			var new_hp: float = maxf(0.0, float(fort["hp"]) - dmg)
			fort["hp"] = new_hp
			sync_revision += 1
			var bus := _bus()
			if bus != null:
				bus.cannonball_impact.emit(next_pos, -1, dmg, false, false)
				bus.fort_damaged.emit(int(fid_var), new_hp, float(fort["max_hp"]), fpos)
			if new_hp <= 0.0:
				fort["destroyed"] = true
				if bus != null:
					bus.fort_destroyed.emit(int(fid_var), fpos)
					bus.notification_posted.emit("%s zerstört! Festungs-Beute im Wasser!" % str(fort["name"]), "combat")
			return true
	return false


func get_fort_sync_array() -> Array:
	var out: Array = []
	for f in forts.values():
		out.append({
			"fort_id": int(f["fort_id"]),
			"island_index": int(f["island_index"]),
			"name": str(f["name"]),
			"x": snappedf(float(f["world_pos"].x), 0.1),
			"y": snappedf(float(f["world_pos"].y), 0.1),
			"hp": snappedf(float(f["hp"]), 0.1),
			"max_hp": snappedf(float(f["max_hp"]), 0.1),
			"destroyed": bool(f["destroyed"])
		})
	return out


func apply_fort_sync_array(raw_forts: Array) -> void:
	var bus := _bus()
	for raw_var in raw_forts:
		if not (raw_var is Dictionary):
			continue
		var d: Dictionary = raw_var
		var fid: int = int(d.get("fort_id", 0))
		var pos := Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		var hp_val: float = float(d.get("hp", FORT_MAX_HP))
		var max_hp_val: float = float(d.get("max_hp", FORT_MAX_HP))
		var dest: bool = bool(d.get("destroyed", false))
		var isl_idx: int = int(d.get("island_index", 0))
		if not forts.has(fid):
			forts[fid] = {
				"fort_id": fid,
				"island_index": isl_idx,
				"name": str(d.get("name", "Küsten-Fort")),
				"world_pos": pos,
				"hp": hp_val,
				"max_hp": max_hp_val,
				"armor": 3.0,
				"fire_cooldown": 3.8,
				"fire_interval": FORT_FIRE_INTERVAL,
				"range": FORT_RANGE,
				"faction": Contracts.ShipFaction.PIRATE,
				"destroyed": dest
			}
			sync_revision += 1
			if bus != null and not dest:
				bus.fort_spawned.emit(fid, pos, isl_idx, max_hp_val)
		else:
			var existing: Dictionary = forts[fid]
			var prev_hp: float = float(existing.get("hp", hp_val))
			var was_dest: bool = bool(existing.get("destroyed", false))
			if absf(prev_hp - hp_val) > 0.05 or was_dest != dest:
				existing["hp"] = hp_val
				existing["destroyed"] = dest
				sync_revision += 1
				if bus != null and dest and not was_dest:
					bus.fort_destroyed.emit(fid, pos)

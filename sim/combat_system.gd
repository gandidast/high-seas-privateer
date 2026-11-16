class_name CombatSystem
extends Node
## Manages ship broadside reloads, lead-prediction ballistics, flying cannonballs,
## special weapons (Greek Fire burn, Harpoon pull, Crow's Nest range), ship-to-ship
## ramming collisions, coastal island forts, and sea-monster hit detection. 100% headless-safe.

const SHIP_VEL_INHERITANCE: float = 0.35
const HULL_HALF_LENGTH: float = 22.0
const HULL_HALF_WIDTH: float = 10.5
const FORT_HIT_RADIUS: float = 22.0
const FORT_MAX_HP: float = 260.0
const FORT_RANGE: float = 270.0
const FORT_FIRE_INTERVAL: float = 3.8
const RAM_COOLDOWN_SEC: float = 0.85

var ships: Dictionary = {} # ship_id (int) -> ShipPhysics Node
var projectiles: Array[Dictionary] = []
var forts: Dictionary = {} # fort_id (int) -> Dictionary

var _reload_timers: Dictionary = {} # ship_id -> { "port": Array[float], "starboard": Array[float] }
var _reload_max: Dictionary = {}    # ship_id -> { "port": Array[float], "starboard": Array[float] }
var _ram_cooldowns: Dictionary = {} # "idA_idB" -> float
var _sea_monster_targets: Dictionary = {} # monster_id -> { "pos": Vector2, "radius": float, "callback": Callable }
var _burn_fallback: Dictionary = {} # ship_id -> { "timer": float, "dps": float, "tick": float }
var _next_shot_id: int = 1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _bus() -> Contracts:
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		return st.root.get_node_or_null("EventBus") as Contracts
	return null


func register_ship(ship: Node) -> void:
	if ship == null:
		return
	var sid: int = int(ship.get("ship_id"))
	ships[sid] = ship
	_ensure_reload_slots(ship)


func unregister_ship(ship_id: int) -> void:
	ships.erase(ship_id)
	_reload_timers.erase(ship_id)
	_reload_max.erase(ship_id)
	_burn_fallback.erase(ship_id)


func register_sea_monster(monster_id: int, world_pos: Vector2, radius: float, hit_callback: Callable) -> void:
	_sea_monster_targets[monster_id] = {
		"pos": world_pos,
		"radius": maxf(14.0, radius),
		"callback": hit_callback
	}


func update_sea_monster_pos(monster_id: int, world_pos: Vector2) -> void:
	if _sea_monster_targets.has(monster_id):
		_sea_monster_targets[monster_id]["pos"] = world_pos


func unregister_sea_monster(monster_id: int) -> void:
	_sea_monster_targets.erase(monster_id)


func clear_all() -> void:
	ships.clear()
	projectiles.clear()
	forts.clear()
	_reload_timers.clear()
	_reload_max.clear()
	_ram_cooldowns.clear()
	_sea_monster_targets.clear()
	_burn_fallback.clear()
	_next_shot_id = 1


## Computes the unit launch direction for a projectile to intercept a moving target,
## accounting for both target velocity and inherited shooter velocity.
static func compute_intercept_direction(
	shooter_pos: Vector2,
	shooter_vel: Vector2,
	target_pos: Vector2,
	target_vel: Vector2,
	proj_speed: float
) -> Vector2:
	var dp: Vector2 = target_pos - shooter_pos
	if dp.length_squared() < 0.0001:
		return Vector2.RIGHT

	var speed: float = maxf(10.0, proj_speed)
	var dv: Vector2 = target_vel - shooter_vel * SHIP_VEL_INHERITANCE

	var a: float = dv.length_squared() - speed * speed
	var b: float = 2.0 * dp.dot(dv)
	var c: float = dp.length_squared()

	var t: float = -1.0
	if absf(a) < 0.001:
		if absf(b) > 0.001:
			t = -c / b
	else:
		var disc: float = b * b - 4.0 * a * c
		if disc >= 0.0:
			var sqrt_disc: float = sqrt(disc)
			var t1: float = (-b - sqrt_disc) / (2.0 * a)
			var t2: float = (-b + sqrt_disc) / (2.0 * a)
			if t1 > 0.0 and t2 > 0.0:
				t = minf(t1, t2)
			elif t1 > 0.0:
				t = t1
			elif t2 > 0.0:
				t = t2

	if t < 0.0:
		t = dp.length() / speed
	t = clampf(t, 0.0, 2.5)

	var aim_vec: Vector2 = dp + dv * t
	if aim_vec.length_squared() < 0.0001:
		return dp.normalized()
	return aim_vec.normalized()


## Returns the broadside aiming cone and reload readiness for a ship side.
## Includes Crow's Nest vision_bonus range extension.
func get_broadside_cone(ship_id: int, is_starboard: bool) -> Dictionary:
	var ship: Node = ships.get(ship_id, null)
	if ship == null:
		return {
			"origin": Vector2.ZERO,
			"dir": Vector2.RIGHT,
			"range": 240.0,
			"half_angle_rad": deg_to_rad(14.0),
			"ready_ratio": 0.0,
			"ready_count": 0,
			"total_count": 0
		}

	var heading: float = float(ship.get("heading"))
	var world_pos: Vector2 = ship.get("world_pos")
	var broadside_angle: float = heading + (PI * 0.5 if is_starboard else -PI * 0.5)
	var dir: Vector2 = Vector2.from_angle(broadside_angle)

	var cannons: Array = _get_effective_cannons(ship, is_starboard)
	_ensure_reload_slots(ship)
	var side_key: String = "starboard" if is_starboard else "port"
	var timers: Array = _reload_timers[ship_id][side_key]
	var max_timers: Array = _reload_max[ship_id][side_key]

	var max_range: float = 0.0
	var max_spread_deg: float = 6.0
	var ready_count: int = 0
	var readiness_sum: float = 0.0

	for i in range(cannons.size()):
		var c: Dictionary = cannons[i]
		max_range = maxf(max_range, float(c.get("cannon_range", c.get("range", 250.0))))
		max_spread_deg = maxf(max_spread_deg, float(c.get("spread_angle_deg", 6.0)))
		var t_rem: float = float(timers[i]) if i < timers.size() else 0.0
		var t_max: float = maxf(0.1, float(max_timers[i]) if i < max_timers.size() else 2.5)
		if t_rem <= 0.001:
			ready_count += 1
			readiness_sum += 1.0
		else:
			readiness_sum += clampf(1.0 - (t_rem / t_max), 0.0, 0.99)

	var total_count: int = cannons.size()
	var ready_ratio: float = (readiness_sum / float(total_count)) if total_count > 0 else 0.0
	if max_range <= 0.0:
		max_range = 240.0

	var stats: Contracts.ShipStats = ship.get("stats")
	if stats != null and stats.vision_bonus > 0.0:
		max_range += stats.vision_bonus * 0.55

	return {
		"origin": world_pos + dir * 10.0,
		"dir": dir,
		"range": max_range,
		"half_angle_rad": deg_to_rad(max_spread_deg + 8.0),
		"ready_ratio": ready_ratio,
		"ready_count": ready_count,
		"total_count": total_count
	}


## Fires all reloaded cannons on the chosen broadside and starts slot reload timers.
func fire_broadside(ship_id: int, is_starboard: bool, aim_bias_rad: float = 0.0) -> Array:
	var ship: Node = ships.get(ship_id, null)
	if ship == null or bool(ship.get("is_sunk")):
		return []

	var cannons: Array = _get_effective_cannons(ship, is_starboard)
	if cannons.is_empty():
		return []

	_ensure_reload_slots(ship)
	var side_key: String = "starboard" if is_starboard else "port"
	var timers: Array = _reload_timers[ship_id][side_key]
	var max_timers: Array = _reload_max[ship_id][side_key]

	var heading: float = float(ship.get("heading"))
	var world_pos: Vector2 = ship.get("world_pos")
	var ship_vel: Vector2 = ship.get("velocity")
	var faction: int = int(ship.get("faction"))
	var stats: Contracts.ShipStats = ship.get("stats")
	var side_reload_mult: float = 1.0
	var vision_range_bonus: float = 0.0
	if stats != null:
		side_reload_mult = stats.starboard_reload_multiplier if is_starboard else stats.port_reload_multiplier
		vision_range_bonus = stats.vision_bonus * 0.25
	side_reload_mult = maxf(0.25, side_reload_mult)

	var base_angle: float = heading + (PI * 0.5 if is_starboard else -PI * 0.5)
	var clamped_bias: float = clampf(aim_bias_rad, -0.24, 0.24)
	var base_dir: Vector2 = Vector2.from_angle(base_angle + clamped_bias)

	var fired_cannons: Array = []
	var count: int = cannons.size()

	for i in range(count):
		if float(timers[i]) > 0.001:
			continue

		var c: Dictionary = cannons[i]
		var dmg: float = float(c.get("damage", c.get("cannon_damage", 15.0)))
		var proj_speed: float = float(c.get("projectile_speed", 220.0))
		var cannon_range: float = float(c.get("cannon_range", c.get("range", 255.0))) + vision_range_bonus
		var chain_slow: float = float(c.get("chain_shot_slow", 0.0))
		var spread_deg: float = float(c.get("spread_angle_deg", 6.0))
		var burn_dps: float = float(c.get("burn_dps", 0.0))
		if not c.has("burn_dps") and stats != null and stats.burn_bonus_dps > 0.0:
			burn_dps = stats.burn_bonus_dps
		var harpoon_pull: float = float(c.get("harpoon_pull", 0.0))

		var reload_dur: float = 2.8
		if c.has("effective_reload_time"):
			reload_dur = float(c["effective_reload_time"])
		elif c.has("synergy_mult"):
			reload_dur = maxf(0.35, float(c.get("reload_time", 2.8)))
		else:
			var raw_reload: float = float(c.get("reload_time", 2.8))
			reload_dur = maxf(0.35, raw_reload / side_reload_mult)

		timers[i] = reload_dur
		max_timers[i] = reload_dur

		var local_offset: Vector2
		if c.has("local_offset") and c["local_offset"] is Vector2:
			local_offset = c["local_offset"]
		elif c.has("deck_offset_x"):
			local_offset = Vector2(float(c["deck_offset_x"]), 9.0 if is_starboard else -9.0)
		else:
			var t: float = 0.0 if count == 1 else (float(i) / float(count - 1) - 0.5) * 2.0
			local_offset = Vector2(t * 11.0, 9.0 if is_starboard else -9.0)

		var muzzle_pos: Vector2 = world_pos + local_offset.rotated(heading)
		var spread_rad: float = deg_to_rad(spread_deg)
		var shot_angle: float = base_angle + clamped_bias + _rng.randf_range(-spread_rad * 0.5, spread_rad * 0.5)
		var shot_dir: Vector2 = Vector2.from_angle(shot_angle)
		var shot_vel: Vector2 = shot_dir * proj_speed + ship_vel * SHIP_VEL_INHERITANCE

		var shot_id: int = _next_shot_id
		_next_shot_id += 1

		var shot_data: Dictionary = {
			"shot_id": shot_id,
			"shooter_id": ship_id,
			"faction": faction,
			"origin": muzzle_pos,
			"pos": muzzle_pos,
			"vel": shot_vel,
			"velocity": shot_vel,
			"dir": shot_dir,
			"speed": shot_vel.length(),
			"damage": dmg,
			"max_range": cannon_range,
			"traveled": 0.0,
			"flight_time": cannon_range / maxf(1.0, shot_vel.length()),
			"chain_slow": chain_slow,
			"burn_dps": burn_dps,
			"harpoon_pull": harpoon_pull,
			"is_starboard": is_starboard
		}
		projectiles.append(shot_data)
		fired_cannons.append(shot_data)
		var bus := _bus()
		if bus != null:
			bus.cannonball_spawned.emit(shot_data)

	if not fired_cannons.is_empty():
		var bus := _bus()
		if bus != null:
			bus.broadside_fired.emit(ship_id, is_starboard, world_pos, base_dir, fired_cannons)

	return fired_cannons


## Advances reload timers, moves all flying projectiles, and resolves ship/monster/fort/land/water impacts.
func step_projectiles(delta: float, world_map: Node) -> void:
	step_reloads(delta)
	_step_burn_fallback(delta)

	var remaining: Array[Dictionary] = []
	for proj in projectiles:
		var vel: Vector2 = proj["vel"]
		var prev_pos: Vector2 = proj["pos"]
		var next_pos: Vector2 = prev_pos + vel * delta
		var step_dist: float = vel.length() * delta
		proj["pos"] = next_pos
		proj["traveled"] = float(proj["traveled"]) + step_dist

		var hit_info: Dictionary = _check_ship_hit(proj, prev_pos, next_pos)
		if bool(hit_info.get("hit", false)):
			var target: Node = hit_info["target"]
			var target_id: int = int(hit_info["target_id"])
			var hit_zone: String = str(hit_info["zone"])
			_apply_ship_hit(proj, target, target_id, next_pos, hit_zone)
			continue

		if _check_sea_monster_hit(proj, prev_pos, next_pos):
			continue

		if _check_fort_hit(proj, prev_pos, next_pos):
			continue

		if world_map != null and world_map.has_method("is_land") and world_map.is_land(next_pos):
			var bus := _bus()
			if bus != null:
				bus.cannonball_impact.emit(next_pos, -1, 0.0, true, false)
			continue

		if float(proj["traveled"]) >= float(proj["max_range"]):
			var bus := _bus()
			if bus != null:
				bus.cannonball_impact.emit(next_pos, -1, 0.0, true, false)
			continue

		remaining.append(proj)

	projectiles = remaining


func step_reloads(delta: float) -> void:
	for sid in _reload_timers.keys():
		var side_dict: Dictionary = _reload_timers[sid]
		for side_key in ["port", "starboard"]:
			var arr: Array = side_dict[side_key]
			for i in range(arr.size()):
				if float(arr[i]) > 0.0:
					arr[i] = maxf(0.0, float(arr[i]) - delta)


## Resolves ship-to-ship hull ramming collisions, applying ram_damage_bonus and clean separation.
func step_ship_collisions(delta: float, p_ships: Dictionary = {}) -> void:
	for key in _ram_cooldowns.keys():
		var rem: float = float(_ram_cooldowns[key]) - delta
		if rem <= 0.0:
			_ram_cooldowns.erase(key)
		else:
			_ram_cooldowns[key] = rem

	var active_dict: Dictionary = p_ships if not p_ships.is_empty() else ships
	var ship_list: Array[Node] = []
	for s_var in active_dict.values():
		var s: Node = s_var
		if s != null and is_instance_valid(s) and not bool(s.get("is_sunk")):
			ship_list.append(s)

	var count: int = ship_list.size()
	for i in range(count):
		var ship_a: Node = ship_list[i]
		if bool(ship_a.get("is_sunk")):
			continue
		for j in range(i + 1, count):
			var ship_b: Node = ship_list[j]
			if bool(ship_b.get("is_sunk")):
				continue

			var pos_a: Vector2 = ship_a.get("world_pos")
			var pos_b: Vector2 = ship_b.get("world_pos")
			var rad_a: float = float(ship_a.get("hull_radius")) if ship_a.get("hull_radius") != null else 14.0
			var rad_b: float = float(ship_b.get("hull_radius")) if ship_b.get("hull_radius") != null else 14.0
			var min_dist: float = rad_a + rad_b
			var diff: Vector2 = pos_b - pos_a
			var dist_sq: float = diff.length_squared()
			if dist_sq >= min_dist * min_dist:
				continue

			var dist: float = sqrt(maxf(0.0001, dist_sq))
			var normal: Vector2 = diff / dist if dist > 0.01 else Vector2.RIGHT
			var overlap: float = min_dist - dist
			var push: Vector2 = normal * (overlap * 0.5 + 1.2)
			ship_a.set("world_pos", pos_a - push)
			ship_b.set("world_pos", pos_b + push)

			var vel_a: Vector2 = ship_a.get("velocity")
			var vel_b: Vector2 = ship_b.get("velocity")
			var approach_a: float = vel_a.dot(normal)
			var approach_b: float = vel_b.dot(-normal)
			var impact_speed: float = approach_a + approach_b

			# Separate velocities so hulls bounce cleanly instead of sticking
			if approach_a > 0.0:
				vel_a -= normal * approach_a * 0.75
			if approach_b > 0.0:
				vel_b += normal * approach_b * 0.75
			ship_a.set("velocity", vel_a)
			ship_b.set("velocity", vel_b)

			var id_a: int = int(ship_a.get("ship_id"))
			var id_b: int = int(ship_b.get("ship_id"))
			var pair_key: String = "%d_%d" % [mini(id_a, id_b), maxi(id_a, id_b)]
			if _ram_cooldowns.has(pair_key):
				continue

			var stats_a: Contracts.ShipStats = ship_a.get("stats")
			var stats_b: Contracts.ShipStats = ship_b.get("stats")
			var ram_bonus_a: float = stats_a.ram_damage_bonus if stats_a != null else 0.0
			var ram_bonus_b: float = stats_b.ram_damage_bonus if stats_b != null else 0.0

			if impact_speed > 18.0 or ((ram_bonus_a > 0.0 or ram_bonus_b > 0.0) and impact_speed > 8.0):
				_ram_cooldowns[pair_key] = RAM_COOLDOWN_SEC
				var impact_pos: Vector2 = (pos_a + pos_b) * 0.5

				if approach_a >= 12.0 or (ram_bonus_a > 0.0 and approach_a > 4.0):
					var raw_a: float = clampf(approach_a * 0.24, 5.0, 24.0) + ram_bonus_a
					var armor_b: float = stats_b.armor if stats_b != null else 0.0
					var dmg_to_b: float = maxf(4.0, raw_a - armor_b * 0.45)
					_apply_direct_damage(ship_b, id_b, dmg_to_b, impact_pos, id_a)
					if ram_bonus_a <= 0.0 and not bool(ship_a.get("is_sunk")):
						_apply_direct_damage(ship_a, id_a, 4.0, impact_pos, id_b)

				if approach_b >= 12.0 or (ram_bonus_b > 0.0 and approach_b > 4.0):
					var raw_b: float = clampf(approach_b * 0.24, 5.0, 24.0) + ram_bonus_b
					var armor_a: float = stats_a.armor if stats_a != null else 0.0
					var dmg_to_a: float = maxf(4.0, raw_b - armor_a * 0.45)
					_apply_direct_damage(ship_a, id_a, dmg_to_a, impact_pos, id_b)
					if ram_bonus_b <= 0.0 and not bool(ship_b.get("is_sunk")):
						_apply_direct_damage(ship_b, id_b, 4.0, impact_pos, id_a)


## Places 4 hostile pirate coastal forts / watchtowers on island headlands.
func setup_island_forts(world_map: Node) -> void:
	forts.clear()
	var candidates: Array = []
	if world_map != null and world_map.has_method("get_fort_positions"):
		var raw: Variant = world_map.call("get_fort_positions")
		if raw is Array:
			candidates = raw

	if candidates.is_empty():
		var islands: Array = Contracts.get_islands()
		for i in range(1, mini(5, islands.size())):
			var isl: Contracts.IslandData = islands[i]
			var fort_angle: float = isl.harbor_angle + PI * 0.72
			var coast_r: float = Contracts.get_island_coast_radius(isl.index, fort_angle)
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
		if not (entry_var is Dictionary):
			continue
		var entry: Dictionary = entry_var
		var isl_idx: int = int(entry.get("island_index", placed))
		# Keep starter/respawn harbor island (0 = Port Tortuga) free of hostile coastal forts
		if isl_idx == 0 and candidates.size() > 4:
			continue
		if placed >= 4:
			break
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
			"fire_cooldown": _rng.randf_range(1.2, 3.4),
			"fire_interval": FORT_FIRE_INTERVAL,
			"range": FORT_RANGE,
			"faction": Contracts.ShipFaction.PIRATE,
			"destroyed": false
		}
		placed += 1
		if bus != null:
			bus.fort_spawned.emit(fid, pos, isl_idx, FORT_MAX_HP)


## Advances fort cannon cooldowns and fires lead-predicted shots at hostile ships in range.
func step_forts(delta: float, p_ships: Dictionary = {}) -> void:
	var active_dict: Dictionary = p_ships if not p_ships.is_empty() else ships
	var bus := _bus()

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

		for s_var in active_dict.values():
			var ship: Node = s_var
			if ship == null or bool(ship.get("is_sunk")):
				continue
			var s_fac: int = int(ship.get("faction"))
			if s_fac == fort_faction:
				continue
			# Respect ships safely docked inside this island's harbor cove
			if int(ship.get("current_harbor_index")) == isl_idx and s_fac == Contracts.ShipFaction.PLAYER:
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
		var aim_dir: Vector2 = compute_intercept_direction(fpos, Vector2.ZERO, tpos, tvel, proj_speed)
		var shot_vel: Vector2 = aim_dir * proj_speed
		var muzzle_pos: Vector2 = fpos + aim_dir * 16.0

		var shot_id: int = _next_shot_id
		_next_shot_id += 1
		var shot_data: Dictionary = {
			"shot_id": shot_id,
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
		}
		projectiles.append(shot_data)
		if bus != null:
			bus.cannonball_spawned.emit(shot_data)


func get_fort_sync_array() -> Array:
	var out: Array = []
	for f in forts.values():
		out.append({
			"fort_id": int(f["fort_id"]),
			"island_index": int(f["island_index"]),
			"name": str(f["name"]),
			"x": float(f["world_pos"].x),
			"y": float(f["world_pos"].y),
			"hp": float(f["hp"]),
			"max_hp": float(f["max_hp"]),
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
			if bus != null and not dest:
				bus.fort_spawned.emit(fid, pos, isl_idx, max_hp_val)
		else:
			var existing: Dictionary = forts[fid]
			var was_dest: bool = bool(existing.get("destroyed", false))
			existing["hp"] = hp_val
			existing["destroyed"] = dest
			if bus != null and dest and not was_dest:
				bus.fort_destroyed.emit(fid, pos)


func _apply_ship_hit(
	proj: Dictionary,
	target: Node,
	target_id: int,
	impact_pos: Vector2,
	hit_zone: String
) -> void:
	var base_dmg: float = float(proj["damage"])
	var zone_mult: float = 1.0
	if hit_zone == "bow":
		zone_mult = 1.10
	elif hit_zone == "stern":
		zone_mult = 1.25

	var stats: Contracts.ShipStats = target.get("stats")
	var armor: float = stats.armor if stats != null else 0.0
	var dmg: float = maxf(2.0, base_dmg * zone_mult - armor * 0.65)

	var is_powder_crit: bool = false
	if stats != null and stats.explosion_hazard_damage > 0.0:
		var crit_chance: float = minf(0.65, 0.20 + float(stats.powder_barrel_count) * 0.12)
		if hit_zone == "midships":
			crit_chance = minf(0.75, crit_chance + 0.15)
		if _rng.randf() < crit_chance:
			is_powder_crit = true
			dmg += stats.explosion_hazard_damage

	var chain_slow: float = float(proj.get("chain_slow", 0.0))
	if chain_slow > 0.0 and target.has_method("apply_chain_slow"):
		target.call("apply_chain_slow", 3.5, chain_slow)

	var burn_dps: float = float(proj.get("burn_dps", 0.0))
	if burn_dps > 0.0:
		if target.has_method("apply_burn"):
			target.call("apply_burn", 4.0, burn_dps)
		else:
			_burn_fallback[target_id] = { "timer": 4.0, "dps": burn_dps, "tick": 0.5 }

	var harpoon_pull: float = float(proj.get("harpoon_pull", 0.0))
	if harpoon_pull > 0.0:
		var shooter_id: int = int(proj.get("shooter_id", -1))
		var pull_origin: Vector2 = proj.get("origin", impact_pos)
		var shooter_node: Node = ships.get(shooter_id, null)
		if shooter_node != null and is_instance_valid(shooter_node):
			pull_origin = shooter_node.get("world_pos")
		var tpos: Vector2 = target.get("world_pos")
		var pull_vec: Vector2 = pull_origin - tpos
		if pull_vec.length_squared() > 1.0:
			var pull_dir: Vector2 = pull_vec.normalized()
			var tvel: Vector2 = target.get("velocity")
			target.set("velocity", tvel + pull_dir * harpoon_pull * 1.35)
			var step_pos: Vector2 = tpos + pull_dir * minf(12.0, harpoon_pull * 0.22)
			if not Contracts.is_land(step_pos):
				target.set("world_pos", step_pos)
		if chain_slow <= 0.0 and target.has_method("apply_chain_slow"):
			target.call("apply_chain_slow", 3.0, 0.45)

	_apply_direct_damage(target, target_id, dmg, impact_pos, int(proj.get("shooter_id", -1)), is_powder_crit)


func _apply_direct_damage(
	target: Node,
	target_id: int,
	dmg: float,
	impact_pos: Vector2,
	attacker_id: int,
	is_powder_crit: bool = false
) -> void:
	if target == null or bool(target.get("is_sunk")):
		return
	var current_hp: float = float(target.get("hp"))
	var max_hp: float = float(target.get("max_hp"))
	var new_hp: float = maxf(0.0, current_hp - dmg)
	target.set("hp", new_hp)

	var bus := _bus()
	if bus != null:
		bus.cannonball_impact.emit(impact_pos, target_id, dmg, false, is_powder_crit)
		bus.ship_damaged.emit(target_id, dmg, new_hp, max_hp, impact_pos)

	if new_hp <= 0.0 and not bool(target.get("is_sunk")):
		target.set("is_sunk", true)
		var target_faction: int = int(target.get("faction"))
		var target_pos: Vector2 = target.get("world_pos")
		if bus != null:
			bus.ship_sunk.emit(target_id, target_pos, target_faction, attacker_id)


func _step_burn_fallback(delta: float) -> void:
	for sid_var in _burn_fallback.keys():
		var sid: int = int(sid_var)
		var ship: Node = ships.get(sid, null)
		if ship == null or not is_instance_valid(ship) or bool(ship.get("is_sunk")):
			_burn_fallback.erase(sid)
			continue
		var b: Dictionary = _burn_fallback[sid]
		b["timer"] = float(b["timer"]) - delta
		b["tick"] = float(b["tick"]) - delta
		if float(b["tick"]) <= 0.0:
			b["tick"] = 0.5
			var dmg: float = float(b["dps"]) * 0.5
			_apply_direct_damage(ship, sid, dmg, ship.get("world_pos"), -1, false)
		if float(b["timer"]) <= 0.0:
			_burn_fallback.erase(sid)


func _check_sea_monster_hit(proj: Dictionary, prev_pos: Vector2, next_pos: Vector2) -> bool:
	if _sea_monster_targets.is_empty():
		return false
	var shooter_id: int = int(proj.get("shooter_id", -1))
	if shooter_id <= 0:
		return false
	var mid_pos: Vector2 = (prev_pos + next_pos) * 0.5
	for mid_var in _sea_monster_targets.keys():
		var info: Dictionary = _sea_monster_targets[mid_var]
		var mpos: Vector2 = info["pos"]
		var rad_sq: float = pow(float(info["radius"]), 2.0)
		if mpos.distance_squared_to(next_pos) <= rad_sq or mpos.distance_squared_to(mid_pos) <= rad_sq:
			var dmg: float = float(proj.get("damage", 15.0)) + float(proj.get("burn_dps", 0.0)) * 2.0
			var cb: Callable = info["callback"]
			if cb.is_valid():
				cb.call(int(mid_var), dmg)
			var bus := _bus()
			if bus != null:
				bus.cannonball_impact.emit(next_pos, -1, dmg, false, false)
			return true
	return false


func _check_fort_hit(proj: Dictionary, prev_pos: Vector2, next_pos: Vector2) -> bool:
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


func _check_ship_hit(proj: Dictionary, prev_pos: Vector2, next_pos: Vector2) -> Dictionary:
	var shooter_id: int = int(proj.get("shooter_id", -1))
	var shooter_faction: int = int(proj.get("faction", Contracts.ShipFaction.NEUTRAL))
	var mid_pos: Vector2 = (prev_pos + next_pos) * 0.5

	for sid_var in ships.keys():
		var sid: int = int(sid_var)
		if sid == shooter_id:
			continue
		var ship: Node = ships[sid_var]
		if ship == null or bool(ship.get("is_sunk")):
			continue

		var target_faction: int = int(ship.get("faction"))
		if shooter_faction != Contracts.ShipFaction.PLAYER and shooter_faction == target_faction:
			continue

		var ship_pos: Vector2 = ship.get("world_pos")
		if ship_pos.distance_squared_to(next_pos) > 38.0 * 38.0 and ship_pos.distance_squared_to(mid_pos) > 38.0 * 38.0:
			continue

		var heading: float = float(ship.get("heading"))
		for sample_pos in [mid_pos, next_pos]:
			var local_pt: Vector2 = (sample_pos - ship_pos).rotated(-heading)
			if absf(local_pt.x) <= HULL_HALF_LENGTH and absf(local_pt.y) <= HULL_HALF_WIDTH:
				var zone: String = "midships"
				if local_pt.x > 10.0:
					zone = "bow"
				elif local_pt.x < -10.0:
					zone = "stern"
				return {
					"hit": true,
					"target": ship,
					"target_id": sid,
					"zone": zone
				}

	return { "hit": false }


func _get_effective_cannons(ship: Node, is_starboard: bool) -> Array:
	var stats: Contracts.ShipStats = ship.get("stats")
	if stats != null:
		var mounted: Array = stats.starboard_cannons if is_starboard else stats.port_cannons
		if not mounted.is_empty():
			return mounted

	var faction: int = int(ship.get("faction"))
	if faction == Contracts.ShipFaction.PLAYER:
		return []

	var y_off: float = 8.0 if is_starboard else -8.0
	return [
		{
			"damage": 12.0,
			"reload_time": 2.9,
			"cannon_range": 235.0,
			"projectile_speed": 215.0,
			"spread_angle_deg": 7.0,
			"chain_shot_slow": 0.0,
			"local_offset": Vector2(-7.0, y_off)
		},
		{
			"damage": 12.0,
			"reload_time": 2.9,
			"cannon_range": 235.0,
			"projectile_speed": 215.0,
			"spread_angle_deg": 7.0,
			"chain_shot_slow": 0.0,
			"local_offset": Vector2(7.0, y_off)
		}
	]


func _ensure_reload_slots(ship: Node) -> void:
	var sid: int = int(ship.get("ship_id"))
	if not _reload_timers.has(sid):
		_reload_timers[sid] = { "port": [], "starboard": [] }
		_reload_max[sid] = { "port": [], "starboard": [] }

	for is_sb in [false, true]:
		var side_key: String = "starboard" if is_sb else "port"
		var cannons: Array = _get_effective_cannons(ship, is_sb)
		var timers: Array = _reload_timers[sid][side_key]
		var max_t: Array = _reload_max[sid][side_key]
		while timers.size() < cannons.size():
			timers.append(0.0)
			max_t.append(2.8)
		if timers.size() > cannons.size():
			timers.resize(cannons.size())
			max_t.resize(cannons.size())

class_name CombatSystem
extends Node
## Manages ship broadside reloads, lead-prediction ballistics, flying cannonballs,
## special weapons (Greek Fire burn, Harpoon pull, Crow's Nest range), ship-to-ship
## ramming collisions, sea-monster hit detection, and delegates coastal island forts
## to FortDefenseSystem. 100% headless-safe.

const SHIP_VEL_INHERITANCE: float = 0.35
const HULL_HALF_LENGTH: float = 22.0
const HULL_HALF_WIDTH: float = 10.5
const FORT_HIT_RADIUS: float = FortDefenseSystem.FORT_HIT_RADIUS
const FORT_MAX_HP: float = FortDefenseSystem.FORT_MAX_HP
const FORT_RANGE: float = FortDefenseSystem.FORT_RANGE
const FORT_FIRE_INTERVAL: float = FortDefenseSystem.FORT_FIRE_INTERVAL
const RAM_COOLDOWN_SEC: float = 0.85

var ships: Dictionary = {} # ship_id (int) -> ShipPhysics Node
var projectiles: Array[Dictionary] = []
var _fort_defense: FortDefenseSystem = FortDefenseSystem.new()
var forts: Dictionary = _fort_defense.forts # Shared reference to FortDefenseSystem.forts

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
	_fort_defense.clear()
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
	return dp.normalized() if aim_vec.length_squared() < 0.0001 else aim_vec.normalized()


func get_broadside_cone(ship_id: int, is_starboard: bool) -> Dictionary:
	var ship: Node = ships.get(ship_id, null)
	if ship == null:
		return {
			"origin": Vector2.ZERO, "dir": Vector2.RIGHT, "range": 240.0,
			"half_angle_rad": deg_to_rad(14.0), "ready_ratio": 0.0, "ready_count": 0, "total_count": 0
		}

	var heading: float = float(ship.get("heading"))
	var world_pos: Vector2 = ship.get("world_pos")
	var dir: Vector2 = Vector2.from_angle(heading + (PI * 0.5 if is_starboard else -PI * 0.5))

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
	var bus := _bus()

	for i in range(count):
		if float(timers[i]) > 0.001:
			continue
		var c: Dictionary = cannons[i]
		var reload_dur: float = _compute_cannon_reload(c, side_reload_mult)
		timers[i] = reload_dur
		max_timers[i] = reload_dur

		var local_offset: Vector2 = _resolve_muzzle_offset(c, i, count, is_starboard)
		var muzzle_pos: Vector2 = world_pos + local_offset.rotated(heading)
		var spread_rad: float = deg_to_rad(float(c.get("spread_angle_deg", 6.0)))
		var shot_dir: Vector2 = Vector2.from_angle(base_angle + clamped_bias + _rng.randf_range(-spread_rad * 0.5, spread_rad * 0.5))
		var proj_speed: float = float(c.get("projectile_speed", 220.0))
		var shot_vel: Vector2 = shot_dir * proj_speed + ship_vel * SHIP_VEL_INHERITANCE
		var cannon_range: float = float(c.get("cannon_range", c.get("range", 255.0))) + vision_range_bonus
		var burn_dps: float = float(c.get("burn_dps", 0.0))
		if not c.has("burn_dps") and stats != null and stats.burn_bonus_dps > 0.0:
			burn_dps = stats.burn_bonus_dps

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
			"damage": float(c.get("damage", c.get("cannon_damage", 15.0))),
			"max_range": cannon_range,
			"traveled": 0.0,
			"flight_time": cannon_range / maxf(1.0, shot_vel.length()),
			"chain_slow": float(c.get("chain_shot_slow", 0.0)),
			"burn_dps": burn_dps,
			"harpoon_pull": float(c.get("harpoon_pull", 0.0)),
			"is_starboard": is_starboard
		}
		projectiles.append(shot_data)
		fired_cannons.append(shot_data)
		if bus != null:
			bus.cannonball_spawned.emit(shot_data)

	if not fired_cannons.is_empty() and bus != null:
		bus.broadside_fired.emit(ship_id, is_starboard, world_pos, base_dir, fired_cannons)

	return fired_cannons


func step_projectiles(delta: float, world_map: Node) -> void:
	step_reloads(delta)
	_step_burn_fallback(delta)

	var remaining: Array[Dictionary] = []
	var bus := _bus()
	for proj in projectiles:
		var vel: Vector2 = proj["vel"]
		var prev_pos: Vector2 = proj["pos"]
		var next_pos: Vector2 = prev_pos + vel * delta
		proj["pos"] = next_pos
		proj["traveled"] = float(proj["traveled"]) + vel.length() * delta

		var hit_info: Dictionary = _check_ship_hit(proj, prev_pos, next_pos)
		if bool(hit_info.get("hit", false)):
			_apply_ship_hit(proj, hit_info["target"], int(hit_info["target_id"]), next_pos, str(hit_info["zone"]))
			continue
		if _check_sea_monster_hit(proj, prev_pos, next_pos):
			continue
		if _fort_defense.check_fort_hit(proj, prev_pos, next_pos):
			continue
		if world_map != null and world_map.has_method("is_land") and world_map.is_land(next_pos):
			if bus != null:
				bus.cannonball_impact.emit(next_pos, -1, 0.0, true, false)
			continue
		if float(proj["traveled"]) >= float(proj["max_range"]):
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


func trigger_client_reload_visual(ship_id: int, is_starboard: bool) -> void:
	var ship: Node = ships.get(ship_id, null)
	if ship == null:
		return
	var cannons: Array = _get_effective_cannons(ship, is_starboard)
	_ensure_reload_slots(ship)
	var side_key: String = "starboard" if is_starboard else "port"
	var timers: Array = _reload_timers[ship_id][side_key]
	var max_timers: Array = _reload_max[ship_id][side_key]
	var stats: Contracts.ShipStats = ship.get("stats")
	var side_reload_mult: float = 1.0
	if stats != null:
		side_reload_mult = stats.starboard_reload_multiplier if is_starboard else stats.port_reload_multiplier
	side_reload_mult = maxf(0.25, side_reload_mult)
	for i in range(cannons.size()):
		if float(timers[i]) <= 0.001:
			var reload_dur: float = _compute_cannon_reload(cannons[i], side_reload_mult)
			timers[i] = reload_dur
			max_timers[i] = reload_dur


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
			if not bool(ship_b.get("is_sunk")):
				_resolve_ram_pair(ship_a, ship_b)


func _resolve_ram_pair(ship_a: Node, ship_b: Node) -> void:
	var pos_a: Vector2 = ship_a.get("world_pos")
	var pos_b: Vector2 = ship_b.get("world_pos")
	var rad_a: float = float(ship_a.get("hull_radius")) if ship_a.get("hull_radius") != null else 14.0
	var rad_b: float = float(ship_b.get("hull_radius")) if ship_b.get("hull_radius") != null else 14.0
	var min_dist: float = rad_a + rad_b
	var diff: Vector2 = pos_b - pos_a
	var dist_sq: float = diff.length_squared()
	if dist_sq >= min_dist * min_dist:
		return

	var dist: float = sqrt(maxf(0.0001, dist_sq))
	var normal: Vector2 = diff / dist if dist > 0.01 else Vector2.RIGHT
	var push: Vector2 = normal * ((min_dist - dist) * 0.5 + 1.2)
	ship_a.set("world_pos", pos_a - push)
	ship_b.set("world_pos", pos_b + push)

	var vel_a: Vector2 = ship_a.get("velocity")
	var vel_b: Vector2 = ship_b.get("velocity")
	var approach_a: float = vel_a.dot(normal)
	var approach_b: float = vel_b.dot(-normal)
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
		return

	var stats_a: Contracts.ShipStats = ship_a.get("stats")
	var stats_b: Contracts.ShipStats = ship_b.get("stats")
	var ram_a: float = stats_a.ram_damage_bonus if stats_a != null else 0.0
	var ram_b: float = stats_b.ram_damage_bonus if stats_b != null else 0.0
	var impact_speed: float = approach_a + approach_b
	if impact_speed <= 18.0 and not ((ram_a > 0.0 or ram_b > 0.0) and impact_speed > 8.0):
		return

	_ram_cooldowns[pair_key] = RAM_COOLDOWN_SEC
	var impact_pos: Vector2 = (pos_a + pos_b) * 0.5
	_apply_ram_strike(ship_a, id_a, ship_b, id_b, approach_a, ram_a, stats_b, impact_pos)
	if not bool(ship_b.get("is_sunk")) and not bool(ship_a.get("is_sunk")):
		_apply_ram_strike(ship_b, id_b, ship_a, id_a, approach_b, ram_b, stats_a, impact_pos)


func _apply_ram_strike(
	attacker: Node,
	attacker_id: int,
	defender: Node,
	defender_id: int,
	approach: float,
	ram_bonus: float,
	defender_stats: Contracts.ShipStats,
	impact_pos: Vector2
) -> void:
	if approach < 12.0 and not (ram_bonus > 0.0 and approach > 4.0):
		return
	var raw_dmg: float = clampf(approach * 0.24, 5.0, 24.0) + ram_bonus
	var armor: float = defender_stats.armor if defender_stats != null else 0.0
	_apply_direct_damage(defender, defender_id, maxf(4.0, raw_dmg - armor * 0.45), impact_pos, attacker_id)
	if ram_bonus <= 0.0 and not bool(attacker.get("is_sunk")):
		_apply_direct_damage(attacker, attacker_id, 4.0, impact_pos, defender_id)


# ==============================================================================
# COASTAL FORTS (Delegated to FortDefenseSystem)
# ==============================================================================

func setup_island_forts(world_map: Node) -> void:
	_fort_defense.setup_island_forts(world_map, _rng)


func step_forts(delta: float, p_ships: Dictionary = {}) -> void:
	var active_dict: Dictionary = p_ships if not p_ships.is_empty() else ships
	var new_shots: Array[Dictionary] = _fort_defense.step_forts(delta, active_dict)
	var bus := _bus()
	for shot_data in new_shots:
		shot_data["shot_id"] = _next_shot_id
		_next_shot_id += 1
		projectiles.append(shot_data)
		if bus != null:
			bus.cannonball_spawned.emit(shot_data)


func get_fort_sync_array() -> Array:
	return _fort_defense.get_fort_sync_array()


func apply_fort_sync_array(raw_forts: Array) -> void:
	_fort_defense.apply_fort_sync_array(raw_forts)


func get_fort_sync_revision() -> int:
	return _fort_defense.sync_revision


# ==============================================================================
# HIT RESOLUTION & DAMAGE
# ==============================================================================

func _apply_ship_hit(proj: Dictionary, target: Node, target_id: int, impact_pos: Vector2, hit_zone: String) -> void:
	var zone_mult: float = 1.10 if hit_zone == "bow" else (1.25 if hit_zone == "stern" else 1.0)
	var stats: Contracts.ShipStats = target.get("stats")
	var armor: float = stats.armor if stats != null else 0.0
	var dmg: float = maxf(2.0, float(proj["damage"]) * zone_mult - armor * 0.65)

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
		_apply_harpoon_pull(proj, target, impact_pos, harpoon_pull, chain_slow)

	_apply_direct_damage(target, target_id, dmg, impact_pos, int(proj.get("shooter_id", -1)), is_powder_crit)


func _apply_harpoon_pull(proj: Dictionary, target: Node, impact_pos: Vector2, harpoon_pull: float, chain_slow: float) -> void:
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


func _apply_direct_damage(target: Node, target_id: int, dmg: float, impact_pos: Vector2, attacker_id: int, is_powder_crit: bool = false) -> void:
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
		if bus != null:
			bus.ship_sunk.emit(target_id, target.get("world_pos"), int(target.get("faction")), attacker_id)


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
			_apply_direct_damage(ship, sid, float(b["dps"]) * 0.5, ship.get("world_pos"), -1, false)
		if float(b["timer"]) <= 0.0:
			_burn_fallback.erase(sid)


func _check_sea_monster_hit(proj: Dictionary, prev_pos: Vector2, next_pos: Vector2) -> bool:
	if _sea_monster_targets.is_empty() or int(proj.get("shooter_id", -1)) <= 0:
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
				var zone: String = "bow" if local_pt.x > 10.0 else ("stern" if local_pt.x < -10.0 else "midships")
				return { "hit": true, "target": ship, "target_id": sid, "zone": zone }
	return { "hit": false }


func _compute_cannon_reload(c: Dictionary, side_reload_mult: float) -> float:
	if c.has("effective_reload_time"):
		return float(c["effective_reload_time"])
	if c.has("synergy_mult"):
		return maxf(0.35, float(c.get("reload_time", 2.8)))
	return maxf(0.35, float(c.get("reload_time", 2.8)) / side_reload_mult)


func _resolve_muzzle_offset(c: Dictionary, index: int, count: int, is_starboard: bool) -> Vector2:
	if c.has("local_offset") and c["local_offset"] is Vector2:
		return c["local_offset"]
	if c.has("deck_offset_x"):
		return Vector2(float(c["deck_offset_x"]), 9.0 if is_starboard else -9.0)
	var t: float = 0.0 if count == 1 else (float(index) / float(count - 1) - 0.5) * 2.0
	return Vector2(t * 11.0, 9.0 if is_starboard else -9.0)


func _get_effective_cannons(ship: Node, is_starboard: bool) -> Array:
	var stats: Contracts.ShipStats = ship.get("stats")
	if stats != null:
		var mounted: Array = stats.starboard_cannons if is_starboard else stats.port_cannons
		if not mounted.is_empty():
			return mounted
	if int(ship.get("faction")) == Contracts.ShipFaction.PLAYER:
		return []
	var y_off: float = 8.0 if is_starboard else -8.0
	return [
		{ "damage": 12.0, "reload_time": 2.9, "cannon_range": 235.0, "projectile_speed": 215.0, "spread_angle_deg": 7.0, "chain_shot_slow": 0.0, "local_offset": Vector2(-7.0, y_off) },
		{ "damage": 12.0, "reload_time": 2.9, "cannon_range": 235.0, "projectile_speed": 215.0, "spread_angle_deg": 7.0, "chain_shot_slow": 0.0, "local_offset": Vector2(7.0, y_off) }
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

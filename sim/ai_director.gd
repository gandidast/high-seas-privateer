class_name AIDirector
extends Node
## Manages AI merchants, treasure galleon convoys, pirate sloops, Royal Navy
## frigates (driven by Wanted Level 1..3), bounty bosses, and the Giant Kraken
## sea-monster boss event. 100% headless-safe.

const SHIP_PHYSICS_PATH: String = "res://sim/ship_physics.gd"

const OPTIMAL_RANGE_MIN: float = 140.0
const OPTIMAL_RANGE_MAX: float = 210.0
const PIRATE_AGGRO_RANGE: float = 430.0
const NAVY_AGGRO_RANGE: float = 760.0
const BOSS_AGGRO_RANGE: float = 580.0
const FLEE_HP_RATIO: float = 0.30
const WRECK_DESPAWN_DELAY: float = 4.0
const KRAKEN_MAX_HP: float = 320.0
const KRAKEN_ATTACK_RANGE: float = 115.0

var world_map_ref: Node = null
var combat_system_ref: CombatSystem = null
var ai_ships: Dictionary = {}      # ship_id (int) -> ShipPhysics Node
var ai_brains: Dictionary = {}     # ship_id (int) -> Dictionary
var sea_monster: Dictionary = {}   # Active Giant Kraken state
var wanted_level: int = 0          # 0..3 Royal Navy wanted stars

var target_merchant_count: int = 4
var target_pirate_count: int = 4

var _next_ai_ship_id: int = 1000
var _next_monster_id: int = 5000
var _respawn_timer: float = 10.0
var _monster_respawn_timer: float = 45.0
var _monster_emit_accum: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _ship_physics_script: Script = null


func _bus() -> Contracts:
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		return st.root.get_node_or_null("EventBus") as Contracts
	return null


func _ready() -> void:
	_rng.randomize()
	if ResourceLoader.exists(SHIP_PHYSICS_PATH):
		_ship_physics_script = load(SHIP_PHYSICS_PATH) as Script
	var bus := _bus()
	if bus != null:
		if not bus.ship_damaged.is_connected(_on_ship_damaged):
			bus.ship_damaged.connect(_on_ship_damaged)
		if not bus.ship_sunk.is_connected(_on_ship_sunk):
			bus.ship_sunk.connect(_on_ship_sunk)
		if not bus.fort_destroyed.is_connected(_on_fort_destroyed):
			bus.fort_destroyed.connect(_on_fort_destroyed)


func setup(p_world_map: Node, p_combat_system: CombatSystem) -> void:
	world_map_ref = p_world_map
	combat_system_ref = p_combat_system


func get_ship_ai_state(ship_id: int) -> int:
	if ai_brains.has(ship_id):
		return int(ai_brains[ship_id].get("state", Contracts.AIState.PATROL))
	return Contracts.AIState.PATROL


func set_wanted_level(new_level: int) -> void:
	var clamped: int = clampi(new_level, 0, 3)
	if clamped == wanted_level:
		return
	wanted_level = clamped
	var bus := _bus()
	if bus != null:
		bus.wanted_level_changed.emit(wanted_level)


func increase_wanted_level(amount: int = 1) -> void:
	var prev: int = wanted_level
	set_wanted_level(wanted_level + amount)
	if wanted_level > prev and wanted_level >= 1:
		var pos: Vector2 = _pick_spawn_away_from_players(ai_ships)
		spawn_ai_ship(Contracts.ShipFaction.NAVY, pos, false, "", Contracts.ShipClass.FRIGATE, false)
		var bus := _bus()
		if bus != null:
			bus.notification_posted.emit("Fahndungsstufe %d! Königliche Marine-Fregatte läuft aus!" % wanted_level, "combat")


func clear_all() -> void:
	var bus := _bus()
	for sid_var in ai_ships.keys():
		var sid: int = int(sid_var)
		if combat_system_ref != null:
			combat_system_ref.unregister_ship(sid)
		var ship: Node = ai_ships[sid_var]
		if is_instance_valid(ship):
			ship.queue_free()
		if bus != null:
			bus.ship_despawned.emit(sid)
	ai_ships.clear()
	ai_brains.clear()
	if not sea_monster.is_empty() and combat_system_ref != null:
		combat_system_ref.unregister_sea_monster(int(sea_monster.get("monster_id", 0)))
	sea_monster.clear()
	wanted_level = 0
	_next_ai_ship_id = 1000
	_next_monster_id = 5000
	_monster_respawn_timer = 45.0


func populate_initial_fleet(merchant_count: int = 4, pirate_count: int = 4) -> void:
	target_merchant_count = merchant_count
	target_pirate_count = pirate_count

	var islands: Array = _get_islands()
	for i in range(merchant_count):
		var isl_idx: int = i % maxi(1, islands.size())
		var spawn_pos: Vector2 = Vector2(220.0 * cos(float(i) * 1.5), 220.0 * sin(float(i) * 1.5))
		if not islands.is_empty():
			var isl: Contracts.IslandData = islands[isl_idx]
			spawn_pos = _find_safe_water(isl.harbor_pos + Vector2(60.0, 0.0).rotated(float(i) * 1.3))
		var is_galleon: bool = (i == 0)
		var tier: int = Contracts.ShipClass.FRIGATE if is_galleon else Contracts.ShipClass.SLOOP
		spawn_ai_ship(Contracts.ShipFaction.MERCHANT, spawn_pos, false, "", tier, is_galleon)

	for j in range(pirate_count):
		var angle: float = float(j) * (TAU / maxf(1.0, float(pirate_count))) + 0.7
		var raw_pos := Vector2(cos(angle), sin(angle)) * _rng.randf_range(340.0, 560.0)
		var spawn_pos: Vector2 = _find_safe_water(raw_pos)
		var p_tier: int = Contracts.ShipClass.BRIGANTINE if j == 0 else Contracts.ShipClass.SLOOP
		spawn_ai_ship(Contracts.ShipFaction.PIRATE, spawn_pos, false, "", p_tier, false)


func spawn_ai_ship(
	faction: int,
	pos: Vector2,
	is_bounty_boss: bool = false,
	boss_name: String = "",
	hull_tier: int = -1,
	is_treasure_galleon: bool = false
) -> int:
	if _ship_physics_script == null and ResourceLoader.exists(SHIP_PHYSICS_PATH):
		_ship_physics_script = load(SHIP_PHYSICS_PATH) as Script
	if _ship_physics_script == null:
		return -1

	var sid: int = _next_ai_ship_id
	_next_ai_ship_id += 1

	var effective_tier: int = hull_tier
	if effective_tier < 0:
		if faction == Contracts.ShipFaction.NAVY or is_treasure_galleon:
			effective_tier = Contracts.ShipClass.FRIGATE
		elif is_bounty_boss:
			effective_tier = Contracts.ShipClass.BRIGANTINE
		else:
			effective_tier = Contracts.ShipClass.SLOOP
	effective_tier = clampi(effective_tier, Contracts.ShipClass.SLOOP, Contracts.ShipClass.FRIGATE)

	var ship: Node = _ship_physics_script.new()
	var ship_label: String = boss_name
	if ship_label.is_empty():
		match faction:
			Contracts.ShipFaction.MERCHANT:
				if is_treasure_galleon:
					var g_names: Array[String] = ["Schatz-Galeone El Dorado", "Gold-Konvoi San Mateo", "Kron-Galeone Fortuna"]
					ship_label = g_names[sid % g_names.size()]
				else:
					var m_names: Array[String] = ["Kauffahrer Aurelia", "Hanse-Brigg", "Gewürz-Karavelle", "Silber-Kogge"]
					ship_label = m_names[sid % m_names.size()]
			Contracts.ShipFaction.NAVY:
				var n_names: Array[String] = ["HMS Sovereign", "Kron-Fregatte Valiant", "Admiralitäts-Galeone"]
				ship_label = n_names[sid % n_names.size()]
			_:
				var p_names: Array[String] = ["Rote Schaluppe", "Korsar-Kutter", "Sturmfalke", "Schwarzsegler"]
				ship_label = p_names[sid % p_names.size()]

	var safe_pos: Vector2 = _find_safe_water(pos)
	var heading: float = _rng.randf_range(-PI, PI)
	ship.call("setup", sid, safe_pos, heading, faction, ship_label)
	ship.set("sail_state", Contracts.SailState.HALF_SAIL)
	if ship.has_method("upgrade_ship_class"):
		ship.call("upgrade_ship_class", effective_tier)
	ship.set_meta("is_treasure_galleon", is_treasure_galleon)
	ship.set_meta("hull_tier", effective_tier)

	var stats := _build_ai_stats(faction, is_bounty_boss, effective_tier, is_treasure_galleon)
	ship.call("apply_stats", stats)
	ship.set("hp", stats.max_hp)
	ship.set("max_hp", stats.max_hp)

	add_child(ship)
	ai_ships[sid] = ship

	var islands: Array = _get_islands()
	var wp_idx: int = _rng.randi_range(0, maxi(0, islands.size() - 1))
	var wp_pos: Vector2 = islands[wp_idx].harbor_pos if not islands.is_empty() else Vector2(300.0, 0.0)

	ai_brains[sid] = {
		"state": Contracts.AIState.PATROL,
		"target_id": -1,
		"attacker_id": -1,
		"under_fire_timer": 0.0,
		"waypoint_idx": wp_idx,
		"waypoint_pos": wp_pos,
		"is_bounty_boss": is_bounty_boss,
		"is_treasure_galleon": is_treasure_galleon,
		"hull_tier": effective_tier,
		"wreck_timer": -1.0,
		"preferred_side": 1 if _rng.randf() > 0.5 else -1
	}

	if combat_system_ref != null:
		combat_system_ref.register_ship(ship)

	var bus := _bus()
	if bus != null:
		bus.ship_spawned.emit(sid, {
			"ship_id": sid,
			"faction": faction,
			"name": ship_label,
			"world_pos": safe_pos,
			"heading": heading,
			"is_bounty_boss": is_bounty_boss,
			"hull_tier": effective_tier,
			"is_treasure_galleon": is_treasure_galleon
		})
		bus.ship_stats_compiled.emit(sid, stats)
	return sid


func step_ai(delta: float, all_ships: Dictionary) -> void:
	var to_despawn: Array[int] = []

	for sid_var in ai_ships.keys():
		var sid: int = int(sid_var)
		var ship: Node = ai_ships[sid_var]
		var brain: Dictionary = ai_brains.get(sid, {})
		if ship == null or brain.is_empty():
			to_despawn.append(sid)
			continue

		if bool(ship.get("is_sunk")):
			var w_timer: float = float(brain.get("wreck_timer", -1.0))
			if w_timer < 0.0:
				brain["wreck_timer"] = WRECK_DESPAWN_DELAY
			else:
				w_timer -= delta
				brain["wreck_timer"] = w_timer
				if w_timer <= 0.0:
					to_despawn.append(sid)
			continue

		var under_fire: float = maxf(0.0, float(brain.get("under_fire_timer", 0.0)) - delta)
		brain["under_fire_timer"] = under_fire
		if under_fire <= 0.0:
			brain["attacker_id"] = -1

		_update_state_transitions(sid, ship, brain, all_ships)
		var steer: float = _execute_state(sid, ship, brain, all_ships, delta)

		if world_map_ref != null:
			ship.call("step_physics", delta, steer, world_map_ref)

	for sid in to_despawn:
		_despawn_ai_ship(sid)

	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = 18.0
		_maintain_population(all_ships)


# ==============================================================================
# GIANT KRAKEN / SEA MONSTER BOSS EVENT
# ==============================================================================

func spawn_sea_monster(world_pos: Vector2) -> int:
	if not sea_monster.is_empty() and not bool(sea_monster.get("defeated", false)):
		return int(sea_monster.get("monster_id", -1))

	var mid: int = _next_monster_id
	_next_monster_id += 1
	var safe_pos: Vector2 = _find_safe_water(world_pos)

	sea_monster = {
		"monster_id": mid,
		"world_pos": safe_pos,
		"hp": KRAKEN_MAX_HP,
		"max_hp": KRAKEN_MAX_HP,
		"phase": 0,
		"attack_timer": 2.4,
		"slam_timer": 0.0,
		"speed": 54.0,
		"radius": 32.0,
		"defeated": false
	}

	if combat_system_ref != null:
		combat_system_ref.register_sea_monster(mid, safe_pos, 32.0, Callable(self, "damage_sea_monster"))

	var bus := _bus()
	if bus != null:
		bus.sea_monster_spawned.emit(mid, safe_pos, KRAKEN_MAX_HP)
		bus.sea_monster_updated.emit(mid, safe_pos, KRAKEN_MAX_HP, KRAKEN_MAX_HP, 0)
		bus.notification_posted.emit("Seeungeheuer! Ein Riesenkraken taucht aus der Tiefe auf!", "combat")
	return mid


func step_sea_monster(delta: float, ships: Dictionary) -> void:
	if delta <= 0.0:
		return

	if sea_monster.is_empty() or bool(sea_monster.get("defeated", false)):
		_monster_respawn_timer -= delta
		if _monster_respawn_timer <= 0.0:
			_monster_respawn_timer = 85.0
			var spawn_pos: Vector2 = _pick_spawn_away_from_players(ships)
			spawn_sea_monster(spawn_pos)
		return

	var mid: int = int(sea_monster["monster_id"])
	var mpos: Vector2 = sea_monster["world_pos"]
	var hp: float = float(sea_monster["hp"])
	var max_hp: float = float(sea_monster["max_hp"])
	var enraged: bool = hp <= max_hp * 0.50

	var slam_t: float = maxf(0.0, float(sea_monster.get("slam_timer", 0.0)) - delta)
	sea_monster["slam_timer"] = slam_t

	# Find nearest non-sunk target ship (prefer player)
	var target_ship: Node = null
	var best_dist_sq: float = 950.0 * 950.0
	for s_var in ships.values():
		var s: Node = s_var
		if s == null or bool(s.get("is_sunk")):
			continue
		var spos: Vector2 = s.get("world_pos")
		var d_sq: float = mpos.distance_squared_to(spos)
		var weighted: float = d_sq * (0.6 if int(s.get("faction")) == Contracts.ShipFaction.PLAYER else 1.0)
		if weighted < best_dist_sq:
			best_dist_sq = weighted
			target_ship = s

	if target_ship != null:
		var tpos: Vector2 = target_ship.get("world_pos")
		var to_t: Vector2 = tpos - mpos
		var dist: float = to_t.length()
		if dist > 42.0:
			var move_speed: float = 70.0 if enraged else 54.0
			var step_dir: Vector2 = to_t / dist
			var cand: Vector2 = mpos + step_dir * move_speed * delta
			if _get_depth(cand) > 0.08:
				mpos = cand
			else:
				var perp: Vector2 = step_dir.rotated(PI * 0.45)
				var cand_alt: Vector2 = mpos + perp * move_speed * delta
				if _get_depth(cand_alt) > 0.08:
					mpos = cand_alt

	sea_monster["world_pos"] = mpos
	if combat_system_ref != null:
		combat_system_ref.update_sea_monster_pos(mid, mpos)

	# Tentacle / whirlpool slam attack
	var atk_t: float = float(sea_monster.get("attack_timer", 2.5)) - delta
	if atk_t <= 0.0:
		var hit_any: bool = false
		var range_sq: float = KRAKEN_ATTACK_RANGE * KRAKEN_ATTACK_RANGE
		var bus := _bus()
		for s_var in ships.values():
			var s: Node = s_var
			if s == null or bool(s.get("is_sunk")):
				continue
			var spos: Vector2 = s.get("world_pos")
			if mpos.distance_squared_to(spos) <= range_sq:
				hit_any = true
				var stats: Contracts.ShipStats = s.get("stats")
				var armor: float = stats.armor if stats != null else 0.0
				var dmg: float = maxf(8.0, (24.0 if enraged else 18.0) - armor * 0.45)
				var cur_hp: float = float(s.get("hp"))
				var s_max_hp: float = float(s.get("max_hp"))
				var next_hp: float = maxf(0.0, cur_hp - dmg)
				s.set("hp", next_hp)
				if s.has_method("apply_chain_slow"):
					s.call("apply_chain_slow", 2.4, 0.45)
				var sid: int = int(s.get("ship_id"))
				if bus != null:
					bus.cannonball_impact.emit(spos, sid, dmg, false, false)
					bus.ship_damaged.emit(sid, dmg, next_hp, s_max_hp, spos)
				if next_hp <= 0.0:
					s.set("is_sunk", true)
					if bus != null:
						bus.ship_sunk.emit(sid, spos, int(s.get("faction")), -mid)
		if hit_any:
			sea_monster["slam_timer"] = 0.65
			atk_t = 2.4 if enraged else 3.2
		else:
			atk_t = 0.45
	sea_monster["attack_timer"] = atk_t

	var phase: int = 1 if float(sea_monster.get("slam_timer", 0.0)) > 0.0 else (2 if enraged else 0)
	sea_monster["phase"] = phase

	_monster_emit_accum += delta
	if _monster_emit_accum >= 0.10:
		_monster_emit_accum = 0.0
		var bus := _bus()
		if bus != null:
			bus.sea_monster_updated.emit(mid, mpos, hp, max_hp, phase)


func damage_sea_monster(monster_id: int, damage: float) -> void:
	if sea_monster.is_empty() or bool(sea_monster.get("defeated", false)):
		return
	if int(sea_monster.get("monster_id", -1)) != monster_id:
		return

	var hp: float = maxf(0.0, float(sea_monster["hp"]) - maxf(1.0, damage))
	var max_hp: float = float(sea_monster["max_hp"])
	var mpos: Vector2 = sea_monster["world_pos"]
	sea_monster["hp"] = hp

	var bus := _bus()
	if hp <= 0.0:
		sea_monster["defeated"] = true
		_monster_respawn_timer = 90.0
		if combat_system_ref != null:
			combat_system_ref.unregister_sea_monster(monster_id)
		if bus != null:
			bus.sea_monster_updated.emit(monster_id, mpos, 0.0, max_hp, 2)
			bus.sea_monster_defeated.emit(monster_id, mpos)
			bus.notification_posted.emit("Riesenkraken besiegt! Legendäres Kraken-Juwel geborgen!", "combat")
	else:
		var phase: int = 2 if hp <= max_hp * 0.50 else int(sea_monster.get("phase", 0))
		sea_monster["phase"] = phase
		if bus != null:
			bus.sea_monster_updated.emit(monster_id, mpos, hp, max_hp, phase)


func get_sea_monster_sync_dict() -> Dictionary:
	if sea_monster.is_empty():
		return {}
	var pos: Vector2 = sea_monster.get("world_pos", Vector2.ZERO)
	return {
		"monster_id": int(sea_monster.get("monster_id", 0)),
		"x": pos.x,
		"y": pos.y,
		"hp": float(sea_monster.get("hp", 0.0)),
		"max_hp": float(sea_monster.get("max_hp", KRAKEN_MAX_HP)),
		"phase": int(sea_monster.get("phase", 0)),
		"defeated": bool(sea_monster.get("defeated", true))
	}


# ==============================================================================
# AI STATE MACHINE & STEERING
# ==============================================================================

func _update_state_transitions(
	_sid: int,
	ship: Node,
	brain: Dictionary,
	all_ships: Dictionary
) -> void:
	var faction: int = int(ship.get("faction"))
	var hp: float = float(ship.get("hp"))
	var max_hp: float = maxf(1.0, float(ship.get("max_hp")))
	var hp_ratio: float = hp / max_hp
	var is_boss: bool = bool(brain.get("is_bounty_boss", false))
	var state: int = int(brain.get("state", Contracts.AIState.PATROL))
	var ship_pos: Vector2 = ship.get("world_pos")

	var flee_thresh: float = 0.15 if (is_boss or faction == Contracts.ShipFaction.NAVY) else FLEE_HP_RATIO
	if hp_ratio < flee_thresh:
		brain["state"] = Contracts.AIState.FLEE_TO_PORT
		return

	var under_fire: float = float(brain.get("under_fire_timer", 0.0))
	if faction == Contracts.ShipFaction.MERCHANT and under_fire > 0.0:
		brain["state"] = Contracts.AIState.FLEE_TO_PORT
		return

	if state == Contracts.AIState.FLEE_TO_PORT:
		if hp_ratio >= 0.70 and under_fire <= 0.0:
			brain["state"] = Contracts.AIState.PATROL
		return

	# Target acquisition for Pirates, Bounty Bosses, and Royal Navy Frigates
	if faction == Contracts.ShipFaction.PIRATE or faction == Contracts.ShipFaction.NAVY or is_boss:
		var aggro_range: float = PIRATE_AGGRO_RANGE
		if faction == Contracts.ShipFaction.NAVY:
			aggro_range = NAVY_AGGRO_RANGE
		elif is_boss:
			aggro_range = BOSS_AGGRO_RANGE

		var best_target: Node = null
		var best_dist_sq: float = aggro_range * aggro_range

		var attacker_id: int = int(brain.get("attacker_id", -1))
		if attacker_id != -1 and all_ships.has(attacker_id):
			var atk: Node = all_ships[attacker_id]
			if atk != null and not bool(atk.get("is_sunk")):
				var d_sq: float = ship_pos.distance_squared_to(atk.get("world_pos"))
				if d_sq <= (aggro_range * 1.4) * (aggro_range * 1.4):
					best_target = atk

		if best_target == null:
			for other_var in all_ships.values():
				var other: Node = other_var
				if other == null or other == ship or bool(other.get("is_sunk")):
					continue
				var other_faction: int = int(other.get("faction"))
				if other_faction == faction:
					continue
				if faction == Contracts.ShipFaction.NAVY and other_faction == Contracts.ShipFaction.MERCHANT:
					continue
				var d_sq: float = ship_pos.distance_squared_to(other.get("world_pos"))
				var weight: float = 1.0
				if other_faction == Contracts.ShipFaction.PLAYER:
					weight = 0.45 if faction == Contracts.ShipFaction.NAVY else 0.75
				var weighted_d_sq: float = d_sq * weight
				if weighted_d_sq < best_dist_sq:
					best_dist_sq = weighted_d_sq
					best_target = other

		if best_target != null:
			brain["target_id"] = int(best_target.get("ship_id"))
			brain["state"] = Contracts.AIState.ENGAGE_BROADSIDE
		else:
			brain["target_id"] = -1
			brain["state"] = Contracts.AIState.PATROL


func _execute_state(
	sid: int,
	ship: Node,
	brain: Dictionary,
	all_ships: Dictionary,
	delta: float
) -> float:
	var state: int = int(brain.get("state", Contracts.AIState.PATROL))
	var ship_pos: Vector2 = ship.get("world_pos")
	var heading: float = float(ship.get("heading"))
	var desired_angle: float = heading

	match state:
		Contracts.AIState.PATROL:
			ship.call("set_sail_state", Contracts.SailState.HALF_SAIL)
			var wp: Vector2 = brain.get("waypoint_pos", Vector2.ZERO)
			if ship_pos.distance_to(wp) < 110.0:
				_pick_next_patrol_waypoint(brain)
				wp = brain.get("waypoint_pos", Vector2.ZERO)
			desired_angle = (wp - ship_pos).angle()

		Contracts.AIState.ENGAGE_BROADSIDE:
			var tid: int = int(brain.get("target_id", -1))
			var target: Node = all_ships.get(tid, null)
			if target == null or bool(target.get("is_sunk")):
				brain["state"] = Contracts.AIState.PATROL
				return 0.0

			var t_pos: Vector2 = target.get("world_pos")
			var t_vel: Vector2 = target.get("velocity")
			var s_vel: Vector2 = ship.get("velocity")
			var dist: float = ship_pos.distance_to(t_pos)

			var intercept_dir: Vector2 = CombatSystem.compute_intercept_direction(
				ship_pos, s_vel, t_pos, t_vel, 220.0
			)
			var to_target_angle: float = intercept_dir.angle()

			if dist > OPTIMAL_RANGE_MAX + 25.0:
				ship.call("set_sail_state", Contracts.SailState.FULL_SAIL)
				desired_angle = to_target_angle
			elif dist < OPTIMAL_RANGE_MIN - 20.0:
				ship.call("set_sail_state", Contracts.SailState.HALF_SAIL)
				desired_angle = to_target_angle + float(brain.get("preferred_side", 1)) * 1.15
			else:
				ship.call("set_sail_state", Contracts.SailState.HALF_SAIL)
				var cand_starboard: float = wrapf(to_target_angle - PI * 0.5, -PI, PI)
				var cand_port: float = wrapf(to_target_angle + PI * 0.5, -PI, PI)
				var diff_sb: float = absf(wrapf(cand_starboard - heading, -PI, PI))
				var diff_pt: float = absf(wrapf(cand_port - heading, -PI, PI))
				desired_angle = cand_starboard if diff_sb <= diff_pt else cand_port

			_try_fire_at_target(sid, ship, intercept_dir, dist)

		Contracts.AIState.FLEE_TO_PORT:
			ship.call("set_sail_state", Contracts.SailState.FULL_SAIL)
			var harbor_pos: Vector2 = _get_nearest_harbor_pos(ship_pos)
			var dist_harbor: float = ship_pos.distance_to(harbor_pos)
			if dist_harbor < 58.0:
				ship.call("set_sail_state", Contracts.SailState.ANCHORED)
				var hp: float = float(ship.get("hp"))
				var max_hp: float = float(ship.get("max_hp"))
				ship.set("hp", minf(max_hp, hp + 6.0 * delta))
			desired_angle = (harbor_pos - ship_pos).angle()

	var avoid_steer: float = _compute_feeler_avoidance(ship_pos, heading)
	if absf(avoid_steer) > 0.05:
		return clampf(avoid_steer, -1.0, 1.0)

	var angle_err: float = wrapf(desired_angle - heading, -PI, PI)
	return clampf(angle_err * 1.8, -1.0, 1.0)


func _try_fire_at_target(
	sid: int,
	ship: Node,
	intercept_dir: Vector2,
	dist: float
) -> void:
	if combat_system_ref == null or dist > 275.0:
		return

	var heading: float = float(ship.get("heading"))
	var port_dir: Vector2 = Vector2.from_angle(heading - PI * 0.5)
	var starboard_dir: Vector2 = Vector2.from_angle(heading + PI * 0.5)

	var port_err: float = wrapf(intercept_dir.angle() - port_dir.angle(), -PI, PI)
	var sb_err: float = wrapf(intercept_dir.angle() - starboard_dir.angle(), -PI, PI)

	if absf(sb_err) <= 0.36:
		var cone_sb: Dictionary = combat_system_ref.get_broadside_cone(sid, true)
		if int(cone_sb.get("ready_count", 0)) > 0:
			combat_system_ref.fire_broadside(sid, true, sb_err)
	elif absf(port_err) <= 0.36:
		var cone_pt: Dictionary = combat_system_ref.get_broadside_cone(sid, false)
		if int(cone_pt.get("ready_count", 0)) > 0:
			combat_system_ref.fire_broadside(sid, false, port_err)


func _compute_feeler_avoidance(pos: Vector2, heading: float) -> float:
	var fwd: Vector2 = Vector2.from_angle(heading)
	var left_dir: Vector2 = Vector2.from_angle(heading - 0.58)
	var right_dir: Vector2 = Vector2.from_angle(heading + 0.58)

	var d_close: float = _get_depth(pos + fwd * 38.0)
	var d_fwd: float = _get_depth(pos + fwd * 85.0)
	var d_left: float = _get_depth(pos + left_dir * 72.0)
	var d_right: float = _get_depth(pos + right_dir * 72.0)

	if absf(pos.x) > Contracts.WORLD_HALF_EXTENT * 0.86 or absf(pos.y) > Contracts.WORLD_HALF_EXTENT * 0.86:
		var center_angle: float = (-pos).angle()
		return clampf(wrapf(center_angle - heading, -PI, PI) * 2.0, -1.0, 1.0)

	if d_close <= 0.03 or d_fwd <= 0.06:
		return -1.0 if d_left > d_right else 1.0

	if d_fwd < 0.14:
		var bias: float = -0.65 if d_left > d_right else 0.65
		return bias

	return 0.0


func _pick_next_patrol_waypoint(brain: Dictionary) -> void:
	var islands: Array = _get_islands()
	if islands.is_empty():
		brain["waypoint_pos"] = Vector2(_rng.randf_range(-500.0, 500.0), _rng.randf_range(-500.0, 500.0))
		return
	var current_idx: int = int(brain.get("waypoint_idx", 0))
	var next_idx: int = (current_idx + _rng.randi_range(1, maxi(1, islands.size() - 1))) % islands.size()
	var isl: Contracts.IslandData = islands[next_idx]
	var jitter := Vector2(_rng.randf_range(-40.0, 40.0), _rng.randf_range(-40.0, 40.0))
	brain["waypoint_idx"] = next_idx
	brain["waypoint_pos"] = _find_safe_water(isl.harbor_pos + jitter)


func _get_nearest_harbor_pos(pos: Vector2) -> Vector2:
	if world_map_ref != null and world_map_ref.has_method("get_nearest_island"):
		var isl: Contracts.IslandData = world_map_ref.call("get_nearest_island", pos)
		if isl != null:
			return isl.harbor_pos
	var islands: Array = _get_islands()
	var best_pos: Vector2 = Vector2.ZERO
	var best_d: float = INF
	for isl in islands:
		var d: float = pos.distance_squared_to(isl.harbor_pos)
		if d < best_d:
			best_d = d
			best_pos = isl.harbor_pos
	return best_pos


func _get_islands() -> Array:
	if world_map_ref != null:
		var arr: Variant = world_map_ref.get("islands")
		if arr is Array and not arr.is_empty():
			return arr
	return Contracts.get_islands()


func _get_depth(pos: Vector2) -> float:
	if world_map_ref != null and world_map_ref.has_method("get_water_depth"):
		return float(world_map_ref.call("get_water_depth", pos))
	return Contracts.get_water_depth(pos)


func _find_safe_water(pos: Vector2) -> Vector2:
	if world_map_ref != null and world_map_ref.has_method("find_open_water_near"):
		return world_map_ref.call("find_open_water_near", pos, 0.18)
	if _get_depth(pos) >= 0.18:
		return pos
	return pos + Contracts.get_coast_normal(pos) * 48.0


func _build_ai_stats(
	faction: int,
	is_bounty_boss: bool,
	hull_tier: int = 0,
	is_treasure_galleon: bool = false
) -> Contracts.ShipStats:
	var stats := Contracts.ShipStats.new()
	stats.hull_tier = hull_tier
	if faction == Contracts.ShipFaction.NAVY:
		stats.base_max_hp = 245.0
		stats.max_hp = 245.0
		stats.armor = 4.0
		stats.base_max_speed = 94.0
		stats.max_speed = 94.0
		stats.turn_speed = 1.65
		stats.port_cannons = _make_ai_cannons(3, 17.0, 2.5, false)
		stats.starboard_cannons = _make_ai_cannons(3, 17.0, 2.5, true)
	elif is_bounty_boss:
		stats.base_max_hp = 220.0
		stats.max_hp = 220.0
		stats.armor = 3.0
		stats.base_max_speed = 92.0
		stats.max_speed = 92.0
		stats.turn_speed = 1.65
		stats.port_cannons = _make_ai_cannons(3, 18.0, 2.5, false)
		stats.starboard_cannons = _make_ai_cannons(3, 18.0, 2.5, true)
	elif faction == Contracts.ShipFaction.MERCHANT:
		if is_treasure_galleon:
			stats.base_max_hp = 225.0
			stats.max_hp = 225.0
			stats.armor = 3.5
			stats.base_max_speed = 70.0
			stats.max_speed = 70.0
			stats.turn_speed = 1.30
			stats.port_cannons = _make_ai_cannons(2, 13.0, 3.0, false)
			stats.starboard_cannons = _make_ai_cannons(2, 13.0, 3.0, true)
		else:
			stats.base_max_hp = 110.0
			stats.max_hp = 110.0
			stats.armor = 1.0
			stats.base_max_speed = 76.0
			stats.max_speed = 76.0
			stats.turn_speed = 1.40
			stats.port_cannons = _make_ai_cannons(1, 10.0, 3.3, false)
			stats.starboard_cannons = _make_ai_cannons(1, 10.0, 3.3, true)
	else:
		var is_brig: bool = hull_tier >= 1
		stats.base_max_hp = 155.0 if is_brig else 105.0
		stats.max_hp = stats.base_max_hp
		stats.armor = 1.5 if is_brig else 0.5
		stats.base_max_speed = 90.0 if is_brig else 88.0
		stats.max_speed = stats.base_max_speed
		stats.turn_speed = 1.68 if is_brig else 1.75
		var c_count: int = 2
		stats.port_cannons = _make_ai_cannons(c_count, 13.0 if is_brig else 12.0, 2.7, false)
		stats.starboard_cannons = _make_ai_cannons(c_count, 13.0 if is_brig else 12.0, 2.7, true)
	return stats


func _make_ai_cannons(count: int, dmg: float, reload_t: float, is_starboard: bool) -> Array:
	var arr: Array = []
	var y_off: float = 8.0 if is_starboard else -8.0
	for i in range(count):
		var t: float = 0.0 if count == 1 else (float(i) / float(count - 1) - 0.5) * 2.0
		arr.append({
			"damage": dmg,
			"reload_time": reload_t,
			"cannon_range": 250.0,
			"projectile_speed": 220.0,
			"spread_angle_deg": 7.0,
			"chain_shot_slow": 0.0,
			"local_offset": Vector2(t * 10.0, y_off)
		})
	return arr


func _maintain_population(all_ships: Dictionary) -> void:
	var merchants: int = 0
	var has_galleon: bool = false
	var pirates: int = 0
	var navy_count: int = 0

	for sid_var in ai_ships.keys():
		var ship: Node = ai_ships[sid_var]
		if ship == null or bool(ship.get("is_sunk")):
			continue
		var fac: int = int(ship.get("faction"))
		var brain: Dictionary = ai_brains.get(int(sid_var), {})
		if bool(brain.get("is_bounty_boss", false)):
			continue
		if fac == Contracts.ShipFaction.MERCHANT:
			merchants += 1
			if bool(brain.get("is_treasure_galleon", false)):
				has_galleon = true
		elif fac == Contracts.ShipFaction.PIRATE:
			pirates += 1
		elif fac == Contracts.ShipFaction.NAVY:
			navy_count += 1

	if merchants < target_merchant_count:
		var pos: Vector2 = _pick_spawn_away_from_players(all_ships)
		var spawn_galleon: bool = not has_galleon
		var m_tier: int = Contracts.ShipClass.FRIGATE if spawn_galleon else Contracts.ShipClass.SLOOP
		spawn_ai_ship(Contracts.ShipFaction.MERCHANT, pos, false, "", m_tier, spawn_galleon)

	if pirates < target_pirate_count:
		var pos: Vector2 = _pick_spawn_away_from_players(all_ships)
		spawn_ai_ship(Contracts.ShipFaction.PIRATE, pos, false, "", Contracts.ShipClass.SLOOP, false)

	if wanted_level >= 1 and navy_count < wanted_level:
		var pos: Vector2 = _pick_spawn_away_from_players(all_ships)
		spawn_ai_ship(Contracts.ShipFaction.NAVY, pos, false, "", Contracts.ShipClass.FRIGATE, false)


func _pick_spawn_away_from_players(all_ships: Dictionary) -> Vector2:
	for _i in range(16):
		var ang: float = _rng.randf_range(-PI, PI)
		var dist: float = _rng.randf_range(380.0, 720.0)
		var candidate := Vector2(cos(ang), sin(ang)) * dist
		if _get_depth(candidate) < 0.22:
			continue
		var too_close: bool = false
		for ship_var in all_ships.values():
			var s: Node = ship_var
			if s != null and int(s.get("faction")) == Contracts.ShipFaction.PLAYER:
				if candidate.distance_to(s.get("world_pos")) < 280.0:
					too_close = true
					break
		if not too_close:
			return candidate
	return _find_safe_water(Vector2(380.0, -240.0))


func _despawn_ai_ship(sid: int) -> void:
	if combat_system_ref != null:
		combat_system_ref.unregister_ship(sid)
	var ship: Node = ai_ships.get(sid, null)
	ai_ships.erase(sid)
	ai_brains.erase(sid)
	if is_instance_valid(ship):
		ship.queue_free()
	var bus := _bus()
	if bus != null:
		bus.ship_despawned.emit(sid)


func _on_ship_damaged(
	ship_id: int,
	_damage: float,
	_new_hp: float,
	_max_hp: float,
	_world_pos: Vector2
) -> void:
	if ai_brains.has(ship_id):
		ai_brains[ship_id]["under_fire_timer"] = 8.0


func _on_ship_sunk(
	ship_id: int,
	_world_pos: Vector2,
	faction: int,
	killer_ship_id: int
) -> void:
	if ai_brains.has(ship_id):
		ai_brains[ship_id]["wreck_timer"] = WRECK_DESPAWN_DELAY

	if faction == Contracts.ShipFaction.PLAYER:
		# Reset wanted level when player sinks
		if wanted_level > 0:
			set_wanted_level(0)
		return

	# Sinking merchants or Royal Navy ships raises Wanted Level if sunk by a player
	if killer_ship_id > 0 and not ai_ships.has(killer_ship_id):
		if faction == Contracts.ShipFaction.MERCHANT or faction == Contracts.ShipFaction.NAVY:
			increase_wanted_level(1)


func _on_fort_destroyed(_fort_id: int, _world_pos: Vector2) -> void:
	increase_wanted_level(1)

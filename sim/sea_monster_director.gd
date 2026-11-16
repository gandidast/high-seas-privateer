class_name SeaMonsterDirector
extends RefCounted
## Manages the Giant Kraken sea-monster boss FSM: spawning, deep-water pursuit,
## tentacle slam attacks, enraged phase, damage/defeat, and revision-tracked sync.
## 100% headless-safe.

const KRAKEN_MAX_HP: float = 320.0
const KRAKEN_ATTACK_RANGE: float = 115.0
const KRAKEN_RESPAWN_SECONDS: float = 110.0
const HARBOR_SAFE_MARGIN: float = 210.0

var sea_monster: Dictionary = {}
var sync_revision: int = 1

var _next_monster_id: int = 5000
var _respawn_timer: float = 45.0
var _emit_accum: float = 0.0


func _bus() -> Contracts:
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		return st.root.get_node_or_null("EventBus") as Contracts
	return null


func clear(combat_system_ref: CombatSystem) -> void:
	if not sea_monster.is_empty():
		if combat_system_ref != null:
			combat_system_ref.unregister_sea_monster(int(sea_monster.get("monster_id", 0)))
		sync_revision += 1
	sea_monster.clear()
	_next_monster_id = 5000
	_respawn_timer = 45.0
	_emit_accum = 0.0


func spawn_sea_monster(
	world_pos: Vector2,
	combat_system_ref: CombatSystem,
	damage_cb: Callable,
	safe_water_pos: Vector2
) -> int:
	if not sea_monster.is_empty() and not bool(sea_monster.get("defeated", false)):
		return int(sea_monster.get("monster_id", -1))

	var mid: int = _next_monster_id
	_next_monster_id += 1

	sea_monster.clear()
	sea_monster["monster_id"] = mid
	sea_monster["world_pos"] = safe_water_pos
	sea_monster["hp"] = KRAKEN_MAX_HP
	sea_monster["max_hp"] = KRAKEN_MAX_HP
	sea_monster["phase"] = 0
	sea_monster["attack_timer"] = 2.4
	sea_monster["slam_timer"] = 0.0
	sea_monster["speed"] = 54.0
	sea_monster["radius"] = 32.0
	sea_monster["defeated"] = false
	sync_revision += 1

	if combat_system_ref != null:
		combat_system_ref.register_sea_monster(mid, safe_water_pos, 32.0, damage_cb)

	var bus := _bus()
	if bus != null:
		bus.sea_monster_spawned.emit(mid, safe_water_pos, KRAKEN_MAX_HP)
		bus.sea_monster_updated.emit(mid, safe_water_pos, KRAKEN_MAX_HP, KRAKEN_MAX_HP, 0)
		bus.notification_posted.emit("Seeungeheuer! Ein Riesenkraken taucht aus der Tiefe auf!", "combat")
	return mid


func step_sea_monster(
	delta: float,
	ships: Dictionary,
	combat_system_ref: CombatSystem,
	depth_fn: Callable,
	pick_spawn_fn: Callable,
	damage_cb: Callable
) -> void:
	if delta <= 0.0:
		return

	if sea_monster.is_empty() or bool(sea_monster.get("defeated", false)):
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn_timer = KRAKEN_RESPAWN_SECONDS
			var spawn_pos: Vector2 = pick_spawn_fn.call(ships)
			spawn_pos = _nudge_away_from_safe_harbors(spawn_pos, depth_fn)
			spawn_sea_monster(spawn_pos, combat_system_ref, damage_cb, spawn_pos)
		return

	var mid: int = int(sea_monster["monster_id"])
	var prev_pos: Vector2 = sea_monster["world_pos"]
	var mpos: Vector2 = prev_pos
	var hp: float = float(sea_monster["hp"])
	var max_hp: float = float(sea_monster["max_hp"])
	var enraged: bool = hp <= max_hp * 0.50

	var slam_t: float = maxf(0.0, float(sea_monster.get("slam_timer", 0.0)) - delta)
	sea_monster["slam_timer"] = slam_t

	var target_ship: Node = _find_nearest_target(mpos, ships)
	if target_ship != null:
		var tpos: Vector2 = target_ship.get("world_pos")
		var to_t: Vector2 = tpos - mpos
		var dist: float = to_t.length()
		if dist > 42.0:
			var move_speed: float = 70.0 if enraged else 54.0
			var step_dir: Vector2 = to_t / dist
			var cand: Vector2 = mpos + step_dir * move_speed * delta
			if float(depth_fn.call(cand)) > 0.08 and not _is_near_safe_harbor(cand, HARBOR_SAFE_MARGIN):
				mpos = cand
			else:
				var cand_alt: Vector2 = mpos + step_dir.rotated(PI * 0.45) * move_speed * delta
				if float(depth_fn.call(cand_alt)) > 0.08 and not _is_near_safe_harbor(cand_alt, HARBOR_SAFE_MARGIN):
					mpos = cand_alt

	sea_monster["world_pos"] = mpos
	if combat_system_ref != null:
		combat_system_ref.update_sea_monster_pos(mid, mpos)

	var atk_t: float = float(sea_monster.get("attack_timer", 2.5)) - delta
	if atk_t <= 0.0:
		var hit_any: bool = _perform_tentacle_slam(mid, mpos, enraged, ships)
		if hit_any:
			sea_monster["slam_timer"] = 0.65
			atk_t = 2.4 if enraged else 3.2
		else:
			atk_t = 0.45
	sea_monster["attack_timer"] = atk_t

	var prev_phase: int = int(sea_monster.get("phase", 0))
	var phase: int = 1 if float(sea_monster.get("slam_timer", 0.0)) > 0.0 else (2 if enraged else 0)
	sea_monster["phase"] = phase

	if prev_pos.distance_squared_to(mpos) > 0.0625 or phase != prev_phase:
		sync_revision += 1

	_emit_accum += delta
	if _emit_accum >= 0.10:
		_emit_accum = 0.0
		var bus := _bus()
		if bus != null:
			bus.sea_monster_updated.emit(mid, mpos, hp, max_hp, phase)


func damage_sea_monster(monster_id: int, damage: float, combat_system_ref: CombatSystem) -> void:
	if sea_monster.is_empty() or bool(sea_monster.get("defeated", false)):
		return
	if int(sea_monster.get("monster_id", -1)) != monster_id:
		return

	var hp: float = maxf(0.0, float(sea_monster["hp"]) - maxf(1.0, damage))
	var max_hp: float = float(sea_monster["max_hp"])
	var mpos: Vector2 = sea_monster["world_pos"]
	sea_monster["hp"] = hp
	sync_revision += 1

	var bus := _bus()
	if hp <= 0.0:
		sea_monster["defeated"] = true
		_respawn_timer = KRAKEN_RESPAWN_SECONDS
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
		"x": snappedf(pos.x, 0.1),
		"y": snappedf(pos.y, 0.1),
		"hp": snappedf(float(sea_monster.get("hp", 0.0)), 0.1),
		"max_hp": snappedf(float(sea_monster.get("max_hp", KRAKEN_MAX_HP)), 0.1),
		"phase": int(sea_monster.get("phase", 0)),
		"defeated": bool(sea_monster.get("defeated", true))
	}


static func _is_ship_harbor_protected(s: Node) -> bool:
	if s == null or not is_instance_valid(s):
		return false
	if s.has_method("is_harbor_protected"):
		return bool(s.call("is_harbor_protected"))
	return int(s.get("faction")) == Contracts.ShipFaction.PLAYER and int(s.get("current_harbor_index")) >= 0


static func _is_near_safe_harbor(pos: Vector2, margin: float = HARBOR_SAFE_MARGIN) -> bool:
	for isl in Contracts.get_islands():
		if not isl.has_harbor:
			continue
		var safe_r: float = isl.harbor_radius + margin
		if pos.distance_squared_to(isl.harbor_pos) <= safe_r * safe_r:
			return true
	return false


static func _nudge_away_from_safe_harbors(pos: Vector2, depth_fn: Callable) -> Vector2:
	if not _is_near_safe_harbor(pos, HARBOR_SAFE_MARGIN):
		return pos
	for isl in Contracts.get_islands():
		if not isl.has_harbor:
			continue
		var safe_r: float = isl.harbor_radius + HARBOR_SAFE_MARGIN + 40.0
		if pos.distance_squared_to(isl.harbor_pos) <= safe_r * safe_r:
			var out_dir: Vector2 = (pos - isl.harbor_pos).normalized()
			if out_dir.length_squared() < 0.01:
				out_dir = Vector2.from_angle(isl.harbor_angle)
			var cand: Vector2 = isl.harbor_pos + out_dir * safe_r
			if float(depth_fn.call(cand)) > 0.14:
				return cand
	return Vector2.ZERO


func _find_nearest_target(mpos: Vector2, ships: Dictionary) -> Node:
	var target_ship: Node = null
	var best_dist_sq: float = 950.0 * 950.0
	for s_var in ships.values():
		var s: Node = s_var
		if s == null or bool(s.get("is_sunk")) or _is_ship_harbor_protected(s):
			continue
		var d_sq: float = mpos.distance_squared_to(s.get("world_pos"))
		var weighted: float = d_sq * (0.6 if int(s.get("faction")) == Contracts.ShipFaction.PLAYER else 1.0)
		if weighted < best_dist_sq:
			best_dist_sq = weighted
			target_ship = s
	return target_ship


func _perform_tentacle_slam(mid: int, mpos: Vector2, enraged: bool, ships: Dictionary) -> bool:
	var hit_any: bool = false
	var range_sq: float = KRAKEN_ATTACK_RANGE * KRAKEN_ATTACK_RANGE
	var bus := _bus()
	for s_var in ships.values():
		var s: Node = s_var
		if s == null or bool(s.get("is_sunk")) or _is_ship_harbor_protected(s):
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
	return hit_any

class_name LootSystem
extends Node
## Manages floating loot crates from sunken ships, ghost-ship wrecks with rare
## gear, coastal fort loot, Kraken boss trophies, periodic open-sea flotsam,
## salvage quest targets, and incremental delta/revision sync. 100% headless-safe.

const ITEM_DB_PATH: String = "res://sim/item_database.gd"
const COLLECT_RADIUS: float = 44.0
const INTERACT_COLLECT_RADIUS: float = 56.0
const MAX_FLOTSAM_COUNT: int = 4
const FLOTSAM_SPAWN_INTERVAL: float = 50.0

const GHOST_WRECK_ITEMS: Array[String] = [
	"greek_fire_2x1",
	"harpoon_ballista_2x1",
	"alchemist_powder_1x1",
	"crows_nest_1x2",
	"gunner_quarters_2x2",
	"carpenter_workshop_2x2",
	"iron_ram_1x2",
	"organ_gun_2x2",
	"pitch_mortar_2x2",
	"bow_chaser_1x2"
]

const TIER_01_GEAR: Array[String] = [
	"swivel_gun_1x2",
	"chain_launcher_2x1",
	"carronade_2x1",
	"powder_barrel_1x1",
	"silk_top_sail_1x2",
	"crows_nest_1x2"
]

const TIER_23_GEAR: Array[String] = [
	"bronze_cannon_2x2",
	"long_culverin_1x3",
	"organ_gun_2x2",
	"pitch_mortar_2x2",
	"greek_fire_2x1",
	"harpoon_ballista_2x1",
	"bow_chaser_1x2",
	"gunner_quarters_2x2",
	"carpenter_workshop_2x2"
]

const TIER_45_GEAR: Array[String] = [
	"twin_cannon_2x3",
	"mortar_cannon_2x2",
	"pitch_mortar_2x2",
	"organ_gun_2x2",
	"bow_chaser_1x2",
	"alchemist_powder_1x1",
	"storm_sails_2x2"
]

var is_authoritative: bool = true
var drops: Dictionary = {} # drop_id (int) -> Contracts.LootDropData
var world_map_ref: Node = null
var sync_revision: int = 1

var _next_drop_id: int = 1
var _flotsam_timer: float = 12.0
var _ship_meta: Dictionary = {} # ship_id (int) -> { "hull_tier": int, "is_treasure_galleon": bool, "is_bounty_boss": bool }
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _item_db_script: Script = null


func _bus() -> Contracts:
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		return st.root.get_node_or_null("EventBus") as Contracts
	return null


func _ready() -> void:
	_rng.randomize()
	if ResourceLoader.exists(ITEM_DB_PATH):
		_item_db_script = load(ITEM_DB_PATH) as Script
	var bus := _bus()
	if bus != null:
		if not bus.ship_spawned.is_connected(_on_ship_spawned):
			bus.ship_spawned.connect(_on_ship_spawned)
		if not bus.ship_sunk.is_connected(_on_ship_sunk):
			bus.ship_sunk.connect(_on_ship_sunk)
		if not bus.fort_destroyed.is_connected(_on_fort_destroyed):
			bus.fort_destroyed.connect(_on_fort_destroyed)
		if not bus.sea_monster_defeated.is_connected(_on_sea_monster_defeated):
			bus.sea_monster_defeated.connect(_on_sea_monster_defeated)


func clear_all() -> void:
	if not drops.is_empty():
		sync_revision += 1
	drops.clear()
	_ship_meta.clear()
	_next_drop_id = 1
	_flotsam_timer = FLOTSAM_SPAWN_INTERVAL


func setup(p_world_map: Node, p_authoritative: bool = true) -> void:
	world_map_ref = p_world_map
	is_authoritative = p_authoritative


func get_sync_revision() -> int:
	return sync_revision


func _register_new_drop(drop: Contracts.LootDropData) -> Contracts.LootDropData:
	drops[drop.drop_id] = drop
	sync_revision += 1
	var bus := _bus()
	if bus != null:
		bus.loot_spawned.emit(drop)
	return drop


func spawn_initial_flotsam(p_world_map: Node, count: int = 10) -> void:
	world_map_ref = p_world_map
	if not is_authoritative:
		return
	for i in range(count):
		if i % 3 == 1:
			spawn_ghost_wreck(_pick_open_sea_position())
		else:
			_spawn_random_flotsam()


func spawn_ghost_wreck(world_pos: Vector2) -> Contracts.LootDropData:
	var drop := Contracts.LootDropData.new()
	drop.drop_id = _next_drop_id
	_next_drop_id += 1
	drop.world_pos = _ensure_water_pos(world_pos)
	drop.gold = _rng.randi_range(65, 125)
	drop.is_salvage_target = false
	drop.quest_id = "ghost_wreck"
	drop.lifetime = 65.0

	var gear_count: int = _rng.randi_range(1, 2)
	for _i in range(gear_count):
		var picked_id: String = GHOST_WRECK_ITEMS[_rng.randi_range(0, GHOST_WRECK_ITEMS.size() - 1)]
		var afx: int = Contracts.ItemAffix.CURSED if _rng.randf() < 0.40 else Contracts.ItemAffix.MASTERWORK
		var item := _create_item_by_id(picked_id, afx)
		if item != null:
			drop.items.append(item)

	return _register_new_drop(drop)


func spawn_salvage_target(world_pos: Vector2, quest_id: String) -> Contracts.LootDropData:
	var drop := Contracts.LootDropData.new()
	drop.drop_id = _next_drop_id
	_next_drop_id += 1
	drop.world_pos = _ensure_water_pos(world_pos)
	drop.gold = _rng.randi_range(55, 95)
	drop.is_salvage_target = true
	drop.quest_id = quest_id
	drop.lifetime = 360.0

	var relic := _create_item_by_id("salvage_relic_1x2", Contracts.ItemAffix.MASTERWORK)
	if relic != null:
		drop.items.append(relic)
	var extra := _create_random_item(false)
	if extra != null:
		drop.items.append(extra)

	return _register_new_drop(drop)


func spawn_loot_drop(
	world_pos: Vector2,
	faction_or_tier: int = Contracts.ShipFaction.PIRATE,
	is_salvage: bool = false,
	quest_id: String = ""
) -> Contracts.LootDropData:
	if is_salvage:
		return spawn_salvage_target(world_pos, quest_id)
	return spawn_ship_wreck_loot(world_pos, faction_or_tier)


func spawn_ship_wreck_loot(
	world_pos: Vector2,
	faction: int,
	is_treasure_galleon: bool = false,
	hull_tier: int = 0,
	is_bounty_boss: bool = false
) -> Contracts.LootDropData:
	var drop := Contracts.LootDropData.new()
	drop.drop_id = _next_drop_id
	_next_drop_id += 1
	drop.world_pos = _ensure_water_pos(world_pos)
	drop.is_salvage_target = false
	drop.lifetime = 55.0

	var eff_tier: int = clampi(hull_tier, 0, 5)
	var is_high_tier: bool = (
		eff_tier >= Contracts.ShipClass.CORSAIR_CLIPPER
		or faction == Contracts.ShipFaction.NAVY
		or is_bounty_boss
		or is_treasure_galleon
	)
	var extra_count: int = 1

	if is_high_tier:
		if is_treasure_galleon:
			drop.gold = _rng.randi_range(240, 360)
			var chest := _create_item_by_id("royal_treasure_2x2", Contracts.ItemAffix.MASTERWORK)
			if chest != null:
				drop.items.append(chest)
		elif is_bounty_boss:
			drop.gold = _rng.randi_range(165, 260)
		elif faction == Contracts.ShipFaction.NAVY:
			drop.gold = _rng.randi_range(135, 220)
		else:
			drop.gold = _rng.randi_range(125, 205)

		var elite_id: String = TIER_45_GEAR[_rng.randi_range(0, TIER_45_GEAR.size() - 1)]
		var elite_item := _create_item_by_id(elite_id, _roll_high_tier_affix(true))
		if elite_item != null:
			drop.items.append(elite_item)
		extra_count = _rng.randi_range(1, 2)
		for _i in range(extra_count):
			var bonus := _create_random_item(false)
			if bonus != null:
				drop.items.append(bonus)

	elif eff_tier >= Contracts.ShipClass.BRIGANTINE:
		drop.gold = _rng.randi_range(95, 170) if faction == Contracts.ShipFaction.MERCHANT else _rng.randi_range(85, 155)
		var rare_id: String = TIER_23_GEAR[_rng.randi_range(0, TIER_23_GEAR.size() - 1)]
		var rare_item := _create_item_by_id(rare_id, _roll_high_tier_affix(false))
		if rare_item != null:
			drop.items.append(rare_item)
		extra_count = _rng.randi_range(1, 2)
		for _i in range(extra_count):
			var bonus := _create_random_item(faction == Contracts.ShipFaction.MERCHANT)
			if bonus != null:
				drop.items.append(bonus)

	else:
		var is_merchant: bool = (faction == Contracts.ShipFaction.MERCHANT)
		drop.gold = _rng.randi_range(65, 130) if is_merchant else _rng.randi_range(45, 100)
		var gear_chance: float = 0.55 if is_merchant else 0.78
		if _rng.randf() < gear_chance:
			var low_id: String = TIER_01_GEAR[_rng.randi_range(0, TIER_01_GEAR.size() - 1)]
			var low_afx: int = Contracts.ItemAffix.MASTERWORK if _rng.randf() < 0.25 else Contracts.ItemAffix.STANDARD
			var gear_item := _create_item_by_id(low_id, low_afx)
			if gear_item != null:
				drop.items.append(gear_item)
		extra_count = _rng.randi_range(1, 2)
		for _i in range(extra_count):
			var want_cargo: bool = is_merchant or (_rng.randf() < 0.30)
			var extra := _create_random_item(want_cargo)
			if extra != null:
				drop.items.append(extra)

	if drop.items.is_empty():
		var fallback_item := _create_item_by_id(TIER_01_GEAR[0], Contracts.ItemAffix.STANDARD)
		if fallback_item != null:
			drop.items.append(fallback_item)

	return _register_new_drop(drop)


func spawn_fort_loot(world_pos: Vector2) -> Contracts.LootDropData:
	var drop := Contracts.LootDropData.new()
	drop.drop_id = _next_drop_id
	_next_drop_id += 1
	drop.world_pos = _ensure_water_pos(world_pos)
	drop.gold = _rng.randi_range(150, 230)
	drop.is_salvage_target = false
	drop.lifetime = 75.0

	var chest := _create_item_by_id("royal_treasure_2x2", Contracts.ItemAffix.STANDARD)
	if chest != null:
		drop.items.append(chest)
	var gear_id: String = GHOST_WRECK_ITEMS[_rng.randi_range(0, GHOST_WRECK_ITEMS.size() - 1)]
	var gear := _create_item_by_id(gear_id, Contracts.ItemAffix.MASTERWORK)
	if gear != null:
		drop.items.append(gear)

	return _register_new_drop(drop)


func spawn_kraken_loot(world_pos: Vector2) -> Contracts.LootDropData:
	var drop := Contracts.LootDropData.new()
	drop.drop_id = _next_drop_id
	_next_drop_id += 1
	drop.world_pos = _ensure_water_pos(world_pos)
	drop.gold = _rng.randi_range(280, 380)
	drop.is_salvage_target = false
	drop.lifetime = 90.0

	var trophy := _create_item_by_id("kraken_tentacle_trophy_2x2", Contracts.ItemAffix.MASTERWORK)
	if trophy != null:
		drop.items.append(trophy)
	var rare_id: String = TIER_45_GEAR[_rng.randi_range(0, TIER_45_GEAR.size() - 1)]
	var rare_gear := _create_item_by_id(rare_id, Contracts.ItemAffix.CURSED)
	if rare_gear != null:
		drop.items.append(rare_gear)

	return _register_new_drop(drop)


func step_loot(
	delta: float,
	ships: Dictionary,
	player_grid: Node = null,
	interact_pressed: bool = false
) -> void:
	if not is_authoritative:
		return

	_flotsam_timer -= delta
	if _flotsam_timer <= 0.0:
		_flotsam_timer = FLOTSAM_SPAWN_INTERVAL
		if _count_flotsam() < MAX_FLOTSAM_COUNT:
			if _rng.randf() < 0.35:
				spawn_ghost_wreck(_pick_open_sea_position())
			else:
				_spawn_random_flotsam()

	var to_remove: Array[int] = []
	var collected_ids: Array[int] = []

	for drop_id_var in drops.keys():
		var did: int = int(drop_id_var)
		var drop: Contracts.LootDropData = drops[drop_id_var]
		if drop == null:
			to_remove.append(did)
			continue

		drop.lifetime -= delta
		if drop.lifetime <= 0.0:
			to_remove.append(did)
			continue

		var radius: float = INTERACT_COLLECT_RADIUS if interact_pressed else COLLECT_RADIUS
		var radius_sq: float = radius * radius
		var collector_id: int = -1

		for sid_var in ships.keys():
			var ship: Node = ships[sid_var]
			if ship == null or bool(ship.get("is_sunk")):
				continue
			if int(ship.get("faction")) != Contracts.ShipFaction.PLAYER:
				continue
			var spos: Vector2 = ship.get("world_pos")
			if spos.distance_squared_to(drop.world_pos) <= radius_sq:
				collector_id = int(ship.get("ship_id"))
				break

		if collector_id != -1:
			_grant_loot_to_grid(drop, player_grid)
			collected_ids.append(did)
			var bus := _bus()
			if bus != null:
				bus.loot_collected.emit(did, collector_id, drop)

	if not to_remove.is_empty() or not collected_ids.is_empty():
		sync_revision += 1
	for did in to_remove:
		drops.erase(did)
	for did in collected_ids:
		drops.erase(did)


func _grant_loot_to_grid(drop: Contracts.LootDropData, player_grid: Node) -> void:
	if player_grid == null:
		return
	for item_var in drop.items:
		if not (item_var is Contracts.GridItemData):
			continue
		var item: Contracts.GridItemData = item_var
		var placed: bool = false
		if player_grid.has_method("auto_place_item"):
			placed = bool(player_grid.call("auto_place_item", item))
		if not placed:
			if player_grid.has_method("add_to_stash"):
				player_grid.call("add_to_stash", item)
			else:
				var stash: Variant = player_grid.get("stash_items")
				if stash is Array:
					stash.append(item)
					if player_grid.has_method("compile_stats"):
						player_grid.call("compile_stats")


func _on_ship_spawned(ship_id: int, ship_data: Dictionary) -> void:
	_ship_meta[ship_id] = {
		"hull_tier": int(ship_data.get("hull_tier", 0)),
		"is_treasure_galleon": bool(ship_data.get("is_treasure_galleon", false)),
		"is_bounty_boss": bool(ship_data.get("is_bounty_boss", false))
	}


func _on_ship_sunk(ship_id: int, world_pos: Vector2, faction: int, _killer_ship_id: int) -> void:
	if not is_authoritative:
		return
	var meta: Dictionary = _ship_meta.get(ship_id, {})
	_ship_meta.erase(ship_id)
	if faction == Contracts.ShipFaction.PLAYER:
		return
	spawn_ship_wreck_loot(
		world_pos,
		faction,
		bool(meta.get("is_treasure_galleon", false)),
		int(meta.get("hull_tier", 0)),
		bool(meta.get("is_bounty_boss", false))
	)


func _on_fort_destroyed(_fort_id: int, world_pos: Vector2) -> void:
	if is_authoritative:
		spawn_fort_loot(world_pos)


func _on_sea_monster_defeated(_monster_id: int, world_pos: Vector2) -> void:
	if is_authoritative:
		spawn_kraken_loot(world_pos)


func _spawn_random_flotsam() -> void:
	var drop := Contracts.LootDropData.new()
	drop.drop_id = _next_drop_id
	_next_drop_id += 1
	drop.world_pos = _pick_open_sea_position()
	drop.gold = _rng.randi_range(15, 45)
	drop.is_salvage_target = false
	drop.lifetime = 60.0

	var item_count: int = _rng.randi_range(1, 2)
	for _i in range(item_count):
		var item := _create_random_item(_rng.randf() < 0.45)
		if item != null:
			drop.items.append(item)

	_register_new_drop(drop)


func _pick_open_sea_position() -> Vector2:
	var extent: float = Contracts.WORLD_HALF_EXTENT * 0.72
	for _attempt in range(24):
		var candidate := Vector2(_rng.randf_range(-extent, extent), _rng.randf_range(-extent, extent))
		if candidate.length() < 120.0:
			continue
		if _get_depth(candidate) >= 0.25:
			return candidate
	return Vector2(_rng.randf_range(-240.0, 240.0), _rng.randf_range(-240.0, 240.0))


func _ensure_water_pos(pos: Vector2) -> Vector2:
	if _get_depth(pos) >= 0.20:
		return pos
	if world_map_ref != null and world_map_ref.has_method("find_open_water_near"):
		return world_map_ref.call("find_open_water_near", pos, 0.22)
	return pos + Contracts.get_coast_normal(pos) * 56.0


func _get_depth(pos: Vector2) -> float:
	if world_map_ref != null and world_map_ref.has_method("get_water_depth"):
		return float(world_map_ref.call("get_water_depth", pos))
	return Contracts.get_water_depth(pos)


func _count_flotsam() -> int:
	var cnt: int = 0
	for drop_var in drops.values():
		var d: Contracts.LootDropData = drop_var
		if d != null and not d.is_salvage_target:
			cnt += 1
	return cnt


func _roll_high_tier_affix(elite: bool) -> int:
	var roll: float = _rng.randf()
	if elite:
		if roll < 0.45:
			return Contracts.ItemAffix.MASTERWORK
		if roll < 0.72:
			return Contracts.ItemAffix.CURSED
		return Contracts.ItemAffix.STANDARD
	if roll < 0.40:
		return Contracts.ItemAffix.MASTERWORK
	if roll < 0.52:
		return Contracts.ItemAffix.CURSED
	return Contracts.ItemAffix.STANDARD


func _create_random_item(include_cargo: bool) -> Contracts.GridItemData:
	if _item_db_script == null and ResourceLoader.exists(ITEM_DB_PATH):
		_item_db_script = load(ITEM_DB_PATH) as Script
	if _item_db_script != null:
		var item: Variant = _item_db_script.call("create_random_item", _rng, include_cargo)
		if item is Contracts.GridItemData:
			if item.affix == Contracts.ItemAffix.STANDARD and _rng.randf() < 0.45:
				item.affix = int(_item_db_script.call("roll_random_affix", _rng))
			return item

	var fallback := Contracts.GridItemData.new()
	fallback.id = "rum_casks_1x1"
	fallback.name = "Rumfässer"
	fallback.category = Contracts.ItemCategory.CARGO
	fallback.affix = _roll_fallback_affix()
	fallback.gold_value = 35
	fallback.instance_id = "rum_%d" % _next_drop_id
	return fallback


func _create_item_by_id(item_id: String, affix: int) -> Contracts.GridItemData:
	if _item_db_script == null and ResourceLoader.exists(ITEM_DB_PATH):
		_item_db_script = load(ITEM_DB_PATH) as Script
	if _item_db_script != null:
		var item: Variant = _item_db_script.call("create_item", item_id, affix)
		if item is Contracts.GridItemData:
			return item
	var fallback := Contracts.GridItemData.new()
	fallback.id = item_id
	fallback.name = "Versunkenes Artefakt"
	fallback.category = Contracts.ItemCategory.TREASURE
	fallback.rarity = Contracts.ItemRarity.RARE
	fallback.affix = affix
	fallback.width = 1
	fallback.height = 2
	fallback.gold_value = 120
	fallback.instance_id = "%s_%d" % [item_id, _next_drop_id]
	return fallback


func _roll_fallback_affix() -> int:
	var roll: float = _rng.randf()
	if roll < 0.22:
		return Contracts.ItemAffix.RUSTED
	elif roll < 0.72:
		return Contracts.ItemAffix.STANDARD
	elif roll < 0.90:
		return Contracts.ItemAffix.MASTERWORK
	return Contracts.ItemAffix.CURSED


func to_sync_array() -> Array:
	var out: Array = []
	for drop_var in drops.values():
		var d: Contracts.LootDropData = drop_var
		if d != null:
			out.append(d.to_dict())
	return out


## Incremental diffing: allocates LootDropData only for genuinely new drops,
## updates existing crates in-place without respawning, and removes gone drops.
func apply_sync_array(raw_drops: Array) -> void:
	var seen: Dictionary = {}
	var bus := _bus()
	var changed: bool = false

	for raw in raw_drops:
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		var did: int = int(d.get("drop_id", 0))
		if did <= 0:
			continue
		seen[did] = true

		if drops.has(did):
			var existing: Contracts.LootDropData = drops[did]
			if existing != null:
				var next_pos := Vector2(float(d.get("x", existing.world_pos.x)), float(d.get("y", existing.world_pos.y)))
				if existing.world_pos.distance_squared_to(next_pos) > 0.01:
					existing.world_pos = next_pos
					changed = true
				existing.lifetime = float(d.get("lifetime", existing.lifetime))
		else:
			var new_drop := Contracts.LootDropData.from_dict(d)
			drops[did] = new_drop
			changed = true
			if bus != null:
				bus.loot_spawned.emit(new_drop)

	var to_erase: Array[int] = []
	for did_var in drops.keys():
		if not seen.has(int(did_var)):
			to_erase.append(int(did_var))

	for did in to_erase:
		var old_drop: Contracts.LootDropData = drops[did]
		drops.erase(did)
		changed = true
		if bus != null:
			bus.loot_collected.emit(did, -1, old_drop)

	if changed:
		sync_revision += 1

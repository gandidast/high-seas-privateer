extends SceneTree
## Automated Headless Verification Suite for High Seas Pixel Privateer.
## Run via: godot --headless --path . -s res://tests/verify_game.gd

var _failures: Array[String] = []
var _checks_passed: int = 0
var _has_run: bool = false


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_checks_passed += 1
	else:
		_failures.append(msg)
		push_error("[VERIFY FAIL] " + msg)


func _process(_delta: float) -> bool:
	if _has_run:
		return true
	_has_run = true

	print("====================================================================")
	print("[VERIFY] Starting Automated Headless Verification Suite...")
	print("====================================================================")

	root.size = Vector2i(1280, 720)

	# Ensure EventBus autoload exists in root when running via -s SceneTree
	if root.get_node_or_null("EventBus") == null:
		var bus := Contracts.new()
		bus.name = "EventBus"
		root.add_child(bus)

	_test_deterministic_world_and_physics()
	_test_dredge_grid_rotation_synergy_and_stats()
	_test_combat_ai_rng_loot_and_quests()
	_test_visual_pipeline_and_headless_server_boot()

	print("====================================================================")
	if _failures.is_empty():
		print("[VERIFY SUCCESS] All %d assertions passed with 0 errors!" % _checks_passed)
		print("====================================================================")
		quit(0)
	else:
		print("[VERIFY FAILED] %d failures out of %d checks:" % [_failures.size(), _checks_passed + _failures.size()])
		for f in _failures:
			print("  - " + f)
		print("====================================================================")
		quit(1)
	return true


func _test_deterministic_world_and_physics() -> void:
	print("[TEST 1/4] Deterministic World (7200x7200), 8 Islands, 3 Safe Harbors, Clear Weather & ShipPhysics...")
	var seed_val: int = Contracts.DEFAULT_WORLD_SEED

	_assert_true(is_equal_approx(Contracts.WORLD_HALF_EXTENT, 3600.0), "WORLD_HALF_EXTENT must be 3600.0 (7200x7200)")
	_assert_true(Contracts.ISLAND_COUNT == 8, "ISLAND_COUNT must be 8 (got %d)" % Contracts.ISLAND_COUNT)

	# 1. Determinism check
	var sample_points: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(250.0, -180.0),
		Vector2(-780.0, -480.0),
		Vector2(1520.0, -1180.0),
		Vector2(-1960.0, 920.0)
	]
	for pt in sample_points:
		var d1: float = Contracts.get_water_depth(pt, seed_val)
		var d2: float = Contracts.get_water_depth(pt, seed_val)
		_assert_true(is_equal_approx(d1, d2), "get_water_depth() must be 100%% deterministic at %s" % str(pt))

	# 2. WorldMap setup & islands (3 safe harbors, 5 wild islands, 5 wild coastal forts)
	var world_map := WorldMap.new()
	root.add_child(world_map)
	world_map.setup(seed_val)

	_assert_true(world_map.islands.size() == 8, "WorldMap must generate exactly 8 named islands (got %d)" % world_map.islands.size())

	var spawn_depth: float = world_map.get_water_depth(Vector2.ZERO)
	_assert_true(spawn_depth > Contracts.SHALLOW_THRESHOLD, "World origin (0,0) must be navigable deep water (depth=%.3f)" % spawn_depth)

	var safe_harbor_count: int = 0
	var wild_island_count: int = 0
	for isl in world_map.islands:
		var center_depth: float = world_map.get_water_depth(isl.center)
		_assert_true(center_depth <= Contracts.LAND_THRESHOLD, "Island '%s' center must be land (depth=%.3f)" % [isl.name, center_depth])
		_assert_true(world_map.is_land(isl.center), "world_map.is_land() must be true at island '%s' center" % isl.name)

		var harbor_depth: float = world_map.get_water_depth(isl.harbor_pos)
		_assert_true(harbor_depth > Contracts.LAND_THRESHOLD, "Island '%s' harbor_pos must be in navigable water (depth=%.3f)" % [isl.name, harbor_depth])
		var detected_harbor: int = world_map.get_harbor_at(isl.harbor_pos)
		if isl.has_harbor:
			safe_harbor_count += 1
			_assert_true(isl.harbor_radius > 0.0, "Safe harbor '%s' must have positive harbor_radius" % isl.name)
			_assert_true(detected_harbor == isl.index, "get_harbor_at(harbor_pos) must return safe harbor index %d (got %d)" % [isl.index, detected_harbor])
		else:
			wild_island_count += 1
			_assert_true(is_zero_approx(isl.harbor_radius), "Wild island '%s' must have harbor_radius=0.0" % isl.name)
			_assert_true(detected_harbor == -1, "get_harbor_at() on wild island '%s' must return -1 (got %d)" % [isl.name, detected_harbor])

	_assert_true(safe_harbor_count == 3, "Must have exactly 3 safe harbors (got %d)" % safe_harbor_count)
	_assert_true(wild_island_count == 5, "Must have exactly 5 wild islands (got %d)" % wild_island_count)

	var fort_positions: Array[Dictionary] = world_map.get_fort_positions()
	_assert_true(fort_positions.size() == 5, "WorldMap must place exactly 5 coastal forts on wild islands (got %d)" % fort_positions.size())
	for fp in fort_positions:
		var f_isl_idx: int = int(fp.get("island_index", -1))
		var f_isl: Contracts.IslandData = world_map.get_island(f_isl_idx)
		_assert_true(f_isl != null and not f_isl.has_harbor, "Coastal fort must never be on a safe harbor island (idx=%d)" % f_isl_idx)

	var nearest_safe: Contracts.IslandData = world_map.get_nearest_safe_harbor(Vector2(-1900.0, 900.0))
	_assert_true(nearest_safe != null and nearest_safe.has_harbor, "get_nearest_safe_harbor() must return a safe harbor island")

	# 3. Weather stays CLEAR when BAD_WEATHER_ENABLED == false
	_assert_true(not WorldMap.BAD_WEATHER_ENABLED, "WorldMap.BAD_WEATHER_ENABLED must be false")
	for _w in range(120):
		world_map.step_wind(0.5)
	_assert_true(world_map.current_weather == Contracts.WeatherState.CLEAR and is_zero_approx(world_map.weather_intensity), "Weather must remain CLEAR after 60s of step_wind()")
	world_map.set_weather(Contracts.WeatherState.STORM, 1.0)
	_assert_true(world_map.current_weather == Contracts.WeatherState.CLEAR, "set_weather(STORM) must stay CLEAR while BAD_WEATHER_ENABLED is false")

	# 4. ShipPhysics 6 tiers, sail states, wind influence & harbor protection
	var ship := ShipPhysics.new()
	root.add_child(ship)
	ship.setup(1, Vector2.ZERO, 0.0, Contracts.ShipFaction.PLAYER, "TestSchaluppe")
	ship.set_sail_state(Contracts.SailState.FULL_SAIL)
	for _i in range(20):
		ship.step_physics(0.05, 0.0, world_map)
	_assert_true(ship.speed > 20.0, "Ship under FULL_SAIL must accelerate forward (speed=%.2f)" % ship.speed)

	# Upwind test
	world_map.wind_direction = Vector2.LEFT
	ship.heading = 0.0
	for _i in range(30):
		ship.step_physics(0.05, 0.0, world_map)
	_assert_true(ship.speed >= ship.stats.max_speed * 0.35, "Ship sailing directly against wind must maintain minimum speed (speed=%.2f)" % ship.speed)

	# Test all 6 ship class upgrades & harbor protection
	for tier in range(6):
		ship.upgrade_ship_class(tier)
		var spec: Dictionary = Contracts.get_ship_class_spec(tier)
		_assert_true(ship.hull_tier == tier, "ShipPhysics.upgrade_ship_class(%d) must update hull_tier" % tier)
		_assert_true(is_equal_approx(ship.max_hp, float(spec["base_hp"])), "ShipPhysics tier %d max_hp must match SHIP_CLASS_SPECS" % tier)
		_assert_true(is_equal_approx(ship.hull_radius, float(spec["hull_radius"])), "ShipPhysics tier %d hull_radius must match spec" % tier)

	var safe_isl0: Contracts.IslandData = world_map.get_island(0)
	ship.world_pos = safe_isl0.harbor_pos
	ship.step_physics(0.02, 0.0, world_map)
	_assert_true(ship.is_harbor_protected(), "Player ship inside safe harbor zone must report is_harbor_protected() == true")

	ship.queue_free()
	world_map.queue_free()
	print("  -> [PASS] 7200x7200 world, 8 islands, 3 safe harbors, 5 wild forts, clear weather & 6-tier ShipPhysics verified.")


func _test_dredge_grid_rotation_synergy_and_stats() -> void:
	print("[TEST 2/4] 6-Class DredgeGrids (6x4..10x7), SlotType.BOW, Downsize Eviction & 27 Items...")

	var all_ids: Array[String] = ItemDatabase.get_all_ids()
	_assert_true(all_ids.size() == 27, "ItemDatabase must define exactly 27 items (got %d)" % all_ids.size())
	for new_id in ["carronade_2x1", "organ_gun_2x2", "twin_cannon_2x3", "pitch_mortar_2x2", "bow_chaser_1x2"]:
		_assert_true(new_id in all_ids, "ItemDatabase must contain new weapon '%s'" % new_id)

	var grid := DredgeGrid.new()
	grid.ship_id = 1
	root.add_child(grid)

	# Verify exact grid sizes for all 6 ShipClass tiers
	var expected_dims: Dictionary = {
		Contracts.ShipClass.SLOOP: Vector2i(6, 4),
		Contracts.ShipClass.SCHOONER: Vector2i(6, 5),
		Contracts.ShipClass.BRIGANTINE: Vector2i(7, 5),
		Contracts.ShipClass.FRIGATE: Vector2i(8, 6),
		Contracts.ShipClass.CORSAIR_CLIPPER: Vector2i(6, 5),
		Contracts.ShipClass.WAR_GALLEON: Vector2i(10, 7)
	}
	for tier in expected_dims.keys():
		grid.set_hull_tier(int(tier))
		var exp: Vector2i = expected_dims[tier]
		_assert_true(
			grid.get_grid_width() == exp.x and grid.get_grid_height() == exp.y,
			"Tier %d grid must be %dx%d (got %dx%d)" % [tier, exp.x, exp.y, grid.get_grid_width(), grid.get_grid_height()]
		)
		var has_bow_slot: bool = false
		for gy in range(exp.y):
			if grid.get_slot_type(exp.x - 1, gy) == Contracts.SlotType.BOW:
				has_bow_slot = true
		_assert_true(has_bow_slot, "Tier %d (%dx%d) must have at least one SlotType.BOW at front column" % [tier, exp.x, exp.y])

	# Test Frigate (8x6) slot layout, cannons, bow chaser, powder synergy & sails
	grid.set_hull_tier(Contracts.ShipClass.FRIGATE)
	_assert_true(grid.get_slot_type(0, 0) == Contracts.SlotType.DECK_PORT, "Frigate row y=0 must be DECK_PORT")
	_assert_true(grid.get_slot_type(0, 5) == Contracts.SlotType.DECK_STARBOARD, "Frigate row y=5 must be DECK_STARBOARD")
	_assert_true(grid.get_slot_type(7, 2) == Contracts.SlotType.BOW and grid.get_slot_type(7, 3) == Contracts.SlotType.BOW, "Frigate (7,2)-(7,3) must be SlotType.BOW")
	_assert_true(grid.get_slot_type(3, 2) == Contracts.SlotType.MAST, "Frigate center (3,2) must be MAST")
	_assert_true(grid.get_slot_type(1, 1) == Contracts.SlotType.CARGO_HOLD, "Frigate interior (1,1) must be CARGO_HOLD")

	# 1. Place a 1x2 swivel cannon rotated (2x1) on DECK_PORT at (0, 0)
	var port_cannon: Contracts.GridItemData = ItemDatabase.create_item("swivel_gun_1x2")
	_assert_true(port_cannon.get_effective_size() == Vector2i(1, 2), "Unrotated swivel_gun_1x2 size must be 1x2")
	_assert_true(grid.can_place_item(port_cannon, 0, 0, true), "Rotated 2x1 cannon must fit along DECK_PORT rail at (0,0)")
	var placed_cannon: bool = grid.place_item(port_cannon, 0, 0, true)
	_assert_true(placed_cannon and port_cannon.get_effective_size() == Vector2i(2, 1), "Placed rotated cannon must have effective size 2x1")

	var stats_before_barrel: Contracts.ShipStats = grid.compile_stats()
	_assert_true(stats_before_barrel.port_cannons.size() == 1, "Port rail cannon must register in stats.port_cannons")
	var base_reload: float = float(stats_before_barrel.port_cannons[0]["reload_time"])

	# 2. Place a cannon solely inside CARGO_HOLD at (4, 1) -> must NOT fire in broadsides!
	var hold_cannon: Contracts.GridItemData = ItemDatabase.create_item("swivel_gun_1x2")
	_assert_true(grid.place_item(hold_cannon, 4, 1, true), "Cannon should be storable in CARGO_HOLD at (4,1)")
	var stats_with_hold_cannon: Contracts.ShipStats = grid.compile_stats()
	_assert_true(
		stats_with_hold_cannon.port_cannons.size() == 1 and stats_with_hold_cannon.starboard_cannons.size() == 0,
		"Cannon stored in CARGO_HOLD must NOT count as active broadside cannon"
	)

	# 3. Place powder_barrel_1x1 at (0, 1) directly adjacent to port_cannon at (0, 0)
	var barrel: Contracts.GridItemData = ItemDatabase.create_item("powder_barrel_1x1")
	_assert_true(grid.place_item(barrel, 0, 1, false), "Powder barrel 1x1 must be placeable at (0,1) adjacent to port cannon")
	var stats_after_barrel: Contracts.ShipStats = grid.compile_stats()
	var boosted_reload: float = float(stats_after_barrel.port_cannons[0]["reload_time"])
	_assert_true(boosted_reload < base_reload * 0.85, "Powder barrel adjacency must grant +25%% reload speed (before=%.2fs, after=%.2fs)" % [base_reload, boosted_reload])
	_assert_true(stats_after_barrel.explosion_hazard_damage >= 10.0, "Equipped powder barrel must increase explosion_hazard_damage")
	_assert_true(not grid.get_adjacent_synergy_cells().is_empty(), "get_adjacent_synergy_cells() must highlight active synergy cells")

	# 4. Place storm_sails_2x2 on MAST at (2, 2) and check speed bonus
	var base_spd: float = stats_after_barrel.max_speed
	var sails: Contracts.GridItemData = ItemDatabase.create_item("storm_sails_2x2")
	_assert_true(grid.place_item(sails, 2, 2, false), "Storm sails 2x2 must be placeable on MAST at (2,2)")
	var stats_after_sails: Contracts.ShipStats = grid.compile_stats()
	_assert_true(stats_after_sails.max_speed > base_spd + 10.0, "Storm sails must increase ShipStats.max_speed")

	# 5. Place bow_chaser_1x2 in SlotType.BOW at (7, 2) and verify compilation
	var bow_gun: Contracts.GridItemData = ItemDatabase.create_item("bow_chaser_1x2")
	_assert_true(grid.place_item(bow_gun, 7, 2, false), "bow_chaser_1x2 must be placeable in Frigate BOW slots (7,2)")
	var stats_with_bow: Contracts.ShipStats = grid.compile_stats()
	_assert_true(stats_with_bow.bow_cannons.size() == 1 and stats_with_bow.bow_salvo_damage >= 20.0, "bow_chaser_1x2 in BOW slot must compile into stats.bow_cannons")

	# 6. Downsize Frigate (8x6) -> Corsair Clipper (6x5): items out of bounds (bow_gun at x=7) must evict to stash!
	var stash_before_downsize: int = grid.stash_items.size()
	grid.set_hull_tier(Contracts.ShipClass.CORSAIR_CLIPPER)
	_assert_true(grid.get_grid_width() == 6 and grid.get_grid_height() == 5, "Downsize to CORSAIR_CLIPPER must set 6x5 grid")
	_assert_true(grid.stash_items.size() > stash_before_downsize and (bow_gun in grid.stash_items), "Downsizing Frigate -> Corsair Clipper must evict out-of-bounds items to stash")
	_assert_true(grid.current_stats.bow_cannons.is_empty(), "Evicted bow gun must no longer be compiled into active bow_cannons")
	_assert_true(is_equal_approx(grid.current_stats.bow_reload_multiplier, 1.15), "Corsair Clipper must apply +15% reload_bonus (1.15)")
	var clipper_mast_count: int = 0
	for gy in range(grid.get_grid_height()):
		for gx in range(grid.get_grid_width()):
			if grid.get_slot_type(gx, gy) == Contracts.SlotType.MAST:
				clipper_mast_count += 1
	_assert_true(clipper_mast_count == 8, "CORSAIR_CLIPPER must have 8 MAST slots (got %d)" % clipper_mast_count)
	var clipper_sail2: Contracts.GridItemData = ItemDatabase.create_item("storm_sails_2x2")
	_assert_true(grid.place_item(clipper_sail2, 3, 1, false), "CORSAIR_CLIPPER must fit a second 2x2 sail in its 8 MAST slots")

	# Verify strictly escalating ship class costs
	var prev_cost: int = -1
	for t_idx in range(6):
		var c_val: int = int(Contracts.get_ship_class_spec(t_idx).get("cost", 0))
		_assert_true(c_val > prev_cost, "ShipClass %d cost (%d) must exceed previous (%d)" % [t_idx, c_val, prev_cost])
		prev_cost = c_val

	# 7. Verify bow_chaser_1x2 also mounts cleanly on War Galleon (10x7) horizontally (8,3 rotated)
	grid.set_hull_tier(Contracts.ShipClass.WAR_GALLEON)
	var galleon_bow: Contracts.GridItemData = ItemDatabase.create_item("bow_chaser_1x2")
	_assert_true(grid.place_item(galleon_bow, 8, 3, true), "bow_chaser_1x2 rotated (2x1) must mount on War Galleon (8,3)->(9,3) BOW")
	_assert_true(grid.current_stats.bow_cannons.size() == 1, "War Galleon bow chaser must compile into bow_cannons")

	grid.queue_free()
	print("  -> [PASS] 6-class grids, BOW slots, downsize stash eviction, 27 items & synergy stats verified.")


func _test_combat_ai_rng_loot_and_quests() -> void:
	print("[TEST 3/4] Multi-Pellet Weapons, Bow Chaser, Safe Harbor Immunity, AI Retreat, Tiered Loot, Death Penalty & HarborUI...")

	var bus: Contracts = Contracts.bus()
	var world_map := WorldMap.new()
	root.add_child(world_map)
	world_map.setup(Contracts.DEFAULT_WORLD_SEED)

	var combat := CombatSystem.new()
	root.add_child(combat)
	combat.setup_island_forts(world_map)
	_assert_true(combat.forts.size() == 5, "CombatSystem must initialize 5 coastal forts on wild islands (got %d)" % combat.forts.size())

	var loot := LootSystem.new()
	root.add_child(loot)
	loot.setup(world_map, true)

	var ai := AIDirector.new()
	root.add_child(ai)
	ai.setup(world_map, combat)

	# Create player ship & Frigate grid with multi-pellet weapons + bow chaser
	var player := ShipPhysics.new()
	root.add_child(player)
	player.setup(1, Vector2.ZERO, 0.0, Contracts.ShipFaction.PLAYER, "Spieler")
	var p_grid := DredgeGrid.new()
	p_grid.ship_id = 1
	root.add_child(p_grid)
	p_grid.set_hull_tier(Contracts.ShipClass.FRIGATE)

	var carronade := ItemDatabase.create_item("carronade_2x1") # 4 pellets
	var organ_gun := ItemDatabase.create_item("organ_gun_2x2") # 3 pellets
	var twin_cannon := ItemDatabase.create_item("twin_cannon_2x3") # 2 pellets
	var bow_chaser := ItemDatabase.create_item("bow_chaser_1x2") # 1 forward shot
	_assert_true(p_grid.place_item(carronade, 0, 0, false), "carronade_2x1 must mount on Frigate PORT rail")
	_assert_true(p_grid.place_item(organ_gun, 2, 0, false), "organ_gun_2x2 must mount on Frigate PORT rail")
	_assert_true(p_grid.place_item(twin_cannon, 0, 4, true), "twin_cannon_2x3 rotated (3x2) must mount on Frigate STARBOARD rail (0,4)")
	_assert_true(p_grid.place_item(bow_chaser, 7, 2, false), "bow_chaser_1x2 must mount in Frigate BOW slot (7,2)")

	player.apply_stats(p_grid.compile_stats())
	combat.register_ship(player)

	# Verify multi-pellet broadside counts: PORT = 4 + 3 = 7 pellets; STARBOARD = 2 pellets
	var port_shots: Array = combat.fire_broadside(1, false)
	_assert_true(port_shots.size() == 7, "Carronade (4) + Organ Gun (3) port broadside must spawn 7 pellets (got %d)" % port_shots.size())

	var pirate_id: int = ai.spawn_ai_ship(Contracts.ShipFaction.PIRATE, Vector2(0.0, 75.0), false, "Piratenschaluppe")
	var pirate: ShipPhysics = ai.ai_ships.get(pirate_id, null)
	_assert_true(pirate != null, "AIDirector must spawn pirate ship")

	var sb_shots: Array = combat.fire_broadside(1, true)
	_assert_true(sb_shots.size() == 2, "Twin Cannon starboard broadside must spawn 2 pellets (got %d)" % sb_shots.size())

	var start_pirate_hp: float = pirate.hp
	for _i in range(40):
		combat.step_projectiles(0.025, world_map)
	_assert_true(pirate.hp < start_pirate_hp, "Starboard Twin Cannon must hit and damage pirate ship")

	# Verify bow chaser forward fire via fire_bow() & get_bow_cone()
	var bow_cone_before: Dictionary = combat.get_bow_cone(1)
	_assert_true(int(bow_cone_before.get("total_count", 0)) == 1 and float(bow_cone_before.get("ready_ratio", 0.0)) >= 0.99, "get_bow_cone(1) must report 1 ready bow cannon")
	var bow_target_id: int = ai.spawn_ai_ship(Contracts.ShipFaction.PIRATE, Vector2(95.0, 0.0), false, "BugZiel")
	var bow_target: ShipPhysics = ai.ai_ships.get(bow_target_id, null)
	var bow_shots: Array = combat.fire_bow(1)
	_assert_true(bow_shots.size() == 1 and bool(bow_shots[0].get("is_bow", false)), "fire_bow(1) must spawn 1 forward projectile with is_bow=true")
	var bow_target_hp0: float = bow_target.hp
	for _i in range(30):
		combat.step_projectiles(0.025, world_map)
	_assert_true(bow_target.hp < bow_target_hp0, "Bow chaser projectile must hit enemy ahead at +X")

	# Verify safe harbor damage immunity & fire block
	var safe_isl0: Contracts.IslandData = world_map.get_island(0)
	player.world_pos = safe_isl0.harbor_pos
	player.step_physics(0.02, 0.0, world_map)
	_assert_true(player.is_harbor_protected(), "Player in Port Tortuga harbor must be protected")
	_assert_true(combat.fire_broadside(1, false).is_empty(), "Harbor-protected player cannot fire broadside")
	_assert_true(combat.fire_bow(1).is_empty(), "Harbor-protected player cannot fire bow chaser")
	var hp_in_harbor: float = player.hp
	combat._apply_direct_damage(player, 1, 50.0, player.world_pos, pirate_id, false)
	_assert_true(is_equal_approx(player.hp, hp_in_harbor), "Harbor-protected player must take 0 damage from direct strikes")
	player.world_pos = Vector2.ZERO
	player.step_physics(0.02, 0.0, world_map)

	# Verify AI FLEE_TO_PORT open-sea retreat & despawn
	pirate.hp = pirate.max_hp * 0.20
	var ships_dict: Dictionary = { 1: player, pirate_id: pirate, bow_target_id: bow_target }
	ai.step_ai(0.1, ships_dict)
	var p_state: int = ai.get_ship_ai_state(pirate_id)
	_assert_true(p_state == Contracts.AIState.FLEE_TO_PORT, "AI ship below 30%% HP must enter FLEE_TO_PORT state (got %d)" % p_state)
	pirate.world_pos = Vector2(2200.0, 2200.0) # Far beyond FLEE_DESPAWN_DIST
	ai.step_ai(0.1, ships_dict)
	_assert_true(not ai.ai_ships.has(pirate_id), "Fleeing AI ship beyond FLEE_DESPAWN_DIST must despawn cleanly")

	# Verify AI fleet population uses calmer fleet & tier-scaled loot drops
	ai.clear_all()
	ai.populate_initial_fleet(3, 3)
	_assert_true(ai.ai_ships.size() == 6, "populate_initial_fleet(3, 3) must spawn 6 AI ships (got %d)" % ai.ai_ships.size())

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var low_wep := ItemDatabase.create_tiered_weapon(0, rng)
	var high_wep := ItemDatabase.create_tiered_weapon(5, rng)
	_assert_true(low_wep != null and low_wep.rarity <= Contracts.ItemRarity.UNCOMMON, "Tier 0 tiered weapon must be COMMON/UNCOMMON")
	_assert_true(high_wep != null and high_wep.rarity >= Contracts.ItemRarity.RARE, "Tier 5 tiered weapon must be RARE/LEGENDARY")

	var high_drop: Contracts.LootDropData = loot.spawn_ship_wreck_loot(Vector2(10.0, 0.0), Contracts.ShipFaction.PIRATE, false, Contracts.ShipClass.WAR_GALLEON, false)
	_assert_true(high_drop != null and high_drop.gold >= 125 and not high_drop.items.is_empty(), "High-tier ship wreck loot must award scaled gold and items")
	var seen_affixes: Dictionary = {}
	for _i in range(60):
		seen_affixes[ItemDatabase.roll_random_affix(rng)] = true
	_assert_true(seen_affixes.size() >= 3, "RNG affix roller must produce at least 3 distinct affixes")

	loot.step_loot(0.1, { 1: player }, p_grid, true)
	_assert_true(not loot.drops.has(high_drop.drop_id), "Player within pickup radius must collect floating loot drop")

	# Verify HarborUI 6-class unlock/switch, shop refresh (5 offers), quests & 10s death penalty
	var harbor_ui := HarborUI.new()
	root.add_child(harbor_ui)
	harbor_ui.setup(player, p_grid, world_map, ai, loot, 5000)
	harbor_ui.open_harbor(3) # Wild island must NOT open harbor UI!
	_assert_true(not harbor_ui.visible, "open_harbor() on wild island (has_harbor=false) must refuse to open")

	harbor_ui.open_harbor(0)
	_assert_true(harbor_ui.visible, "open_harbor(0) on Port Tortuga must open HarborUI")
	var shop0: Array = harbor_ui.harbor_shops.get(0, [])
	_assert_true(shop0.size() == 5, "Harbor shop must generate 5 offers (got %d)" % shop0.size())

	# Visiting another safe harbor refreshes shop
	harbor_ui.open_harbor(1)
	_assert_true(harbor_ui.harbor_shops.get(1, []).size() == 5, "Second safe harbor must generate 5 shop offers")
	harbor_ui.open_harbor(0)
	_assert_true(harbor_ui._shop_just_refreshed, "Returning from another safe harbor must auto-refresh shop inventory")

	# 6-class Shipyard unlock, free switch back, and downsize eviction
	harbor_ui._select_or_buy_ship_tier(Contracts.ShipClass.FRIGATE)
	_assert_true(player.hull_tier == Contracts.ShipClass.FRIGATE and harbor_ui.owned_ship_tiers.has(Contracts.ShipClass.FRIGATE), "Buying FRIGATE must unlock and equip tier 3")
	var gold_after_frigate: int = harbor_ui.current_gold
	harbor_ui._select_or_buy_ship_tier(Contracts.ShipClass.CORSAIR_CLIPPER)
	_assert_true(player.hull_tier == Contracts.ShipClass.CORSAIR_CLIPPER, "Buying CORSAIR_CLIPPER must switch to tier 4")
	var gold_after_clipper: int = harbor_ui.current_gold
	_assert_true(gold_after_clipper < gold_after_frigate, "Buying new class must deduct gold")
	harbor_ui._select_or_buy_ship_tier(Contracts.ShipClass.FRIGATE)
	_assert_true(player.hull_tier == Contracts.ShipClass.FRIGATE and harbor_ui.current_gold == gold_after_clipper, "Switching back to owned FRIGATE must be free")

	# Quests (DELIVERY must only target safe harbors)
	var quests: Array = harbor_ui.harbor_quests.get(0, [])
	_assert_true(quests.size() == 3, "HarborUI must generate 3 quests per harbor")
	var delivery_quest: Contracts.QuestData = null
	for q in quests:
		if q is Contracts.QuestData and q.quest_type == Contracts.QuestType.DELIVERY:
			delivery_quest = q
			break
	_assert_true(delivery_quest != null and (delivery_quest.target_island_idx in Contracts.SAFE_HARBOR_INDICES), "DELIVERY quest target must be one of the 3 safe harbors")
	var gold_before_q: int = harbor_ui.current_gold
	harbor_ui._accept_quest(delivery_quest)
	var completed_ok: bool = harbor_ui.complete_quest(delivery_quest.id)
	_assert_true(completed_ok and harbor_ui.current_gold > gold_before_q, "Completing quest must award gold")

	# 10s death penalty signal -> HarborUI gold deduction + HudOverlay countdown banner
	var hud := HudOverlay.new()
	root.add_child(hud)
	hud.setup(player, world_map, combat, loot, { 1: player }, harbor_ui.current_gold)
	var gold_pre_death: int = harbor_ui.current_gold
	bus.player_death_penalty.emit(1, 20, 10.0)
	_assert_true(harbor_ui.current_gold == gold_pre_death - 20, "player_death_penalty must deduct 20 gold in HarborUI")
	_assert_true(not harbor_ui.visible, "player_death_penalty must close HarborUI")
	_assert_true(hud._death_active and is_equal_approx(hud._death_countdown, 10.0), "HudOverlay must activate 10s death countdown banner")

	# Verify MinimapRenderer & WorldMapOverlay
	hud.toggle_world_map()
	_assert_true(hud.is_world_map_open(), "HudOverlay.toggle_world_map() must open WorldMapOverlay")
	_assert_true(hud._minimap != null and hud._minimap._baked_map_tex != null, "MinimapRenderer must bake static 7200x7200 world texture")
	_assert_true(hud._world_map != null and hud._world_map._baked_tex != null, "WorldMapOverlay must bake static 7200x7200 chart texture")
	hud.set_world_map_open(false)
	_assert_true(not hud.is_world_map_open(), "HudOverlay.set_world_map_open(false) must close WorldMapOverlay")

	hud.queue_free()
	harbor_ui.queue_free()
	p_grid.queue_free()
	player.queue_free()
	ai.clear_all()
	ai.queue_free()
	loot.clear_all()
	loot.queue_free()
	combat.clear_all()
	combat.queue_free()
	world_map.queue_free()
	print("  -> [PASS] Multi-pellet weapons, bow chaser, harbor immunity, AI retreat, tiered loot, death penalty & UI verified.")


func _test_visual_pipeline_and_headless_server_boot() -> void:
	print("[TEST 4/4] 2D Sprite-Stacking (6 Classes), 27 Item Icons, Ocean 4-Quadrant Coverage & Headless Server Sync...")

	# 1. Verify ProceduralShipBaker generates 24 crisp 64x32 1:1 pixel layers for ALL 6 ship classes + ALL 27 item icons
	for tier in range(6):
		var layers: Array[ImageTexture] = ProceduralShipBaker.bake_ship_layers(Contracts.ShipFaction.PLAYER, 24, tier)
		_assert_true(layers.size() == 24, "ProceduralShipBaker must bake 24 layers for hull_tier %d (got %d)" % [tier, layers.size()])
		_assert_true(layers[0].get_width() == 64 and layers[0].get_height() == 32, "Baked ship layer texture must be 64x32 px")

	var kraken_tex: ImageTexture = ProceduralShipBaker.bake_kraken_body_texture(false)
	_assert_true(kraken_tex != null and kraken_tex.get_width() == 64 and kraken_tex.get_height() == 64, "Kraken body texture must be 64x64")
	var tent_tex: ImageTexture = ProceduralShipBaker.bake_kraken_tentacle_texture(0, false)
	_assert_true(tent_tex != null and tent_tex.get_width() == 32 and tent_tex.get_height() == 32, "Kraken tentacle texture must be 32x32")
	var fort_tex: ImageTexture = ProceduralShipBaker.bake_fort_texture()
	_assert_true(fort_tex != null and fort_tex.get_width() == 48 and fort_tex.get_height() == 48, "Fort texture must be 48x48")

	var all_ids: Array[String] = ItemDatabase.get_all_ids()
	_assert_true(all_ids.size() == 27, "Expected 27 items for icon baking (got %d)" % all_ids.size())
	for item_id in all_ids:
		var item_data: Contracts.GridItemData = ItemDatabase.create_item(item_id)
		var icon_tex: ImageTexture = ProceduralShipBaker.bake_item_grid_icon(
			item_data.id,
			item_data.category,
			item_data.width,
			item_data.height,
			item_data.rarity,
			item_data.affix
		)
		_assert_true(icon_tex != null and icon_tex.get_width() == item_data.width * 24 and icon_tex.get_height() == item_data.height * 24, "Item '%s' must bake a %dx%d grid icon texture" % [item_id, item_data.width * 24, item_data.height * 24])

	var bow_mod_tex: ImageTexture = ProceduralShipBaker.bake_module_texture(Contracts.ItemCategory.BOW_WEAPON, Contracts.ItemRarity.RARE)
	_assert_true(bow_mod_tex != null and bow_mod_tex.get_width() > 0, "ProceduralShipBaker must bake BOW_WEAPON module texture")

	# 2. Verify OceanRenderer covers all 4 quadrants around camera center
	var ocean := OceanRenderer.new()
	root.add_child(ocean)
	ocean.setup(Contracts.DEFAULT_WORLD_SEED)
	ocean.set_camera_center(Vector2.ZERO)
	_assert_true(ocean._ocean_sprite != null and not ocean._ocean_sprite.centered, "OceanQuad Sprite2D must use centered=false")
	_assert_true(ocean._ocean_sprite.position.x <= -320.0 and ocean._ocean_sprite.position.y <= -180.0, "OceanQuad top-left must cover top-left quadrant")
	_assert_true(ocean._harbor_buoy_markers.size() == 3, "OceanRenderer must only create buoy rings for the 3 safe harbors (got %d)" % ocean._harbor_buoy_markers.size())
	ocean.queue_free()

	# 3. Verify ShipStackRenderer 24-layer stacking across tiers 0..5, BOW socket & sunk state
	var renderer := ShipStackRenderer.new()
	root.add_child(renderer)
	renderer.setup_ship(1, Contracts.ShipFaction.PLAYER, "Morgenstern")
	for tier in range(6):
		renderer.set_hull_tier(tier)
		_assert_true(renderer.hull_tier == tier and renderer._layer_sprites.size() == 24, "ShipStackRenderer must maintain 24 layers for tier %d" % tier)
	renderer.update_transform_state(Vector2(100.0, 50.0), 0.75, 60.0, Contracts.SailState.FULL_SAIL, 280.0, 280.0)
	renderer.update_equipped_modules([
		{ "category": Contracts.ItemCategory.CANNON, "slot_type": Contracts.SlotType.DECK_PORT, "grid_x": 2, "grid_y": 0, "rarity": 1, "affix": 0 },
		{ "category": Contracts.ItemCategory.BOW_WEAPON, "slot_type": Contracts.SlotType.BOW, "grid_x": 9, "grid_y": 3, "rarity": 2, "affix": 2 }
	])
	_assert_true(renderer.position.distance_to(Vector2(100.0, 50.0)) < 1.0, "ShipStackRenderer must update world position")
	renderer.set_sunk(true)
	_assert_true(renderer._is_sunk and not renderer._wake_line.visible, "ShipStackRenderer.set_sunk(true) must suppress wake line")
	renderer.queue_free()

	# 4. Verify Main scene Hybrid Rendering, ServerConfig, Forts, Kraken & Headless Server + Client Snapshot Roundtrip
	var srv_cfg: Script = load("res://net/server_config.gd") as Script
	var initial_url: String = str(srv_cfg.call("get_initial_server_url"))
	_assert_true(not initial_url.is_empty(), "ServerConfig.get_initial_server_url() must return a non-empty URL")
	srv_cfg.call("save_profile", "Käpt'n Rotbart", srv_cfg.get("DEFAULT_SERVER_URL"))
	_assert_true(str(srv_cfg.call("load_captain_name")) == "Käpt'n Rotbart", "ServerConfig must persist captain_name")

	var main_scene: PackedScene = load("res://main.tscn") as PackedScene
	_assert_true(main_scene != null, "res://main.tscn must load cleanly")
	var main_node: Main = main_scene.instantiate() as Main
	_assert_true(main_node != null, "Main scene must instantiate cleanly")
	root.add_child(main_node)

	_assert_true(main_node.world_viewport_container != null and main_node.world_viewport_container.stretch and main_node.world_viewport_container.stretch_shrink == 2, "Main must have SubViewportContainer with stretch=true and stretch_shrink=2")
	_assert_true(main_node.world_subviewport != null and main_node.world_subviewport.get_parent() == main_node.world_viewport_container, "Main must have SubViewport inside SubViewportContainer")
	_assert_true(main_node.world_subviewport.snap_2d_transforms_to_pixel, "GameSubViewport must have snap_2d_transforms_to_pixel=true")
	_assert_true(main_node.world_root.get_parent() == main_node.world_subviewport, "WorldRoot must live inside GameSubViewport")
	_assert_true(main_node.ui_layer.get_parent() == main_node, "UILayer must live directly under Main outside SubViewport")

	# Test Solo mode initialization inside Main
	main_node._on_solo_pressed()
	_assert_true(main_node.game_started and main_node.player_ship != null, "Main Solo mode must initialize player_ship and simulation")
	_assert_true(main_node.hud_overlay != null and main_node.harbor_ui != null and main_node.cargo_grid_ui != null, "Main Solo mode must initialize HudOverlay, HarborUI & CargoGridUI")
	_assert_true(main_node.combat_system.forts.size() == 5, "CombatSystem must initialize 5 coastal forts on wild islands")
	var kraken_id: int = main_node.ai_director.spawn_sea_monster(Vector2(320.0, -240.0))
	_assert_true(kraken_id > 0, "AIDirector must spawn giant Kraken sea monster event")
	main_node._physics_process(0.05)

	# Switch Main into Headless Server mode on ephemeral port 18089 and step server loop
	main_node._clear_game_world()
	main_node.is_headless_server = true
	main_node._init_simulation(Contracts.DEFAULT_WORLD_SEED, true)
	main_node.ai_director.populate_initial_fleet(3, 3)
	main_node.loot_system.spawn_initial_flotsam(main_node.world_map, 4)
	main_node.network_manager.bind_simulation(
		main_node.world_map,
		main_node.combat_system,
		main_node.loot_system,
		main_node.ai_director,
		main_node.all_ships
	)
	var srv_err: int = main_node.network_manager.start_server(18089, Contracts.DEFAULT_WORLD_SEED)
	_assert_true(srv_err == OK, "NetworkManager WebSocket server must bind cleanly (err=%d)" % srv_err)
	main_node._on_server_peer_joined(4242, "TestPeer")
	for _i in range(5):
		main_node._physics_process(0.05)

	var srv_ships_count: int = main_node.all_ships.size() + main_node.ai_director.ai_ships.size()
	_assert_true(srv_ships_count == 7, "Server must track joined player ship + 6 AI ships (got %d)" % srv_ships_count)
	var peer_ship: Node = main_node.all_ships.get(4242, null)
	_assert_true(peer_ship != null, "Server must spawn joined peer ship")
	peer_ship.call("set_sail_state", Contracts.SailState.FULL_SAIL)
	for _i in range(20):
		main_node._physics_process(0.05)
	_assert_true(float(peer_ship.get("speed")) > 20.0, "Server-side peer ship must sail forward under FULL_SAIL (speed=%.2f)" % float(peer_ship.get("speed")))

	# Build snapshot array just like _broadcast_world_snapshot and feed to client _on_snapshot_received
	var snap_ships: Array = []
	for s in main_node.all_ships.values():
		snap_ships.append(s.call("to_sync_dict"))
	for ai_s in main_node.ai_director.ai_ships.values():
		snap_ships.append(ai_s.call("to_sync_dict"))
	var test_snapshot: Dictionary = {
		"t": 1.5,
		"wind_x": 1.0,
		"wind_y": 0.0,
		"wind_strength": 0.8,
		"weather_state": main_node.world_map.current_weather,
		"weather_intensity": main_node.world_map.weather_intensity,
		"wanted_level": main_node.ai_director.wanted_level,
		"ships": snap_ships,
		"drops": main_node.loot_system.to_sync_array(),
		"forts": main_node.combat_system.get_fort_sync_array(),
		"sea_monster": {}
	}
	main_node.network_manager.shutdown()
	main_node._clear_game_world()
	main_node.is_headless_server = false
	main_node.player_ship_id = 4242
	main_node._init_simulation(Contracts.DEFAULT_WORLD_SEED, false)
	main_node._on_snapshot_received(test_snapshot)
	_assert_true(main_node.all_ships.size() == 7, "Client _on_snapshot_received must instantiate player and all 6 AI ships (got %d)" % main_node.all_ships.size())
	_assert_true(main_node.combat_system.forts.size() == 5, "Client _on_snapshot_received must sync all 5 wild island forts (got %d)" % main_node.combat_system.forts.size())
	_assert_true(main_node.world_map.current_weather == Contracts.WeatherState.CLEAR, "Client synced weather must stay CLEAR")
	_assert_true(main_node.loot_system.drops.size() == 4, "Client _on_snapshot_received must sync 4 loot drops (got %d)" % main_node.loot_system.drops.size())
	main_node._clear_game_world()
	main_node.queue_free()

	print("  -> [PASS] 6-tier Sprite-Stacking, 27 Item Icons, 4-Quadrant Ocean, 5 Forts, Kraken & Headless Server Sync verified.")

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
	_test_user_auth_and_save_persistence()

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
	print("[TEST 1/5] Deterministic World (21600x21600), 18 Islands, 5 Safe Harbors, Clear Weather & 9-tier ShipPhysics...")
	var seed_val: int = Contracts.DEFAULT_WORLD_SEED

	_assert_true(is_equal_approx(Contracts.WORLD_HALF_EXTENT, 10800.0), "WORLD_HALF_EXTENT must be 10800.0 (21600x21600)")
	_assert_true(Contracts.ISLAND_COUNT == 18, "ISLAND_COUNT must be 18 (got %d)" % Contracts.ISLAND_COUNT)
	_assert_true(Contracts.SAFE_HARBOR_INDICES.size() == 5, "SAFE_HARBOR_INDICES must contain 5 safe harbors (got %d)" % Contracts.SAFE_HARBOR_INDICES.size())

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

	# 2. WorldMap setup & islands (5 safe harbors, 13 wild islands, 13 wild coastal forts)
	var world_map := WorldMap.new()
	root.add_child(world_map)
	world_map.setup(seed_val)

	_assert_true(world_map.islands.size() == 18, "WorldMap must generate exactly 18 named islands (got %d)" % world_map.islands.size())

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

	_assert_true(safe_harbor_count == 5, "Must have exactly 5 safe harbors (got %d)" % safe_harbor_count)
	_assert_true(wild_island_count == 13, "Must have exactly 13 wild islands (got %d)" % wild_island_count)

	var fort_positions: Array[Dictionary] = world_map.get_fort_positions()
	_assert_true(fort_positions.size() == 13, "WorldMap must place exactly 13 coastal forts on wild islands (got %d)" % fort_positions.size())
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

	# Test all 9 ship class upgrades & harbor protection
	for tier in range(9):
		ship.upgrade_ship_class(tier)
		var spec: Dictionary = Contracts.get_ship_class_spec(tier)
		_assert_true(ship.hull_tier == tier, "ShipPhysics.upgrade_ship_class(%d) must update hull_tier" % tier)
		_assert_true(is_equal_approx(ship.max_hp, float(spec["base_hp"])), "ShipPhysics tier %d max_hp must match SHIP_CLASS_SPECS" % tier)
		_assert_true(is_equal_approx(ship.hull_radius, float(spec["hull_radius"])), "ShipPhysics tier %d hull_radius must match spec" % tier)
		_assert_true(is_equal_approx(ship.stats.innate_ram_bonus, float(spec.get("ram_bonus", 0.0))), "ShipPhysics tier %d innate_ram_bonus must match spec" % tier)

	var safe_isl0: Contracts.IslandData = world_map.get_island(0)
	ship.world_pos = safe_isl0.harbor_pos
	ship.step_physics(0.02, 0.0, world_map)
	_assert_true(ship.is_harbor_protected(), "Player ship inside safe harbor zone must report is_harbor_protected() == true")

	ship.queue_free()
	world_map.queue_free()
	print("  -> [PASS] 21600x21600 world, 18 islands, 5 safe harbors, 13 wild forts, clear weather & 9-tier ShipPhysics verified.")


func _test_dredge_grid_rotation_synergy_and_stats() -> void:
	print("[TEST 2/5] 9-Class DredgeGrids (6x4..12x7), SlotType.BOW (2 Lanes on Xebec), Cursed Sails, Downsize Eviction & 27 Items...")

	var all_ids: Array[String] = ItemDatabase.get_all_ids()
	_assert_true(all_ids.size() == 27, "ItemDatabase must define exactly 27 items (got %d)" % all_ids.size())
	for new_id in ["carronade_2x1", "organ_gun_2x2", "twin_cannon_2x3", "pitch_mortar_2x2", "bow_chaser_1x2"]:
		_assert_true(new_id in all_ids, "ItemDatabase must contain new weapon '%s'" % new_id)

	var grid := DredgeGrid.new()
	grid.ship_id = 1
	root.add_child(grid)

	# Verify exact grid sizes for all 9 ShipClass tiers
	var expected_dims: Dictionary = {
		Contracts.ShipClass.SLOOP: Vector2i(6, 4),
		Contracts.ShipClass.SCHOONER: Vector2i(6, 5),
		Contracts.ShipClass.BRIGANTINE: Vector2i(7, 5),
		Contracts.ShipClass.FRIGATE: Vector2i(8, 6),
		Contracts.ShipClass.CORSAIR_CLIPPER: Vector2i(6, 5),
		Contracts.ShipClass.WAR_GALLEON: Vector2i(10, 7),
		Contracts.ShipClass.CORSAIR_XEBEC: Vector2i(8, 5),
		Contracts.ShipClass.IRONCLAD: Vector2i(9, 6),
		Contracts.ShipClass.MAN_O_WAR: Vector2i(12, 7)
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

	# Verify ship class costs across all 9 tiers (0..5 escalating, 6..8 escalating, all >= 1 paid)
	var prev_cost: int = -1
	for t_idx in range(6):
		var c_val: int = int(Contracts.get_ship_class_spec(t_idx).get("cost", 0))
		_assert_true(c_val > prev_cost, "ShipClass %d cost (%d) must exceed previous (%d)" % [t_idx, c_val, prev_cost])
		prev_cost = c_val
	var prev_late_cost: int = 0
	for t_idx in [Contracts.ShipClass.CORSAIR_XEBEC, Contracts.ShipClass.IRONCLAD, Contracts.ShipClass.MAN_O_WAR]:
		var c_val: int = int(Contracts.get_ship_class_spec(t_idx).get("cost", 0))
		_assert_true(c_val > prev_late_cost, "ShipClass %d cost (%d) must exceed %d" % [t_idx, c_val, prev_late_cost])
		prev_late_cost = c_val

	# 7. Verify bow_chaser_1x2 also mounts cleanly on War Galleon (10x7), Xebec (8x5, 2 BOW lanes), Ironclad (9x6) & Man-o'-War (12x7)
	grid.set_hull_tier(Contracts.ShipClass.WAR_GALLEON)
	var galleon_bow: Contracts.GridItemData = ItemDatabase.create_item("bow_chaser_1x2")
	_assert_true(grid.place_item(galleon_bow, 8, 3, true), "bow_chaser_1x2 rotated (2x1) must mount on War Galleon (8,3)->(9,3) BOW")
	_assert_true(grid.current_stats.bow_cannons.size() == 1, "War Galleon bow chaser must compile into bow_cannons")

	# Tier 6: CORSAIR_XEBEC (8x5) has 2 BOW lanes allowing 2 simultaneous horizontal bow chasers
	var xebec_grid := DredgeGrid.new()
	xebec_grid.set_hull_tier(Contracts.ShipClass.CORSAIR_XEBEC)
	_assert_true(
		xebec_grid.get_slot_type(6, 1) == Contracts.SlotType.BOW and xebec_grid.get_slot_type(7, 1) == Contracts.SlotType.BOW
		and xebec_grid.get_slot_type(6, 3) == Contracts.SlotType.BOW and xebec_grid.get_slot_type(7, 3) == Contracts.SlotType.BOW,
		"CORSAIR_XEBEC (8x5) must expose 2 horizontal BOW lanes at (6..7,1) and (6..7,3)"
	)
	var x_bow1 := ItemDatabase.create_item("bow_chaser_1x2")
	var x_bow2 := ItemDatabase.create_item("bow_chaser_1x2")
	_assert_true(xebec_grid.place_item(x_bow1, 6, 1, true) and xebec_grid.place_item(x_bow2, 6, 3, true), "CORSAIR_XEBEC must fit 2 bow_chaser_1x2 across its 2 BOW lanes")
	_assert_true(xebec_grid.current_stats.bow_cannons.size() == 2, "CORSAIR_XEBEC must compile 2 active bow_cannons (got %d)" % xebec_grid.current_stats.bow_cannons.size())
	_assert_true(is_equal_approx(xebec_grid.current_stats.innate_ram_bonus, 12.0), "CORSAIR_XEBEC must have 12.0 innate_ram_bonus")
	xebec_grid.free()

	# Tier 7: IRONCLAD (9x6) & Tier 8: MAN_O_WAR (12x7)
	var heavy_grid := DredgeGrid.new()
	heavy_grid.set_hull_tier(Contracts.ShipClass.IRONCLAD)
	_assert_true(heavy_grid.get_grid_width() == 9 and heavy_grid.get_grid_height() == 6, "IRONCLAD grid must be 9x6")
	_assert_true(is_equal_approx(heavy_grid.current_stats.armor, 24.0) and is_equal_approx(heavy_grid.current_stats.innate_ram_bonus, 24.0), "IRONCLAD must compile 24.0 base armor and 24.0 innate_ram_bonus")
	heavy_grid.set_hull_tier(Contracts.ShipClass.MAN_O_WAR)
	_assert_true(heavy_grid.get_grid_width() == 12 and heavy_grid.get_grid_height() == 7, "MAN_O_WAR grid must be 12x7")
	_assert_true(is_equal_approx(heavy_grid.current_stats.max_hp, 1040.0), "MAN_O_WAR must compile 1040.0 base max_hp")
	heavy_grid.free()

	# 8. Verify 5-tier affix scaling (Selten / Meisterhaft / Verflucht), +1 polyomino shapes, L-corner nesting & Fix #3 cursed sails
	var c_rare := ItemDatabase.create_item("carronade_2x1", Contracts.ItemAffix.RARE)
	var c_mast := ItemDatabase.create_item("carronade_2x1", Contracts.ItemAffix.MASTERWORK)
	var c_curs := ItemDatabase.create_item("carronade_2x1", Contracts.ItemAffix.CURSED)
	_assert_true(is_equal_approx(c_rare.get_affix_stat_multiplier(), 1.25) and c_rare.get_display_name().begins_with("Selten:"), "RARE affix must grant 1.25x & 'Selten:' prefix")
	_assert_true(is_equal_approx(c_mast.get_affix_stat_multiplier(), 1.45) and c_mast.get_display_name().begins_with("Meisterhaft:"), "MASTERWORK affix must grant 1.45x & 'Meisterhaft:' prefix")
	_assert_true(is_equal_approx(c_curs.get_affix_stat_multiplier(), 1.75) and c_curs.get_display_name().begins_with("Verflucht:"), "CURSED affix must grant 1.75x & 'Verflucht:' prefix")
	_assert_true(c_curs.get_effective_range() > c_curs.cannon_range and c_curs.get_effective_burn_dps() >= 5.0, "CURSED weapon must grant extra range (+15%) and innate abyssal burn (+5 DPS)")
	_assert_true(not c_curs.shape_offsets.is_empty() and c_curs.get_cell_count() == 3, "CURSED 2x1 non-sail item must keep eldritch shape of 2+1=3 cells (got %d)" % c_curs.get_cell_count())

	# Fix #3: Cursed sails keep rectangular shape (shape_offsets empty) so they always fit MAST slots
	var cursed_storm := ItemDatabase.create_item("storm_sails_2x2", Contracts.ItemAffix.CURSED)
	var cursed_silk := ItemDatabase.create_item("silk_top_sail_1x2", Contracts.ItemAffix.CURSED)
	_assert_true(cursed_storm.shape_offsets.is_empty() and cursed_storm.get_cell_count() == 4 and cursed_storm.get_effective_bbox(0) == Vector2i(2, 2), "CURSED storm_sails_2x2 must keep rectangular 2x2 shape (shape_offsets empty)")
	_assert_true(cursed_silk.shape_offsets.is_empty() and cursed_silk.get_cell_count() == 2 and cursed_silk.get_effective_bbox(0) == Vector2i(1, 2), "CURSED silk_top_sail_1x2 must keep rectangular 1x2 shape (shape_offsets empty)")
	var restored_cursed_sail := Contracts.GridItemData.from_dict(cursed_storm.to_dict())
	_assert_true(restored_cursed_sail.affix == Contracts.ItemAffix.CURSED and restored_cursed_sail.shape_offsets.is_empty(), "CURSED sail to_dict/from_dict must preserve CURSED affix and rectangular shape")

	var test_grid := DredgeGrid.new()
	test_grid.set_hull_tier(Contracts.ShipClass.WAR_GALLEON)
	test_grid.placed_items.clear()
	test_grid.stash_items.clear()
	_assert_true(test_grid.place_item(cursed_storm, 3, 2, 0), "CURSED storm_sails_2x2 must fit cleanly into rectangular MAST slots")
	var cursed_spice := ItemDatabase.create_item("spice_crates_1x2", Contracts.ItemAffix.CURSED)
	_assert_true(cursed_spice.get_cell_count() == 3 and cursed_spice.get_effective_bbox(0) == Vector2i(2, 2), "CURSED 1x2 non-sail item must have L-shape of 3 cells inside 2x2 bbox")
	_assert_true(test_grid.place_item(cursed_spice, 0, 1, 0), "Must place CURSED L-shape at (0,1) rot=0")
	var corner_rum := ItemDatabase.create_item("rum_casks_1x1", Contracts.ItemAffix.STANDARD)
	_assert_true(test_grid.can_place_item(corner_rum, 1, 1, 0) and test_grid.place_item(corner_rum, 1, 1, 0), "1x1 item must fit inside the open empty corner (1,1) of the CURSED L-shape")
	var collide_rum := ItemDatabase.create_item("rum_casks_1x1", Contracts.ItemAffix.STANDARD)
	_assert_true(not test_grid.can_place_item(collide_rum, 1, 2, 0), "Protruding cursed cell (1,2) must block overlapping placement")
	_assert_true(test_grid.rotate_item_in_grid(cursed_spice) or cursed_spice.get_rotated_local_cells(1) != cursed_spice.get_rotated_local_cells(0), "CURSED polyomino must support 4-step rotation")
	var raw_spice: Dictionary = cursed_spice.to_dict()
	var restored_spice := Contracts.GridItemData.from_dict(raw_spice)
	_assert_true(restored_spice.affix == Contracts.ItemAffix.CURSED and restored_spice.get_cell_count() == 3, "GridItemData to_dict/from_dict must preserve CURSED shape")
	test_grid.queue_free()

	grid.queue_free()
	print("  -> [PASS] 9-class grids, BOW slots (2 lanes on Xebec), cursed sails, downsize stash eviction, 27 items & synergy stats verified.")


func _test_combat_ai_rng_loot_and_quests() -> void:
	print("[TEST 3/5] Combat, Hybrid Armor, Speed Ramming, AI Chased Keepalive, Hull-Scaled Loot, FxManager Clear, HarborUI & Coords HUD...")

	var bus: Contracts = Contracts.bus()
	var world_map := WorldMap.new()
	root.add_child(world_map)
	world_map.setup(Contracts.DEFAULT_WORLD_SEED)

	var combat := CombatSystem.new()
	root.add_child(combat)
	combat.setup_island_forts(world_map)
	_assert_true(combat.forts.size() == 13, "CombatSystem must initialize 13 coastal forts on wild islands (got %d)" % combat.forts.size())

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

	# Verify AI FLEE_TO_PORT open-sea retreat, chased/under-fire keepalive (Fix #1) & distant despawn
	pirate.hp = pirate.max_hp * 0.20
	var ships_dict: Dictionary = { 1: player, pirate_id: pirate, bow_target_id: bow_target }
	ai.step_ai(0.1, ships_dict)
	var p_state: int = ai.get_ship_ai_state(pirate_id)
	_assert_true(p_state == Contracts.AIState.FLEE_TO_PORT, "AI ship below 30%% HP must enter FLEE_TO_PORT state (got %d)" % p_state)
	pirate.world_pos = Vector2(2200.0, 2200.0) # Far beyond FLEE_HARD_DESPAWN_DIST
	ai.step_ai(0.1, ships_dict)
	_assert_true(not ai.ai_ships.has(pirate_id), "Fleeing AI ship beyond FLEE_HARD_DESPAWN_DIST must despawn cleanly")

	# Fix #1: Chased/under-fire AI merchant/galleon must NOT despawn after 20+ seconds under fire
	var galleon_id: int = ai.spawn_ai_ship(Contracts.ShipFaction.MERCHANT, Vector2(260.0, 0.0), false, "", Contracts.ShipClass.WAR_GALLEON, true)
	var galleon: ShipPhysics = ai.ai_ships.get(galleon_id, null)
	_assert_true(galleon != null, "AIDirector must spawn treasure galleon")
	ships_dict[galleon_id] = galleon
	combat._apply_direct_damage(galleon, galleon_id, galleon.max_hp * 0.75, galleon.world_pos, 1, false)
	for tick in range(44):
		if tick == 20:
			combat._apply_direct_damage(galleon, galleon_id, 5.0, galleon.world_pos, 1, false)
		galleon.world_pos = Vector2(1500.0, 0.0) # Within chase/keepalive distance while fleeing
		ai.step_ai(0.5, ships_dict)
	_assert_true(ai.ai_ships.has(galleon_id) and ai.get_ship_ai_state(galleon_id) == Contracts.AIState.FLEE_TO_PORT, "Fix #1: Chased/under-fire treasure galleon must NOT despawn after 22s under fire")
	# Once fire ceases and galleon is beyond FLEE_HARD_DESPAWN_DIST, it despawns cleanly
	ai.ai_brains[galleon_id]["under_fire_timer"] = 0.0
	galleon.world_pos = Vector2(3100.0, 0.0)
	ai.step_ai(0.1, ships_dict)
	_assert_true(not ai.ai_ships.has(galleon_id), "Abandoned galleon beyond FLEE_HARD_DESPAWN_DIST must despawn cleanly")

	# Fix #5 & #6: Hybrid armor mitigation & speed-scaled ramming (iron_ram_1x2 zero recoil)
	_assert_true(is_equal_approx(CombatSystem._apply_hybrid_armor(40.0, 0.0, 2.0), 40.0), "Unarmored hybrid armor must pass full 40.0 damage")
	var dmg_galleon: float = CombatSystem._apply_hybrid_armor(40.0, float(Contracts.get_ship_class_spec(Contracts.ShipClass.WAR_GALLEON)["armor"]), 2.0)
	var dmg_ironclad: float = CombatSystem._apply_hybrid_armor(40.0, float(Contracts.get_ship_class_spec(Contracts.ShipClass.IRONCLAD)["armor"]), 2.0)
	var dmg_plated: float = CombatSystem._apply_hybrid_armor(40.0, float(Contracts.get_ship_class_spec(Contracts.ShipClass.IRONCLAD)["armor"]) + 11.0, 2.0)
	_assert_true(dmg_galleon < 22.0 and dmg_ironclad < dmg_galleon and dmg_plated < dmg_ironclad and dmg_plated >= 2.0, "Fix #5: Hybrid armor mitigation must scale down damage across WAR_GALLEON -> IRONCLAD -> copper_plating_2x2 (%.2f > %.2f > %.2f)" % [dmg_galleon, dmg_ironclad, dmg_plated])

	var iron_target := ShipPhysics.new()
	root.add_child(iron_target)
	iron_target.setup(91, Vector2(0.0, 240.0), 0.0, Contracts.ShipFaction.PIRATE, "PanzerZiel")
	var iron_grid := DredgeGrid.new()
	iron_grid.ship_id = 91
	iron_grid.set_hull_tier(Contracts.ShipClass.IRONCLAD)
	var copper_plate := ItemDatabase.create_item("copper_plating_2x2")
	_assert_true(iron_grid.place_item(copper_plate, 0, 1, 0), "copper_plating_2x2 must fit IRONCLAD CARGO_HOLD at (0,1)")
	iron_target.apply_stats(iron_grid.compile_stats())
	_assert_true(is_equal_approx(iron_target.stats.armor, 35.0), "IRONCLAD (24) + copper_plating_2x2 (11) must compile 35.0 armor")
	combat.register_ship(iron_target)
	var iron_hp0: float = iron_target.hp
	combat._apply_ship_hit({"damage": 40.0, "shooter_id": 1}, iron_target, 91, iron_target.world_pos, "midships")
	_assert_true(is_equal_approx(iron_hp0 - iron_target.hp, dmg_plated), "Fix #5: Midships hit on plated IRONCLAD must apply hybrid armor mitigation")
	combat.unregister_ship(91)
	iron_grid.free()
	iron_target.free()

	# Fix #6: Speed-scaled ramming (approach > 100 deals > 24 base damage, iron_ram_1x2 takes 0 recoil)
	var rammer := ShipPhysics.new()
	var victim := ShipPhysics.new()
	root.add_child(rammer)
	root.add_child(victim)
	rammer.setup(92, Vector2.ZERO, 0.0, Contracts.ShipFaction.PLAYER, "Rammer")
	victim.setup(93, Vector2(20.0, 0.0), PI, Contracts.ShipFaction.PIRATE, "Victim")
	rammer.velocity = Vector2(130.0, 0.0)
	victim.velocity = Vector2.ZERO
	combat.register_ship(rammer)
	combat.register_ship(victim)
	combat._ram_cooldowns.clear()
	combat._resolve_ram_pair(rammer, victim)
	var bare_ram_dmg: float = 120.0 - victim.hp
	var bare_recoil: float = 120.0 - rammer.hp
	_assert_true(bare_ram_dmg > 24.0, "Fix #6: High-speed ram (approach=130 > 100) must deal > 24 damage (got %.2f)" % bare_ram_dmg)
	_assert_true(is_equal_approx(bare_recoil, 4.0), "Unarmored rammer without iron_ram_1x2 must take 4.0 recoil damage (got %.2f)" % bare_recoil)

	var ram_grid := DredgeGrid.new()
	ram_grid.ship_id = 92
	ram_grid.set_hull_tier(Contracts.ShipClass.SLOOP)
	var iron_ram := ItemDatabase.create_item("iron_ram_1x2")
	_assert_true(ram_grid.place_item(iron_ram, 1, 1, 0), "iron_ram_1x2 must fit in SLOOP CARGO_HOLD")
	rammer.apply_stats(ram_grid.compile_stats())
	rammer.hp = rammer.max_hp
	victim.hp = victim.max_hp
	rammer.world_pos = Vector2.ZERO
	victim.world_pos = Vector2(20.0, 0.0)
	rammer.velocity = Vector2(130.0, 0.0)
	victim.velocity = Vector2.ZERO
	combat._ram_cooldowns.clear()
	combat._resolve_ram_pair(rammer, victim)
	_assert_true(is_equal_approx(rammer.hp, rammer.max_hp), "Fix #6: Rammer with iron_ram_1x2 must take 0 recoil damage")
	_assert_true((victim.max_hp - victim.hp) > bare_ram_dmg + 20.0, "Fix #6: iron_ram_1x2 must massively amplify speed-scaled ram damage")
	combat.unregister_ship(92)
	combat.unregister_ship(93)
	ram_grid.free()
	rammer.free()
	victim.free()

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

	# Fix #2: hull_radius-scaled pickup radius + loot_cleared & FxManager.clear_fx() cleanup
	player.upgrade_ship_class(Contracts.ShipClass.SLOOP)
	player.world_pos = Vector2.ZERO
	var edge_drop: Contracts.LootDropData = loot.spawn_ship_wreck_loot(Vector2(45.5, 0.0), Contracts.ShipFaction.PIRATE, false, Contracts.ShipClass.SLOOP, false)
	loot.step_loot(0.05, { 1: player }, p_grid, false)
	_assert_true(loot.drops.has(edge_drop.drop_id), "Fix #2: SLOOP (hull_radius=14 -> pickup=44px) must NOT pick up crate at 45.5px without interact")
	player.upgrade_ship_class(Contracts.ShipClass.MAN_O_WAR)
	loot.step_loot(0.05, { 1: player }, p_grid, false)
	_assert_true(not loot.drops.has(edge_drop.drop_id), "Fix #2: MAN_O_WAR (hull_radius=25 -> pickup=47px) MUST pick up crate at 45.5px")
	player.upgrade_ship_class(Contracts.ShipClass.FRIGATE)

	var fx_test := FxManager.new()
	root.add_child(fx_test)
	fx_test.bind_loot_system(loot)
	var cleared_count: Array[int] = [0]
	loot.loot_cleared.connect(func(): cleared_count[0] += 1)
	var fx_drop: Contracts.LootDropData = loot.spawn_ship_wreck_loot(Vector2(180.0, 0.0), Contracts.ShipFaction.PIRATE, false, Contracts.ShipClass.SLOOP, false)
	_assert_true(fx_test._loot_crates.has(fx_drop.drop_id), "FxManager must track spawned loot crate sprite")
	loot.clear_all()
	_assert_true(cleared_count[0] == 1 and fx_test._loot_crates.is_empty(), "Fix #2: LootSystem.clear_all() must emit loot_cleared and clear FxManager._loot_crates")
	loot.spawn_ship_wreck_loot(Vector2(190.0, 0.0), Contracts.ShipFaction.PIRATE, false, Contracts.ShipClass.SLOOP, false)
	fx_test._projectiles.append({"pos": Vector2.ZERO})
	fx_test.clear_fx()
	_assert_true(fx_test._loot_crates.is_empty() and fx_test._projectiles.is_empty(), "Fix #2: FxManager.clear_fx() must purge loot crates and projectiles")
	fx_test.free()
	loot.clear_all()

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
	_assert_true(delivery_quest != null and (delivery_quest.target_island_idx in Contracts.SAFE_HARBOR_INDICES), "DELIVERY quest target must be one of the 5 safe harbors")
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

	# Fix #8: HudOverlay / HudLabelsView.lbl_coords updates coordinates cleanly
	_assert_true(hud._labels != null and hud._labels.lbl_coords != null, "HudLabelsView must build lbl_coords")
	player.world_pos = Vector2(450.0, -320.0)
	hud._process(0.1)
	_assert_true(hud._labels.lbl_coords.text == "POS: X +450  Y -320", "Fix #8: HudLabelsView.lbl_coords must update to 'POS: X +450  Y -320' (got '%s')" % hud._labels.lbl_coords.text)
	hud._labels.sync_coords_pos(true)
	var y_with_bow: float = hud._labels.lbl_coords.position.y
	hud._labels.sync_coords_pos(false)
	_assert_true(y_with_bow > hud._labels.lbl_coords.position.y, "Fix #8: sync_coords_pos(true) must shift lbl_coords below bow bar")

	# Verify MinimapRenderer & WorldMapOverlay
	hud.toggle_world_map()
	_assert_true(hud.is_world_map_open(), "HudOverlay.toggle_world_map() must open WorldMapOverlay")
	_assert_true(hud._minimap != null and hud._minimap._baked_map_tex != null, "MinimapRenderer must bake static 21600x21600 world texture")
	_assert_true(hud._world_map != null and hud._world_map._baked_tex != null, "WorldMapOverlay must bake static 21600x21600 chart texture")
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
	print("  -> [PASS] Combat, hybrid armor, speed ramming, AI keepalive, hull-scaled loot, FxManager clear, HarborUI & coords HUD verified.")


func _test_visual_pipeline_and_headless_server_boot() -> void:
	print("[TEST 4/5] 2D Sprite-Stacking (9 Classes), 27 Item Icons (Cursed Sails Rectangular), Ocean 4-Quadrant Coverage & Headless Server Sync...")

	# 1. Verify ProceduralShipBaker generates 24 crisp 64x32 1:1 pixel layers for ALL 9 ship classes + ALL 27 item icons
	for tier in range(9):
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

	var cursed_cannon_tex: ImageTexture = ProceduralShipBaker.bake_item_grid_icon("bronze_cannon_2x2", Contracts.ItemCategory.CANNON, 2, 2, Contracts.ItemRarity.RARE, Contracts.ItemAffix.CURSED)
	_assert_true(cursed_cannon_tex != null and cursed_cannon_tex.get_width() == 72 and cursed_cannon_tex.get_height() == 48, "CURSED 2x2 item icon must expand to 3x2 bbox (72x48 px)")
	var cursed_spice_tex: ImageTexture = ProceduralShipBaker.bake_item_grid_icon("spice_crates_1x2", Contracts.ItemCategory.CARGO, 1, 2, Contracts.ItemRarity.UNCOMMON, Contracts.ItemAffix.CURSED)
	_assert_true(cursed_spice_tex != null and cursed_spice_tex.get_width() == 48 and cursed_spice_tex.get_height() == 48, "CURSED 1x2 item icon must expand to 2x2 L-bbox (48x48 px)")
	var cursed_storm_tex: ImageTexture = ProceduralShipBaker.bake_item_grid_icon("storm_sails_2x2", Contracts.ItemCategory.SAIL, 2, 2, Contracts.ItemRarity.RARE, Contracts.ItemAffix.CURSED)
	_assert_true(cursed_storm_tex != null and cursed_storm_tex.get_width() == 48 and cursed_storm_tex.get_height() == 48, "Fix #3: CURSED storm_sails_2x2 icon must remain 2x2 rectangular (48x48 px)")
	var cursed_silk_tex: ImageTexture = ProceduralShipBaker.bake_item_grid_icon("silk_top_sail_1x2", Contracts.ItemCategory.SAIL, 1, 2, Contracts.ItemRarity.UNCOMMON, Contracts.ItemAffix.CURSED)
	_assert_true(cursed_silk_tex != null and cursed_silk_tex.get_width() == 24 and cursed_silk_tex.get_height() == 48, "Fix #3: CURSED silk_top_sail_1x2 icon must remain 1x2 rectangular (24x48 px)")

	var bow_mod_tex: ImageTexture = ProceduralShipBaker.bake_module_texture(Contracts.ItemCategory.BOW_WEAPON, Contracts.ItemRarity.RARE)
	_assert_true(bow_mod_tex != null and bow_mod_tex.get_width() > 0, "ProceduralShipBaker must bake BOW_WEAPON module texture")

	# 2. Verify OceanRenderer covers all 4 quadrants around camera center
	var ocean := OceanRenderer.new()
	root.add_child(ocean)
	ocean.setup(Contracts.DEFAULT_WORLD_SEED)
	ocean.set_camera_center(Vector2.ZERO)
	_assert_true(ocean._ocean_sprite != null and not ocean._ocean_sprite.centered, "OceanQuad Sprite2D must use centered=false")
	_assert_true(ocean._ocean_sprite.position.x <= -320.0 and ocean._ocean_sprite.position.y <= -180.0, "OceanQuad top-left must cover top-left quadrant")
	_assert_true(ocean._harbor_buoy_markers.size() == 5, "OceanRenderer must only create buoy rings for the 5 safe harbors (got %d)" % ocean._harbor_buoy_markers.size())
	ocean.queue_free()

	# 3. Verify ShipStackRenderer 24-layer stacking across tiers 0..8, BOW socket & sunk state
	var renderer := ShipStackRenderer.new()
	root.add_child(renderer)
	renderer.setup_ship(1, Contracts.ShipFaction.PLAYER, "Morgenstern")
	for tier in range(9):
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
	_assert_true(main_node.combat_system.forts.size() == 13, "CombatSystem must initialize 13 coastal forts on wild islands (got %d)" % main_node.combat_system.forts.size())
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
	_assert_true(main_node.combat_system.forts.size() == 13, "Client _on_snapshot_received must sync all 13 wild island forts (got %d)" % main_node.combat_system.forts.size())
	_assert_true(main_node.world_map.current_weather == Contracts.WeatherState.CLEAR, "Client synced weather must stay CLEAR")
	_assert_true(main_node.loot_system.drops.size() == 4, "Client _on_snapshot_received must sync 4 loot drops (got %d)" % main_node.loot_system.drops.size())
	main_node._clear_game_world()
	main_node.queue_free()

	print("  -> [PASS] 9-tier Sprite-Stacking, 27 Item Icons, 4-Quadrant Ocean, 13 Forts, Kraken & Headless Server Sync verified.")


func _test_user_auth_and_save_persistence() -> void:
	print("[TEST 5/5] SaveStore Auth (Register/Login/Token), Ship/Grid/Gold Save Roundtrip & StartMenuUI...")
	var save_store_script: Script = load("res://sim/save_store.gd") as Script
	var test_id: int = Time.get_ticks_usec()
	var test_dir: String = "user://test_accounts_%d" % test_id
	var test_solo: String = "user://test_solo_%d.json" % test_id
	var store = save_store_script.new(test_dir, test_solo)

	# 1. Validation rules
	_assert_true(not bool(save_store_script.call("validate_username", "ab")["ok"]), "Username < 3 chars must fail")
	_assert_true(not bool(save_store_script.call("validate_username", "bad/name")["ok"]), "Username with '/' must fail")
	_assert_true(bool(save_store_script.call("validate_username", "Käptn_Bob")["ok"]), "Valid username must pass")
	_assert_true(not bool(save_store_script.call("validate_password", "12")["ok"]), "Password < 3 chars must fail")
	_assert_true(bool(save_store_script.call("validate_password", "123")["ok"]), "Simple 3+ char password must pass")

	# 2. Register, duplicate block, wrong password, login, token login
	var reg_ok: Dictionary = store.register_account("BlackBeard", "rum123")
	_assert_true(bool(reg_ok.get("ok", false)), "First registration must succeed")
	var tok1: String = str(reg_ok.get("session_token", ""))
	_assert_true(not tok1.is_empty(), "Registration must issue non-empty session_token")

	var reg_dup: Dictionary = store.register_account("blackbeard", "other")
	_assert_true(not bool(reg_dup.get("ok", false)), "Duplicate case-insensitive registration must be rejected")

	var bad_pw: Dictionary = store.login_account("BlackBeard", "wrong")
	_assert_true(not bool(bad_pw.get("ok", false)), "Wrong password login must be rejected")

	var login_ok: Dictionary = store.login_account("blackbeard", "rum123")
	_assert_true(bool(login_ok.get("ok", false)), "Valid login must succeed case-insensitively")
	var tok2: String = str(login_ok.get("session_token", ""))
	_assert_true(not tok2.is_empty(), "Login must return valid session_token")

	var tok_ok: Dictionary = store.login_with_token("BlackBeard", tok2)
	_assert_true(bool(tok_ok.get("ok", false)), "Valid token login must succeed")
	var tok_bad: Dictionary = store.login_with_token("BlackBeard", "forged_token")
	_assert_true(not bool(tok_bad.get("ok", false)) and bool(tok_bad.get("clear_token", false)), "Invalid token login must fail with clear_token=true")

	# 3. Full ship/grid/gold/quest save roundtrip
	var p_grid := DredgeGrid.new()
	p_grid.ship_id = 77
	p_grid.set_hull_tier(Contracts.ShipClass.FRIGATE)
	p_grid.populate_starter_loadout()
	var bonus_gun := ItemDatabase.create_item("carronade_2x1", Contracts.ItemAffix.MASTERWORK)
	p_grid.auto_place_item(bonus_gun)

	var q := Contracts.QuestData.new()
	q.id = "q_test_deliv"
	q.quest_type = Contracts.QuestType.DELIVERY
	q.title = "Eilfracht nach San Aurelio"
	q.target_island_idx = 2
	q.reward_gold = 185

	var custom_save: Dictionary = {
		"gold": 2450,
		"hull_tier": Contracts.ShipClass.FRIGATE,
		"owned_ship_tiers": [Contracts.ShipClass.SLOOP, Contracts.ShipClass.FRIGATE],
		"hp": 275.5,
		"world_x": 420.0,
		"world_y": -310.0,
		"heading": 1.25,
		"has_saved_pos": true,
		"grid": p_grid.to_dict(),
		"active_quests": [q.to_dict()]
	}
	_assert_true(store.update_account_save("blackbeard", custom_save), "Account save update must succeed")

	var reloaded_acct: Dictionary = store.login_with_token("BlackBeard", tok2)
	var loaded_save: Dictionary = reloaded_acct.get("save_data", {})
	_assert_true(int(loaded_save.get("gold", 0)) == 2450, "Loaded account gold must equal 2450")
	_assert_true(int(loaded_save.get("hull_tier", 0)) == Contracts.ShipClass.FRIGATE, "Loaded hull_tier must equal FRIGATE")
	_assert_true(Contracts.ShipClass.FRIGATE in loaded_save.get("owned_ship_tiers", []), "Loaded owned_ship_tiers must retain FRIGATE")
	_assert_true(is_equal_approx(float(loaded_save.get("hp", 0.0)), 275.5), "Loaded HP must match saved HP")
	_assert_true((loaded_save.get("active_quests", []) as Array).size() == 1, "Loaded active_quests must persist")

	var restored_grid := DredgeGrid.new()
	restored_grid.from_dict(loaded_save.get("grid", {}))
	_assert_true(restored_grid.hull_tier == Contracts.ShipClass.FRIGATE, "Restored DredgeGrid must keep FRIGATE tier")
	_assert_true(restored_grid.placed_items.size() == p_grid.placed_items.size(), "Restored DredgeGrid must keep all placed items")
	p_grid.free()
	restored_grid.free()

	# 4. Solo save/load/clear
	_assert_true(not store.has_solo_save(), "Solo save must not exist initially")
	_assert_true(store.save_solo(custom_save) and store.has_solo_save(), "Solo save must write file")
	var solo_loaded: Dictionary = store.load_solo()
	_assert_true(int(solo_loaded.get("gold", 0)) == 2450, "Solo save must restore gold")
	store.clear_solo_save()
	_assert_true(not store.has_solo_save(), "clear_solo_save() must remove solo save file")

	# 5. Server spawn from saved profile + ServerConfig + StartMenuUI first-start auth gate
	var main_srv := Main.new()
	root.add_child(main_srv)
	main_srv.is_headless_server = true
	main_srv._init_simulation(Contracts.DEFAULT_WORLD_SEED, true)
	main_srv._on_server_peer_joined_with_save(9001, "BlackBeard", loaded_save)
	var restored_srv_ship: Node = main_srv.all_ships.get(9001, null)
	_assert_true(restored_srv_ship != null, "Server must spawn ship from saved account profile")
	_assert_true(int(restored_srv_ship.get("hull_tier")) == Contracts.ShipClass.FRIGATE, "Server ship must restore FRIGATE hull_tier")
	_assert_true(is_equal_approx(float(restored_srv_ship.get("hp")), 275.5), "Server ship must restore saved HP")
	_assert_true((restored_srv_ship.get("world_pos") as Vector2).distance_to(Vector2(420.0, -310.0)) < 1.0, "Server ship must restore saved world_pos")
	main_srv._clear_game_world()
	main_srv.queue_free()

	var srv_cfg: Script = load("res://net/server_config.gd") as Script
	var prev_user: String = str(srv_cfg.call("load_mp_username"))
	var prev_tok: String = str(srv_cfg.call("load_mp_session_token"))
	var prev_srv: String = str(srv_cfg.call("load_mp_auth_server"))
	var prev_local_u: String = str(srv_cfg.call("load_local_username"))
	var prev_local_tok: String = str(srv_cfg.call("load_local_session_token"))
	srv_cfg.call("clear_mp_auth", false)
	srv_cfg.call("clear_local_auth", false)
	var start_ui := StartMenuUI.new()
	root.add_child(start_ui)
	_assert_true(start_ui._auth_form_box.visible and not start_ui._logged_in_box.visible, "StartMenuUI must require Username+Password form on first MP start")
	_assert_true(not start_ui._local_auth_box.visible, "Optional local login box must stay collapsed by default for 1-click Solo")
	start_ui._on_solo_account_btn_pressed()
	_assert_true(start_ui._local_auth_box.visible, "Clicking optional local account toggle must reveal local login form")
	start_ui._local_store = store
	start_ui._local_username_input.text = "BlackBeard"
	start_ui._local_password_input.text = "rum123"
	start_ui._submit_local_credentials(false)
	_assert_true(bool(srv_cfg.call("has_local_auth")) and not start_ui._local_auth_box.visible, "Optional local login must load account save and collapse form")
	start_ui._on_solo_account_btn_pressed()
	_assert_true(not bool(srv_cfg.call("has_local_auth")), "Local logout must return Solo to optional anonymous mode")
	srv_cfg.call("save_mp_auth", "TestCap", "tok_xyz", start_ui.get_url_text())
	start_ui.refresh_menu_state()
	_assert_true(not start_ui._auth_form_box.visible and start_ui._logged_in_box.visible, "StartMenuUI must show remembered account after login")
	start_ui._on_logout_pressed()
	_assert_true(start_ui._auth_form_box.visible and not start_ui._logged_in_box.visible, "Logout must return StartMenuUI to Username+Password form")

	# 6. Hidden Creative / Test Mode trigger, 9 ship classes, 27 items + affixes, Godmode/Reload & Solo save isolation
	_assert_true(not start_ui._creative_box.visible, "StartMenuUI hidden creative code box must stay collapsed by default")
	var creative_emits: Array[int] = [0]
	start_ui.creative_requested.connect(func(): creative_emits[0] += 1)
	start_ui.toggle_creative_box()
	_assert_true(start_ui._creative_box.visible, "toggle_creative_box() must reveal hidden creative code input")
	start_ui._creative_code_input.text = "wrong"
	start_ui._submit_creative_code()
	_assert_true(creative_emits[0] == 0 and start_ui._status_label.text == "Ungültiger Code.", "Invalid creative code must show muted error and not emit creative_requested")
	start_ui._creative_code_input.text = "  Pirat  "
	start_ui._submit_creative_code()
	_assert_true(creative_emits[0] == 1 and not start_ui._creative_box.visible and start_ui._creative_code_input.text.is_empty(), "Valid creative code must clear/hide input and emit creative_requested")
	start_ui.queue_free()

	var creative_solo_path: String = "user://test_creative_solo_%d.json" % test_id
	var isolated_store = save_store_script.new(test_dir, creative_solo_path)
	var baseline_solo: Dictionary = save_store_script.create_default_save_data()
	baseline_solo["gold"] = 555
	_assert_true(isolated_store.save_solo(baseline_solo), "Baseline solo save for creative isolation test must write cleanly")

	var main_scene_c: PackedScene = load("res://main.tscn") as PackedScene
	var main_c: Main = main_scene_c.instantiate() as Main
	root.add_child(main_c)
	main_c._save_store = isolated_store
	main_c._on_creative_pressed()
	_assert_true(main_c.is_creative_mode and main_c.game_started, "Main._on_creative_pressed() must activate Creative Mode")
	_assert_true(main_c.harbor_ui != null and main_c.harbor_ui.current_gold == 999999, "Creative Mode must grant 999999 Gold")
	_assert_true(main_c.harbor_ui.get_owned_ship_tiers_array().size() == 9, "Creative Mode must unlock all 9 ship tiers (0..8)")
	var c_ui = main_c.creative_debug_ui
	_assert_true(c_ui != null and not bool(c_ui.call("is_panel_open")), "Creative Mode must initialize CreativeDebugUI collapsed by default")
	c_ui.call("set_panel_open", true)
	_assert_true(main_c._is_ui_open(), "Main._is_ui_open() must return true when CreativeDebugUI panel is open")
	for tier_c in range(9):
		c_ui.call("switch_ship_class", tier_c)
		_assert_true(int(main_c.player_ship.get("hull_tier")) == tier_c and int(main_c.player_grid.get("hull_tier")) == tier_c, "Creative switch_ship_class(%d) must switch ship and grid tier" % tier_c)
	c_ui.call("clear_player_grid")
	_assert_true((main_c.player_grid.get("placed_items") as Array).is_empty(), "Creative clear_player_grid() must empty placed items")
	_assert_true(bool(c_ui.call("spawn_item_by_id", "carronade_2x1", Contracts.ItemAffix.CURSED)), "Creative spawn_item_by_id must auto-place CURSED carronade into Man-o'-War grid")
	_assert_true(bool(c_ui.call("spawn_item_by_id", "storm_sails_2x2", Contracts.ItemAffix.CURSED)), "Creative spawn_item_by_id must auto-place CURSED storm_sails_2x2 into MAST slots")
	var stash_before_all: int = (main_c.player_grid.get("stash_items") as Array).size()
	var added_all_cnt: int = int(c_ui.call("add_all_items_to_stash", Contracts.ItemAffix.MASTERWORK))
	_assert_true(added_all_cnt == 27 and (main_c.player_grid.get("stash_items") as Array).size() == stash_before_all + 27, "Creative add_all_items_to_stash must add all 27 MASTERWORK items")
	c_ui.set("godmode_enabled", true)
	c_ui.set("instant_reload_enabled", true)
	main_c.player_ship.set("hp", 1.0)
	main_c.player_ship.set("is_sunk", true)
	main_c.player_ship.set("burn_timer", 4.0)
	main_c.combat_system.fire_broadside(main_c.player_ship_id, false)
	main_c._physics_process(0.05)
	_assert_true(not bool(main_c.player_ship.get("is_sunk")) and is_equal_approx(float(main_c.player_ship.get("hp")), float(main_c.player_ship.get("max_hp"))) and float(main_c.player_ship.get("burn_timer")) == 0.0, "Creative Godmode must keep player alive at full HP with zero burn")
	_assert_true(float(main_c.combat_system.get_broadside_cone(main_c.player_ship_id, false).get("ready_ratio", 0.0)) >= 0.99, "Creative Instant Reload must keep broadside ready")
	main_c._mark_save_dirty()
	main_c._step_local_save_sync(12.0)
	main_c._flush_local_save(true)
	var after_creative_solo: Dictionary = isolated_store.load_solo()
	_assert_true(int(after_creative_solo.get("gold", 0)) == 555, "Creative Mode must NOT modify normal solo save (expected 555 gold, got %d)" % int(after_creative_solo.get("gold", 0)))
	c_ui.call("set_panel_open", false)
	main_c._clear_game_world()
	main_c.queue_free()
	isolated_store.clear_solo_save()

	if not prev_user.is_empty() and not prev_tok.is_empty() and not prev_srv.is_empty():
		srv_cfg.call("save_mp_auth", prev_user, prev_tok, prev_srv)
	else:
		srv_cfg.call("clear_mp_auth", false)
	if not prev_local_u.is_empty() and not prev_local_tok.is_empty():
		srv_cfg.call("save_local_auth", prev_local_u, prev_local_tok)
	else:
		srv_cfg.call("clear_local_auth", false)

	# Cleanup temp test directory
	var abs_test_dir: String = ProjectSettings.globalize_path(test_dir)
	var dir_acc := DirAccess.open(abs_test_dir)
	if dir_acc != null:
		for fname in dir_acc.get_files():
			dir_acc.remove(fname)
		DirAccess.remove_absolute(abs_test_dir)

	print("  -> [PASS] SaveStore auth, ship/grid/gold/quest save roundtrip, server restore & StartMenuUI auth gate verified.")

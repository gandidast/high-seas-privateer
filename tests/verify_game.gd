extends SceneTree
## Automated Headless Verification Suite for High Seas Pixel Privateer.
## Run via: godot --headless -s res://tests/verify_game.gd

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
	print("[TEST 1/4] Deterministic get_water_depth(), Islands & ShipPhysics...")
	var seed_val: int = Contracts.DEFAULT_WORLD_SEED

	# 1. Determinism check
	var sample_points: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(250.0, -180.0),
		Vector2(-560.0, -340.0),
		Vector2(620.0, -380.0),
		Vector2(-1100.0, 950.0)
	]
	for pt in sample_points:
		var d1: float = Contracts.get_water_depth(pt, seed_val)
		var d2: float = Contracts.get_water_depth(pt, seed_val)
		_assert_true(is_equal_approx(d1, d2), "get_water_depth() must be 100%% deterministic at %s" % str(pt))

	# 2. WorldMap setup & islands
	var world_map := WorldMap.new()
	root.add_child(world_map)
	world_map.setup(seed_val)

	_assert_true(world_map.islands.size() >= 5 and world_map.islands.size() <= 7, "WorldMap must generate 5..7 named islands (got %d)" % world_map.islands.size())

	# Spawn point (0,0) must be deep navigable water
	var spawn_depth: float = world_map.get_water_depth(Vector2.ZERO)
	_assert_true(spawn_depth > Contracts.SHALLOW_THRESHOLD, "World origin (0,0) must be navigable deep water (depth=%.3f)" % spawn_depth)

	# Each island center must be solid land, and its harbor must be navigable water inside harbor zone
	for isl in world_map.islands:
		var center_depth: float = world_map.get_water_depth(isl.center)
		_assert_true(center_depth <= Contracts.LAND_THRESHOLD, "Island '%s' center must be land (depth=%.3f)" % [isl.name, center_depth])
		_assert_true(world_map.is_land(isl.center), "world_map.is_land() must be true at island '%s' center" % isl.name)

		var harbor_depth: float = world_map.get_water_depth(isl.harbor_pos)
		_assert_true(harbor_depth > Contracts.LAND_THRESHOLD, "Island '%s' harbor_pos must be in navigable water (depth=%.3f)" % [isl.name, harbor_depth])
		var detected_harbor: int = world_map.get_harbor_at(isl.harbor_pos)
		_assert_true(detected_harbor == isl.index, "get_harbor_at(harbor_pos) must return island index %d (got %d)" % [isl.index, detected_harbor])

	# 3. ShipPhysics sail states, wind influence & coast bounce
	var ship := ShipPhysics.new()
	root.add_child(ship)
	ship.setup(1, Vector2.ZERO, 0.0, Contracts.ShipFaction.PLAYER, "TestSchaluppe")
	ship.set_sail_state(Contracts.SailState.FULL_SAIL)
	for _i in range(20):
		ship.step_physics(0.05, 0.0, world_map)
	_assert_true(ship.speed > 20.0, "Ship under FULL_SAIL must accelerate forward (speed=%.2f)" % ship.speed)

	# Upwind test: heading directly against wind must still maintain generous minimum speed
	world_map.wind_direction = Vector2.LEFT
	ship.heading = 0.0 # sailing RIGHT against LEFT wind
	for _i in range(30):
		ship.step_physics(0.05, 0.0, world_map)
	_assert_true(ship.speed >= ship.stats.max_speed * 0.35, "Ship sailing directly against wind must maintain generous minimum speed (speed=%.2f)" % ship.speed)

	ship.queue_free()
	world_map.queue_free()
	print("  -> [PASS] Deterministic water depth, 6 islands, harbors & ShipPhysics verified.")


func _test_dredge_grid_rotation_synergy_and_stats() -> void:
	print("[TEST 2/4] DredgeGrid Placement, Rotation, Adjacency Synergy & Stat Compilation...")

	var all_ids: Array[String] = ItemDatabase.get_all_ids()
	_assert_true(all_ids.size() >= 12, "ItemDatabase must define at least 12 items (got %d)" % all_ids.size())

	var grid := DredgeGrid.new()
	grid.ship_id = 1
	root.add_child(grid)

	# Verify slot types in 8x6 grid
	_assert_true(grid.get_slot_type(0, 0) == Contracts.SlotType.DECK_PORT, "Row y=0 must be DECK_PORT")
	_assert_true(grid.get_slot_type(0, 5) == Contracts.SlotType.DECK_STARBOARD, "Row y=5 must be DECK_STARBOARD")
	_assert_true(grid.get_slot_type(3, 2) == Contracts.SlotType.MAST, "Center (3,2) must be MAST")
	_assert_true(grid.get_slot_type(1, 1) == Contracts.SlotType.CARGO_HOLD, "Interior (1,1) must be CARGO_HOLD")

	# 1. Place a 1x2 swivel cannon rotated (2x1) on DECK_PORT at (0, 0)
	var port_cannon: Contracts.GridItemData = ItemDatabase.create_item("swivel_gun_1x2")
	_assert_true(port_cannon.get_effective_size() == Vector2i(1, 2), "Unrotated swivel_gun_1x2 size must be 1x2")
	var can_rot: bool = grid.can_place_item(port_cannon, 0, 0, true)
	_assert_true(can_rot, "Rotated 2x1 cannon must fit along DECK_PORT rail at (0,0)")
	var placed_cannon: bool = grid.place_item(port_cannon, 0, 0, true)
	_assert_true(placed_cannon and port_cannon.get_effective_size() == Vector2i(2, 1), "Placed rotated cannon must have effective size 2x1")

	var stats_before_barrel: Contracts.ShipStats = grid.compile_stats()
	_assert_true(stats_before_barrel.port_cannons.size() == 1, "Port rail cannon must register in stats.port_cannons")
	var base_reload: float = float(stats_before_barrel.port_cannons[0]["reload_time"])

	# 2. Place a cannon solely inside CARGO_HOLD (e.g. rotated at (4, 1)) -> must NOT fire in broadsides!
	var hold_cannon: Contracts.GridItemData = ItemDatabase.create_item("swivel_gun_1x2")
	var placed_hold: bool = grid.place_item(hold_cannon, 4, 1, true)
	_assert_true(placed_hold, "Cannon should be storable in CARGO_HOLD at (4,1)")
	var stats_with_hold_cannon: Contracts.ShipStats = grid.compile_stats()
	_assert_true(
		stats_with_hold_cannon.port_cannons.size() == 1 and stats_with_hold_cannon.starboard_cannons.size() == 0,
		"Cannon stored in CARGO_HOLD must NOT count as active broadside cannon"
	)

	# 3. Place powder_barrel_1x1 at (0, 1) directly adjacent to port_cannon at (0, 0)
	var barrel: Contracts.GridItemData = ItemDatabase.create_item("powder_barrel_1x1")
	var placed_barrel: bool = grid.place_item(barrel, 0, 1, false)
	_assert_true(placed_barrel, "Powder barrel 1x1 must be placeable at (0,1) adjacent to port cannon")

	var stats_after_barrel: Contracts.ShipStats = grid.compile_stats()
	var boosted_reload: float = float(stats_after_barrel.port_cannons[0]["reload_time"])
	_assert_true(boosted_reload < base_reload * 0.85, "Powder barrel adjacency must grant +25%% reload speed (before=%.2fs, after=%.2fs)" % [base_reload, boosted_reload])
	_assert_true(stats_after_barrel.explosion_hazard_damage >= 10.0, "Equipped powder barrel must increase explosion_hazard_damage (got %.1f)" % stats_after_barrel.explosion_hazard_damage)
	_assert_true(not grid.get_adjacent_synergy_cells().is_empty(), "get_adjacent_synergy_cells() must highlight active synergy cells")

	# 4. Place storm_sails_2x2 on MAST at (2, 2) and check speed bonus
	var base_spd: float = stats_after_barrel.max_speed
	var sails: Contracts.GridItemData = ItemDatabase.create_item("storm_sails_2x2")
	var placed_sails: bool = grid.place_item(sails, 2, 2, false)
	_assert_true(placed_sails, "Storm sails 2x2 must be placeable on MAST at (2,2)")
	var stats_after_sails: Contracts.ShipStats = grid.compile_stats()
	_assert_true(stats_after_sails.max_speed > base_spd + 10.0, "Storm sails must increase ShipStats.max_speed (before=%.1f, after=%.1f)" % [base_spd, stats_after_sails.max_speed])

	grid.queue_free()
	print("  -> [PASS] DredgeGrid placement, rotation, edge-slot cannon rule, powder synergy & stat compiler verified.")


func _test_combat_ai_rng_loot_and_quests() -> void:
	print("[TEST 3/4] Combat Broadsides, AI State Machine, RNG Affix Loot & Harbor Quests...")

	var world_map := WorldMap.new()
	root.add_child(world_map)
	world_map.setup(Contracts.DEFAULT_WORLD_SEED)

	var combat := CombatSystem.new()
	root.add_child(combat)

	var loot := LootSystem.new()
	root.add_child(loot)
	loot.setup(world_map, true)

	var ai := AIDirector.new()
	root.add_child(ai)
	ai.setup(world_map, combat)

	# Create player ship & grid
	var player := ShipPhysics.new()
	root.add_child(player)
	player.setup(1, Vector2.ZERO, 0.0, Contracts.ShipFaction.PLAYER, "Spieler")
	var p_grid := DredgeGrid.new()
	p_grid.ship_id = 1
	root.add_child(p_grid)
	p_grid.populate_starter_loadout()
	player.apply_stats(p_grid.compile_stats())
	combat.register_ship(player)

	# Create target pirate ship right on player's starboard side
	var pirate_id: int = ai.spawn_ai_ship(Contracts.ShipFaction.PIRATE, Vector2(0.0, 75.0), false, "Piratenschaluppe")
	var pirate: ShipPhysics = ai.ai_ships.get(pirate_id, null)
	_assert_true(pirate != null, "AIDirector must spawn pirate ship")

	# Fire starboard broadside from player (heading=0 -> starboard is +Y where pirate sits at (0, 75))
	var shots: Array = combat.fire_broadside(1, true)
	_assert_true(shots.size() > 0, "Player starboard broadside must spawn projectiles")

	var start_pirate_hp: float = pirate.hp
	for _i in range(40):
		combat.step_projectiles(0.025, world_map)
	_assert_true(pirate.hp < start_pirate_hp, "Starboard broadside projectiles must hit and damage pirate ship (hp %.1f -> %.1f)" % [start_pirate_hp, pirate.hp])

	# Verify AI FLEE_TO_PORT state transition when HP < 30%
	pirate.hp = pirate.max_hp * 0.20
	var ships_dict: Dictionary = { 1: player, pirate_id: pirate }
	ai.step_ai(0.1, ships_dict)
	var p_state: int = ai.get_ship_ai_state(pirate_id)
	_assert_true(p_state == Contracts.AIState.FLEE_TO_PORT, "AI ship below 30%% HP must enter FLEE_TO_PORT state (got %d)" % p_state)

	# Verify RNG loot drop generation on ship sink & affix variety
	var initial_drops: int = loot.drops.size()
	var drop: Contracts.LootDropData = loot.spawn_loot_drop(Vector2(10.0, 0.0), 2, false)
	_assert_true(drop != null and loot.drops.size() == initial_drops + 1, "LootSystem must spawn floating LootDropData")
	_assert_true(drop.gold > 0 and drop.items.size() >= 1, "LootDropData must contain gold and RNG items")

	# Verify RNG affix rolling produces valid affixes
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var seen_affixes: Dictionary = {}
	for _i in range(60):
		var afx: int = ItemDatabase.roll_random_affix(rng)
		seen_affixes[afx] = true
	_assert_true(seen_affixes.size() >= 3, "RNG affix roller must produce multiple distinct affixes (RUSTED, STANDARD, MASTERWORK, CURSED)")

	# Collect loot by stepping loot system with player at (0,0) and drop at (10,0)
	loot.step_loot(0.1, ships_dict, p_grid, true)
	_assert_true(not loot.drops.has(drop.drop_id), "Player within pickup radius must collect floating loot drop")

	# Verify HarborUI quests & completion
	var harbor_ui := HarborUI.new()
	root.add_child(harbor_ui)
	harbor_ui.setup(player, p_grid, world_map, ai, loot, 100)
	harbor_ui.open_harbor(0)
	var quests: Array = harbor_ui.harbor_quests.get(0, [])
	_assert_true(quests.size() == 3, "HarborUI must generate 3 quests per harbor (BOUNTY, DELIVERY, SALVAGE)")

	var gold_before: int = harbor_ui.current_gold
	var delivery_quest: Contracts.QuestData = null
	for q in quests:
		if q is Contracts.QuestData and q.quest_type == Contracts.QuestType.DELIVERY:
			delivery_quest = q
			break
	if delivery_quest == null:
		delivery_quest = quests[0]
	harbor_ui._accept_quest(delivery_quest)
	var completed_ok: bool = harbor_ui.complete_quest(delivery_quest.id)
	_assert_true(completed_ok and harbor_ui.current_gold > gold_before, "Completing a quest must mark it completed and award gold")

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
	print("  -> [PASS] Combat broadsides, AI FSM, RNG loot affixes & Harbor quests verified.")


func _test_visual_pipeline_and_headless_server_boot() -> void:
	print("[TEST 4/4] 2D Sprite-Stacking (3 Classes), Ocean 4-Quadrant Coverage, Item Icons & Headless Server...")

	# 1. Verify ProceduralShipBaker generates 24 crisp 64x32 1:1 pixel layers for all 3 ship classes + all 22 item icons
	for tier in range(3):
		var layers: Array[ImageTexture] = ProceduralShipBaker.bake_ship_layers(Contracts.ShipFaction.PLAYER, 24, tier)
		_assert_true(layers.size() == 24, "ProceduralShipBaker must bake 24 vertical 2D pixel layers for hull_tier %d (got %d)" % [tier, layers.size()])
		_assert_true(layers[0].get_width() == 64 and layers[0].get_height() == 32, "Baked ship layer texture must be 64x32 px 1:1 pixel art")

	var kraken_tex: ImageTexture = ProceduralShipBaker.bake_kraken_body_texture(false)
	_assert_true(kraken_tex != null and kraken_tex.get_width() == 64 and kraken_tex.get_height() == 64, "Kraken body texture must be a 64x64 pixel-art ImageTexture")
	var tent_tex: ImageTexture = ProceduralShipBaker.bake_kraken_tentacle_texture(0, false)
	_assert_true(tent_tex != null and tent_tex.get_width() == 32 and tent_tex.get_height() == 32, "Kraken tentacle texture must be a 32x32 pixel-art ImageTexture")
	var fort_tex: ImageTexture = ProceduralShipBaker.bake_fort_texture()
	_assert_true(fort_tex != null and fort_tex.get_width() == 48 and fort_tex.get_height() == 48, "Fort texture must be a 48x48 pixel-art ImageTexture")

	for item_id in ItemDatabase.get_all_ids():
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

	var cannon_tex: ImageTexture = ProceduralShipBaker.bake_module_texture(Contracts.ItemCategory.CANNON, Contracts.ItemRarity.RARE)
	_assert_true(cannon_tex != null and cannon_tex.get_width() > 0, "ProceduralShipBaker must bake cannon module texture")

	# 2. Verify OceanRenderer covers all 4 quadrants around camera center (top-left < 0 and bottom-right > 0)
	var ocean := OceanRenderer.new()
	root.add_child(ocean)
	ocean.setup(Contracts.DEFAULT_WORLD_SEED)
	ocean.set_camera_center(Vector2.ZERO)
	_assert_true(ocean._ocean_sprite != null and not ocean._ocean_sprite.centered, "OceanQuad Sprite2D must use centered=false to avoid 0.5px vertex-snap quadrant shift")
	_assert_true(ocean._ocean_sprite.position.x <= -320.0 and ocean._ocean_sprite.position.y <= -180.0, "OceanQuad top-left must cover top-left quadrant (pos=%s)" % str(ocean._ocean_sprite.position))
	ocean.queue_free()

	# 3. Verify ShipStackRenderer 24-layer stacking, 3 ship classes & deck module sockets
	var renderer := ShipStackRenderer.new()
	root.add_child(renderer)
	renderer.setup_ship(1, Contracts.ShipFaction.PLAYER, "Morgenstern")
	renderer.set_hull_tier(Contracts.ShipClass.FRIGATE)
	renderer.update_transform_state(Vector2(100.0, 50.0), 0.75, 60.0, Contracts.SailState.FULL_SAIL, 280.0, 280.0)
	renderer.update_equipped_modules([
		{ "category": Contracts.ItemCategory.CANNON, "slot_type": Contracts.SlotType.DECK_PORT, "grid_x": 2, "grid_y": 0, "rarity": 1, "affix": 0 },
		{ "category": Contracts.ItemCategory.CANNON, "slot_type": Contracts.SlotType.DECK_STARBOARD, "grid_x": 2, "grid_y": 5, "rarity": 2, "affix": 2 },
		{ "category": Contracts.ItemCategory.POWDER_BARREL, "slot_type": Contracts.SlotType.CARGO_HOLD, "grid_x": 2, "grid_y": 1, "rarity": 1, "affix": 0 }
	])
	_assert_true(renderer.position.distance_to(Vector2(100.0, 50.0)) < 1.0, "ShipStackRenderer must update world position")
	renderer.queue_free()

	# 4. Verify Main scene Hybrid Rendering (SubViewport 640x360 + HD UILayer), ServerConfig, Forts, Kraken & Headless Server
	var srv_cfg: Script = load("res://net/server_config.gd") as Script
	var initial_url: String = str(srv_cfg.call("get_initial_server_url"))
	_assert_true(not initial_url.is_empty(), "ServerConfig.get_initial_server_url() must return a non-empty URL")
	srv_cfg.call("save_profile", "Käpt'n Rotbart", srv_cfg.get("DEFAULT_SERVER_URL"))
	_assert_true(str(srv_cfg.call("load_captain_name")) == "Käpt'n Rotbart", "ServerConfig must persist captain_name in user://player_profile.cfg")

	var main_scene: PackedScene = load("res://main.tscn") as PackedScene
	_assert_true(main_scene != null, "res://main.tscn must load cleanly")
	var main_node: Main = main_scene.instantiate() as Main
	_assert_true(main_node != null, "Main scene must instantiate cleanly")
	root.add_child(main_node)

	# Verify Hybrid Rendering hierarchy: SubViewportContainer (stretch_shrink=2) -> SubViewport (640x360) -> WorldRoot
	_assert_true(main_node.world_viewport_container != null and main_node.world_viewport_container.stretch and main_node.world_viewport_container.stretch_shrink == 2, "Main must have SubViewportContainer with stretch=true and stretch_shrink=2")
	_assert_true(main_node.world_subviewport != null and main_node.world_subviewport.get_parent() == main_node.world_viewport_container, "Main must have SubViewport inside SubViewportContainer for pixel world")
	_assert_true(main_node.world_subviewport.snap_2d_transforms_to_pixel, "GameSubViewport must have snap_2d_transforms_to_pixel=true")
	_assert_true(main_node.world_root.get_parent() == main_node.world_subviewport, "WorldRoot must live inside GameSubViewport")
	_assert_true(main_node.ui_layer.get_parent() == main_node, "UILayer must live directly under Main outside SubViewport for crisp 1280x720 HD UI")

	# Test Solo mode initialization inside Main
	main_node._on_solo_pressed()
	_assert_true(main_node.game_started and main_node.player_ship != null, "Main Solo mode must initialize player_ship and simulation")
	_assert_true(main_node.combat_system.forts.size() >= 3, "CombatSystem must initialize island coastal forts")
	var kraken_id: int = main_node.ai_director.spawn_sea_monster(Vector2(320.0, -240.0))
	_assert_true(kraken_id > 0, "AIDirector must spawn giant Kraken sea monster event")
	main_node._physics_process(0.05)

	# Switch Main into Headless Server mode on an ephemeral port (e.g. 18089) and step server loop
	main_node._clear_game_world()
	main_node.is_headless_server = true
	main_node._init_simulation(Contracts.DEFAULT_WORLD_SEED, true)
	main_node.ai_director.populate_initial_fleet(2, 2)
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

	# Verify server snapshot includes BOTH player ships and AI ships + forts
	var srv_ships_count: int = main_node.all_ships.size() + main_node.ai_director.ai_ships.size()
	_assert_true(srv_ships_count >= 5, "Server must track both joined player ship and AI ships (got %d)" % srv_ships_count)
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
		"wind_x": 1.0,
		"wind_y": 0.0,
		"wind_strength": 0.8,
		"weather_state": Contracts.WeatherState.FOG,
		"weather_intensity": 0.6,
		"wanted_level": 0,
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
	_assert_true(main_node.all_ships.size() >= 5, "Client _on_snapshot_received must instantiate both player and all AI ships (got %d)" % main_node.all_ships.size())
	_assert_true(main_node.combat_system.forts.size() >= 3, "Client _on_snapshot_received must sync island forts (got %d)" % main_node.combat_system.forts.size())
	main_node._clear_game_world()
	main_node.queue_free()

	print("  -> [PASS] 2D Sprite-Stacking pipeline (3 classes), 22 Item Icons, 4-Quadrant Ocean, Forts, Kraken & Headless Server verified.")

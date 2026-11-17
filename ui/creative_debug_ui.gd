class_name CreativeDebugUI
extends Control
## Hidden Solo Creative / Debug / Test Mode Arsenal UI (1280x720 HD overlay).
## Lets the user test all 9 ship classes, all 27 items across all 5 affixes,
## gold/repair/grid tools, enemy/Kraken/loot spawning, island teleports, and cheats
## without touching normal Solo saves or Live Multiplayer.

const AFFIX_DEFS: Array[Dictionary] = [
	{ "affix": Contracts.ItemAffix.STANDARD, "label": "Standard" },
	{ "affix": Contracts.ItemAffix.RUSTED, "label": "Verrostet" },
	{ "affix": Contracts.ItemAffix.RARE, "label": "Selten" },
	{ "affix": Contracts.ItemAffix.MASTERWORK, "label": "Meisterhaft" },
	{ "affix": Contracts.ItemAffix.CURSED, "label": "Verflucht" }
]

const CATEGORY_LABELS: Dictionary = {
	Contracts.ItemCategory.CANNON: "Kanone",
	Contracts.ItemCategory.POWDER_BARREL: "Pulver",
	Contracts.ItemCategory.SAIL: "Segel",
	Contracts.ItemCategory.HULL: "Rumpf",
	Contracts.ItemCategory.CARGO: "Fracht",
	Contracts.ItemCategory.TREASURE: "Schatz",
	Contracts.ItemCategory.CREW_MOD: "Crew",
	Contracts.ItemCategory.BOW_WEAPON: "Bug-Waffe"
}

var godmode_enabled: bool = false
var instant_reload_enabled: bool = false
var selected_affix: int = Contracts.ItemAffix.STANDARD

var player_ship: Node = null
var player_grid: Node = null
var harbor_ui: HarborUI = null
var hud_overlay: HudOverlay = null
var world_map_ref: Node = null
var combat_system_ref: CombatSystem = null
var loot_system_ref: LootSystem = null
var ai_director_ref: AIDirector = null
var ship_renderers_ref: Dictionary = {}
var pixel_camera_ref: Camera2D = null
var cargo_grid_ui_ref: Control = null
var player_ship_id: int = 1

var _pill_btn: Button = null
var _modal_backdrop: ColorRect = null
var _panel: PanelContainer = null
var _status_lbl: Label = null
var _ship_btns: Dictionary = {}
var _affix_btns: Dictionary = {}
var _item_grid: GridContainer = null
var _item_cards: Array[Dictionary] = []
var _godmode_btn: Button = null
var _reload_btn: Button = null
var _island_jump_idx: int = 1


func _bus() -> Contracts:
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		return st.root.get_node_or_null("EventBus") as Contracts
	return null


func _ready() -> void:
	name = "CreativeDebugUI"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_ui()
	set_panel_open(false)


func setup(
	p_player_ship: Node,
	p_player_grid: Node,
	p_harbor_ui: HarborUI,
	p_hud_overlay: HudOverlay,
	p_world_map: Node,
	p_combat_system: CombatSystem,
	p_loot_system: LootSystem,
	p_ai_director: AIDirector,
	p_ship_renderers: Dictionary,
	p_pixel_camera: Camera2D,
	p_player_ship_id: int = 1,
	p_cargo_grid_ui: Control = null
) -> void:
	player_ship = p_player_ship
	player_grid = p_player_grid
	harbor_ui = p_harbor_ui
	hud_overlay = p_hud_overlay
	world_map_ref = p_world_map
	combat_system_ref = p_combat_system
	loot_system_ref = p_loot_system
	ai_director_ref = p_ai_director
	ship_renderers_ref = p_ship_renderers
	pixel_camera_ref = p_pixel_camera
	player_ship_id = p_player_ship_id
	cargo_grid_ui_ref = p_cargo_grid_ui
	_refresh_ui()


func is_panel_open() -> bool:
	return visible and _modal_backdrop != null and _modal_backdrop.visible


func set_panel_open(open: bool) -> void:
	if _modal_backdrop != null:
		_modal_backdrop.visible = open
	if _pill_btn != null:
		_pill_btn.visible = not open
	mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if open:
		if harbor_ui != null and harbor_ui.visible:
			harbor_ui.close_harbor()
		if cargo_grid_ui_ref != null and cargo_grid_ui_ref.visible:
			var bus := _bus()
			if bus != null:
				bus.cargo_grid_toggled.emit(false)
			cargo_grid_ui_ref.visible = false
		if hud_overlay != null and hud_overlay.is_world_map_open():
			hud_overlay.set_world_map_open(false)
		_refresh_ui()


func toggle_panel() -> void:
	set_panel_open(not is_panel_open())


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var kev := event as InputEventKey
		if kev.pressed and not kev.echo:
			if kev.keycode == KEY_F8:
				toggle_panel()
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
			elif kev.keycode == KEY_ESCAPE and is_panel_open():
				set_panel_open(false)
				if get_viewport() != null:
					get_viewport().set_input_as_handled()


func switch_ship_class(tier: int) -> void:
	var clamped_tier: int = clampi(tier, Contracts.ShipClass.SLOOP, Contracts.ShipClass.MAN_O_WAR)
	if player_grid != null and player_grid.has_method("set_hull_tier"):
		player_grid.call("set_hull_tier", clamped_tier)
	if player_ship != null and player_ship.has_method("upgrade_ship_class"):
		player_ship.call("upgrade_ship_class", clamped_tier)
	var compiled_stats: Contracts.ShipStats = null
	if player_grid != null and player_grid.has_method("compile_stats"):
		compiled_stats = player_grid.call("compile_stats")
	if compiled_stats != null and player_ship != null and player_ship.has_method("apply_stats"):
		player_ship.call("apply_stats", compiled_stats)
	if player_ship != null:
		var mhp: float = float(player_ship.get("max_hp"))
		player_ship.set("hp", mhp)
		player_ship.set("is_sunk", false)
		player_ship.set("burn_timer", 0.0)
		player_ship.set("burn_dps", 0.0)
	if harbor_ui != null:
		harbor_ui.owned_ship_tiers[clamped_tier] = true
	_sync_player_renderer(clamped_tier, compiled_stats)
	if player_ship != null and _bus() != null:
		_bus().ship_state_updated.emit(
			player_ship_id,
			player_ship.get("world_pos"),
			float(player_ship.get("heading")),
			float(player_ship.get("speed")),
			int(player_ship.get("sail_state")),
			float(player_ship.get("hp")),
			float(player_ship.get("max_hp"))
		)
		var cname: String = str(Contracts.get_ship_class_spec(clamped_tier).get("name", "Schiff"))
		_bus().notification_posted.emit("Creative: Schiffsklasse -> %s (Tier %d)" % [cname, clamped_tier], "system")
	_refresh_ui()


func spawn_item_by_id(item_id: String, affix: int = -1) -> bool:
	var use_affix: int = selected_affix if affix < 0 else affix
	var item: Contracts.GridItemData = ItemDatabase.create_item(item_id, use_affix)
	if item == null or player_grid == null:
		return false

	var placed: bool = false
	if player_grid.has_method("auto_place_item"):
		placed = bool(player_grid.call("auto_place_item", item))
	if not placed and player_grid.has_method("add_to_stash"):
		player_grid.call("add_to_stash", item)

	var stats: Variant = player_grid.get("current_stats")
	if stats is Contracts.ShipStats:
		if player_ship != null and player_ship.has_method("apply_stats"):
			player_ship.call("apply_stats", stats)
		_sync_player_renderer(int(player_grid.get("hull_tier")), stats)

	var bus := _bus()
	if bus != null:
		if placed:
			bus.notification_posted.emit("Creative: %s im Grid platziert!" % item.get_display_name(), "loot")
		else:
			bus.notification_posted.emit("Grid voll -> %s ins Lager gelegt!" % item.get_display_name(), "loot")
	_refresh_header_status()
	return placed


func add_all_items_to_stash(affix: int = -1) -> int:
	if player_grid == null or not player_grid.has_method("add_to_stash"):
		return 0
	var use_affix: int = selected_affix if affix < 0 else affix
	var ids: Array[String] = ItemDatabase.get_all_ids()
	for item_id in ids:
		var item: Contracts.GridItemData = ItemDatabase.create_item(item_id, use_affix)
		if item != null:
			player_grid.call("add_to_stash", item)
	var bus := _bus()
	if bus != null:
		bus.notification_posted.emit("Creative: Alle %d Items (%s) ins Lager gelegt!" % [ids.size(), _affix_label(use_affix)], "loot")
	_refresh_header_status()
	return ids.size()


func clear_player_grid() -> void:
	if player_grid == null:
		return
	var placed: Variant = player_grid.get("placed_items")
	if placed is Array:
		(placed as Array).clear()
	var stats: Contracts.ShipStats = null
	if player_grid.has_method("compile_stats"):
		stats = player_grid.call("compile_stats")
	if stats != null and player_ship != null and player_ship.has_method("apply_stats"):
		player_ship.call("apply_stats", stats)
	_sync_player_renderer(int(player_grid.get("hull_tier")), stats)
	var bus := _bus()
	if bus != null:
		bus.notification_posted.emit("Creative: Schiffs-Grid geleert.", "system")
	_refresh_header_status()


func add_gold(amount: int) -> void:
	if harbor_ui != null:
		harbor_ui.set_gold(maxi(0, harbor_ui.current_gold + amount))
		var bus := _bus()
		if bus != null:
			bus.gold_changed.emit(harbor_ui.current_gold, amount)
			bus.notification_posted.emit("Creative: +%d Gold" % amount, "trade")
	_refresh_header_status()


func full_repair_player() -> void:
	if player_ship == null:
		return
	var mhp: float = maxf(10.0, float(player_ship.get("max_hp")))
	player_ship.set("hp", mhp)
	player_ship.set("is_sunk", false)
	player_ship.set("burn_timer", 0.0)
	player_ship.set("burn_dps", 0.0)
	player_ship.set("chain_slow_timer", 0.0)
	player_ship.set("chain_slow_strength", 0.0)
	if ship_renderers_ref.has(player_ship_id) and is_instance_valid(ship_renderers_ref[player_ship_id]):
		var rend: Node2D = ship_renderers_ref[player_ship_id]
		if rend.has_method("set_sunk"):
			rend.call("set_sunk", false)
	var bus := _bus()
	if bus != null:
		bus.ship_repaired.emit(player_ship_id, mhp, mhp, 0)
		bus.ship_state_updated.emit(
			player_ship_id,
			player_ship.get("world_pos"),
			float(player_ship.get("heading")),
			float(player_ship.get("speed")),
			int(player_ship.get("sail_state")),
			mhp,
			mhp
		)
		bus.notification_posted.emit("Creative: Schiff voll repariert!", "harbor")


func spawn_enemy_ahead(kind: String) -> int:
	var spawn_pos: Vector2 = _find_safe_water_ahead(260.0)
	var bus := _bus()
	match kind:
		"pirate":
			if ai_director_ref == null:
				return -1
			var sid: int = ai_director_ref.spawn_ai_ship(Contracts.ShipFaction.PIRATE, spawn_pos, false, "", Contracts.ShipClass.BRIGANTINE, false)
			if bus != null:
				bus.notification_posted.emit("Creative: Pirat voraus gespawnt!", "combat")
			return sid
		"galleon":
			if ai_director_ref == null:
				return -1
			var sid: int = ai_director_ref.spawn_ai_ship(Contracts.ShipFaction.MERCHANT, spawn_pos, false, "", Contracts.ShipClass.WAR_GALLEON, true)
			if bus != null:
				bus.notification_posted.emit("Creative: Schatz-Galeone voraus gespawnt!", "combat")
			return sid
		"navy":
			if ai_director_ref == null:
				return -1
			var sid: int = ai_director_ref.spawn_ai_ship(Contracts.ShipFaction.NAVY, spawn_pos, false, "", Contracts.ShipClass.WAR_GALLEON, false)
			if bus != null:
				bus.notification_posted.emit("Creative: Navy-Galeone voraus gespawnt!", "combat")
			return sid
		"kraken":
			if ai_director_ref == null:
				return -1
			var mid: int = ai_director_ref.spawn_sea_monster(spawn_pos)
			return mid
		"loot":
			if loot_system_ref == null:
				return -1
			var drop: Contracts.LootDropData = loot_system_ref.spawn_ship_wreck_loot(spawn_pos, Contracts.ShipFaction.PIRATE, true, Contracts.ShipClass.WAR_GALLEON, false)
			if bus != null:
				bus.notification_posted.emit("Creative: Beute-Kiste voraus gespawnt!", "loot")
			return drop.drop_id if drop != null else -1
	return -1


func teleport_to_island(island_index: int) -> void:
	if player_ship == null:
		return
	var islands: Array = _get_islands()
	if islands.is_empty():
		return
	var idx: int = posmod(island_index, islands.size())
	var isl: Contracts.IslandData = islands[idx]
	if isl == null:
		return
	var target_pos: Vector2 = isl.harbor_pos if isl.has_harbor else (isl.center + Vector2.from_angle(isl.harbor_angle) * (isl.radius + 95.0))
	if world_map_ref != null and world_map_ref.has_method("find_open_water_near"):
		target_pos = world_map_ref.call("find_open_water_near", target_pos, 0.22)
	player_ship.set("world_pos", target_pos)
	player_ship.set("velocity", Vector2.ZERO)
	player_ship.set("speed", 0.0)
	player_ship.set("sail_state", Contracts.SailState.ANCHORED)
	if ship_renderers_ref.has(player_ship_id) and is_instance_valid(ship_renderers_ref[player_ship_id]):
		var rend: Node2D = ship_renderers_ref[player_ship_id]
		if rend.has_method("clear_visual_offset"):
			rend.call("clear_visual_offset")
		if rend.has_method("update_transform_state"):
			rend.call("update_transform_state", target_pos, float(player_ship.get("heading")), 0.0, Contracts.SailState.ANCHORED, float(player_ship.get("hp")), float(player_ship.get("max_hp")))
	if pixel_camera_ref != null and pixel_camera_ref.has_method("snap_to_pos"):
		pixel_camera_ref.call("snap_to_pos", target_pos)
	var bus := _bus()
	if bus != null:
		bus.ship_state_updated.emit(
			player_ship_id,
			target_pos,
			float(player_ship.get("heading")),
			0.0,
			Contracts.SailState.ANCHORED,
			float(player_ship.get("hp")),
			float(player_ship.get("max_hp"))
		)
		bus.notification_posted.emit("Sprung nach %s (#%d)" % [isl.name, idx], "system")


func jump_next_island() -> void:
	var islands: Array = _get_islands()
	if islands.is_empty():
		return
	var idx: int = _island_jump_idx % islands.size()
	_island_jump_idx = (idx + 1) % islands.size()
	teleport_to_island(idx)


func _find_safe_water_ahead(dist: float = 260.0) -> Vector2:
	var origin: Vector2 = Vector2.ZERO
	var heading: float = 0.0
	if player_ship != null:
		var wp: Variant = player_ship.get("world_pos")
		if wp is Vector2:
			origin = wp
		heading = float(player_ship.get("heading"))
	var desired: Vector2 = origin + Vector2.from_angle(heading) * dist
	if world_map_ref != null and world_map_ref.has_method("find_open_water_near"):
		return world_map_ref.call("find_open_water_near", desired, 0.24)
	return desired


func _get_islands() -> Array:
	if world_map_ref != null:
		var arr: Variant = world_map_ref.get("islands")
		if arr is Array and not arr.is_empty():
			return arr
	return Contracts.get_islands()


func _sync_player_renderer(tier: int, stats: Contracts.ShipStats) -> void:
	if not ship_renderers_ref.has(player_ship_id) or not is_instance_valid(ship_renderers_ref[player_ship_id]):
		return
	var rend: Node2D = ship_renderers_ref[player_ship_id]
	if rend.has_method("set_hull_tier"):
		rend.call("set_hull_tier", tier)
	if stats != null and rend.has_method("update_equipped_modules"):
		rend.call("update_equipped_modules", stats.visual_equipped_items)
	if rend.has_method("set_sunk"):
		rend.call("set_sunk", false)


func _affix_label(afx: int) -> String:
	for entry in AFFIX_DEFS:
		if int(entry["affix"]) == afx:
			return str(entry["label"])
	return "Standard"


func _build_ui() -> void:
	_pill_btn = UIThemeHelper.make_button("[F8] TEST-ARSENAL", Color(0.24, 0.16, 0.34, 0.94), 14)
	_pill_btn.position = Vector2(18.0, 636.0)
	_pill_btn.size = Vector2(194.0, 38.0)
	_pill_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_pill_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_pill_btn.pressed.connect(toggle_panel)
	add_child(_pill_btn)

	_modal_backdrop = ColorRect.new()
	_modal_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.color = UIThemeHelper.COL_BG_DIM_CARGO
	_modal_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_backdrop.visible = false
	add_child(_modal_backdrop)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -580.0
	_panel.offset_top = -330.0
	_panel.offset_right = 580.0
	_panel.offset_bottom = 330.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", UIThemeHelper.make_box_style(UIThemeHelper.COL_PANEL_BG, UIThemeHelper.COL_BRASS, 8, 2, 12))
	_modal_backdrop.add_child(_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(root_vbox)

	# Header
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 12)
	root_vbox.add_child(hdr)

	var title_lbl := UIThemeHelper.make_label("CREATIVE / TEST-ARSENAL [F8]", 20, UIThemeHelper.COL_GOLD)
	hdr.add_child(title_lbl)

	_status_lbl = UIThemeHelper.make_label("", 15, UIThemeHelper.COL_TURQUOISE)
	_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hdr.add_child(_status_lbl)

	var close_btn := UIThemeHelper.make_button("X", Color(0.46, 0.17, 0.16), 15)
	close_btn.custom_minimum_size = Vector2(36.0, 32.0)
	close_btn.pressed.connect(func(): set_panel_open(false))
	hdr.add_child(close_btn)

	# Section 1: 9 Ship Classes
	var ship_hdr := UIThemeHelper.make_label("SCHIFFSKLASSEN (ALLE 9 TIERS • SOFORTIGER WECHSEL AUF SEE)", 14, UIThemeHelper.COL_MUTED)
	root_vbox.add_child(ship_hdr)

	var ship_row := HBoxContainer.new()
	ship_row.add_theme_constant_override("separation", 6)
	root_vbox.add_child(ship_row)

	for tier in range(9):
		var spec: Dictionary = Contracts.get_ship_class_spec(tier)
		var cname: String = str(spec.get("name", "Schiff"))
		var cols: int = int(spec.get("grid_cols", 6))
		var rows: int = int(spec.get("grid_rows", 4))
		var sbtn := UIThemeHelper.make_button("%d: %s\n%dx%d" % [tier, cname, cols, rows], UIThemeHelper.COL_PANEL_CARD, 14)
		sbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sbtn.custom_minimum_size = Vector2(0.0, 48.0)
		sbtn.pressed.connect(func(): switch_ship_class(tier))
		ship_row.add_child(sbtn)
		_ship_btns[tier] = sbtn

	# Section 2: Quick Tools & World/Combat Spawner
	var tools_row := HBoxContainer.new()
	tools_row.add_theme_constant_override("separation", 6)
	root_vbox.add_child(tools_row)

	var gold_btn := UIThemeHelper.make_button("+100.000 Gold", Color(0.32, 0.25, 0.10), 14)
	gold_btn.pressed.connect(func(): add_gold(100000))
	tools_row.add_child(gold_btn)

	var all_stash_btn := UIThemeHelper.make_button("Alle Items ins Lager", Color(0.18, 0.34, 0.28), 14)
	all_stash_btn.pressed.connect(func(): add_all_items_to_stash(-1))
	tools_row.add_child(all_stash_btn)

	var clear_grid_btn := UIThemeHelper.make_button("Grid leeren", Color(0.38, 0.18, 0.18), 14)
	clear_grid_btn.pressed.connect(clear_player_grid)
	tools_row.add_child(clear_grid_btn)

	var repair_btn := UIThemeHelper.make_button("Voll-Reparatur", Color(0.16, 0.36, 0.22), 14)
	repair_btn.pressed.connect(full_repair_player)
	tools_row.add_child(repair_btn)

	var open_grid_btn := UIThemeHelper.make_button("Grid öffnen [Tab]", Color(0.20, 0.26, 0.38), 14)
	open_grid_btn.pressed.connect(func():
		set_panel_open(false)
		var bus := _bus()
		if bus != null:
			bus.cargo_grid_toggled.emit(true)
	)
	tools_row.add_child(open_grid_btn)

	_godmode_btn = UIThemeHelper.make_button("Godmode: AUS", Color(0.20, 0.18, 0.26), 14)
	_godmode_btn.pressed.connect(func():
		godmode_enabled = not godmode_enabled
		_refresh_cheat_buttons()
	)
	tools_row.add_child(_godmode_btn)

	_reload_btn = UIThemeHelper.make_button("Instant Reload: AUS", Color(0.20, 0.18, 0.26), 14)
	_reload_btn.pressed.connect(func():
		instant_reload_enabled = not instant_reload_enabled
		_refresh_cheat_buttons()
	)
	tools_row.add_child(_reload_btn)

	var spawn_row := HBoxContainer.new()
	spawn_row.add_theme_constant_override("separation", 6)
	root_vbox.add_child(spawn_row)

	var spawn_pirate_btn := UIThemeHelper.make_button("Pirat spawnen", Color(0.40, 0.18, 0.16), 14)
	spawn_pirate_btn.pressed.connect(func(): spawn_enemy_ahead("pirate"))
	spawn_row.add_child(spawn_pirate_btn)

	var spawn_gal_btn := UIThemeHelper.make_button("Schatz-Galeone spawnen", Color(0.36, 0.26, 0.12), 14)
	spawn_gal_btn.pressed.connect(func(): spawn_enemy_ahead("galleon"))
	spawn_row.add_child(spawn_gal_btn)

	var spawn_navy_btn := UIThemeHelper.make_button("Navy-Galeone spawnen", Color(0.16, 0.26, 0.42), 14)
	spawn_navy_btn.pressed.connect(func(): spawn_enemy_ahead("navy"))
	spawn_row.add_child(spawn_navy_btn)

	var spawn_kraken_btn := UIThemeHelper.make_button("Kraken rufen", Color(0.32, 0.14, 0.36), 14)
	spawn_kraken_btn.pressed.connect(func(): spawn_enemy_ahead("kraken"))
	spawn_row.add_child(spawn_kraken_btn)

	var spawn_loot_btn := UIThemeHelper.make_button("Beute-Kiste spawnen", Color(0.22, 0.34, 0.18), 14)
	spawn_loot_btn.pressed.connect(func(): spawn_enemy_ahead("loot"))
	spawn_row.add_child(spawn_loot_btn)

	var tp_tortuga_btn := UIThemeHelper.make_button("Zu Port Tortuga (0)", Color(0.18, 0.30, 0.34), 14)
	tp_tortuga_btn.pressed.connect(func(): teleport_to_island(0))
	spawn_row.add_child(tp_tortuga_btn)

	var tp_next_btn := UIThemeHelper.make_button("Insel-Sprung", Color(0.18, 0.30, 0.34), 14)
	tp_next_btn.pressed.connect(jump_next_island)
	spawn_row.add_child(tp_next_btn)

	# Section 3: Affix Selector + 27 Items Grid
	var item_hdr_row := HBoxContainer.new()
	item_hdr_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(item_hdr_row)

	var item_hdr := UIThemeHelper.make_label("ITEM-SPAWNER (ALLE 27 ITEMS • KLICK = AUTO-GRID / LAGER)   Affix:", 14, UIThemeHelper.COL_MUTED)
	item_hdr_row.add_child(item_hdr)

	for afx_def in AFFIX_DEFS:
		var afx_val: int = int(afx_def["affix"])
		var afx_lbl: String = str(afx_def["label"])
		var abtn := UIThemeHelper.make_button(afx_lbl, UIThemeHelper.COL_PANEL_CARD, 14)
		abtn.pressed.connect(func():
			selected_affix = afx_val
			_refresh_affix_buttons()
			_refresh_item_cards()
		)
		item_hdr_row.add_child(abtn)
		_affix_btns[afx_val] = abtn

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	_item_grid = GridContainer.new()
	_item_grid.columns = 4
	_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_grid.add_theme_constant_override("h_separation", 8)
	_item_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_item_grid)

	_build_item_cards()
	_refresh_ui()


func _build_item_cards() -> void:
	var all_ids: Array[String] = ItemDatabase.get_all_ids()
	var templates: Array[Contracts.GridItemData] = []
	for item_id in all_ids:
		templates.append(ItemDatabase.create_item(item_id, Contracts.ItemAffix.STANDARD))
	templates.sort_custom(func(a: Contracts.GridItemData, b: Contracts.GridItemData) -> bool:
		if a.category != b.category:
			return a.category < b.category
		return a.name < b.name
	)

	for tmpl in templates:
		var card_btn := Button.new()
		card_btn.custom_minimum_size = Vector2(268.0, 58.0)
		card_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card_btn.add_theme_stylebox_override("normal", UIThemeHelper.make_box_style(UIThemeHelper.COL_PANEL_CARD, UIThemeHelper.COL_BRASS_DIM, 4, 1, 6))
		card_btn.add_theme_stylebox_override("hover", UIThemeHelper.make_box_style(UIThemeHelper.COL_PANEL_CARD_INNER, UIThemeHelper.COL_GOLD, 4, 1, 6))
		card_btn.add_theme_stylebox_override("pressed", UIThemeHelper.make_box_style(UIThemeHelper.COL_PANEL_INSET, UIThemeHelper.COL_GOLD, 4, 1, 6))
		var item_id: String = tmpl.id
		card_btn.pressed.connect(func(): spawn_item_by_id(item_id, selected_affix))
		_item_grid.add_child(card_btn)

		var hbox := HBoxContainer.new()
		hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hbox.offset_left = 6.0
		hbox.offset_right = -6.0
		hbox.offset_top = 4.0
		hbox.offset_bottom = -4.0
		hbox.add_theme_constant_override("separation", 8)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_btn.add_child(hbox)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(46.0, 46.0)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(icon_rect)

		var txt_vbox := VBoxContainer.new()
		txt_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		txt_vbox.add_theme_constant_override("separation", 1)
		txt_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(txt_vbox)

		var name_lbl := UIThemeHelper.make_label(tmpl.name, 14, UIThemeHelper.COL_IVORY)
		name_lbl.clip_text = true
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		txt_vbox.add_child(name_lbl)

		var meta_lbl := UIThemeHelper.make_label("", 14, UIThemeHelper.COL_MUTED)
		meta_lbl.clip_text = true
		meta_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		txt_vbox.add_child(meta_lbl)

		_item_cards.append({
			"btn": card_btn,
			"icon": icon_rect,
			"name_lbl": name_lbl,
			"meta_lbl": meta_lbl,
			"tmpl": tmpl
		})


func _refresh_ui() -> void:
	_refresh_header_status()
	_refresh_ship_buttons()
	_refresh_affix_buttons()
	_refresh_cheat_buttons()
	_refresh_item_cards()


func _refresh_header_status() -> void:
	if _status_lbl == null:
		return
	var tier: int = int(player_ship.get("hull_tier")) if player_ship != null else 0
	var spec: Dictionary = Contracts.get_ship_class_spec(tier)
	var cname: String = str(spec.get("name", "Schaluppe"))
	var cols: int = int(spec.get("grid_cols", 6))
	var rows: int = int(spec.get("grid_rows", 4))
	var gold_val: int = harbor_ui.current_gold if harbor_ui != null else 0
	var placed_cnt: int = (player_grid.get("placed_items") as Array).size() if (player_grid != null and player_grid.get("placed_items") is Array) else 0
	var stash_cnt: int = (player_grid.get("stash_items") as Array).size() if (player_grid != null and player_grid.get("stash_items") is Array) else 0
	_status_lbl.text = "%s (%dx%d)  •  Gold: %d  •  Grid: %d / Lager: %d" % [cname, cols, rows, gold_val, placed_cnt, stash_cnt]


func _refresh_ship_buttons() -> void:
	var active_tier: int = int(player_ship.get("hull_tier")) if player_ship != null else 0
	for tier_var in _ship_btns.keys():
		var t: int = int(tier_var)
		var btn: Button = _ship_btns[tier_var]
		var is_active: bool = (t == active_tier)
		var bg: Color = Color(0.28, 0.22, 0.12) if is_active else UIThemeHelper.COL_PANEL_CARD
		var border: Color = UIThemeHelper.COL_GOLD if is_active else UIThemeHelper.COL_BRASS_DIM
		btn.add_theme_stylebox_override("normal", UIThemeHelper.make_box_style(bg, border, 4, 2 if is_active else 1, 4))
		btn.add_theme_color_override("font_color", UIThemeHelper.COL_GOLD if is_active else UIThemeHelper.COL_IVORY)


func _refresh_affix_buttons() -> void:
	for afx_var in _affix_btns.keys():
		var afx: int = int(afx_var)
		var btn: Button = _affix_btns[afx_var]
		var is_sel: bool = (afx == selected_affix)
		var col: Color = UIThemeHelper.affix_color(afx, Contracts.ItemRarity.COMMON)
		var bg: Color = col.darkened(0.68) if is_sel else UIThemeHelper.COL_PANEL_CARD
		var border: Color = col if is_sel else UIThemeHelper.COL_BRASS_DIM
		btn.add_theme_stylebox_override("normal", UIThemeHelper.make_box_style(bg, border, 4, 2 if is_sel else 1, 6))
		btn.add_theme_color_override("font_color", col if is_sel else UIThemeHelper.COL_IVORY)


func _refresh_cheat_buttons() -> void:
	if _godmode_btn != null:
		_godmode_btn.text = "Godmode: AN" if godmode_enabled else "Godmode: AUS"
		var bg: Color = Color(0.18, 0.42, 0.26) if godmode_enabled else Color(0.20, 0.18, 0.26)
		_godmode_btn.add_theme_stylebox_override("normal", UIThemeHelper.make_box_style(bg, UIThemeHelper.COL_GOLD if godmode_enabled else UIThemeHelper.COL_BRASS, 4, 1, 8))
	if _reload_btn != null:
		_reload_btn.text = "Instant Reload: AN" if instant_reload_enabled else "Instant Reload: AUS"
		var rbg: Color = Color(0.42, 0.26, 0.14) if instant_reload_enabled else Color(0.20, 0.18, 0.26)
		_reload_btn.add_theme_stylebox_override("normal", UIThemeHelper.make_box_style(rbg, UIThemeHelper.COL_GOLD if instant_reload_enabled else UIThemeHelper.COL_BRASS, 4, 1, 8))


func _refresh_item_cards() -> void:
	var afx_col: Color = UIThemeHelper.affix_color(selected_affix, Contracts.ItemRarity.COMMON)
	for entry in _item_cards:
		var tmpl: Contracts.GridItemData = entry["tmpl"]
		var icon_rect: TextureRect = entry["icon"]
		var name_lbl: Label = entry["name_lbl"]
		var meta_lbl: Label = entry["meta_lbl"]
		icon_rect.texture = ProceduralShipBaker.bake_item_grid_icon(
			tmpl.id,
			tmpl.category,
			tmpl.width,
			tmpl.height,
			tmpl.rarity,
			selected_affix
		)
		name_lbl.add_theme_color_override("font_color", UIThemeHelper.COL_IVORY if selected_affix == Contracts.ItemAffix.STANDARD else afx_col)
		var size_str: String = "%dx%d" % [tmpl.width, tmpl.height]
		if selected_affix == Contracts.ItemAffix.CURSED and tmpl.category != Contracts.ItemCategory.SAIL:
			size_str += "+1"
		var cat_str: String = str(CATEGORY_LABELS.get(tmpl.category, "Item"))
		meta_lbl.text = "%s • %s" % [size_str, cat_str]

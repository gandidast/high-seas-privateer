class_name HarborUI
extends Control
## Safe Harbor UI for ship repair, 6-Class Shipyard Roster (unlock & free switch),
## rotating Armory equipment shop (auto-refreshes on new port / cooldown),
## selling loot/cargo with affix bonuses, and 3-slot Harbor Quests.

var player_ship: Node = null
var player_grid: Node = null
var world_map_ref: Node = null
var ai_director_ref: AIDirector = null
var loot_system_ref: LootSystem = null
var network_manager_ref: Node = null

var current_island_index: int = -1
var current_gold: int = 120
var owned_ship_tiers: Dictionary = { Contracts.ShipClass.SLOOP: true }
var harbor_quests: Dictionary = {}   # island_idx (int) -> Array[Contracts.QuestData]
var harbor_shops: Dictionary = {}    # island_idx (int) -> Array[Dictionary]
var shop_refresh_times: Dictionary = {} # island_idx (int) -> float (sec)
var active_quests: Array[Contracts.QuestData] = []

var _last_shop_island_idx: int = -1
var _shop_just_refreshed: bool = false
var _bound_network_manager: Node = null
var _active_left_tab: String = "shop"
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _shop_panel: HarborShopPanel = HarborShopPanel.new()
var _quest_panel: HarborQuestPanel = HarborQuestPanel.new()
var _tab_active_style: StyleBoxFlat = null
var _tab_inactive_style: StyleBoxFlat = null

var _panel: PanelContainer = null
var _title_label: Label = null
var _gold_label: Label = null
var _class_label: Label = null
var _hp_label: Label = null
var _hp_bar: ProgressBar = null
var _repair_btn: Button = null
var _class_btns: Dictionary = {} # tier (int) -> Button
var _tab_shop_btn: Button = null
var _tab_sell_btn: Button = null
var _sell_all_btn: Button = null
var _shop_hint_label: Label = null
var _shop_scroll: ScrollContainer = null
var _sell_scroll: ScrollContainer = null
var _shop_list: VBoxContainer = null
var _sell_list: VBoxContainer = null
var _quest_list: VBoxContainer = null


func _bus() -> Contracts:
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		return st.root.get_node_or_null("EventBus") as Contracts
	return null


func _get_network_manager() -> Node:
	if is_instance_valid(network_manager_ref):
		return network_manager_ref
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("Main/NetworkManager")
	return null


func _sync_network_harbor_state(is_open: bool) -> void:
	var nm: Node = _get_network_manager()
	if nm != null and int(nm.get("current_mode")) == NetworkManager.Mode.CLIENT and nm.has_method("send_harbor_ui_state"):
		nm.call("send_harbor_ui_state", is_open)


func _ensure_network_quest_signals() -> void:
	var nm: Node = _get_network_manager()
	if nm == null or nm == _bound_network_manager:
		return
	_bound_network_manager = nm
	if nm.has_signal("bounty_spawned") and not nm.is_connected("bounty_spawned", Callable(self, "_on_network_bounty_spawned")):
		nm.connect("bounty_spawned", Callable(self, "_on_network_bounty_spawned"))
	if nm.has_signal("salvage_spawned") and not nm.is_connected("salvage_spawned", Callable(self, "_on_network_salvage_spawned")):
		nm.connect("salvage_spawned", Callable(self, "_on_network_salvage_spawned"))


func _on_network_bounty_spawned(quest_id: String, ship_id: int) -> void:
	for q in active_quests:
		if q.id == quest_id:
			q.target_ship_id = ship_id
			return


func _on_network_salvage_spawned(quest_id: String, drop_id: int, world_pos: Vector2) -> void:
	for q in active_quests:
		if q.id == quest_id:
			q.target_drop_id = drop_id
			q.target_pos = world_pos
			return


func _ready() -> void:
	_rng.randomize()
	_tab_active_style = UIThemeHelper.make_box_style(Color(0.28, 0.22, 0.16), UIThemeHelper.COL_GOLD, 3, 1, 5)
	_tab_inactive_style = UIThemeHelper.make_box_style(Color(0.15, 0.14, 0.20), UIThemeHelper.COL_BRASS_DIM, 3, 1, 5)

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	_build_ui()
	_connect_signals()
	_ensure_network_quest_signals()


func setup(
	p_player_ship: Node,
	p_player_grid: Node,
	p_world_map: Node,
	p_ai_director: AIDirector,
	p_loot_system: LootSystem,
	p_starting_gold: int = 120
) -> void:
	player_ship = p_player_ship
	player_grid = p_player_grid
	world_map_ref = p_world_map
	ai_director_ref = p_ai_director
	loot_system_ref = p_loot_system
	current_gold = p_starting_gold
	owned_ship_tiers = { Contracts.ShipClass.SLOOP: true }
	owned_ship_tiers[_get_player_hull_tier()] = true
	_ensure_network_quest_signals()
	_refresh_ui()


func set_gold(new_gold: int) -> void:
	current_gold = new_gold
	_refresh_header_and_shipyard()


func open_harbor(island_index: int) -> void:
	var islands: Array = _get_islands()
	if island_index < 0 or island_index >= islands.size():
		return
	var isl: Contracts.IslandData = islands[island_index]
	if isl != null and not isl.has_harbor:
		var bus := _bus()
		if bus != null:
			bus.notification_posted.emit("'%s' besitzt keinen sicheren Hafen!" % isl.name, "harbor")
		return

	current_island_index = island_index
	if not harbor_quests.has(island_index):
		_quest_panel.generate_harbor_quests(island_index, harbor_quests, _rng, islands, _find_water_pos)

	var now_sec: float = float(Time.get_ticks_msec()) * 0.001
	var first_gen: bool = not harbor_shops.has(island_index)
	var visited_other: bool = (_last_shop_island_idx >= 0 and _last_shop_island_idx != island_index)
	var cooldown_elapsed: bool = (now_sec - float(shop_refresh_times.get(island_index, 0.0))) >= HarborShopPanel.SHOP_REFRESH_COOLDOWN_SEC

	_shop_just_refreshed = false
	if first_gen or visited_other or cooldown_elapsed:
		_shop_panel.generate_harbor_shop(island_index, harbor_shops, _rng)
		shop_refresh_times[island_index] = now_sec
		_shop_just_refreshed = true
		if visited_other or (not first_gen and cooldown_elapsed):
			var bus := _bus()
			if bus != null:
				bus.notification_posted.emit("Frische Hafenlieferung verfügbar!", "trade")
	_last_shop_island_idx = island_index

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sync_network_harbor_state(true)
	_refresh_ui()


func close_harbor() -> void:
	var was_open: bool = visible
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if was_open:
		_sync_network_harbor_state(false)


func get_active_quests() -> Array[Contracts.QuestData]:
	return active_quests


func complete_quest(quest_id: String) -> bool:
	for i in range(active_quests.size()):
		var q: Contracts.QuestData = active_quests[i]
		if q.id == quest_id and not q.completed:
			q.completed = true
			active_quests.remove_at(i)
			_add_gold(q.reward_gold)
			var bus := _bus()
			if bus != null:
				bus.quest_completed.emit(q)
				bus.quest_list_updated.emit(active_quests.duplicate())
				bus.notification_posted.emit("Auftrag erfüllt: %s (+%d Gold)" % [q.title, q.reward_gold], "quest")
			if harbor_quests.has(q.source_island_idx):
				_quest_panel.replace_completed_harbor_quest(q.source_island_idx, q.quest_type, harbor_quests, _rng, _get_islands(), _find_water_pos)
			if visible:
				_refresh_ui()
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_harbor()
		get_viewport().set_input_as_handled()


func _connect_signals() -> void:
	var bus := _bus()
	if bus == null:
		return
	bus.harbor_ui_requested.connect(_on_harbor_ui_requested)
	bus.harbor_exited.connect(_on_harbor_exited)
	bus.harbor_entered.connect(_on_harbor_entered)
	bus.gold_changed.connect(_on_gold_changed)
	bus.ship_sunk.connect(_on_ship_sunk)
	bus.loot_collected.connect(_on_loot_collected)
	bus.ship_grid_updated.connect(_on_ship_grid_updated)
	bus.player_death_penalty.connect(_on_player_death_penalty)


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UIThemeHelper.COL_BG_DIM_HARBOR
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5; _panel.anchor_top = 0.5
	_panel.anchor_right = 0.5; _panel.anchor_bottom = 0.5
	_panel.offset_left = -560.0; _panel.offset_top = -325.0
	_panel.offset_right = 560.0; _panel.offset_bottom = 325.0
	_panel.add_theme_stylebox_override("panel", UIThemeHelper.make_box_style(UIThemeHelper.COL_PANEL_BG, UIThemeHelper.COL_BRASS, 8, 2, 12))
	add_child(_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(root_vbox)
	_build_header(root_vbox)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root_vbox.add_child(body)

	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(560.0, 0.0)
	left_col.add_theme_constant_override("separation", 10)
	body.add_child(left_col)

	_build_shipyard_card(left_col)
	_build_trade_card(left_col)
	_build_quests_card(body)
	_switch_left_tab("shop")


func _build_header(root_vbox: VBoxContainer) -> void:
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", UIThemeHelper.make_box_style(UIThemeHelper.COL_HEADER_BG, UIThemeHelper.COL_BRASS_DIM, 5, 1, 10))
	root_vbox.add_child(header_panel)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header_panel.add_child(header)

	_title_label = UIThemeHelper.make_label("HAFEN", 20, UIThemeHelper.COL_GOLD)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_gold_label = UIThemeHelper.make_label("120 Gold", 18, UIThemeHelper.COL_GOLD)
	header.add_child(_gold_label)

	var grid_btn := UIThemeHelper.make_button("Schiffs-Grid [Tab]", Color(0.18, 0.30, 0.42), 15)
	grid_btn.pressed.connect(_on_open_grid_pressed)
	header.add_child(grid_btn)

	var close_btn := UIThemeHelper.make_button("Ablegen [ESC]", Color(0.46, 0.18, 0.18), 15)
	close_btn.pressed.connect(close_harbor)
	header.add_child(close_btn)


func _build_shipyard_card(left_col: VBoxContainer) -> void:
	var yard_panel := PanelContainer.new()
	yard_panel.add_theme_stylebox_override("panel", UIThemeHelper.make_box_style(UIThemeHelper.COL_PANEL_CARD, UIThemeHelper.COL_BRASS_DIM, 6, 1, 10))
	left_col.add_child(yard_panel)

	var yard_vbox := VBoxContainer.new()
	yard_vbox.add_theme_constant_override("separation", 8)
	yard_panel.add_child(yard_vbox)

	var yard_top := HBoxContainer.new()
	yard_vbox.add_child(yard_top)
	var yard_title := UIThemeHelper.make_label("WERFT & FLOTTEN-ROSTER (6 KLASSEN)", 17, UIThemeHelper.COL_GOLD)
	yard_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yard_top.add_child(yard_title)
	_class_label = UIThemeHelper.make_label("Schaluppe (6x4)", 15, UIThemeHelper.COL_TURQUOISE)
	yard_top.add_child(_class_label)

	var rep_row := HBoxContainer.new()
	rep_row.add_theme_constant_override("separation", 10)
	yard_vbox.add_child(rep_row)

	var hp_col := VBoxContainer.new()
	hp_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_col.add_theme_constant_override("separation", 4)
	rep_row.add_child(hp_col)

	_hp_label = UIThemeHelper.make_label("Rumpf: 120 / 120", 15, UIThemeHelper.COL_IVORY)
	hp_col.add_child(_hp_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0.0, 12.0)
	_hp_bar.show_percentage = false
	_hp_bar.max_value = 100.0
	_hp_bar.value = 100.0
	_hp_bar.add_theme_stylebox_override("background", UIThemeHelper.make_box_style(UIThemeHelper.COL_PANEL_INSET, Color(0, 0, 0, 0), 3, 0, 0))
	_hp_bar.add_theme_stylebox_override("fill", UIThemeHelper.make_box_style(Color(0.30, 0.80, 0.44, 0.95), Color(0, 0, 0, 0), 3, 0, 0))
	hp_col.add_child(_hp_bar)

	_repair_btn = UIThemeHelper.make_button("Reparieren (0 G)", Color(0.18, 0.38, 0.26), 15)
	_repair_btn.pressed.connect(_on_repair_pressed)
	rep_row.add_child(_repair_btn)

	var class_grid := GridContainer.new()
	class_grid.columns = 2
	class_grid.add_theme_constant_override("h_separation", 8)
	class_grid.add_theme_constant_override("v_separation", 6)
	yard_vbox.add_child(class_grid)

	var tier_colors: Dictionary = {
		Contracts.ShipClass.SLOOP: Color(0.20, 0.28, 0.36),
		Contracts.ShipClass.SCHOONER: Color(0.18, 0.34, 0.38),
		Contracts.ShipClass.BRIGANTINE: Color(0.20, 0.30, 0.44),
		Contracts.ShipClass.FRIGATE: Color(0.30, 0.22, 0.42),
		Contracts.ShipClass.CORSAIR_CLIPPER: Color(0.42, 0.24, 0.18),
		Contracts.ShipClass.WAR_GALLEON: Color(0.38, 0.28, 0.14)
	}
	var tier_notes: Dictionary = {
		Contracts.ShipClass.SLOOP: "Starter",
		Contracts.ShipClass.CORSAIR_CLIPPER: "Schnellster Jäger (+15% Reload)",
		Contracts.ShipClass.WAR_GALLEON: "Schweres Schlachtschiff"
	}

	_class_btns.clear()
	for tier in range(6):
		var spec: Dictionary = Contracts.get_ship_class_spec(tier)
		var cname: String = str(spec.get("name", "Schiff"))
		var cols: int = int(spec.get("grid_cols", 6))
		var rows: int = int(spec.get("grid_rows", 4))
		var cost: int = int(spec.get("cost", 0))
		var note: String = str(tier_notes.get(tier, ""))

		var btn := UIThemeHelper.make_button("%s (%dx%d)" % [cname, cols, rows], tier_colors.get(tier, Color(0.22, 0.28, 0.38)), 14)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0.0, 32.0)
		var tip := "Tier %d • %dx%d Grid • %.0f HP • %.0f kn • %.1f Rüstung • %.0f kg" % [
			tier, cols, rows,
			float(spec.get("base_hp", 120.0)),
			float(spec.get("base_speed", 95.0)),
			float(spec.get("armor", 0.0)),
			float(spec.get("max_weight", 45.0))
		]
		if not note.is_empty():
			tip += " • %s" % note
		if cost > 0:
			tip += " • Preis: %d G (Wechsel danach kostenlos)" % cost
		btn.tooltip_text = tip
		btn.pressed.connect(_select_or_buy_ship_tier.bind(tier))
		class_grid.add_child(btn)
		_class_btns[tier] = btn


func _build_trade_card(left_col: VBoxContainer) -> void:
	var trade_panel := PanelContainer.new()
	trade_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	trade_panel.add_theme_stylebox_override("panel", UIThemeHelper.make_box_style(UIThemeHelper.COL_PANEL_CARD, UIThemeHelper.COL_BRASS_DIM, 6, 1, 10))
	left_col.add_child(trade_panel)

	var trade_vbox := VBoxContainer.new()
	trade_vbox.add_theme_constant_override("separation", 8)
	trade_panel.add_child(trade_vbox)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	trade_vbox.add_child(tab_row)

	_tab_shop_btn = UIThemeHelper.make_button("Waffenkammer", Color(0.28, 0.22, 0.16), 15)
	_tab_shop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_shop_btn.pressed.connect(_switch_left_tab.bind("shop"))
	tab_row.add_child(_tab_shop_btn)

	_tab_sell_btn = UIThemeHelper.make_button("Fracht-Verkauf", Color(0.20, 0.17, 0.16), 15)
	_tab_sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_sell_btn.pressed.connect(_switch_left_tab.bind("sell"))
	tab_row.add_child(_tab_sell_btn)

	_sell_all_btn = UIThemeHelper.make_button("Alles verkaufen", Color(0.46, 0.32, 0.14), 15)
	_sell_all_btn.pressed.connect(_on_sell_all_cargo_pressed)
	tab_row.add_child(_sell_all_btn)

	_shop_hint_label = UIThemeHelper.make_label("Frische Hafenlieferung verfügbar!", 14, Color(0.46, 0.90, 0.58))
	trade_vbox.add_child(_shop_hint_label)

	_shop_scroll = ScrollContainer.new()
	_shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	trade_vbox.add_child(_shop_scroll)
	_shop_list = VBoxContainer.new()
	_shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_list.add_theme_constant_override("separation", 8)
	_shop_scroll.add_child(_shop_list)

	_sell_scroll = ScrollContainer.new()
	_sell_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sell_scroll.visible = false
	trade_vbox.add_child(_sell_scroll)
	_sell_list = VBoxContainer.new()
	_sell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sell_list.add_theme_constant_override("separation", 6)
	_sell_scroll.add_child(_sell_list)


func _build_quests_card(body: HBoxContainer) -> void:
	var quest_panel := PanelContainer.new()
	quest_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quest_panel.add_theme_stylebox_override("panel", UIThemeHelper.make_box_style(UIThemeHelper.COL_PANEL_CARD, UIThemeHelper.COL_BRASS_DIM, 6, 1, 10))
	body.add_child(quest_panel)

	var q_vbox := VBoxContainer.new()
	q_vbox.add_theme_constant_override("separation", 10)
	quest_panel.add_child(q_vbox)

	var q_header := HBoxContainer.new()
	q_vbox.add_child(q_header)
	var q_title := UIThemeHelper.make_label("HAFEN-AUFTRÄGE (3)", 18, UIThemeHelper.COL_GOLD)
	q_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_header.add_child(q_title)

	var refresh_q_btn := UIThemeHelper.make_button("Neue Aufträge", Color(0.24, 0.21, 0.24), 15)
	refresh_q_btn.pressed.connect(func() -> void:
		if current_island_index >= 0:
			_quest_panel.generate_harbor_quests(current_island_index, harbor_quests, _rng, _get_islands(), _find_water_pos)
			_refresh_quest_list()
	)
	q_header.add_child(refresh_q_btn)

	var q_scroll := ScrollContainer.new()
	q_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	q_vbox.add_child(q_scroll)
	_quest_list = VBoxContainer.new()
	_quest_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_list.add_theme_constant_override("separation", 10)
	q_scroll.add_child(_quest_list)


func _switch_left_tab(tab_name: String) -> void:
	_active_left_tab = tab_name
	var is_shop: bool = (tab_name == "shop")
	if _shop_scroll != null: _shop_scroll.visible = is_shop
	if _shop_hint_label != null: _shop_hint_label.visible = is_shop
	if _sell_scroll != null: _sell_scroll.visible = not is_shop
	if _sell_all_btn != null: _sell_all_btn.visible = not is_shop
	if _tab_shop_btn != null: _tab_shop_btn.add_theme_stylebox_override("normal", _tab_active_style if is_shop else _tab_inactive_style)
	if _tab_sell_btn != null: _tab_sell_btn.add_theme_stylebox_override("normal", _tab_active_style if not is_shop else _tab_inactive_style)


func _refresh_ui() -> void:
	_refresh_header_and_shipyard()
	_refresh_shop_hint()
	_shop_panel.refresh_shop_list(_shop_list, harbor_shops.get(current_island_index, []), current_gold, _buy_shop_item)
	_shop_panel.refresh_sell_list(_sell_list, _tab_sell_btn, player_grid, _sell_single_item)
	_refresh_quest_list()


func _refresh_shop_hint() -> void:
	if _shop_hint_label == null:
		return
	var now_sec: float = float(Time.get_ticks_msec()) * 0.001
	var last_t: float = float(shop_refresh_times.get(current_island_index, now_sec))
	var remaining: float = maxf(0.0, HarborShopPanel.SHOP_REFRESH_COOLDOWN_SEC - (now_sec - last_t))
	if _shop_just_refreshed or remaining <= 0.5:
		_shop_hint_label.text = "Frische Hafenlieferung verfügbar!"
		_shop_hint_label.add_theme_color_override("font_color", Color(0.46, 0.90, 0.58))
	else:
		_shop_hint_label.text = "Nächste Lieferung in %ds (oder anderen sicheren Hafen anlaufen)" % int(ceil(remaining))
		_shop_hint_label.add_theme_color_override("font_color", UIThemeHelper.COL_MUTED)


func _refresh_quest_list() -> void:
	_quest_panel.refresh_quest_list(
		_quest_list,
		harbor_quests.get(current_island_index, []),
		current_island_index,
		_is_quest_active,
		_accept_quest,
		complete_quest
	)


func _get_player_hull_tier() -> int:
	if player_ship != null and player_ship.get("hull_tier") != null:
		return int(player_ship.get("hull_tier"))
	if player_grid != null and player_grid.get("hull_tier") != null:
		return int(player_grid.get("hull_tier"))
	return Contracts.ShipClass.SLOOP


func _get_class_name(tier: int) -> String:
	var spec: Dictionary = Contracts.get_ship_class_spec(tier)
	return "%s (%dx%d)" % [str(spec.get("name", "Schaluppe")), int(spec.get("grid_cols", 6)), int(spec.get("grid_rows", 4))]


func _refresh_header_and_shipyard() -> void:
	if _title_label == null:
		return
	var island_name: String = "Unbekannter Hafen"
	if current_island_index >= 0 and current_island_index < Contracts.ISLAND_NAMES.size():
		island_name = Contracts.ISLAND_NAMES[current_island_index]
	_title_label.text = "HAFEN: %s" % island_name.to_upper()
	_gold_label.text = "%d Gold" % current_gold

	var current_tier: int = _get_player_hull_tier()
	owned_ship_tiers[current_tier] = true
	_class_label.text = _get_class_name(current_tier)

	for tier_var in _class_btns.keys():
		var tier: int = int(tier_var)
		var btn: Button = _class_btns[tier_var]
		if btn == null:
			continue
		var spec: Dictionary = Contracts.get_ship_class_spec(tier)
		var cname: String = str(spec.get("name", "Schiff"))
		var cols: int = int(spec.get("grid_cols", 6))
		var rows: int = int(spec.get("grid_rows", 4))
		var cost: int = int(spec.get("cost", 0))
		var is_owned: bool = bool(owned_ship_tiers.get(tier, cost <= 0))
		if tier == current_tier:
			btn.text = "★ %s (%dx%d)" % [cname, cols, rows]
			btn.disabled = true
		elif is_owned:
			btn.text = "%s (%dx%d) • Wählen" % [cname, cols, rows]
			btn.disabled = false
		else:
			btn.text = "%s (%dx%d) • %d G" % [cname, cols, rows, cost]
			btn.disabled = current_gold < cost

	if player_ship != null:
		var hp: float = float(player_ship.get("hp"))
		var max_hp: float = maxf(1.0, float(player_ship.get("max_hp")))
		var missing: float = maxf(0.0, max_hp - hp)
		_hp_label.text = "Rumpf: %d / %d" % [int(round(hp)), int(round(max_hp))]
		if _hp_bar != null:
			_hp_bar.max_value = max_hp
			_hp_bar.value = hp
		_repair_btn.text = "Rumpf intakt" if missing <= 0.5 else "Reparieren (%d G)" % int(ceil(missing * 0.6))
		_repair_btn.disabled = missing <= 0.5 or current_gold < 1
	else:
		_hp_label.text = "Kein Schiff"
		if _hp_bar != null: _hp_bar.value = 0.0
		_repair_btn.disabled = true


func _select_or_buy_ship_tier(new_tier: int) -> void:
	var current_tier: int = _get_player_hull_tier()
	if new_tier == current_tier:
		return
	var spec: Dictionary = Contracts.get_ship_class_spec(new_tier)
	var is_owned: bool = bool(owned_ship_tiers.get(new_tier, int(spec.get("cost", 0)) <= 0))
	var cost: int = 0 if is_owned else int(spec.get("cost", 0))
	if not is_owned and current_gold < cost:
		return

	if cost > 0:
		_add_gold(-cost)
	owned_ship_tiers[new_tier] = true

	var stash_before: int = 0
	if player_grid != null and player_grid.get("stash_items") is Array:
		stash_before = (player_grid.get("stash_items") as Array).size()

	if player_grid != null and player_grid.has_method("set_hull_tier"):
		player_grid.call("set_hull_tier", new_tier)
	if player_ship != null and player_ship.has_method("upgrade_ship_class"):
		player_ship.call("upgrade_ship_class", new_tier)
	if player_grid != null and player_grid.has_method("compile_stats"):
		var new_stats: Contracts.ShipStats = player_grid.call("compile_stats")
		if player_ship != null and player_ship.has_method("apply_stats"):
			player_ship.call("apply_stats", new_stats)
			if not is_owned:
				player_ship.set("hp", new_stats.max_hp)
				var nm: Node = _get_network_manager()
				if nm != null and int(nm.get("current_mode")) == NetworkManager.Mode.CLIENT and nm.has_method("send_ship_repair"):
					nm.call("send_ship_repair", new_stats.max_hp)

	var moved_to_stash: int = 0
	if player_grid != null and player_grid.get("stash_items") is Array:
		moved_to_stash = maxi(0, (player_grid.get("stash_items") as Array).size() - stash_before)

	var bus := _bus()
	if bus != null:
		var cname: String = str(spec.get("name", "Schiff"))
		var msg: String = "Werft: %s gekauft & ausgerüstet!" % cname if not is_owned else "Werft: Auf %s gewechselt!" % cname
		if moved_to_stash > 0:
			msg += " (%d überschüssige Items im Lager)" % moved_to_stash
		bus.notification_posted.emit(msg, "harbor")
	_refresh_ui()


func _upgrade_ship_to_tier(new_tier: int, _cost: int) -> void:
	_select_or_buy_ship_tier(new_tier)


func _buy_shop_item(entry: Dictionary) -> void:
	if _shop_panel.buy_shop_item(entry, player_grid, current_gold, _add_gold, _bus()):
		_refresh_ui()


func _sell_single_item(item: Contracts.GridItemData, in_stash: bool) -> void:
	if _shop_panel.sell_single_item(item, in_stash, player_grid, _add_gold):
		_refresh_ui()


func _on_sell_all_cargo_pressed() -> void:
	if _shop_panel.sell_all_cargo(player_grid, _add_gold, _bus()):
		_refresh_ui()


func _accept_quest(q: Contracts.QuestData) -> void:
	if _is_quest_active(q.id):
		return
	_ensure_network_quest_signals()
	var nm: Node = _get_network_manager()
	var is_client: bool = (nm != null and int(nm.get("current_mode")) == NetworkManager.Mode.CLIENT)
	var boss_tier: int = int(q.get_meta("boss_hull_tier", Contracts.ShipClass.BRIGANTINE))
	if q.quest_type == Contracts.QuestType.BOUNTY:
		if is_client:
			if nm.has_method("send_bounty_quest_request"):
				nm.call("send_bounty_quest_request", q.target_pos, q.cargo_item_id, boss_tier, q.id)
		elif ai_director_ref != null:
			q.target_ship_id = ai_director_ref.spawn_ai_ship(Contracts.ShipFaction.PIRATE, q.target_pos, true, q.cargo_item_id, boss_tier)
	elif q.quest_type == Contracts.QuestType.SALVAGE:
		if is_client:
			if nm.has_method("send_salvage_quest_request"):
				nm.call("send_salvage_quest_request", q.target_pos, q.id)
		elif loot_system_ref != null:
			var drop: Contracts.LootDropData = loot_system_ref.spawn_salvage_target(q.target_pos, q.id)
			q.target_drop_id = drop.drop_id
			q.target_pos = drop.world_pos

	active_quests.append(q)
	var bus := _bus()
	if bus != null:
		bus.quest_accepted.emit(q)
		bus.quest_list_updated.emit(active_quests.duplicate())
		bus.notification_posted.emit("Auftrag angenommen: %s" % q.title, "quest")
	_refresh_quest_list()


func _on_repair_pressed() -> void:
	if player_ship == null:
		return
	var hp: float = float(player_ship.get("hp"))
	var max_hp: float = float(player_ship.get("max_hp"))
	var missing: float = maxf(0.0, max_hp - hp)
	if missing <= 0.5 or current_gold <= 0:
		return
	var full_cost: int = int(ceil(missing * 0.6))
	var paid: int = mini(current_gold, full_cost)
	var new_hp: float = minf(max_hp, hp + missing * (float(paid) / maxf(1.0, float(full_cost))))
	player_ship.set("hp", new_hp)
	_add_gold(-paid)
	var bus := _bus()
	if bus != null:
		bus.ship_repaired.emit(int(player_ship.get("ship_id")), new_hp, max_hp, paid)
		bus.notification_posted.emit("Rumpf repariert (-%d Gold)" % paid, "harbor")
	_refresh_header_and_shipyard()


func _on_open_grid_pressed() -> void:
	close_harbor()
	var bus := _bus()
	if bus != null:
		bus.cargo_grid_toggled.emit(true)


func _add_gold(delta: int) -> void:
	current_gold = maxi(0, current_gold + delta)
	var bus := _bus()
	if bus != null:
		bus.gold_changed.emit(current_gold, delta)


func _is_quest_active(qid: String) -> bool:
	for q in active_quests:
		if q.id == qid:
			return true
	return false


func _get_islands() -> Array:
	if world_map_ref != null:
		var arr: Variant = world_map_ref.get("islands")
		if arr is Array and not arr.is_empty():
			return arr
	return Contracts.get_islands()


func _find_water_pos(pos: Vector2) -> Vector2:
	if world_map_ref != null and world_map_ref.has_method("find_open_water_near"):
		return world_map_ref.call("find_open_water_near", pos, 0.22)
	if Contracts.get_water_depth(pos) >= 0.22:
		return pos
	return pos + Contracts.get_coast_normal(pos) * 60.0


func _on_harbor_ui_requested(open: bool, island_index: int) -> void:
	if open: open_harbor(island_index)
	else: close_harbor()


func _on_harbor_entered(ship_id: int, island_index: int, _island_name: String) -> void:
	if player_ship == null or ship_id != int(player_ship.get("ship_id")):
		return
	current_island_index = island_index
	var to_complete: Array[String] = []
	for q in active_quests:
		if q.quest_type == Contracts.QuestType.DELIVERY and q.target_island_idx == island_index:
			to_complete.append(q.id)
	for qid in to_complete:
		complete_quest(qid)


func _on_harbor_exited(ship_id: int, _island_index: int) -> void:
	if player_ship != null and ship_id == int(player_ship.get("ship_id")):
		current_island_index = -1
		if visible: close_harbor()


func _on_gold_changed(new_gold: int, _delta: int) -> void:
	current_gold = new_gold
	if visible: _refresh_header_and_shipyard()


func _on_player_death_penalty(ship_id: int, gold_lost: int, _respawn_seconds: float) -> void:
	if player_ship == null or ship_id == int(player_ship.get("ship_id")):
		if gold_lost > 0:
			_add_gold(-gold_lost)
		if visible:
			close_harbor()


func _on_ship_sunk(ship_id: int, _world_pos: Vector2, _faction: int, _killer_ship_id: int) -> void:
	var to_complete: Array[String] = []
	for q in active_quests:
		if q.quest_type == Contracts.QuestType.BOUNTY and q.target_ship_id == ship_id:
			to_complete.append(q.id)
	for qid in to_complete:
		complete_quest(qid)


func _on_loot_collected(drop_id: int, collector_ship_id: int, loot_data: Contracts.LootDropData) -> void:
	if player_ship != null and collector_ship_id != int(player_ship.get("ship_id")):
		return
	if loot_data != null:
		var nm: Node = _get_network_manager()
		var is_mp_client: bool = (nm != null and int(nm.get("current_mode")) == NetworkManager.Mode.CLIENT)
		if is_mp_client and player_grid != null and not loot_data.items.is_empty():
			for item_var in loot_data.items:
				if not (item_var is Contracts.GridItemData):
					continue
				var item: Contracts.GridItemData = item_var
				var placed: bool = false
				if player_grid.has_method("auto_place_item"):
					placed = bool(player_grid.call("auto_place_item", item))
				if not placed and player_grid.has_method("add_to_stash"):
					player_grid.call("add_to_stash", item)
		if loot_data.gold > 0:
			_add_gold(loot_data.gold)
			var bus := _bus()
			if bus != null:
				var item_cnt: int = loot_data.items.size()
				var msg: String = "Beute geborgen: +%d Gold" % loot_data.gold if item_cnt <= 0 else "Beute geborgen: +%d Gold & %d Item(s)" % [loot_data.gold, item_cnt]
				bus.notification_posted.emit(msg, "loot")
	var to_complete: Array[String] = []
	for q in active_quests:
		if q.quest_type == Contracts.QuestType.SALVAGE and (q.target_drop_id == drop_id or (loot_data != null and loot_data.quest_id == q.id)):
			to_complete.append(q.id)
	for qid in to_complete:
		complete_quest(qid)
	if visible:
		_shop_panel.refresh_sell_list(_sell_list, _tab_sell_btn, player_grid, _sell_single_item)


func _on_ship_grid_updated(ship_id: int, _equipped_items: Array) -> void:
	if visible and player_ship != null and ship_id == int(player_ship.get("ship_id")):
		_shop_panel.refresh_sell_list(_sell_list, _tab_sell_btn, player_grid, _sell_single_item)

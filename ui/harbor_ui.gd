class_name HarborUI
extends Control
## Safe Harbor UI for ship repair, 3-tier Shipyard class upgrades (Sloop ->
## Brigantine -> Heavy Frigate), rotating Armory equipment shop, selling
## loot/cargo with affix bonuses, and 3-slot Harbor Quests.
## Styled for crisp canvas_items MSDF readability on darkened navy/mahogany panels
## with brass borders and ProceduralShipBaker item icons.

const ITEM_DB_PATH: String = "res://sim/item_database.gd"

const BRIG_COST: int = 250
const FRIGATE_COST: int = 550

# Cohesive Navy / Mahogany / Brass / Ivory / Turquoise Palette
const COL_BG_DIM: Color = Color(0.03, 0.04, 0.07, 0.68)
const COL_PANEL_BG: Color = Color(0.10, 0.09, 0.14, 0.96)
const COL_CARD_BG: Color = Color(0.13, 0.12, 0.18, 0.94)
const COL_CARD_INNER: Color = Color(0.16, 0.14, 0.21, 0.95)
const COL_BRASS: Color = Color(0.85, 0.66, 0.29, 0.95)       # #d8a94b
const COL_BRASS_DIM: Color = Color(0.45, 0.35, 0.20, 0.80)
const COL_IVORY: Color = Color(0.97, 0.94, 0.88, 1.0)        # #f7f0e0
const COL_MUTED: Color = Color(0.75, 0.72, 0.68, 1.0)
const COL_GOLD: Color = Color(0.96, 0.79, 0.27, 1.0)         # #f6c945
const COL_TURQUOISE: Color = Color(0.40, 0.88, 0.92, 1.0)
const COL_OUTLINE: Color = Color(0.05, 0.04, 0.08, 0.85)
const COL_SHADOW: Color = Color(0.03, 0.03, 0.06, 0.70)

const SHOP_ITEM_POOL: Array[String] = [
	"greek_fire_2x1",
	"harpoon_ballista_2x1",
	"gunner_quarters_2x2",
	"carpenter_workshop_2x2",
	"crows_nest_1x2",
	"iron_ram_1x2",
	"storm_sails_2x2",
	"bronze_cannon_2x2",
	"alchemist_powder_1x1",
	"long_culverin_1x3"
]

var player_ship: Node = null
var player_grid: Node = null
var world_map_ref: Node = null
var ai_director_ref: AIDirector = null
var loot_system_ref: LootSystem = null

var current_island_index: int = -1
var current_gold: int = 120
var harbor_quests: Dictionary = {}   # island_idx (int) -> Array[Contracts.QuestData]
var harbor_shops: Dictionary = {}    # island_idx (int) -> Array[Dictionary]
var active_quests: Array[Contracts.QuestData] = []

var _active_left_tab: String = "shop" # "shop" or "sell"
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _panel: PanelContainer = null
var _title_label: Label = null
var _gold_label: Label = null
var _class_label: Label = null
var _hp_label: Label = null
var _hp_bar: ProgressBar = null
var _repair_btn: Button = null
var _brig_btn: Button = null
var _frigate_btn: Button = null
var _tab_shop_btn: Button = null
var _tab_sell_btn: Button = null
var _sell_all_btn: Button = null
var _shop_scroll: ScrollContainer = null
var _sell_scroll: ScrollContainer = null
var _shop_list: VBoxContainer = null
var _sell_list: VBoxContainer = null
var _quest_list: VBoxContainer = null
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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	_build_ui()
	_connect_signals()


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
	_refresh_ui()


func set_gold(new_gold: int) -> void:
	current_gold = new_gold
	_refresh_header_and_shipyard()


func open_harbor(island_index: int) -> void:
	current_island_index = island_index
	if not harbor_quests.has(island_index):
		_generate_harbor_quests(island_index)
	if not harbor_shops.has(island_index):
		_generate_harbor_shop(island_index)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_ui()


func close_harbor() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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
				bus.notification_posted.emit(
					"Auftrag erfüllt: %s (+%d Gold)" % [q.title, q.reward_gold],
					"quest"
				)
			if harbor_quests.has(q.source_island_idx):
				_replace_completed_harbor_quest(q.source_island_idx, q.quest_type)
			if visible:
				_refresh_ui()
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_harbor()
		get_viewport().set_input_as_handled()


func _connect_signals() -> void:
	var bus := _bus()
	if bus == null:
		return
	if not bus.harbor_ui_requested.is_connected(_on_harbor_ui_requested):
		bus.harbor_ui_requested.connect(_on_harbor_ui_requested)
	if not bus.harbor_exited.is_connected(_on_harbor_exited):
		bus.harbor_exited.connect(_on_harbor_exited)
	if not bus.harbor_entered.is_connected(_on_harbor_entered):
		bus.harbor_entered.connect(_on_harbor_entered)
	if not bus.gold_changed.is_connected(_on_gold_changed):
		bus.gold_changed.connect(_on_gold_changed)
	if not bus.ship_sunk.is_connected(_on_ship_sunk):
		bus.ship_sunk.connect(_on_ship_sunk)
	if not bus.loot_collected.is_connected(_on_loot_collected):
		bus.loot_collected.connect(_on_loot_collected)
	if not bus.ship_grid_updated.is_connected(_on_ship_grid_updated):
		bus.ship_grid_updated.connect(_on_ship_grid_updated)


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = COL_BG_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -540.0
	_panel.offset_top = -300.0
	_panel.offset_right = 540.0
	_panel.offset_bottom = 300.0
	_panel.add_theme_stylebox_override("panel", _make_box_style(COL_PANEL_BG, COL_BRASS, 8, 2, 12))
	add_child(_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(root_vbox)

	# Header Bar
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", _make_box_style(Color(0.15, 0.11, 0.12, 0.98), COL_BRASS_DIM, 5, 1, 10))
	root_vbox.add_child(header_panel)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header_panel.add_child(header)

	_title_label = _make_label("HAFEN", 20, COL_GOLD)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_gold_label = _make_label("120 Gold", 18, COL_GOLD)
	header.add_child(_gold_label)

	var grid_btn := _make_button("Schiffs-Grid [Tab]", Color(0.18, 0.30, 0.42), 15)
	grid_btn.pressed.connect(_on_open_grid_pressed)
	header.add_child(grid_btn)

	var close_btn := _make_button("Ablegen [ESC]", Color(0.46, 0.18, 0.18), 15)
	close_btn.pressed.connect(close_harbor)
	header.add_child(close_btn)

	# Body Columns
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root_vbox.add_child(body)

	# Left Column: Werft (Shipyard) + Waffenkammer / Fracht-Verkauf
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(520.0, 0.0)
	left_col.add_theme_constant_override("separation", 10)
	body.add_child(left_col)

	# Card 1: Werft (Repair & Ship Class Upgrade)
	var yard_panel := PanelContainer.new()
	yard_panel.add_theme_stylebox_override("panel", _make_box_style(COL_CARD_BG, COL_BRASS_DIM, 6, 1, 10))
	left_col.add_child(yard_panel)

	var yard_vbox := VBoxContainer.new()
	yard_vbox.add_theme_constant_override("separation", 8)
	yard_panel.add_child(yard_vbox)

	var yard_top := HBoxContainer.new()
	yard_vbox.add_child(yard_top)
	var yard_title := _make_label("WERFT & AUSBAU", 18, COL_GOLD)
	yard_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yard_top.add_child(yard_title)

	_class_label = _make_label("Schaluppe (Tier 0)", 15, COL_TURQUOISE)
	yard_top.add_child(_class_label)

	var rep_row := HBoxContainer.new()
	rep_row.add_theme_constant_override("separation", 10)
	yard_vbox.add_child(rep_row)

	var hp_col := VBoxContainer.new()
	hp_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_col.add_theme_constant_override("separation", 4)
	rep_row.add_child(hp_col)

	_hp_label = _make_label("Rumpf: 120 / 120", 15, COL_IVORY)
	hp_col.add_child(_hp_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0.0, 12.0)
	_hp_bar.show_percentage = false
	_hp_bar.max_value = 100.0
	_hp_bar.value = 100.0
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.08, 0.07, 0.11, 0.95)
	hp_bg.set_corner_radius_all(3)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.30, 0.80, 0.44, 0.95)
	hp_fill.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("background", hp_bg)
	_hp_bar.add_theme_stylebox_override("fill", hp_fill)
	hp_col.add_child(_hp_bar)

	_repair_btn = _make_button("Reparieren (0 G)", Color(0.18, 0.38, 0.26), 15)
	_repair_btn.pressed.connect(_on_repair_pressed)
	rep_row.add_child(_repair_btn)

	var class_row := HBoxContainer.new()
	class_row.add_theme_constant_override("separation", 10)
	yard_vbox.add_child(class_row)

	_brig_btn = _make_button("Brigg (250 G)", Color(0.20, 0.30, 0.42), 15)
	_brig_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brig_btn.tooltip_text = "Tier 1: 190 Basis-HP, 2 Masten, 70 Tragkraft"
	_brig_btn.pressed.connect(_upgrade_ship_to_tier.bind(Contracts.ShipClass.BRIGANTINE, BRIG_COST))
	class_row.add_child(_brig_btn)

	_frigate_btn = _make_button("Fregatte (550 G)", Color(0.32, 0.22, 0.40), 15)
	_frigate_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frigate_btn.tooltip_text = "Tier 2: 280 Basis-HP, +4 Rüstung, 3 Masten, 105 Tragkraft"
	_frigate_btn.pressed.connect(_upgrade_ship_to_tier.bind(Contracts.ShipClass.FRIGATE, FRIGATE_COST))
	class_row.add_child(_frigate_btn)

	# Card 2: Waffenkammer (Armory) & Fracht-Verkauf (Cargo Sell)
	var trade_panel := PanelContainer.new()
	trade_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	trade_panel.add_theme_stylebox_override("panel", _make_box_style(COL_CARD_BG, COL_BRASS_DIM, 6, 1, 10))
	left_col.add_child(trade_panel)

	var trade_vbox := VBoxContainer.new()
	trade_vbox.add_theme_constant_override("separation", 8)
	trade_panel.add_child(trade_vbox)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	trade_vbox.add_child(tab_row)

	_tab_shop_btn = _make_button("Waffenkammer", Color(0.28, 0.22, 0.16), 15)
	_tab_shop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_shop_btn.pressed.connect(_switch_left_tab.bind("shop"))
	tab_row.add_child(_tab_shop_btn)

	_tab_sell_btn = _make_button("Fracht-Verkauf", Color(0.20, 0.17, 0.16), 15)
	_tab_sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_sell_btn.pressed.connect(_switch_left_tab.bind("sell"))
	tab_row.add_child(_tab_sell_btn)

	_sell_all_btn = _make_button("Alles verkaufen", Color(0.46, 0.32, 0.14), 15)
	_sell_all_btn.pressed.connect(_on_sell_all_cargo_pressed)
	tab_row.add_child(_sell_all_btn)

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

	# Right Column: Hafen-Aufträge (Quests)
	var quest_panel := PanelContainer.new()
	quest_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quest_panel.add_theme_stylebox_override("panel", _make_box_style(COL_CARD_BG, COL_BRASS_DIM, 6, 1, 10))
	body.add_child(quest_panel)

	var q_vbox := VBoxContainer.new()
	q_vbox.add_theme_constant_override("separation", 10)
	quest_panel.add_child(q_vbox)

	var q_header := HBoxContainer.new()
	q_vbox.add_child(q_header)
	var q_title := _make_label("HAFEN-AUFTRÄGE (3)", 18, COL_GOLD)
	q_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_header.add_child(q_title)

	var refresh_q_btn := _make_button("Neue Aufträge", Color(0.24, 0.21, 0.24), 15)
	refresh_q_btn.pressed.connect(func() -> void:
		if current_island_index >= 0:
			_generate_harbor_quests(current_island_index)
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

	_switch_left_tab("shop")


func _switch_left_tab(tab_name: String) -> void:
	_active_left_tab = tab_name
	var is_shop: bool = (tab_name == "shop")
	if _shop_scroll != null:
		_shop_scroll.visible = is_shop
	if _sell_scroll != null:
		_sell_scroll.visible = not is_shop
	if _sell_all_btn != null:
		_sell_all_btn.visible = not is_shop
	if _tab_shop_btn != null:
		_tab_shop_btn.add_theme_stylebox_override(
			"normal",
			_make_box_style(Color(0.28, 0.22, 0.16) if is_shop else Color(0.15, 0.14, 0.20), COL_GOLD if is_shop else COL_BRASS_DIM, 3, 1, 5)
		)
	if _tab_sell_btn != null:
		_tab_sell_btn.add_theme_stylebox_override(
			"normal",
			_make_box_style(Color(0.28, 0.22, 0.16) if not is_shop else Color(0.15, 0.14, 0.20), COL_GOLD if not is_shop else COL_BRASS_DIM, 3, 1, 5)
		)


func _refresh_ui() -> void:
	_refresh_header_and_shipyard()
	_refresh_shop_list()
	_refresh_sell_list()
	_refresh_quest_list()


func _get_player_hull_tier() -> int:
	if player_ship != null and player_ship.get("hull_tier") != null:
		return int(player_ship.get("hull_tier"))
	if player_grid != null and player_grid.get("hull_tier") != null:
		return int(player_grid.get("hull_tier"))
	return Contracts.ShipClass.SLOOP


func _get_class_name(tier: int) -> String:
	match tier:
		Contracts.ShipClass.BRIGANTINE:
			return "Brigg (Tier 1)"
		Contracts.ShipClass.FRIGATE:
			return "Fregatte (Tier 2)"
		_:
			return "Schaluppe (Tier 0)"


func _refresh_header_and_shipyard() -> void:
	if _title_label == null:
		return
	var island_name: String = "Unbekannter Hafen"
	if current_island_index >= 0 and current_island_index < Contracts.ISLAND_NAMES.size():
		island_name = Contracts.ISLAND_NAMES[current_island_index]
	_title_label.text = "HAFEN: %s" % island_name.to_upper()
	_gold_label.text = "%d Gold" % current_gold

	var tier: int = _get_player_hull_tier()
	_class_label.text = _get_class_name(tier)

	if _brig_btn != null:
		if tier >= Contracts.ShipClass.BRIGANTINE:
			_brig_btn.text = "Brigg ✓"
			_brig_btn.disabled = true
		else:
			_brig_btn.text = "Brigg (%d G)" % BRIG_COST
			_brig_btn.disabled = current_gold < BRIG_COST

	if _frigate_btn != null:
		if tier >= Contracts.ShipClass.FRIGATE:
			_frigate_btn.text = "Fregatte ✓"
			_frigate_btn.disabled = true
		else:
			_frigate_btn.text = "Fregatte (%d G)" % FRIGATE_COST
			_frigate_btn.disabled = current_gold < FRIGATE_COST

	if player_ship != null:
		var hp: float = float(player_ship.get("hp"))
		var max_hp: float = maxf(1.0, float(player_ship.get("max_hp")))
		var missing: float = maxf(0.0, max_hp - hp)
		var cost: int = int(ceil(missing * 0.6))
		_hp_label.text = "Rumpf: %d / %d" % [int(round(hp)), int(round(max_hp))]
		if _hp_bar != null:
			_hp_bar.max_value = max_hp
			_hp_bar.value = hp
		if missing <= 0.5:
			_repair_btn.text = "Rumpf intakt"
			_repair_btn.disabled = true
		else:
			_repair_btn.text = "Reparieren (%d G)" % cost
			_repair_btn.disabled = current_gold < 1
	else:
		_hp_label.text = "Kein Schiff"
		if _hp_bar != null:
			_hp_bar.value = 0.0
		_repair_btn.disabled = true


func _upgrade_ship_to_tier(new_tier: int, cost: int) -> void:
	var cur_tier: int = _get_player_hull_tier()
	if new_tier <= cur_tier or current_gold < cost:
		return

	_add_gold(-cost)
	if player_ship != null and player_ship.has_method("upgrade_ship_class"):
		player_ship.call("upgrade_ship_class", new_tier)
	if player_grid != null and player_grid.has_method("set_hull_tier"):
		player_grid.call("set_hull_tier", new_tier)
	if player_grid != null and player_grid.has_method("compile_stats"):
		var new_stats: Contracts.ShipStats = player_grid.call("compile_stats")
		if player_ship != null and player_ship.has_method("apply_stats"):
			player_ship.call("apply_stats", new_stats)
			player_ship.set("hp", new_stats.max_hp)

	var bus := _bus()
	if bus != null:
		bus.notification_posted.emit("Werft: Schiff zur %s aufgerüstet!" % _get_class_name(new_tier), "harbor")
	_refresh_ui()


func _generate_harbor_shop(island_idx: int) -> void:
	var pool: Array[String] = SHOP_ITEM_POOL.duplicate()
	var offer: Array[Dictionary] = []
	for _i in range(4):
		if pool.is_empty():
			break
		var pick_idx: int = _rng.randi_range(0, pool.size() - 1)
		var item_id: String = pool[pick_idx]
		pool.remove_at(pick_idx)
		var item: Contracts.GridItemData = _create_shop_item(item_id)
		if item != null:
			var price: int = maxi(85, item.get_effective_gold_value() + 30)
			offer.append({
				"item_id": item_id,
				"item": item,
				"price": price,
				"sold": false
			})
	harbor_shops[island_idx] = offer


func _create_shop_item(item_id: String) -> Contracts.GridItemData:
	if _item_db_script == null and ResourceLoader.exists(ITEM_DB_PATH):
		_item_db_script = load(ITEM_DB_PATH) as Script
	if _item_db_script != null:
		var item: Variant = _item_db_script.call("create_item", item_id, Contracts.ItemAffix.STANDARD)
		if item is Contracts.GridItemData:
			return item
	return null


func _make_item_icon_rect(item: Contracts.GridItemData, icon_sz: float) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(icon_sz + 4.0, icon_sz + 4.0)
	frame.add_theme_stylebox_override("panel", _make_box_style(Color(0.08, 0.07, 0.11, 0.96), COL_BRASS_DIM, 2, 1, 2))

	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(icon_sz, icon_sz)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_rect.texture = ProceduralShipBaker.bake_item_grid_icon(
		item.id,
		item.category,
		item.width,
		item.height,
		item.rarity,
		item.affix
	)
	frame.add_child(tex_rect)
	return frame


func _refresh_shop_list() -> void:
	if _shop_list == null:
		return
	for child in _shop_list.get_children():
		child.queue_free()

	var offers: Array = harbor_shops.get(current_island_index, [])
	if offers.is_empty():
		_shop_list.add_child(_make_label("Keine Ausrüstung im Angebot.", 15, COL_MUTED))
		return

	for entry_var in offers:
		var entry: Dictionary = entry_var
		var item: Contracts.GridItemData = entry.get("item", null)
		if item == null:
			continue
		var price: int = int(entry.get("price", 120))
		var sold: bool = bool(entry.get("sold", false))

		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _make_box_style(COL_CARD_INNER, COL_BRASS_DIM, 5, 1, 8))
		_shop_list.add_child(card)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)

		row.add_child(_make_item_icon_rect(item, 44.0))

		var info_col := VBoxContainer.new()
		info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_col.add_theme_constant_override("separation", 3)
		row.add_child(info_col)

		var title := _make_label("%s (%dx%d)" % [item.name, item.width, item.height], 16, COL_GOLD)
		info_col.add_child(title)

		var desc := _make_label(item.description, 14, COL_MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_col.add_child(desc)

		var buy_btn := _make_button("Gekauft" if sold else "%d G" % price, Color(0.18, 0.36, 0.25), 15)
		buy_btn.custom_minimum_size = Vector2(96.0, 0.0)
		buy_btn.disabled = sold or current_gold < price
		buy_btn.pressed.connect(_buy_shop_item.bind(entry))
		row.add_child(buy_btn)


func _buy_shop_item(entry: Dictionary) -> void:
	if player_grid == null or bool(entry.get("sold", false)):
		return
	var price: int = int(entry.get("price", 120))
	if current_gold < price:
		return

	var item_id: String = str(entry.get("item_id", ""))
	var bought_item: Contracts.GridItemData = _create_shop_item(item_id)
	if bought_item == null:
		return

	entry["sold"] = true
	_add_gold(-price)

	var placed: bool = false
	if player_grid.has_method("auto_place_item"):
		placed = bool(player_grid.call("auto_place_item", bought_item))
	if not placed:
		if player_grid.has_method("add_to_stash"):
			player_grid.call("add_to_stash", bought_item)

	var bus := _bus()
	if bus != null:
		var msg: String = "%s gekauft & ausgerüstet!" % bought_item.name if placed else "%s gekauft (im Lager abgelegt)." % bought_item.name
		bus.notification_posted.emit(msg, "trade")
	_refresh_ui()


func _refresh_sell_list() -> void:
	if _sell_list == null:
		return
	for child in _sell_list.get_children():
		child.queue_free()

	if player_grid == null:
		_sell_list.add_child(_make_label("Kein Frachtraum verbunden.", 15, COL_MUTED))
		return

	var entries: Array[Dictionary] = []
	var stash: Variant = player_grid.get("stash_items")
	if stash is Array:
		for item_var in stash:
			if item_var is Contracts.GridItemData:
				entries.append({ "item": item_var, "in_stash": true })

	var placed: Array = _get_placed_grid_items()
	for item_var in placed:
		if item_var is Contracts.GridItemData:
			entries.append({ "item": item_var, "in_stash": false })

	if _tab_sell_btn != null:
		_tab_sell_btn.text = "Fracht (%d)" % entries.size()

	if entries.is_empty():
		_sell_list.add_child(_make_label("Keine Fracht oder Beute an Bord.", 15, COL_MUTED))
		return

	for entry in entries:
		var item: Contracts.GridItemData = entry["item"]
		var in_stash: bool = bool(entry["in_stash"])
		var value: int = item.get_effective_gold_value()

		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _make_box_style(COL_CARD_INNER, Color(0.32, 0.28, 0.22, 0.70), 5, 1, 6))
		_sell_list.add_child(card)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)

		row.add_child(_make_item_icon_rect(item, 32.0))

		var tag: String = "[Lager] " if in_stash else "[Deck] "
		var col: Color = COL_IVORY
		if item.affix == Contracts.ItemAffix.MASTERWORK:
			col = COL_TURQUOISE
		elif item.affix == Contracts.ItemAffix.CURSED:
			col = Color(0.86, 0.48, 0.96)
		elif item.affix == Contracts.ItemAffix.RUSTED:
			col = Color(0.72, 0.62, 0.55)

		var lbl := _make_label(tag + item.get_display_name(), 15, col)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(lbl)

		var btn := _make_button("+%d G" % value, Color(0.42, 0.30, 0.14), 15)
		btn.pressed.connect(_sell_single_item.bind(item, in_stash))
		row.add_child(btn)


func _refresh_quest_list() -> void:
	if _quest_list == null:
		return
	for child in _quest_list.get_children():
		child.queue_free()

	var offered: Array = harbor_quests.get(current_island_index, [])
	for q_var in offered:
		var q: Contracts.QuestData = q_var
		if q == null:
			continue
		_quest_list.add_child(_create_quest_card(q))


func _create_quest_card(q: Contracts.QuestData) -> PanelContainer:
	var accent: Color = Color(0.94, 0.46, 0.42)
	var type_tag: String = "KOPFGELD"
	if q.quest_type == Contracts.QuestType.DELIVERY:
		type_tag = "LIEFERUNG"
		accent = COL_TURQUOISE
	elif q.quest_type == Contracts.QuestType.SALVAGE:
		type_tag = "BERGUNG"
		accent = COL_GOLD

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_box_style(COL_CARD_INNER, COL_BRASS_DIM, 6, 1, 10))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vbox.add_child(top)

	var badge := _make_label("[%s]" % type_tag, 14, accent)
	top.add_child(badge)

	var title_lbl := _make_label(q.title, 16, COL_IVORY)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(title_lbl)

	top.add_child(_make_label("+%d G" % q.reward_gold, 16, COL_GOLD))

	var desc_lbl := _make_label(q.description, 14, COL_MUTED)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)

	var is_active: bool = _is_quest_active(q.id)
	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)

	if is_active:
		if q.quest_type == Contracts.QuestType.DELIVERY and q.target_island_idx == current_island_index:
			var turn_in_btn := _make_button("Lieferung abgeben (+%d G)" % q.reward_gold, Color(0.18, 0.42, 0.24), 15)
			turn_in_btn.pressed.connect(func() -> void: complete_quest(q.id))
			btn_row.add_child(turn_in_btn)
		else:
			var active_lbl := _make_label("Auftrag aktiv (siehe Kompass-HUD)", 14, Color(0.50, 0.90, 0.56))
			btn_row.add_child(active_lbl)
	else:
		var accept_btn := _make_button("Auftrag annehmen", Color(0.20, 0.32, 0.46), 15)
		accept_btn.pressed.connect(_accept_quest.bind(q))
		btn_row.add_child(accept_btn)

	return card


func _generate_harbor_quests(island_idx: int) -> void:
	var list: Array[Contracts.QuestData] = []
	list.append(_make_quest_of_type(island_idx, Contracts.QuestType.BOUNTY))
	list.append(_make_quest_of_type(island_idx, Contracts.QuestType.DELIVERY))
	list.append(_make_quest_of_type(island_idx, Contracts.QuestType.SALVAGE))
	harbor_quests[island_idx] = list


func _replace_completed_harbor_quest(island_idx: int, q_type: int) -> void:
	if not harbor_quests.has(island_idx):
		return
	var list: Array = harbor_quests[island_idx]
	for i in range(list.size()):
		var q: Contracts.QuestData = list[i]
		if q.quest_type == q_type and q.completed:
			list[i] = _make_quest_of_type(island_idx, q_type)
			return


func _make_quest_of_type(island_idx: int, q_type: int) -> Contracts.QuestData:
	var q := Contracts.QuestData.new()
	q.id = "q_%d_%d_%d" % [island_idx, q_type, _rng.randi_range(1000, 99999)]
	q.quest_type = q_type
	q.source_island_idx = island_idx

	var islands: Array = _get_islands()
	var src_isl: Contracts.IslandData = islands[clampi(island_idx, 0, islands.size() - 1)]

	match q_type:
		Contracts.QuestType.BOUNTY:
			var captains: Array[String] = ["Korsar Vane", "Rotbart Morgan", "Schwarze Anne", "Eisenkiefer Flint", "Käpt'n Blutsturm"]
			var cap_name: String = captains[_rng.randi_range(0, captains.size() - 1)]
			var spawn_dir: Vector2 = Vector2.from_angle(_rng.randf_range(-PI, PI))
			var target_pos: Vector2 = _find_water_pos(src_isl.harbor_pos + spawn_dir * _rng.randf_range(360.0, 560.0))
			q.title = "Jagd auf %s" % cap_name
			q.description = "Versenke die gefürchtete Piraten-Brigg '%s' vor %s." % [cap_name, src_isl.name]
			q.target_pos = target_pos
			q.reward_gold = _rng.randi_range(160, 240)
			q.cargo_item_id = cap_name

		Contracts.QuestType.DELIVERY:
			var target_idx: int = (island_idx + _rng.randi_range(1, maxi(1, islands.size() - 1))) % islands.size()
			var dst_isl: Contracts.IslandData = islands[target_idx]
			q.target_island_idx = target_idx
			q.target_pos = dst_isl.harbor_pos
			q.cargo_item_id = "spice_crates_1x2"
			q.title = "Eilfracht nach %s" % dst_isl.name
			q.description = "Liefere versiegelte Gewürzkisten sicher in den Hafen von %s." % dst_isl.name
			q.reward_gold = _rng.randi_range(115, 175)

		Contracts.QuestType.SALVAGE:
			var angle: float = _rng.randf_range(-PI, PI)
			var wreck_pos: Vector2 = _find_water_pos(Vector2(cos(angle), sin(angle)) * _rng.randf_range(260.0, 640.0))
			q.target_pos = wreck_pos
			q.title = "Versunkenes Wrack bergen"
			q.description = "Berge die verlorene Schatztruhe bei den Wrack-Koordinaten (%d, %d)." % [int(wreck_pos.x), int(wreck_pos.y)]
			q.reward_gold = _rng.randi_range(130, 195)

	return q


func _accept_quest(q: Contracts.QuestData) -> void:
	if _is_quest_active(q.id):
		return

	if q.quest_type == Contracts.QuestType.BOUNTY and ai_director_ref != null:
		var boss_id: int = ai_director_ref.spawn_ai_ship(
			Contracts.ShipFaction.PIRATE,
			q.target_pos,
			true,
			q.cargo_item_id
		)
		q.target_ship_id = boss_id
	elif q.quest_type == Contracts.QuestType.SALVAGE and loot_system_ref != null:
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
	var heal_ratio: float = float(paid) / maxf(1.0, float(full_cost))
	var new_hp: float = minf(max_hp, hp + missing * heal_ratio)
	player_ship.set("hp", new_hp)

	_add_gold(-paid)
	var sid: int = int(player_ship.get("ship_id"))
	var bus := _bus()
	if bus != null:
		bus.ship_repaired.emit(sid, new_hp, max_hp, paid)
		bus.notification_posted.emit("Rumpf repariert (-%d Gold)" % paid, "harbor")
	_refresh_header_and_shipyard()


func _on_sell_all_cargo_pressed() -> void:
	if player_grid == null:
		return
	var total_gained: int = 0

	var stash: Variant = player_grid.get("stash_items")
	if stash is Array:
		var stash_copy: Array = stash.duplicate()
		for item_var in stash_copy:
			if item_var is Contracts.GridItemData:
				total_gained += item_var.get_effective_gold_value()
				if player_grid.has_method("remove_from_stash"):
					player_grid.call("remove_from_stash", item_var)
				else:
					stash.erase(item_var)

	var placed: Array = _get_placed_grid_items()
	for item_var in placed:
		if item_var is Contracts.GridItemData:
			if item_var.category == Contracts.ItemCategory.CARGO or item_var.category == Contracts.ItemCategory.TREASURE:
				total_gained += item_var.get_effective_gold_value()
				_remove_from_grid(item_var)

	if total_gained > 0:
		_add_gold(total_gained)
		if player_grid.has_method("compile_stats"):
			player_grid.call("compile_stats")
		var bus := _bus()
		if bus != null:
			bus.notification_posted.emit("Beute & Fracht verkauft (+%d Gold)" % total_gained, "trade")
		_refresh_ui()


func _sell_single_item(item: Contracts.GridItemData, in_stash: bool) -> void:
	if player_grid == null or item == null:
		return
	var val: int = item.get_effective_gold_value()
	if in_stash:
		if player_grid.has_method("remove_from_stash"):
			player_grid.call("remove_from_stash", item)
		else:
			var stash: Variant = player_grid.get("stash_items")
			if stash is Array:
				stash.erase(item)
	else:
		_remove_from_grid(item)
		if player_grid.has_method("compile_stats"):
			player_grid.call("compile_stats")

	_add_gold(val)
	_refresh_ui()


func _get_placed_grid_items() -> Array:
	if player_grid == null:
		return []
	if player_grid.has_method("get_placed_items"):
		return player_grid.call("get_placed_items")
	var raw: Variant = player_grid.get("placed_items")
	if raw is Array:
		return raw.duplicate()
	return []


func _remove_from_grid(item: Contracts.GridItemData) -> void:
	if player_grid == null:
		return
	if player_grid.has_method("remove_item"):
		player_grid.call("remove_item", item)
	else:
		var raw: Variant = player_grid.get("placed_items")
		if raw is Array:
			raw.erase(item)


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
	if open:
		open_harbor(island_index)
	else:
		close_harbor()


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
		if visible:
			close_harbor()


func _on_gold_changed(new_gold: int, _delta: int) -> void:
	current_gold = new_gold
	if visible:
		_refresh_header_and_shipyard()


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
	if loot_data != null and loot_data.gold > 0:
		_add_gold(loot_data.gold)
		var bus := _bus()
		if bus != null:
			bus.notification_posted.emit("Beute geborgen: +%d Gold" % loot_data.gold, "loot")

	var to_complete: Array[String] = []
	for q in active_quests:
		if q.quest_type == Contracts.QuestType.SALVAGE:
			if q.target_drop_id == drop_id or (loot_data != null and loot_data.quest_id == q.id):
				to_complete.append(q.id)
	for qid in to_complete:
		complete_quest(qid)

	if visible:
		_refresh_sell_list()


func _on_ship_grid_updated(ship_id: int, _equipped_items: Array) -> void:
	if visible and player_ship != null and ship_id == int(player_ship.get("ship_id")):
		_refresh_sell_list()


func _make_box_style(bg: Color, border: Color, corner_rad: int = 3, border_w: int = 1, margin: int = 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(corner_rad)
	sb.set_content_margin_all(margin)
	return sb


func _make_label(txt: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", maxi(14, font_size))
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", COL_OUTLINE)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_shadow_color", COL_SHADOW)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	return lbl


func _make_button(txt: String, bg: Color, font_size: int = 15) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.add_theme_font_size_override("font_size", maxi(14, font_size))
	btn.add_theme_color_override("font_color", COL_IVORY)
	btn.add_theme_color_override("font_outline_color", COL_OUTLINE)
	btn.add_theme_constant_override("outline_size", 2)
	btn.add_theme_color_override("font_shadow_color", COL_SHADOW)
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 2)
	btn.add_theme_stylebox_override("normal", _make_box_style(bg, COL_BRASS, 4, 1, 8))
	btn.add_theme_stylebox_override("hover", _make_box_style(bg.lightened(0.14), COL_GOLD, 4, 1, 8))
	btn.add_theme_stylebox_override("pressed", _make_box_style(bg.darkened(0.18), COL_GOLD, 4, 1, 8))
	btn.add_theme_stylebox_override("disabled", _make_box_style(Color(0.14, 0.13, 0.16, 0.90), Color(0.32, 0.29, 0.28, 0.80), 4, 1, 8))
	return btn

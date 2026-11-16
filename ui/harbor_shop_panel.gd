class_name HarborShopPanel
extends RefCounted
## Modular Armory shop & Cargo-sell panel helper for HarborUI.
## Caches NEAREST pixel-art item icons and uses UIThemeHelper for styling.

const ITEM_DB_PATH: String = "res://sim/item_database.gd"
const SHOP_OFFER_COUNT: int = 5
const SHOP_REFRESH_COOLDOWN_SEC: float = 75.0
const SHOP_ITEM_POOL: Array[String] = [
	"carronade_2x1",
	"organ_gun_2x2",
	"twin_cannon_2x3",
	"pitch_mortar_2x2",
	"bow_chaser_1x2",
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

var _item_db_script: Script = null
var _icon_cache: Dictionary = {}
var _icon_frame_style: StyleBoxFlat = null
var _shop_card_style: StyleBoxFlat = null
var _sell_card_style: StyleBoxFlat = null


func _init() -> void:
	if ResourceLoader.exists(ITEM_DB_PATH):
		_item_db_script = load(ITEM_DB_PATH) as Script
	_icon_frame_style = UIThemeHelper.make_box_style(Color(0.08, 0.07, 0.11, 0.96), UIThemeHelper.COL_BRASS_DIM, 2, 1, 2)
	_shop_card_style = UIThemeHelper.make_box_style(UIThemeHelper.COL_PANEL_CARD_INNER, UIThemeHelper.COL_BRASS_DIM, 5, 1, 8)
	_sell_card_style = UIThemeHelper.make_box_style(UIThemeHelper.COL_PANEL_CARD_INNER, Color(0.32, 0.28, 0.22, 0.70), 5, 1, 6)


func create_shop_item(item_id: String, affix: int = Contracts.ItemAffix.STANDARD) -> Contracts.GridItemData:
	if _item_db_script == null and ResourceLoader.exists(ITEM_DB_PATH):
		_item_db_script = load(ITEM_DB_PATH) as Script
	if _item_db_script != null:
		var item: Variant = _item_db_script.call("create_item", item_id, affix)
		if item is Contracts.GridItemData:
			return item
	return null


func generate_harbor_shop(island_idx: int, harbor_shops: Dictionary, rng: RandomNumberGenerator) -> void:
	var pool: Array[String] = SHOP_ITEM_POOL.duplicate()
	var offer: Array[Dictionary] = []
	for _i in range(SHOP_OFFER_COUNT):
		if pool.is_empty():
			break
		var pick_idx: int = rng.randi_range(0, pool.size() - 1)
		var item_id: String = pool[pick_idx]
		pool.remove_at(pick_idx)
		var affix: int = Contracts.ItemAffix.MASTERWORK if rng.randf() < 0.24 else Contracts.ItemAffix.STANDARD
		var item: Contracts.GridItemData = create_shop_item(item_id, affix)
		if item != null:
			var price: int = maxi(85, item.get_effective_gold_value() + 30)
			offer.append({
				"item_id": item_id,
				"affix": affix,
				"item": item,
				"price": price,
				"sold": false
			})
	harbor_shops[island_idx] = offer


func get_item_icon(item: Contracts.GridItemData) -> ImageTexture:
	var key: String = "%s_%d_%dx%d_%d_%d" % [item.id, item.category, item.width, item.height, item.rarity, item.affix]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var tex: ImageTexture = ProceduralShipBaker.bake_item_grid_icon(
		item.id, item.category, item.width, item.height, item.rarity, item.affix
	)
	_icon_cache[key] = tex
	return tex


func make_item_icon_rect(item: Contracts.GridItemData, icon_sz: float) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(icon_sz + 4.0, icon_sz + 4.0)
	frame.add_theme_stylebox_override("panel", _icon_frame_style)

	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(icon_sz, icon_sz)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_rect.texture = get_item_icon(item)
	frame.add_child(tex_rect)
	return frame


func refresh_shop_list(shop_list: VBoxContainer, offers: Array, current_gold: int, on_buy: Callable) -> void:
	if shop_list == null:
		return
	for child in shop_list.get_children():
		child.queue_free()

	if offers.is_empty():
		shop_list.add_child(UIThemeHelper.make_label("Keine Ausrüstung im Angebot.", 15, UIThemeHelper.COL_MUTED))
		return

	for entry_var in offers:
		var entry: Dictionary = entry_var
		var item: Contracts.GridItemData = entry.get("item", null)
		if item == null:
			continue
		var price: int = int(entry.get("price", 120))
		var sold: bool = bool(entry.get("sold", false))

		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _shop_card_style)
		shop_list.add_child(card)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		row.add_child(make_item_icon_rect(item, 44.0))

		var info_col := VBoxContainer.new()
		info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_col.add_theme_constant_override("separation", 3)
		row.add_child(info_col)

		var name_col: Color = UIThemeHelper.affix_color(item.affix, item.rarity) if item.affix != Contracts.ItemAffix.STANDARD else UIThemeHelper.COL_GOLD
		info_col.add_child(UIThemeHelper.make_label("%s (%dx%d)" % [item.get_display_name(), item.width, item.height], 15, name_col))
		var desc: Label = UIThemeHelper.make_label(item.description, 14, UIThemeHelper.COL_MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_col.add_child(desc)

		var buy_btn: Button = UIThemeHelper.make_button("Gekauft" if sold else "%d G" % price, Color(0.18, 0.36, 0.25), 15)
		buy_btn.custom_minimum_size = Vector2(96.0, 0.0)
		buy_btn.disabled = sold or current_gold < price
		buy_btn.pressed.connect(on_buy.bind(entry))
		row.add_child(buy_btn)


func refresh_sell_list(sell_list: VBoxContainer, tab_sell_btn: Button, player_grid: Node, on_sell_one: Callable) -> void:
	if sell_list == null:
		return
	for child in sell_list.get_children():
		child.queue_free()

	if player_grid == null:
		sell_list.add_child(UIThemeHelper.make_label("Kein Frachtraum verbunden.", 15, UIThemeHelper.COL_MUTED))
		return

	var entries: Array[Dictionary] = []
	var stash: Variant = player_grid.get("stash_items")
	if stash is Array:
		for item_var in stash:
			if item_var is Contracts.GridItemData:
				entries.append({ "item": item_var, "in_stash": true })

	for item_var in get_placed_grid_items(player_grid):
		if item_var is Contracts.GridItemData:
			entries.append({ "item": item_var, "in_stash": false })

	if tab_sell_btn != null:
		tab_sell_btn.text = "Fracht (%d)" % entries.size()

	if entries.is_empty():
		sell_list.add_child(UIThemeHelper.make_label("Keine Fracht oder Beute an Bord.", 15, UIThemeHelper.COL_MUTED))
		return

	for entry in entries:
		var item: Contracts.GridItemData = entry["item"]
		var in_stash: bool = bool(entry["in_stash"])
		var value: int = item.get_effective_gold_value()

		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _sell_card_style)
		sell_list.add_child(card)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		row.add_child(make_item_icon_rect(item, 32.0))

		var tag: String = "[Lager] " if in_stash else "[Deck] "
		var col: Color = UIThemeHelper.COL_IVORY
		if item.affix == Contracts.ItemAffix.MASTERWORK:
			col = UIThemeHelper.COL_TURQUOISE
		elif item.affix == Contracts.ItemAffix.CURSED:
			col = Color(0.86, 0.48, 0.96)
		elif item.affix == Contracts.ItemAffix.RUSTED:
			col = Color(0.72, 0.62, 0.55)

		var lbl: Label = UIThemeHelper.make_label(tag + item.get_display_name(), 15, col)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(lbl)

		var btn: Button = UIThemeHelper.make_button("+%d G" % value, Color(0.42, 0.30, 0.14), 15)
		btn.pressed.connect(on_sell_one.bind(item, in_stash))
		row.add_child(btn)


func buy_shop_item(entry: Dictionary, player_grid: Node, current_gold: int, add_gold_cb: Callable, bus: Contracts) -> bool:
	if player_grid == null or bool(entry.get("sold", false)):
		return false
	var price: int = int(entry.get("price", 120))
	if current_gold < price:
		return false

	var affix: int = int(entry.get("affix", Contracts.ItemAffix.STANDARD))
	var bought_item: Contracts.GridItemData = create_shop_item(str(entry.get("item_id", "")), affix)
	if bought_item == null:
		return false

	entry["sold"] = true
	add_gold_cb.call(-price)

	var placed: bool = false
	if player_grid.has_method("auto_place_item"):
		placed = bool(player_grid.call("auto_place_item", bought_item))
	if not placed and player_grid.has_method("add_to_stash"):
		player_grid.call("add_to_stash", bought_item)

	if bus != null:
		var msg: String = "%s gekauft & ausgerüstet!" % bought_item.get_display_name() if placed else "%s gekauft (im Lager abgelegt)." % bought_item.get_display_name()
		bus.notification_posted.emit(msg, "trade")
	return true


func sell_single_item(item: Contracts.GridItemData, in_stash: bool, player_grid: Node, add_gold_cb: Callable) -> bool:
	if player_grid == null or item == null:
		return false
	var val: int = item.get_effective_gold_value()
	if in_stash:
		if player_grid.has_method("remove_from_stash"):
			player_grid.call("remove_from_stash", item)
		else:
			var stash: Variant = player_grid.get("stash_items")
			if stash is Array:
				stash.erase(item)
	else:
		remove_from_grid(player_grid, item)
		if player_grid.has_method("compile_stats"):
			player_grid.call("compile_stats")
	add_gold_cb.call(val)
	return true


func sell_all_cargo(player_grid: Node, add_gold_cb: Callable, bus: Contracts) -> bool:
	if player_grid == null:
		return false
	var total_gained: int = 0
	var stash: Variant = player_grid.get("stash_items")
	if stash is Array:
		for item_var in stash.duplicate():
			if item_var is Contracts.GridItemData:
				total_gained += item_var.get_effective_gold_value()
				if player_grid.has_method("remove_from_stash"):
					player_grid.call("remove_from_stash", item_var)
				else:
					stash.erase(item_var)

	for item_var in get_placed_grid_items(player_grid):
		if item_var is Contracts.GridItemData:
			if item_var.category == Contracts.ItemCategory.CARGO or item_var.category == Contracts.ItemCategory.TREASURE:
				total_gained += item_var.get_effective_gold_value()
				remove_from_grid(player_grid, item_var)

	if total_gained > 0:
		add_gold_cb.call(total_gained)
		if player_grid.has_method("compile_stats"):
			player_grid.call("compile_stats")
		if bus != null:
			bus.notification_posted.emit("Beute & Fracht verkauft (+%d Gold)" % total_gained, "trade")
		return true
	return false


func get_placed_grid_items(player_grid: Node) -> Array:
	if player_grid == null:
		return []
	if player_grid.has_method("get_placed_items"):
		return player_grid.call("get_placed_items")
	var raw: Variant = player_grid.get("placed_items")
	return raw.duplicate() if raw is Array else []


func remove_from_grid(player_grid: Node, item: Contracts.GridItemData) -> void:
	if player_grid == null:
		return
	if player_grid.has_method("remove_item"):
		player_grid.call("remove_item", item)
	else:
		var raw: Variant = player_grid.get("placed_items")
		if raw is Array:
			raw.erase(item)

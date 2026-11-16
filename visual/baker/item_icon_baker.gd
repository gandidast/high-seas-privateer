extends RefCounted
## Bakes detailed 24px/cell Dredge-Grid item icons and compact 16x16 deck socket
## module sprites for ship sprite stacks.

const Draw = preload("res://visual/baker/pixel_draw_utils.gd")
const WeaponPainters = preload("res://visual/baker/item_weapon_painters.gd")
const CargoPainters = preload("res://visual/baker/item_cargo_painters.gd")

const GRID_CELL_PX: int = 24
const MODULE_TEX_SIZE: int = 16


static func bake_item_grid_icon(
	item_id: String,
	category: int = 0,
	width_cells: int = 1,
	height_cells: int = 1,
	rarity: int = 0,
	affix: int = 0
) -> ImageTexture:
	var cw: int = maxi(1, width_cells)
	var ch: int = maxi(1, height_cells)
	var w: int = cw * GRID_CELL_PX
	var h: int = ch * GRID_CELL_PX
	var img := Draw.create_canvas(w, h)

	match item_id:
		"swivel_gun_1x2":
			WeaponPainters.icon_swivel_gun(img, w, h, affix)
		"bronze_cannon_2x2":
			WeaponPainters.icon_bronze_cannon(img, w, h, affix)
		"chain_launcher_2x1":
			WeaponPainters.icon_chain_launcher(img, w, h)
		"long_culverin_1x3":
			WeaponPainters.icon_long_culverin(img, w, h)
		"mortar_cannon_2x2":
			WeaponPainters.icon_mortar_cannon(img, w, h)
		"greek_fire_2x1":
			WeaponPainters.icon_greek_fire(img, w, h)
		"harpoon_ballista_2x1":
			WeaponPainters.icon_harpoon_ballista(img, w, h)
		"powder_barrel_1x1":
			WeaponPainters.icon_powder_barrel(img, w, h, false)
		"alchemist_powder_1x1":
			WeaponPainters.icon_powder_barrel(img, w, h, true)
		"storm_sails_2x2":
			CargoPainters.icon_storm_sails(img, w, h)
		"silk_top_sail_1x2":
			CargoPainters.icon_silk_top_sail(img, w, h)
		"crows_nest_1x2":
			CargoPainters.icon_crows_nest(img, w, h)
		"iron_ram_1x2":
			CargoPainters.icon_iron_ram(img, w, h)
		"reinforced_ribs_1x3":
			CargoPainters.icon_reinforced_ribs(img, w, h)
		"copper_plating_2x2":
			CargoPainters.icon_copper_plating(img, w, h)
		"gunner_quarters_2x2":
			CargoPainters.icon_gunner_quarters(img, w, h)
		"carpenter_workshop_2x2":
			CargoPainters.icon_carpenter_workshop(img, w, h)
		"spice_crates_1x2":
			CargoPainters.icon_spice_crates(img, w, h)
		"rum_casks_1x1":
			CargoPainters.icon_rum_cask(img, w, h)
		"royal_treasure_2x2":
			CargoPainters.icon_royal_treasure(img, w, h)
		"salvage_relic_1x2":
			CargoPainters.icon_salvage_relic(img, w, h)
		"kraken_tentacle_trophy_2x2":
			CargoPainters.icon_kraken_trophy(img, w, h)
		_:
			_paint_category_fallback(img, w, h, category, rarity, affix)

	Draw.apply_affix_accents(img, affix)
	Draw.apply_pixel_outline(img, Draw.OUTLINE_COLOR)
	return ImageTexture.create_from_image(img)


static func _paint_category_fallback(
	img: Image,
	w: int,
	h: int,
	category: int,
	rarity: int,
	affix: int
) -> void:
	match category:
		Contracts.ItemCategory.CANNON:
			WeaponPainters.icon_bronze_cannon(img, w, h, affix)
		Contracts.ItemCategory.POWDER_BARREL:
			WeaponPainters.icon_powder_barrel(img, w, h, rarity >= Contracts.ItemRarity.LEGENDARY)
		Contracts.ItemCategory.SAIL:
			CargoPainters.icon_storm_sails(img, w, h)
		Contracts.ItemCategory.HULL:
			CargoPainters.icon_copper_plating(img, w, h)
		Contracts.ItemCategory.TREASURE:
			CargoPainters.icon_royal_treasure(img, w, h)
		Contracts.ItemCategory.CREW_MOD:
			CargoPainters.icon_gunner_quarters(img, w, h)
		Contracts.ItemCategory.BOW_WEAPON:
			CargoPainters.icon_iron_ram(img, w, h)
		_:
			CargoPainters.icon_spice_crates(img, w, h)


static func bake_module_texture(category: int, rarity: int = 0, affix: int = 0) -> ImageTexture:
	var img := Draw.create_canvas(MODULE_TEX_SIZE, MODULE_TEX_SIZE)
	match category:
		Contracts.ItemCategory.CANNON:
			_draw_module_cannon(img, rarity, affix)
		Contracts.ItemCategory.POWDER_BARREL:
			_draw_module_powder_barrel(img)
		Contracts.ItemCategory.SAIL:
			_draw_module_sail(img, rarity)
		Contracts.ItemCategory.HULL, Contracts.ItemCategory.BOW_WEAPON:
			_draw_module_hull_plate(img)
		Contracts.ItemCategory.TREASURE:
			_draw_module_treasure_chest(img)
		Contracts.ItemCategory.CREW_MOD:
			_draw_module_crew_mod(img)
		_:
			_draw_module_cargo_crate(img)

	Draw.apply_affix_accents(img, affix)
	Draw.apply_pixel_outline(img, Draw.OUTLINE_COLOR)
	return ImageTexture.create_from_image(img)


static func _draw_module_cannon(img: Image, rarity: int, affix: int) -> void:
	var metal_dark := Color(0.220, 0.243, 0.294, 1.0)
	var metal_mid := Color(0.369, 0.412, 0.482, 1.0)
	var metal_hi := Color(0.678, 0.725, 0.796, 1.0)
	var brass := Color(0.922, 0.690, 0.220, 1.0)
	var wood := Color(0.561, 0.337, 0.231, 1.0)

	if rarity >= Contracts.ItemRarity.RARE:
		metal_dark = Color(0.510, 0.310, 0.145, 1.0)
		metal_mid = Color(0.769, 0.518, 0.220, 1.0)
		metal_hi = Color(0.973, 0.824, 0.420, 1.0)
	if affix == Contracts.ItemAffix.CURSED:
		brass = Color(0.451, 0.941, 0.788, 1.0)

	Draw.rect(img, 3, 5, 6, 6, wood)
	for wx in [4, 7]:
		img.set_pixel(wx, 4, metal_dark)
		img.set_pixel(wx, 11, metal_dark)

	for x in range(4, 14):
		for y in range(6, 10):
			if x >= 11 and (y == 6 or y == 9):
				continue
			var c: Color = metal_hi if y == 6 else (metal_dark if y == 9 else metal_mid)
			if x == 13 or x == 8:
				c = brass
			img.set_pixel(x, y, c)


static func _draw_module_powder_barrel(img: Image) -> void:
	var wood_dark := Color(0.380, 0.208, 0.137, 1.0)
	var wood_mid := Color(0.561, 0.337, 0.231, 1.0)
	var wood_hi := Color(0.780, 0.518, 0.353, 1.0)
	var iron := Color(0.345, 0.380, 0.443, 1.0)
	var red_band := Color(0.851, 0.220, 0.220, 1.0)

	for y in range(3, 13):
		for x in range(4, 12):
			var dx: float = float(x) - 7.5
			var dy: float = float(y) - 7.5
			if (dx * dx) / 14.0 + (dy * dy) / 22.0 > 1.0:
				continue
			var c: Color = wood_mid
			if y == 5 or y == 10:
				c = iron
			elif (y == 7 or y == 8) and absf(dx) < 2.2:
				c = red_band
			elif x <= 6:
				c = wood_hi
			elif x >= 10:
				c = wood_dark
			img.set_pixel(x, y, c)


static func _draw_module_sail(img: Image, rarity: int) -> void:
	var cloth_lit := Color(0.973, 0.945, 0.875, 1.0)
	var cloth_mid := Color(0.878, 0.824, 0.714, 1.0)
	var stripe := Color(0.227, 0.490, 0.835, 1.0) if rarity >= Contracts.ItemRarity.RARE else Color(0.796, 0.235, 0.220, 1.0)
	Draw.rect(img, 7, 3, 2, 10, Color(0.561, 0.337, 0.231, 1.0))
	for x in range(4, 13):
		for y in range(4, 12):
			if abs(x - 8) + abs(y - 8) <= 5:
				var c: Color = stripe if (y == 7 or y == 8) else (cloth_lit if y < 7 else cloth_mid)
				img.set_pixel(x, y, c)


static func _draw_module_hull_plate(img: Image) -> void:
	var copper_dark := Color(0.522, 0.278, 0.180, 1.0)
	var copper_mid := Color(0.780, 0.451, 0.255, 1.0)
	var copper_hi := Color(0.957, 0.690, 0.420, 1.0)
	var rivet := Color(0.961, 0.922, 0.800, 1.0)

	for y in range(4, 12):
		for x in range(3, 13):
			var c: Color = copper_hi if (y == 4 or x == 3) else (copper_dark if (y == 11 or x == 12 or y == 8) else copper_mid)
			img.set_pixel(x, y, c)
	for rx in [4, 11]:
		for ry in [5, 10]:
			img.set_pixel(rx, ry, rivet)


static func _draw_module_cargo_crate(img: Image) -> void:
	var wood_dark := Color(0.396, 0.220, 0.145, 1.0)
	var wood_mid := Color(0.651, 0.412, 0.271, 1.0)
	var wood_hi := Color(0.851, 0.627, 0.400, 1.0)
	var strap := Color(0.902, 0.722, 0.302, 1.0)

	for y in range(4, 12):
		for x in range(4, 12):
			var c: Color = wood_hi if (y == 4 or x == 4) else (wood_dark if (y == 11 or x == 11) else (strap if x == y else wood_mid))
			img.set_pixel(x, y, c)


static func _draw_module_treasure_chest(img: Image) -> void:
	var wood := Color(0.522, 0.278, 0.165, 1.0)
	var gold := Color(0.957, 0.706, 0.106, 1.0)
	var gold_hi := Color(1.0, 0.925, 0.561, 1.0)
	var gem := Color(0.286, 0.878, 0.878, 1.0)

	for y in range(4, 12):
		for x in range(3, 13):
			var c: Color = wood
			if y == 4 or y == 11 or x == 3 or x == 12:
				c = gold_hi if y <= 5 else gold
			elif y == 7:
				c = gold
			img.set_pixel(x, y, c)
	img.set_pixel(7, 7, gem)
	img.set_pixel(8, 7, gem)


static func _draw_module_crew_mod(img: Image) -> void:
	var brass := Color(0.95, 0.76, 0.24, 1.0)
	var lantern := Color(1.0, 0.92, 0.56, 1.0)
	Draw.rect(img, 4, 4, 8, 8, Color(0.56, 0.34, 0.22, 1.0))
	img.set_pixel(7, 7, brass)
	img.set_pixel(8, 7, lantern)
	img.set_pixel(7, 8, lantern)
	img.set_pixel(8, 8, brass)

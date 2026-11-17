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
	var base_w: int = cw * GRID_CELL_PX
	var base_h: int = ch * GRID_CELL_PX
	var base_img := Draw.create_canvas(base_w, base_h)

	match item_id:
		"swivel_gun_1x2":
			WeaponPainters.icon_swivel_gun(base_img, base_w, base_h, affix)
		"bronze_cannon_2x2":
			WeaponPainters.icon_bronze_cannon(base_img, base_w, base_h, affix)
		"carronade_2x1":
			WeaponPainters.icon_carronade(base_img, base_w, base_h, affix)
		"organ_gun_2x2":
			WeaponPainters.icon_organ_gun(base_img, base_w, base_h)
		"twin_cannon_2x3":
			WeaponPainters.icon_twin_cannon(base_img, base_w, base_h, affix)
		"pitch_mortar_2x2":
			WeaponPainters.icon_pitch_mortar(base_img, base_w, base_h)
		"bow_chaser_1x2":
			WeaponPainters.icon_bow_chaser(base_img, base_w, base_h)
		"chain_launcher_2x1":
			WeaponPainters.icon_chain_launcher(base_img, base_w, base_h)
		"long_culverin_1x3":
			WeaponPainters.icon_long_culverin(base_img, base_w, base_h)
		"mortar_cannon_2x2":
			WeaponPainters.icon_mortar_cannon(base_img, base_w, base_h)
		"greek_fire_2x1":
			WeaponPainters.icon_greek_fire(base_img, base_w, base_h)
		"harpoon_ballista_2x1":
			WeaponPainters.icon_harpoon_ballista(base_img, base_w, base_h)
		"powder_barrel_1x1":
			WeaponPainters.icon_powder_barrel(base_img, base_w, base_h, false)
		"alchemist_powder_1x1":
			WeaponPainters.icon_powder_barrel(base_img, base_w, base_h, true)
		"storm_sails_2x2":
			CargoPainters.icon_storm_sails(base_img, base_w, base_h)
		"silk_top_sail_1x2":
			CargoPainters.icon_silk_top_sail(base_img, base_w, base_h)
		"crows_nest_1x2":
			CargoPainters.icon_crows_nest(base_img, base_w, base_h)
		"iron_ram_1x2":
			CargoPainters.icon_iron_ram(base_img, base_w, base_h)
		"reinforced_ribs_1x3":
			CargoPainters.icon_reinforced_ribs(base_img, base_w, base_h)
		"copper_plating_2x2":
			CargoPainters.icon_copper_plating(base_img, base_w, base_h)
		"gunner_quarters_2x2":
			CargoPainters.icon_gunner_quarters(base_img, base_w, base_h)
		"carpenter_workshop_2x2":
			CargoPainters.icon_carpenter_workshop(base_img, base_w, base_h)
		"spice_crates_1x2":
			CargoPainters.icon_spice_crates(base_img, base_w, base_h)
		"rum_casks_1x1":
			CargoPainters.icon_rum_cask(base_img, base_w, base_h)
		"royal_treasure_2x2":
			CargoPainters.icon_royal_treasure(base_img, base_w, base_h)
		"salvage_relic_1x2":
			CargoPainters.icon_salvage_relic(base_img, base_w, base_h)
		"kraken_tentacle_trophy_2x2":
			CargoPainters.icon_kraken_trophy(base_img, base_w, base_h)
		_:
			_paint_category_fallback(base_img, base_w, base_h, category, rarity, affix)

	Draw.apply_affix_accents(base_img, affix)

	var img: Image = base_img
	if affix == Contracts.ItemAffix.CURSED:
		var has_extra_cell: bool = false
		if category != Contracts.ItemCategory.SAIL:
			var cells: Array[Vector2i] = Contracts.GridItemData.compute_cursed_shape(cw, ch)
			var max_cx: int = cw
			var max_cy: int = ch
			for c in cells:
				max_cx = maxi(max_cx, c.x + 1)
				max_cy = maxi(max_cy, c.y + 1)
			img = Draw.create_canvas(max_cx * GRID_CELL_PX, max_cy * GRID_CELL_PX)
			img.blit_rect(base_img, Rect2i(0, 0, base_w, base_h), Vector2i.ZERO)
			if cells.size() > cw * ch:
				has_extra_cell = true
				_paint_cursed_eldritch_growth(img, cells[cells.size() - 1], cw, ch)
		_paint_cursed_eldritch_overlay(img, item_id, category, base_w, base_h, has_extra_cell)

	var outline_col: Color = Draw.CURSED_OUTLINE if affix == Contracts.ItemAffix.CURSED else Draw.OUTLINE_COLOR
	Draw.apply_pixel_outline(img, outline_col)
	return ImageTexture.create_from_image(img)


static func _paint_cursed_eldritch_growth(img: Image, extra_cell: Vector2i, cw: int, ch: int) -> void:
	var px0: int = extra_cell.x * GRID_CELL_PX
	var py0: int = extra_cell.y * GRID_CELL_PX

	if extra_cell.x >= cw:
		# Thick tentacle emerging from adjacent base cell and curling into a hooked tip
		Draw.draw_cursed_tentacle(
			img,
			Vector2(float(px0 - 4), float(py0 + 13)),
			Vector2(float(px0 + 13), float(py0 + 16)),
			Vector2(float(px0 + 18), float(py0 + 5)),
			4.0, 1.0, 4, Vector2(0.4, 0.9)
		)
		Draw.draw_cursed_tentacle(
			img,
			Vector2(float(px0 - 2), float(py0 + 15)),
			Vector2(float(px0 + 8), float(py0 + 20)),
			Vector2(float(px0 + 17), float(py0 + 19)),
			2.6, 0.85, 4, Vector2(0.0, -1.0)
		)
		Draw.circle_inner(img, float(px0 + 9), float(py0 + 11), 5.2, Draw.CURSED_TENTACLE_DARK)
		Draw.circle_inner(img, float(px0 + 8.5), float(py0 + 10.5), 4.0, Draw.CURSED_TENTACLE_MID)
		Draw.draw_eldritch_eye(img, px0 + 9, py0 + 11, true)
		Draw.draw_eldritch_eye(img, px0 + 15, py0 + 15, false)
		Draw.draw_abyssal_barnacle(img, px0 + 4, py0 + 7)
		Draw.draw_cursed_kelp_strand(img, px0 + 12, py0 + 5, 4, 1)
		Draw.draw_cursed_slime_drip(img, px0 + 6, py0 + 16, 5, true)
		Draw.draw_cursed_slime_drip(img, px0 + 13, py0 + 18, 4, false)
	else:
		Draw.draw_cursed_tentacle(
			img,
			Vector2(float(px0 + 12), float(py0 - 4)),
			Vector2(float(px0 + 16), float(py0 + 13)),
			Vector2(float(px0 + 19), float(py0 + 15)),
			4.0, 1.0, 4, Vector2(-0.8, 0.4)
		)
		Draw.draw_cursed_tentacle(
			img,
			Vector2(float(px0 + 9), float(py0 - 2)),
			Vector2(float(px0 + 5), float(py0 + 12)),
			Vector2(float(px0 + 4), float(py0 + 18)),
			2.6, 0.85, 4, Vector2(1.0, 0.0)
		)
		Draw.circle_inner(img, float(px0 + 11), float(py0 + 10), 5.2, Draw.CURSED_TENTACLE_DARK)
		Draw.circle_inner(img, float(px0 + 10.5), float(py0 + 9.5), 4.0, Draw.CURSED_TENTACLE_MID)
		Draw.draw_eldritch_eye(img, px0 + 11, py0 + 10, true)
		Draw.draw_abyssal_barnacle(img, px0 + 16, py0 + 6)
		Draw.draw_cursed_kelp_strand(img, px0 + 6, py0 + 4, 4, -1)
		Draw.draw_cursed_slime_drip(img, px0 + 9, py0 + 16, 4, true)
		Draw.draw_cursed_slime_drip(img, px0 + 15, py0 + 15, 4, false)


static func _paint_cursed_eldritch_overlay(
	img: Image,
	item_id: String,
	category: int,
	base_w: int,
	base_h: int,
	has_extra_cell: bool
) -> void:
	## Wraps base item silhouettes with tentacles, suction cups, slime drips, kelp & eldritch eyes.
	var min_x: int = base_w
	var min_y: int = base_h
	var max_x: int = -1
	var max_y: int = -1
	var top_y: PackedInt32Array = PackedInt32Array()
	var bot_y: PackedInt32Array = PackedInt32Array()
	top_y.resize(base_w)
	bot_y.resize(base_w)
	for x in range(base_w):
		top_y[x] = -1
		bot_y[x] = -1
		for y in range(base_h):
			if img.get_pixel(x, y).a > 0.5:
				if top_y[x] < 0:
					top_y[x] = y
				bot_y[x] = y
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)

	if max_x < min_x or max_y < min_y:
		min_x = 3
		min_y = 3
		max_x = base_w - 4
		max_y = base_h - 4

	var span_w: int = maxi(4, max_x - min_x)
	var span_h: int = maxi(4, max_y - min_y)
	var is_sail: bool = (category == Contracts.ItemCategory.SAIL)

	# 1. Kelp & sea-algae tendrils hanging from upper silhouette rim
	var kelp_fractions := PackedFloat32Array([0.28, 0.72]) if base_w <= 24 else PackedFloat32Array([0.22, 0.52, 0.80])
	for idx in range(kelp_fractions.size()):
		var kx: int = clampi(min_x + int(round(float(span_w) * kelp_fractions[idx])), 2, base_w - 3)
		var ky: int = top_y[kx]
		if ky >= 0:
			Draw.draw_cursed_kelp_strand(img, kx, ky, 4 if base_h <= 24 else 5, 1 if idx % 2 == 0 else -1)

	# 2. Writhing tentacles with suction cups gripping corners/edges
	var r0_small: float = 1.9 if (base_w <= 24 and base_h <= 24) else 2.5
	# Lower-left gripping tentacle
	Draw.draw_cursed_tentacle(
		img,
		Vector2(float(maxi(2, min_x)), float(mini(base_h - 3, max_y))),
		Vector2(float(maxi(2, min_x + 1)), float(maxi(3, max_y - span_h / 3))),
		Vector2(float(mini(base_w - 4, min_x + maxi(6, span_w / 3))), float(maxi(3, max_y - 4))),
		r0_small, 0.80, 4, Vector2(0.4, 0.9)
	)
	# Upper-right gripping tentacle (for sails and multi-cell items)
	if is_sail or base_w >= 40 or base_h >= 40:
		Draw.draw_cursed_tentacle(
			img,
			Vector2(float(mini(base_w - 3, max_x)), float(maxi(3, min_y + 3))),
			Vector2(float(mini(base_w - 3, max_x - 2)), float(mini(base_h - 4, min_y + 10))),
			Vector2(float(maxi(3, max_x - maxi(7, span_w / 3))), float(mini(base_h - 4, min_y + 7))),
			r0_small, 0.78, 4, Vector2(-0.5, 0.85)
		)

	# 3. Slimy bioluminescent green goo drips from bottom edge
	var drip_fractions := PackedFloat32Array([0.34, 0.68]) if base_w <= 24 else PackedFloat32Array([0.20, 0.48, 0.78])
	for idx in range(drip_fractions.size()):
		var dx: int = clampi(min_x + int(round(float(span_w) * drip_fractions[idx])), 2, base_w - 3)
		var dy: int = bot_y[dx]
		if dy >= 0:
			var drip_len: int = 3 + ((idx + dx) % 3)
			Draw.draw_cursed_slime_drip(img, dx, maxi(2, dy - 1), drip_len, base_w >= 36)

	# 4. Abyssal barnacles clinging to rim
	var bx: int = clampi(min_x + span_w / 4, 3, base_w - 4)
	if top_y[bx] >= 0:
		Draw.draw_abyssal_barnacle(img, bx, clampi(top_y[bx] + 3, 3, base_h - 4))
	if base_w >= 36 or base_h >= 36:
		var bx2: int = clampi(max_x - span_w / 5, 3, base_w - 4)
		if bot_y[bx2] >= 0:
			Draw.draw_abyssal_barnacle(img, bx2, clampi(bot_y[bx2] - 3, 3, base_h - 4))

	# 5. Eldritch eyes on cursed sails (which stay rectangular) & items without L-cell
	if is_sail:
		var ecx: int = base_w / 2
		if item_id == "storm_sails_2x2":
			Draw.draw_eldritch_eye(img, ecx, 33, true)
			Draw.draw_abyssal_barnacle(img, ecx - 9, 17)
			Draw.draw_abyssal_barnacle(img, ecx + 9, 17)
		elif item_id == "crows_nest_1x2":
			Draw.draw_eldritch_eye(img, ecx, 19, false)
		else:
			Draw.draw_eldritch_eye(img, ecx, base_h / 2, false)
	elif not has_extra_cell:
		Draw.draw_eldritch_eye(img, base_w / 2, base_h / 2, base_w >= 48 and base_h >= 48)


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
		Contracts.ItemCategory.HULL:
			_draw_module_hull_plate(img)
		Contracts.ItemCategory.BOW_WEAPON:
			_draw_module_bow_weapon(img, affix)
		Contracts.ItemCategory.TREASURE:
			_draw_module_treasure_chest(img)
		Contracts.ItemCategory.CREW_MOD:
			_draw_module_crew_mod(img)
		_:
			_draw_module_cargo_crate(img)

	Draw.apply_affix_accents(img, affix)
	if affix == Contracts.ItemAffix.CURSED:
		_paint_cursed_module_overlay(img, category)
	var outline_col: Color = Draw.CURSED_OUTLINE if affix == Contracts.ItemAffix.CURSED else Draw.OUTLINE_COLOR
	Draw.apply_pixel_outline(img, outline_col)
	return ImageTexture.create_from_image(img)


static func _paint_cursed_module_overlay(img: Image, category: int) -> void:
	## Adds crisp 16x16 eldritch tentacles, slime drips, kelp & abyssal eyes to deck modules.
	Draw.draw_cursed_kelp_strand(img, 5, 3, 3, 1)
	Draw.draw_cursed_slime_drip(img, 5, 11, 3, false)
	Draw.draw_cursed_slime_drip(img, 10, 11, 2, false)
	Draw.draw_cursed_tentacle(
		img,
		Vector2(3.0, 12.0),
		Vector2(2.0, 7.0),
		Vector2(6.0, 5.0),
		1.45, 0.70, 3, Vector2(1.0, 0.2)
	)
	match category:
		Contracts.ItemCategory.SAIL:
			Draw.draw_eldritch_eye(img, 8, 7, false)
		Contracts.ItemCategory.CANNON, Contracts.ItemCategory.BOW_WEAPON:
			Draw.px_inner(img, 13, 7, Draw.CURSED_SLIME_GLOW)
			Draw.px_inner(img, 13, 8, Draw.CURSED_SLIME_CORE)
			Draw.draw_abyssal_barnacle(img, 9, 5)
		Contracts.ItemCategory.POWDER_BARREL:
			Draw.px_inner(img, 8, 6, Draw.CURSED_SLIME_GLOW)
			Draw.px_inner(img, 8, 7, Draw.CURSED_SLIME_CORE)
			Draw.draw_abyssal_barnacle(img, 10, 8)
		Contracts.ItemCategory.HULL:
			Draw.draw_abyssal_barnacle(img, 10, 6)
			Draw.draw_eldritch_eye(img, 8, 8, false)
		_:
			Draw.draw_eldritch_eye(img, 8, 7, false)


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


static func _draw_module_bow_weapon(img: Image, affix: int) -> void:
	var brass_d := Color(0.510, 0.310, 0.145, 1.0)
	var brass_m := Color(0.840, 0.590, 0.220, 1.0)
	var brass_h := Color(0.451, 0.941, 0.788, 1.0) if affix == Contracts.ItemAffix.CURSED else Color(0.990, 0.870, 0.440, 1.0)
	Draw.rect(img, 2, 5, 5, 6, Draw.WOOD_MID)
	for x in range(3, 15):
		for y in range(6, 10):
			if x >= 11 and (y == 6 or y == 9):
				continue
			var c: Color = brass_h if y == 6 else (brass_d if y == 9 else brass_m)
			if x == 8 or x == 14:
				c = brass_h if y < 8 else brass_d
			img.set_pixel(x, y, c)

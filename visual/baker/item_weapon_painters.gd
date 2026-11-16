extends RefCounted
## Detailed 2D pixel-art icon painters (24px/cell) for cannons, bow weapons,
## and gunpowder barrels.

const Draw = preload("res://visual/baker/pixel_draw_utils.gd")


static func icon_swivel_gun(img: Image, w: int, h: int, _affix: int) -> void:
	var cx: int = w / 2
	var iron_d := Color(0.24, 0.26, 0.32)
	var iron_m := Color(0.42, 0.46, 0.54)
	var iron_h := Color(0.75, 0.80, 0.88)

	Draw.rect(img, cx - 6, h - 10, 12, 6, Draw.WOOD_DARK)
	Draw.rect(img, cx - 5, h - 10, 10, 4, Draw.WOOD_MID)
	Draw.rect(img, cx - 3, h - 18, 6, 9, Draw.WOOD_DARK)
	Draw.rect(img, cx - 2, h - 18, 4, 8, Draw.WOOD_LIGHT)
	Draw.rect(img, cx - 5, h - 22, 10, 4, Draw.BRASS)
	Draw.rect(img, cx - 5, h - 27, 2, 6, iron_m)
	Draw.rect(img, cx + 3, h - 27, 2, 6, iron_m)

	Draw.draw_upright_gun_barrel(
		img, cx, 6, h - 16, 14, 8, [9, 18, h - 17],
		iron_d, iron_m, iron_h, Draw.BRASS
	)
	Draw.line(img, Vector2i(cx, h - 16), Vector2i(cx + 4, h - 12), Draw.BRASS, 2)


static func icon_bronze_cannon(img: Image, w: int, h: int, affix: int) -> void:
	var cy: int = h / 2 + 2
	var bronze_d := Color(0.49, 0.30, 0.14)
	var bronze_m := Color(0.79, 0.54, 0.22)
	var bronze_h := Color(0.45, 0.94, 0.80) if affix == Contracts.ItemAffix.CURSED else Color(0.98, 0.85, 0.44)
	var iron := Color(0.26, 0.28, 0.34)

	Draw.rect(img, 8, cy + 2, w - 20, 8, Draw.WOOD_DARK)
	Draw.rect(img, 9, cy + 2, w - 22, 5, Draw.WOOD_MID)
	Draw.rect(img, 12, cy - 2, w - 26, 4, Draw.WOOD_LIGHT)

	for x in range(8, w - 5):
		var t: float = float(x - 8) / float(maxi(1, w - 13))
		var r: int = 6 if (t < 0.35 or t >= 0.82) else 5
		for y in range(cy - 5 - r, cy - 4 + r):
			var c: Color = bronze_m
			if y <= cy - 5 - r + 2:
				c = bronze_h
			elif y >= cy - 4 + r - 2:
				c = bronze_d
			if x == 16 or x == 26 or x >= w - 7:
				c = bronze_h if y < cy - 3 else bronze_d
			Draw.px(img, x, y, c)

	Draw.circle(img, 6.0, float(cy - 5), 2.5, bronze_m)
	Draw.px(img, 5, cy - 6, bronze_h)
	Draw.rect(img, w - 5, cy - 7, 2, 5, Draw.OUTLINE_COLOR)

	for wx in [14, w - 16]:
		Draw.circle(img, float(wx), float(cy + 10), 5.5, iron)
		Draw.circle(img, float(wx), float(cy + 10), 4.0, Draw.WOOD_MID)
		Draw.circle(img, float(wx), float(cy + 10), 1.5, bronze_h)


static func icon_chain_launcher(img: Image, w: int, h: int) -> void:
	var cy: int = h / 2
	var iron_d := Color(0.20, 0.24, 0.30)
	var iron_m := Color(0.42, 0.48, 0.56)
	var iron_h := Color(0.78, 0.84, 0.92)
	var steel := Color(0.58, 0.68, 0.80)

	Draw.rect(img, 4, cy - 6, 16, 12, Color(0.50, 0.30, 0.20))
	Draw.rect(img, 6, cy - 5, 14, 4, iron_m)
	Draw.rect(img, 6, cy + 1, 14, 4, iron_d)
	Draw.rect(img, 7, cy - 4, 12, 1, iron_h)

	for lx in range(21, w - 10, 3):
		Draw.rect(img, lx, cy - 1, 3, 2, steel)
		Draw.px(img, lx + 1, cy - 2, iron_h)

	Draw.circle(img, 21.0, float(cy - 4), 4.2, iron_d)
	Draw.circle(img, 20.5, float(cy - 4.5), 3.0, iron_m)
	Draw.px(img, 19, cy - 6, iron_h)

	Draw.circle(img, float(w - 9), float(cy + 3), 4.5, iron_d)
	Draw.circle(img, float(w - 9.5), float(cy + 2.5), 3.2, iron_m)
	Draw.px(img, w - 11, cy + 1, iron_h)


static func icon_long_culverin(img: Image, w: int, h: int) -> void:
	var cx: int = w / 2
	var iron_d := Color(0.18, 0.20, 0.25)
	var iron_m := Color(0.35, 0.39, 0.46)
	var iron_h := Color(0.72, 0.77, 0.85)
	var brass := Color(0.92, 0.74, 0.28)

	Draw.rect(img, cx - 5, h - 22, 10, 16, Draw.WOOD_DARK)
	Draw.rect(img, cx - 4, h - 21, 8, 14, Draw.WOOD_MID)
	Draw.rect(img, cx - 8, h - 20, 3, 10, iron_d)
	Draw.rect(img, cx + 5, h - 20, 3, 10, iron_d)
	Draw.rect(img, cx - 7, h - 18, 1, 6, brass)
	Draw.rect(img, cx + 6, h - 18, 1, 6, brass)

	Draw.draw_upright_gun_barrel(
		img, cx, 4, h - 14, 34, 7, [8, 24, 42, h - 15],
		iron_d, iron_m, iron_h, brass
	)
	Draw.circle(img, float(cx), float(h - 12), 2.5, brass)


static func icon_mortar_cannon(img: Image, w: int, h: int) -> void:
	var iron_d := Color(0.22, 0.18, 0.22)
	var iron_m := Color(0.39, 0.34, 0.40)
	var iron_h := Color(0.70, 0.68, 0.74)
	var brass := Color(0.98, 0.68, 0.22)

	Draw.rect(img, 7, h - 15, w - 14, 9, Draw.WOOD_DARK)
	Draw.rect(img, 8, h - 14, w - 16, 6, Draw.WOOD_MID)
	Draw.rect(img, 9, h - 14, w - 18, 2, Draw.WOOD_LIGHT)

	var p0 := Vector2(16.0, float(h - 15))
	var p1 := Vector2(float(w - 11), 12.0)
	for i in range(28):
		var t: float = float(i) / 27.0
		var center: Vector2 = p0.lerp(p1, t)
		var rad: float = 8.5 if t < 0.75 else 9.5
		Draw.circle(img, center.x, center.y, rad, iron_m)
		Draw.circle(img, center.x - 2.0, center.y - 2.0, rad * 0.55, iron_h)
		Draw.circle(img, center.x + 2.0, center.y + 2.0, rad * 0.55, iron_d)

	Draw.circle(img, p1.x, p1.y, 9.2, brass)
	Draw.circle(img, p1.x + 1.0, p1.y - 1.0, 5.5, Draw.OUTLINE_COLOR)
	Draw.rect(img, 10, h - 19, 3, 3, Color(1.0, 0.52, 0.14))
	Draw.px(img, 11, h - 18, Color(1.0, 0.94, 0.56))


static func icon_greek_fire(img: Image, _w: int, h: int) -> void:
	var cy: int = h / 2
	var copper_d := Color(0.50, 0.25, 0.16)
	var copper_m := Color(0.78, 0.44, 0.22)
	var brass := Color(0.95, 0.76, 0.26)
	var brass_hi := Color(1.0, 0.94, 0.60)
	var flame_r := Color(0.94, 0.26, 0.14)
	var flame_o := Color(1.0, 0.58, 0.16)
	var flame_y := Color(1.0, 0.92, 0.45)

	Draw.circle(img, 10.0, float(cy), 6.5, copper_d)
	Draw.circle(img, 9.5, float(cy - 0.5), 5.0, copper_m)
	Draw.rect(img, 8, cy - 7, 4, 14, brass)
	Draw.rect(img, 14, cy - 3, 14, 6, brass)
	Draw.rect(img, 14, cy - 3, 14, 2, brass_hi)

	Draw.rect(img, 24, cy - 5, 8, 4, brass)
	Draw.rect(img, 25, cy - 5, 6, 2, brass_hi)
	Draw.rect(img, 25, cy + 2, 6, 3, copper_m)
	Draw.px(img, 27, cy - 4, Color(0.96, 0.24, 0.20))
	Draw.px(img, 30, cy - 2, Color.WHITE)
	Draw.px(img, 30, cy + 1, Color.WHITE)

	Draw.circle(img, 36.0, float(cy), 5.0, flame_r)
	Draw.circle(img, 40.0, float(cy - 1), 4.0, flame_o)
	Draw.circle(img, 36.0, float(cy), 3.0, flame_o)
	Draw.circle(img, 35.0, float(cy), 1.8, flame_y)
	Draw.px(img, 44, cy - 3, flame_o)
	Draw.px(img, 45, cy, flame_y)
	Draw.px(img, 43, cy + 3, flame_r)


static func icon_harpoon_ballista(img: Image, w: int, h: int) -> void:
	var cy: int = h / 2
	var steel_d := Color(0.32, 0.38, 0.46)
	var steel_h := Color(0.84, 0.90, 0.96)
	var rope := Color(0.85, 0.76, 0.54)

	Draw.rect(img, 6, cy - 2, 26, 4, Draw.WOOD_MID)
	Draw.rect(img, 6, cy - 2, 26, 1, Draw.WOOD_LIGHT)
	Draw.rect(img, 5, cy - 4, 4, 8, Draw.WOOD_DARK)

	Draw.line(img, Vector2i(26, cy), Vector2i(22, 4), Draw.WOOD_DARK, 3)
	Draw.line(img, Vector2i(26, cy), Vector2i(22, h - 5), Draw.WOOD_DARK, 3)
	Draw.line(img, Vector2i(25, cy), Vector2i(22, 5), Draw.WOOD_LIGHT, 1)
	Draw.line(img, Vector2i(25, cy), Vector2i(22, h - 6), Draw.WOOD_LIGHT, 1)

	Draw.line(img, Vector2i(21, 5), Vector2i(13, cy), rope, 1)
	Draw.line(img, Vector2i(21, h - 6), Vector2i(13, cy), rope, 1)

	Draw.circle(img, 13.0, float(cy + 6), 3.0, rope)
	Draw.px(img, 13, cy + 6, Draw.WOOD_DARK)

	Draw.line(img, Vector2i(13, cy), Vector2i(w - 5, cy), steel_d, 2)
	Draw.line(img, Vector2i(13, cy - 1), Vector2i(w - 6, cy - 1), steel_h, 1)
	Draw.line(img, Vector2i(w - 4, cy), Vector2i(w - 11, cy - 4), steel_h, 2)
	Draw.line(img, Vector2i(w - 4, cy), Vector2i(w - 11, cy + 4), steel_d, 2)


static func icon_powder_barrel(img: Image, w: int, h: int, is_alchemist: bool) -> void:
	var cx: float = float(w) * 0.5 - 0.5
	var cy: float = float(h) * 0.5 + 1.0
	var band := Color(0.30, 0.92, 0.72) if is_alchemist else Color(0.86, 0.22, 0.22)
	var hoop := Color(0.95, 0.76, 0.24) if is_alchemist else Color(0.32, 0.36, 0.42)

	Draw.draw_vertical_barrel(
		img, w, h, cx, cy, 6.5, 7.5, 5, 3, 5,
		[8, h - 6], hoop, 10, 13, band,
		Draw.WOOD_DARK, Draw.WOOD_MID, Draw.WOOD_LIGHT
	)
	Draw.px(img, int(cx), 11, Color.WHITE)
	Draw.px(img, int(cx) + 1, 11, Color.WHITE)
	Draw.px(img, int(cx), 12, Color.WHITE)

	if is_alchemist:
		Draw.rect(img, int(cx) - 2, 2, 5, 4, Color(0.45, 0.98, 0.85))
		Draw.px(img, int(cx), 1, Color.WHITE)
	else:
		Draw.line(img, Vector2i(int(cx), 5), Vector2i(int(cx) + 3, 2), Color(0.82, 0.72, 0.50), 1)
		Draw.px(img, int(cx) + 3, 2, Color(1.0, 0.65, 0.16))
		Draw.px(img, int(cx) + 4, 1, Color(1.0, 0.96, 0.60))


static func icon_carronade(img: Image, w: int, h: int, affix: int) -> void:
	## Stubby wide-mouthed brass/iron shotgun carronade (48x24).
	var cy: int = h / 2
	var iron_d := Color(0.20, 0.23, 0.28)
	var iron_m := Color(0.38, 0.43, 0.50)
	var iron_h := Color(0.76, 0.82, 0.90)
	var brass_m := Color(0.86, 0.62, 0.20)
	var brass_h := Color(0.45, 0.94, 0.80) if affix == Contracts.ItemAffix.CURSED else Color(0.99, 0.86, 0.44)

	# Heavy timber slide carriage
	Draw.rect(img, 6, cy + 3, w - 18, 6, Draw.WOOD_DARK)
	Draw.rect(img, 7, cy + 3, w - 20, 3, Draw.WOOD_MID)
	Draw.rect(img, 9, cy + 2, w - 24, 2, Draw.WOOD_LIGHT)

	# Short thick barrel flaring dramatically at muzzle (right)
	for x in range(11, w - 8):
		var t: float = float(x - 11) / float(maxi(1, w - 19))
		var r: int = 5
		if t < 0.25:
			r = 5
		elif t < 0.72:
			r = 4
		else:
			r = 6 if t < 0.88 else 7
		for y in range(cy - r, cy + r):
			var c: Color = iron_m
			if y <= cy - r + 1:
				c = iron_h
			elif y >= cy + r - 2:
				c = iron_d
			if x == 16 or x == 25 or x >= w - 11:
				c = brass_h if y < cy else brass_m
			Draw.px(img, x, y, c)

	# Breech cascabel loop & dark wide blunderbuss muzzle bore
	Draw.circle(img, 8.5, float(cy - 1), 2.5, brass_m)
	Draw.px(img, 8, cy - 2, brass_h)
	Draw.rect(img, w - 8, cy - 4, 2, 8, Draw.OUTLINE_COLOR)
	Draw.px(img, w - 5, cy - 2, Color(0.98, 0.78, 0.34))
	Draw.px(img, w - 4, cy + 1, Color(0.98, 0.78, 0.34))

	# Small iron slide trucks
	for wx in [13, w - 18]:
		Draw.circle(img, float(wx), float(cy + 8), 3.2, iron_d)
		Draw.circle(img, float(wx), float(cy + 8), 1.5, brass_m)


static func icon_organ_gun(img: Image, w: int, h: int) -> void:
	## Multi-barrel 3-pipe organ volley cannon on wooden carriage (48x48).
	var iron_d := Color(0.20, 0.22, 0.28)
	var iron_m := Color(0.40, 0.45, 0.54)
	var iron_h := Color(0.78, 0.84, 0.92)
	var brass_h := Color(0.98, 0.84, 0.40)

	# Wooden carriage frame & trail
	Draw.line(img, Vector2i(7, h - 10), Vector2i(26, h - 14), Draw.WOOD_DARK, 5)
	Draw.line(img, Vector2i(8, h - 11), Vector2i(25, h - 15), Draw.WOOD_MID, 3)
	Draw.rect(img, 14, 18, 12, 16, Draw.WOOD_DARK)
	Draw.rect(img, 15, 19, 10, 14, Draw.WOOD_MID)

	# Three fanned organ barrels pointing up-right
	var pipes: Array = [
		[Vector2i(12, 21), Vector2i(35, 8)],
		[Vector2i(14, 26), Vector2i(39, 17)],
		[Vector2i(16, 31), Vector2i(41, 26)]
	]
	for pair in pipes:
		var p0: Vector2i = pair[0]
		var p1: Vector2i = pair[1]
		Draw.line(img, p0 + Vector2i(0, 1), p1 + Vector2i(0, 1), iron_d, 4)
		Draw.line(img, p0, p1, iron_m, 3)
		Draw.line(img, p0 + Vector2i(0, -1), p1 + Vector2i(0, -1), iron_h, 1)
		Draw.rect(img, p1.x - 1, p1.y - 2, 3, 4, Draw.BRASS)
		Draw.px(img, p1.x + 1, p1.y, Draw.OUTLINE_COLOR)

	# Brass binding strap across middle of the 3 pipes + priming bar
	Draw.line(img, Vector2i(21, 14), Vector2i(25, 29), Draw.BRASS, 2)
	Draw.line(img, Vector2i(11, 20), Vector2i(16, 32), brass_h, 2)

	# Spoked wooden carriage wheel
	Draw.circle(img, 20.0, float(h - 12), 7.5, iron_d)
	Draw.circle(img, 20.0, float(h - 12), 5.8, Draw.WOOD_MID)
	Draw.circle(img, 20.0, float(h - 12), 2.2, Draw.BRASS)
	Draw.px(img, 19, h - 13, brass_h)


static func icon_twin_cannon(img: Image, w: int, h: int, affix: int) -> void:
	## Massive heavy double-barreled late-game cannon pair with gilded trim (48x72).
	var iron_d := Color(0.16, 0.18, 0.24)
	var iron_m := Color(0.32, 0.36, 0.44)
	var iron_h := Color(0.68, 0.74, 0.84)
	var gold_d := Color(0.56, 0.36, 0.12)
	var gold_m := Color(0.92, 0.70, 0.22)
	var gold_h := Color(0.45, 0.94, 0.80) if affix == Contracts.ItemAffix.CURSED else Color(1.0, 0.92, 0.52)

	# Heavy 4-wheel naval double carriage
	for wy in [h - 24, h - 11]:
		Draw.rect(img, 4, wy - 3, 4, 7, iron_d)
		Draw.rect(img, w - 8, wy - 3, 4, 7, iron_d)
		Draw.px(img, 5, wy, gold_m)
		Draw.px(img, w - 6, wy, gold_m)
	Draw.rect(img, 7, h - 29, w - 14, 22, Draw.WOOD_DARK)
	Draw.rect(img, 9, h - 28, w - 18, 19, Draw.WOOD_MID)
	Draw.rect(img, 10, h - 27, w - 20, 3, Draw.WOOD_LIGHT)
	Draw.rect(img, 8, h - 29, w - 16, 2, gold_m)
	Draw.rect(img, 8, h - 9, w - 16, 2, gold_d)

	# Twin heavy upright gun barrels
	for cx in [16, 31]:
		for y in range(6, h - 13):
			var half_w: int = 4 if y < 22 else 5
			if y <= 11:
				half_w = 5
			var is_band: bool = (y in [8, 9, 24, 25, 42, 43, h - 15])
			for x in range(cx - half_w, cx + half_w + 1):
				var c: Color = iron_m
				if x <= cx - half_w + 1:
					c = iron_h
				elif x >= cx + half_w - 1:
					c = iron_d
				if is_band:
					c = gold_h if x <= cx else (gold_d if x >= cx + half_w - 1 else gold_m)
				Draw.px(img, x, y, c)
		# Cascabel knob & dark bore crown
		Draw.circle(img, float(cx), float(h - 10), 2.5, gold_m)
		Draw.px(img, cx - 1, h - 11, gold_h)
		Draw.rect(img, cx - 2, 5, 5, 2, Draw.OUTLINE_COLOR)

	# Gilded cross-yoke linking the twin barrels
	Draw.rect(img, 14, 25, 20, 4, gold_m)
	Draw.rect(img, 14, 25, 20, 1, gold_h)
	Draw.rect(img, 13, 44, 22, 4, gold_m)
	Draw.rect(img, 13, 44, 22, 1, gold_h)


static func icon_pitch_mortar(img: Image, w: int, h: int) -> void:
	## Thick dark cauldron mortar with glowing orange-tar pitch rim (48x48).
	var iron_d := Color(0.15, 0.14, 0.19)
	var iron_m := Color(0.28, 0.27, 0.34)
	var iron_h := Color(0.56, 0.56, 0.64)
	var tar_d := Color(0.84, 0.26, 0.08)
	var tar_m := Color(1.0, 0.54, 0.12)
	var tar_h := Color(1.0, 0.90, 0.38)

	# Heavy timber mortar bed
	Draw.rect(img, 6, h - 14, w - 12, 8, Draw.WOOD_DARK)
	Draw.rect(img, 7, h - 13, w - 14, 5, Draw.WOOD_MID)
	Draw.rect(img, 8, h - 13, w - 16, 2, Draw.WOOD_LIGHT)
	Draw.rect(img, 8, h - 12, 3, 5, iron_m)
	Draw.rect(img, w - 11, h - 12, 3, 5, iron_m)

	# Thick squat cauldron bowl
	var cx: float = float(w) * 0.5
	var cy: float = 25.5
	for y in range(12, h - 11):
		for x in range(8, w - 8):
			var dx: float = (float(x) - cx) / 14.5
			var dy: float = (float(y) - cy) / 12.5
			if dx * dx + dy * dy <= 1.0:
				var c: Color = iron_m
				if float(x) < cx - 5.0 and y < 28:
					c = iron_h
				elif float(x) > cx + 5.0 or y > 31:
					c = iron_d
				if y == 25 or y == 26:
					c = iron_d if (x % 4 != 0) else iron_h
				Draw.px(img, x, y, c)

	# Wide flared cauldron rim + glowing orange-tar pitch crust
	Draw.rect(img, 9, 10, w - 18, 6, iron_d)
	Draw.rect(img, 10, 11, w - 20, 4, iron_m)
	Draw.rect(img, 12, 11, w - 24, 3, tar_d)
	Draw.rect(img, 14, 11, w - 28, 2, tar_m)
	Draw.rect(img, 17, 11, w - 34, 1, tar_h)
	Draw.rect(img, 14, 9, w - 28, 2, Draw.OUTLINE_COLOR)

	# Molten pitch drips running down the cauldron front
	Draw.rect(img, 17, 14, 3, 6, tar_m)
	Draw.px(img, 18, 20, tar_d)
	Draw.px(img, 18, 15, tar_h)
	Draw.rect(img, 27, 14, 2, 5, tar_m)
	Draw.px(img, 28, 19, tar_d)


static func icon_bow_chaser(img: Image, w: int, h: int) -> void:
	## Sleek forward-pointing long brass chase gun (24x48).
	var cx: int = w / 2
	var brass_d := Color(0.52, 0.32, 0.14)
	var brass_m := Color(0.86, 0.62, 0.22)
	var brass_h := Color(1.0, 0.90, 0.46)
	var iron_d := Color(0.22, 0.24, 0.30)

	# Narrow bow swivel rail mount
	Draw.rect(img, cx - 6, h - 13, 12, 8, Draw.WOOD_DARK)
	Draw.rect(img, cx - 5, h - 12, 10, 6, Draw.WOOD_MID)
	Draw.rect(img, cx - 7, h - 10, 2, 4, iron_d)
	Draw.rect(img, cx + 5, h - 10, 2, 4, iron_d)
	Draw.rect(img, cx - 4, h - 15, 8, 3, brass_d)

	# Long slender upright brass chase barrel
	Draw.draw_upright_gun_barrel(
		img, cx, 4, h - 12, 18, 7, [8, 19, 30, h - 13],
		brass_d, brass_m, brass_h, brass_h
	)
	Draw.circle(img, float(cx), float(h - 9), 2.2, brass_m)
	Draw.px(img, cx - 1, h - 10, brass_h)
	Draw.rect(img, cx - 1, 3, 3, 2, Draw.OUTLINE_COLOR)

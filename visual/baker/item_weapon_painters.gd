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

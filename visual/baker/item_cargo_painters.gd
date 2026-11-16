extends RefCounted
## Detailed 2D pixel-art icon painters (24px/cell) for sails, hull armor,
## crew modules, trade cargo, and treasures/trophies.

const Draw = preload("res://visual/baker/pixel_draw_utils.gd")


static func icon_storm_sails(img: Image, w: int, h: int) -> void:
	var cx: int = w / 2
	var mast := Color(0.56, 0.34, 0.22)
	var mast_hi := Color(0.84, 0.60, 0.38)
	var cloth_h := Color(0.97, 0.94, 0.86)
	var cloth_m := Color(0.86, 0.80, 0.69)
	var stripe := Color(0.78, 0.22, 0.20)

	Draw.rect(img, cx - 2, 4, 4, h - 8, mast)
	Draw.rect(img, cx - 2, 4, 1, h - 8, mast_hi)
	Draw.rect(img, 7, 10, w - 14, 3, mast)
	Draw.rect(img, 5, 26, w - 10, 3, mast)

	_draw_billowing_sail(img, cx, 11, 24, 13, 12.0, 17, 15, 17, cloth_h, cloth_m, stripe)
	_draw_billowing_sail(img, cx, 27, h - 6, 16, 14.0, 34, 32, 34, cloth_h, cloth_m, stripe)
	Draw.px(img, cx, 5, Draw.BRASS)


static func _draw_billowing_sail(
	img: Image,
	cx: int,
	y_start: int,
	y_end: int,
	base_hw: int,
	span_f: float,
	lit_cut: int,
	stripe_min: int,
	stripe_max: int,
	cloth_h: Color,
	cloth_m: Color,
	stripe: Color
) -> void:
	for y in range(y_start, y_end):
		var half_w: int = base_hw + int(sin((float(y - y_start) / span_f) * PI) * 3.0)
		for x in range(cx - half_w, cx + half_w):
			var c: Color = cloth_h if y < lit_cut else cloth_m
			if y >= stripe_min and y <= stripe_max:
				c = stripe
			Draw.px(img, x, y, c)


static func icon_silk_top_sail(img: Image, w: int, h: int) -> void:
	var cx: int = w / 2
	var mast := Color(0.62, 0.40, 0.25)
	var silk_h := Color(0.98, 0.96, 0.90)
	var silk_m := Color(0.89, 0.86, 0.78)
	var azure := Color(0.22, 0.52, 0.86)

	Draw.rect(img, cx - 1, 4, 3, h - 8, mast)
	Draw.rect(img, 4, 10, w - 8, 2, mast)
	Draw.rect(img, 4, h - 12, w - 8, 2, mast)

	for y in range(12, h - 12):
		var curve: int = int(sin((float(y - 12) / float(h - 24)) * PI) * 2.5)
		for x in range(5 - curve, w - 5 + curve):
			var c: Color = silk_h if x < cx + 2 else silk_m
			if (y / 5) % 2 == 1:
				c = azure
			Draw.px(img, x, y, c)
	Draw.rect(img, cx + 1, 5, 7, 3, azure)


static func icon_crows_nest(img: Image, _w: int, h: int) -> void:
	var cx: int = _w / 2
	var lens := Color(0.42, 0.88, 0.96)

	Draw.rect(img, cx - 2, 6, 4, h - 10, Draw.WOOD_DARK)
	Draw.rect(img, cx - 2, 6, 2, h - 10, Draw.WOOD_MID)
	Draw.rect(img, cx - 7, 15, 14, 9, Draw.WOOD_MID)
	Draw.rect(img, cx - 7, 15, 14, 2, Draw.WOOD_LIGHT)
	Draw.rect(img, cx - 7, 22, 14, 2, Draw.WOOD_DARK)
	for rx in range(cx - 5, cx + 6, 3):
		Draw.rect(img, rx, 17, 1, 5, Draw.WOOD_DARK)

	Draw.line(img, Vector2i(cx - 2, 13), Vector2i(cx + 8, 7), Draw.BRASS, 3)
	Draw.line(img, Vector2i(cx - 2, 12), Vector2i(cx + 7, 6), Color(1.0, 0.93, 0.56), 1)
	Draw.rect(img, cx + 7, 6, 2, 3, lens)


static func icon_iron_ram(img: Image, w: int, h: int) -> void:
	var cx: int = w / 2
	var steel_d := Color(0.24, 0.28, 0.35)
	var steel_m := Color(0.46, 0.52, 0.62)
	var steel_h := Color(0.84, 0.89, 0.96)

	Draw.rect(img, cx - 6, h - 14, 12, 9, Color(0.52, 0.30, 0.20))
	Draw.rect(img, cx - 7, h - 18, 14, 6, steel_d)
	Draw.rect(img, cx - 6, h - 17, 12, 3, steel_m)
	Draw.px(img, cx - 4, h - 16, Draw.BRASS)
	Draw.px(img, cx + 4, h - 16, Draw.BRASS)

	for y in range(5, h - 18):
		var t: float = float(y - 5) / float(maxi(1, h - 23))
		var half_w: int = maxi(1, int(round(lerpf(1.0, 6.0, t))))
		for x in range(cx - half_w, cx + half_w + 1):
			var c: Color = steel_h if x < cx else (steel_d if x > cx + 1 else steel_m)
			Draw.px(img, x, y, c)


static func icon_reinforced_ribs(img: Image, w: int, h: int) -> void:
	var cx: int = w / 2
	var wood_m := Color(0.62, 0.39, 0.24)
	var wood_l := Color(0.86, 0.64, 0.40)
	var iron := Color(0.34, 0.39, 0.46)

	Draw.rect(img, cx - 2, 5, 4, h - 10, Draw.WOOD_DARK)
	Draw.rect(img, cx - 1, 5, 2, h - 10, wood_m)
	for ry in range(10, h - 8, 12):
		Draw.rect(img, 4, ry - 2, w - 8, 5, wood_m)
		Draw.rect(img, 4, ry - 2, w - 8, 2, wood_l)
		Draw.rect(img, 4, ry + 2, w - 8, 1, Draw.WOOD_DARK)
		Draw.rect(img, cx - 3, ry - 3, 6, 7, iron)
		Draw.px(img, cx - 2, ry - 1, Draw.BRASS)
		Draw.px(img, cx + 1, ry + 1, Draw.BRASS)


static func icon_copper_plating(img: Image, w: int, h: int) -> void:
	var cop_d := Color(0.52, 0.27, 0.17)
	var cop_m := Color(0.80, 0.47, 0.26)
	var cop_h := Color(0.97, 0.72, 0.44)
	var verdigris := Color(0.34, 0.78, 0.68)
	var rivet := Color(0.98, 0.92, 0.76)

	Draw.rect(img, 6, 7, w - 12, h - 14, cop_m)
	Draw.rect(img, 6, 7, w - 12, 3, cop_h)
	Draw.rect(img, 6, 7, 3, h - 14, cop_h)
	Draw.rect(img, 6, h - 10, w - 12, 3, cop_d)
	Draw.rect(img, w - 9, 7, 3, h - 14, cop_d)

	Draw.rect(img, 6, h / 2 - 1, w - 12, 2, cop_d)
	Draw.rect(img, 6, h / 2 + 1, w - 12, 1, cop_h)
	Draw.rect(img, w / 2 - 1, 7, 2, h - 14, cop_d)

	Draw.rect(img, 10, h - 11, 8, 2, verdigris)
	Draw.rect(img, w - 18, h / 2 - 2, 7, 2, verdigris)

	for rx in [9, w / 2 - 4, w / 2 + 3, w - 10]:
		for ry in [10, h / 2 - 4, h / 2 + 3, h - 11]:
			Draw.rect(img, rx, ry, 2, 2, rivet)


static func icon_gunner_quarters(img: Image, w: int, h: int) -> void:
	var iron_d := Color(0.20, 0.22, 0.28)
	var iron_m := Color(0.38, 0.42, 0.50)
	var iron_h := Color(0.76, 0.82, 0.90)
	var ember := Color(1.0, 0.55, 0.16)

	Draw.rect(img, 6, h - 13, w - 12, 7, Draw.WOOD_DARK)
	Draw.rect(img, 7, h - 12, w - 14, 4, Draw.WOOD_MID)
	Draw.line(img, Vector2i(8, 10), Vector2i(w - 9, h - 15), Draw.BRASS, 2)
	Draw.line(img, Vector2i(w - 9, 10), Vector2i(8, h - 15), Draw.WOOD_MID, 2)
	Draw.circle(img, 8.0, 10.0, 2.5, ember)

	var balls: Array[Vector2] = [
		Vector2(16, h - 16), Vector2(24, h - 16), Vector2(32, h - 16),
		Vector2(20, h - 23), Vector2(28, h - 23), Vector2(24, h - 30)
	]
	for bp in balls:
		Draw.circle(img, bp.x, bp.y, 4.2, iron_d)
		Draw.circle(img, bp.x - 0.5, bp.y - 0.5, 3.0, iron_m)
		Draw.px(img, int(bp.x) - 2, int(bp.y) - 2, iron_h)


static func icon_carpenter_workshop(img: Image, w: int, h: int) -> void:
	var steel_m := Color(0.56, 0.62, 0.72)
	var steel_h := Color(0.88, 0.93, 0.98)

	Draw.rect(img, 7, h - 18, w - 14, 5, Draw.WOOD_LIGHT)
	Draw.rect(img, 7, h - 13, w - 14, 3, Draw.WOOD_MID)
	Draw.rect(img, 9, h - 10, 5, 6, Draw.WOOD_DARK)
	Draw.rect(img, w - 14, h - 10, 5, 6, Draw.WOOD_DARK)

	Draw.line(img, Vector2i(10, 22), Vector2i(w - 11, 10), steel_m, 4)
	Draw.line(img, Vector2i(10, 20), Vector2i(w - 12, 9), steel_h, 1)
	Draw.rect(img, 7, 19, 6, 7, Draw.WOOD_MID)
	Draw.rect(img, 8, 21, 3, 3, Draw.BRASS)

	Draw.line(img, Vector2i(20, 28), Vector2i(32, 13), Draw.WOOD_LIGHT, 2)
	Draw.rect(img, 28, 9, 9, 5, steel_m)
	Draw.rect(img, 28, 9, 9, 2, steel_h)


static func icon_spice_crates(img: Image, w: int, h: int) -> void:
	var wood_m := Color(0.66, 0.43, 0.26)
	var saffron := Color(0.96, 0.72, 0.16)
	var paprika := Color(0.86, 0.28, 0.18)

	Draw.rect(img, 4, h - 20, w - 8, 15, wood_m)
	Draw.rect(img, 4, h - 20, w - 8, 2, Draw.WOOD_LIGHT)
	Draw.rect(img, 4, h - 7, w - 8, 2, Draw.WOOD_DARK)
	Draw.line(img, Vector2i(5, h - 18), Vector2i(w - 6, h - 7), Draw.WOOD_DARK, 2)

	Draw.rect(img, 5, 8, w - 10, 14, wood_m)
	Draw.rect(img, 5, 8, w - 10, 2, Draw.WOOD_LIGHT)
	Draw.circle(img, 9.0, 9.0, 3.0, saffron)
	Draw.circle(img, 14.0, 8.5, 3.0, paprika)


static func icon_rum_cask(img: Image, w: int, h: int) -> void:
	var cx: float = float(w) * 0.5 - 0.5
	var cy: float = float(h) * 0.5
	Draw.draw_vertical_barrel(
		img, w, h, cx, cy, 6.2, 7.5, 4, 4, 5,
		[7, h - 8], Draw.BRASS, 1, 0, Draw.BRASS,
		Draw.WOOD_DARK, Color(0.62, 0.38, 0.22), Draw.WOOD_LIGHT
	)
	Draw.rect(img, int(cx) - 1, int(cy), 3, 2, Draw.BRASS)
	Draw.px(img, int(cx), int(cy) + 2, Color(0.75, 0.22, 0.18))


static func icon_royal_treasure(img: Image, w: int, h: int) -> void:
	var wood_d := Color(0.36, 0.18, 0.12)
	var wood_m := Color(0.58, 0.31, 0.18)
	var gold := Color(0.95, 0.72, 0.14)
	var gold_h := Color(1.0, 0.94, 0.56)

	Draw.rect(img, 7, 22, w - 14, h - 28, wood_m)
	Draw.rect(img, 7, h - 9, w - 14, 3, wood_d)
	Draw.rect(img, 8, 9, w - 16, 10, wood_m)
	Draw.rect(img, 7, 9, w - 14, 3, gold_h)

	for gx in range(11, w - 11, 3):
		Draw.circle(img, float(gx), 20.0, 2.5, gold)
		Draw.px(img, gx - 1, 19, gold_h)
	Draw.circle(img, 18.0, 19.0, 2.2, Color(0.92, 0.22, 0.28))
	Draw.circle(img, 25.0, 18.0, 2.4, Color(0.24, 0.88, 0.52))
	Draw.circle(img, 31.0, 19.5, 2.0, Color(0.28, 0.82, 0.96))

	Draw.rect(img, 7, 22, 4, h - 28, gold)
	Draw.rect(img, w - 11, 22, 4, h - 28, gold)
	Draw.rect(img, 7, 22, w - 14, 2, gold_h)
	Draw.rect(img, w / 2 - 3, 22, 6, 7, gold_h)
	Draw.rect(img, w / 2 - 1, 24, 2, 3, Draw.OUTLINE_COLOR)


static func icon_salvage_relic(img: Image, w: int, h: int) -> void:
	var cx: int = w / 2
	var gold_d := Color(0.58, 0.40, 0.14)
	var gold := Color(0.94, 0.74, 0.22)
	var gold_h := Color(1.0, 0.94, 0.58)
	var teal := Color(0.32, 0.94, 0.84)

	Draw.rect(img, cx - 5, h - 10, 10, 4, gold_d)
	Draw.rect(img, cx - 2, h - 20, 4, 10, gold)
	Draw.circle(img, float(cx), 18.0, 8.5, gold)
	Draw.circle(img, float(cx) - 1.0, 17.0, 7.0, gold_h)
	Draw.circle(img, float(cx), 18.0, 5.2, Color(0.14, 0.24, 0.28))
	Draw.circle(img, float(cx), 18.0, 3.0, teal)
	Draw.px(img, cx - 1, 17, Color.WHITE)
	Draw.rect(img, cx - 2, 6, 4, 4, gold_h)


static func icon_kraken_trophy(img: Image, w: int, h: int) -> void:
	var cx: float = float(w) * 0.5
	var cy: float = float(h) * 0.5
	var tent_d := Color(0.34, 0.12, 0.26)
	var tent_m := Color(0.62, 0.20, 0.36)
	var tent_h := Color(0.86, 0.38, 0.48)
	var sucker := Color(0.96, 0.78, 0.72)

	for i in range(44):
		var ang: float = float(i) * 0.14 + 0.5
		var rad: float = 15.5 - float(i) * 0.12
		var tx: float = cx + cos(ang) * rad
		var ty: float = cy + sin(ang) * rad
		var seg_r: float = lerpf(4.8, 2.2, float(i) / 43.0)
		Draw.circle(img, tx, ty, seg_r, tent_m)
		Draw.circle(img, tx - 0.8, ty - 0.8, seg_r * 0.55, tent_h if i < 25 else tent_d)
		if i % 5 == 0:
			Draw.px(img, int(tx + 1), int(ty + 1), sucker)

	Draw.circle(img, cx, cy, 8.0, Color(0.96, 0.76, 0.22))
	Draw.circle(img, cx, cy, 6.0, Color(0.14, 0.52, 0.62))
	Draw.circle(img, cx, cy, 4.5, Color(0.38, 0.96, 0.90))
	Draw.circle(img, cx - 1.5, cy - 1.5, 2.0, Color.WHITE)

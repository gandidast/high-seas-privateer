extends RefCounted
## Bakes 2D pixel-art world entity textures: floating loot/salvage crates (20x20),
## Giant Kraken body (64x64) & animated tentacles (32x32), and coastal forts (48x48).

const Draw = preload("res://visual/baker/pixel_draw_utils.gd")


static func bake_loot_crate_texture(is_salvage: bool = false) -> ImageTexture:
	var w: int = 20
	var h: int = 20
	var img := Draw.create_canvas(w, h)

	var foam_col := Color(0.918, 0.969, 0.976, 0.85)
	var teal_ring := Color(0.451, 0.867, 0.859, 0.65)
	for y in range(2, 18):
		for x in range(2, 18):
			var dx: float = float(x) - 9.5
			var dy: float = float(y) - 10.5
			var d: float = sqrt(dx * dx + dy * dy)
			if d >= 6.8 and d <= 7.9:
				img.set_pixel(x, y, foam_col if ((x + y) % 2 == 0) else teal_ring)

	var body_img := Draw.create_canvas(w, h)
	var wood_dark := Color(0.396, 0.220, 0.145, 1.0)
	var wood_mid := Color(0.561, 0.337, 0.231, 1.0)
	var wood_light := Color(0.851, 0.627, 0.400, 1.0)
	var gold := Color(0.957, 0.706, 0.106, 1.0)
	var gold_hi := Color(1.0, 0.925, 0.561, 1.0)
	var gem := Color(0.329, 0.922, 0.722, 1.0) if is_salvage else Color(0.890, 0.286, 0.286, 1.0)

	for y in range(5, 15):
		for x in range(5, 15):
			var c: Color = wood_mid
			if y <= 6:
				c = wood_light
			elif y >= 13 or y == 9:
				c = wood_dark
			elif (x == 6 or x == 13) and y >= 7:
				c = gold
			body_img.set_pixel(x, y, c)

	for x in range(5, 15):
		body_img.set_pixel(x, 5, gold_hi if x < 10 else gold)
		if is_salvage:
			body_img.set_pixel(x, 14, gold)
	for y in range(5, 15):
		body_img.set_pixel(5, y, gold)
		body_img.set_pixel(14, y, gold)

	body_img.set_pixel(9, 9, gold_hi)
	body_img.set_pixel(10, 9, gold_hi)
	body_img.set_pixel(9, 10, gem)
	body_img.set_pixel(10, 10, gem)

	Draw.apply_pixel_outline(body_img, Draw.OUTLINE_COLOR)
	Draw.composite_over(img, body_img)
	return ImageTexture.create_from_image(img)


static func bake_kraken_body_texture(hit_flash: bool = false) -> ImageTexture:
	var w: int = 64
	var h: int = 64
	var img := Draw.create_canvas(w, h)
	_draw_kraken_water_vortex(img)

	var body_img := Draw.create_canvas(w, h)
	var pal: Dictionary = Draw.get_kraken_palette(hit_flash)
	_draw_kraken_mantle(body_img, pal)
	_draw_kraken_face(body_img, pal["dark"])

	Draw.apply_pixel_outline(body_img, Draw.OUTLINE_COLOR)
	Draw.composite_over(img, body_img)
	return ImageTexture.create_from_image(img)


static func _draw_kraken_water_vortex(img: Image) -> void:
	var foam_white := Color(0.965, 0.984, 1.0, 0.92)
	var foam_aqua := Color(0.420, 0.929, 0.886, 0.84)
	var foam_deep := Color(0.114, 0.459, 0.580, 0.68)
	var vcx: float = 31.5
	var vcy: float = 47.5
	for y in range(36, 61):
		for x in range(4, 60):
			var dx: float = (float(x) - vcx) / 24.5
			var dy: float = (float(y) - vcy) / 10.0
			var r: float = sqrt(dx * dx + dy * dy)
			if r <= 1.08:
				var swirl: float = sin(atan2(dy, dx) * 3.0 + r * 6.5)
				if r >= 0.82 and r <= 1.04 and swirl > -0.25:
					Draw.px(img, x, y, foam_white if swirl > 0.2 else foam_aqua)
				elif r >= 0.56 and r < 0.82 and swirl > 0.10:
					Draw.px(img, x, y, foam_aqua)
				elif r < 0.56:
					Draw.px(img, x, y, foam_deep)


static func _draw_kraken_mantle(body_img: Image, pal: Dictionary) -> void:
	var col_dark: Color = pal["dark"]
	var col_mid: Color = pal["mid"]
	var col_lit: Color = pal["lit"]
	var col_hi: Color = pal["hi"]

	for side in [-1.0, 1.0]:
		for step_i in range(18):
			var t: float = float(step_i) / 17.0
			var fx: float = 31.5 + side * lerpf(9.0, 22.5, t)
			var fy: float = lerpf(23.0, 14.0, pow(t, 0.8)) + sin(t * PI) * 2.5
			var fr: float = lerpf(4.8, 1.4, t)
			var fc: Color = col_lit if (side < 0.0 and t < 0.7) else col_mid
			if t > 0.65 and side > 0.0:
				fc = col_dark
			Draw.circle(body_img, fx, fy, fr, fc)
			if side < 0.0 and t < 0.8:
				Draw.circle(body_img, fx - 0.8, fy - 0.8, fr * 0.48, col_hi)

	for y in range(7, 48):
		var t: float = float(y - 7) / 40.0
		var half_w: float = 0.0
		if t < 0.18:
			half_w = lerpf(2.2, 11.5, sqrt(t / 0.18))
		elif t < 0.58:
			half_w = 11.5 + sin(((t - 0.18) / 0.40) * PI) * 6.5
		else:
			var bt: float = (t - 0.58) / 0.42
			half_w = lerpf(13.5, 15.2, bt * 0.7) - sin(bt * PI) * 1.8

		for x in range(10, 54):
			var dx: float = float(x) - 31.5
			var adx: float = absf(dx)
			if adx > half_w:
				continue
			var norm_x: float = dx / maxf(1.0, half_w)
			var c: Color = col_mid
			if norm_x < -0.18 or (t < 0.45 and norm_x < 0.12):
				c = col_lit
			if norm_x < -0.52 and t < 0.68:
				c = col_hi
			elif norm_x > 0.38 or t > 0.84:
				c = col_dark
			if (y == 16 or y == 24) and adx < half_w * 0.72:
				c = col_dark if norm_x > 0.0 else col_mid
			Draw.px(body_img, x, y, c)

	Draw.circle(body_img, 28.5, 16.0, 4.2, col_hi)
	Draw.circle(body_img, 27.5, 14.5, 2.2, col_hi.lightened(0.15))


static func _draw_kraken_face(body_img: Image, col_dark: Color) -> void:
	var eye_glow := Color(1.000, 0.878, 0.259, 1.0)
	var eye_hot := Color(1.000, 0.980, 0.720, 1.0)
	var beak_bone := Color(0.961, 0.922, 0.839, 1.0)
	var beak_shad := Color(0.761, 0.690, 0.588, 1.0)

	for side_x in [-1, 1]:
		var ex_c: int = (32 + 5) if side_x > 0 else (31 - 5)
		for bx in range(ex_c - 3, ex_c + 4):
			var brow_y: int = 33 + (1 if (bx - ex_c) * side_x < 0 else 0)
			Draw.px(body_img, bx, brow_y, col_dark)
			Draw.px(body_img, bx, brow_y - 1, Draw.OUTLINE_COLOR)
		for ey in range(34, 39):
			for ex in range(ex_c - 2, ex_c + 3):
				if abs(ex - ex_c) + abs(ey - 36) <= 3:
					var ec: Color = eye_hot if ey == 34 else eye_glow
					if ex == ex_c and ey >= 35 and ey <= 37:
						ec = Draw.OUTLINE_COLOR
					Draw.px(body_img, ex, ey, ec)

	for my in range(41, 48):
		var mw: int = 6 if my < 45 else 4
		for mx in range(32 - mw, 32 + mw):
			Draw.px(body_img, mx, my, Draw.OUTLINE_COLOR)
	for fx in [27, 29, 31, 33, 35]:
		var fang_h: int = 3 if fx == 31 else 2
		for fy in range(41, 41 + fang_h):
			Draw.px(body_img, fx, fy, beak_bone if fy == 41 else beak_shad)
	for fx in [28, 30, 32, 34]:
		Draw.px(body_img, fx, 46, beak_shad)
		Draw.px(body_img, fx, 45, beak_bone)


static func bake_kraken_tentacle_texture(frame: int = 0, hit_flash: bool = false) -> ImageTexture:
	var safe_frame: int = clampi(frame, 0, 2)
	var w: int = 32
	var h: int = 32
	var img := Draw.create_canvas(w, h)

	var foam_white := Color(0.965, 0.984, 1.0, 0.90)
	var foam_aqua := Color(0.451, 0.933, 0.890, 0.80)
	for y in range(23, 31):
		for x in range(5, 27):
			var dx: float = (float(x) - 15.5) / 8.5
			var dy: float = (float(y) - 26.8) / 2.8
			var r: float = sqrt(dx * dx + dy * dy)
			if r >= 0.65 and r <= 1.05:
				Draw.px(img, x, y, foam_white if (x + y) % 2 == 0 else foam_aqua)

	var body_img := Draw.create_canvas(w, h)
	var pal: Dictionary = Draw.get_kraken_palette(hit_flash)
	var sucker := Color(0.949, 0.722, 0.635, 1.0)
	var sucker_dim := Color(0.769, 0.451, 0.412, 1.0)

	var phase: float = [-0.4, 1.35, 3.05][safe_frame]
	var steps: int = 34
	var spine: Array[Vector2] = []
	for i in range(steps):
		var t: float = float(i) / float(steps - 1)
		var sy: float = lerpf(26.5, 4.0, t)
		var sx: float = 15.5 + sin(t * PI * 1.48 + phase) * lerpf(1.2, 5.2, t)
		spine.append(Vector2(sx, sy))

	for i in range(steps):
		var t: float = float(i) / float(steps - 1)
		var p: Vector2 = spine[i]
		var rad: float = lerpf(4.3, 1.15, pow(t, 0.82))
		Draw.circle(body_img, p.x, p.y, rad, pal["mid"])
		Draw.circle(body_img, p.x - rad * 0.28, p.y - rad * 0.18, rad * 0.65, pal["lit"])
		Draw.circle(body_img, p.x + rad * 0.32, p.y + rad * 0.20, rad * 0.52, pal["dark"])
		if rad >= 2.0:
			Draw.px(body_img, int(round(p.x - rad * 0.48)), int(round(p.y - rad * 0.35)), pal["hi"])

	for idx_s in [6, 12, 18, 24]:
		var p: Vector2 = spine[idx_s]
		var next_p: Vector2 = spine[mini(steps - 1, idx_s + 1)]
		var tang: Vector2 = (next_p - p).normalized()
		var inner_n := Vector2(tang.y, -tang.x)
		if inner_n.x < 0.0:
			inner_n = -inner_n
		var sp: Vector2 = p + inner_n * lerpf(2.2, 1.1, float(idx_s) / float(steps))
		Draw.circle(body_img, sp.x, sp.y, 1.35, sucker)
		Draw.px(body_img, int(round(sp.x)), int(round(sp.y)), sucker_dim)

	Draw.apply_pixel_outline(body_img, Draw.OUTLINE_COLOR)
	Draw.composite_over(img, body_img)
	return ImageTexture.create_from_image(img)


static func bake_fort_texture(hit_flash: bool = false) -> ImageTexture:
	var w: int = 48
	var h: int = 48
	var img := Draw.create_canvas(w, h)
	var cx: float = 23.5
	var cy: float = 23.5

	var stone_dark := Color(0.78, 0.72, 0.62, 1.0) if hit_flash else Color(0.467, 0.435, 0.420, 1.0)
	var stone_mid := Color(0.95, 0.90, 0.78, 1.0) if hit_flash else Color(0.718, 0.686, 0.635, 1.0)
	var stone_lit := Color(1.0, 0.97, 0.88, 1.0) if hit_flash else Color(0.867, 0.839, 0.776, 1.0)
	var stone_hi := Color(0.953, 0.929, 0.875, 1.0)
	var wood_dark := Color(0.353, 0.196, 0.137, 1.0)
	var wood_mid := Color(0.545, 0.329, 0.216, 1.0)
	var wood_lit := Color(0.722, 0.467, 0.302, 1.0)
	var iron_dark := Color(0.188, 0.204, 0.251, 1.0)
	var iron_mid := Color(0.329, 0.361, 0.427, 1.0)
	var iron_hi := Color(0.659, 0.706, 0.776, 1.0)
	var brass := Color(0.933, 0.714, 0.220, 1.0)

	for y in range(3, h - 3):
		for x in range(3, w - 3):
			var dx: float = float(x) - cx
			var dy: float = float(y) - cy
			var adx: float = absf(dx)
			var ady: float = absf(dy)
			var oct_d: float = maxf(maxf(adx, ady), (adx + ady) * 0.7071)
			var rad_d: float = sqrt(dx * dx + dy * dy)
			if oct_d > 18.8:
				continue
			if oct_d >= 12.2:
				var c: Color = stone_lit if oct_d < 14.5 else (stone_dark if oct_d > 17.3 else stone_mid)
				var ang_bin: int = int(floor((atan2(dy, dx) + PI) / (TAU / 16.0)))
				if (ang_bin % 2 == 0 and absf(oct_d - 15.5) < 0.45) or absf(wrapf(atan2(dy, dx), 0.0, TAU / 8.0)) < 0.04:
					c = stone_dark
				Draw.px(img, x, y, c)
			else:
				var c: Color = wood_mid if ((y / 3) % 2 == 0) else wood_lit
				if y % 3 == 0 or oct_d >= 11.1:
					c = wood_dark
				elif absf(rad_d - 8.5) <= 0.8:
					c = iron_dark
				Draw.px(img, x, y, c)

	for m in range(8):
		var ang: float = (float(m) / 8.0) * TAU + PI / 8.0
		var mx: int = int(round(cx + cos(ang) * 16.8))
		var my: int = int(round(cy + sin(ang) * 16.8))
		Draw.rect(img, mx - 2, my - 2, 5, 5, stone_dark)
		Draw.rect(img, mx - 1, my - 1, 3, 3, stone_hi)

	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var tx: int = int(round(cx + sx * 10.6))
			var ty: int = int(round(cy + sy * 10.6))
			Draw.rect(img, tx - 2, ty - 2, 4, 4, iron_dark)
			Draw.rect(img, tx - 1, ty - 1, 3, 3, Color(1.0, 0.54, 0.14, 1.0))
			Draw.px(img, tx, ty, Color(1.0, 0.94, 0.52, 1.0))

	Draw.rect(img, 17, 19, 10, 10, wood_dark)
	Draw.rect(img, 18, 20, 8, 8, iron_dark)
	Draw.rect(img, 19, 21, 6, 6, iron_mid)
	Draw.rect(img, 20, 18, 4, 2, brass)
	Draw.rect(img, 20, 28, 4, 2, brass)

	for x in range(18, 43):
		var half_b: int = 3 if (x < 29 or x >= 40) else 2
		for y in range(24 - half_b, 24 + half_b):
			var bc: Color = iron_hi if y == 24 - half_b else (iron_dark if y == 24 + half_b - 1 else iron_mid)
			if x == 29 or x >= 41:
				bc = brass if y > 24 - half_b else Color(1.0, 0.92, 0.52, 1.0)
			Draw.px(img, x, y, bc)
	Draw.rect(img, 16, 22, 2, 4, brass)

	Draw.apply_pixel_outline(img, Draw.OUTLINE_COLOR)
	return ImageTexture.create_from_image(img)

extends RefCounted
## Shared 2D pixel-art canvas primitives, outlines, affix accents, compositing,
## and common palette / shape helpers used across visual/baker/* modules.

const OUTLINE_COLOR := Color(0.094, 0.078, 0.145, 1.0) # #181425
const SUNLIGHT_HIGHLIGHT := Color(0.980, 0.898, 0.690, 1.0)

const WOOD_DARK := Color(0.36, 0.20, 0.13, 1.0)
const WOOD_MID := Color(0.56, 0.34, 0.22, 1.0)
const WOOD_LIGHT := Color(0.84, 0.60, 0.38, 1.0)

const IRON_DARK := Color(0.22, 0.24, 0.30, 1.0)
const IRON_MID := Color(0.40, 0.44, 0.52, 1.0)
const IRON_HIGH := Color(0.75, 0.80, 0.88, 1.0)
const BRASS := Color(0.94, 0.74, 0.24, 1.0)


static func create_canvas(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	return img


static func px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, col)


static func rect(img: Image, x0: int, y0: int, rw: int, rh: int, col: Color) -> void:
	for y in range(y0, y0 + rh):
		for x in range(x0, x0 + rw):
			px(img, x, y, col)


static func circle(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	var min_x: int = int(floor(cx - r))
	var max_x: int = int(ceil(cx + r))
	var min_y: int = int(floor(cy - r))
	var max_y: int = int(ceil(cy + r))
	var r_sq: float = r * r
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx: float = float(x) - cx
			var dy: float = float(y) - cy
			if dx * dx + dy * dy <= r_sq:
				px(img, x, y, col)


static func line(img: Image, p0: Vector2i, p1: Vector2i, col: Color, thickness: int = 1) -> void:
	var dist: float = Vector2(p0).distance_to(Vector2(p1))
	var steps: int = maxi(1, int(ceil(dist * 1.5)))
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var x: int = int(round(lerpf(float(p0.x), float(p1.x), t)))
		var y: int = int(round(lerpf(float(p0.y), float(p1.y), t)))
		if thickness <= 1:
			px(img, x, y, col)
		else:
			rect(img, x - thickness / 2, y - thickness / 2, thickness, thickness, col)


static func composite_over(dst: Image, src: Image) -> void:
	var w: int = mini(dst.get_width(), src.get_width())
	var h: int = mini(dst.get_height(), src.get_height())
	for y in range(h):
		for x in range(w):
			var sp: Color = src.get_pixel(x, y)
			if sp.a > 0.0:
				dst.set_pixel(x, y, sp)


static func apply_pixel_outline(img: Image, outline_col: Color = OUTLINE_COLOR) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var copy := img.duplicate() as Image
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in range(h):
		for x in range(w):
			if copy.get_pixel(x, y).a > 0.0:
				continue
			for dir in dirs:
				var nx: int = x + dir.x
				var ny: int = y + dir.y
				if nx >= 0 and nx < w and ny >= 0 and ny < h and copy.get_pixel(nx, ny).a > 0.5:
					img.set_pixel(x, y, outline_col)
					break


static func apply_affix_accents(img: Image, affix: int) -> void:
	if affix == Contracts.ItemAffix.STANDARD:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	var rust_col := Color(0.604, 0.275, 0.137, 1.0)
	var cursed_accent := Color(0.608, 0.365, 0.898, 1.0)
	var cursed_tint := Color(0.329, 0.145, 0.510, 1.0)
	for y in range(h):
		for x in range(w):
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			if affix == Contracts.ItemAffix.RUSTED:
				img.set_pixel(x, y, rust_col if (x * 3 + y * 5) % 7 == 0 else c.darkened(0.12))
			elif affix == Contracts.ItemAffix.MASTERWORK:
				img.set_pixel(x, y, SUNLIGHT_HIGHLIGHT if (x + y) % 11 == 0 else c.lightened(0.06))
			elif affix == Contracts.ItemAffix.CURSED:
				img.set_pixel(x, y, cursed_accent if (x * 2 + y * 3) % 9 == 0 else c.lerp(cursed_tint, 0.16))


static func draw_upright_gun_barrel(
	img: Image,
	cx: int,
	y_start: int,
	y_end: int,
	narrow_until_y: int,
	muzzle_end_y: int,
	ring_ys: Array[int],
	iron_d: Color,
	iron_m: Color,
	iron_h: Color,
	brass_col: Color
) -> void:
	## Shared upright gun barrel painter used by swivel guns and long culverins.
	for y in range(y_start, y_end):
		var half_w: int = 2 if y < narrow_until_y else 3
		if y <= muzzle_end_y:
			half_w = 3 # Flared muzzle ring
		var is_ring: bool = y in ring_ys
		for x in range(cx - half_w, cx + half_w + 1):
			var c: Color = iron_m
			if x == cx - half_w:
				c = iron_h
			elif x == cx + half_w:
				c = iron_d
			if is_ring:
				c = brass_col
			px(img, x, y, c)


static func draw_vertical_barrel(
	img: Image,
	w: int,
	h: int,
	cx: float,
	cy: float,
	rx: float,
	ry: float,
	y_pad_top: int,
	y_pad_bot: int,
	x_pad: int,
	hoop_ys: Array[int],
	hoop_col: Color,
	band_y_min: int,
	band_y_max: int,
	band_col: Color,
	wood_d: Color,
	wood_m: Color,
	wood_l: Color
) -> void:
	## Shared curved wooden barrel painter used by powder barrels and rum casks.
	for y in range(y_pad_top, h - y_pad_bot):
		for x in range(x_pad, w - x_pad):
			var dx: float = (float(x) - cx) / rx
			var dy: float = (float(y) - cy) / ry
			if dx * dx + dy * dy > 1.0:
				continue
			var c: Color = wood_m
			if y in hoop_ys:
				c = hoop_col
			elif band_y_min <= band_y_max and y >= band_y_min and y <= band_y_max and absf(float(x) - cx) < 3.5:
				c = band_col
			elif float(x) < cx - 1.5:
				c = wood_l
			elif float(x) > cx + 2.0:
				c = wood_d
			px(img, x, y, c)


static func get_kraken_palette(hit_flash: bool) -> Dictionary:
	if hit_flash:
		return {
			"dark": Color(0.780, 0.440, 0.520, 1.0),
			"mid": Color(0.941, 0.680, 0.720, 1.0),
			"lit": Color(0.988, 0.860, 0.880, 1.0),
			"hi": Color(1.000, 0.965, 0.960, 1.0)
		}
	return {
		"dark": Color(0.231, 0.090, 0.208, 1.0),
		"mid": Color(0.431, 0.133, 0.275, 1.0),
		"lit": Color(0.620, 0.216, 0.345, 1.0),
		"hi": Color(0.831, 0.408, 0.478, 1.0)
	}

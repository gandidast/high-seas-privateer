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

const CURSED_OUTLINE := Color(0.145, 0.039, 0.235, 1.0)
const CURSED_SHADOW_PURPLE := Color(0.165, 0.067, 0.290, 1.0)
const CURSED_SHADOW_TEAL := Color(0.063, 0.196, 0.247, 1.0)
const CURSED_TENTACLE_DARK := Color(0.220, 0.063, 0.329, 1.0)
const CURSED_TENTACLE_MID := Color(0.451, 0.145, 0.576, 1.0)
const CURSED_TENTACLE_HI := Color(0.725, 0.282, 0.839, 1.0)
const CURSED_SUCKER := Color(0.922, 0.678, 0.961, 1.0)
const CURSED_SLIME_DARK := Color(0.075, 0.420, 0.333, 1.0)
const CURSED_SLIME_GLOW := Color(0.263, 0.961, 0.616, 1.0)
const CURSED_SLIME_CORE := Color(0.780, 1.000, 0.839, 1.0)
const CURSED_KELP_DARK := Color(0.055, 0.255, 0.212, 1.0)
const CURSED_KELP_MID := Color(0.118, 0.459, 0.341, 1.0)
const CURSED_EYE_GLOW := Color(0.282, 0.980, 0.741, 1.0)
const CURSED_EYE_CORE := Color(0.961, 0.176, 0.439, 1.0)
const CURSED_BARNACLE_MID := Color(0.478, 0.439, 0.541, 1.0)
const CURSED_BARNACLE_HI := Color(0.761, 0.722, 0.800, 1.0)


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
	var rare_glint := Color(0.450, 0.910, 1.000, 1.0)
	var rare_tint := Color(0.240, 0.680, 0.940, 1.0)
	var master_tint := Color(0.960, 0.780, 0.260, 1.0)
	for y in range(h):
		var v_ratio: float = float(y) / float(maxi(1, h - 1))
		for x in range(w):
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			if affix == Contracts.ItemAffix.RUSTED:
				img.set_pixel(x, y, rust_col if (x * 3 + y * 5) % 7 == 0 else c.darkened(0.14))
			elif affix == Contracts.ItemAffix.RARE:
				img.set_pixel(x, y, rare_glint if (x + y * 2) % 13 == 0 else c.lerp(rare_tint, 0.11).lightened(0.03))
			elif affix == Contracts.ItemAffix.MASTERWORK:
				img.set_pixel(x, y, SUNLIGHT_HIGHLIGHT if (x + y) % 9 == 0 else c.lerp(master_tint, 0.10).lightened(0.06))
			elif affix == Contracts.ItemAffix.CURSED:
				var lum: float = c.r * 0.30 + c.g * 0.59 + c.b * 0.11
				var abyss_col: Color = CURSED_SHADOW_PURPLE.lerp(CURSED_SHADOW_TEAL, clampf(v_ratio * 0.75 + (0.25 if ((x + y) % 5 == 0) else 0.0), 0.0, 1.0))
				var blend_amt: float = lerpf(0.42, 0.18, clampf(lum, 0.0, 1.0))
				img.set_pixel(x, y, c.lerp(abyss_col, blend_amt))


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


static func px_inner(img: Image, x: int, y: int, col: Color) -> void:
	## Sets pixel inside a 1px safety border so apply_pixel_outline stays intact.
	if x >= 1 and x < img.get_width() - 1 and y >= 1 and y < img.get_height() - 1:
		img.set_pixel(x, y, col)


static func circle_inner(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
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
				px_inner(img, x, y, col)


static func draw_cursed_tentacle(
	img: Image,
	p0: Vector2,
	ctrl: Vector2,
	p1: Vector2,
	r0: float,
	r1: float,
	sucker_step: int = 4,
	sucker_dir: Vector2 = Vector2(0.0, 1.0)
) -> void:
	## Draws a tapered eldritch tentacle along a quadratic Bezier curve with suction cups.
	var steps: int = maxi(8, int(ceil((p0.distance_to(ctrl) + ctrl.distance_to(p1)) * 1.6)))
	var pts: Array[Vector2] = []
	var radii: Array[float] = []
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var omt: float = 1.0 - t
		var pt: Vector2 = p0 * (omt * omt) + ctrl * (2.0 * omt * t) + p1 * (t * t)
		pts.append(pt)
		radii.append(lerpf(r0, r1, t))
	for i in range(steps + 1):
		circle_inner(img, pts[i].x, pts[i].y, radii[i], CURSED_TENTACLE_DARK)
	for i in range(steps + 1):
		var rm: float = radii[i] * 0.72
		if rm >= 0.65:
			circle_inner(img, pts[i].x - 0.35, pts[i].y - 0.45, rm, CURSED_TENTACLE_MID)
	for i in range(steps + 1):
		var rh: float = radii[i] * 0.36
		if rh >= 0.55 and i < steps - 1:
			circle_inner(img, pts[i].x - 0.65, pts[i].y - 0.65, rh, CURSED_TENTACLE_HI)
	var sdir: Vector2 = sucker_dir.normalized() if sucker_dir.length_squared() > 0.01 else Vector2(0.0, 1.0)
	for i in range(2, steps - 1, maxi(2, sucker_step)):
		var r: float = radii[i]
		if r < 1.05:
			continue
		var sp: Vector2 = pts[i] + sdir * maxf(0.8, r * 0.62)
		var sx: int = int(round(sp.x))
		var sy: int = int(round(sp.y))
		px_inner(img, sx, sy, CURSED_SUCKER)
		if r >= 2.2:
			px_inner(img, sx + 1, sy, CURSED_SUCKER)


static func draw_cursed_slime_drip(img: Image, x: int, y_start: int, length: int, wide_base: bool = true) -> void:
	## Draws a slimy bioluminescent goo drip hanging downward from an edge.
	var len_c: int = maxi(2, length)
	if wide_base:
		px_inner(img, x - 1, y_start, CURSED_SLIME_DARK)
		px_inner(img, x + 1, y_start, CURSED_SLIME_DARK)
	px_inner(img, x, y_start, CURSED_SLIME_GLOW)
	for dy in range(1, len_c):
		var py: int = y_start + dy
		if dy == len_c - 1:
			px_inner(img, x, py, CURSED_SLIME_CORE)
			if wide_base:
				px_inner(img, x + 1, py - 1, CURSED_SLIME_DARK)
		elif dy == len_c - 2:
			px_inner(img, x, py, CURSED_SLIME_GLOW)
			if wide_base:
				px_inner(img, x - 1, py, CURSED_SLIME_DARK)
		else:
			px_inner(img, x, py, CURSED_SLIME_GLOW if dy % 2 == 1 else CURSED_SLIME_DARK)


static func draw_cursed_kelp_strand(img: Image, x: int, y_start: int, length: int, sway_dir: int = 1) -> void:
	## Draws a clinging sea-algae / kelp tendril draping down from a rim.
	var cx: int = x
	for dy in range(maxi(2, length)):
		if dy > 0 and dy % 2 == 0:
			cx += sway_dir
		var col: Color = CURSED_KELP_MID if (dy % 2 == 0) else CURSED_KELP_DARK
		px_inner(img, cx, y_start + dy, col)
		if dy == 1:
			px_inner(img, cx - sway_dir, y_start + dy, CURSED_KELP_DARK)
	if length >= 4:
		px_inner(img, cx, y_start + length - 2, CURSED_SLIME_GLOW)


static func draw_eldritch_eye(img: Image, cx: int, cy: int, large: bool = true) -> void:
	## Draws a sinister glowing abyssal eye with vertical slit pupil.
	if large:
		for dy in range(-2, 3):
			var hw: int = 3 if abs(dy) <= 1 else 2
			for dx in range(-hw, hw + 1):
				px_inner(img, cx + dx, cy + dy, CURSED_TENTACLE_DARK)
		for dy in range(-1, 2):
			for dx in range(-2, 3):
				px_inner(img, cx + dx, cy + dy, CURSED_EYE_GLOW)
		for dy in range(-1, 2):
			px_inner(img, cx, cy + dy, CURSED_EYE_CORE)
		px_inner(img, cx - 1, cy - 1, CURSED_SLIME_CORE)
	else:
		for dy in range(-1, 2):
			for dx in range(-2, 3):
				px_inner(img, cx + dx, cy + dy, CURSED_TENTACLE_DARK)
		for dx in range(-1, 2):
			px_inner(img, cx + dx, cy, CURSED_EYE_GLOW)
			px_inner(img, cx + dx, cy + 1, CURSED_SLIME_DARK if dx != 0 else CURSED_EYE_CORE)
		px_inner(img, cx, cy, CURSED_EYE_CORE)
		px_inner(img, cx - 1, cy, CURSED_SLIME_CORE)


static func draw_abyssal_barnacle(img: Image, cx: int, cy: int) -> void:
	## Draws a small crusty abyssal barnacle cluster with glowing spore center.
	px_inner(img, cx - 1, cy, CURSED_BARNACLE_MID)
	px_inner(img, cx + 1, cy, CURSED_BARNACLE_MID)
	px_inner(img, cx, cy - 1, CURSED_BARNACLE_HI)
	px_inner(img, cx, cy + 1, CURSED_BARNACLE_MID)
	px_inner(img, cx, cy, CURSED_TENTACLE_DARK)

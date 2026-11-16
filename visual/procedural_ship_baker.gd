class_name ProceduralShipBaker
extends RefCounted
## Generates crisp 1:1 (64x32) 2D pixel-art sprite-stack ship layers for 3 ship classes,
## pixel-art Giant Kraken body & animated tentacle sprites, 48x48 coastal fort bastions,
## deck module sprites, floating loot crate textures, and detailed Dredge-Grid item icons.

const OUTLINE_COLOR := Color(0.094, 0.078, 0.145, 1.0) # #181425
const SUNLIGHT_HIGHLIGHT := Color(0.980, 0.898, 0.690, 1.0)
const SHIP_TEX_WIDTH: int = 64
const SHIP_TEX_HEIGHT: int = 32
const GRID_CELL_PX: int = 24

static var _ship_layer_cache: Dictionary = {}
static var _module_cache: Dictionary = {}
static var _loot_cache: Dictionary = {}
static var _item_icon_cache: Dictionary = {}
static var _kraken_body_cache: Dictionary = {}
static var _kraken_tentacle_cache: Dictionary = {}
static var _fort_cache: Dictionary = {}


static func get_sail_layer_range(layer_count: int = 24) -> Vector2i:
	var safe_layers: int = maxi(12, layer_count)
	var cabin_end: int = int(round(0.56 * float(safe_layers - 1)))
	var sail_start: int = cabin_end + 2
	var sail_end: int = safe_layers - 3
	return Vector2i(sail_start, sail_end)


static func bake_ship_layers(faction: int = 0, layer_count: int = 20, hull_tier: int = 0) -> Array[ImageTexture]:
	var safe_layers: int = maxi(12, layer_count)
	var safe_tier: int = clampi(hull_tier, 0, 2)
	var cache_key: String = "%d_%d_%d" % [faction, safe_layers, safe_tier]
	if _ship_layer_cache.has(cache_key):
		return _ship_layer_cache[cache_key]

	var layers: Array[ImageTexture] = []
	var colors: Dictionary = _get_faction_palette(faction)
	var spec: Dictionary = _get_hull_spec(safe_tier)

	var last_idx: int = safe_layers - 1
	var keel_end: int = int(round(0.15 * float(last_idx)))
	var hull_lower_end: int = int(round(0.28 * float(last_idx)))
	var deck_end: int = int(round(0.42 * float(last_idx)))
	var cabin_end: int = int(round(0.56 * float(last_idx)))
	var yard_layer: int = cabin_end + 1
	var sail_range: Vector2i = get_sail_layer_range(safe_layers)
	var sail_mid: int = (sail_range.x + sail_range.y) / 2
	var crow_nest_layer: int = safe_layers - 2
	var flag_layer: int = safe_layers - 1

	for layer_idx in range(safe_layers):
		var img := Image.create(SHIP_TEX_WIDTH, SHIP_TEX_HEIGHT, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.0, 0.0, 0.0, 0.0))

		var apply_outline: bool = false

		if layer_idx <= keel_end:
			var k_frac: float = float(layer_idx) / float(maxi(1, keel_end))
			_draw_keel_and_lower_hull(img, k_frac, spec)
			if layer_idx == 1 or layer_idx == keel_end:
				apply_outline = true
		elif layer_idx <= hull_lower_end:
			var h_step: int = layer_idx - keel_end
			var h_steps: int = maxi(1, hull_lower_end - keel_end)
			_draw_lower_bulwark(img, h_step, h_steps, spec, colors)
			if layer_idx == hull_lower_end:
				apply_outline = true
		elif layer_idx <= deck_end:
			var d_step: int = layer_idx - hull_lower_end - 1
			var d_steps: int = maxi(1, deck_end - hull_lower_end)
			_draw_main_deck_and_rails(img, d_step, d_steps, spec, colors)
			if layer_idx == hull_lower_end + 1 or layer_idx == deck_end:
				apply_outline = true
		elif layer_idx <= cabin_end:
			var c_step: int = layer_idx - deck_end - 1
			var c_steps: int = maxi(1, cabin_end - deck_end)
			_draw_cabin_and_castles(img, c_step, c_steps, spec, colors)
			if layer_idx == cabin_end:
				apply_outline = true
		else:
			_draw_masts_and_sails_tiered(
				img, layer_idx, yard_layer, sail_range.x, sail_range.y,
				crow_nest_layer, flag_layer, faction, spec, colors
			)
			if layer_idx == yard_layer or layer_idx == sail_range.x or layer_idx == sail_mid or layer_idx == flag_layer:
				apply_outline = true

		if apply_outline:
			_apply_pixel_outline(img, OUTLINE_COLOR)

		layers.append(ImageTexture.create_from_image(img))

	_ship_layer_cache[cache_key] = layers
	return layers


static func _get_hull_spec(hull_tier: int) -> Dictionary:
	# 1:1 64x32 pixel-art ship hulls
	match hull_tier:
		1:
			# Brigg: balanced twin-mast medium warship
			return {
				"tier": 1,
				"x_min": 9,
				"x_max": 53,
				"max_hw": 8.0,
				"stern_end": 20,
				"fore_start": 43,
				"masts": [26, 41],
				"yard_halfs": [9, 7],
				"sail_halfs": [8, 6],
				"gunport_xs": [22, 29, 36, 43],
				"bowsprit_len": 7
			}
		2:
			# Schwere Fregatte / Galeone: 3-mast flagship with high castles
			return {
				"tier": 2,
				"x_min": 5,
				"x_max": 57,
				"max_hw": 9.8,
				"stern_end": 18,
				"fore_start": 45,
				"masts": [18, 32, 46],
				"yard_halfs": [7, 11, 8],
				"sail_halfs": [6, 10, 7],
				"gunport_xs": [19, 25, 31, 37, 43, 49],
				"bowsprit_len": 5
			}
		_:
			# Schaluppe (Tier 0): nimble, compact 1-mast sloop
			return {
				"tier": 0,
				"x_min": 14,
				"x_max": 49,
				"max_hw": 6.4,
				"stern_end": 22,
				"fore_start": 41,
				"masts": [31],
				"yard_halfs": [8],
				"sail_halfs": [7],
				"gunport_xs": [25, 32, 39],
				"bowsprit_len": 6
			}


static func _hull_half_width_spec(x: int, spec: Dictionary) -> float:
	var x_min: int = int(spec["x_min"])
	var x_max: int = int(spec["x_max"])
	if x < x_min or x > x_max:
		return 0.0
	var span: float = float(maxi(1, x_max - x_min))
	var t: float = float(x - x_min) / span
	var max_hw: float = float(spec["max_hw"])
	var curve: float = sin(pow(t, 0.72) * PI * 0.85 + 0.44)
	return clampf(curve * max_hw, 0.7, max_hw)


static func _get_faction_palette(faction: int) -> Dictionary:
	match faction:
		Contracts.ShipFaction.PIRATE:
			return {
				"trim": Color(0.820, 0.220, 0.235, 1.0),
				"rail": Color(0.320, 0.255, 0.300, 1.0),
				"sail_a": Color(0.145, 0.125, 0.165, 1.0),
				"sail_b": Color(0.686, 0.145, 0.188, 1.0),
				"sail_c": Color(0.240, 0.195, 0.235, 1.0),
				"flag": Color(0.118, 0.106, 0.145, 1.0),
				"flag_emblem": Color(0.961, 0.933, 0.863, 1.0)
			}
		Contracts.ShipFaction.MERCHANT:
			return {
				"trim": Color(0.957, 0.769, 0.263, 1.0),
				"rail": Color(0.949, 0.922, 0.851, 1.0),
				"sail_a": Color(0.180, 0.435, 0.725, 1.0),
				"sail_b": Color(0.961, 0.773, 0.275, 1.0),
				"sail_c": Color(0.965, 0.953, 0.910, 1.0),
				"flag": Color(0.961, 0.773, 0.275, 1.0),
				"flag_emblem": Color(0.180, 0.435, 0.725, 1.0)
			}
		Contracts.ShipFaction.NAVY:
			return {
				"trim": Color(0.969, 0.745, 0.145, 1.0),
				"rail": Color(0.969, 0.745, 0.145, 1.0),
				"sail_a": Color(0.118, 0.235, 0.565, 1.0),
				"sail_b": Color(0.949, 0.729, 0.212, 1.0),
				"sail_c": Color(0.929, 0.949, 0.988, 1.0),
				"flag": Color(0.118, 0.235, 0.565, 1.0),
				"flag_emblem": Color(0.969, 0.745, 0.145, 1.0)
			}
		Contracts.ShipFaction.NEUTRAL:
			return {
				"trim": Color(0.851, 0.627, 0.400, 1.0),
				"rail": Color(0.922, 0.867, 0.753, 1.0),
				"sail_a": Color(0.918, 0.875, 0.776, 1.0),
				"sail_b": Color(0.722, 0.588, 0.435, 1.0),
				"sail_c": Color(0.957, 0.929, 0.867, 1.0),
				"flag": Color(0.851, 0.627, 0.400, 1.0),
				"flag_emblem": Color(0.957, 0.929, 0.867, 1.0)
			}
		_:
			return {
				"trim": Color(0.957, 0.706, 0.106, 1.0),
				"rail": Color(0.957, 0.922, 0.835, 1.0),
				"sail_a": Color(0.796, 0.235, 0.220, 1.0),
				"sail_b": Color(0.961, 0.922, 0.839, 1.0),
				"sail_c": Color(0.878, 0.624, 0.243, 1.0),
				"flag": Color(0.796, 0.235, 0.220, 1.0),
				"flag_emblem": Color(0.961, 0.922, 0.839, 1.0)
			}


static func _draw_keel_and_lower_hull(img: Image, k_frac: float, spec: Dictionary) -> void:
	var scale_w: float = lerpf(0.36, 0.86, k_frac)
	var hull_dark := Color(0.247, 0.145, 0.137, 1.0)
	var hull_mid := Color(0.376, 0.216, 0.165, 1.0)
	var hull_lit := Color(0.490, 0.294, 0.212, 1.0)
	var cy: float = float(SHIP_TEX_HEIGHT) * 0.5 - 0.5

	var x_min: int = int(spec["x_min"])
	var x_max: int = int(spec["x_max"])
	for x in range(x_min, x_max + 1):
		var hw: float = _hull_half_width_spec(x, spec) * scale_w
		if hw <= 0.4:
			continue
		for y in range(1, SHIP_TEX_HEIGHT - 1):
			var dy: float = absf(float(y) - cy)
			if dy <= hw:
				var c: Color = hull_mid if k_frac >= 0.45 else hull_dark
				if float(y) < cy - hw * 0.35 and k_frac >= 0.45:
					c = hull_lit
				img.set_pixel(x, y, c)


static func _draw_lower_bulwark(img: Image, step: int, steps: int, spec: Dictionary, colors: Dictionary) -> void:
	var frac: float = float(step) / float(maxi(1, steps))
	var flare: float = lerpf(0.92, 0.99, frac)
	var hull_side_dark := Color(0.420, 0.243, 0.173, 1.0)
	var hull_side := Color(0.561, 0.337, 0.231, 1.0)
	var hull_lit := Color(0.761, 0.510, 0.333, 1.0)
	var trim_col: Color = colors["trim"]
	var tier: int = int(spec["tier"])
	var gunport_xs: Array = spec["gunport_xs"]
	var cy: float = float(SHIP_TEX_HEIGHT) * 0.5 - 0.5

	var x_min: int = int(spec["x_min"]) - 1
	var x_max: int = int(spec["x_max"]) + 1
	for x in range(x_min, x_max + 1):
		var hw: float = _hull_half_width_spec(x, spec) * flare
		if hw <= 0.4:
			continue
		for y in range(1, SHIP_TEX_HEIGHT - 1):
			var dy: float = absf(float(y) - cy)
			if dy > hw:
				continue
			var c: Color = hull_side if float(y) < cy else hull_side_dark
			if dy > hw - 1.3 and float(y) < cy:
				c = hull_lit
			if step == steps or (tier == 2 and step == 1):
				if dy > hw - 1.5:
					if tier == 2 and step == steps and (x % 3 == 0):
						c = trim_col
					for gx_var in gunport_xs:
						var gx: int = int(gx_var)
						if abs(x - gx) <= 0 and dy > hw - 1.4:
							c = OUTLINE_COLOR
							break
			img.set_pixel(x, y, c)


static func _draw_main_deck_and_rails(img: Image, step: int, steps: int, spec: Dictionary, colors: Dictionary) -> void:
	var frac: float = float(step) / float(maxi(1, steps - 1))
	var flare: float = lerpf(1.00, 1.05, frac)
	var hull_side_dark := Color(0.431, 0.247, 0.173, 1.0)
	var hull_side := Color(0.561, 0.337, 0.231, 1.0)
	var deck_mid := Color(0.722, 0.447, 0.314, 1.0)
	var deck_light := Color(0.835, 0.596, 0.384, 1.0)
	var deck_seam := Color(0.510, 0.302, 0.208, 1.0)
	var trim_col: Color = colors["trim"]
	var rail_col: Color = colors["rail"]

	var tier: int = int(spec["tier"])
	var x_min: int = int(spec["x_min"]) - 1
	var x_max: int = int(spec["x_max"]) + 1
	var stern_end: int = int(spec["stern_end"])
	var fore_start: int = int(spec["fore_start"])
	var masts: Array = spec["masts"]
	var cy: float = float(SHIP_TEX_HEIGHT) * 0.5 - 0.5
	var is_top_rail: bool = (step == steps - 1)
	var is_deck_base: bool = (step <= 1)

	for x in range(x_min, x_max + 1):
		var hw: float = _hull_half_width_spec(x, spec) * flare
		if hw <= 0.4:
			continue
		for y in range(1, SHIP_TEX_HEIGHT - 1):
			var dy: float = absf(float(y) - cy)
			if dy > hw:
				continue

			var is_bulwark: bool = dy > hw - 1.65 or x <= x_min + 2 or x >= x_max - 3
			if not is_deck_base and not is_bulwark:
				var in_stern: bool = (x <= stern_end)
				var in_fore: bool = (tier >= 1 and x >= fore_start)
				var is_beam: bool = false
				for mx_var in masts:
					if abs(x - int(mx_var)) <= 1:
						is_beam = true
						break
				if not in_stern and not in_fore and not is_beam:
					continue

			if is_bulwark:
				var bc: Color = hull_side if float(y) < cy else hull_side_dark
				if is_top_rail:
					if x >= x_max - 4 or x <= x_min + 2 or (tier == 2 and x % 3 == 0):
						bc = trim_col
					else:
						bc = rail_col if (x % 2 == 0 or tier >= 1) else deck_light
				elif float(y) < cy - hw + 1.3:
					bc = SUNLIGHT_HIGHLIGHT
				img.set_pixel(x, y, bc)
			else:
				var pc: Color = deck_light if ((y / 2) % 2 == 0) else deck_mid
				if y % 3 == 0:
					pc = deck_seam
				var mid_x: int = (x_min + x_max) / 2 + 2
				if step == 1 and abs(x - mid_x) <= 3 and dy <= 2.2:
					pc = Color(0.28, 0.17, 0.14, 1.0) if (x % 2 == 0) else deck_seam
				img.set_pixel(x, y, pc)

	# Bowsprit spar protruding forward (+X)
	if step >= 1:
		var b_len: int = int(spec["bowsprit_len"])
		var b_end: int = mini(SHIP_TEX_WIDTH - 2, x_max + b_len - (steps - 1 - step))
		for bx in range(x_max - 2, b_end + 1):
			img.set_pixel(bx, 15, deck_light)
			img.set_pixel(bx, 16, hull_side)
		if tier == 2 and step == steps - 1:
			img.set_pixel(x_max + 1, 15, trim_col)
			img.set_pixel(x_max + 1, 16, trim_col)


static func _draw_cabin_and_castles(img: Image, step: int, steps: int, spec: Dictionary, colors: Dictionary) -> void:
	var rail_col: Color = colors["rail"]
	var trim_col: Color = colors["trim"]
	var wood_dark := Color(0.396, 0.220, 0.145, 1.0)
	var wood_mid := Color(0.561, 0.337, 0.231, 1.0)
	var wood_light := Color(0.835, 0.596, 0.384, 1.0)
	var lantern := Color(1.0, 0.859, 0.420, 1.0)

	var tier: int = int(spec["tier"])
	var x_min: int = int(spec["x_min"])
	var stern_end: int = int(spec["stern_end"])
	var fore_start: int = int(spec["fore_start"])
	var x_max: int = int(spec["x_max"])
	var masts: Array = spec["masts"]
	var cy: float = float(SHIP_TEX_HEIGHT) * 0.5 - 0.5
	var is_roof: bool = (step >= steps - 1)

	# Stern quarterdeck / captain's cabin
	var cab_start: int = x_min + 1
	var cab_end: int = stern_end - (1 if step > 0 else 0)
	for x in range(cab_start, cab_end + 1):
		var hw: float = _hull_half_width_spec(x, spec) * (0.98 - float(step) * 0.06)
		for y in range(2, SHIP_TEX_HEIGHT - 2):
			var dy: float = absf(float(y) - cy)
			if dy > hw:
				continue
			if step == 0:
				if dy > hw - 1.3 or x == cab_start or x == cab_end:
					img.set_pixel(x, y, trim_col if tier == 2 else rail_col)
				else:
					img.set_pixel(x, y, wood_light if ((y / 2) % 2 == 0) else wood_mid)
			elif not is_roof:
				if x >= cab_start + 1 and x <= cab_end - 1 and dy <= hw - 1.1:
					var c: Color = wood_dark if (x == cab_start + 1 or x == cab_end - 1) else wood_mid
					if x == cab_start + 1 and (int(absf(float(y) - cy)) == 2 or int(absf(float(y) - cy)) == 3):
						c = lantern
					img.set_pixel(x, y, c)
			else:
				if x >= cab_start + 2 and x <= cab_end - 2 and dy <= hw - 1.6:
					var rc: Color = trim_col if (x == cab_start + 2 or dy > hw - 2.5) else wood_light
					img.set_pixel(x, y, rc)

	# Frigate & Brigg forecastle deck & golden trim
	if tier >= 1 and step <= 1:
		for x in range(fore_start, x_max):
			var hw: float = _hull_half_width_spec(x, spec) * 0.96
			for y in range(2, SHIP_TEX_HEIGHT - 2):
				var dy: float = absf(float(y) - cy)
				if dy <= hw:
					if dy > hw - 1.3 or x == fore_start or x >= x_max - 2:
						img.set_pixel(x, y, trim_col if tier == 2 else rail_col)
					elif tier == 2 and step == 0:
						img.set_pixel(x, y, wood_mid)

	# Ship's wheel just forward of stern cabin
	if step == 1:
		var wx: int = cab_end + 1
		for wy in range(14, 18):
			img.set_pixel(wx, wy, trim_col if (wy == 14 or wy == 17) else wood_dark)

	# Mast step collars
	for mx_var in masts:
		var mx: int = int(mx_var)
		for dy in [-1, 0, 1]:
			for dx in [0, 1]:
				if abs(dx) + abs(dy) <= 1:
					img.set_pixel(mx + dx, 15 + dy, wood_light if dy < 0 else wood_dark)


static func _draw_masts_and_sails_tiered(
	img: Image,
	layer_idx: int,
	yard_layer: int,
	sail_start: int,
	sail_end: int,
	crow_nest_layer: int,
	flag_layer: int,
	faction: int,
	spec: Dictionary,
	colors: Dictionary
) -> void:
	var mast_col := Color(0.612, 0.400, 0.247, 1.0)
	var mast_hi := Color(0.851, 0.627, 0.400, 1.0)
	var trim_col: Color = colors["trim"]
	var sail_a: Color = colors["sail_a"]
	var sail_b: Color = colors["sail_b"]
	var sail_c: Color = colors["sail_c"]
	var flag_col: Color = colors["flag"]
	var flag_emblem: Color = colors["flag_emblem"]

	var masts: Array = spec["masts"]
	var yard_halfs: Array = spec["yard_halfs"]
	var sail_halfs: Array = spec["sail_halfs"]
	var tier: int = int(spec["tier"])
	var main_mast_idx: int = 1 if masts.size() >= 2 else 0
	var main_mx: int = int(masts[main_mast_idx])

	for mx_var in masts:
		var mx: int = int(mx_var)
		img.set_pixel(mx, 15, mast_hi)
		img.set_pixel(mx, 16, mast_col)

	if layer_idx == yard_layer:
		for m_i in range(masts.size()):
			var mx: int = int(masts[m_i])
			var yh: int = int(yard_halfs[m_i])
			for y in range(16 - yh, 16 + yh):
				img.set_pixel(mx, y, mast_hi if y < 16 else mast_col)
		return

	if layer_idx >= sail_start and layer_idx <= sail_end:
		var sail_prog: float = float(layer_idx - sail_start) / float(maxi(1, sail_end - sail_start))
		var taper: int = 2 if sail_prog > 0.68 else 0
		var sail_mid: int = (sail_start + sail_end) / 2

		for m_i in range(masts.size()):
			var mx: int = int(masts[m_i])
			var sh: int = maxi(3, int(sail_halfs[m_i]) - taper)
			for y in range(16 - sh, 16 + sh):
				var dist_center: float = absf(float(y) - 15.5) / float(sh)
				var bulge: int = 3 if (dist_center < 0.45 and tier >= 1) else (2 if dist_center < 0.65 else 1)
				var sx: int = mx + bulge
				var sc: Color = _pick_clean_sail_band(y, sail_prog, faction, sail_a, sail_b, sail_c)
				img.set_pixel(sx, y, sc)
				img.set_pixel(sx - 1, y, sc.darkened(0.10))

			# Pirate skull emblem on primary sail
			if faction == Contracts.ShipFaction.PIRATE and m_i == main_mast_idx and abs(layer_idx - sail_mid) <= 1:
				var skull_x: int = mx + (3 if tier >= 1 else 2)
				for sy in range(14, 18):
					if layer_idx == sail_mid and (sy == 15 or sy == 16):
						img.set_pixel(skull_x, sy, OUTLINE_COLOR)
					else:
						img.set_pixel(skull_x, sy, flag_emblem)

		# Navy / Merchant golden edge heraldry on main sail tips
		if tier == 2 and (faction == Contracts.ShipFaction.NAVY or faction == Contracts.ShipFaction.MERCHANT):
			var main_sh: int = maxi(3, int(sail_halfs[main_mast_idx]) - taper)
			img.set_pixel(main_mx + 1, 16 - main_sh, trim_col)
			img.set_pixel(main_mx + 1, 16 + main_sh - 1, trim_col)
		return

	if layer_idx == crow_nest_layer:
		for mx_var in masts:
			var mx: int = int(mx_var)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					img.set_pixel(mx + dx, 15 + dy, mast_hi if dy < 0 else mast_col)
	elif layer_idx == flag_layer:
		var flag_len: int = 6 + tier * 2
		for fx in range(main_mx - flag_len, main_mx):
			var wave_y: int = 15 + (1 if ((fx - main_mx) % 3 == 0) else 0)
			img.set_pixel(fx, wave_y, flag_emblem if fx == main_mx - 3 else flag_col)
			if fx >= main_mx - 4:
				img.set_pixel(fx, wave_y + 1, flag_col)


static func _pick_clean_sail_band(y: int, sail_prog: float, faction: int, a: Color, b: Color, c: Color) -> Color:
	var band: int = (y / 3) % 3
	var base: Color = a
	if faction == Contracts.ShipFaction.PIRATE:
		base = a if ((y / 3) % 2 == 0) else b
	elif band == 1:
		base = b
	elif band == 2:
		base = c
	if sail_prog > 0.65:
		base = base.lightened(0.12)
	return base


# ==============================================================================
# DETAILED PIXEL-ART ITEM GRID ICONS (24px PER CELL) FOR CARGO EDITOR
# ==============================================================================

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
	var cache_key: String = "%s_%d_%dx%d_%d_%d" % [item_id, category, cw, ch, rarity, affix]
	if _item_icon_cache.has(cache_key):
		return _item_icon_cache[cache_key]

	var w: int = cw * GRID_CELL_PX
	var h: int = ch * GRID_CELL_PX
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	match item_id:
		"swivel_gun_1x2":
			_icon_swivel_gun(img, w, h, affix)
		"bronze_cannon_2x2":
			_icon_bronze_cannon(img, w, h, affix)
		"chain_launcher_2x1":
			_icon_chain_launcher(img, w, h)
		"long_culverin_1x3":
			_icon_long_culverin(img, w, h)
		"mortar_cannon_2x2":
			_icon_mortar_cannon(img, w, h)
		"greek_fire_2x1":
			_icon_greek_fire(img, w, h)
		"harpoon_ballista_2x1":
			_icon_harpoon_ballista(img, w, h)
		"powder_barrel_1x1":
			_icon_powder_barrel(img, w, h, false)
		"alchemist_powder_1x1":
			_icon_powder_barrel(img, w, h, true)
		"storm_sails_2x2":
			_icon_storm_sails(img, w, h)
		"silk_top_sail_1x2":
			_icon_silk_top_sail(img, w, h)
		"crows_nest_1x2":
			_icon_crows_nest(img, w, h)
		"iron_ram_1x2":
			_icon_iron_ram(img, w, h)
		"reinforced_ribs_1x3":
			_icon_reinforced_ribs(img, w, h)
		"copper_plating_2x2":
			_icon_copper_plating(img, w, h)
		"gunner_quarters_2x2":
			_icon_gunner_quarters(img, w, h)
		"carpenter_workshop_2x2":
			_icon_carpenter_workshop(img, w, h)
		"spice_crates_1x2":
			_icon_spice_crates(img, w, h)
		"rum_casks_1x1":
			_icon_rum_cask(img, w, h)
		"royal_treasure_2x2":
			_icon_royal_treasure(img, w, h)
		"salvage_relic_1x2":
			_icon_salvage_relic(img, w, h)
		"kraken_tentacle_trophy_2x2":
			_icon_kraken_trophy(img, w, h)
		_:
			# Category-based detailed fallback
			match category:
				Contracts.ItemCategory.CANNON:
					_icon_bronze_cannon(img, w, h, affix)
				Contracts.ItemCategory.POWDER_BARREL:
					_icon_powder_barrel(img, w, h, rarity >= Contracts.ItemRarity.LEGENDARY)
				Contracts.ItemCategory.SAIL:
					_icon_storm_sails(img, w, h)
				Contracts.ItemCategory.HULL:
					_icon_copper_plating(img, w, h)
				Contracts.ItemCategory.TREASURE:
					_icon_royal_treasure(img, w, h)
				Contracts.ItemCategory.CREW_MOD:
					_icon_gunner_quarters(img, w, h)
				Contracts.ItemCategory.BOW_WEAPON:
					_icon_iron_ram(img, w, h)
				_:
					_icon_spice_crates(img, w, h)

	_apply_affix_accents(img, affix)
	_apply_pixel_outline(img, OUTLINE_COLOR)

	var tex := ImageTexture.create_from_image(img)
	_item_icon_cache[cache_key] = tex
	return tex


# --- Drawing Primitives for High-Detail Pixel Icons ---

static func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, col)


static func _rect(img: Image, x0: int, y0: int, rw: int, rh: int, col: Color) -> void:
	for y in range(y0, y0 + rh):
		for x in range(x0, x0 + rw):
			_px(img, x, y, col)


static func _circle(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	var min_x: int = int(floor(cx - r))
	var max_x: int = int(ceil(cx + r))
	var min_y: int = int(floor(cy - r))
	var max_y: int = int(ceil(cy + r))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx: float = float(x) - cx
			var dy: float = float(y) - cy
			if dx * dx + dy * dy <= r * r:
				_px(img, x, y, col)


static func _line(img: Image, p0: Vector2i, p1: Vector2i, col: Color, thickness: int = 1) -> void:
	var dist: float = Vector2(p0).distance_to(Vector2(p1))
	var steps: int = maxi(1, int(ceil(dist * 1.5)))
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var x: int = int(round(lerpf(float(p0.x), float(p1.x), t)))
		var y: int = int(round(lerpf(float(p0.y), float(p1.y), t)))
		if thickness <= 1:
			_px(img, x, y, col)
		else:
			_rect(img, x - thickness / 2, y - thickness / 2, thickness, thickness, col)


# --- Individual Detailed Icon Painters ---

static func _icon_swivel_gun(img: Image, w: int, h: int, _affix: int) -> void:
	# 24x48 vertical swivel deck gun
	var cx: int = w / 2
	var wood_d := Color(0.38, 0.21, 0.14)
	var wood_m := Color(0.58, 0.35, 0.23)
	var wood_l := Color(0.82, 0.59, 0.38)
	var iron_d := Color(0.24, 0.26, 0.32)
	var iron_m := Color(0.42, 0.46, 0.54)
	var iron_h := Color(0.75, 0.80, 0.88)
	var brass := Color(0.94, 0.72, 0.24)

	# Heavy timber pedestal base
	_rect(img, cx - 6, h - 10, 12, 6, wood_d)
	_rect(img, cx - 5, h - 10, 10, 4, wood_m)
	_rect(img, cx - 3, h - 18, 6, 9, wood_d)
	_rect(img, cx - 2, h - 18, 4, 8, wood_l)
	# Swivel fork yoke
	_rect(img, cx - 5, h - 22, 10, 4, brass)
	_rect(img, cx - 5, h - 27, 2, 6, iron_m)
	_rect(img, cx + 3, h - 27, 2, 6, iron_m)

	# Upright sleek barrel pointing up
	for y in range(6, h - 16):
		var half_w: int = 3 if y > 13 else 2
		if y <= 8:
			half_w = 3 # Flared muzzle
		for x in range(cx - half_w, cx + half_w + 1):
			var c: Color = iron_m
			if x == cx - half_w:
				c = iron_h
			elif x == cx + half_w:
				c = iron_d
			if y == 9 or y == 18 or y == h - 17:
				c = brass
			_px(img, x, y, c)
	# Breech handle
	_line(img, Vector2i(cx, h - 16), Vector2i(cx + 4, h - 12), brass, 2)


static func _icon_bronze_cannon(img: Image, w: int, h: int, affix: int) -> void:
	# 48x48 heavy ornate naval bronze cannon on 4-wheeled oak carriage
	var cy: int = h / 2 + 2
	var wood_d := Color(0.36, 0.20, 0.13)
	var wood_m := Color(0.56, 0.34, 0.22)
	var wood_l := Color(0.84, 0.60, 0.38)
	var bronze_d := Color(0.49, 0.30, 0.14)
	var bronze_m := Color(0.79, 0.54, 0.22)
	var bronze_h := Color(0.98, 0.85, 0.44)
	var iron := Color(0.26, 0.28, 0.34)
	if affix == Contracts.ItemAffix.CURSED:
		bronze_h = Color(0.45, 0.94, 0.80)

	# Stepped oak naval gun carriage
	_rect(img, 8, cy + 2, w - 20, 8, wood_d)
	_rect(img, 9, cy + 2, w - 22, 5, wood_m)
	_rect(img, 12, cy - 2, w - 26, 4, wood_l)

	# Heavy bronze cannon barrel pointing right
	for x in range(8, w - 5):
		var t: float = float(x - 8) / float(maxi(1, w - 13))
		var r: int = 6 if t < 0.35 else (5 if t < 0.82 else 6)
		for y in range(cy - 5 - r, cy - 4 + r):
			var c: Color = bronze_m
			if y <= cy - 5 - r + 2:
				c = bronze_h
			elif y >= cy - 4 + r - 2:
				c = bronze_d
			if x == 16 or x == 26 or x >= w - 7:
				c = bronze_h if y < cy - 3 else bronze_d
			_px(img, x, y, c)
	# Cascabel knob at breech & bore hole
	_circle(img, 6.0, float(cy - 5), 2.5, bronze_m)
	_px(img, 5, cy - 6, bronze_h)
	_rect(img, w - 5, cy - 7, 2, 5, OUTLINE_COLOR)

	# Front & rear spoked wooden wheels with iron rims
	for wx in [14, w - 16]:
		_circle(img, float(wx), float(cy + 10), 5.5, iron)
		_circle(img, float(wx), float(cy + 10), 4.0, wood_m)
		_circle(img, float(wx), float(cy + 10), 1.5, bronze_h)


static func _icon_chain_launcher(img: Image, w: int, h: int) -> void:
	# 48x24 twin iron balls linked by iron chain + steel launcher frame
	var cy: int = h / 2
	var iron_d := Color(0.20, 0.24, 0.30)
	var iron_m := Color(0.42, 0.48, 0.56)
	var iron_h := Color(0.78, 0.84, 0.92)
	var wood := Color(0.50, 0.30, 0.20)
	var steel := Color(0.58, 0.68, 0.80)

	# Compact twin-rail launcher frame on left
	_rect(img, 4, cy - 6, 16, 12, wood)
	_rect(img, 6, cy - 5, 14, 4, iron_m)
	_rect(img, 6, cy + 1, 14, 4, iron_d)
	_rect(img, 7, cy - 4, 12, 1, iron_h)

	# Chain links bridging two heavy iron balls
	for lx in range(21, w - 10, 3):
		_rect(img, lx, cy - 1, 3, 2, steel)
		_px(img, lx + 1, cy - 2, iron_h)

	# Twin linked chain-shot iron spheres
	_circle(img, 21.0, float(cy - 4), 4.2, iron_d)
	_circle(img, 20.5, float(cy - 4.5), 3.0, iron_m)
	_px(img, 19, cy - 6, iron_h)

	_circle(img, float(w - 9), float(cy + 3), 4.5, iron_d)
	_circle(img, float(w - 9.5), float(cy + 2.5), 3.2, iron_m)
	_px(img, w - 11, cy + 1, iron_h)


static func _icon_long_culverin(img: Image, w: int, h: int) -> void:
	# 24x72 extra-long precision culverin pointing up
	var cx: int = w / 2
	var iron_d := Color(0.18, 0.20, 0.25)
	var iron_m := Color(0.35, 0.39, 0.46)
	var iron_h := Color(0.72, 0.77, 0.85)
	var brass := Color(0.92, 0.74, 0.28)
	var wood_d := Color(0.36, 0.20, 0.13)
	var wood_m := Color(0.56, 0.34, 0.22)

	# Long trail carriage at bottom
	_rect(img, cx - 5, h - 22, 10, 16, wood_d)
	_rect(img, cx - 4, h - 21, 8, 14, wood_m)
	# Side wheels
	_rect(img, cx - 8, h - 20, 3, 10, iron_d)
	_rect(img, cx + 5, h - 20, 3, 10, iron_d)
	_rect(img, cx - 7, h - 18, 1, 6, brass)
	_rect(img, cx + 6, h - 18, 1, 6, brass)

	# Slender 56px long barrel
	for y in range(4, h - 14):
		var half_w: int = 2 if y < 34 else 3
		if y <= 7:
			half_w = 3
		for x in range(cx - half_w, cx + half_w + 1):
			var c: Color = iron_m
			if x == cx - half_w:
				c = iron_h
			elif x == cx + half_w:
				c = iron_d
			if y == 8 or y == 24 or y == 42 or y == h - 15:
				c = brass
			_px(img, x, y, c)
	_circle(img, float(cx), float(h - 12), 2.5, brass)


static func _icon_mortar_cannon(img: Image, w: int, h: int) -> void:
	# 48x48 wide-bore siege mortar angled up-right on heavy timber bed
	var wood_d := Color(0.34, 0.19, 0.13)
	var wood_m := Color(0.55, 0.33, 0.21)
	var wood_l := Color(0.82, 0.58, 0.36)
	var iron_d := Color(0.22, 0.18, 0.22)
	var iron_m := Color(0.39, 0.34, 0.40)
	var iron_h := Color(0.70, 0.68, 0.74)
	var brass := Color(0.98, 0.68, 0.22)

	# Solid timber mortar bed
	_rect(img, 7, h - 15, w - 14, 9, wood_d)
	_rect(img, 8, h - 14, w - 16, 6, wood_m)
	_rect(img, 9, h - 14, w - 18, 2, wood_l)

	# Short, fat mortar tube angled at ~45 deg
	var p0 := Vector2(16.0, float(h - 15))
	var p1 := Vector2(float(w - 11), 12.0)
	for i in range(28):
		var t: float = float(i) / 27.0
		var center: Vector2 = p0.lerp(p1, t)
		var rad: float = 8.5 if t < 0.75 else 9.5
		_circle(img, center.x, center.y, rad, iron_m)
		_circle(img, center.x - 2.0, center.y - 2.0, rad * 0.55, iron_h)
		_circle(img, center.x + 2.0, center.y + 2.0, rad * 0.55, iron_d)

	# Heavy brass reinforcing ring + wide dark bore
	_circle(img, p1.x, p1.y, 9.2, brass)
	_circle(img, p1.x + 1.0, p1.y - 1.0, 5.5, OUTLINE_COLOR)
	# Glowing ember spark at breech fuse
	_rect(img, 10, h - 19, 3, 3, Color(1.0, 0.52, 0.14))
	_px(img, 11, h - 18, Color(1.0, 0.94, 0.56))


static func _icon_greek_fire(img: Image, w: int, h: int) -> void:
	# 48x24 brass dragon-head flamethrower siphon + roaring flame
	var cy: int = h / 2
	var copper_d := Color(0.50, 0.25, 0.16)
	var copper_m := Color(0.78, 0.44, 0.22)
	var brass := Color(0.95, 0.76, 0.26)
	var brass_hi := Color(1.0, 0.94, 0.60)
	var flame_r := Color(0.94, 0.26, 0.14)
	var flame_o := Color(1.0, 0.58, 0.16)
	var flame_y := Color(1.0, 0.92, 0.45)

	# Pressurized copper fuel reservoir on left
	_circle(img, 10.0, float(cy), 6.5, copper_d)
	_circle(img, 9.5, float(cy - 0.5), 5.0, copper_m)
	_rect(img, 8, cy - 7, 4, 14, brass)

	# Brass siphon barrel
	_rect(img, 14, cy - 3, 14, 6, brass)
	_rect(img, 14, cy - 3, 14, 2, brass_hi)

	# Dragon-head muzzle (x: 24..33)
	_rect(img, 24, cy - 5, 8, 4, brass)
	_rect(img, 25, cy - 5, 6, 2, brass_hi)
	_rect(img, 25, cy + 2, 6, 3, copper_m)
	_px(img, 27, cy - 4, Color(0.96, 0.24, 0.20)) # Dragon eye
	_px(img, 30, cy - 2, Color.WHITE) # Fang
	_px(img, 30, cy + 1, Color.WHITE)

	# Roaring alchemical fire jetting right (x: 32..45)
	_circle(img, 36.0, float(cy), 5.0, flame_r)
	_circle(img, 40.0, float(cy - 1), 4.0, flame_o)
	_circle(img, 36.0, float(cy), 3.0, flame_o)
	_circle(img, 35.0, float(cy), 1.8, flame_y)
	_px(img, 44, cy - 3, flame_o)
	_px(img, 45, cy, flame_y)
	_px(img, 43, cy + 3, flame_r)


static func _icon_harpoon_ballista(img: Image, w: int, h: int) -> void:
	# 48x24 crossbow torsion arms + barbed iron harpoon spear + coiled rope
	var cy: int = h / 2
	var wood_d := Color(0.36, 0.20, 0.14)
	var wood_m := Color(0.58, 0.35, 0.23)
	var wood_l := Color(0.84, 0.62, 0.40)
	var steel_d := Color(0.32, 0.38, 0.46)
	var steel_h := Color(0.84, 0.90, 0.96)
	var rope := Color(0.85, 0.76, 0.54)

	# Wooden stock & crank
	_rect(img, 6, cy - 2, 26, 4, wood_m)
	_rect(img, 6, cy - 2, 26, 1, wood_l)
	_rect(img, 5, cy - 4, 4, 8, wood_d)

	# Curved torsion bow arms
	_line(img, Vector2i(26, cy), Vector2i(22, 4), wood_d, 3)
	_line(img, Vector2i(26, cy), Vector2i(22, h - 5), wood_d, 3)
	_line(img, Vector2i(25, cy), Vector2i(22, 5), wood_l, 1)
	_line(img, Vector2i(25, cy), Vector2i(22, h - 6), wood_l, 1)

	# Taut bowstring
	_line(img, Vector2i(21, 5), Vector2i(13, cy), rope, 1)
	_line(img, Vector2i(21, h - 6), Vector2i(13, cy), rope, 1)

	# Coiled tether rope beside stock
	_circle(img, 13.0, float(cy + 6), 3.0, rope)
	_px(img, 13, cy + 6, wood_d)

	# Long barbed steel harpoon spearhead extending right
	_line(img, Vector2i(13, cy), Vector2i(w - 5, cy), steel_d, 2)
	_line(img, Vector2i(13, cy - 1), Vector2i(w - 6, cy - 1), steel_h, 1)
	# Barbed tip
	_line(img, Vector2i(w - 4, cy), Vector2i(w - 11, cy - 4), steel_h, 2)
	_line(img, Vector2i(w - 4, cy), Vector2i(w - 11, cy + 4), steel_d, 2)


static func _icon_powder_barrel(img: Image, w: int, h: int, is_alchemist: bool) -> void:
	# 24x24 oak powder barrel (or glowing alchemical barrel)
	var cx: float = float(w) * 0.5 - 0.5
	var cy: float = float(h) * 0.5 + 1.0
	var wood_d := Color(0.36, 0.19, 0.13)
	var wood_m := Color(0.56, 0.34, 0.22)
	var wood_l := Color(0.82, 0.58, 0.38)
	var band := Color(0.86, 0.22, 0.22) if not is_alchemist else Color(0.30, 0.92, 0.72)
	var hoop := Color(0.32, 0.36, 0.42) if not is_alchemist else Color(0.95, 0.76, 0.24)

	for y in range(5, h - 3):
		for x in range(5, w - 5):
			var dx: float = (float(x) - cx) / 6.5
			var dy: float = (float(y) - cy) / 7.5
			if dx * dx + dy * dy > 1.0:
				continue
			var c: Color = wood_m
			if y == 8 or y == h - 6:
				c = hoop
			elif y >= 10 and y <= 13:
				c = band if absf(float(x) - cx) < 3.5 else wood_m
			elif float(x) < cx - 2.0:
				c = wood_l
			elif float(x) > cx + 2.5:
				c = wood_d
			_px(img, x, y, c)

	# Skull or alchemy rune dot on center band
	_px(img, int(cx), 11, Color.WHITE)
	_px(img, int(cx) + 1, 11, Color.WHITE)
	_px(img, int(cx), 12, Color.WHITE)

	# Lit fuse / glowing alchemy vial at top
	if is_alchemist:
		_rect(img, int(cx) - 2, 2, 5, 4, Color(0.45, 0.98, 0.85))
		_px(img, int(cx), 1, Color.WHITE)
	else:
		_line(img, Vector2i(int(cx), 5), Vector2i(int(cx) + 3, 2), Color(0.82, 0.72, 0.50), 1)
		_px(img, int(cx) + 3, 2, Color(1.0, 0.65, 0.16))
		_px(img, int(cx) + 4, 1, Color(1.0, 0.96, 0.60))


static func _icon_storm_sails(img: Image, w: int, h: int) -> void:
	# 48x48 double billowing heavy storm sails on crossed oak mast
	var cx: int = w / 2
	var mast := Color(0.56, 0.34, 0.22)
	var mast_hi := Color(0.84, 0.60, 0.38)
	var cloth_h := Color(0.97, 0.94, 0.86)
	var cloth_m := Color(0.86, 0.80, 0.69)
	var stripe := Color(0.78, 0.22, 0.20)
	var brass := Color(0.94, 0.74, 0.24)

	# Vertical mast & two yards
	_rect(img, cx - 2, 4, 4, h - 8, mast)
	_rect(img, cx - 2, 4, 1, h - 8, mast_hi)
	_rect(img, 7, 10, w - 14, 3, mast)
	_rect(img, 5, 26, w - 10, 3, mast)

	# Upper topsail
	for y in range(11, 24):
		var half_w: int = 13 + int(sin((float(y - 11) / 12.0) * PI) * 3.0)
		for x in range(cx - half_w, cx + half_w):
			var c: Color = cloth_h if y < 17 else cloth_m
			if y >= 15 and y <= 17:
				c = stripe
			_px(img, x, y, c)

	# Lower mainsail
	for y in range(27, h - 6):
		var half_w: int = 16 + int(sin((float(y - 27) / 14.0) * PI) * 3.0)
		for x in range(cx - half_w, cx + half_w):
			var c: Color = cloth_h if y < 34 else cloth_m
			if y >= 32 and y <= 34:
				c = stripe
			_px(img, x, y, c)

	_px(img, cx, 5, brass)


static func _icon_silk_top_sail(img: Image, w: int, h: int) -> void:
	# 24x48 sleek azure-striped silk topsail
	var cx: int = w / 2
	var mast := Color(0.62, 0.40, 0.25)
	var silk_h := Color(0.98, 0.96, 0.90)
	var silk_m := Color(0.89, 0.86, 0.78)
	var azure := Color(0.22, 0.52, 0.86)

	_rect(img, cx - 1, 4, 3, h - 8, mast)
	_rect(img, 4, 10, w - 8, 2, mast)
	_rect(img, 4, h - 12, w - 8, 2, mast)

	for y in range(12, h - 12):
		var curve: int = int(sin((float(y - 12) / float(h - 24)) * PI) * 2.5)
		for x in range(5 - curve, w - 5 + curve):
			var c: Color = silk_h if x < cx + 2 else silk_m
			if (y / 5) % 2 == 1:
				c = azure
			_px(img, x, y, c)

	# Top blue pennant
	_rect(img, cx + 1, 5, 7, 3, azure)


static func _icon_crows_nest(img: Image, w: int, h: int) -> void:
	# 24x48 timber lookout mast + basket + gleaming brass spyglass
	var cx: int = w / 2
	var wood_d := Color(0.38, 0.21, 0.14)
	var wood_m := Color(0.58, 0.36, 0.23)
	var wood_l := Color(0.84, 0.62, 0.39)
	var brass := Color(0.95, 0.76, 0.26)
	var lens := Color(0.42, 0.88, 0.96)

	# Mast shaft
	_rect(img, cx - 2, 6, 4, h - 10, wood_d)
	_rect(img, cx - 2, 6, 2, h - 10, wood_m)

	# Crow's nest wooden basket at upper third
	_rect(img, cx - 7, 15, 14, 9, wood_m)
	_rect(img, cx - 7, 15, 14, 2, wood_l)
	_rect(img, cx - 7, 22, 14, 2, wood_d)
	for rx in range(cx - 5, cx + 6, 3):
		_rect(img, rx, 17, 1, 5, wood_d)

	# Brass spyglass / telescope angled upward right
	_line(img, Vector2i(cx - 2, 13), Vector2i(cx + 8, 7), brass, 3)
	_line(img, Vector2i(cx - 2, 12), Vector2i(cx + 7, 6), Color(1.0, 0.93, 0.56), 1)
	_rect(img, cx + 7, 6, 2, 3, lens)


static func _icon_iron_ram(img: Image, w: int, h: int) -> void:
	# 24x48 forged steel prow ramming beak
	var cx: int = w / 2
	var wood := Color(0.52, 0.30, 0.20)
	var steel_d := Color(0.24, 0.28, 0.35)
	var steel_m := Color(0.46, 0.52, 0.62)
	var steel_h := Color(0.84, 0.89, 0.96)
	var brass := Color(0.92, 0.72, 0.26)

	# Timber prow backing at bottom
	_rect(img, cx - 6, h - 14, 12, 9, wood)
	# Heavy iron mounting collar with rivets
	_rect(img, cx - 7, h - 18, 14, 6, steel_d)
	_rect(img, cx - 6, h - 17, 12, 3, steel_m)
	_px(img, cx - 4, h - 16, brass)
	_px(img, cx + 4, h - 16, brass)

	# Beveled tapering steel ramming blade pointing up
	for y in range(5, h - 18):
		var t: float = float(y - 5) / float(maxi(1, h - 23))
		var half_w: int = maxi(1, int(round(lerpf(1.0, 6.0, t))))
		for x in range(cx - half_w, cx + half_w + 1):
			var c: Color = steel_m
			if x < cx:
				c = steel_h
			elif x > cx + 1:
				c = steel_d
			_px(img, x, y, c)


static func _icon_reinforced_ribs(img: Image, w: int, h: int) -> void:
	# 24x72 massive curved oak ship ribs with iron brackets
	var cx: int = w / 2
	var wood_d := Color(0.38, 0.22, 0.14)
	var wood_m := Color(0.62, 0.39, 0.24)
	var wood_l := Color(0.86, 0.64, 0.40)
	var iron := Color(0.34, 0.39, 0.46)
	var brass := Color(0.92, 0.74, 0.28)

	# Central keel spine
	_rect(img, cx - 2, 5, 4, h - 10, wood_d)
	_rect(img, cx - 1, 5, 2, h - 10, wood_m)

	# 5 heavy rib frames along length
	for ry in range(10, h - 8, 12):
		_rect(img, 4, ry - 2, w - 8, 5, wood_m)
		_rect(img, 4, ry - 2, w - 8, 2, wood_l)
		_rect(img, 4, ry + 2, w - 8, 1, wood_d)
		# Iron bracket & bolts at center joint
		_rect(img, cx - 3, ry - 3, 6, 7, iron)
		_px(img, cx - 2, ry - 1, brass)
		_px(img, cx + 1, ry + 1, brass)


static func _icon_copper_plating(img: Image, w: int, h: int) -> void:
	# 48x48 overlapping riveted copper hull armor sheets + verdigris edge
	var cop_d := Color(0.52, 0.27, 0.17)
	var cop_m := Color(0.80, 0.47, 0.26)
	var cop_h := Color(0.97, 0.72, 0.44)
	var verdigris := Color(0.34, 0.78, 0.68)
	var rivet := Color(0.98, 0.92, 0.76)

	_rect(img, 6, 7, w - 12, h - 14, cop_m)
	_rect(img, 6, 7, w - 12, 3, cop_h)
	_rect(img, 6, 7, 3, h - 14, cop_h)
	_rect(img, 6, h - 10, w - 12, 3, cop_d)
	_rect(img, w - 9, 7, 3, h - 14, cop_d)

	# Overlapping plate seams
	_rect(img, 6, h / 2 - 1, w - 12, 2, cop_d)
	_rect(img, 6, h / 2 + 1, w - 12, 1, cop_h)
	_rect(img, w / 2 - 1, 7, 2, h - 14, cop_d)

	# Turquoise verdigris patina accents along lower seam
	_rect(img, 10, h - 11, 8, 2, verdigris)
	_rect(img, w - 18, h / 2 - 2, 7, 2, verdigris)

	# Corner rivets on each plate quadrant
	for rx in [9, w / 2 - 4, w / 2 + 3, w - 10]:
		for ry in [10, h / 2 - 4, h / 2 + 3, h - 11]:
			_rect(img, rx, ry, 2, 2, rivet)


static func _icon_gunner_quarters(img: Image, w: int, h: int) -> void:
	# 48x48 cannonball pyramid + crossed brass linstocks + lantern
	var wood_d := Color(0.34, 0.20, 0.14)
	var wood_m := Color(0.56, 0.34, 0.22)
	var iron_d := Color(0.20, 0.22, 0.28)
	var iron_m := Color(0.38, 0.42, 0.50)
	var iron_h := Color(0.76, 0.82, 0.90)
	var brass := Color(0.94, 0.74, 0.24)
	var ember := Color(1.0, 0.55, 0.16)

	# Oak ammunition rack base
	_rect(img, 6, h - 13, w - 12, 7, wood_d)
	_rect(img, 7, h - 12, w - 14, 4, wood_m)

	# Crossed brass ramrod & linstock behind cannonballs
	_line(img, Vector2i(8, 10), Vector2i(w - 9, h - 15), brass, 2)
	_line(img, Vector2i(w - 9, 10), Vector2i(8, h - 15), wood_m, 2)
	_circle(img, 8.0, 10.0, 2.5, ember)

	# Pyramid of 6 iron cannonballs
	var balls: Array[Vector2] = [
		Vector2(16, h - 16), Vector2(24, h - 16), Vector2(32, h - 16),
		Vector2(20, h - 23), Vector2(28, h - 23),
		Vector2(24, h - 30)
	]
	for bp in balls:
		_circle(img, bp.x, bp.y, 4.2, iron_d)
		_circle(img, bp.x - 0.5, bp.y - 0.5, 3.0, iron_m)
		_px(img, int(bp.x) - 2, int(bp.y) - 2, iron_h)


static func _icon_carpenter_workshop(img: Image, w: int, h: int) -> void:
	# 48x48 oak workbench with gleaming steel saw & mallet
	var wood_d := Color(0.36, 0.20, 0.13)
	var wood_m := Color(0.60, 0.37, 0.23)
	var wood_l := Color(0.86, 0.64, 0.40)
	var steel_m := Color(0.56, 0.62, 0.72)
	var steel_h := Color(0.88, 0.93, 0.98)
	var brass := Color(0.94, 0.74, 0.24)

	# Workbench table + legs
	_rect(img, 7, h - 18, w - 14, 5, wood_l)
	_rect(img, 7, h - 13, w - 14, 3, wood_m)
	_rect(img, 9, h - 10, 5, 6, wood_d)
	_rect(img, w - 14, h - 10, 5, 6, wood_d)

	# Hand saw resting diagonally
	_line(img, Vector2i(10, 22), Vector2i(w - 11, 10), steel_m, 4)
	_line(img, Vector2i(10, 20), Vector2i(w - 12, 9), steel_h, 1)
	_rect(img, 7, 19, 6, 7, wood_m)
	_rect(img, 8, 21, 3, 3, brass)

	# Carpenter hammer crossed over saw
	_line(img, Vector2i(20, 28), Vector2i(32, 13), wood_l, 2)
	_rect(img, 28, 9, 9, 5, steel_m)
	_rect(img, 28, 9, 9, 2, steel_h)


static func _icon_spice_crates(img: Image, w: int, h: int) -> void:
	# 24x48 stacked spice crates with bright saffron/cinnamon sacks
	var wood_d := Color(0.38, 0.22, 0.14)
	var wood_m := Color(0.66, 0.43, 0.26)
	var wood_l := Color(0.86, 0.65, 0.42)
	var saffron := Color(0.96, 0.72, 0.16)
	var paprika := Color(0.86, 0.28, 0.18)

	# Lower crate
	_rect(img, 4, h - 20, w - 8, 15, wood_m)
	_rect(img, 4, h - 20, w - 8, 2, wood_l)
	_rect(img, 4, h - 7, w - 8, 2, wood_d)
	_line(img, Vector2i(5, h - 18), Vector2i(w - 6, h - 7), wood_d, 2)

	# Upper open spice crate
	_rect(img, 5, 8, w - 10, 14, wood_m)
	_rect(img, 5, 8, w - 10, 2, wood_l)
	_circle(img, 9.0, 9.0, 3.0, saffron)
	_circle(img, 14.0, 8.5, 3.0, paprika)


static func _icon_rum_cask(img: Image, w: int, h: int) -> void:
	# 24x24 cozy curved rum cask with brass tap
	var cx: float = float(w) * 0.5 - 0.5
	var cy: float = float(h) * 0.5
	var wood_d := Color(0.38, 0.21, 0.14)
	var wood_m := Color(0.62, 0.38, 0.22)
	var wood_l := Color(0.84, 0.62, 0.38)
	var brass := Color(0.95, 0.74, 0.24)

	for y in range(4, h - 4):
		for x in range(5, w - 5):
			var dx: float = (float(x) - cx) / 6.2
			var dy: float = (float(y) - cy) / 7.5
			if dx * dx + dy * dy > 1.0:
				continue
			var c: Color = wood_m
			if y == 7 or y == h - 8:
				c = brass
			elif float(x) < cx - 1.5:
				c = wood_l
			elif float(x) > cx + 2.0:
				c = wood_d
			_px(img, x, y, c)
	# Tap spigot
	_rect(img, int(cx) - 1, int(cy), 3, 2, brass)
	_px(img, int(cx), int(cy) + 2, Color(0.75, 0.22, 0.18))


static func _icon_royal_treasure(img: Image, w: int, h: int) -> void:
	# 48x48 ornate gold-trimmed royal treasure chest overflowing with doubloons & gems
	var wood_d := Color(0.36, 0.18, 0.12)
	var wood_m := Color(0.58, 0.31, 0.18)
	var gold := Color(0.95, 0.72, 0.14)
	var gold_h := Color(1.0, 0.94, 0.56)
	var ruby := Color(0.92, 0.22, 0.28)
	var emerald := Color(0.24, 0.88, 0.52)
	var sapphire := Color(0.28, 0.82, 0.96)

	# Chest lower box
	_rect(img, 7, 22, w - 14, h - 28, wood_m)
	_rect(img, 7, h - 9, w - 14, 3, wood_d)
	# Domed lid open/ajar with gold rim
	_rect(img, 8, 9, w - 16, 10, wood_m)
	_rect(img, 7, 9, w - 14, 3, gold_h)

	# Pile of glittering gold coins & gems in the middle seam
	for gx in range(11, w - 11, 3):
		_circle(img, float(gx), 20.0, 2.5, gold)
		_px(img, gx - 1, 19, gold_h)
	_circle(img, 18.0, 19.0, 2.2, ruby)
	_circle(img, 25.0, 18.0, 2.4, emerald)
	_circle(img, 31.0, 19.5, 2.0, sapphire)

	# Gold straps & lock clasp
	_rect(img, 7, 22, 4, h - 28, gold)
	_rect(img, w - 11, 22, 4, h - 28, gold)
	_rect(img, 7, 22, w - 14, 2, gold_h)
	_rect(img, w / 2 - 3, 22, 6, 7, gold_h)
	_rect(img, w / 2 - 1, 24, 2, 3, OUTLINE_COLOR)


static func _icon_salvage_relic(img: Image, w: int, h: int) -> void:
	# 24x48 ancient golden astrolabe/chalice with glowing sea-teal core
	var cx: int = w / 2
	var gold_d := Color(0.58, 0.40, 0.14)
	var gold := Color(0.94, 0.74, 0.22)
	var gold_h := Color(1.0, 0.94, 0.58)
	var teal := Color(0.32, 0.94, 0.84)

	# Pedestal & handle
	_rect(img, cx - 5, h - 10, 10, 4, gold_d)
	_rect(img, cx - 2, h - 20, 4, 10, gold)

	# Ornate astrolabe ring
	_circle(img, float(cx), 18.0, 8.5, gold)
	_circle(img, float(cx) - 1.0, 17.0, 7.0, gold_h)
	_circle(img, float(cx), 18.0, 5.2, Color(0.14, 0.24, 0.28))
	_circle(img, float(cx), 18.0, 3.0, teal)
	_px(img, cx - 1, 17, Color.WHITE)
	# Top crown ring
	_rect(img, cx - 2, 6, 4, 4, gold_h)


static func _icon_kraken_trophy(img: Image, w: int, h: int) -> void:
	# 48x48 coiled crimson-violet kraken tentacle clutching a radiant abyssal jewel
	var cx: float = float(w) * 0.5
	var cy: float = float(h) * 0.5
	var tent_d := Color(0.34, 0.12, 0.26)
	var tent_m := Color(0.62, 0.20, 0.36)
	var tent_h := Color(0.86, 0.38, 0.48)
	var sucker := Color(0.96, 0.78, 0.72)
	var gold := Color(0.96, 0.76, 0.22)
	var pearl := Color(0.38, 0.96, 0.90)

	# Coiled outer tentacle spiral
	for i in range(44):
		var ang: float = float(i) * 0.14 + 0.5
		var rad: float = 15.5 - float(i) * 0.12
		var tx: float = cx + cos(ang) * rad
		var ty: float = cy + sin(ang) * rad
		var seg_r: float = lerpf(4.8, 2.2, float(i) / 43.0)
		_circle(img, tx, ty, seg_r, tent_m)
		_circle(img, tx - 0.8, ty - 0.8, seg_r * 0.55, tent_h if i < 25 else tent_d)
		if i % 5 == 0:
			_px(img, int(tx + 1), int(ty + 1), sucker)

	# Central glowing abyssal jewel set in gold crown
	_circle(img, cx, cy, 8.0, gold)
	_circle(img, cx, cy, 6.0, Color(0.14, 0.52, 0.62))
	_circle(img, cx, cy, 4.5, pearl)
	_circle(img, cx - 1.5, cy - 1.5, 2.0, Color.WHITE)


# ==============================================================================
# COMPACT 16x16 DECK SOCKET MODULE SPRITE BAKERS (FOR SHIP STACKS)
# ==============================================================================

static func bake_module_texture(category: int, rarity: int = 0, affix: int = 0) -> ImageTexture:
	var cache_key: String = "%d_%d_%d" % [category, rarity, affix]
	if _module_cache.has(cache_key):
		return _module_cache[cache_key]

	var w: int = 16
	var h: int = 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	match category:
		Contracts.ItemCategory.CANNON:
			_draw_module_cannon(img, rarity, affix)
		Contracts.ItemCategory.POWDER_BARREL:
			_draw_module_powder_barrel(img)
		Contracts.ItemCategory.SAIL:
			_draw_module_sail(img, rarity)
		Contracts.ItemCategory.HULL:
			_draw_module_hull_plate(img)
		Contracts.ItemCategory.CARGO:
			_draw_module_cargo_crate(img)
		Contracts.ItemCategory.TREASURE:
			_draw_module_treasure_chest(img)
		Contracts.ItemCategory.CREW_MOD:
			_draw_module_crew_mod(img)
		Contracts.ItemCategory.BOW_WEAPON:
			_draw_module_hull_plate(img)
		_:
			_draw_module_cargo_crate(img)

	_apply_affix_accents(img, affix)
	_apply_pixel_outline(img, OUTLINE_COLOR)

	var tex := ImageTexture.create_from_image(img)
	_module_cache[cache_key] = tex
	return tex


static func bake_loot_crate_texture(is_salvage: bool = false) -> ImageTexture:
	var cache_key: int = 1 if is_salvage else 0
	if _loot_cache.has(cache_key):
		return _loot_cache[cache_key]

	var w: int = 20
	var h: int = 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var foam_col := Color(0.918, 0.969, 0.976, 0.85)
	var teal_ring := Color(0.451, 0.867, 0.859, 0.65)
	for y in range(2, 18):
		for x in range(2, 18):
			var dx: float = float(x) - 9.5
			var dy: float = float(y) - 10.5
			var d: float = sqrt(dx * dx + dy * dy)
			if d >= 6.8 and d <= 7.9:
				img.set_pixel(x, y, foam_col if ((x + y) % 2 == 0) else teal_ring)

	var body_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	body_img.fill(Color(0, 0, 0, 0))

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
			elif y >= 13:
				c = wood_dark
			elif y == 9:
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

	_apply_pixel_outline(body_img, OUTLINE_COLOR)

	for y in range(h):
		for x in range(w):
			var bp: Color = body_img.get_pixel(x, y)
			if bp.a > 0.0:
				img.set_pixel(x, y, bp)

	var tex := ImageTexture.create_from_image(img)
	_loot_cache[cache_key] = tex
	return tex


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

	for x in range(3, 9):
		for y in range(5, 11):
			img.set_pixel(x, y, wood)
	for wx in [4, 7]:
		img.set_pixel(wx, 4, metal_dark)
		img.set_pixel(wx, 11, metal_dark)

	for x in range(4, 14):
		for y in range(6, 10):
			if x >= 11 and (y == 6 or y == 9):
				continue
			var c: Color = metal_mid
			if y == 6:
				c = metal_hi
			elif y == 9:
				c = metal_dark
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
			elif y == 7 or y == 8:
				c = red_band if absf(dx) < 2.2 else wood_mid
			elif x <= 6:
				c = wood_hi
			elif x >= 10:
				c = wood_dark
			img.set_pixel(x, y, c)


static func _draw_module_sail(img: Image, rarity: int) -> void:
	var cloth_lit := Color(0.973, 0.945, 0.875, 1.0)
	var cloth_mid := Color(0.878, 0.824, 0.714, 1.0)
	var stripe := Color(0.227, 0.490, 0.835, 1.0) if rarity >= Contracts.ItemRarity.RARE else Color(0.796, 0.235, 0.220, 1.0)
	var spar := Color(0.561, 0.337, 0.231, 1.0)

	for y in range(3, 13):
		img.set_pixel(7, y, spar)
		img.set_pixel(8, y, spar)
	for x in range(4, 13):
		for y in range(4, 12):
			if abs(x - 8) + abs(y - 8) <= 5:
				var c: Color = cloth_lit if y < 7 else cloth_mid
				if y == 7 or y == 8:
					c = stripe
				img.set_pixel(x, y, c)


static func _draw_module_hull_plate(img: Image) -> void:
	var copper_dark := Color(0.522, 0.278, 0.180, 1.0)
	var copper_mid := Color(0.780, 0.451, 0.255, 1.0)
	var copper_hi := Color(0.957, 0.690, 0.420, 1.0)
	var rivet := Color(0.961, 0.922, 0.800, 1.0)

	for y in range(4, 12):
		for x in range(3, 13):
			var c: Color = copper_mid
			if y == 4 or x == 3:
				c = copper_hi
			elif y == 11 or x == 12 or y == 8:
				c = copper_dark
			img.set_pixel(x, y, c)
	img.set_pixel(4, 5, rivet)
	img.set_pixel(11, 5, rivet)
	img.set_pixel(4, 10, rivet)
	img.set_pixel(11, 10, rivet)


static func _draw_module_cargo_crate(img: Image) -> void:
	var wood_dark := Color(0.396, 0.220, 0.145, 1.0)
	var wood_mid := Color(0.651, 0.412, 0.271, 1.0)
	var wood_hi := Color(0.851, 0.627, 0.400, 1.0)
	var strap := Color(0.902, 0.722, 0.302, 1.0)

	for y in range(4, 12):
		for x in range(4, 12):
			var c: Color = wood_mid
			if y == 4 or x == 4:
				c = wood_hi
			elif y == 11 or x == 11:
				c = wood_dark
			elif x == y:
				c = strap
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
	var wood := Color(0.56, 0.34, 0.22, 1.0)
	var brass := Color(0.95, 0.76, 0.24, 1.0)
	var lantern := Color(1.0, 0.92, 0.56, 1.0)
	for y in range(4, 12):
		for x in range(4, 12):
			img.set_pixel(x, y, wood)
	img.set_pixel(7, 7, brass)
	img.set_pixel(8, 7, lantern)
	img.set_pixel(7, 8, lantern)
	img.set_pixel(8, 8, brass)


static func _apply_affix_accents(img: Image, affix: int) -> void:
	if affix == Contracts.ItemAffix.STANDARD:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	for y in range(h):
		for x in range(w):
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			if affix == Contracts.ItemAffix.RUSTED:
				if (x * 3 + y * 5) % 7 == 0:
					img.set_pixel(x, y, Color(0.604, 0.275, 0.137, 1.0))
				else:
					img.set_pixel(x, y, c.darkened(0.12))
			elif affix == Contracts.ItemAffix.MASTERWORK:
				if (x + y) % 11 == 0:
					img.set_pixel(x, y, SUNLIGHT_HIGHLIGHT)
				else:
					img.set_pixel(x, y, c.lightened(0.06))
			elif affix == Contracts.ItemAffix.CURSED:
				if (x * 2 + y * 3) % 9 == 0:
					img.set_pixel(x, y, Color(0.608, 0.365, 0.898, 1.0))
				else:
					img.set_pixel(x, y, c.lerp(Color(0.329, 0.145, 0.510, 1.0), 0.16))


static func _apply_pixel_outline(img: Image, outline_col: Color) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var copy := img.duplicate() as Image
	for y in range(h):
		for x in range(w):
			if copy.get_pixel(x, y).a > 0.0:
				continue
			var touches_opaque := false
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + dir.x
				var ny: int = y + dir.y
				if nx >= 0 and nx < w and ny >= 0 and ny < h:
					if copy.get_pixel(nx, ny).a > 0.5:
						touches_opaque = true
						break
			if touches_opaque:
				img.set_pixel(x, y, outline_col)


# ==============================================================================
# PIXEL-ART GIANT KRAKEN & COASTAL FORT BASTION TEXTURES
# ==============================================================================

static func bake_kraken_body_texture(hit_flash: bool = false) -> ImageTexture:
	var cache_key: int = 1 if hit_flash else 0
	if _kraken_body_cache.has(cache_key):
		return _kraken_body_cache[cache_key]

	var w: int = 64
	var h: int = 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	# 1. Turquoise-white swirling foam vortex under Kraken waterline (y = 38..58)
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
				var ang: float = atan2(dy, dx)
				var swirl: float = sin(ang * 3.0 + r * 6.5)
				if r >= 0.82 and r <= 1.04 and swirl > -0.25:
					_px(img, x, y, foam_white if swirl > 0.2 else foam_aqua)
				elif r >= 0.56 and r < 0.82 and swirl > 0.10:
					_px(img, x, y, foam_aqua)
				elif r < 0.56:
					_px(img, x, y, foam_deep)

	# 2. Separate body image so Kraken mantle/fins get a razor-sharp 1px #181425 outline
	var body_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	body_img.fill(Color(0.0, 0.0, 0.0, 0.0))

	var col_dark := Color(0.231, 0.090, 0.208, 1.0) # #3b1735
	var col_mid := Color(0.431, 0.133, 0.275, 1.0)  # #6e2246
	var col_lit := Color(0.620, 0.216, 0.345, 1.0)  # #9e3758
	var col_hi := Color(0.831, 0.408, 0.478, 1.0)   # #d4687a
	var eye_glow := Color(1.000, 0.878, 0.259, 1.0) # #ffe042
	var eye_hot := Color(1.000, 0.980, 0.720, 1.0)
	var beak_bone := Color(0.961, 0.922, 0.839, 1.0)
	var beak_shad := Color(0.761, 0.690, 0.588, 1.0)

	if hit_flash:
		col_dark = Color(0.780, 0.440, 0.520, 1.0)
		col_mid = Color(0.941, 0.680, 0.720, 1.0)
		col_lit = Color(0.988, 0.860, 0.880, 1.0)
		col_hi = Color(1.000, 0.965, 0.960, 1.0)

	# Curved lateral mantle fins / ear-horns (y = 14..29)
	for side in [-1.0, 1.0]:
		for step_i in range(18):
			var t: float = float(step_i) / 17.0
			var fx: float = 31.5 + side * lerpf(9.0, 22.5, t)
			var fy: float = lerpf(23.0, 14.0, pow(t, 0.8)) + sin(t * PI) * 2.5
			var fr: float = lerpf(4.8, 1.4, t)
			var fc: Color = col_lit if (side < 0.0 and t < 0.7) else col_mid
			if t > 0.65 and side > 0.0:
				fc = col_dark
			_circle(body_img, fx, fy, fr, fc)
			if side < 0.0 and t < 0.8:
				_circle(body_img, fx - 0.8, fy - 0.8, fr * 0.48, col_hi)

	# Bulbous Kraken hood / mantle (y = 7..47)
	for y in range(7, 48):
		var t: float = float(y - 7) / 40.0
		var half_w: float = 0.0
		if t < 0.18:
			var st: float = t / 0.18
			half_w = lerpf(2.2, 11.5, sqrt(st))
		elif t < 0.58:
			var mt: float = (t - 0.18) / 0.40
			half_w = 11.5 + sin(mt * PI) * 6.5
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
			# Subtle horizontal ridge folds across dome
			if (y == 16 or y == 24) and adx < half_w * 0.72:
				c = col_dark if norm_x > 0.0 else col_mid
			_px(body_img, x, y, c)

	# Crown highlight crest
	_circle(body_img, 28.5, 16.0, 4.2, col_hi)
	_circle(body_img, 27.5, 14.5, 2.2, col_hi.lightened(0.15))

	# Menacing dark brow ridge + glowing yellow slit eyes (#ffe042)
	for side_x in [-1, 1]:
		var ex_c: int = 31 + side_x * 6
		if side_x > 0:
			ex_c = 32 + 5
		else:
			ex_c = 31 - 5
		# Angled dark brow shadow
		for bx in range(ex_c - 3, ex_c + 4):
			var brow_y: int = 33 + (1 if (bx - ex_c) * side_x < 0 else 0)
			_px(body_img, bx, brow_y, col_dark)
			_px(body_img, bx, brow_y - 1, OUTLINE_COLOR)
		# Eye socket & glowing iris
		for ey in range(34, 39):
			for ex in range(ex_c - 2, ex_c + 3):
				if abs(ex - ex_c) + abs(ey - 36) <= 3:
					var ec: Color = eye_glow
					if ey == 34:
						ec = eye_hot
					if ex == ex_c and ey >= 35 and ey <= 37:
						ec = OUTLINE_COLOR # Fierce vertical slit pupil
					_px(body_img, ex, ey, ec)

	# Jagged beak / maw emerging at the waterline (y = 41..47)
	for my in range(41, 48):
		var mw: int = 6 if my < 45 else 4
		for mx in range(32 - mw, 32 + mw):
			_px(body_img, mx, my, OUTLINE_COLOR)
	# Ivory beak fangs
	for fx in [27, 29, 31, 33, 35]:
		var fang_h: int = 3 if fx == 31 else 2
		for fy in range(41, 41 + fang_h):
			_px(body_img, fx, fy, beak_bone if fy == 41 else beak_shad)
	for fx in [28, 30, 32, 34]:
		_px(body_img, fx, 46, beak_shad)
		_px(body_img, fx, 45, beak_bone)

	_apply_pixel_outline(body_img, OUTLINE_COLOR)

	# Composite outlined Kraken body onto water foam vortex
	for y in range(h):
		for x in range(w):
			var bp: Color = body_img.get_pixel(x, y)
			if bp.a > 0.0:
				img.set_pixel(x, y, bp)

	var tex := ImageTexture.create_from_image(img)
	_kraken_body_cache[cache_key] = tex
	return tex


static func bake_kraken_tentacle_texture(frame: int = 0, hit_flash: bool = false) -> ImageTexture:
	var safe_frame: int = clampi(frame, 0, 2)
	var cache_key: String = "%d_%d" % [safe_frame, 1 if hit_flash else 0]
	if _kraken_tentacle_cache.has(cache_key):
		return _kraken_tentacle_cache[cache_key]

	var w: int = 32
	var h: int = 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	# Small water foam ring at base (y = 24..30)
	var foam_white := Color(0.965, 0.984, 1.0, 0.90)
	var foam_aqua := Color(0.451, 0.933, 0.890, 0.80)
	for y in range(23, 31):
		for x in range(5, 27):
			var dx: float = (float(x) - 15.5) / 8.5
			var dy: float = (float(y) - 26.8) / 2.8
			var r: float = sqrt(dx * dx + dy * dy)
			if r >= 0.65 and r <= 1.05:
				_px(img, x, y, foam_white if (x + y) % 2 == 0 else foam_aqua)

	var body_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	body_img.fill(Color(0.0, 0.0, 0.0, 0.0))

	var col_dark := Color(0.231, 0.090, 0.208, 1.0) # #3b1735
	var col_mid := Color(0.431, 0.133, 0.275, 1.0)  # #6e2246
	var col_lit := Color(0.620, 0.216, 0.345, 1.0)  # #9e3758
	var col_hi := Color(0.831, 0.408, 0.478, 1.0)   # #d4687a
	var sucker := Color(0.949, 0.722, 0.635, 1.0)   # #f2b8a2
	var sucker_dim := Color(0.769, 0.451, 0.412, 1.0)

	if hit_flash:
		col_dark = Color(0.780, 0.440, 0.520, 1.0)
		col_mid = Color(0.941, 0.680, 0.720, 1.0)
		col_lit = Color(0.988, 0.860, 0.880, 1.0)
		col_hi = Color(1.000, 0.965, 0.960, 1.0)

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
		_circle(body_img, p.x, p.y, rad, col_mid)
		_circle(body_img, p.x - rad * 0.28, p.y - rad * 0.18, rad * 0.65, col_lit)
		_circle(body_img, p.x + rad * 0.32, p.y + rad * 0.20, rad * 0.52, col_dark)
		if rad >= 2.0:
			_px(body_img, int(round(p.x - rad * 0.48)), int(round(p.y - rad * 0.35)), col_hi)

	# Bright suckers (#f2b8a2) along the inner curve
	for idx_s in [6, 12, 18, 24]:
		var p: Vector2 = spine[idx_s]
		var next_p: Vector2 = spine[mini(steps - 1, idx_s + 1)]
		var tang: Vector2 = (next_p - p).normalized()
		var inner_n := Vector2(tang.y, -tang.x)
		if inner_n.x < 0.0:
			inner_n = -inner_n
		var sp: Vector2 = p + inner_n * lerpf(2.2, 1.1, float(idx_s) / float(steps))
		_circle(body_img, sp.x, sp.y, 1.35, sucker)
		_px(body_img, int(round(sp.x)), int(round(sp.y)), sucker_dim)

	_apply_pixel_outline(body_img, OUTLINE_COLOR)

	for y in range(h):
		for x in range(w):
			var bp: Color = body_img.get_pixel(x, y)
			if bp.a > 0.0:
				img.set_pixel(x, y, bp)

	var tex := ImageTexture.create_from_image(img)
	_kraken_tentacle_cache[cache_key] = tex
	return tex


static func bake_fort_texture(hit_flash: bool = false) -> ImageTexture:
	var cache_key: int = 1 if hit_flash else 0
	if _fort_cache.has(cache_key):
		return _fort_cache[cache_key]

	var w: int = 48
	var h: int = 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	var cx: float = 23.5
	var cy: float = 23.5

	var stone_dark := Color(0.467, 0.435, 0.420, 1.0)
	var stone_mid := Color(0.718, 0.686, 0.635, 1.0)
	var stone_lit := Color(0.867, 0.839, 0.776, 1.0)
	var stone_hi := Color(0.953, 0.929, 0.875, 1.0)
	var wood_dark := Color(0.353, 0.196, 0.137, 1.0)
	var wood_mid := Color(0.545, 0.329, 0.216, 1.0)
	var wood_lit := Color(0.722, 0.467, 0.302, 1.0)
	var iron_dark := Color(0.188, 0.204, 0.251, 1.0)
	var iron_mid := Color(0.329, 0.361, 0.427, 1.0)
	var iron_hi := Color(0.659, 0.706, 0.776, 1.0)
	var brass := Color(0.933, 0.714, 0.220, 1.0)

	if hit_flash:
		stone_dark = Color(0.78, 0.72, 0.62, 1.0)
		stone_mid = Color(0.95, 0.90, 0.78, 1.0)
		stone_lit = Color(1.0, 0.97, 0.88, 1.0)

	# 1. Octagonal bright limestone fortress ring + wooden gun deck
	for y in range(3, h - 3):
		for x in range(3, w - 3):
			var dx: float = float(x) - cx
			var dy: float = float(y) - cy
			var adx: float = absf(dx)
			var ady: float = absf(dy)
			var oct_d: float = maxf(maxf(adx, ady), (adx + ady) * 0.7071)
			var rad_d: float = sqrt(dx * dx + dy * dy)

			if oct_d <= 18.8:
				if oct_d >= 12.2:
					# Limestone parapet ring with ashlar stone blocks & radial bevel
					var c: Color = stone_mid
					if oct_d < 14.5:
						c = stone_lit
					elif oct_d > 17.3:
						c = stone_dark
					var ang_bin: int = int(floor((atan2(dy, dx) + PI) / (TAU / 16.0)))
					if (ang_bin % 2 == 0 and absf(oct_d - 15.5) < 0.45) or absf(wrapf(atan2(dy, dx), 0.0, TAU / 8.0)) < 0.04:
						c = stone_dark
					_px(img, x, y, c)
				else:
					# Sunken wooden gun deck
					var c: Color = wood_mid if ((y / 3) % 2 == 0) else wood_lit
					if y % 3 == 0:
						c = wood_dark
					if oct_d >= 11.1:
						c = wood_dark
					elif absf(rad_d - 8.5) <= 0.8:
						c = iron_dark # Iron turret traverse rail
					_px(img, x, y, c)

	# 2. 8 crisp stone crenellations (merlons) around the octagonal perimeter
	for m in range(8):
		var ang: float = (float(m) / 8.0) * TAU + PI / 8.0
		var mx: float = cx + cos(ang) * 16.8
		var my: float = cy + sin(ang) * 16.8
		_rect(img, int(round(mx)) - 2, int(round(my)) - 2, 5, 5, stone_dark)
		_rect(img, int(round(mx)) - 1, int(round(my)) - 1, 3, 3, stone_hi)

	# 3. 4 warm glowing corner torches / braziers on parapet corners
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var tx: int = int(round(cx + sx * 10.6))
			var ty: int = int(round(cy + sy * 10.6))
			_rect(img, tx - 2, ty - 2, 4, 4, iron_dark)
			_rect(img, tx - 1, ty - 1, 3, 3, Color(1.0, 0.54, 0.14, 1.0))
			_px(img, tx, ty, Color(1.0, 0.94, 0.52, 1.0))

	# 4. Dark rotating gun carriage at center + heavy cannon barrel pointing +X
	_rect(img, 17, 19, 10, 10, wood_dark)
	_rect(img, 18, 20, 8, 8, iron_dark)
	_rect(img, 19, 21, 6, 6, iron_mid)
	# Trunnion pins & brass wheels
	_rect(img, 20, 18, 4, 2, brass)
	_rect(img, 20, 28, 4, 2, brass)

	# Heavy fort cannon barrel extending right (+X) to x = 42
	for x in range(18, 43):
		var half_b: int = 3 if x < 29 else 2
		if x >= 40:
			half_b = 3 # Flared muzzle ring
		for y in range(24 - half_b, 24 + half_b):
			var bc: Color = iron_mid
			if y == 24 - half_b:
				bc = iron_hi
			elif y == 24 + half_b - 1:
				bc = iron_dark
			if x == 29 or x >= 41:
				bc = brass if y > 24 - half_b else Color(1.0, 0.92, 0.52, 1.0)
			_px(img, x, y, bc)
	# Breech cascabel knob
	_rect(img, 16, 22, 2, 4, brass)

	_apply_pixel_outline(img, OUTLINE_COLOR)

	var tex := ImageTexture.create_from_image(img)
	_fort_cache[cache_key] = tex
	return tex

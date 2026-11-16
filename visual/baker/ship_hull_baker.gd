extends RefCounted
## Generates 2D pixel-art sprite-stack ship layers (64x32) for 3 ship classes
## (Sloop, Brigantine, Frigate) across all factions.

const Draw = preload("res://visual/baker/pixel_draw_utils.gd")

const SHIP_TEX_WIDTH: int = 64
const SHIP_TEX_HEIGHT: int = 32

const HULL_SPECS: Dictionary = {
	0: { "tier": 0, "x_min": 14, "x_max": 49, "max_hw": 6.4, "stern_end": 22, "fore_start": 41, "masts": [31], "yard_halfs": [8], "sail_halfs": [7], "gunport_xs": [25, 32, 39], "bowsprit_len": 6 },
	1: { "tier": 1, "x_min": 9, "x_max": 53, "max_hw": 8.0, "stern_end": 20, "fore_start": 43, "masts": [26, 41], "yard_halfs": [9, 7], "sail_halfs": [8, 6], "gunport_xs": [22, 29, 36, 43], "bowsprit_len": 7 },
	2: { "tier": 2, "x_min": 5, "x_max": 57, "max_hw": 9.8, "stern_end": 18, "fore_start": 45, "masts": [18, 32, 46], "yard_halfs": [7, 11, 8], "sail_halfs": [6, 10, 7], "gunport_xs": [19, 25, 31, 37, 43, 49], "bowsprit_len": 5 }
}

const FACTION_PALETTES: Dictionary = {
	Contracts.ShipFaction.PLAYER: {
		"trim": Color(0.957, 0.706, 0.106, 1.0),
		"rail": Color(0.957, 0.922, 0.835, 1.0),
		"sail_a": Color(0.796, 0.235, 0.220, 1.0),
		"sail_b": Color(0.961, 0.922, 0.839, 1.0),
		"sail_c": Color(0.878, 0.624, 0.243, 1.0),
		"flag": Color(0.796, 0.235, 0.220, 1.0),
		"flag_emblem": Color(0.961, 0.922, 0.839, 1.0)
	},
	Contracts.ShipFaction.PIRATE: {
		"trim": Color(0.820, 0.220, 0.235, 1.0),
		"rail": Color(0.320, 0.255, 0.300, 1.0),
		"sail_a": Color(0.145, 0.125, 0.165, 1.0),
		"sail_b": Color(0.686, 0.145, 0.188, 1.0),
		"sail_c": Color(0.240, 0.195, 0.235, 1.0),
		"flag": Color(0.118, 0.106, 0.145, 1.0),
		"flag_emblem": Color(0.961, 0.933, 0.863, 1.0)
	},
	Contracts.ShipFaction.MERCHANT: {
		"trim": Color(0.957, 0.769, 0.263, 1.0),
		"rail": Color(0.949, 0.922, 0.851, 1.0),
		"sail_a": Color(0.180, 0.435, 0.725, 1.0),
		"sail_b": Color(0.961, 0.773, 0.275, 1.0),
		"sail_c": Color(0.965, 0.953, 0.910, 1.0),
		"flag": Color(0.961, 0.773, 0.275, 1.0),
		"flag_emblem": Color(0.180, 0.435, 0.725, 1.0)
	},
	Contracts.ShipFaction.NAVY: {
		"trim": Color(0.969, 0.745, 0.145, 1.0),
		"rail": Color(0.969, 0.745, 0.145, 1.0),
		"sail_a": Color(0.118, 0.235, 0.565, 1.0),
		"sail_b": Color(0.949, 0.729, 0.212, 1.0),
		"sail_c": Color(0.929, 0.949, 0.988, 1.0),
		"flag": Color(0.118, 0.235, 0.565, 1.0),
		"flag_emblem": Color(0.969, 0.745, 0.145, 1.0)
	},
	Contracts.ShipFaction.NEUTRAL: {
		"trim": Color(0.851, 0.627, 0.400, 1.0),
		"rail": Color(0.922, 0.867, 0.753, 1.0),
		"sail_a": Color(0.918, 0.875, 0.776, 1.0),
		"sail_b": Color(0.722, 0.588, 0.435, 1.0),
		"sail_c": Color(0.957, 0.929, 0.867, 1.0),
		"flag": Color(0.851, 0.627, 0.400, 1.0),
		"flag_emblem": Color(0.957, 0.929, 0.867, 1.0)
	}
}


static func normalize_faction(faction: int) -> int:
	return faction if FACTION_PALETTES.has(faction) else Contracts.ShipFaction.PLAYER


static func get_sail_layer_range(layer_count: int = 24) -> Vector2i:
	var safe_layers: int = maxi(12, layer_count)
	var cabin_end: int = int(round(0.56 * float(safe_layers - 1)))
	return Vector2i(cabin_end + 2, safe_layers - 3)


static func bake_ship_layers(faction: int = 0, layer_count: int = 20, hull_tier: int = 0) -> Array[ImageTexture]:
	var safe_layers: int = maxi(12, layer_count)
	var safe_tier: int = clampi(hull_tier, 0, 2)
	var safe_faction: int = normalize_faction(faction)

	var layers: Array[ImageTexture] = []
	var colors: Dictionary = FACTION_PALETTES[safe_faction]
	var spec: Dictionary = HULL_SPECS[safe_tier]

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
		var img := Draw.create_canvas(SHIP_TEX_WIDTH, SHIP_TEX_HEIGHT)
		var apply_outline: bool = false

		if layer_idx <= keel_end:
			var k_frac: float = float(layer_idx) / float(maxi(1, keel_end))
			_draw_keel_and_lower_hull(img, k_frac, spec)
			apply_outline = (layer_idx == 1 or layer_idx == keel_end)
		elif layer_idx <= hull_lower_end:
			var h_step: int = layer_idx - keel_end
			var h_steps: int = maxi(1, hull_lower_end - keel_end)
			_draw_lower_bulwark(img, h_step, h_steps, spec, colors)
			apply_outline = (layer_idx == hull_lower_end)
		elif layer_idx <= deck_end:
			var d_step: int = layer_idx - hull_lower_end - 1
			var d_steps: int = maxi(1, deck_end - hull_lower_end)
			_draw_main_deck_and_rails(img, d_step, d_steps, spec, colors)
			apply_outline = (layer_idx == hull_lower_end + 1 or layer_idx == deck_end)
		elif layer_idx <= cabin_end:
			var c_step: int = layer_idx - deck_end - 1
			var c_steps: int = maxi(1, cabin_end - deck_end)
			_draw_cabin_and_castles(img, c_step, c_steps, spec, colors)
			apply_outline = (layer_idx == cabin_end)
		else:
			_draw_masts_and_sails_tiered(
				img, layer_idx, yard_layer, sail_range.x, sail_range.y,
				crow_nest_layer, flag_layer, safe_faction, spec, colors
			)
			apply_outline = (
				layer_idx == yard_layer
				or layer_idx == sail_range.x
				or layer_idx == sail_mid
				or layer_idx == flag_layer
			)

		if apply_outline:
			Draw.apply_pixel_outline(img, Draw.OUTLINE_COLOR)
		layers.append(ImageTexture.create_from_image(img))

	return layers


static func _hull_half_width_spec(x: int, spec: Dictionary) -> float:
	var x_min: int = int(spec["x_min"])
	var x_max: int = int(spec["x_max"])
	if x < x_min or x > x_max:
		return 0.0
	var t: float = float(x - x_min) / float(maxi(1, x_max - x_min))
	var max_hw: float = float(spec["max_hw"])
	var curve: float = sin(pow(t, 0.72) * PI * 0.85 + 0.44)
	return clampf(curve * max_hw, 0.7, max_hw)


static func _draw_keel_and_lower_hull(img: Image, k_frac: float, spec: Dictionary) -> void:
	var scale_w: float = lerpf(0.36, 0.86, k_frac)
	var hull_dark := Color(0.247, 0.145, 0.137, 1.0)
	var hull_mid := Color(0.376, 0.216, 0.165, 1.0)
	var hull_lit := Color(0.490, 0.294, 0.212, 1.0)
	var cy: float = float(SHIP_TEX_HEIGHT) * 0.5 - 0.5

	for x in range(int(spec["x_min"]), int(spec["x_max"]) + 1):
		var hw: float = _hull_half_width_spec(x, spec) * scale_w
		if hw <= 0.4:
			continue
		for y in range(1, SHIP_TEX_HEIGHT - 1):
			if absf(float(y) - cy) <= hw:
				var c: Color = hull_mid if k_frac >= 0.45 else hull_dark
				if float(y) < cy - hw * 0.35 and k_frac >= 0.45:
					c = hull_lit
				img.set_pixel(x, y, c)


static func _draw_lower_bulwark(img: Image, step: int, steps: int, spec: Dictionary, colors: Dictionary) -> void:
	var flare: float = lerpf(0.92, 0.99, float(step) / float(maxi(1, steps)))
	var hull_side_dark := Color(0.420, 0.243, 0.173, 1.0)
	var hull_side := Color(0.561, 0.337, 0.231, 1.0)
	var hull_lit := Color(0.761, 0.510, 0.333, 1.0)
	var trim_col: Color = colors["trim"]
	var tier: int = int(spec["tier"])
	var gunport_xs: Array = spec["gunport_xs"]
	var cy: float = float(SHIP_TEX_HEIGHT) * 0.5 - 0.5

	for x in range(int(spec["x_min"]) - 1, int(spec["x_max"]) + 2):
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
			if (step == steps or (tier == 2 and step == 1)) and dy > hw - 1.5:
				if tier == 2 and step == steps and (x % 3 == 0):
					c = trim_col
				for gx_var in gunport_xs:
					if x == int(gx_var) and dy > hw - 1.4:
						c = Draw.OUTLINE_COLOR
						break
			img.set_pixel(x, y, c)


static func _draw_main_deck_and_rails(img: Image, step: int, steps: int, spec: Dictionary, colors: Dictionary) -> void:
	var flare: float = lerpf(1.00, 1.05, float(step) / float(maxi(1, steps - 1)))
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
					bc = Draw.SUNLIGHT_HIGHLIGHT
				img.set_pixel(x, y, bc)
			else:
				var pc: Color = deck_light if ((y / 2) % 2 == 0) else deck_mid
				if y % 3 == 0:
					pc = deck_seam
				var mid_x: int = (x_min + x_max) / 2 + 2
				if step == 1 and abs(x - mid_x) <= 3 and dy <= 2.2:
					pc = Color(0.28, 0.17, 0.14, 1.0) if (x % 2 == 0) else deck_seam
				img.set_pixel(x, y, pc)

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
	var cy: float = float(SHIP_TEX_HEIGHT) * 0.5 - 0.5
	var is_roof: bool = (step >= steps - 1)

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
					if x == cab_start + 1 and (int(dy) == 2 or int(dy) == 3):
						c = lantern
					img.set_pixel(x, y, c)
			elif x >= cab_start + 2 and x <= cab_end - 2 and dy <= hw - 1.6:
				img.set_pixel(x, y, trim_col if (x == cab_start + 2 or dy > hw - 2.5) else wood_light)

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

	if step == 1:
		var wx: int = cab_end + 1
		for wy in range(14, 18):
			img.set_pixel(wx, wy, trim_col if (wy == 14 or wy == 17) else wood_dark)

	for mx_var in spec["masts"]:
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
				var sc: Color = _pick_clean_sail_band(y, sail_prog, faction, colors["sail_a"], colors["sail_b"], colors["sail_c"])
				img.set_pixel(sx, y, sc)
				img.set_pixel(sx - 1, y, sc.darkened(0.10))

			if faction == Contracts.ShipFaction.PIRATE and m_i == main_mast_idx and abs(layer_idx - sail_mid) <= 1:
				var skull_x: int = mx + (3 if tier >= 1 else 2)
				for sy in range(14, 18):
					var is_eye: bool = (layer_idx == sail_mid and (sy == 15 or sy == 16))
					img.set_pixel(skull_x, sy, Draw.OUTLINE_COLOR if is_eye else colors["flag_emblem"])

		if tier == 2 and (faction == Contracts.ShipFaction.NAVY or faction == Contracts.ShipFaction.MERCHANT):
			var main_sh: int = maxi(3, int(sail_halfs[main_mast_idx]) - taper)
			img.set_pixel(main_mx + 1, 16 - main_sh, colors["trim"])
			img.set_pixel(main_mx + 1, 16 + main_sh - 1, colors["trim"])
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
			img.set_pixel(fx, wave_y, colors["flag_emblem"] if fx == main_mx - 3 else colors["flag"])
			if fx >= main_mx - 4:
				img.set_pixel(fx, wave_y + 1, colors["flag"])


static func _pick_clean_sail_band(y: int, sail_prog: float, faction: int, a: Color, b: Color, c: Color) -> Color:
	var band: int = (y / 3) % 3
	var base: Color = a
	if faction == Contracts.ShipFaction.PIRATE:
		base = a if ((y / 3) % 2 == 0) else b
	elif band == 1:
		base = b
	elif band == 2:
		base = c
	return base.lightened(0.12) if sail_prog > 0.65 else base

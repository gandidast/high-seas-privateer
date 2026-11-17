extends RefCounted
## Generates 2D pixel-art sprite-stack ship layers (64x32) for all 9 ship classes
## (Sloop, Schooner, Brigantine, Frigate, Corsair Clipper, War Galleon,
## Corsair Xebec, Ironclad, Man-o'-War) across all factions.

const Draw = preload("res://visual/baker/pixel_draw_utils.gd")

const SHIP_TEX_WIDTH: int = 64
const SHIP_TEX_HEIGHT: int = 32

const HULL_SPECS: Dictionary = {
	# 0: Sloop ("Schaluppe") — compact 1-mast sloop
	0: {
		"tier": 0, "x_min": 15, "x_max": 48, "max_hw": 6.2,
		"stern_end": 23, "fore_start": 40,
		"masts": [31], "yard_halfs": [8], "sail_halfs": [7],
		"gunport_xs": [26, 32, 38], "bowsprit_len": 5, "raked": false
	},
	# 1: Schooner ("Schoner") — sleek 2-mast schooner (longer than sloop, narrower than brig)
	1: {
		"tier": 1, "x_min": 10, "x_max": 53, "max_hw": 6.8,
		"stern_end": 19, "fore_start": 44,
		"masts": [25, 40], "yard_halfs": [8, 7], "sail_halfs": [7, 6],
		"gunport_xs": [22, 29, 36, 43], "bowsprit_len": 7, "raked": false
	},
	# 2: Brigantine ("Brigg") — stout 2-mast brig
	2: {
		"tier": 2, "x_min": 9, "x_max": 53, "max_hw": 8.4,
		"stern_end": 20, "fore_start": 43,
		"masts": [25, 41], "yard_halfs": [10, 8], "sail_halfs": [9, 7],
		"gunport_xs": [21, 28, 35, 42], "bowsprit_len": 6, "raked": false
	},
	# 3: Frigate ("Fregatte") — classic 3-mast warship
	3: {
		"tier": 3, "x_min": 6, "x_max": 56, "max_hw": 9.8,
		"stern_end": 18, "fore_start": 45,
		"masts": [18, 31, 45], "yard_halfs": [7, 11, 8], "sail_halfs": [6, 10, 7],
		"gunport_xs": [19, 25, 31, 37, 43, 49], "bowsprit_len": 5, "raked": false
	},
	# 4: Corsair Clipper ("Kaper-Klipper") — razor-sleek narrow fast interceptor with 2 raked sails + sharp bowsprit
	4: {
		"tier": 4, "x_min": 7, "x_max": 54, "max_hw": 6.4,
		"stern_end": 16, "fore_start": 46,
		"masts": [23, 39], "yard_halfs": [9, 8], "sail_halfs": [8, 7],
		"gunport_xs": [21, 28, 35, 42], "bowsprit_len": 8, "raked": true
	},
	# 5: War Galleon ("Kriegsgaleone") — massive wide dreadnought hull filling 64x32
	5: {
		"tier": 5, "x_min": 2, "x_max": 61, "max_hw": 12.0,
		"stern_end": 18, "fore_start": 45,
		"masts": [16, 32, 47], "yard_halfs": [9, 13, 10], "sail_halfs": [8, 12, 9],
		"gunport_xs": [15, 20, 25, 30, 35, 40, 45, 50, 54], "bowsprit_len": 3, "raked": false
	},
	# 6: Corsair Xebec ("Korsaren-Schebecke") — sleek raked 3-mast hunter with ramming beak
	6: {
		"tier": 6, "x_min": 5, "x_max": 55, "max_hw": 6.9,
		"stern_end": 16, "fore_start": 45,
		"masts": [17, 32, 46], "yard_halfs": [7, 10, 8], "sail_halfs": [6, 9, 7],
		"gunport_xs": [20, 26, 32, 38, 44, 49], "bowsprit_len": 7, "raked": true
	},
	# 7: Ironclad ("Panzer-Monitor") — dark riveted iron-armored hull, ram prow, casemate & smokestack
	7: {
		"tier": 7, "x_min": 4, "x_max": 56, "max_hw": 10.6,
		"stern_end": 18, "fore_start": 44,
		"masts": [24], "yard_halfs": [8], "sail_halfs": [7],
		"gunport_xs": [18, 24, 30, 36, 42, 48], "bowsprit_len": 4, "raked": false,
		"smokestack_x": 38
	},
	# 8: Man-o'-War ("Linienschiff") — grand 3-deck flagship larger & heavier than War Galleon
	8: {
		"tier": 8, "x_min": 2, "x_max": 60, "max_hw": 13.0,
		"stern_end": 18, "fore_start": 45,
		"masts": [15, 32, 48], "yard_halfs": [10, 14, 11], "sail_halfs": [9, 13, 10],
		"gunport_xs": [13, 18, 23, 28, 33, 38, 43, 48, 53], "bowsprit_len": 3, "raked": false
	}
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
	var safe_tier: int = clampi(hull_tier, 0, 8)
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
	var tier: int = int(spec["tier"])
	var curve: float
	if tier == 4:
		# Razor-sleek Corsair Clipper: sharp bow & stern taper
		curve = sin(pow(t, 0.78) * PI * 0.88 + 0.34)
	elif tier == 6:
		# Sleek Corsair Xebec: narrow raked hull with pointed ramming bow
		curve = sin(pow(t, 0.76) * PI * 0.88 + 0.36)
	elif tier == 7:
		# Broad armored Ironclad monitor hull
		curve = sin(pow(t, 0.66) * PI * 0.84 + 0.48)
	elif tier == 8:
		# Grand 3-deck Man-o'-War: fullest beam and heavy stern/bow quarters
		curve = sin(pow(t, 0.58) * PI * 0.80 + 0.56)
	elif tier == 5:
		# Massive War Galleon: broad dreadnought beam with heavy castles
		curve = sin(pow(t, 0.65) * PI * 0.82 + 0.50)
	else:
		curve = sin(pow(t, 0.72) * PI * 0.85 + 0.44)
	return clampf(curve * max_hw, 0.7, max_hw)


static func _draw_keel_and_lower_hull(img: Image, k_frac: float, spec: Dictionary) -> void:
	var scale_w: float = lerpf(0.36, 0.86, k_frac)
	var tier: int = int(spec["tier"])
	var is_ironclad: bool = (tier == 7)
	var hull_dark := Color(0.145, 0.165, 0.210, 1.0) if is_ironclad else Color(0.247, 0.145, 0.137, 1.0)
	var hull_mid := Draw.IRON_DARK if is_ironclad else Color(0.376, 0.216, 0.165, 1.0)
	var hull_lit := Draw.IRON_MID if is_ironclad else Color(0.490, 0.294, 0.212, 1.0)
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
				Draw.px(img, x, y, c)

	if is_ironclad and k_frac >= 0.35:
		var x_max: int = int(spec["x_max"])
		for rx in range(x_max + 1, mini(SHIP_TEX_WIDTH - 2, x_max + 5)):
			Draw.px(img, rx, 15, hull_lit)
			Draw.px(img, rx, 16, hull_mid)


static func _draw_lower_bulwark(img: Image, step: int, steps: int, spec: Dictionary, colors: Dictionary) -> void:
	var flare: float = lerpf(0.92, 0.99, float(step) / float(maxi(1, steps)))
	var tier: int = int(spec["tier"])
	var is_ironclad: bool = (tier == 7)
	var hull_side_dark := Draw.IRON_DARK if is_ironclad else Color(0.420, 0.243, 0.173, 1.0)
	var hull_side := Draw.IRON_MID if is_ironclad else Color(0.561, 0.337, 0.231, 1.0)
	var hull_lit := Draw.IRON_HIGH if is_ironclad else Color(0.761, 0.510, 0.333, 1.0)
	var trim_col: Color = colors["trim"]
	var has_double_deck: bool = (tier == 3 or tier == 5 or tier == 8)
	var has_gilded_trim: bool = (tier >= 3 and tier != 7)
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
			if is_ironclad and dy > hw - 1.6:
				if x % 4 == 0:
					c = hull_side_dark
				elif x % 4 == 2 and step == steps:
					c = hull_lit
			if (step == steps or (has_double_deck and step == 1) or (tier == 8 and step >= 1)) and dy > hw - 1.5:
				if has_gilded_trim and step == steps and (x % 3 == 0 or (tier == 5 or tier == 8) and x % 2 == 0):
					c = trim_col
				elif is_ironclad and step == steps and x % 6 == 0:
					c = trim_col
				for gx_var in gunport_xs:
					var gx: int = int(gx_var)
					var hit_port: bool = (x == gx) or ((tier == 5 or tier == 8) and step == steps and x == gx + 1)
					if hit_port and dy > hw - 1.4:
						c = Draw.OUTLINE_COLOR
						break
			Draw.px(img, x, y, c)


static func _draw_main_deck_and_rails(img: Image, step: int, steps: int, spec: Dictionary, colors: Dictionary) -> void:
	var flare: float = lerpf(1.00, 1.05, float(step) / float(maxi(1, steps - 1)))
	var tier: int = int(spec["tier"])
	var is_ironclad: bool = (tier == 7)
	var hull_side_dark := Draw.IRON_DARK if is_ironclad else Color(0.431, 0.247, 0.173, 1.0)
	var hull_side := Draw.IRON_MID if is_ironclad else Color(0.561, 0.337, 0.231, 1.0)
	var deck_mid := Color(0.275, 0.295, 0.355, 1.0) if is_ironclad else Color(0.722, 0.447, 0.314, 1.0)
	var deck_light := Color(0.365, 0.395, 0.465, 1.0) if is_ironclad else Color(0.835, 0.596, 0.384, 1.0)
	var deck_seam := Draw.IRON_DARK if is_ironclad else Color(0.510, 0.302, 0.208, 1.0)
	var trim_col: Color = colors["trim"]
	var rail_col: Color = Draw.IRON_HIGH if is_ironclad else colors["rail"]

	var x_min: int = maxi(1, int(spec["x_min"]) - 1)
	var x_max: int = mini(SHIP_TEX_WIDTH - 2, int(spec["x_max"]) + 1)
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
				var in_stern: bool = (x <= stern_end) and not is_ironclad
				var in_fore: bool = (tier >= 2 and tier != 4 and tier != 6 and tier != 7 and x >= fore_start)
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
					if is_ironclad:
						bc = trim_col if (x >= x_max - 4 or x % 6 == 0) else (rail_col if x % 2 == 0 else hull_side)
					elif x >= x_max - 4 or x <= x_min + 2 or (tier >= 3 and x % 3 == 0):
						bc = trim_col
					else:
						bc = rail_col if (x % 2 == 0 or tier >= 2) else deck_light
				elif float(y) < cy - hw + 1.3:
					bc = Draw.IRON_HIGH if is_ironclad else Draw.SUNLIGHT_HIGHLIGHT
				Draw.px(img, x, y, bc)
			else:
				var pc: Color = deck_light if ((y / 2) % 2 == 0) else deck_mid
				if is_ironclad:
					if x % 5 == 0 or y % 4 == 0:
						pc = deck_seam
					elif x % 5 == 2 and y % 4 == 2:
						pc = Draw.IRON_HIGH
				elif y % 3 == 0:
					pc = deck_seam
				var mid_x: int = (x_min + x_max) / 2 + 2
				if step == 1 and not is_ironclad and abs(x - mid_x) <= 3 and dy <= 2.2:
					pc = Color(0.28, 0.17, 0.14, 1.0) if (x % 2 == 0) else deck_seam
				Draw.px(img, x, y, pc)

	if step >= 1:
		if is_ironclad:
			# Heavy pointed iron ramming prow
			var ram_end: int = mini(SHIP_TEX_WIDTH - 2, x_max + 5)
			for rx in range(x_max - 1, ram_end + 1):
				Draw.px(img, rx, 15, Draw.IRON_HIGH if rx >= ram_end - 1 else Draw.IRON_MID)
				Draw.px(img, rx, 16, Draw.IRON_MID if rx >= ram_end - 1 else Draw.IRON_DARK)
				if rx <= x_max + 2:
					Draw.px(img, rx, 14, trim_col if rx == x_max else Draw.IRON_MID)
					Draw.px(img, rx, 17, trim_col if rx == x_max else Draw.IRON_DARK)
		else:
			var b_len: int = int(spec["bowsprit_len"])
			var b_end: int = mini(SHIP_TEX_WIDTH - 2, x_max + b_len - (steps - 1 - step))
			for bx in range(x_max - 2, b_end + 1):
				if (tier == 4 or tier == 6) and bx >= b_end - 2:
					# Sharp lance-like bowsprit / ramming beak tip for Corsair Clipper & Xebec
					Draw.px(img, bx, 15, trim_col if bx == b_end else deck_light)
					if tier == 6:
						Draw.px(img, bx, 16, Draw.IRON_HIGH if bx == b_end else Draw.IRON_MID)
				else:
					Draw.px(img, bx, 15, deck_light)
					Draw.px(img, bx, 16, hull_side)
			if tier == 6 and step == steps - 1:
				# Twin bow-slot chaser mounts on Corsair Xebec
				Draw.px(img, x_max - 1, 14, trim_col)
				Draw.px(img, x_max - 1, 17, trim_col)
			elif tier >= 3 and step == steps - 1:
				Draw.px(img, x_max + 1, 15, trim_col)
				Draw.px(img, x_max + 1, 16, trim_col)


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
	var rich_trim: bool = (tier >= 3)

	if tier == 7:
		# Ironclad armored casemate citadel + base of smokestack
		var case_start: int = stern_end - 2 + step
		var case_end: int = fore_start - 2 - step
		var case_hw: float = maxf(3.0, 6.4 - float(step) * 0.9)
		for x in range(case_start, case_end + 1):
			for y in range(2, SHIP_TEX_HEIGHT - 2):
				var dy: float = absf(float(y) - cy)
				if dy > case_hw:
					continue
				if is_roof:
					Draw.px(img, x, y, Draw.IRON_HIGH if (x == case_start or dy > case_hw - 1.2) else Draw.IRON_MID)
				elif dy > case_hw - 1.2 or x == case_start or x == case_end:
					var slit: bool = (x % 5 == 0 and x > case_start + 1 and x < case_end - 1)
					Draw.px(img, x, y, Draw.OUTLINE_COLOR if slit else (trim_col if step == 0 else Draw.IRON_HIGH))
				else:
					Draw.px(img, x, y, Draw.IRON_DARK if y > int(cy) else Draw.IRON_MID)
		var stack_x: int = int(spec.get("smokestack_x", 38))
		for dy_i in [-1, 0, 1]:
			for dx_i in [-1, 0, 1]:
				var edge: bool = (abs(dx_i) + abs(dy_i)) > 0
				Draw.px(img, stack_x + dx_i, 15 + dy_i, Draw.IRON_HIGH if (edge and dy_i < 0) else (Draw.IRON_DARK if edge else Draw.OUTLINE_COLOR))
		for mx_var in spec["masts"]:
			var mx: int = int(mx_var)
			for dy_m in [-1, 0, 1]:
				for dx_m in [0, 1]:
					if abs(dx_m) + abs(dy_m) <= 1:
						Draw.px(img, mx + dx_m, 15 + dy_m, Draw.IRON_HIGH if dy_m < 0 else Draw.IRON_DARK)
		return

	var cab_start: int = x_min + 1
	var cab_end: int = stern_end - (1 if step > 0 and tier != 5 and tier != 8 else 0)
	for x in range(cab_start, cab_end + 1):
		var hw: float = _hull_half_width_spec(x, spec) * (0.98 - float(step) * 0.055)
		for y in range(2, SHIP_TEX_HEIGHT - 2):
			var dy: float = absf(float(y) - cy)
			if dy > hw:
				continue
			if step == 0:
				if dy > hw - 1.3 or x == cab_start or x == cab_end:
					Draw.px(img, x, y, trim_col if rich_trim else rail_col)
				else:
					Draw.px(img, x, y, wood_light if ((y / 2) % 2 == 0) else wood_mid)
			elif not is_roof:
				if x >= cab_start + 1 and x <= cab_end - 1 and dy <= hw - 1.1:
					var c: Color = wood_dark if (x == cab_start + 1 or x == cab_end - 1) else wood_mid
					if x == cab_start + 1 and (int(dy) == 2 or int(dy) == 3 or ((tier == 5 or tier == 8) and int(dy) == 5) or (tier == 8 and int(dy) == 7)):
						c = lantern
					Draw.px(img, x, y, c)
			elif x >= cab_start + 2 and x <= cab_end - 2 and dy <= hw - 1.6:
				Draw.px(img, x, y, trim_col if (x == cab_start + 2 or dy > hw - 2.5) else wood_light)

	# Forecastle: Schooner gets low rail, Brig/Frigate medium castle, Galleon/Man-o'-War tall grand forecastle
	var fore_max_step: int = 2 if (tier == 5 or tier == 8) else (1 if (tier == 2 or tier == 3) else (0 if (tier == 1 or tier == 6) else -1))
	if step <= fore_max_step:
		for x in range(fore_start, x_max):
			var hw: float = _hull_half_width_spec(x, spec) * (0.96 - float(step) * 0.04)
			for y in range(2, SHIP_TEX_HEIGHT - 2):
				var dy: float = absf(float(y) - cy)
				if dy <= hw:
					if dy > hw - 1.3 or x == fore_start or x >= x_max - 2:
						Draw.px(img, x, y, trim_col if rich_trim else rail_col)
					elif (tier >= 3 and step <= 1) or tier == 5 or tier == 8:
						Draw.px(img, x, y, wood_light if step == 2 else wood_mid)

	if step == 1:
		var wx: int = cab_end + 1
		for wy in range(14, 18):
			Draw.px(img, wx, wy, trim_col if (wy == 14 or wy == 17) else wood_dark)

	for mx_var in spec["masts"]:
		var mx: int = int(mx_var)
		for dy in [-1, 0, 1]:
			for dx in [0, 1]:
				if abs(dx) + abs(dy) <= 1:
					Draw.px(img, mx + dx, 15 + dy, wood_light if dy < 0 else wood_dark)


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
	var is_raked: bool = bool(spec.get("raked", false))
	var main_mast_idx: int = 1 if masts.size() >= 2 else 0
	var main_mx: int = int(masts[main_mast_idx])

	for mx_var in masts:
		var mx: int = int(mx_var)
		Draw.px(img, mx, 15, Draw.IRON_HIGH if tier == 7 else mast_hi)
		Draw.px(img, mx, 16, Draw.IRON_MID if tier == 7 else mast_col)

	if tier == 7:
		var stack_x: int = int(spec.get("smokestack_x", 38))
		var sail_mid_i: int = (sail_start + sail_end) / 2
		if layer_idx <= sail_mid_i + 1:
			for dy_s in [-1, 0, 1]:
				for dx_s in [-1, 0, 1]:
					var is_center: bool = (dx_s == 0 and dy_s == 0)
					var col_s: Color = Color(0.95, 0.45, 0.16, 1.0) if (is_center and layer_idx == sail_mid_i + 1) else (Draw.OUTLINE_COLOR if is_center else (Draw.IRON_HIGH if dy_s < 0 else Draw.IRON_DARK))
					Draw.px(img, stack_x + dx_s, 15 + dy_s, col_s)
		else:
			var drift: int = layer_idx - (sail_mid_i + 1)
			var smoke_col := Color(0.56, 0.58, 0.62, 0.72) if drift <= 2 else Color(0.72, 0.74, 0.78, 0.48)
			Draw.px(img, stack_x - drift, 15, smoke_col)
			Draw.px(img, stack_x - drift - 1, 16, smoke_col)

	if layer_idx == yard_layer:
		for m_i in range(masts.size()):
			var mx: int = int(masts[m_i])
			var yh: int = int(yard_halfs[m_i])
			for y in range(16 - yh, 16 + yh):
				var y_skew: int = int((y - 16) / 4) if tier == 6 else 0
				Draw.px(img, mx - y_skew, y, mast_hi if y < 16 else mast_col)
		return

	if layer_idx >= sail_start and layer_idx <= sail_end:
		var sail_prog: float = float(layer_idx - sail_start) / float(maxi(1, sail_end - sail_start))
		var taper: int = 2 if sail_prog > 0.68 else 0
		var rake_shift: int = -int(round(sail_prog * 2.0)) if is_raked else 0
		var sail_mid: int = (sail_start + sail_end) / 2
		for m_i in range(masts.size()):
			var mx: int = int(masts[m_i])
			var sh: int = maxi(3, int(sail_halfs[m_i]) - taper)
			for y in range(16 - sh, 16 + sh):
				var dist_center: float = absf(float(y) - 15.5) / float(sh)
				var bulge: int = 3 if (dist_center < 0.45 and tier >= 2) else (2 if dist_center < 0.65 else 1)
				var lateen_skew: int = -int((y - 16) / 5) if tier == 6 else 0
				var sx: int = mx + bulge + rake_shift + lateen_skew
				var sc: Color = _pick_clean_sail_band(y, sail_prog, faction, colors["sail_a"], colors["sail_b"], colors["sail_c"])
				Draw.px(img, sx, y, sc)
				Draw.px(img, sx - 1, y, sc.darkened(0.10))

			if faction == Contracts.ShipFaction.PIRATE and m_i == main_mast_idx and abs(layer_idx - sail_mid) <= 1:
				var skull_x: int = mx + (3 if tier >= 2 else 2) + rake_shift
				for sy in range(14, 18):
					var is_eye: bool = (layer_idx == sail_mid and (sy == 15 or sy == 16))
					Draw.px(img, skull_x, sy, Draw.OUTLINE_COLOR if is_eye else colors["flag_emblem"])

		if (tier == 3 or tier == 5 or tier == 8) and (faction == Contracts.ShipFaction.NAVY or faction == Contracts.ShipFaction.MERCHANT or tier == 5 or tier == 8):
			var main_sh: int = maxi(3, int(sail_halfs[main_mast_idx]) - taper)
			Draw.px(img, main_mx + 1 + rake_shift, 16 - main_sh, colors["trim"])
			Draw.px(img, main_mx + 1 + rake_shift, 16 + main_sh - 1, colors["trim"])
		return

	if layer_idx == crow_nest_layer:
		var nest_offset: int = -1 if is_raked else 0
		for mx_var in masts:
			var mx: int = int(mx_var) + nest_offset
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					Draw.px(img, mx + dx, 15 + dy, mast_hi if dy < 0 else mast_col)
			if tier == 8:
				Draw.px(img, mx, 13, colors["trim"])
				Draw.px(img, mx, 17, colors["trim"])
		if tier == 5:
			for dy in [-2, 2]:
				Draw.px(img, main_mx, 15 + dy, colors["trim"])
	elif layer_idx == flag_layer:
		var flag_len: int = mini(15, 5 + tier * 2)
		var flag_anchor: int = main_mx - (1 if is_raked else 0)
		for fx in range(maxi(1, flag_anchor - flag_len), flag_anchor):
			var wave_y: int = 15 + (1 if ((fx - flag_anchor) % 3 == 0) else 0)
			Draw.px(img, fx, wave_y, colors["flag_emblem"] if fx == flag_anchor - 3 else colors["flag"])
			if fx >= flag_anchor - 4 or (tier == 8 and fx >= flag_anchor - 8):
				Draw.px(img, fx, wave_y + 1, colors["flag"])


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

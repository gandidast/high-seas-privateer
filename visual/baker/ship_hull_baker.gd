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
	# 6: Corsair Xebec ("Korsaren-Schebecke") — sleek dark-mahogany 3-mast lateen hunter with ramming beak & twin bow chasers
	6: {
		"tier": 6, "x_min": 5, "x_max": 54, "max_hw": 6.7,
		"stern_end": 16, "fore_start": 44,
		"masts": [17, 32, 46], "yard_halfs": [7, 10, 8], "sail_halfs": [6, 9, 7],
		"gunport_xs": [20, 26, 32, 38, 44, 49], "bowsprit_len": 7, "raked": true
	},
	# 7: Ironclad ("Panzer-Monitor") — riveted dark-steel steam warship, wedge ram, casemate, turret & smokestack (NO masts/sails)
	7: {
		"tier": 7, "x_min": 4, "x_max": 55, "max_hw": 10.6,
		"stern_end": 18, "fore_start": 44,
		"masts": [], "yard_halfs": [], "sail_halfs": [],
		"gunport_xs": [18, 24, 30, 36, 42], "bowsprit_len": 0, "raked": false,
		"smokestack_x": 25, "aux_stack_x": 19, "cupola_x": 34, "turret_x": 43, "flagpole_x": 8
	},
	# 8: Man-o'-War ("Linienschiff") — grand royal-oak/ebony 3-deck flagship with figurehead & double-tiered sails
	8: {
		"tier": 8, "x_min": 2, "x_max": 58, "max_hw": 13.0,
		"stern_end": 18, "fore_start": 44,
		"masts": [15, 31, 47], "yard_halfs": [10, 14, 11], "sail_halfs": [9, 13, 10],
		"gunport_xs": [13, 18, 23, 28, 33, 38, 43, 48, 52], "bowsprit_len": 4, "raked": false
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


static func _hull_palette_for_tier(tier: int) -> Dictionary:
	if tier == 7:
		return {
			"keel_dark": Color(0.125, 0.145, 0.190, 1.0),
			"keel_mid": Draw.IRON_DARK,
			"keel_lit": Draw.IRON_MID,
			"side_dark": Draw.IRON_DARK,
			"side_mid": Draw.IRON_MID,
			"side_lit": Draw.IRON_HIGH,
			"deck_mid": Color(0.255, 0.275, 0.335, 1.0),
			"deck_light": Color(0.355, 0.385, 0.455, 1.0),
			"deck_seam": Draw.IRON_DARK
		}
	if tier == 6:
		return {
			"keel_dark": Color(0.180, 0.075, 0.082, 1.0),
			"keel_mid": Color(0.294, 0.118, 0.114, 1.0),
			"keel_lit": Color(0.412, 0.173, 0.149, 1.0),
			"side_dark": Color(0.275, 0.106, 0.102, 1.0),
			"side_mid": Color(0.408, 0.165, 0.137, 1.0),
			"side_lit": Color(0.573, 0.259, 0.188, 1.0),
			"deck_mid": Color(0.494, 0.231, 0.176, 1.0),
			"deck_light": Color(0.612, 0.314, 0.224, 1.0),
			"deck_seam": Color(0.310, 0.133, 0.114, 1.0)
		}
	if tier == 8:
		return {
			"keel_dark": Color(0.157, 0.098, 0.094, 1.0),
			"keel_mid": Color(0.271, 0.157, 0.129, 1.0),
			"keel_lit": Color(0.384, 0.227, 0.169, 1.0),
			"side_dark": Color(0.137, 0.094, 0.114, 1.0),
			"side_mid": Color(0.376, 0.212, 0.149, 1.0),
			"side_lit": Color(0.569, 0.349, 0.227, 1.0),
			"deck_mid": Color(0.667, 0.427, 0.278, 1.0),
			"deck_light": Color(0.847, 0.635, 0.396, 1.0),
			"deck_seam": Color(0.380, 0.216, 0.145, 1.0)
		}
	return {
		"keel_dark": Color(0.247, 0.145, 0.137, 1.0),
		"keel_mid": Color(0.376, 0.216, 0.165, 1.0),
		"keel_lit": Color(0.490, 0.294, 0.212, 1.0),
		"side_dark": Color(0.420, 0.243, 0.173, 1.0),
		"side_mid": Color(0.561, 0.337, 0.231, 1.0),
		"side_lit": Color(0.761, 0.510, 0.333, 1.0),
		"deck_mid": Color(0.722, 0.447, 0.314, 1.0),
		"deck_light": Color(0.835, 0.596, 0.384, 1.0),
		"deck_seam": Color(0.510, 0.302, 0.208, 1.0)
	}


static func _draw_ironclad_ram_wedge(img: Image, x_max: int, trim_col: Color, full_wedge: bool) -> void:
	var ram_end: int = mini(SHIP_TEX_WIDTH - 2, x_max + 6)
	for rx in range(x_max - 1, ram_end + 1):
		var prog: float = float(rx - (x_max - 1)) / float(maxi(1, ram_end - (x_max - 1)))
		var half_w: int = 2 if prog < 0.35 else (1 if prog < 0.78 else 0)
		if not full_wedge:
			half_w = mini(half_w, 1)
		for ry in range(15 - half_w, 17 + half_w):
			var c: Color = Draw.IRON_MID
			if ry == 15 - half_w:
				c = Draw.IRON_HIGH
			elif ry == 16 + half_w:
				c = Draw.IRON_DARK
			if full_wedge and rx == x_max and (ry == 14 or ry == 17):
				c = trim_col
			elif rx >= ram_end - 1 and (ry == 15 or ry == 16):
				c = Draw.IRON_HIGH
			Draw.px(img, rx, ry, c)


static func _draw_keel_and_lower_hull(img: Image, k_frac: float, spec: Dictionary) -> void:
	var scale_w: float = lerpf(0.36, 0.86, k_frac)
	var tier: int = int(spec["tier"])
	var pal: Dictionary = _hull_palette_for_tier(tier)
	var hull_dark: Color = pal["keel_dark"]
	var hull_mid: Color = pal["keel_mid"]
	var hull_lit: Color = pal["keel_lit"]
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

	var x_max: int = int(spec["x_max"])
	if tier == 7 and k_frac >= 0.30:
		_draw_ironclad_ram_wedge(img, x_max, Draw.BRASS, k_frac >= 0.7)
	elif tier == 6 and k_frac >= 0.55:
		for rx in range(x_max + 1, mini(SHIP_TEX_WIDTH - 2, x_max + 5)):
			Draw.px(img, rx, 15, Draw.IRON_HIGH if rx >= x_max + 3 else hull_lit)
			Draw.px(img, rx, 16, Draw.IRON_MID if rx >= x_max + 3 else hull_mid)


static func _draw_lower_bulwark(img: Image, step: int, steps: int, spec: Dictionary, colors: Dictionary) -> void:
	var flare: float = lerpf(0.92, 0.99, float(step) / float(maxi(1, steps)))
	var tier: int = int(spec["tier"])
	var is_ironclad: bool = (tier == 7)
	var is_xebec: bool = (tier == 6)
	var is_man_o_war: bool = (tier == 8)
	var pal: Dictionary = _hull_palette_for_tier(tier)
	var hull_side_dark: Color = pal["side_dark"]
	var hull_side: Color = pal["side_mid"]
	var hull_lit: Color = pal["side_lit"]
	var trim_col: Color = colors["trim"]
	var xebec_crimson := Color(0.761, 0.145, 0.176, 1.0)
	var has_double_deck: bool = (tier == 3 or tier == 5 or is_man_o_war)
	var has_gilded_trim: bool = (tier >= 3 and not is_ironclad)
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
			if is_man_o_war and step == 2 and dy > hw - 1.5:
				c = hull_side_dark # Ebony sheer strake band between gun decks
			if dy > hw - 1.3 and float(y) < cy:
				c = hull_lit
			if is_ironclad and dy > hw - 1.6:
				if x % 4 == 0:
					c = hull_side_dark
				elif x % 4 == 2 and step == steps:
					c = hull_lit
			if (step == steps or (has_double_deck and step == 1) or (is_man_o_war and step >= 1)) and dy > hw - 1.5:
				if is_xebec and step == steps:
					c = Draw.BRASS if x % 3 == 0 else xebec_crimson
				elif is_man_o_war and step == steps:
					c = Draw.BRASS if x % 2 == 0 else trim_col
				elif has_gilded_trim and step == steps and (x % 3 == 0 or (tier == 5 and x % 2 == 0)):
					c = trim_col
				elif is_ironclad and step == steps and x % 6 == 0:
					c = trim_col
				for gx_var in gunport_xs:
					var gx: int = int(gx_var)
					var hit_port: bool = (x == gx) or ((tier == 5 or is_man_o_war) and step == steps and x == gx + 1)
					if is_man_o_war and step == 1 and (x == gx + 2):
						hit_port = true # Staggered lower battery gunports
					if hit_port and dy > hw - 1.4:
						c = Draw.BRASS if (is_man_o_war and step == 1 and x == gx + 2 and dy > hw - 0.7) else Draw.OUTLINE_COLOR
						break
			Draw.px(img, x, y, c)

	if is_ironclad and step == steps:
		_draw_ironclad_ram_wedge(img, int(spec["x_max"]), trim_col, true)


static func _draw_main_deck_and_rails(img: Image, step: int, steps: int, spec: Dictionary, colors: Dictionary) -> void:
	var flare: float = lerpf(1.00, 1.05, float(step) / float(maxi(1, steps - 1)))
	var tier: int = int(spec["tier"])
	var is_ironclad: bool = (tier == 7)
	var is_xebec: bool = (tier == 6)
	var is_man_o_war: bool = (tier == 8)
	var pal: Dictionary = _hull_palette_for_tier(tier)
	var hull_side_dark: Color = pal["side_dark"]
	var hull_side: Color = pal["side_mid"]
	var deck_mid: Color = pal["deck_mid"]
	var deck_light: Color = pal["deck_light"]
	var deck_seam: Color = pal["deck_seam"]
	var trim_col: Color = colors["trim"]
	var rail_col: Color = Draw.IRON_HIGH if is_ironclad else colors["rail"]
	var xebec_crimson := Color(0.761, 0.145, 0.176, 1.0)

	var x_min: int = maxi(1, int(spec["x_min"]) - 1)
	var x_max: int = mini(SHIP_TEX_WIDTH - 2, int(spec["x_max"]) + 1)
	var stern_end: int = int(spec["stern_end"])
	var fore_start: int = int(spec["fore_start"])
	var masts: Array = spec["masts"]
	var gunport_xs: Array = spec["gunport_xs"]
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
				if is_man_o_war and step == 1 and dy > hw - 1.4:
					for gx_var in gunport_xs:
						if x == int(gx_var):
							bc = Draw.OUTLINE_COLOR
							break
				if is_top_rail:
					if is_ironclad:
						bc = trim_col if (x >= x_max - 4 or x % 5 == 0) else (rail_col if x % 2 == 0 else hull_side)
					elif is_xebec:
						bc = Draw.BRASS if (x >= x_max - 4 or x <= x_min + 3 or x % 4 == 0) else xebec_crimson
					elif is_man_o_war:
						bc = Draw.BRASS if (x % 2 == 0 or x >= x_max - 4 or x <= x_min + 3) else trim_col
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
			_draw_ironclad_ram_wedge(img, int(spec["x_max"]), trim_col, true)
			# Flush deck hatches & riveted turret ring on ironclad foredeck
			var turret_x: int = int(spec.get("turret_x", 43))
			if step == steps - 1:
				for tx in range(turret_x - 4, turret_x + 5):
					for ty in range(11, 21):
						if Vector2(float(tx - turret_x), float(ty) - cy).length() <= 4.3:
							Draw.px(img, tx, ty, Draw.IRON_HIGH if ty < 15 else Draw.IRON_DARK)
		else:
			var b_len: int = int(spec["bowsprit_len"])
			var spec_x_max: int = int(spec["x_max"])
			var b_end: int = mini(SHIP_TEX_WIDTH - 2, spec_x_max + b_len - (steps - 1 - step))
			if is_xebec:
				# Sharp forward steel/brass ramming beak
				var beak_end: int = mini(SHIP_TEX_WIDTH - 2, spec_x_max + b_len)
				for bx in range(spec_x_max - 1, beak_end + 1):
					var is_tip: bool = bx >= beak_end - 2
					Draw.px(img, bx, 15, Draw.IRON_HIGH if is_tip else Draw.BRASS)
					Draw.px(img, bx, 16, Draw.IRON_MID if is_tip else xebec_crimson)
				if step >= steps - 2:
					# Twin brass bow-chaser cannon barrels flanking the bow
					for cx in range(spec_x_max - 5, spec_x_max + 2):
						var is_muzzle: bool = (cx == spec_x_max + 1)
						var is_ring: bool = (cx == spec_x_max - 4 or cx == spec_x_max - 1)
						var bcol: Color = Draw.OUTLINE_COLOR if is_muzzle else (Draw.SUNLIGHT_HIGHLIGHT if is_ring else Draw.BRASS)
						Draw.px(img, cx, 13, bcol)
						Draw.px(img, cx, 18, bcol)
			elif is_man_o_war:
				# Gilded prow figurehead crest + heavy royal bowsprit
				for fx in range(spec_x_max - 1, mini(SHIP_TEX_WIDTH - 2, spec_x_max + 3)):
					Draw.px(img, fx, 14, Draw.SUNLIGHT_HIGHLIGHT if fx >= spec_x_max else Draw.BRASS)
					Draw.px(img, fx, 15, Draw.BRASS)
					Draw.px(img, fx, 16, trim_col)
					Draw.px(img, fx, 17, Draw.BRASS if fx == spec_x_max else trim_col)
				for bx in range(spec_x_max, b_end + 1):
					Draw.px(img, bx, 15, Draw.SUNLIGHT_HIGHLIGHT if bx == b_end else deck_light)
					Draw.px(img, bx, 16, Draw.BRASS if bx % 2 == 0 else hull_side)
			else:
				for bx in range(spec_x_max - 2, b_end + 1):
					if tier == 4 and bx >= b_end - 2:
						Draw.px(img, bx, 15, trim_col if bx == b_end else deck_light)
					else:
						Draw.px(img, bx, 15, deck_light)
						Draw.px(img, bx, 16, hull_side)
				if tier >= 3 and step == steps - 1:
					Draw.px(img, spec_x_max + 1, 15, trim_col)
					Draw.px(img, spec_x_max + 1, 16, trim_col)


static func _draw_cabin_and_castles(img: Image, step: int, steps: int, spec: Dictionary, colors: Dictionary) -> void:
	var rail_col: Color = colors["rail"]
	var trim_col: Color = colors["trim"]
	var tier: int = int(spec["tier"])
	var is_xebec: bool = (tier == 6)
	var is_man_o_war: bool = (tier == 8)
	var pal: Dictionary = _hull_palette_for_tier(tier)
	var wood_dark: Color = pal["side_dark"]
	var wood_mid: Color = pal["side_mid"]
	var wood_light: Color = pal["deck_light"]
	var lantern := Color(1.0, 0.859, 0.420, 1.0)
	var lantern_core := Color(1.0, 0.980, 0.800, 1.0)
	var grate_ember := Color(1.0, 0.440, 0.100, 1.0)
	var grate_bright := Color(1.0, 0.780, 0.220, 1.0)

	var x_min: int = int(spec["x_min"])
	var stern_end: int = int(spec["stern_end"])
	var fore_start: int = int(spec["fore_start"])
	var x_max: int = int(spec["x_max"])
	var cy: float = float(SHIP_TEX_HEIGHT) * 0.5 - 0.5
	var is_roof: bool = (step >= steps - 1)
	var rich_trim: bool = (tier >= 3)

	if tier == 7:
		# Ironclad: sloped riveted casemate + glowing boiler grates + revolving twin-gun turret + cupola + flagpole
		var case_start: int = 16 + step
		var case_end: int = 36 - step
		var case_hw: float = maxf(3.0, 6.8 - float(step) * 1.05)
		for x in range(case_start, case_end + 1):
			for y in range(2, SHIP_TEX_HEIGHT - 2):
				var dy: float = absf(float(y) - cy)
				if dy > case_hw:
					continue
				if is_roof:
					var is_grate: bool = (x >= 19 and x <= 22 and int(dy) == 3) or (x >= 28 and x <= 31 and int(dy) == 3)
					if is_grate:
						Draw.px(img, x, y, grate_bright if (x % 2 == 0) else Draw.OUTLINE_COLOR)
					else:
						Draw.px(img, x, y, Draw.IRON_HIGH if (x == case_start or dy > case_hw - 1.2) else Draw.IRON_MID)
				elif dy > case_hw - 1.3 or x == case_start or x == case_end:
					var is_furnace_grate: bool = (x >= 19 and x <= 22) or (x >= 28 and x <= 31)
					if is_furnace_grate and dy > case_hw - 1.2:
						Draw.px(img, x, y, grate_ember if (x % 2 == 0) else grate_bright)
					else:
						var slit: bool = (x % 5 == 0 and x > case_start + 1 and x < case_end - 1)
						Draw.px(img, x, y, Draw.OUTLINE_COLOR if slit else (trim_col if step == 0 else Draw.IRON_HIGH))
				else:
					Draw.px(img, x, y, Draw.IRON_DARK if y > int(cy) else Draw.IRON_MID)

		# Raised revolving gun turret with twin heavy protruding iron cannon barrels
		var turret_x: int = int(spec.get("turret_x", 43))
		var turret_r: float = maxf(2.4, 4.1 - float(step) * 0.45)
		for tx in range(turret_x - 5, turret_x + 5):
			for ty in range(10, 22):
				var dist: float = Vector2(float(tx - turret_x), float(ty) - cy).length()
				if dist <= turret_r:
					var edge: bool = dist > turret_r - 1.0
					Draw.px(img, tx, ty, Draw.IRON_HIGH if (edge and ty < 16) else (Draw.IRON_DARK if edge else Draw.IRON_MID))
		if step <= 1:
			var barrel_end: int = mini(SHIP_TEX_WIDTH - 4, turret_x + 10)
			for bx in range(turret_x + 2, barrel_end + 1):
				var is_tip: bool = (bx == barrel_end)
				var is_breech: bool = (bx == turret_x + 2 or bx == turret_x + 5)
				var b_top: Color = Draw.OUTLINE_COLOR if is_tip else (Draw.BRASS if is_breech else Draw.IRON_HIGH)
				var b_bot: Color = Draw.OUTLINE_COLOR if is_tip else (Draw.BRASS if is_breech else Draw.IRON_DARK)
				Draw.px(img, bx, 13, b_top)
				Draw.px(img, bx, 14, Draw.IRON_MID if not is_tip else Draw.OUTLINE_COLOR)
				Draw.px(img, bx, 17, Draw.IRON_MID if not is_tip else Draw.OUTLINE_COLOR)
				Draw.px(img, bx, 18, b_bot)

		# Armored conning cupola + twin smokestack bases + stern battle-flag pole
		var cupola_x: int = int(spec.get("cupola_x", 34))
		for dx_c in [-1, 0, 1]:
			for dy_c in [-1, 0, 1]:
				var rim_c: Color = Draw.OUTLINE_COLOR if (dx_c == 1 and dy_c == 0) else (Draw.IRON_HIGH if dy_c < 0 else Draw.IRON_DARK)
				Draw.px(img, cupola_x + dx_c, 15 + dy_c, rim_c)

		var stack_x: int = int(spec.get("smokestack_x", 25))
		for dy_i in range(-2, 3):
			for dx_i in range(-2, 3):
				if abs(dx_i) == 2 and abs(dy_i) == 2:
					continue
				var edge: bool = (maxi(abs(dx_i), abs(dy_i)) >= 1)
				Draw.px(img, stack_x + dx_i, 15 + dy_i, Draw.IRON_HIGH if (edge and dy_i < 0) else (Draw.IRON_DARK if edge else Draw.OUTLINE_COLOR))

		var aux_x: int = int(spec.get("aux_stack_x", 19))
		for dy_a in [-1, 0, 1]:
			for dx_a in [-1, 0, 1]:
				var edge_a: bool = (abs(dx_a) + abs(dy_a)) > 0
				Draw.px(img, aux_x + dx_a, 15 + dy_a, Draw.IRON_HIGH if (edge_a and dy_a < 0) else (Draw.IRON_DARK if edge_a else Draw.OUTLINE_COLOR))

		var flag_x: int = int(spec.get("flagpole_x", 8))
		Draw.px(img, flag_x, 15, Draw.IRON_HIGH)
		Draw.px(img, flag_x, 16, Draw.IRON_DARK)
		return

	var cab_start: int = x_min + 1
	var cab_end: int = stern_end - (1 if step > 0 and tier != 5 and not is_man_o_war else 0)
	for x in range(cab_start, cab_end + 1):
		var hw: float = _hull_half_width_spec(x, spec) * (0.98 - float(step) * 0.055)
		for y in range(2, SHIP_TEX_HEIGHT - 2):
			var dy: float = absf(float(y) - cy)
			if dy > hw:
				continue
			if step == 0:
				if dy > hw - 1.3 or x == cab_start or x == cab_end:
					Draw.px(img, x, y, Draw.BRASS if is_man_o_war else (trim_col if rich_trim else rail_col))
				else:
					Draw.px(img, x, y, wood_light if ((y / 2) % 2 == 0) else wood_mid)
			elif not is_roof:
				if x >= cab_start + 1 and x <= cab_end - 1 and dy <= hw - 1.1:
					var c: Color = wood_dark if (x == cab_start + 1 or x == cab_end - 1) else wood_mid
					if x == cab_start + 1 and (int(dy) == 2 or int(dy) == 3 or (tier == 5 and int(dy) == 5)):
						c = lantern
					Draw.px(img, x, y, c)
			elif x >= cab_start + 2 and x <= cab_end - 2 and dy <= hw - 1.6:
				Draw.px(img, x, y, trim_col if (x == cab_start + 2 or dy > hw - 2.5) else wood_light)

	# Man-o'-War ornate 3-lantern admiral stern gallery (port, center, starboard)
	if is_man_o_war and step >= 1:
		var gx: int = cab_start + (1 if not is_roof else 2)
		for ly in [10, 15, 20]:
			Draw.px(img, gx, ly, lantern_core)
			Draw.px(img, gx, ly + 1, lantern)
			Draw.px(img, gx - 1, ly, Draw.BRASS)
			Draw.px(img, gx - 1, ly + 1, Draw.BRASS)

	# Xebec twin bow-chaser barrels visible at cabin step 0
	if is_xebec and step == 0:
		for cx in range(x_max - 4, x_max + 2):
			var is_muzzle: bool = (cx == x_max + 1)
			Draw.px(img, cx, 13, Draw.OUTLINE_COLOR if is_muzzle else Draw.BRASS)
			Draw.px(img, cx, 18, Draw.OUTLINE_COLOR if is_muzzle else Draw.BRASS)

	# Forecastle: Schooner gets low rail, Brig/Frigate medium castle, Galleon/Man-o'-War tall grand forecastle
	var fore_max_step: int = 2 if (tier == 5 or is_man_o_war) else (1 if (tier == 2 or tier == 3) else (0 if (tier == 1 or is_xebec) else -1))
	if step <= fore_max_step:
		for x in range(fore_start, x_max):
			var hw: float = _hull_half_width_spec(x, spec) * (0.96 - float(step) * 0.04)
			for y in range(2, SHIP_TEX_HEIGHT - 2):
				var dy: float = absf(float(y) - cy)
				if dy <= hw:
					if dy > hw - 1.3 or x == fore_start or x >= x_max - 2:
						Draw.px(img, x, y, Draw.BRASS if is_man_o_war else (trim_col if rich_trim else rail_col))
					elif (tier >= 3 and step <= 1) or tier == 5 or is_man_o_war:
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


static func _draw_ironclad_upper_layers(
	img: Image,
	layer_idx: int,
	yard_layer: int,
	sail_start: int,
	sail_end: int,
	crow_nest_layer: int,
	flag_layer: int,
	spec: Dictionary,
	colors: Dictionary
) -> void:
	var stack_x: int = int(spec.get("smokestack_x", 25))
	var aux_x: int = int(spec.get("aux_stack_x", 19))
	var cupola_x: int = int(spec.get("cupola_x", 34))
	var turret_x: int = int(spec.get("turret_x", 43))
	var flag_x: int = int(spec.get("flagpole_x", 8))
	var trim_col: Color = colors["trim"]

	# Armored turret roof hatch on yard_layer
	if layer_idx == yard_layer:
		for tx in range(turret_x - 2, turret_x + 3):
			for ty in range(13, 19):
				if Vector2(float(tx - turret_x), float(ty) - 15.5).length() <= 2.4:
					Draw.px(img, tx, ty, Draw.IRON_HIGH if ty < 15 else Draw.IRON_MID)

	# Armored conning cupola upper dome
	if layer_idx <= yard_layer + 2:
		for dx_c in [-1, 0, 1]:
			for dy_c in [-1, 0, 1]:
				if abs(dx_c) + abs(dy_c) <= 1:
					Draw.px(img, cupola_x + dx_c, 15 + dy_c, Draw.IRON_HIGH if dy_c <= 0 else Draw.IRON_DARK)

	# Auxiliary vent funnel (stops earlier) & main tall iron smokestack with brass rim + coal smoke
	if layer_idx <= sail_start + 1:
		for dy_a in [-1, 0, 1]:
			for dx_a in [-1, 0, 1]:
				var is_core: bool = (dx_a == 0 and dy_a == 0)
				Draw.px(img, aux_x + dx_a, 15 + dy_a, Draw.OUTLINE_COLOR if is_core else (Draw.IRON_HIGH if dy_a < 0 else Draw.IRON_DARK))

	var stack_top: int = sail_start + 3
	if layer_idx <= stack_top:
		var is_collar: bool = (layer_idx == stack_top - 1)
		for dy_s in range(-2, 3):
			for dx_s in range(-2, 3):
				if abs(dx_s) == 2 and abs(dy_s) == 2:
					continue
				var is_flue: bool = (abs(dx_s) <= 1 and abs(dy_s) <= 1) and (abs(dx_s) + abs(dy_s) <= 1)
				var col_s: Color
				if is_flue:
					col_s = Color(1.0, 0.48, 0.14, 1.0) if (layer_idx == stack_top and dx_s == 0 and dy_s == 0) else Draw.OUTLINE_COLOR
				elif is_collar:
					col_s = trim_col
				else:
					col_s = Draw.IRON_HIGH if dy_s < 0 else (Draw.IRON_MID if dy_s == 0 else Draw.IRON_DARK)
				Draw.px(img, stack_x + dx_s, 15 + dy_s, col_s)

	# Billowing coal smoke drifting aft across upper layers (sail_start + 2 .. crow_nest_layer)
	if layer_idx >= sail_start + 2 and layer_idx <= crow_nest_layer:
		var drift: int = layer_idx - (sail_start + 1)
		var puff_cx: int = maxi(4, stack_x - drift * 2)
		var puff_r: float = 1.6 + float(drift) * 0.42
		var smoke_dark := Color(0.18, 0.19, 0.23, 0.90)
		var smoke_mid := Color(0.36, 0.38, 0.42, 0.78)
		var smoke_light := Color(0.58, 0.60, 0.65, 0.56)
		var s_col: Color = smoke_dark if drift <= 2 else (smoke_mid if drift <= 5 else smoke_light)
		for sy in range(11, 21):
			for sx in range(maxi(2, puff_cx - 4), mini(SHIP_TEX_WIDTH - 2, puff_cx + 4)):
				var d: float = Vector2(float(sx - puff_cx), float(sy) - 15.5).length()
				if d <= puff_r:
					Draw.px(img, sx, sy, s_col if d > puff_r - 1.0 else s_col.darkened(0.16))
		# Trailing secondary wisp from auxiliary stack
		var aux_cx: int = maxi(3, aux_x - drift * 2)
		Draw.px(img, aux_cx, 15, smoke_light)
		Draw.px(img, aux_cx - 1, 16, smoke_light)

	# Stern battle-flag pole & battle ensign
	Draw.px(img, flag_x, 15, Draw.IRON_HIGH)
	Draw.px(img, flag_x, 16, Draw.IRON_DARK)
	if layer_idx == flag_layer:
		for fx in range(maxi(1, flag_x - 6), flag_x):
			var wy: int = 15 + (1 if ((fx - flag_x) % 2 == 0) else 0)
			Draw.px(img, fx, wy, colors["flag_emblem"] if fx == flag_x - 3 else colors["flag"])
			Draw.px(img, fx, wy + 1, colors["flag"])


static func _draw_xebec_lateen_rig(
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
	var mast_col := Color(0.460, 0.230, 0.160, 1.0)
	var mast_hi := Color(0.720, 0.420, 0.250, 1.0)
	var crimson := Color(0.761, 0.145, 0.176, 1.0)
	var masts: Array = spec["masts"]
	var yard_halfs: Array = spec["yard_halfs"]
	var sail_halfs: Array = spec["sail_halfs"]

	for mx_var in masts:
		var mx: int = int(mx_var)
		Draw.px(img, mx, 15, mast_hi)
		Draw.px(img, mx, 16, mast_col)

	if layer_idx == yard_layer:
		# Diagonal lateen yards sweeping forward-port to aft-starboard
		for m_i in range(masts.size()):
			var mx: int = int(masts[m_i])
			var yh: int = int(yard_halfs[m_i])
			for y in range(16 - yh, 16 + yh):
				var lx: int = mx + int(round((15.5 - float(y)) * 0.72))
				var is_tip: bool = (y == 16 - yh or y == 16 + yh - 1)
				Draw.px(img, lx, y, Draw.BRASS if is_tip else (mast_hi if y < 16 else mast_col))
		return

	if layer_idx >= sail_start and layer_idx <= sail_end:
		var sail_prog: float = float(layer_idx - sail_start) / float(maxi(1, sail_end - sail_start))
		var sail_mid: int = (sail_start + sail_end) / 2
		for m_i in range(masts.size()):
			var mx: int = int(masts[m_i])
			var sh: int = int(sail_halfs[m_i])
			# Asymmetric triangular lateen sail converging toward aft peak as height increases
			var y_start: int = int(round(lerpf(float(16 - sh), float(16 + sh - 2), sail_prog)))
			var y_end: int = 16 + sh
			var span: int = maxi(1, y_end - y_start)
			for y in range(y_start, y_end):
				var u: float = float(y - y_start) / float(span)
				var x_yard: int = mx + int(round((15.5 - float(y)) * 0.72))
				var billow: int = int(round((1.0 - sail_prog * 0.50) * 2.4 * sin(u * PI))) + 1
				var sc: Color = _pick_clean_sail_band(y, sail_prog, faction, colors["sail_a"], colors["sail_b"], colors["sail_c"])
				if y == y_start or y == y_end - 1:
					sc = crimson
				for bx in range(0, billow + 1):
					var sx: int = x_yard + bx
					Draw.px(img, sx, y, sc if bx >= billow - 1 else sc.darkened(0.12))
			if faction == Contracts.ShipFaction.PIRATE and m_i == 1 and abs(layer_idx - sail_mid) <= 1:
				var skull_x: int = mx + 2
				for sy in range(15, 19):
					Draw.px(img, skull_x, sy, Draw.OUTLINE_COLOR if (layer_idx == sail_mid and sy == 16) else colors["flag_emblem"])
		return

	if layer_idx == crow_nest_layer:
		# Sleek gilded masthead caps (no square crow's nests)
		for mx_var in masts:
			var mx: int = int(mx_var) - 2
			Draw.px(img, mx, 15, Draw.BRASS)
			Draw.px(img, mx, 16, crimson)
	elif layer_idx == flag_layer:
		# Twin-tailed corsair pennants on all 3 lateen mastheads
		for m_i in range(masts.size()):
			var anchor: int = int(masts[m_i]) - 3
			var p_len: int = 12 if m_i == 1 else 7
			for fx in range(maxi(1, anchor - p_len), anchor):
				var wy: int = 15 + (1 if ((fx - anchor) % 3 == 0) else 0)
				Draw.px(img, fx, wy, Draw.BRASS if fx == anchor - 2 else crimson)


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
	var tier: int = int(spec["tier"])
	if tier == 7:
		_draw_ironclad_upper_layers(img, layer_idx, yard_layer, sail_start, sail_end, crow_nest_layer, flag_layer, spec, colors)
		return
	if tier == 6:
		_draw_xebec_lateen_rig(img, layer_idx, yard_layer, sail_start, sail_end, crow_nest_layer, flag_layer, faction, spec, colors)
		return

	var mast_col := Color(0.612, 0.400, 0.247, 1.0)
	var mast_hi := Color(0.851, 0.627, 0.400, 1.0)
	var masts: Array = spec["masts"]
	var yard_halfs: Array = spec["yard_halfs"]
	var sail_halfs: Array = spec["sail_halfs"]
	var is_raked: bool = bool(spec.get("raked", false))
	var is_man_o_war: bool = (tier == 8)
	var main_mast_idx: int = 1 if masts.size() >= 2 else 0
	var main_mx: int = int(masts[main_mast_idx])

	for mx_var in masts:
		var mx: int = int(mx_var)
		Draw.px(img, mx, 15, mast_hi)
		Draw.px(img, mx, 16, mast_col)

	if layer_idx == yard_layer:
		for m_i in range(masts.size()):
			var mx: int = int(masts[m_i])
			var yh: int = int(yard_halfs[m_i])
			for y in range(16 - yh, 16 + yh):
				Draw.px(img, mx, y, mast_hi if y < 16 else mast_col)
		return

	if layer_idx >= sail_start and layer_idx <= sail_end:
		var sail_prog: float = float(layer_idx - sail_start) / float(maxi(1, sail_end - sail_start))
		var sail_mid: int = (sail_start + sail_end) / 2
		if is_man_o_war and layer_idx == sail_mid:
			# Distinct upper topsail/topgallant yardarm separating double-tiered sails
			for m_i in range(masts.size()):
				var mx: int = int(masts[m_i])
				var yh_top: int = maxi(4, int(yard_halfs[m_i]) - 3)
				for y in range(16 - yh_top, 16 + yh_top):
					var is_tip: bool = (y == 16 - yh_top or y == 16 + yh_top - 1)
					Draw.px(img, mx, y, Draw.BRASS if is_tip else (mast_hi if y < 16 else mast_col))
			return

		var is_upper_tier: bool = is_man_o_war and layer_idx > sail_mid
		var taper: int = (3 if is_upper_tier else 0) if is_man_o_war else (2 if sail_prog > 0.68 else 0)
		var rake_shift: int = -int(round(sail_prog * 2.0)) if is_raked else 0
		for m_i in range(masts.size()):
			var mx: int = int(masts[m_i])
			var sh: int = maxi(3, int(sail_halfs[m_i]) - taper)
			for y in range(16 - sh, 16 + sh):
				var dist_center: float = absf(float(y) - 15.5) / float(sh)
				var bulge: int = 4 if (is_man_o_war and not is_upper_tier and dist_center < 0.45) else (3 if (dist_center < 0.45 and tier >= 2) else (2 if dist_center < 0.65 else 1))
				var sx: int = mx + bulge + rake_shift
				var sc: Color = _pick_clean_sail_band(y, sail_prog, faction, colors["sail_a"], colors["sail_b"], colors["sail_c"])
				if is_man_o_war and (y == 16 - sh or y == 16 + sh - 1):
					sc = colors["trim"]
				Draw.px(img, sx, y, sc)
				Draw.px(img, sx - 1, y, sc.darkened(0.10))

			if is_man_o_war and m_i == main_mast_idx and is_upper_tier:
				# Royal heraldic crest stripe on upper topgallant mainmast sail
				for hy in range(14, 18):
					Draw.px(img, mx + 3, hy, colors["flag_emblem"] if (hy == 15 or hy == 16) else colors["trim"])
			elif faction == Contracts.ShipFaction.PIRATE and m_i == main_mast_idx and abs(layer_idx - sail_mid) <= 1:
				var skull_x: int = mx + (3 if tier >= 2 else 2) + rake_shift
				for sy in range(14, 18):
					var is_eye: bool = (layer_idx == sail_mid and (sy == 15 or sy == 16))
					Draw.px(img, skull_x, sy, Draw.OUTLINE_COLOR if is_eye else colors["flag_emblem"])

		if (tier == 3 or tier == 5 or is_man_o_war) and (faction == Contracts.ShipFaction.NAVY or faction == Contracts.ShipFaction.MERCHANT or tier == 5 or is_man_o_war):
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
					var is_rim: bool = is_man_o_war and (abs(dx) == 1 or abs(dy) == 1)
					Draw.px(img, mx + dx, 15 + dy, Draw.BRASS if is_rim else (mast_hi if dy < 0 else mast_col))
			if is_man_o_war:
				Draw.px(img, mx, 13, colors["trim"])
				Draw.px(img, mx, 17, colors["trim"])
		if tier == 5:
			for dy in [-2, 2]:
				Draw.px(img, main_mx, 15 + dy, colors["trim"])
	elif layer_idx == flag_layer:
		var flag_len: int = 18 if is_man_o_war else mini(15, 5 + tier * 2)
		var flag_anchor: int = main_mx - (1 if is_raked else 0)
		for fx in range(maxi(1, flag_anchor - flag_len), flag_anchor):
			var wave_y: int = 15 + (1 if ((fx - flag_anchor) % 3 == 0) else 0)
			Draw.px(img, fx, wave_y, colors["flag_emblem"] if fx == flag_anchor - 3 else colors["flag"])
			if fx >= flag_anchor - 4 or (is_man_o_war and fx >= flag_anchor - 10):
				Draw.px(img, fx, wave_y + 1, Draw.BRASS if (is_man_o_war and fx == flag_anchor - 10) else colors["flag"])
		if is_man_o_war:
			for m_i in [0, 2]:
				var sub_mx: int = int(masts[m_i])
				for fx in range(maxi(1, sub_mx - 8), sub_mx):
					Draw.px(img, fx, 15, colors["trim"] if fx == sub_mx - 2 else colors["flag"])


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

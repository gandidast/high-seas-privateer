class_name ItemDatabase
extends RefCounted
## Catalog of 22 ship modules, cannons, powder barrels, sails, hull reinforcements,
## crew modules, trade cargo, and treasures with RNG affix generation.

static var _instance_counter: int = 0

static var _TEMPLATES: Dictionary = {}


static func _ensure_templates() -> void:
	if not _TEMPLATES.is_empty():
		return

	_register(
		"swivel_gun_1x2",
		"Leichte Drehbasse",
		"Schnellfeuernde Deckskanone für wendige Schaluppen.",
		Contracts.ItemCategory.CANNON,
		Contracts.ItemRarity.COMMON,
		1, 2,
		[Contracts.SlotType.DECK_PORT, Contracts.SlotType.DECK_STARBOARD, Contracts.SlotType.CARGO_HOLD],
		4.0, 45,
		Color(0.38, 0.34, 0.32), Color(0.80, 0.66, 0.32),
		12.0, 1.9, 240.0, 240.0, 0.0, 5.0
	)

	_register(
		"bronze_cannon_2x2",
		"Schwere Bronzekanone",
		"Schwere Breitseitenkanone mit enormer Durchschlagskraft.",
		Contracts.ItemCategory.CANNON,
		Contracts.ItemRarity.RARE,
		2, 2,
		[Contracts.SlotType.DECK_PORT, Contracts.SlotType.DECK_STARBOARD, Contracts.SlotType.CARGO_HOLD],
		9.0, 115,
		Color(0.62, 0.44, 0.22), Color(0.92, 0.78, 0.38),
		28.0, 3.2, 280.0, 220.0, 0.0, 6.0
	)

	_register(
		"chain_launcher_2x1",
		"Kettenkugel-Werfer",
		"Zerreißt gegnerische Takelage und verlangsamt Feindschiffe.",
		Contracts.ItemCategory.CANNON,
		Contracts.ItemRarity.UNCOMMON,
		2, 1,
		[Contracts.SlotType.DECK_PORT, Contracts.SlotType.DECK_STARBOARD, Contracts.SlotType.CARGO_HOLD],
		5.5, 78,
		Color(0.28, 0.34, 0.42), Color(0.68, 0.80, 0.90),
		14.0, 2.6, 250.0, 210.0, 0.45, 7.0
	)

	_register(
		"long_culverin_1x3",
		"Lange Feldschlange",
		"Präzisionsgeschütz mit überlegener Reichweite.",
		Contracts.ItemCategory.CANNON,
		Contracts.ItemRarity.RARE,
		1, 3,
		[Contracts.SlotType.DECK_PORT, Contracts.SlotType.DECK_STARBOARD, Contracts.SlotType.CARGO_HOLD],
		7.5, 125,
		Color(0.24, 0.26, 0.30), Color(0.84, 0.72, 0.40),
		24.0, 2.9, 340.0, 275.0, 0.0, 3.0
	)

	_register(
		"mortar_cannon_2x2",
		"Belagerungs-Mörser",
		"Verheerendes schweres Geschütz gegen feindliche Rümpfe.",
		Contracts.ItemCategory.CANNON,
		Contracts.ItemRarity.LEGENDARY,
		2, 2,
		[Contracts.SlotType.DECK_PORT, Contracts.SlotType.DECK_STARBOARD, Contracts.SlotType.CARGO_HOLD],
		11.0, 195,
		Color(0.34, 0.20, 0.24), Color(0.98, 0.62, 0.24),
		38.0, 3.8, 305.0, 195.0, 0.0, 8.0
	)

	_register(
		"powder_barrel_1x1",
		"Schwarzpulver-Fass",
		"+25 % Nachladetempo für angrenzende Kanonen. Explosionsrisiko bei Treffern!",
		Contracts.ItemCategory.POWDER_BARREL,
		Contracts.ItemRarity.UNCOMMON,
		1, 1,
		[Contracts.SlotType.CARGO_HOLD, Contracts.SlotType.DECK_PORT, Contracts.SlotType.DECK_STARBOARD],
		3.5, 52,
		Color(0.48, 0.24, 0.18), Color(0.95, 0.36, 0.22),
		0.0, 3.0, 260.0, 220.0, 0.0, 6.0,
		0.0, 0.0, 0.0, 0.0, 0.25, 12.0
	)

	_register(
		"storm_sails_2x2",
		"Sturmsegel",
		"Verstärkte Hochsee-Bespannung für maximale Fahrt und Wendigkeit.",
		Contracts.ItemCategory.SAIL,
		Contracts.ItemRarity.RARE,
		2, 2,
		[Contracts.SlotType.MAST],
		4.0, 120,
		Color(0.88, 0.84, 0.74), Color(0.76, 0.24, 0.20),
		0.0, 3.0, 260.0, 220.0, 0.0, 6.0,
		24.0, 0.30, 0.0, 0.0, 0.0, 0.0
	)

	_register(
		"silk_top_sail_1x2",
		"Seiden-Toppsegel",
		"Leichtes Toppsegel für flinke Manöver.",
		Contracts.ItemCategory.SAIL,
		Contracts.ItemRarity.UNCOMMON,
		1, 2,
		[Contracts.SlotType.MAST],
		2.0, 80,
		Color(0.94, 0.91, 0.82), Color(0.28, 0.54, 0.78),
		0.0, 3.0, 260.0, 220.0, 0.0, 6.0,
		14.0, 0.22, 0.0, 0.0, 0.0, 0.0
	)

	_register(
		"reinforced_ribs_1x3",
		"Verstärkte Spanten",
		"Massives Eichenholz stärkt Struktur und Rumpfpanzerung.",
		Contracts.ItemCategory.HULL,
		Contracts.ItemRarity.UNCOMMON,
		1, 3,
		[Contracts.SlotType.CARGO_HOLD],
		7.0, 85,
		Color(0.52, 0.35, 0.22), Color(0.74, 0.56, 0.38),
		0.0, 3.0, 260.0, 220.0, 0.0, 6.0,
		0.0, 0.0, 3.0, 45.0, 0.0, 0.0
	)

	_register(
		"copper_plating_2x2",
		"Kupferbeschlag",
		"Schützt den Rumpf vor Treffern und reduziert Wasserwiderstand.",
		Contracts.ItemCategory.HULL,
		Contracts.ItemRarity.RARE,
		2, 2,
		[Contracts.SlotType.CARGO_HOLD],
		8.0, 130,
		Color(0.72, 0.42, 0.26), Color(0.42, 0.78, 0.66),
		0.0, 3.0, 260.0, 220.0, 0.0, 6.0,
		8.0, 0.0, 5.0, 30.0, 0.0, 0.0
	)

	_register(
		"spice_crates_1x2",
		"Gewürzkisten",
		"Duftende Kolonialwaren mit hohem Marktwert in Häfen.",
		Contracts.ItemCategory.CARGO,
		Contracts.ItemRarity.COMMON,
		1, 2,
		[Contracts.SlotType.CARGO_HOLD, Contracts.SlotType.DECK_PORT, Contracts.SlotType.DECK_STARBOARD],
		4.5, 65,
		Color(0.68, 0.48, 0.26), Color(0.90, 0.68, 0.22)
	)

	_register(
		"rum_casks_1x1",
		"Rumfässer",
		"Beliebtes Handelsgut in jeder Hafen-Taverne.",
		Contracts.ItemCategory.CARGO,
		Contracts.ItemRarity.COMMON,
		1, 1,
		[Contracts.SlotType.CARGO_HOLD],
		2.5, 35,
		Color(0.54, 0.34, 0.20), Color(0.78, 0.58, 0.32)
	)

	_register(
		"royal_treasure_2x2",
		"Königliche Schatztruhe",
		"Mit Golddublonen und Juwelen gefüllte Prachttruhe.",
		Contracts.ItemCategory.TREASURE,
		Contracts.ItemRarity.LEGENDARY,
		2, 2,
		[Contracts.SlotType.CARGO_HOLD],
		8.5, 180,
		Color(0.78, 0.58, 0.18), Color(1.00, 0.88, 0.36)
	)

	_register(
		"salvage_relic_1x2",
		"Versunkenes Artefakt",
		"Seltenes Relikt aus einem alten Schiffswrack.",
		Contracts.ItemCategory.TREASURE,
		Contracts.ItemRarity.RARE,
		1, 2,
		[Contracts.SlotType.CARGO_HOLD],
		4.0, 120,
		Color(0.26, 0.54, 0.52), Color(0.72, 0.92, 0.78)
	)

	# --- ROUND 2: 8 NEW SPECIAL ITEMS (TOTAL 22) ---

	_register(
		"greek_fire_2x1",
		"Griechisches Feuer",
		"Speit flüssiges Feuer auf nahe Gegner und setzt Zielschiffe in Brand!",
		Contracts.ItemCategory.CANNON,
		Contracts.ItemRarity.RARE,
		2, 1,
		[Contracts.SlotType.DECK_PORT, Contracts.SlotType.DECK_STARBOARD, Contracts.SlotType.CARGO_HOLD],
		6.0, 145,
		Color(0.72, 0.30, 0.16), Color(1.00, 0.68, 0.20),
		16.0, 2.4, 175.0, 215.0, 0.0, 8.0,
		0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
		6.5, 0.0, 0.0, 0.0, 0.0
	)

	_register(
		"harpoon_ballista_2x1",
		"Harpunen-Balliste",
		"Verschießt schwere Enter-Harpunen, zieht getroffene Schiffe heran und bremst sie!",
		Contracts.ItemCategory.CANNON,
		Contracts.ItemRarity.RARE,
		2, 1,
		[Contracts.SlotType.DECK_PORT, Contracts.SlotType.DECK_STARBOARD, Contracts.SlotType.CARGO_HOLD],
		6.5, 150,
		Color(0.42, 0.30, 0.22), Color(0.74, 0.86, 0.94),
		18.0, 3.0, 255.0, 250.0, 0.55, 4.0,
		0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
		0.0, 55.0, 0.0, 0.0, 0.0
	)

	_register(
		"iron_ram_1x2",
		"Verstärkter Rammsporn",
		"Massiver Eisenbug für verheerenden Ramm-Schaden und verstärkte Panzerung.",
		Contracts.ItemCategory.HULL,
		Contracts.ItemRarity.RARE,
		1, 2,
		[Contracts.SlotType.CARGO_HOLD, Contracts.SlotType.DECK_PORT, Contracts.SlotType.DECK_STARBOARD],
		8.0, 140,
		Color(0.32, 0.36, 0.44), Color(0.84, 0.88, 0.95),
		0.0, 3.0, 260.0, 220.0, 0.0, 6.0,
		0.0, 0.0, 4.0, 25.0, 0.0, 0.0,
		0.0, 0.0, 35.0, 0.0, 0.0
	)

	_register(
		"crows_nest_1x2",
		"Krähennest-Ausguck",
		"Erhöht Zielreichweite (+90 px), Wendigkeit und Segeltempo.",
		Contracts.ItemCategory.SAIL,
		Contracts.ItemRarity.UNCOMMON,
		1, 2,
		[Contracts.SlotType.MAST],
		2.5, 95,
		Color(0.56, 0.38, 0.22), Color(0.94, 0.80, 0.36),
		0.0, 3.0, 260.0, 220.0, 0.0, 6.0,
		6.0, 0.18, 0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0, 90.0
	)

	_register(
		"gunner_quarters_2x2",
		"Kanonier-Quartier",
		"+20 % Nachladetempo für angrenzende Kanonen – ganz ohne Explosionsrisiko!",
		Contracts.ItemCategory.CREW_MOD,
		Contracts.ItemRarity.RARE,
		2, 2,
		[Contracts.SlotType.CARGO_HOLD],
		5.0, 155,
		Color(0.38, 0.26, 0.22), Color(0.92, 0.72, 0.30),
		0.0, 3.0, 260.0, 220.0, 0.0, 6.0,
		0.0, 0.0, 0.0, 0.0, 0.20, 0.0
	)

	_register(
		"carpenter_workshop_2x2",
		"Zimmermann-Werkstatt",
		"Repariert den Schiffsrumpf kontinuierlich auf offener See (+2.2 HP/s).",
		Contracts.ItemCategory.CREW_MOD,
		Contracts.ItemRarity.RARE,
		2, 2,
		[Contracts.SlotType.CARGO_HOLD],
		5.5, 165,
		Color(0.54, 0.36, 0.22), Color(0.74, 0.84, 0.90),
		0.0, 3.0, 260.0, 220.0, 0.0, 6.0,
		0.0, 0.0, 0.0, 20.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 2.2, 0.0
	)

	_register(
		"alchemist_powder_1x1",
		"Alchemie-Pulverfass",
		"+35 % Nachladetempo & Brandmunition für angrenzende Kanonen. Hohes Risiko!",
		Contracts.ItemCategory.POWDER_BARREL,
		Contracts.ItemRarity.LEGENDARY,
		1, 1,
		[Contracts.SlotType.CARGO_HOLD, Contracts.SlotType.DECK_PORT, Contracts.SlotType.DECK_STARBOARD],
		3.5, 185,
		Color(0.18, 0.46, 0.34), Color(0.44, 0.96, 0.62),
		0.0, 3.0, 260.0, 220.0, 0.0, 6.0,
		0.0, 0.0, 0.0, 0.0, 0.35, 16.0,
		4.5, 0.0, 0.0, 0.0, 0.0
	)

	_register(
		"kraken_tentacle_trophy_2x2",
		"Kraken-Juwel",
		"Legendäre Trophäe eines besiegten Riesenkraken von höchstem Goldwert.",
		Contracts.ItemCategory.TREASURE,
		Contracts.ItemRarity.LEGENDARY,
		2, 2,
		[Contracts.SlotType.CARGO_HOLD],
		6.0, 320,
		Color(0.30, 0.16, 0.44), Color(0.32, 0.94, 0.78)
	)


static func _register(
	p_id: String,
	p_name: String,
	p_desc: String,
	p_category: int,
	p_rarity: int,
	p_width: int,
	p_height: int,
	p_slots: Array[int],
	p_weight: float,
	p_gold: int,
	p_primary: Color,
	p_accent: Color,
	p_damage: float = 0.0,
	p_reload: float = 3.0,
	p_range: float = 260.0,
	p_proj_speed: float = 220.0,
	p_chain_slow: float = 0.0,
	p_spread: float = 6.0,
	p_speed_bonus: float = 0.0,
	p_turn_bonus: float = 0.0,
	p_armor_bonus: float = 0.0,
	p_hp_bonus: float = 0.0,
	p_reload_synergy: float = 0.0,
	p_explosion_hazard: float = 0.0,
	p_burn_dps: float = 0.0,
	p_harpoon_pull: float = 0.0,
	p_ram_damage_bonus: float = 0.0,
	p_passive_repair_rate: float = 0.0,
	p_vision_bonus: float = 0.0
) -> void:
	var item := Contracts.GridItemData.new()
	item.id = p_id
	item.name = p_name
	item.description = p_desc
	item.category = p_category
	item.rarity = p_rarity
	item.affix = Contracts.ItemAffix.STANDARD
	item.width = p_width
	item.height = p_height
	item.allowed_slots = p_slots
	item.weight = p_weight
	item.gold_value = p_gold
	item.primary_color = p_primary
	item.accent_color = p_accent
	item.cannon_damage = p_damage
	item.reload_time = p_reload
	item.cannon_range = p_range
	item.projectile_speed = p_proj_speed
	item.chain_shot_slow = p_chain_slow
	item.spread_angle_deg = p_spread
	item.speed_bonus = p_speed_bonus
	item.turn_bonus = p_turn_bonus
	item.armor_bonus = p_armor_bonus
	item.max_hp_bonus = p_hp_bonus
	item.reload_synergy_bonus = p_reload_synergy
	item.explosion_hazard = p_explosion_hazard
	item.burn_dps = p_burn_dps
	item.harpoon_pull = p_harpoon_pull
	item.ram_damage_bonus = p_ram_damage_bonus
	item.passive_repair_rate = p_passive_repair_rate
	item.vision_bonus = p_vision_bonus
	_TEMPLATES[p_id] = item


static func get_all_ids() -> Array[String]:
	_ensure_templates()
	var ids: Array[String] = []
	for key in _TEMPLATES.keys():
		ids.append(str(key))
	return ids


static func create_item(item_id: String, affix: int = Contracts.ItemAffix.STANDARD) -> Contracts.GridItemData:
	_ensure_templates()
	var tmpl: Contracts.GridItemData = _TEMPLATES.get(item_id, null)
	if tmpl == null:
		tmpl = _TEMPLATES["rum_casks_1x1"]
	var copy: Contracts.GridItemData = tmpl.duplicate_item(affix)
	_instance_counter += 1
	copy.instance_id = "%s_%d_%d" % [copy.id, _instance_counter, Time.get_ticks_usec()]
	copy.grid_pos = Vector2i(-1, -1)
	copy.rotated = false
	return copy


static func roll_random_affix(rng: RandomNumberGenerator = null) -> int:
	var roll: float = rng.randf() if rng != null else randf()
	if roll < 0.18:
		return Contracts.ItemAffix.RUSTED
	elif roll < 0.72:
		return Contracts.ItemAffix.STANDARD
	elif roll < 0.92:
		return Contracts.ItemAffix.MASTERWORK
	else:
		return Contracts.ItemAffix.CURSED


static func create_random_item(rng: RandomNumberGenerator = null, include_cargo: bool = true) -> Contracts.GridItemData:
	_ensure_templates()
	var candidates: Array[String] = []
	for key in _TEMPLATES.keys():
		var id_str: String = str(key)
		var tmpl: Contracts.GridItemData = _TEMPLATES[id_str]
		if not include_cargo and (tmpl.category == Contracts.ItemCategory.CARGO or tmpl.category == Contracts.ItemCategory.TREASURE):
			continue
		candidates.append(id_str)

	if candidates.is_empty():
		candidates = get_all_ids()

	var idx: int = rng.randi_range(0, candidates.size() - 1) if rng != null else randi_range(0, candidates.size() - 1)
	var picked_id: String = candidates[idx]
	var affix: int = roll_random_affix(rng)
	return create_item(picked_id, affix)

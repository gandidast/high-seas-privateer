class_name Contracts
extends Node
## Central architecture contracts, enums, data structures, EventBus signals,
## and the 100% deterministic water depth & island generator function shared
## between res://visual/ (shaders/rendering), res://sim/ (physics/server/world),
## res://ui/, and res://net/.
##
## Registered as Autoload `EventBus` in project.godot and globally accessible
## via both `Contracts` (class_name) and `EventBus` (Autoload singleton).

const DEFAULT_WORLD_SEED: int = 1337420
const WORLD_HALF_EXTENT: float = 2400.0
const SERVER_DEFAULT_PORT: int = 8080

# Water depth thresholds returned by get_water_depth(world_pos, world_seed):
#   depth <= 0.0        -> Solid land / island collision (beach: 0.0..-0.18, vegetation: -0.18..-0.55, rock peak: < -0.55)
#   0.0 < depth < 0.22  -> Shallow water / shoals (turquoise water + foam rings)
#   depth >= 0.22       -> Deep navigable ocean
const LAND_THRESHOLD: float = 0.0
const SHALLOW_THRESHOLD: float = 0.22
const FOAM_THRESHOLD: float = 0.085

# ==============================================================================
# CENTRAL ENUMS
# ==============================================================================

enum SlotType {
	NONE = 0,
	DECK_PORT = 1,       ## Left broadside rail slots (cannons fire portside)
	DECK_STARBOARD = 2,  ## Right broadside rail slots (cannons fire starboard)
	MAST = 3,            ## Centerline rigging/sail slots
	CARGO_HOLD = 4,      ## Interior hold / general hull slots
	ANY = 5              ## Universal slot
}

enum ItemRarity {
	COMMON = 0,
	UNCOMMON = 1,
	RARE = 2,
	LEGENDARY = 3,
	CURSED = 4
}

enum ItemAffix {
	STANDARD = 0,        ## Standard (1.0x stats)
	RUSTED = 1,          ## Verrostet (-20% performance, -35% value)
	MASTERWORK = 2,      ## Meisterhaft (+25% performance, +60% value)
	CURSED = 3           ## Verflucht (+45% damage/speed, but adds hull/explosion penalty)
}

enum ItemCategory {
	CANNON = 0,
	POWDER_BARREL = 1,
	SAIL = 2,
	HULL = 3,
	CARGO = 4,
	TREASURE = 5,
	CREW_MOD = 6,
	BOW_WEAPON = 7
}

enum ShipClass {
	SLOOP = 0,       ## Schaluppe (Tier 0: wendig, 1 Mast, Starter)
	BRIGANTINE = 1,  ## Brigg (Tier 1: Allrounder, 2 Masten, mehr Kanonenplätze)
	FRIGATE = 2      ## Schwere Fregatte / Galeone (Tier 2: volles 8x6 Grid, 3 Masten, schwere Panzerung)
}

enum WeatherState {
	CLEAR = 0,       ## Klare See & Sonnenschein
	FOG = 1,         ## Dichter Seenebel (reduzierte Sicht, mystische Atmosphäre)
	STORM = 2        ## Sturmfront mit starken Böen, hohen Wellen & Blitzen
}

enum ShipFaction {
	PLAYER = 0,
	PIRATE = 1,
	MERCHANT = 2,
	NAVY = 3,
	NEUTRAL = 4
}

enum SailState {
	ANCHORED = 0,        ## 0% sail thrust
	HALF_SAIL = 1,       ## ~55% sail thrust, tighter turning
	FULL_SAIL = 2        ## 100% sail thrust
}

enum AIState {
	PATROL = 0,
	ENGAGE_BROADSIDE = 1,
	FLEE_TO_PORT = 2
}

enum QuestType {
	BOUNTY = 0,          ## Kopfgeldjagd auf Piratenkapitän
	DELIVERY = 1,        ## Handelslieferung zu Zielhafen
	SALVAGE = 2          ## Bergungsmission (Treibgut / Schatzkiste bergen)
}

# ==============================================================================
# SIGNAL BUS (EventBus Autoload)
# ==============================================================================

# Environment & World
signal wind_changed(direction: Vector2, strength: float)
signal world_initialized(world_seed: int, islands: Array)
signal weather_changed(weather_state: int, intensity: float)
signal lightning_flash(world_pos: Vector2)

# Ship Lifecycle & Physics -> Visuals/UI/Net
signal ship_spawned(ship_id: int, ship_data: Dictionary)
signal ship_despawned(ship_id: int)
signal ship_state_updated(ship_id: int, world_pos: Vector2, heading: float, speed: float, sail_state: int, hp: float, max_hp: float)
signal ship_stats_compiled(ship_id: int, stats: ShipStats)
signal ship_grid_updated(ship_id: int, equipped_items: Array)
signal ship_coast_scraped(ship_id: int, world_pos: Vector2, normal: Vector2, impact_speed: float)
signal ship_class_upgraded(ship_id: int, new_hull_tier: int, class_title: String)

# Combat, Forts, Sea Monsters & FX
signal broadside_fired(ship_id: int, is_starboard: bool, origin: Vector2, dir: Vector2, cannons: Array)
signal cannonball_spawned(shot_data: Dictionary)
signal cannonball_impact(world_pos: Vector2, hit_ship_id: int, damage: float, is_water_splash: bool, is_powder_crit: bool)
signal ship_damaged(ship_id: int, damage: float, new_hp: float, max_hp: float, world_pos: Vector2)
signal ship_sunk(ship_id: int, world_pos: Vector2, faction: int, killer_ship_id: int)
signal wanted_level_changed(new_level: int)
signal fort_spawned(fort_id: int, world_pos: Vector2, island_index: int, max_hp: float)
signal fort_damaged(fort_id: int, hp: float, max_hp: float, world_pos: Vector2)
signal fort_destroyed(fort_id: int, world_pos: Vector2)
signal sea_monster_spawned(monster_id: int, world_pos: Vector2, max_hp: float)
signal sea_monster_updated(monster_id: int, world_pos: Vector2, hp: float, max_hp: float, phase: int)
signal sea_monster_defeated(monster_id: int, world_pos: Vector2)

# Loot, Economy, Harbors & Quests
signal loot_spawned(loot_data: LootDropData)
signal loot_collected(drop_id: int, collector_ship_id: int, loot_data: LootDropData)
signal harbor_entered(ship_id: int, island_index: int, island_name: String)
signal harbor_exited(ship_id: int, island_index: int)
signal harbor_ui_requested(open: bool, island_index: int)
signal cargo_grid_toggled(open: bool)
signal gold_changed(new_gold: int, delta: int)
signal ship_repaired(ship_id: int, new_hp: float, max_hp: float, cost_gold: int)
signal quest_accepted(quest: QuestData)
signal quest_completed(quest: QuestData)
signal quest_list_updated(quests: Array)

# Networking & Notifications
signal network_mode_changed(mode: String, is_server: bool)
signal notification_posted(message: String, category: String)

static var _fallback_bus: Node = null

func _enter_tree() -> void:
	_fallback_bus = self

static func bus() -> Variant:
	var ml := Engine.get_main_loop() as SceneTree
	if ml != null and ml.root != null:
		var node: Node = ml.root.get_node_or_null("EventBus")
		if node != null:
			return node
	if _fallback_bus == null:
		var script_res := ResourceLoader.load("res://shared/contracts.gd") as Script
		if script_res != null:
			_fallback_bus = script_res.new()
	return _fallback_bus

# ==============================================================================
# DATA STRUCTURES
# ==============================================================================

class GridItemData extends Resource:
	@export var id: String = ""
	@export var name: String = ""
	@export var description: String = ""
	@export var category: int = ItemCategory.CARGO
	@export var rarity: int = ItemRarity.COMMON
	@export var affix: int = ItemAffix.STANDARD
	@export var width: int = 1
	@export var height: int = 1
	@export var allowed_slots: Array[int] = [SlotType.CARGO_HOLD]
	@export var weight: float = 4.0
	@export var gold_value: int = 25

	# Combat / Cannon stats
	@export var cannon_damage: float = 0.0
	@export var reload_time: float = 3.0
	@export var cannon_range: float = 260.0
	@export var projectile_speed: float = 220.0
	@export var chain_shot_slow: float = 0.0
	@export var spread_angle_deg: float = 6.0

	# Ship & Synergy modifiers
	@export var speed_bonus: float = 0.0
	@export var turn_bonus: float = 0.0
	@export var armor_bonus: float = 0.0
	@export var max_hp_bonus: float = 0.0
	@export var reload_synergy_bonus: float = 0.0  ## e.g. 0.25 = +25% reload speed for adjacent cannons
	@export var explosion_hazard: float = 0.0      ## Extra damage taken on hull hit when equipped
	@export var burn_dps: float = 0.0              ## Fire damage over time (Greek Fire / Alchemist Powder)
	@export var harpoon_pull: float = 0.0          ## Pull force on hit (Harpoon Ballista)
	@export var ram_damage_bonus: float = 0.0      ## Hull ramming impact bonus (Iron Ram)
	@export var passive_repair_rate: float = 0.0   ## Hull HP regenerated per second (Carpenter Workshop)
	@export var vision_bonus: float = 0.0          ## Extra aim cone & minimap range (Crow's Nest)

	# Visual tint / style hint for procedural ship baker & UI
	@export var primary_color: Color = Color(0.55, 0.42, 0.28)
	@export var accent_color: Color = Color(0.85, 0.72, 0.35)

	# Runtime placement state inside DredgeGrid
	var instance_id: String = ""
	var grid_pos: Vector2i = Vector2i(-1, -1)
	var rotated: bool = false

	func get_effective_size() -> Vector2i:
		return Vector2i(height, width) if rotated else Vector2i(width, height)

	func get_affix_prefix() -> String:
		match affix:
			ItemAffix.RUSTED:
				return "Verrostet: "
			ItemAffix.MASTERWORK:
				return "Meisterhaft: "
			ItemAffix.CURSED:
				return "Verflucht: "
			_:
				return ""

	func get_display_name() -> String:
		return get_affix_prefix() + name

	func get_affix_stat_multiplier() -> float:
		match affix:
			ItemAffix.RUSTED:
				return 0.80
			ItemAffix.MASTERWORK:
				return 1.25
			ItemAffix.CURSED:
				return 1.45
			_:
				return 1.0

	func get_effective_damage() -> float:
		return cannon_damage * get_affix_stat_multiplier()

	func get_effective_reload_time(synergy_mult: float = 1.0) -> float:
		var base_reload: float = maxf(0.4, reload_time)
		if affix == ItemAffix.RUSTED:
			base_reload *= 1.20
		elif affix == ItemAffix.MASTERWORK:
			base_reload *= 0.85
		elif affix == ItemAffix.CURSED:
			base_reload *= 0.78
		return maxf(0.35, base_reload / maxf(0.25, synergy_mult))

	func get_effective_gold_value() -> int:
		match affix:
			ItemAffix.RUSTED:
				return maxi(1, int(round(float(gold_value) * 0.65)))
			ItemAffix.MASTERWORK:
				return int(round(float(gold_value) * 1.60))
			ItemAffix.CURSED:
				return int(round(float(gold_value) * 1.35))
			_:
				return gold_value

	func duplicate_item(new_affix: int = -1) -> GridItemData:
		var copy := GridItemData.new()
		copy.id = id
		copy.name = name
		copy.description = description
		copy.category = category
		copy.rarity = rarity
		copy.affix = affix if new_affix < 0 else new_affix
		copy.width = width
		copy.height = height
		copy.allowed_slots = allowed_slots.duplicate()
		copy.weight = weight
		copy.gold_value = gold_value
		copy.cannon_damage = cannon_damage
		copy.reload_time = reload_time
		copy.cannon_range = cannon_range
		copy.projectile_speed = projectile_speed
		copy.chain_shot_slow = chain_shot_slow
		copy.spread_angle_deg = spread_angle_deg
		copy.speed_bonus = speed_bonus
		copy.turn_bonus = turn_bonus
		copy.armor_bonus = armor_bonus
		copy.max_hp_bonus = max_hp_bonus
		copy.reload_synergy_bonus = reload_synergy_bonus
		copy.explosion_hazard = explosion_hazard
		copy.burn_dps = burn_dps
		copy.harpoon_pull = harpoon_pull
		copy.ram_damage_bonus = ram_damage_bonus
		copy.passive_repair_rate = passive_repair_rate
		copy.vision_bonus = vision_bonus
		copy.primary_color = primary_color
		copy.accent_color = accent_color
		copy.instance_id = "%s_%d" % [id, Time.get_ticks_usec()]
		copy.grid_pos = grid_pos
		copy.rotated = rotated
		return copy

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"description": description,
			"category": category,
			"rarity": rarity,
			"affix": affix,
			"width": width,
			"height": height,
			"allowed_slots": allowed_slots.duplicate(),
			"weight": weight,
			"gold_value": gold_value,
			"cannon_damage": cannon_damage,
			"reload_time": reload_time,
			"cannon_range": cannon_range,
			"projectile_speed": projectile_speed,
			"chain_shot_slow": chain_shot_slow,
			"spread_angle_deg": spread_angle_deg,
			"speed_bonus": speed_bonus,
			"turn_bonus": turn_bonus,
			"armor_bonus": armor_bonus,
			"max_hp_bonus": max_hp_bonus,
			"reload_synergy_bonus": reload_synergy_bonus,
			"explosion_hazard": explosion_hazard,
			"burn_dps": burn_dps,
			"harpoon_pull": harpoon_pull,
			"ram_damage_bonus": ram_damage_bonus,
			"passive_repair_rate": passive_repair_rate,
			"vision_bonus": vision_bonus,
			"primary_color": primary_color.to_html(),
			"accent_color": accent_color.to_html(),
			"instance_id": instance_id,
			"grid_x": grid_pos.x,
			"grid_y": grid_pos.y,
			"rotated": rotated
		}

	static func from_dict(d: Dictionary) -> GridItemData:
		var item := GridItemData.new()
		item.id = str(d.get("id", ""))
		item.name = str(d.get("name", ""))
		item.description = str(d.get("description", ""))
		item.category = int(d.get("category", ItemCategory.CARGO))
		item.rarity = int(d.get("rarity", ItemRarity.COMMON))
		item.affix = int(d.get("affix", ItemAffix.STANDARD))
		item.width = int(d.get("width", 1))
		item.height = int(d.get("height", 1))
		var raw_slots: Array = d.get("allowed_slots", [SlotType.CARGO_HOLD])
		item.allowed_slots.clear()
		for s in raw_slots:
			item.allowed_slots.append(int(s))
		item.weight = float(d.get("weight", 4.0))
		item.gold_value = int(d.get("gold_value", 25))
		item.cannon_damage = float(d.get("cannon_damage", 0.0))
		item.reload_time = float(d.get("reload_time", 3.0))
		item.cannon_range = float(d.get("cannon_range", 260.0))
		item.projectile_speed = float(d.get("projectile_speed", 220.0))
		item.chain_shot_slow = float(d.get("chain_shot_slow", 0.0))
		item.spread_angle_deg = float(d.get("spread_angle_deg", 6.0))
		item.speed_bonus = float(d.get("speed_bonus", 0.0))
		item.turn_bonus = float(d.get("turn_bonus", 0.0))
		item.armor_bonus = float(d.get("armor_bonus", 0.0))
		item.max_hp_bonus = float(d.get("max_hp_bonus", 0.0))
		item.reload_synergy_bonus = float(d.get("reload_synergy_bonus", 0.0))
		item.explosion_hazard = float(d.get("explosion_hazard", 0.0))
		item.burn_dps = float(d.get("burn_dps", 0.0))
		item.harpoon_pull = float(d.get("harpoon_pull", 0.0))
		item.ram_damage_bonus = float(d.get("ram_damage_bonus", 0.0))
		item.passive_repair_rate = float(d.get("passive_repair_rate", 0.0))
		item.vision_bonus = float(d.get("vision_bonus", 0.0))
		if d.has("primary_color"):
			item.primary_color = Color.html(str(d["primary_color"]))
		if d.has("accent_color"):
			item.accent_color = Color.html(str(d["accent_color"]))
		item.instance_id = str(d.get("instance_id", "%s_net" % item.id))
		item.grid_pos = Vector2i(int(d.get("grid_x", -1)), int(d.get("grid_y", -1)))
		item.rotated = bool(d.get("rotated", false))
		return item


class ShipStats extends RefCounted:
	var hull_tier: int = 0                ## 0 = Schaluppe, 1 = Brigg, 2 = Schwere Fregatte/Galeone
	var base_max_hp: float = 120.0
	var max_hp: float = 120.0
	var armor: float = 0.0
	var base_max_speed: float = 95.0
	var max_speed: float = 95.0
	var acceleration: float = 48.0
	var turn_speed: float = 1.75
	var rudder_inertia: float = 6.5
	var min_upwind_factor: float = 0.42
	var total_weight: float = 0.0
	var max_safe_weight: float = 45.0
	var cargo_weight_penalty: float = 0.0  ## 0.0 .. 0.45 speed/turn reduction
	var port_cannons: Array = []          ## Array[Dictionary] of compiled port cannon mounts
	var starboard_cannons: Array = []     ## Array[Dictionary] of compiled starboard cannon mounts
	var port_salvo_damage: float = 0.0
	var starboard_salvo_damage: float = 0.0
	var port_reload_multiplier: float = 1.0
	var starboard_reload_multiplier: float = 1.0
	var explosion_hazard_damage: float = 0.0
	var powder_barrel_count: int = 0
	var sail_upgrade_count: int = 0
	var passive_repair_rate: float = 0.0
	var ram_damage_bonus: float = 0.0
	var vision_bonus: float = 0.0
	var burn_bonus_dps: float = 0.0
	var visual_equipped_items: Array = [] ## Array[Dictionary] for 2D sprite-stacking deck socket rendering

	func to_dict() -> Dictionary:
		return {
			"hull_tier": hull_tier,
			"max_hp": max_hp,
			"armor": armor,
			"max_speed": max_speed,
			"acceleration": acceleration,
			"turn_speed": turn_speed,
			"rudder_inertia": rudder_inertia,
			"min_upwind_factor": min_upwind_factor,
			"total_weight": total_weight,
			"cargo_weight_penalty": cargo_weight_penalty,
			"port_cannons": port_cannons.duplicate(true),
			"starboard_cannons": starboard_cannons.duplicate(true),
			"port_salvo_damage": port_salvo_damage,
			"starboard_salvo_damage": starboard_salvo_damage,
			"port_reload_multiplier": port_reload_multiplier,
			"starboard_reload_multiplier": starboard_reload_multiplier,
			"explosion_hazard_damage": explosion_hazard_damage,
			"powder_barrel_count": powder_barrel_count,
			"sail_upgrade_count": sail_upgrade_count,
			"passive_repair_rate": passive_repair_rate,
			"ram_damage_bonus": ram_damage_bonus,
			"vision_bonus": vision_bonus,
			"burn_bonus_dps": burn_bonus_dps,
			"visual_equipped_items": visual_equipped_items.duplicate(true)
		}

	static func from_dict(d: Dictionary) -> ShipStats:
		var s := ShipStats.new()
		s.hull_tier = int(d.get("hull_tier", 0))
		s.max_hp = float(d.get("max_hp", 120.0))
		s.armor = float(d.get("armor", 0.0))
		s.max_speed = float(d.get("max_speed", 95.0))
		s.acceleration = float(d.get("acceleration", 48.0))
		s.turn_speed = float(d.get("turn_speed", 1.75))
		s.rudder_inertia = float(d.get("rudder_inertia", 6.5))
		s.min_upwind_factor = float(d.get("min_upwind_factor", 0.42))
		s.total_weight = float(d.get("total_weight", 0.0))
		s.cargo_weight_penalty = float(d.get("cargo_weight_penalty", 0.0))
		s.port_cannons = d.get("port_cannons", []).duplicate(true)
		s.starboard_cannons = d.get("starboard_cannons", []).duplicate(true)
		s.port_salvo_damage = float(d.get("port_salvo_damage", 0.0))
		s.starboard_salvo_damage = float(d.get("starboard_salvo_damage", 0.0))
		s.port_reload_multiplier = float(d.get("port_reload_multiplier", 1.0))
		s.starboard_reload_multiplier = float(d.get("starboard_reload_multiplier", 1.0))
		s.explosion_hazard_damage = float(d.get("explosion_hazard_damage", 0.0))
		s.powder_barrel_count = int(d.get("powder_barrel_count", 0))
		s.sail_upgrade_count = int(d.get("sail_upgrade_count", 0))
		s.passive_repair_rate = float(d.get("passive_repair_rate", 0.0))
		s.ram_damage_bonus = float(d.get("ram_damage_bonus", 0.0))
		s.vision_bonus = float(d.get("vision_bonus", 0.0))
		s.burn_bonus_dps = float(d.get("burn_bonus_dps", 0.0))
		s.visual_equipped_items = d.get("visual_equipped_items", []).duplicate(true)
		return s


class LootDropData extends RefCounted:
	var drop_id: int = 0
	var world_pos: Vector2 = Vector2.ZERO
	var gold: int = 30
	var items: Array = [] ## Array[GridItemData]
	var is_salvage_target: bool = false
	var quest_id: String = ""
	var lifetime: float = 180.0

	func to_dict() -> Dictionary:
		var serialized_items: Array = []
		for item in items:
			if item is GridItemData:
				serialized_items.append(item.to_dict())
			elif item is Dictionary:
				serialized_items.append(item)
		return {
			"drop_id": drop_id,
			"x": world_pos.x,
			"y": world_pos.y,
			"gold": gold,
			"items": serialized_items,
			"is_salvage_target": is_salvage_target,
			"quest_id": quest_id,
			"lifetime": lifetime
		}

	static func from_dict(d: Dictionary) -> LootDropData:
		var drop := LootDropData.new()
		drop.drop_id = int(d.get("drop_id", 0))
		drop.world_pos = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		drop.gold = int(d.get("gold", 30))
		drop.is_salvage_target = bool(d.get("is_salvage_target", false))
		drop.quest_id = str(d.get("quest_id", ""))
		drop.lifetime = float(d.get("lifetime", 180.0))
		var raw_items: Array = d.get("items", [])
		for raw in raw_items:
			if raw is Dictionary:
				drop.items.append(GridItemData.from_dict(raw))
			elif raw is GridItemData:
				drop.items.append(raw)
		return drop


class IslandData extends RefCounted:
	var index: int = 0
	var name: String = ""
	var center: Vector2 = Vector2.ZERO
	var radius: float = 190.0
	var harbor_angle: float = 0.0
	var harbor_pos: Vector2 = Vector2.ZERO
	var harbor_radius: float = 85.0
	var seed_phase: float = 0.0

	func to_dict() -> Dictionary:
		return {
			"index": index,
			"name": name,
			"center": center,
			"radius": radius,
			"harbor_angle": harbor_angle,
			"harbor_pos": harbor_pos,
			"harbor_radius": harbor_radius,
			"seed_phase": seed_phase
		}


class QuestData extends RefCounted:
	var id: String = ""
	var title: String = ""
	var description: String = ""
	var quest_type: int = QuestType.BOUNTY
	var source_island_idx: int = 0
	var target_island_idx: int = 1
	var target_pos: Vector2 = Vector2.ZERO
	var target_ship_id: int = -1
	var target_drop_id: int = -1
	var cargo_item_id: String = ""
	var reward_gold: int = 140
	var completed: bool = false

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"title": title,
			"description": description,
			"quest_type": quest_type,
			"source_island_idx": source_island_idx,
			"target_island_idx": target_island_idx,
			"target_x": target_pos.x,
			"target_y": target_pos.y,
			"target_ship_id": target_ship_id,
			"target_drop_id": target_drop_id,
			"cargo_item_id": cargo_item_id,
			"reward_gold": reward_gold,
			"completed": completed
		}

	static func from_dict(d: Dictionary) -> QuestData:
		var q := QuestData.new()
		q.id = str(d.get("id", ""))
		q.title = str(d.get("title", ""))
		q.description = str(d.get("description", ""))
		q.quest_type = int(d.get("quest_type", QuestType.BOUNTY))
		q.source_island_idx = int(d.get("source_island_idx", 0))
		q.target_island_idx = int(d.get("target_island_idx", 1))
		q.target_pos = Vector2(float(d.get("target_x", 0.0)), float(d.get("target_y", 0.0)))
		q.target_ship_id = int(d.get("target_ship_id", -1))
		q.target_drop_id = int(d.get("target_drop_id", -1))
		q.cargo_item_id = str(d.get("cargo_item_id", ""))
		q.reward_gold = int(d.get("reward_gold", 140))
		q.completed = bool(d.get("completed", false))
		return q


# ==============================================================================
# 100% DETERMINISTIC ISLAND & WATER DEPTH MATH (SHARED BY SHADER & SIMULATION)
# ==============================================================================
# IMPORTANT FOR WORKER 1 (ocean_shader.gdshader) AND WORKER 2 (world_map.gd):
# The island parameters and water depth formula below use pure trigonometric math
# (sin, cos, atan2, length, clamp) so that GLSL in `ocean_shader.gdshader` and
# GDScript in `world_map.gd` / `ship_physics.gd` produce 100% identical results!

const ISLAND_COUNT: int = 6

const ISLAND_NAMES: Array[String] = [
	"Port Tortuga",
	"Smaragd-Atoll",
	"Krakenzahn-Bucht",
	"San Aurelio",
	"Schädelriff-Hafen",
	"Neu-Nassau"
]

# Base island archetypes: Vector4(base_x, base_y, base_radius, harbor_angle_rad)
# Placed around the open central starting sea (0, 0 is deep navigable ocean!).
const BASE_ISLAND_SPECS: Array[Vector4] = [
	Vector4(-560.0, -340.0, 175.0, 0.55),   # 0: Port Tortuga (NW, harbor facing SE toward spawn)
	Vector4(620.0, -380.0, 190.0, 2.45),    # 1: Smaragd-Atoll (NE, harbor facing SW)
	Vector4(-680.0, 440.0, 165.0, -0.50),   # 2: Krakenzahn-Bucht (SW, harbor facing NE)
	Vector4(580.0, 460.0, 200.0, -2.35),    # 3: San Aurelio (SE, harbor facing NW)
	Vector4(0.0, -780.0, 180.0, 1.57),      # 4: Schädelriff-Hafen (North, harbor facing South)
	Vector4(40.0, 820.0, 185.0, -1.57)      # 5: Neu-Nassau (South, harbor facing North)
]

static func _seed_offset(world_seed: int, idx: int) -> Vector3:
	var s: float = float(world_seed % 100000) * 0.0137 + float(idx) * 2.39996
	var dx: float = sin(s * 1.7 + float(idx) * 1.1) * 48.0
	var dy: float = cos(s * 2.3 + float(idx) * 1.9) * 48.0
	var phase: float = fmod(absf(s * 3.14159 + float(idx) * 1.618), 6.2831853)
	return Vector3(dx, dy, phase)

static func get_island_center(idx: int, world_seed: int = DEFAULT_WORLD_SEED) -> Vector2:
	var spec: Vector4 = BASE_ISLAND_SPECS[clampi(idx, 0, ISLAND_COUNT - 1)]
	var off: Vector3 = _seed_offset(world_seed, idx)
	return Vector2(spec.x + off.x, spec.y + off.y)

static func get_island_radius(idx: int, _world_seed: int = DEFAULT_WORLD_SEED) -> float:
	var spec: Vector4 = BASE_ISLAND_SPECS[clampi(idx, 0, ISLAND_COUNT - 1)]
	return spec.z

static func get_island_harbor_angle(idx: int, _world_seed: int = DEFAULT_WORLD_SEED) -> float:
	var spec: Vector4 = BASE_ISLAND_SPECS[clampi(idx, 0, ISLAND_COUNT - 1)]
	return spec.w

static func get_island_phase(idx: int, world_seed: int = DEFAULT_WORLD_SEED) -> float:
	return _seed_offset(world_seed, idx).z

## Evaluates the exact coastline radius of island `idx` at angle `theta` (in radians).
## Identical in GDScript and GLSL shader.
static func get_island_coast_radius(idx: int, theta: float, world_seed: int = DEFAULT_WORLD_SEED) -> float:
	var base_r: float = get_island_radius(idx, world_seed)
	var phase: float = get_island_phase(idx, world_seed)
	var harbor_angle: float = get_island_harbor_angle(idx, world_seed)

	# Multi-harmonic organic coastline wobble
	var wave: float = (
		0.14 * sin(theta * 3.0 + phase)
		+ 0.09 * cos(theta * 5.0 - phase * 1.3)
		+ 0.05 * sin(theta * 7.0 + phase * 2.1)
	)

	# Carve a natural crescent harbor cove at `harbor_angle` so ships have a sheltered bay
	var angle_diff: float = wrapf(theta - harbor_angle, -PI, PI)
	var cove_factor: float = exp(-(angle_diff * angle_diff) / 0.18)
	var effective_r: float = base_r * (1.0 + wave - 0.28 * cove_factor)
	return effective_r

## Returns the deterministic array of all 6 named islands and their safe harbor zones.
static func get_islands(world_seed: int = DEFAULT_WORLD_SEED) -> Array[IslandData]:
	var result: Array[IslandData] = []
	for i in range(ISLAND_COUNT):
		var isl := IslandData.new()
		isl.index = i
		isl.name = ISLAND_NAMES[i]
		isl.center = get_island_center(i, world_seed)
		isl.radius = get_island_radius(i, world_seed)
		isl.harbor_angle = get_island_harbor_angle(i, world_seed)
		isl.seed_phase = get_island_phase(i, world_seed)
		var coast_r_at_harbor: float = get_island_coast_radius(i, isl.harbor_angle, world_seed)
		var dir := Vector2(cos(isl.harbor_angle), sin(isl.harbor_angle))
		# Place harbor safe-zone center 46px outside the cove shoreline (guaranteed navigable water!)
		isl.harbor_pos = isl.center + dir * (coast_r_at_harbor + 46.0)
		isl.harbor_radius = 85.0
		result.append(isl)
	return result

## Returns packed island uniforms for `ocean_shader.gdshader`:
## Each element is Vector4(center.x, center.y, base_radius, seed_phase)
static func get_shader_island_centers(world_seed: int = DEFAULT_WORLD_SEED) -> PackedVector4Array:
	var arr := PackedVector4Array()
	for i in range(ISLAND_COUNT):
		var c: Vector2 = get_island_center(i, world_seed)
		var r: float = get_island_radius(i, world_seed)
		var p: float = get_island_phase(i, world_seed)
		arr.append(Vector4(c.x, c.y, r, p))
	return arr

## Returns packed harbor angles for `ocean_shader.gdshader`
static func get_shader_harbor_angles(world_seed: int = DEFAULT_WORLD_SEED) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for i in range(ISLAND_COUNT):
		arr.append(get_island_harbor_angle(i, world_seed))
	return arr

## EXACT deterministic water depth function used by both Simulation and Ocean Shader.
## Convention:
##   > 0.0  : Water (0.0 = shoreline, 0.0..0.22 = turquoise shallow shoals, 0.22..1.0 = deep ocean)
##   <= 0.0 : Island land (0.0..-0.18 = sandy beach, -0.18..-0.55 = lush green/palms, < -0.55 = rock peak)
static func get_water_depth(world_pos: Vector2, world_seed: int = DEFAULT_WORLD_SEED) -> float:
	var min_signed_depth: float = 1.0
	var transition_band: float = 140.0

	for i in range(ISLAND_COUNT):
		var center: Vector2 = get_island_center(i, world_seed)
		var rel: Vector2 = world_pos - center
		var dist: float = rel.length()
		var base_r: float = get_island_radius(i, world_seed)
		# Fast bounding check before trigonometry
		if dist > base_r * 1.35 + transition_band * 1.5:
			continue
		var theta: float = atan2(rel.y, rel.x)
		var coast_r: float = get_island_coast_radius(i, theta, world_seed)
		var signed_dist: float = (dist - coast_r) / transition_band
		if signed_dist < min_signed_depth:
			min_signed_depth = signed_dist

	# Subtle open-sea depth undulation (never creates unmapped land, keeps open sea > 0.28)
	var seed_f: float = float(world_seed % 10000) * 0.0071
	var sea_wave: float = (
		sin(world_pos.x * 0.0045 + seed_f) * cos(world_pos.y * 0.0045 - seed_f) * 0.08
		+ sin((world_pos.x + world_pos.y) * 0.009 + seed_f * 2.0) * 0.04
	)

	if min_signed_depth > 0.22:
		return clampf(min_signed_depth + sea_wave, 0.23, 1.0)
	elif min_signed_depth > 0.0:
		# Smoothly blend sea_wave to 0 at shoreline so coast is 100% exact
		var t: float = min_signed_depth / 0.22
		return clampf(min_signed_depth + sea_wave * t * 0.25, 0.001, 1.0)
	else:
		return clampf(min_signed_depth, -1.0, 0.0)

static func is_land(world_pos: Vector2, world_seed: int = DEFAULT_WORLD_SEED) -> bool:
	return get_water_depth(world_pos, world_seed) <= LAND_THRESHOLD

static func is_shallow(world_pos: Vector2, world_seed: int = DEFAULT_WORLD_SEED) -> bool:
	var d: float = get_water_depth(world_pos, world_seed)
	return d > LAND_THRESHOLD and d < SHALLOW_THRESHOLD

## Computes the outward normal pointing from land toward deeper water.
static func get_coast_normal(world_pos: Vector2, world_seed: int = DEFAULT_WORLD_SEED) -> Vector2:
	var eps: float = 4.0
	var dx: float = get_water_depth(world_pos + Vector2(eps, 0.0), world_seed) - get_water_depth(world_pos - Vector2(eps, 0.0), world_seed)
	var dy: float = get_water_depth(world_pos + Vector2(0.0, eps), world_seed) - get_water_depth(world_pos - Vector2(0.0, eps), world_seed)
	var grad := Vector2(dx, dy)
	if grad.length_squared() < 0.000001:
		return Vector2.UP
	return grad.normalized()

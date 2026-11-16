class_name DredgeGrid
extends Node
## Dredge-inspired 8x6 Tetris ship inventory & stat compiler.
## Handles 3 ship classes (Sloop/Brigantine/Frigate), slot-type constraints,
## adjacency synergies (powder barrels, alchemist powder, gunner quarters),
## crew/hull/sail upgrades, and weight penalties.

const GRID_WIDTH: int = 8
const GRID_HEIGHT: int = 6

var ship_id: int = 1
var hull_tier: int = Contracts.ShipClass.SLOOP
var placed_items: Array[Contracts.GridItemData] = []
var stash_items: Array[Contracts.GridItemData] = []
var current_stats: Contracts.ShipStats = Contracts.ShipStats.new()


func set_hull_tier(new_tier: int) -> void:
	hull_tier = clampi(new_tier, Contracts.ShipClass.SLOOP, Contracts.ShipClass.FRIGATE)
	compile_stats()


func get_slot_type(gx: int, gy: int) -> int:
	if gx < 0 or gx >= GRID_WIDTH or gy < 0 or gy >= GRID_HEIGHT:
		return Contracts.SlotType.NONE
	if gy == 0:
		return Contracts.SlotType.DECK_PORT
	if gy == 5:
		return Contracts.SlotType.DECK_STARBOARD
	if (gy == 2 or gy == 3) and gx >= 2 and gx <= 5:
		return Contracts.SlotType.MAST
	return Contracts.SlotType.CARGO_HOLD


func get_item_cells(item: Contracts.GridItemData, gx: int, gy: int, is_rotated: bool) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if item == null:
		return cells
	var w: int = item.height if is_rotated else item.width
	var h: int = item.width if is_rotated else item.height
	for dy in range(h):
		for dx in range(w):
			cells.append(Vector2i(gx + dx, gy + dy))
	return cells


func get_item_at(gx: int, gy: int) -> Contracts.GridItemData:
	if gx < 0 or gx >= GRID_WIDTH or gy < 0 or gy >= GRID_HEIGHT:
		return null
	for item in placed_items:
		var cells: Array[Vector2i] = get_item_cells(item, item.grid_pos.x, item.grid_pos.y, item.rotated)
		for c in cells:
			if c.x == gx and c.y == gy:
				return item
	return null


func _is_slot_compatible(item: Contracts.GridItemData, slot_type: int) -> bool:
	if slot_type == Contracts.SlotType.NONE:
		return false
	if Contracts.SlotType.ANY in item.allowed_slots:
		return true
	if item.category == Contracts.ItemCategory.CANNON:
		return (
			slot_type == Contracts.SlotType.DECK_PORT
			or slot_type == Contracts.SlotType.DECK_STARBOARD
			or slot_type == Contracts.SlotType.CARGO_HOLD
		)
	return slot_type in item.allowed_slots


func can_place_item(item: Contracts.GridItemData, gx: int, gy: int, is_rotated: bool) -> bool:
	if item == null:
		return false
	var w: int = item.height if is_rotated else item.width
	var h: int = item.width if is_rotated else item.height
	if gx < 0 or gy < 0 or gx + w > GRID_WIDTH or gy + h > GRID_HEIGHT:
		return false

	var candidate_cells: Array[Vector2i] = get_item_cells(item, gx, gy, is_rotated)
	for c in candidate_cells:
		var slot: int = get_slot_type(c.x, c.y)
		if not _is_slot_compatible(item, slot):
			return false
		var occupant: Contracts.GridItemData = get_item_at(c.x, c.y)
		if occupant != null and occupant != item and occupant.instance_id != item.instance_id:
			return false

	return true


func place_item(item: Contracts.GridItemData, gx: int, gy: int, is_rotated: bool) -> bool:
	if not can_place_item(item, gx, gy, is_rotated):
		return false

	remove_from_stash(item)
	if not (item in placed_items):
		placed_items.append(item)

	item.grid_pos = Vector2i(gx, gy)
	item.rotated = is_rotated
	compile_stats()
	return true


func remove_item(item: Contracts.GridItemData, move_item_to_stash: bool = false) -> bool:
	if item == null:
		return false
	var idx: int = placed_items.find(item)
	if idx < 0:
		return false
	placed_items.remove_at(idx)
	item.grid_pos = Vector2i(-1, -1)
	if move_item_to_stash and not (item in stash_items):
		stash_items.append(item)
	compile_stats()
	return true


func add_to_stash(item: Contracts.GridItemData) -> void:
	if item == null:
		return
	var idx: int = placed_items.find(item)
	if idx >= 0:
		placed_items.remove_at(idx)
	item.grid_pos = Vector2i(-1, -1)
	if not (item in stash_items):
		stash_items.append(item)
	compile_stats()


func remove_from_stash(item: Contracts.GridItemData) -> bool:
	if item == null:
		return false
	var idx: int = stash_items.find(item)
	if idx >= 0:
		stash_items.remove_at(idx)
		return true
	return false


func rotate_item_in_grid(item: Contracts.GridItemData) -> bool:
	if item == null or not (item in placed_items):
		return false
	var next_rot: bool = not item.rotated
	if can_place_item(item, item.grid_pos.x, item.grid_pos.y, next_rot):
		item.rotated = next_rot
		compile_stats()
		return true
	return false


func auto_place_item(item: Contracts.GridItemData) -> bool:
	if item == null:
		return false
	for gy in range(GRID_HEIGHT):
		for gx in range(GRID_WIDTH):
			if can_place_item(item, gx, gy, false):
				return place_item(item, gx, gy, false)
			if item.width != item.height and can_place_item(item, gx, gy, true):
				return place_item(item, gx, gy, true)
	return false


func populate_starter_loadout() -> void:
	placed_items.clear()
	stash_items.clear()

	var port_gun := ItemDatabase.create_item("swivel_gun_1x2", Contracts.ItemAffix.STANDARD)
	var starboard_gun := ItemDatabase.create_item("swivel_gun_1x2", Contracts.ItemAffix.STANDARD)
	var powder := ItemDatabase.create_item("powder_barrel_1x1", Contracts.ItemAffix.STANDARD)
	var sail := ItemDatabase.create_item("silk_top_sail_1x2", Contracts.ItemAffix.STANDARD)
	var rum := ItemDatabase.create_item("rum_casks_1x1", Contracts.ItemAffix.STANDARD)

	# Place directly before a single compile_stats() call
	port_gun.grid_pos = Vector2i(2, 0)
	port_gun.rotated = false
	placed_items.append(port_gun)

	starboard_gun.grid_pos = Vector2i(2, 4)
	starboard_gun.rotated = false
	placed_items.append(starboard_gun)

	powder.grid_pos = Vector2i(3, 0)
	powder.rotated = false
	placed_items.append(powder)

	sail.grid_pos = Vector2i(3, 2)
	sail.rotated = false
	placed_items.append(sail)

	rum.grid_pos = Vector2i(0, 1)
	rum.rotated = false
	placed_items.append(rum)

	compile_stats()


func _cells_adjacent(cells_a: Array[Vector2i], cells_b: Array[Vector2i]) -> bool:
	for a in cells_a:
		for b in cells_b:
			if absi(a.x - b.x) + absi(a.y - b.y) == 1:
				return true
	return false


func _is_cannon_mounted_side(cannon: Contracts.GridItemData) -> Dictionary:
	var cells: Array[Vector2i] = get_item_cells(cannon, cannon.grid_pos.x, cannon.grid_pos.y, cannon.rotated)
	var port: bool = false
	var starboard: bool = false
	for c in cells:
		var slot: int = get_slot_type(c.x, c.y)
		if slot == Contracts.SlotType.DECK_PORT:
			port = true
		elif slot == Contracts.SlotType.DECK_STARBOARD:
			starboard = true
	return {"port": port, "starboard": starboard, "cells": cells}


func _is_synergy_source(item: Contracts.GridItemData) -> bool:
	if item == null:
		return false
	return item.reload_synergy_bonus > 0.0 or item.burn_dps > 0.0 and item.category != Contracts.ItemCategory.CANNON


func get_adjacent_synergy_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var sources: Array[Contracts.GridItemData] = []
	var mounted_cannons: Array[Contracts.GridItemData] = []

	for item in placed_items:
		if _is_synergy_source(item):
			sources.append(item)
		elif item.category == Contracts.ItemCategory.CANNON:
			var side: Dictionary = _is_cannon_mounted_side(item)
			if bool(side["port"]) or bool(side["starboard"]):
				mounted_cannons.append(item)

	for src in sources:
		var s_cells: Array[Vector2i] = get_item_cells(src, src.grid_pos.x, src.grid_pos.y, src.rotated)
		for cannon in mounted_cannons:
			var c_cells: Array[Vector2i] = get_item_cells(cannon, cannon.grid_pos.x, cannon.grid_pos.y, cannon.rotated)
			if _cells_adjacent(s_cells, c_cells):
				for sc in s_cells:
					if not (sc in result):
						result.append(sc)
				for cc in c_cells:
					if not (cc in result):
						result.append(cc)

	return result


func get_synergy_pairs_for_preview(
	item: Contracts.GridItemData,
	gx: int,
	gy: int,
	is_rotated: bool
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if item == null:
		return result
	var preview_cells: Array[Vector2i] = get_item_cells(item, gx, gy, is_rotated)

	if _is_synergy_source(item):
		for other in placed_items:
			if other == item or other.category != Contracts.ItemCategory.CANNON:
				continue
			var side: Dictionary = _is_cannon_mounted_side(other)
			if not bool(side["port"]) and not bool(side["starboard"]):
				continue
			var o_cells: Array[Vector2i] = side["cells"]
			if _cells_adjacent(preview_cells, o_cells):
				for oc in o_cells:
					if not (oc in result):
						result.append(oc)
	elif item.category == Contracts.ItemCategory.CANNON:
		var touches_port: bool = false
		var touches_starboard: bool = false
		for pc in preview_cells:
			var st: int = get_slot_type(pc.x, pc.y)
			if st == Contracts.SlotType.DECK_PORT:
				touches_port = true
			elif st == Contracts.SlotType.DECK_STARBOARD:
				touches_starboard = true
		if touches_port or touches_starboard:
			for other in placed_items:
				if other == item or not _is_synergy_source(other):
					continue
				var o_cells: Array[Vector2i] = get_item_cells(other, other.grid_pos.x, other.grid_pos.y, other.rotated)
				if _cells_adjacent(preview_cells, o_cells):
					for oc in o_cells:
						if not (oc in result):
							result.append(oc)

	return result


func compile_stats() -> Contracts.ShipStats:
	var stats := Contracts.ShipStats.new()
	stats.hull_tier = hull_tier

	var base_armor: float = 0.0
	var base_turn: float = 1.75
	match hull_tier:
		Contracts.ShipClass.BRIGANTINE:
			stats.base_max_hp = 190.0
			stats.base_max_speed = 101.0
			stats.max_safe_weight = 70.0
			stats.acceleration = 45.0
			stats.rudder_inertia = 5.6
			base_turn = 1.65
		Contracts.ShipClass.FRIGATE:
			stats.base_max_hp = 280.0
			stats.base_max_speed = 98.0
			stats.max_safe_weight = 105.0
			stats.acceleration = 42.0
			stats.rudder_inertia = 4.6
			base_armor = 4.0
			base_turn = 1.45
		_:
			stats.base_max_hp = 120.0
			stats.base_max_speed = 95.0
			stats.max_safe_weight = 45.0
			stats.acceleration = 48.0
			stats.rudder_inertia = 6.5
			base_turn = 1.75

	var synergy_sources: Array[Dictionary] = []
	var total_weight: float = 0.0
	var hp_bonus: float = 0.0
	var armor_bonus: float = 0.0
	var speed_bonus: float = 0.0
	var turn_bonus: float = 0.0
	var cursed_hazard: float = 0.0

	for item in placed_items:
		total_weight += item.weight
		var mult: float = item.get_affix_stat_multiplier()

		if item.category == Contracts.ItemCategory.POWDER_BARREL:
			stats.powder_barrel_count += 1
			stats.explosion_hazard_damage += item.explosion_hazard
		elif item.category == Contracts.ItemCategory.SAIL:
			stats.sail_upgrade_count += 1

		if _is_synergy_source(item):
			synergy_sources.append({
				"item": item,
				"cells": get_item_cells(item, item.grid_pos.x, item.grid_pos.y, item.rotated)
			})

		hp_bonus += item.max_hp_bonus * mult
		armor_bonus += item.armor_bonus * mult
		speed_bonus += item.speed_bonus * mult
		turn_bonus += item.turn_bonus * mult
		stats.passive_repair_rate += item.passive_repair_rate * mult
		stats.ram_damage_bonus += item.ram_damage_bonus * mult
		stats.vision_bonus += item.vision_bonus * mult

		if item.affix == Contracts.ItemAffix.CURSED:
			cursed_hazard += 6.0

	stats.explosion_hazard_damage += cursed_hazard
	stats.total_weight = total_weight
	if total_weight > stats.max_safe_weight:
		var excess: float = total_weight - stats.max_safe_weight
		stats.cargo_weight_penalty = clampf(excess / 55.0, 0.0, 0.45)
	else:
		stats.cargo_weight_penalty = 0.0

	var weight_mult: float = 1.0 - stats.cargo_weight_penalty
	stats.max_hp = maxf(40.0, stats.base_max_hp + hp_bonus)
	stats.armor = maxf(0.0, base_armor + armor_bonus)
	stats.max_speed = maxf(35.0, (stats.base_max_speed + speed_bonus) * weight_mult)
	stats.turn_speed = maxf(0.85, (base_turn + turn_bonus) * lerpf(1.0, weight_mult, 0.7))

	var port_syn_sum: float = 0.0
	var starboard_syn_sum: float = 0.0
	var active_burn_bonus: float = 0.0

	for item in placed_items:
		var eff_size: Vector2i = item.get_effective_size()
		var item_cells: Array[Vector2i] = get_item_cells(item, item.grid_pos.x, item.grid_pos.y, item.rotated)
		var primary_slot: int = get_slot_type(item.grid_pos.x, item.grid_pos.y)

		if item.category == Contracts.ItemCategory.CANNON:
			var side: Dictionary = _is_cannon_mounted_side(item)
			var is_port: bool = bool(side["port"])
			var is_starboard: bool = bool(side["starboard"])
			if is_port:
				primary_slot = Contracts.SlotType.DECK_PORT
			elif is_starboard:
				primary_slot = Contracts.SlotType.DECK_STARBOARD

			if is_port or is_starboard:
				var synergy_mult: float = 1.0
				var mult_item: float = item.get_affix_stat_multiplier()
				var total_burn_dps: float = item.burn_dps * mult_item
				for s_info in synergy_sources:
					var src: Contracts.GridItemData = s_info["item"]
					var s_cells: Array[Vector2i] = s_info["cells"]
					if _cells_adjacent(s_cells, item_cells):
						var src_mult: float = src.get_affix_stat_multiplier()
						synergy_mult += src.reload_synergy_bonus * src_mult
						if src.burn_dps > 0.0:
							var added_burn: float = src.burn_dps * src_mult
							total_burn_dps += added_burn
							active_burn_bonus = maxf(active_burn_bonus, added_burn)

				var eff_damage: float = item.get_effective_damage()
				var eff_reload: float = item.get_effective_reload_time(synergy_mult)
				var deck_offset_x: float = ((float(item.grid_pos.x) + float(eff_size.x) * 0.5) / float(GRID_WIDTH) - 0.5) * 34.0
				var cannon_data := {
					"instance_id": item.instance_id,
					"id": item.id,
					"name": item.get_display_name(),
					"damage": eff_damage,
					"reload_time": eff_reload,
					"range": item.cannon_range,
					"projectile_speed": item.projectile_speed,
					"chain_shot_slow": item.chain_shot_slow,
					"spread_angle_deg": item.spread_angle_deg,
					"burn_dps": total_burn_dps,
					"harpoon_pull": item.harpoon_pull * mult_item,
					"synergy_mult": synergy_mult,
					"grid_x": item.grid_pos.x,
					"grid_y": item.grid_pos.y,
					"deck_offset_x": deck_offset_x
				}

				if is_port:
					stats.port_cannons.append(cannon_data.duplicate())
					stats.port_salvo_damage += eff_damage
					port_syn_sum += synergy_mult
				if is_starboard:
					stats.starboard_cannons.append(cannon_data.duplicate())
					stats.starboard_salvo_damage += eff_damage
					starboard_syn_sum += synergy_mult

		var center_cell := Vector2(item.grid_pos) + Vector2(eff_size) * 0.5
		stats.visual_equipped_items.append({
			"instance_id": item.instance_id,
			"id": item.id,
			"category": item.category,
			"rarity": item.rarity,
			"affix": item.affix,
			"slot_type": primary_slot,
			"grid_x": item.grid_pos.x,
			"grid_y": item.grid_pos.y,
			"width": eff_size.x,
			"height": eff_size.y,
			"norm_x": center_cell.x / float(GRID_WIDTH),
			"norm_y": center_cell.y / float(GRID_HEIGHT),
			"primary_color": item.primary_color,
			"accent_color": item.accent_color
		})

	stats.burn_bonus_dps = active_burn_bonus
	if not stats.port_cannons.is_empty():
		stats.port_reload_multiplier = port_syn_sum / float(stats.port_cannons.size())
	if not stats.starboard_cannons.is_empty():
		stats.starboard_reload_multiplier = starboard_syn_sum / float(stats.starboard_cannons.size())

	current_stats = stats
	Contracts.bus().ship_stats_compiled.emit(ship_id, stats)
	Contracts.bus().ship_grid_updated.emit(ship_id, stats.visual_equipped_items)
	return stats


func to_dict() -> Dictionary:
	var placed_arr: Array = []
	for item in placed_items:
		placed_arr.append(item.to_dict())
	var stash_arr: Array = []
	for item in stash_items:
		stash_arr.append(item.to_dict())
	return {
		"ship_id": ship_id,
		"hull_tier": hull_tier,
		"placed_items": placed_arr,
		"stash_items": stash_arr
	}


func from_dict(d: Dictionary) -> void:
	ship_id = int(d.get("ship_id", ship_id))
	hull_tier = clampi(int(d.get("hull_tier", hull_tier)), Contracts.ShipClass.SLOOP, Contracts.ShipClass.FRIGATE)
	placed_items.clear()
	stash_items.clear()

	var raw_placed: Array = d.get("placed_items", [])
	for raw in raw_placed:
		if raw is Dictionary:
			placed_items.append(Contracts.GridItemData.from_dict(raw))

	var raw_stash: Array = d.get("stash_items", [])
	for raw in raw_stash:
		if raw is Dictionary:
			stash_items.append(Contracts.GridItemData.from_dict(raw))

	compile_stats()

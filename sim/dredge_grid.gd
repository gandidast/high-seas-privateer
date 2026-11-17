class_name DredgeGrid
extends Node
## Dredge-inspired dynamic Tetris ship inventory & stat compiler.
## Handles 9 ship classes (6x4 Sloop up to 12x7 Man-o'-War), slot-type constraints
## (including BOW_WEAPON slots), adjacency synergies (powder barrels, alchemist powder,
## gunner quarters), crew/hull/sail upgrades, and weight penalties.

const GRID_WIDTH: int = 8
const GRID_HEIGHT: int = 6

var ship_id: int = 1
var hull_tier: int = Contracts.ShipClass.SLOOP
var placed_items: Array[Contracts.GridItemData] = []
var stash_items: Array[Contracts.GridItemData] = []
var current_stats: Contracts.ShipStats = Contracts.ShipStats.new()


func get_grid_width() -> int:
	var spec: Dictionary = Contracts.get_ship_class_spec(hull_tier)
	return int(spec.get("grid_cols", GRID_WIDTH))


func get_grid_height() -> int:
	var spec: Dictionary = Contracts.get_ship_class_spec(hull_tier)
	return int(spec.get("grid_rows", GRID_HEIGHT))


func set_hull_tier(new_tier: int) -> void:
	hull_tier = clampi(new_tier, Contracts.ShipClass.SLOOP, Contracts.ShipClass.MAN_O_WAR)
	_evict_incompatible_items_to_stash()
	compile_stats()


func _evict_incompatible_items_to_stash() -> void:
	var w: int = get_grid_width()
	var h: int = get_grid_height()
	var kept: Array[Contracts.GridItemData] = []
	for item in placed_items:
		if item == null:
			continue
		var cells: Array[Vector2i] = get_item_cells(item, item.grid_pos.x, item.grid_pos.y, item.rot_steps)
		var valid: bool = not cells.is_empty()
		if valid:
			for c in cells:
				if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h or not _is_slot_compatible(item, get_slot_type(c.x, c.y)):
					valid = false
					break
		if valid:
			kept.append(item)
		else:
			item.grid_pos = Vector2i(-1, -1)
			item.rotated = false
			item.rot_steps = 0
			if not (item in stash_items):
				stash_items.append(item)
	placed_items = kept


func get_slot_type(gx: int, gy: int) -> int:
	var w: int = get_grid_width()
	var h: int = get_grid_height()
	if gx < 0 or gx >= w or gy < 0 or gy >= h:
		return Contracts.SlotType.NONE
	if gy == 0:
		return Contracts.SlotType.DECK_PORT
	if gy == h - 1:
		return Contracts.SlotType.DECK_STARBOARD
	if hull_tier == Contracts.ShipClass.CORSAIR_XEBEC:
		if gx == w - 1 and gy >= 1 and gy <= h - 2:
			return Contracts.SlotType.BOW
		if gx == w - 2 and (gy == 1 or gy == h - 2):
			return Contracts.SlotType.BOW
	elif gx == w - 1 and gy >= 1 and gy <= h - 2 and gy >= (h - 1) / 2 and gy <= h / 2:
		return Contracts.SlotType.BOW
	var is_clipper: bool = (hull_tier == Contracts.ShipClass.CORSAIR_CLIPPER)
	var mast_w: int = 4 if is_clipper else clampi(w - 4, 2, 4)
	var mast_x0: int = 1 if is_clipper else maxi(1, (w - mast_w) / 2)
	var mast_x1: int = mini((w - 2) if is_clipper else (w - 3), mast_x0 + mast_w - 1)
	var mast_y0: int = maxi(1, (h - 2) / 2)
	var mast_y1: int = mini(h - 2, mast_y0 + 1)
	if gx >= mast_x0 and gx <= mast_x1 and gy >= mast_y0 and gy <= mast_y1:
		return Contracts.SlotType.MAST
	return Contracts.SlotType.CARGO_HOLD


static func _resolve_rot_steps(rot_arg: Variant) -> int:
	if rot_arg is int:
		return posmod(int(rot_arg), 4)
	return 1 if bool(rot_arg) else 0


func get_item_cells(item: Contracts.GridItemData, gx: int, gy: int, rot_arg: Variant = 0) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if item == null:
		return cells
	var steps: int = _resolve_rot_steps(rot_arg)
	for local_cell in item.get_rotated_local_cells(steps):
		cells.append(Vector2i(gx + local_cell.x, gy + local_cell.y))
	return cells


func get_item_at(gx: int, gy: int) -> Contracts.GridItemData:
	if gx < 0 or gx >= get_grid_width() or gy < 0 or gy >= get_grid_height():
		return null
	for item in placed_items:
		var cells: Array[Vector2i] = get_item_cells(item, item.grid_pos.x, item.grid_pos.y, item.rot_steps)
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


func can_place_item(item: Contracts.GridItemData, gx: int, gy: int, rot_arg: Variant = 0) -> bool:
	if item == null:
		return false
	var gw: int = get_grid_width()
	var gh: int = get_grid_height()
	var candidate_cells: Array[Vector2i] = get_item_cells(item, gx, gy, rot_arg)
	if candidate_cells.is_empty():
		return false
	for c in candidate_cells:
		if c.x < 0 or c.y < 0 or c.x >= gw or c.y >= gh:
			return false
		var slot: int = get_slot_type(c.x, c.y)
		if not _is_slot_compatible(item, slot):
			return false
		var occupant: Contracts.GridItemData = get_item_at(c.x, c.y)
		if occupant != null and occupant != item and occupant.instance_id != item.instance_id:
			return false

	return true


func place_item(item: Contracts.GridItemData, gx: int, gy: int, rot_arg: Variant = 0) -> bool:
	if not can_place_item(item, gx, gy, rot_arg):
		return false

	var steps: int = _resolve_rot_steps(rot_arg)
	remove_from_stash(item)
	if not (item in placed_items):
		placed_items.append(item)

	item.grid_pos = Vector2i(gx, gy)
	item.rot_steps = steps
	item.rotated = (steps % 2 == 1)
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
	var has_poly: bool = not item.shape_offsets.is_empty()
	var max_steps: int = 4 if has_poly else (2 if item.width != item.height else 1)
	if max_steps <= 1:
		return false
	for delta in range(1, max_steps):
		var next_step: int = (item.rot_steps + delta) % max_steps
		if can_place_item(item, item.grid_pos.x, item.grid_pos.y, next_step):
			item.rot_steps = next_step
			item.rotated = (next_step % 2 == 1)
			compile_stats()
			return true
	return false


func auto_place_item(item: Contracts.GridItemData) -> bool:
	if item == null:
		return false
	var gw: int = get_grid_width()
	var gh: int = get_grid_height()
	var has_poly: bool = not item.shape_offsets.is_empty()
	var max_steps: int = 4 if has_poly else (2 if item.width != item.height else 1)
	for gy in range(gh):
		for gx in range(gw):
			for step in range(max_steps):
				if can_place_item(item, gx, gy, step):
					return place_item(item, gx, gy, step)
	return false


func populate_starter_loadout() -> void:
	placed_items.clear()
	stash_items.clear()

	var gw: int = get_grid_width()
	var gh: int = get_grid_height()
	var mast_x: int = maxi(1, (gw - clampi(gw - 4, 2, 4)) / 2)
	var mast_y: int = maxi(1, (gh - 2) / 2)

	var port_gun := ItemDatabase.create_item("swivel_gun_1x2", Contracts.ItemAffix.STANDARD)
	var starboard_gun := ItemDatabase.create_item("swivel_gun_1x2", Contracts.ItemAffix.STANDARD)
	var powder := ItemDatabase.create_item("powder_barrel_1x1", Contracts.ItemAffix.STANDARD)
	var sail := ItemDatabase.create_item("silk_top_sail_1x2", Contracts.ItemAffix.STANDARD)
	var rum := ItemDatabase.create_item("rum_casks_1x1", Contracts.ItemAffix.STANDARD)

	# Place directly before a single compile_stats() call
	port_gun.grid_pos = Vector2i(1, 0)
	port_gun.rotated = true
	port_gun.rot_steps = 1
	placed_items.append(port_gun)

	starboard_gun.grid_pos = Vector2i(1, gh - 1)
	starboard_gun.rotated = true
	starboard_gun.rot_steps = 1
	placed_items.append(starboard_gun)

	powder.grid_pos = Vector2i(3, 0)
	powder.rotated = false
	powder.rot_steps = 0
	placed_items.append(powder)

	sail.grid_pos = Vector2i(mast_x, mast_y)
	sail.rotated = false
	sail.rot_steps = 0
	placed_items.append(sail)

	rum.grid_pos = Vector2i(0, 1)
	rum.rotated = false
	rum.rot_steps = 0
	placed_items.append(rum)

	compile_stats()


func _cells_adjacent(cells_a: Array[Vector2i], cells_b: Array[Vector2i]) -> bool:
	for a in cells_a:
		for b in cells_b:
			if absi(a.x - b.x) + absi(a.y - b.y) == 1:
				return true
	return false


func _is_cannon_mounted_side(cannon: Contracts.GridItemData) -> Dictionary:
	var cells: Array[Vector2i] = get_item_cells(cannon, cannon.grid_pos.x, cannon.grid_pos.y, cannon.rot_steps)
	var port: bool = false
	var starboard: bool = false
	for c in cells:
		var slot: int = get_slot_type(c.x, c.y)
		if slot == Contracts.SlotType.DECK_PORT:
			port = true
		elif slot == Contracts.SlotType.DECK_STARBOARD:
			starboard = true
	return {"port": port, "starboard": starboard, "cells": cells}


func _is_bow_mounted(weapon: Contracts.GridItemData) -> bool:
	if weapon == null or weapon.category != Contracts.ItemCategory.BOW_WEAPON:
		return false
	var cells: Array[Vector2i] = get_item_cells(weapon, weapon.grid_pos.x, weapon.grid_pos.y, weapon.rot_steps)
	for c in cells:
		if get_slot_type(c.x, c.y) == Contracts.SlotType.BOW:
			return true
	return false


func _is_synergy_source(item: Contracts.GridItemData) -> bool:
	if item == null:
		return false
	var is_weapon: bool = item.category == Contracts.ItemCategory.CANNON or item.category == Contracts.ItemCategory.BOW_WEAPON
	return item.reload_synergy_bonus > 0.0 or item.get_cursed_bonus_synergy() > 0.0 or (item.burn_dps > 0.0 and not is_weapon)


func _is_mounted_weapon(item: Contracts.GridItemData) -> bool:
	if item == null:
		return false
	if item.category == Contracts.ItemCategory.CANNON:
		var side: Dictionary = _is_cannon_mounted_side(item)
		return bool(side["port"]) or bool(side["starboard"])
	if item.category == Contracts.ItemCategory.BOW_WEAPON:
		return _is_bow_mounted(item)
	return false


func get_adjacent_synergy_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var sources: Array[Contracts.GridItemData] = []
	var mounted_cannons: Array[Contracts.GridItemData] = []

	for item in placed_items:
		if _is_synergy_source(item):
			sources.append(item)
		elif _is_mounted_weapon(item):
			mounted_cannons.append(item)

	for src in sources:
		var s_cells: Array[Vector2i] = get_item_cells(src, src.grid_pos.x, src.grid_pos.y, src.rot_steps)
		for cannon in mounted_cannons:
			var c_cells: Array[Vector2i] = get_item_cells(cannon, cannon.grid_pos.x, cannon.grid_pos.y, cannon.rot_steps)
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
	rot_arg: Variant = 0
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if item == null:
		return result
	var preview_cells: Array[Vector2i] = get_item_cells(item, gx, gy, rot_arg)

	if _is_synergy_source(item):
		for other in placed_items:
			if other == item or not _is_mounted_weapon(other):
				continue
			var o_cells: Array[Vector2i] = get_item_cells(other, other.grid_pos.x, other.grid_pos.y, other.rot_steps)
			if _cells_adjacent(preview_cells, o_cells):
				for oc in o_cells:
					if not (oc in result):
						result.append(oc)
	elif item.category == Contracts.ItemCategory.CANNON or item.category == Contracts.ItemCategory.BOW_WEAPON:
		var is_mounted_preview: bool = false
		for pc in preview_cells:
			var st: int = get_slot_type(pc.x, pc.y)
			if item.category == Contracts.ItemCategory.CANNON and (st == Contracts.SlotType.DECK_PORT or st == Contracts.SlotType.DECK_STARBOARD):
				is_mounted_preview = true
				break
			if item.category == Contracts.ItemCategory.BOW_WEAPON and st == Contracts.SlotType.BOW:
				is_mounted_preview = true
				break
		if is_mounted_preview:
			for other in placed_items:
				if other == item or not _is_synergy_source(other):
					continue
				var o_cells: Array[Vector2i] = get_item_cells(other, other.grid_pos.x, other.grid_pos.y, other.rot_steps)
				if _cells_adjacent(preview_cells, o_cells):
					for oc in o_cells:
						if not (oc in result):
							result.append(oc)

	return result


func _compile_weapon_entry(
	item: Contracts.GridItemData,
	item_cells: Array[Vector2i],
	eff_size: Vector2i,
	grid_w: int,
	synergy_sources: Array[Dictionary],
	class_reload_bonus: float
) -> Dictionary:
	var synergy_mult: float = class_reload_bonus
	var total_burn_dps: float = item.get_effective_burn_dps()
	var max_added_burn: float = 0.0
	for s_info in synergy_sources:
		var src: Contracts.GridItemData = s_info["item"]
		var s_cells: Array[Vector2i] = s_info["cells"]
		if _cells_adjacent(s_cells, item_cells):
			var src_mult: float = src.get_affix_stat_multiplier()
			synergy_mult += src.reload_synergy_bonus * src_mult + src.get_cursed_bonus_synergy()
			if src.burn_dps > 0.0:
				var added_burn: float = src.burn_dps * src_mult
				total_burn_dps += added_burn
				max_added_burn = maxf(max_added_burn, added_burn)

	var eff_damage: float = item.get_effective_damage()
	var eff_reload: float = item.get_effective_reload_time(synergy_mult)
	var deck_offset_x: float = ((float(item.grid_pos.x) + float(eff_size.x) * 0.5) / float(maxi(1, grid_w)) - 0.5) * 34.0
	var pellets: int = maxi(1, item.pellet_count)
	var cannon_data := {
		"instance_id": item.instance_id,
		"id": item.id,
		"name": item.get_display_name(),
		"damage": eff_damage,
		"pellet_count": pellets,
		"reload_time": eff_reload,
		"range": item.get_effective_range(),
		"projectile_speed": item.projectile_speed,
		"chain_shot_slow": item.chain_shot_slow,
		"spread_angle_deg": item.spread_angle_deg,
		"burn_dps": total_burn_dps,
		"harpoon_pull": item.harpoon_pull * item.get_affix_stat_multiplier(),
		"synergy_mult": synergy_mult,
		"grid_x": item.grid_pos.x,
		"grid_y": item.grid_pos.y,
		"deck_offset_x": deck_offset_x
	}
	return {
		"cannon": cannon_data,
		"salvo_damage": eff_damage * float(pellets),
		"synergy_mult": synergy_mult,
		"added_burn": max_added_burn
	}


func compile_stats() -> Contracts.ShipStats:
	var stats := Contracts.ShipStats.new()
	stats.hull_tier = hull_tier

	var spec: Dictionary = Contracts.get_ship_class_spec(hull_tier)
	var grid_w: int = int(spec.get("grid_cols", GRID_WIDTH))
	var grid_h: int = int(spec.get("grid_rows", GRID_HEIGHT))
	stats.base_max_hp = float(spec.get("base_hp", 120.0))
	stats.base_max_speed = float(spec.get("base_speed", 95.0))
	stats.max_safe_weight = float(spec.get("max_weight", 45.0))
	stats.acceleration = float(spec.get("accel", 48.0))
	stats.rudder_inertia = float(spec.get("inertia", 6.5))
	var base_armor: float = float(spec.get("armor", 0.0))
	var base_turn: float = float(spec.get("turn_speed", 1.75))
	var class_reload_bonus: float = maxf(0.25, float(spec.get("reload_bonus", 1.0)))
	var innate_ram: float = float(spec.get("ram_bonus", 0.0))
	stats.innate_ram_bonus = innate_ram
	stats.ram_damage_bonus = innate_ram

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
				"cells": get_item_cells(item, item.grid_pos.x, item.grid_pos.y, item.rot_steps)
			})

		hp_bonus += item.max_hp_bonus * mult + item.get_cursed_bonus_hp()
		armor_bonus += item.armor_bonus * mult
		speed_bonus += item.speed_bonus * mult + item.get_cursed_bonus_speed()
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
	var bow_syn_sum: float = 0.0
	var active_burn_bonus: float = 0.0

	for item in placed_items:
		var eff_size: Vector2i = item.get_effective_size()
		var item_cells: Array[Vector2i] = get_item_cells(item, item.grid_pos.x, item.grid_pos.y, item.rot_steps)
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
				var compiled: Dictionary = _compile_weapon_entry(item, item_cells, eff_size, grid_w, synergy_sources, class_reload_bonus)
				var cannon_data: Dictionary = compiled["cannon"]
				var salvo_dmg: float = float(compiled["salvo_damage"])
				var synergy_mult: float = float(compiled["synergy_mult"])
				active_burn_bonus = maxf(active_burn_bonus, float(compiled["added_burn"]))

				if is_port:
					stats.port_cannons.append(cannon_data.duplicate())
					stats.port_salvo_damage += salvo_dmg
					port_syn_sum += synergy_mult
				if is_starboard:
					stats.starboard_cannons.append(cannon_data.duplicate())
					stats.starboard_salvo_damage += salvo_dmg
					starboard_syn_sum += synergy_mult
		elif item.category == Contracts.ItemCategory.BOW_WEAPON:
			if _is_bow_mounted(item):
				primary_slot = Contracts.SlotType.BOW
				var compiled_bow: Dictionary = _compile_weapon_entry(item, item_cells, eff_size, grid_w, synergy_sources, class_reload_bonus)
				var bow_data: Dictionary = compiled_bow["cannon"]
				var bow_salvo: float = float(compiled_bow["salvo_damage"])
				var bow_syn: float = float(compiled_bow["synergy_mult"])
				active_burn_bonus = maxf(active_burn_bonus, float(compiled_bow["added_burn"]))

				stats.bow_cannons.append(bow_data)
				stats.bow_salvo_damage += bow_salvo
				bow_syn_sum += bow_syn

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
			"rot_steps": item.rot_steps,
			"norm_x": center_cell.x / float(maxi(1, grid_w)),
			"norm_y": center_cell.y / float(maxi(1, grid_h)),
			"primary_color": item.primary_color,
			"accent_color": item.accent_color
		})

	stats.burn_bonus_dps = active_burn_bonus
	if not stats.port_cannons.is_empty():
		stats.port_reload_multiplier = port_syn_sum / float(stats.port_cannons.size())
	if not stats.starboard_cannons.is_empty():
		stats.starboard_reload_multiplier = starboard_syn_sum / float(stats.starboard_cannons.size())
	if not stats.bow_cannons.is_empty():
		stats.bow_reload_multiplier = bow_syn_sum / float(stats.bow_cannons.size())
	elif class_reload_bonus != 1.0:
		stats.bow_reload_multiplier = class_reload_bonus

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
	hull_tier = clampi(int(d.get("hull_tier", hull_tier)), Contracts.ShipClass.SLOOP, Contracts.ShipClass.MAN_O_WAR)
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

	_evict_incompatible_items_to_stash()
	compile_stats()

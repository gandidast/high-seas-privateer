class_name CargoSlotRenderer
extends RefCounted
## Modular renderer for CargoGridUI: draws the top-down ship blueprint & 8x6
## Dredge grid, Beute-Lager stash cards, Schiffswerte stats bars, dragging ghost,
## and item tooltips using UIThemeHelper and cached NEAREST pixel-art icons.

const PANEL_SIZE: Vector2 = Vector2(1040.0, 580.0)
const CELL_SIZE: float = 48.0
const GRID_OFFSET: Vector2 = Vector2(54.0, 102.0)
const STASH_RECT_REL: Rect2 = Rect2(512.0, 56.0, 260.0, 488.0)
const STATS_RECT_REL: Rect2 = Rect2(784.0, 56.0, 242.0, 508.0)
const CLOSE_BTN_REL: Rect2 = Rect2(996.0, 10.0, 32.0, 32.0)
const STASH_ROW_HEIGHT: float = 60.0
const STASH_HEADER_HEIGHT: float = 34.0

const COL_VALID: Color = Color(0.22, 0.82, 0.45, 0.30)
const COL_INVALID: Color = Color(0.90, 0.25, 0.28, 0.34)

var _icon_cache: Dictionary = {} # "id_cat_wxh_rar_aff" -> ImageTexture
var _hull_poly: PackedVector2Array = PackedVector2Array([
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO
])
var _hull_closed: PackedVector2Array = PackedVector2Array([
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO
])


func get_item_icon_texture(item: Contracts.GridItemData) -> ImageTexture:
	if item == null:
		return null
	var key: String = "%s_%d_%dx%d_%d_%d" % [item.id, item.category, item.width, item.height, item.rarity, item.affix]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var tex: ImageTexture = ProceduralShipBaker.bake_item_grid_icon(
		item.id, item.category, item.width, item.height, item.rarity, item.affix
	)
	_icon_cache[key] = tex
	return tex


func draw_item_sprite(canvas: CanvasItem, rect: Rect2, item: Contracts.GridItemData, is_rotated: bool, modulate_col: Color = Color.WHITE) -> void:
	var tex: ImageTexture = get_item_icon_texture(item)
	if tex == null:
		return
	var inner_size := Vector2(maxf(16.0, rect.size.x - 8.0), maxf(16.0, rect.size.y - 8.0))
	var center: Vector2 = rect.get_center().round()
	if is_rotated:
		var unrot_size := Vector2(inner_size.y, inner_size.x)
		canvas.draw_set_transform(center, PI * 0.5, Vector2.ONE)
		canvas.draw_texture_rect(tex, Rect2(-unrot_size * 0.5, unrot_size), false, modulate_col)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		canvas.draw_texture_rect(tex, Rect2((center - inner_size * 0.5).round(), inner_size.round()), false, modulate_col)


func draw_stash_item_sprite(canvas: CanvasItem, box_rect: Rect2, item: Contracts.GridItemData) -> void:
	var tex: ImageTexture = get_item_icon_texture(item)
	if tex == null:
		return
	var tw: float = float(tex.get_width())
	var th: float = float(tex.get_height())
	var pad_box: Vector2 = box_rect.size - Vector2(6.0, 6.0)
	var scale_f: float = minf(pad_box.x / maxf(1.0, tw), pad_box.y / maxf(1.0, th))
	var draw_size := Vector2(tw * scale_f, th * scale_f).round()
	var center: Vector2 = box_rect.get_center().round()
	canvas.draw_texture_rect(tex, Rect2((center - draw_size * 0.5).round(), draw_size), false)


func draw_ship_blueprint_and_grid(
	canvas: CanvasItem,
	panel_pos: Vector2,
	font: Font,
	dredge_grid: DredgeGrid,
	ship_physics: ShipPhysics,
	hovered_item: Contracts.GridItemData,
	pulse_time: float
) -> void:
	var grid_origin: Vector2 = (panel_pos + GRID_OFFSET).round()
	var grid_px_size := Vector2(float(DredgeGrid.GRID_WIDTH) * CELL_SIZE, float(DredgeGrid.GRID_HEIGHT) * CELL_SIZE)
	var cy: float = grid_origin.y + grid_px_size.y * 0.5

	var left_x: float = grid_origin.x - 36.0
	var gx0: float = grid_origin.x - 6.0
	var gx1: float = grid_origin.x + grid_px_size.x + 4.0
	var bow_tip_x: float = gx1 + 48.0
	var top_y: float = grid_origin.y - 16.0
	var bot_y: float = grid_origin.y + grid_px_size.y + 16.0

	_hull_poly[0] = Vector2(left_x + 6.0, top_y + 28.0)
	_hull_poly[1] = Vector2(left_x + 18.0, top_y + 8.0)
	_hull_poly[2] = Vector2(gx0 + 28.0, top_y)
	_hull_poly[3] = Vector2(gx1 - 16.0, top_y)
	_hull_poly[4] = Vector2(gx1 + 22.0, top_y + 38.0)
	_hull_poly[5] = Vector2(bow_tip_x, cy)
	_hull_poly[6] = Vector2(gx1 + 22.0, bot_y - 38.0)
	_hull_poly[7] = Vector2(gx1 - 16.0, bot_y)
	_hull_poly[8] = Vector2(gx0 + 28.0, bot_y)
	_hull_poly[9] = Vector2(left_x + 18.0, bot_y - 8.0)
	_hull_poly[10] = Vector2(left_x + 6.0, bot_y - 28.0)
	canvas.draw_colored_polygon(_hull_poly, Color(0.14, 0.11, 0.12, 0.94))

	for i in range(-4, 5):
		var py: float = cy + float(i) * 28.0
		var inset_x: float = absf(float(i)) * 7.0
		canvas.draw_line(
			Vector2(left_x + 18.0 + inset_x, py),
			Vector2(gx1 + 22.0 - inset_x * 1.4, py),
			Color(0.28, 0.22, 0.18, 0.35),
			1.5
		)

	for i in range(11):
		_hull_closed[i] = _hull_poly[i]
	_hull_closed[11] = _hull_poly[0]
	canvas.draw_polyline(_hull_closed, UIThemeHelper.COL_BRASS, 2.0, true)

	canvas.draw_line(Vector2(bow_tip_x - 10.0, cy), Vector2(bow_tip_x + 16.0, cy), UIThemeHelper.COL_BRASS, 3.0)
	canvas.draw_line(Vector2(bow_tip_x + 3.0, cy - 8.0), Vector2(bow_tip_x + 3.0, cy + 8.0), UIThemeHelper.COL_BRASS_DIM, 1.5)

	var helm_c := Vector2(grid_origin.x - 20.0, cy)
	canvas.draw_line(Vector2(grid_origin.x - 4.0, top_y + 12.0), Vector2(grid_origin.x - 4.0, bot_y - 12.0), UIThemeHelper.COL_BRASS_DIM, 1.5)
	canvas.draw_arc(helm_c, 10.0, 0.0, TAU, 20, UIThemeHelper.COL_BRASS_DIM, 1.5)
	canvas.draw_circle(helm_c, 3.5, UIThemeHelper.COL_BRASS)

	for gx in range(DredgeGrid.GRID_WIDTH):
		var port_x: float = grid_origin.x + (float(gx) + 0.5) * CELL_SIZE
		canvas.draw_rect(Rect2(port_x - 5.0, top_y - 2.0, 10.0, 5.0), Color(0.32, 0.56, 0.72, 0.90), true)
		canvas.draw_rect(Rect2(port_x - 5.0, bot_y - 3.0, 10.0, 5.0), Color(0.68, 0.36, 0.34, 0.90), true)

	UIThemeHelper.draw_sharp_text(canvas, font, Vector2(grid_origin.x, top_y - 6.0), "BACKBORD (Q)", 14, Color(0.54, 0.84, 0.96), HORIZONTAL_ALIGNMENT_CENTER, int(grid_px_size.x))
	UIThemeHelper.draw_sharp_text(canvas, font, Vector2(grid_origin.x, bot_y + 19.0), "STEUERBORD (E)", 14, Color(0.95, 0.58, 0.52), HORIZONTAL_ALIGNMENT_CENTER, int(grid_px_size.x))

	UIThemeHelper.draw_clean_box(canvas, Rect2(grid_origin - Vector2(3.0, 3.0), grid_px_size + Vector2(6.0, 6.0)), UIThemeHelper.COL_PANEL_INSET, UIThemeHelper.COL_BRASS_DIM)

	for gy in range(DredgeGrid.GRID_HEIGHT):
		for gx in range(DredgeGrid.GRID_WIDTH):
			var slot_type: int = dredge_grid.get_slot_type(gx, gy)
			var cell_rect := Rect2(grid_origin + Vector2(float(gx) * CELL_SIZE, float(gy) * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
			UIThemeHelper.draw_clean_box(canvas, cell_rect, UIThemeHelper.slot_fill_color(slot_type), UIThemeHelper.slot_border_color(slot_type))

	var mast_center := Vector2(grid_origin.x + 4.0 * CELL_SIZE, grid_origin.y + 3.0 * CELL_SIZE)
	canvas.draw_arc(mast_center, CELL_SIZE * 0.78, 0.0, TAU, 32, Color(0.85, 0.66, 0.29, 0.28), 1.5)
	canvas.draw_line(mast_center + Vector2(0.0, -CELL_SIZE * 0.92), mast_center + Vector2(0.0, CELL_SIZE * 0.92), Color(0.85, 0.66, 0.29, 0.24), 2.0)
	UIThemeHelper.draw_sharp_text(canvas, font, Vector2(grid_origin.x + 2.0 * CELL_SIZE, grid_origin.y + 3.0 * CELL_SIZE + 6.0), "MAST", 16, Color(0.92, 0.78, 0.42, 0.42), HORIZONTAL_ALIGNMENT_CENTER, int(4.0 * CELL_SIZE), 0)
	UIThemeHelper.draw_sharp_text(canvas, font, Vector2(grid_origin.x + 4.0, grid_origin.y + 4.0 * CELL_SIZE + 26.0), "FRACHTRAUM", 16, Color(0.82, 0.76, 0.66, 0.36), HORIZONTAL_ALIGNMENT_CENTER, int(grid_px_size.x - 8.0), 0)

	var synergy_cells: Array[Vector2i] = dredge_grid.get_adjacent_synergy_cells()
	for item in dredge_grid.placed_items:
		var eff_size: Vector2i = item.get_effective_size()
		var item_rect := Rect2(
			grid_origin + Vector2(float(item.grid_pos.x) * CELL_SIZE + 2.0, float(item.grid_pos.y) * CELL_SIZE + 2.0),
			Vector2(float(eff_size.x) * CELL_SIZE - 4.0, float(eff_size.y) * CELL_SIZE - 4.0)
		)
		var tile_bg: Color = Color(0.11, 0.11, 0.16, 0.94).lerp(item.primary_color, 0.10)
		var border: Color = UIThemeHelper.affix_color(item.affix, item.rarity)
		if hovered_item == item:
			border = UIThemeHelper.COL_GOLD
		UIThemeHelper.draw_clean_box(canvas, item_rect, tile_bg, border)
		canvas.draw_line(item_rect.position + Vector2(1.0, 1.0), Vector2(item_rect.end.x - 1.0, item_rect.position.y + 1.0), Color(1.0, 1.0, 1.0, 0.10), 1.5)
		draw_item_sprite(canvas, item_rect, item, item.rotated)
		if item.affix != Contracts.ItemAffix.STANDARD:
			var tag: String = "R" if item.affix == Contracts.ItemAffix.RUSTED else ("M" if item.affix == Contracts.ItemAffix.MASTERWORK else "V")
			UIThemeHelper.draw_sharp_text(canvas, font, item_rect.position + Vector2(5.0, 17.0), tag, 14, border)

	var pulse_alpha: float = 0.58 + 0.35 * sin(pulse_time * 5.0)
	var syn_border := Color(UIThemeHelper.COL_GOLD.r, UIThemeHelper.COL_GOLD.g, UIThemeHelper.COL_GOLD.b, pulse_alpha)
	for sc in synergy_cells:
		var s_rect := Rect2(grid_origin + Vector2(float(sc.x) * CELL_SIZE + 2.0, float(sc.y) * CELL_SIZE + 2.0), Vector2(CELL_SIZE - 4.0, CELL_SIZE - 4.0))
		canvas.draw_rect(s_rect, Color(1.0, 0.84, 0.22, 0.14), true)
		canvas.draw_rect(s_rect, syn_border, false, 2.0)

	var ly: float = bot_y + 36.0
	var lx: float = panel_pos.x + 20.0
	_draw_legend_chip(canvas, Vector2(lx, ly), Contracts.SlotType.DECK_PORT, "Backbord (Q)", font)
	_draw_legend_chip(canvas, Vector2(lx + 210.0, ly), Contracts.SlotType.DECK_STARBOARD, "Steuerbord (E)", font)
	_draw_legend_chip(canvas, Vector2(lx, ly + 24.0), Contracts.SlotType.MAST, "Mast (Segel)", font)
	_draw_legend_chip(canvas, Vector2(lx + 210.0, ly + 24.0), Contracts.SlotType.CARGO_HOLD, "Frachtraum", font)

	var tier: int = ship_physics.hull_tier if ship_physics != null else (dredge_grid.hull_tier if dredge_grid != null else 0)
	var class_title: String = "Brigg" if tier == Contracts.ShipClass.BRIGANTINE else ("Schwere Fregatte" if tier == Contracts.ShipClass.FRIGATE else "Schaluppe")
	UIThemeHelper.draw_sharp_text(canvas, font, Vector2(lx, ly + 62.0), "Schiffsklasse: %s" % class_title, 16, UIThemeHelper.COL_TURQUOISE)
	UIThemeHelper.draw_sharp_text(canvas, font, Vector2(lx, ly + 84.0), "Ziehen: Bewegen  •  [R] / Rechtsklick: Drehen", 14, UIThemeHelper.COL_IVORY)
	UIThemeHelper.draw_sharp_text(canvas, font, Vector2(lx, ly + 104.0), "Gold-Rahmen: Pulver / Quartier neben Kanone!", 14, UIThemeHelper.COL_GOLD)
	UIThemeHelper.draw_sharp_text(canvas, font, Vector2(lx, ly + 124.0), "[I / Tab / Esc] Inventar schließen", 14, UIThemeHelper.COL_MUTED)


func _draw_legend_chip(canvas: CanvasItem, pos: Vector2, slot_type: int, label: String, font: Font) -> void:
	UIThemeHelper.draw_clean_box(canvas, Rect2(pos.round(), Vector2(16.0, 16.0)), UIThemeHelper.slot_fill_color(slot_type), UIThemeHelper.slot_border_color(slot_type))
	UIThemeHelper.draw_sharp_text(canvas, font, pos + Vector2(22.0, 13.0), label, 14, UIThemeHelper.COL_IVORY)


func draw_stash_panel(
	canvas: CanvasItem,
	panel_pos: Vector2,
	font: Font,
	dredge_grid: DredgeGrid,
	stash_scroll: int,
	dragging_item: Contracts.GridItemData,
	hovered_item: Contracts.GridItemData
) -> void:
	var sr := Rect2((panel_pos + STASH_RECT_REL.position).round(), STASH_RECT_REL.size.round())
	UIThemeHelper.draw_framed_panel(canvas, sr, UIThemeHelper.COL_PANEL_INSET, UIThemeHelper.COL_BRASS_DIM, Color(0.22, 0.18, 0.14, 0.55))
	UIThemeHelper.draw_sharp_text(canvas, font, sr.position + Vector2(12.0, 24.0), "Gegenstände (%d)" % dredge_grid.stash_items.size(), 15, UIThemeHelper.COL_MUTED)

	var list_top: float = sr.position.y + STASH_HEADER_HEIGHT
	var max_visible: int = int(floor((sr.size.y - STASH_HEADER_HEIGHT - 4.0) / STASH_ROW_HEIGHT))
	if dredge_grid.stash_items.is_empty():
		UIThemeHelper.draw_sharp_text(canvas, font, Vector2(sr.position.x + 14.0, list_top + 32.0), "Leer. Ziehe Items hierher.", 14, UIThemeHelper.COL_MUTED)
	else:
		var drawn_row: int = 0
		for i in range(max_visible + 1):
			if drawn_row >= max_visible:
				break
			var idx: int = stash_scroll + i
			if idx >= dredge_grid.stash_items.size():
				break
			var item: Contracts.GridItemData = dredge_grid.stash_items[idx]
			if item == dragging_item:
				continue
			var row_rect := Rect2(sr.position.x + 8.0, list_top + float(drawn_row) * STASH_ROW_HEIGHT, sr.size.x - 16.0, STASH_ROW_HEIGHT - 5.0)
			var border: Color = UIThemeHelper.affix_color(item.affix, item.rarity)
			var is_hov: bool = (hovered_item == item)
			UIThemeHelper.draw_clean_box(canvas, row_rect, Color(0.17, 0.16, 0.23, 0.96) if is_hov else UIThemeHelper.COL_PANEL_CARD, UIThemeHelper.COL_GOLD if is_hov else border)

			var icon_box := Rect2(row_rect.position + Vector2(5.0, 4.0), Vector2(47.0, 47.0))
			UIThemeHelper.draw_clean_box(canvas, icon_box, UIThemeHelper.COL_PANEL_INSET, Color(border.r, border.g, border.b, 0.45))
			draw_stash_item_sprite(canvas, icon_box, item)

			var short_name: String = item.get_display_name()
			if short_name.length() > 21:
				short_name = short_name.substr(0, 20) + "."
			UIThemeHelper.draw_sharp_text(canvas, font, row_rect.position + Vector2(58.0, 22.0), short_name, 14, border)
			UIThemeHelper.draw_sharp_text(canvas, font, row_rect.position + Vector2(58.0, 43.0), "%dx%d • %d Gold" % [item.width, item.height, item.get_effective_gold_value()], 14, UIThemeHelper.COL_MUTED)
			drawn_row += 1

	UIThemeHelper.draw_sharp_text(canvas, font, Vector2(sr.position.x + 6.0, sr.position.y + sr.size.y + 22.0), "Mausrad: Stash scrollen", 14, UIThemeHelper.COL_MUTED)


func draw_stats_panel(canvas: CanvasItem, panel_pos: Vector2, font: Font, dredge_grid: DredgeGrid, ship_physics: ShipPhysics) -> void:
	var st_rect := Rect2((panel_pos + STATS_RECT_REL.position).round(), STATS_RECT_REL.size.round())
	UIThemeHelper.draw_framed_panel(canvas, st_rect, UIThemeHelper.COL_PANEL_INSET, UIThemeHelper.COL_BRASS_DIM, Color(0.22, 0.18, 0.14, 0.55))

	var stats: Contracts.ShipStats = dredge_grid.current_stats
	var cur_hp: float = ship_physics.hp if ship_physics != null else stats.max_hp
	var x: float = st_rect.position.x + 12.0
	var bar_w: float = st_rect.size.x - 24.0
	var y: float = st_rect.position.y + 24.0

	var hp_ratio: float = clampf(cur_hp / maxf(1.0, stats.max_hp), 0.0, 1.0)
	var hp_col: Color = Color(0.32, 0.82, 0.46) if hp_ratio > 0.35 else Color(0.92, 0.30, 0.28)
	_draw_stat_bar(canvas, Vector2(x, y), bar_w, "Rumpf-HP", "%d/%d" % [int(round(cur_hp)), int(round(stats.max_hp))], hp_ratio, hp_col, UIThemeHelper.COL_IVORY, font)
	y += 38.0

	_draw_stat_bar(canvas, Vector2(x, y), bar_w, "Geschwindigkeit", "%d kn" % int(round(stats.max_speed * 0.14)), clampf(stats.max_speed / 260.0, 0.0, 1.0), UIThemeHelper.COL_TURQUOISE, UIThemeHelper.COL_TURQUOISE, font)
	y += 38.0

	var weight_ratio: float = clampf(stats.total_weight / maxf(1.0, stats.max_safe_weight), 0.0, 1.0)
	var over_w: bool = stats.cargo_weight_penalty > 0.0
	var weight_col: Color = Color(0.94, 0.34, 0.30) if over_w else (UIThemeHelper.COL_GOLD if weight_ratio > 0.80 else Color(0.46, 0.86, 0.52))
	var weight_txt: String = "%.0f/%.0f" % [stats.total_weight, stats.max_safe_weight]
	if over_w:
		weight_txt += " (-%d%%)" % int(round(stats.cargo_weight_penalty * 100.0))
	_draw_stat_bar(canvas, Vector2(x, y), bar_w, "Traglast", weight_txt, weight_ratio, weight_col, weight_col, font)
	y += 40.0

	_draw_stat_line(canvas, Vector2(x, y), bar_w, "Panzerung:", "%.1f" % stats.armor, UIThemeHelper.COL_IVORY, font)
	y += 23.0
	_draw_stat_line(canvas, Vector2(x, y), bar_w, "Wendung:", "%.2f" % stats.turn_speed, UIThemeHelper.COL_IVORY, font)
	y += 16.0

	canvas.draw_line(Vector2(x, y), Vector2(x + bar_w, y), UIThemeHelper.COL_BRASS_DIM, 1.5)
	y += 22.0
	UIThemeHelper.draw_sharp_text(canvas, font, Vector2(x, y), "BREITSEITEN-FEUERKRAFT", 15, UIThemeHelper.COL_GOLD)
	y += 24.0

	var max_salvo_ref: float = maxf(60.0, maxf(stats.port_salvo_damage, stats.starboard_salvo_damage))
	_draw_stat_bar(canvas, Vector2(x, y), bar_w, "Backbord (%dx)" % stats.port_cannons.size(), "%d DMG" % int(round(stats.port_salvo_damage)), clampf(stats.port_salvo_damage / max_salvo_ref, 0.0, 1.0), Color(0.42, 0.76, 0.96), Color(0.62, 0.86, 1.0), font)
	y += 38.0
	_draw_stat_bar(canvas, Vector2(x, y), bar_w, "Steuerbord (%dx)" % stats.starboard_cannons.size(), "%d DMG" % int(round(stats.starboard_salvo_damage)), clampf(stats.starboard_salvo_damage / max_salvo_ref, 0.0, 1.0), Color(0.94, 0.48, 0.44), Color(0.98, 0.64, 0.58), font)
	y += 36.0

	canvas.draw_line(Vector2(x, y), Vector2(x + bar_w, y), UIThemeHelper.COL_BRASS_DIM, 1.5)
	y += 22.0
	UIThemeHelper.draw_sharp_text(canvas, font, Vector2(x, y), "SYNERGIEN", 15, UIThemeHelper.COL_GOLD)
	y += 24.0

	var syn_cells: int = dredge_grid.get_adjacent_synergy_cells().size()
	_draw_stat_line(canvas, Vector2(x, y), bar_w, "Lade-Boost:", "Aktiv!" if syn_cells > 0 else "Keine", UIThemeHelper.COL_GOLD if syn_cells > 0 else UIThemeHelper.COL_MUTED, font)
	y += 22.0
	_draw_stat_line(canvas, Vector2(x, y), bar_w, "Expl.-Risiko:", "+%.0f" % stats.explosion_hazard_damage, Color(0.96, 0.44, 0.32) if stats.explosion_hazard_damage > 0.0 else UIThemeHelper.COL_MUTED, font)
	y += 22.0
	if stats.passive_repair_rate > 0.0:
		_draw_stat_line(canvas, Vector2(x, y), bar_w, "Reparatur:", "+%.1f/s" % stats.passive_repair_rate, Color(0.50, 0.92, 0.58), font)
		y += 22.0
	if stats.ram_damage_bonus > 0.0:
		_draw_stat_line(canvas, Vector2(x, y), bar_w, "Ramm-Bonus:", "+%.0f" % stats.ram_damage_bonus, Color(0.86, 0.90, 0.98), font)
		y += 22.0
	if stats.vision_bonus > 0.0:
		_draw_stat_line(canvas, Vector2(x, y), bar_w, "Ausguck:", "+%.0fpx" % stats.vision_bonus, UIThemeHelper.COL_GOLD, font)


func _draw_stat_bar(canvas: CanvasItem, pos: Vector2, width: float, label: String, val_text: String, ratio: float, bar_color: Color, val_color: Color, font: Font) -> void:
	UIThemeHelper.draw_sharp_text(canvas, font, pos, label, 14, UIThemeHelper.COL_MUTED)
	UIThemeHelper.draw_sharp_text(canvas, font, pos, val_text, 14, val_color, HORIZONTAL_ALIGNMENT_RIGHT, int(width))
	UIThemeHelper.draw_progress_bar(canvas, Rect2(pos.x, pos.y + 7.0, width, 10.0), ratio, bar_color, Color(0.05, 0.05, 0.08, 0.95), Color(0.32, 0.28, 0.24, 0.85), 2.0)


func _draw_stat_line(canvas: CanvasItem, pos: Vector2, width: float, label: String, value: String, val_color: Color, font: Font) -> void:
	UIThemeHelper.draw_sharp_text(canvas, font, pos, label, 14, UIThemeHelper.COL_MUTED)
	UIThemeHelper.draw_sharp_text(canvas, font, pos, value, 14, val_color, HORIZONTAL_ALIGNMENT_RIGHT, int(width))


func draw_dragging_ghost(
	canvas: CanvasItem,
	mouse_pos: Vector2,
	panel_pos: Vector2,
	font: Font,
	dredge_grid: DredgeGrid,
	dragging_item: Contracts.GridItemData,
	drag_rot: bool,
	target_origin: Vector2i
) -> void:
	var grid_origin: Vector2 = (panel_pos + GRID_OFFSET).round()
	var grid_rect := Rect2(panel_pos + GRID_OFFSET, Vector2(float(DredgeGrid.GRID_WIDTH) * CELL_SIZE, float(DredgeGrid.GRID_HEIGHT) * CELL_SIZE))
	var eff_w: int = dragging_item.height if drag_rot else dragging_item.width
	var eff_h: int = dragging_item.width if drag_rot else dragging_item.height

	if grid_rect.has_point(mouse_pos):
		var is_valid: bool = dredge_grid.can_place_item(dragging_item, target_origin.x, target_origin.y, drag_rot)
		var preview_col: Color = COL_VALID if is_valid else COL_INVALID
		var preview_border: Color = Color(0.38, 0.94, 0.56) if is_valid else Color(0.96, 0.34, 0.34)
		for c in dredge_grid.get_item_cells(dragging_item, target_origin.x, target_origin.y, drag_rot):
			if c.x >= 0 and c.x < DredgeGrid.GRID_WIDTH and c.y >= 0 and c.y < DredgeGrid.GRID_HEIGHT:
				UIThemeHelper.draw_clean_box(canvas, Rect2(grid_origin + Vector2(float(c.x) * CELL_SIZE, float(c.y) * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE)), preview_col, preview_border)
		if is_valid:
			for sc in dredge_grid.get_synergy_pairs_for_preview(dragging_item, target_origin.x, target_origin.y, drag_rot):
				var sr := Rect2(grid_origin + Vector2(float(sc.x) * CELL_SIZE + 2.0, float(sc.y) * CELL_SIZE + 2.0), Vector2(CELL_SIZE - 4.0, CELL_SIZE - 4.0))
				canvas.draw_rect(sr, Color(1.0, 0.84, 0.22, 0.30), true)
				canvas.draw_rect(sr, UIThemeHelper.COL_GOLD, false, 2.0)

	var ghost_size := Vector2(float(eff_w) * CELL_SIZE * 1.12, float(eff_h) * CELL_SIZE * 1.12).round()
	var ghost_rect := Rect2((mouse_pos - ghost_size * 0.5).round(), ghost_size)
	canvas.draw_rect(Rect2(ghost_rect.position + Vector2(5.0, 6.0), ghost_rect.size), Color(0.02, 0.02, 0.05, 0.50), true)
	canvas.draw_rect(ghost_rect, Color(0.10, 0.09, 0.15, 0.90), true)
	draw_item_sprite(canvas, ghost_rect, dragging_item, drag_rot, Color.WHITE)
	canvas.draw_rect(ghost_rect, UIThemeHelper.COL_GOLD, false, 2.0)
	canvas.draw_rect(Rect2(ghost_rect.position - Vector2(1.0, 1.0), ghost_rect.size + Vector2(2.0, 2.0)), UIThemeHelper.COL_OUTLINE_SOLID, false, 1.0)

	var hint_rect := Rect2(ghost_rect.position.x, ghost_rect.end.y + 5.0, maxf(110.0, ghost_rect.size.x), 24.0)
	UIThemeHelper.draw_clean_box(canvas, hint_rect, Color(0.08, 0.07, 0.12, 0.92), UIThemeHelper.COL_BRASS_DIM)
	UIThemeHelper.draw_sharp_text(canvas, font, hint_rect.position + Vector2(0.0, 17.0), "[R] Drehen", 14, UIThemeHelper.COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER, int(hint_rect.size.x))


func _category_label(cat: int) -> String:
	match cat:
		Contracts.ItemCategory.CANNON: return "Kanone"
		Contracts.ItemCategory.POWDER_BARREL: return "Pulverfass"
		Contracts.ItemCategory.SAIL: return "Segel"
		Contracts.ItemCategory.HULL: return "Rumpf"
		Contracts.ItemCategory.CREW_MOD: return "Crew-Modul"
		Contracts.ItemCategory.TREASURE: return "Schatz"
		_: return "Handelsgut"


func draw_tooltip(canvas: CanvasItem, mouse_pos: Vector2, vp_size: Vector2, item: Contracts.GridItemData, font: Font) -> void:
	var lines: Array[String] = ["%s (%dx%d)" % [_category_label(item.category), item.width, item.height]]
	var mult: float = item.get_affix_stat_multiplier()
	if item.category == Contracts.ItemCategory.CANNON:
		lines.append("Schaden: %.0f | Reload: %.2fs" % [item.get_effective_damage(), item.get_effective_reload_time(1.0)])
		lines.append("Reichweite: %.0f px" % item.cannon_range)
		if item.chain_shot_slow > 0.0:
			lines.append("Bremst Ziel: -%d%% Tempo" % int(round(item.chain_shot_slow * 100.0)))
		if item.burn_dps > 0.0:
			lines.append("Brandschaden: %.1f DPS" % (item.burn_dps * mult))
		if item.harpoon_pull > 0.0:
			lines.append("Harpunen-Zug: %.0f Kraft" % (item.harpoon_pull * mult))
	if item.reload_synergy_bonus > 0.0:
		lines.append("Synergie: +%d%% Kanonen-Reload" % int(round(item.reload_synergy_bonus * 100.0)))
		if item.burn_dps > 0.0 and item.category != Contracts.ItemCategory.CANNON:
			lines.append("Verleiht Brandmunition (+%.1f DPS)" % (item.burn_dps * mult))
	if item.explosion_hazard > 0.0: lines.append("Risiko: +%.0f Trefferschaden" % item.explosion_hazard)
	if item.speed_bonus > 0.0: lines.append("Tempo: +%.1f kn" % (item.speed_bonus * mult))
	if item.turn_bonus > 0.0: lines.append("Wendung: +%.2f" % (item.turn_bonus * mult))
	if item.max_hp_bonus > 0.0: lines.append("Max-HP: +%.0f" % (item.max_hp_bonus * mult))
	if item.armor_bonus > 0.0: lines.append("Panzerung: +%.1f" % (item.armor_bonus * mult))
	if item.ram_damage_bonus > 0.0: lines.append("Ramm-Schaden: +%.0f" % (item.ram_damage_bonus * mult))
	if item.passive_repair_rate > 0.0: lines.append("Rumpf-Reparatur: +%.1f HP/s" % (item.passive_repair_rate * mult))
	if item.vision_bonus > 0.0: lines.append("Ziel-Reichweite: +%.0f px" % (item.vision_bonus * mult))
	lines.append("Gewicht: %.1f kg • Wert: %d Gold" % [item.weight, item.get_effective_gold_value()])

	var box_w: float = 360.0
	var box_h: float = 46.0 + float(lines.size()) * 22.0
	var pos: Vector2 = (mouse_pos + Vector2(18.0, 18.0)).floor()
	if pos.x + box_w > vp_size.x - 8.0: pos.x = mouse_pos.x - box_w - 14.0
	if pos.y + box_h > vp_size.y - 8.0: pos.y = vp_size.y - box_h - 8.0
	pos.x = maxf(8.0, pos.x)
	pos.y = maxf(8.0, pos.y)

	var accent: Color = UIThemeHelper.affix_color(item.affix, item.rarity)
	UIThemeHelper.draw_framed_panel(canvas, Rect2(pos, Vector2(box_w, box_h)), Color(0.09, 0.08, 0.13, 0.97), accent, UIThemeHelper.COL_BRASS_DIM)
	UIThemeHelper.draw_sharp_text(canvas, font, pos + Vector2(14.0, 26.0), item.get_display_name(), 17, accent, HORIZONTAL_ALIGNMENT_LEFT, int(box_w - 28.0))
	var ly: float = pos.y + 50.0
	for line in lines:
		UIThemeHelper.draw_sharp_text(canvas, font, Vector2(pos.x + 14.0, ly), line, 14, UIThemeHelper.COL_IVORY, HORIZONTAL_ALIGNMENT_LEFT, int(box_w - 28.0))
		ly += 22.0

class_name CargoGridUI
extends Control
## Dredge-inspired 1280x720 HD ship cargo & rigging blueprint UI.
## Uses ProceduralShipBaker.bake_item_grid_icon with TEXTURE_FILTER_NEAREST for
## crisp pixel-art item icons, calm darkened navy/mahogany panels with double brass
## borders, a stylized top-down ship deck silhouette around the 8x6 grid, and progress bars.

const PANEL_SIZE: Vector2 = Vector2(1040.0, 580.0)
const CELL_SIZE: float = 48.0
const GRID_OFFSET: Vector2 = Vector2(54.0, 102.0)
const STASH_RECT_REL: Rect2 = Rect2(512.0, 56.0, 260.0, 488.0)
const STATS_RECT_REL: Rect2 = Rect2(784.0, 56.0, 242.0, 508.0)
const CLOSE_BTN_REL: Rect2 = Rect2(996.0, 10.0, 32.0, 32.0)
const STASH_ROW_HEIGHT: float = 60.0
const STASH_HEADER_HEIGHT: float = 34.0

# Cohesive Navy / Mahogany / Brass / Ivory / Turquoise Palette
const COL_BG_DIM: Color = Color(0.03, 0.04, 0.07, 0.72)
const COL_PANEL_BG: Color = Color(0.10, 0.09, 0.14, 0.95)
const COL_PANEL_CARD: Color = Color(0.13, 0.12, 0.18, 0.94)
const COL_PANEL_INSET: Color = Color(0.08, 0.07, 0.11, 0.96)
const COL_HEADER_BG: Color = Color(0.15, 0.11, 0.12, 0.98)
const COL_OUTLINE: Color = Color(0.05, 0.04, 0.08, 0.95)
const COL_TEXT_OUTLINE: Color = Color(0.05, 0.04, 0.08, 0.85)
const COL_TEXT_SHADOW: Color = Color(0.03, 0.03, 0.06, 0.68)
const COL_BRASS: Color = Color(0.85, 0.66, 0.29, 0.95)       # #d8a94b
const COL_BRASS_DIM: Color = Color(0.46, 0.35, 0.18, 0.75)
const COL_TEXT_LIGHT: Color = Color(0.97, 0.94, 0.88, 1.0)   # #f7f0e0
const COL_TEXT_DIM: Color = Color(0.74, 0.71, 0.66, 1.0)
const COL_GOLD: Color = Color(0.96, 0.79, 0.27, 1.0)         # #f6c945
const COL_TURQUOISE: Color = Color(0.40, 0.88, 0.92, 1.0)
const COL_VALID: Color = Color(0.22, 0.82, 0.45, 0.30)
const COL_INVALID: Color = Color(0.90, 0.25, 0.28, 0.34)

var dredge_grid: DredgeGrid = null
var ship_physics: ShipPhysics = null

var _dragging_item: Contracts.GridItemData = null
var _drag_from_grid: bool = false
var _drag_orig_pos: Vector2i = Vector2i(-1, -1)
var _drag_orig_rot: bool = false
var _drag_rot: bool = false
var _drag_press_pos: Vector2 = Vector2.ZERO
var _drag_moved: bool = false

var _hovered_item: Contracts.GridItemData = null
var _hover_close: bool = false
var _stash_scroll: int = 0
var _updating_visibility: bool = false
var _pulse_time: float = 0.0

var _icon_cache: Dictionary = {} # "id_cat_wxh_rar_aff" -> ImageTexture


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false

	var bus: Contracts = Contracts.bus()
	if not bus.cargo_grid_toggled.is_connected(_on_cargo_grid_toggled):
		bus.cargo_grid_toggled.connect(_on_cargo_grid_toggled)
	if not bus.ship_stats_compiled.is_connected(_on_ship_stats_compiled):
		bus.ship_stats_compiled.connect(_on_ship_stats_compiled)
	if not bus.ship_grid_updated.is_connected(_on_ship_grid_updated):
		bus.ship_grid_updated.connect(_on_ship_grid_updated)


func bind_grid(grid: DredgeGrid, p_ship_physics: ShipPhysics = null) -> void:
	dredge_grid = grid
	ship_physics = p_ship_physics
	queue_redraw()


func setup(grid: DredgeGrid, p_ship_physics: ShipPhysics = null) -> void:
	bind_grid(grid, p_ship_physics)


func set_dredge_grid(grid: DredgeGrid) -> void:
	bind_grid(grid, ship_physics)


func _process(delta: float) -> void:
	if visible:
		_pulse_time += delta
		if _dragging_item != null or not (dredge_grid == null or dredge_grid.get_adjacent_synergy_cells().is_empty()):
			queue_redraw()


func _on_cargo_grid_toggled(open: bool) -> void:
	if _updating_visibility:
		return
	if not open and _dragging_item != null:
		_cancel_drag()
	visible = open
	if visible:
		_hovered_item = null
		queue_redraw()


func _on_ship_stats_compiled(p_ship_id: int, _stats: Contracts.ShipStats) -> void:
	if dredge_grid != null and p_ship_id == dredge_grid.ship_id and visible:
		queue_redraw()


func _on_ship_grid_updated(p_ship_id: int, _equipped: Array) -> void:
	if dredge_grid != null and p_ship_id == dredge_grid.ship_id and visible:
		queue_redraw()


func _toggle_open(open: bool) -> void:
	if not open and _dragging_item != null:
		_cancel_drag()
	_updating_visibility = true
	visible = open
	Contracts.bus().cargo_grid_toggled.emit(open)
	_updating_visibility = false
	if visible:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var toggle_pressed: bool = false
	if InputMap.has_action("toggle_grid") and event.is_action_pressed("toggle_grid"):
		toggle_pressed = true
	elif event is InputEventKey and event.pressed and not event.echo:
		var kev := event as InputEventKey
		if kev.keycode == KEY_G or kev.keycode == KEY_TAB:
			toggle_pressed = true
		elif visible and kev.keycode == KEY_ESCAPE:
			_toggle_open(false)
			get_viewport().set_input_as_handled()
			return

	if toggle_pressed:
		_toggle_open(not visible)
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	var rotate_pressed: bool = false
	if InputMap.has_action("rotate_item") and event.is_action_pressed("rotate_item"):
		rotate_pressed = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		rotate_pressed = true

	if rotate_pressed:
		if _dragging_item != null:
			_drag_rot = not _drag_rot
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif _hovered_item != null and dredge_grid != null and (_hovered_item in dredge_grid.placed_items):
			dredge_grid.rotate_item_in_grid(_hovered_item)
			queue_redraw()
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not visible or dredge_grid == null:
		return

	var panel_pos: Vector2 = _get_panel_pos()

	if event is InputEventMouseMotion:
		var mpos: Vector2 = (event as InputEventMouseMotion).position
		if _dragging_item != null and mpos.distance_to(_drag_press_pos) > 4.0:
			_drag_moved = true
		_update_hover(mpos, panel_pos)
		queue_redraw()
		accept_event()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var mpos: Vector2 = mb.position

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if Rect2(panel_pos + STASH_RECT_REL.position, STASH_RECT_REL.size).has_point(mpos):
				_stash_scroll = maxi(0, _stash_scroll - 1)
				queue_redraw()
				accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if Rect2(panel_pos + STASH_RECT_REL.position, STASH_RECT_REL.size).has_point(mpos):
				var max_vis: int = maxi(1, int(floor((STASH_RECT_REL.size.y - STASH_HEADER_HEIGHT - 4.0) / STASH_ROW_HEIGHT)))
				var max_scroll: int = maxi(0, dredge_grid.stash_items.size() - max_vis)
				_stash_scroll = mini(max_scroll, _stash_scroll + 1)
				queue_redraw()
				accept_event()
			return

		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _dragging_item != null:
				_drag_rot = not _drag_rot
				queue_redraw()
				accept_event()
				return
			else:
				var cell: Vector2i = _screen_to_grid_cell(mpos, panel_pos)
				var clicked: Contracts.GridItemData = dredge_grid.get_item_at(cell.x, cell.y)
				if clicked != null:
					dredge_grid.rotate_item_in_grid(clicked)
					queue_redraw()
					accept_event()
					return

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var close_rect := Rect2(panel_pos + CLOSE_BTN_REL.position, CLOSE_BTN_REL.size)
				if close_rect.has_point(mpos):
					_toggle_open(false)
					accept_event()
					return

				if _dragging_item == null:
					_try_begin_drag(mpos, panel_pos)
				else:
					_try_drop_drag(mpos, panel_pos)
				queue_redraw()
				accept_event()
			else:
				if _dragging_item != null and _drag_moved:
					_try_drop_drag(mpos, panel_pos)
					queue_redraw()
					accept_event()


func _get_panel_pos() -> Vector2:
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		vp_size = size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		vp_size = Vector2(1280.0, 720.0)
	return ((vp_size - PANEL_SIZE) * 0.5).floor()


func _get_grid_rect(panel_pos: Vector2) -> Rect2:
	return Rect2(
		panel_pos + GRID_OFFSET,
		Vector2(float(DredgeGrid.GRID_WIDTH) * CELL_SIZE, float(DredgeGrid.GRID_HEIGHT) * CELL_SIZE)
	)


func _screen_to_grid_cell(screen_pos: Vector2, panel_pos: Vector2) -> Vector2i:
	var rel: Vector2 = screen_pos - (panel_pos + GRID_OFFSET)
	if rel.x < 0.0 or rel.y < 0.0:
		return Vector2i(-1, -1)
	var gx: int = int(floor(rel.x / CELL_SIZE))
	var gy: int = int(floor(rel.y / CELL_SIZE))
	if gx < 0 or gx >= DredgeGrid.GRID_WIDTH or gy < 0 or gy >= DredgeGrid.GRID_HEIGHT:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)


func _get_drag_target_origin(screen_pos: Vector2, panel_pos: Vector2) -> Vector2i:
	if _dragging_item == null:
		return Vector2i(-1, -1)
	var eff_w: int = _dragging_item.height if _drag_rot else _dragging_item.width
	var eff_h: int = _dragging_item.width if _drag_rot else _dragging_item.height
	var grid_origin: Vector2 = panel_pos + GRID_OFFSET
	var rel: Vector2 = screen_pos - grid_origin
	var half_span := Vector2(float(eff_w) * CELL_SIZE * 0.5, float(eff_h) * CELL_SIZE * 0.5)
	var top_left: Vector2 = rel - half_span + Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)
	return Vector2i(int(floor(top_left.x / CELL_SIZE)), int(floor(top_left.y / CELL_SIZE)))


func _get_stash_item_at(screen_pos: Vector2, panel_pos: Vector2) -> Contracts.GridItemData:
	if dredge_grid == null:
		return null
	var stash_rect := Rect2(panel_pos + STASH_RECT_REL.position, STASH_RECT_REL.size)
	if not stash_rect.has_point(screen_pos):
		return null
	var list_top: float = stash_rect.position.y + STASH_HEADER_HEIGHT
	if screen_pos.y < list_top:
		return null
	var row: int = int(floor((screen_pos.y - list_top) / STASH_ROW_HEIGHT))
	var idx: int = _stash_scroll + row
	if idx >= 0 and idx < dredge_grid.stash_items.size():
		return dredge_grid.stash_items[idx]
	return null


func _update_hover(screen_pos: Vector2, panel_pos: Vector2) -> void:
	_hover_close = Rect2(panel_pos + CLOSE_BTN_REL.position, CLOSE_BTN_REL.size).has_point(screen_pos)
	var cell: Vector2i = _screen_to_grid_cell(screen_pos, panel_pos)
	if cell.x >= 0:
		_hovered_item = dredge_grid.get_item_at(cell.x, cell.y)
		return
	_hovered_item = _get_stash_item_at(screen_pos, panel_pos)


func _try_begin_drag(screen_pos: Vector2, panel_pos: Vector2) -> void:
	var cell: Vector2i = _screen_to_grid_cell(screen_pos, panel_pos)
	if cell.x >= 0:
		var grid_item: Contracts.GridItemData = dredge_grid.get_item_at(cell.x, cell.y)
		if grid_item != null:
			_dragging_item = grid_item
			_drag_from_grid = true
			_drag_orig_pos = grid_item.grid_pos
			_drag_orig_rot = grid_item.rotated
			_drag_rot = grid_item.rotated
			_drag_press_pos = screen_pos
			_drag_moved = false
			dredge_grid.remove_item(grid_item, false)
			return

	var stash_item: Contracts.GridItemData = _get_stash_item_at(screen_pos, panel_pos)
	if stash_item != null:
		_dragging_item = stash_item
		_drag_from_grid = false
		_drag_orig_pos = Vector2i(-1, -1)
		_drag_orig_rot = stash_item.rotated
		_drag_rot = stash_item.rotated
		_drag_press_pos = screen_pos
		_drag_moved = false


func _try_drop_drag(screen_pos: Vector2, panel_pos: Vector2) -> void:
	if _dragging_item == null:
		return

	var grid_rect := _get_grid_rect(panel_pos)
	if grid_rect.has_point(screen_pos):
		var origin: Vector2i = _get_drag_target_origin(screen_pos, panel_pos)
		if dredge_grid.can_place_item(_dragging_item, origin.x, origin.y, _drag_rot):
			dredge_grid.place_item(_dragging_item, origin.x, origin.y, _drag_rot)
			_dragging_item = null
			return

	var stash_rect := Rect2(panel_pos + STASH_RECT_REL.position, STASH_RECT_REL.size)
	if stash_rect.has_point(screen_pos):
		_dragging_item.rotated = false
		dredge_grid.add_to_stash(_dragging_item)
		_dragging_item = null
		return

	_cancel_drag()


func _cancel_drag() -> void:
	if _dragging_item == null:
		return
	if _drag_from_grid and dredge_grid != null:
		if not dredge_grid.place_item(_dragging_item, _drag_orig_pos.x, _drag_orig_pos.y, _drag_orig_rot):
			dredge_grid.add_to_stash(_dragging_item)
	_dragging_item = null


func _slot_fill_color(slot_type: int) -> Color:
	match slot_type:
		Contracts.SlotType.DECK_PORT:
			return Color(0.11, 0.19, 0.27, 0.95)
		Contracts.SlotType.DECK_STARBOARD:
			return Color(0.25, 0.13, 0.14, 0.95)
		Contracts.SlotType.MAST:
			return Color(0.23, 0.19, 0.12, 0.95)
		_:
			return Color(0.15, 0.12, 0.11, 0.95)


func _slot_border_color(slot_type: int) -> Color:
	match slot_type:
		Contracts.SlotType.DECK_PORT:
			return Color(0.32, 0.56, 0.72, 0.85)
		Contracts.SlotType.DECK_STARBOARD:
			return Color(0.68, 0.36, 0.34, 0.85)
		Contracts.SlotType.MAST:
			return Color(0.72, 0.58, 0.28, 0.85)
		_:
			return Color(0.34, 0.27, 0.22, 0.85)


func _affix_color(affix: int, rarity: int) -> Color:
	match affix:
		Contracts.ItemAffix.RUSTED:
			return Color(0.72, 0.58, 0.48, 1.0)
		Contracts.ItemAffix.MASTERWORK:
			return Color(0.42, 0.90, 0.96, 1.0)
		Contracts.ItemAffix.CURSED:
			return Color(0.86, 0.46, 0.96, 1.0)
		_:
			match rarity:
				Contracts.ItemRarity.UNCOMMON:
					return Color(0.48, 0.88, 0.54, 1.0)
				Contracts.ItemRarity.RARE:
					return Color(0.46, 0.72, 0.98, 1.0)
				Contracts.ItemRarity.LEGENDARY:
					return COL_GOLD
				_:
					return Color(0.68, 0.62, 0.52, 0.90)


func _draw_framed_panel(rect: Rect2, fill: Color, outer_border: Color = COL_BRASS, inner_border: Color = COL_BRASS_DIM) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	draw_rect(r, fill, true)
	draw_rect(r, outer_border, false, 1.0)
	if r.size.x > 6.0 and r.size.y > 6.0:
		var inner := Rect2(r.position + Vector2(2.0, 2.0), r.size - Vector2(4.0, 4.0))
		draw_rect(inner, inner_border, false, 1.0)


func _draw_clean_box(rect: Rect2, fill: Color, border: Color = COL_OUTLINE) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	draw_rect(r, fill, true)
	draw_rect(r, border, false, 1.0)


func _draw_sharp_text(
	font: Font,
	pos: Vector2,
	text: String,
	font_size: int,
	color: Color,
	align: int = HORIZONTAL_ALIGNMENT_LEFT,
	width: int = -1,
	outline_sz: int = 2
) -> void:
	var p: Vector2 = pos.round()
	draw_string(font, p + Vector2(1.0, 2.0), text, align, width, font_size, COL_TEXT_SHADOW)
	if outline_sz > 0:
		draw_string_outline(font, p, text, align, width, font_size, outline_sz, COL_TEXT_OUTLINE)
	draw_string(font, p, text, align, width, font_size, color)


func _get_item_icon_texture(item: Contracts.GridItemData) -> ImageTexture:
	if item == null:
		return null
	var key: String = "%s_%d_%dx%d_%d_%d" % [item.id, item.category, item.width, item.height, item.rarity, item.affix]
	if _icon_cache.has(key):
		return _icon_cache[key]

	var tex: ImageTexture = ProceduralShipBaker.bake_item_grid_icon(
		item.id,
		item.category,
		item.width,
		item.height,
		item.rarity,
		item.affix
	)
	_icon_cache[key] = tex
	return tex


func _draw_item_sprite(rect: Rect2, item: Contracts.GridItemData, is_rotated: bool, modulate_col: Color = Color.WHITE) -> void:
	var tex: ImageTexture = _get_item_icon_texture(item)
	if tex == null:
		return

	var pad: float = 4.0
	var inner_size := Vector2(maxf(16.0, rect.size.x - pad * 2.0), maxf(16.0, rect.size.y - pad * 2.0))
	var center: Vector2 = rect.get_center().round()

	if is_rotated:
		var unrot_size := Vector2(inner_size.y, inner_size.x)
		draw_set_transform(center, PI * 0.5, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-unrot_size * 0.5, unrot_size), false, modulate_col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect(tex, Rect2((center - inner_size * 0.5).round(), inner_size.round()), false, modulate_col)


func _draw_stash_item_sprite(box_rect: Rect2, item: Contracts.GridItemData) -> void:
	var tex: ImageTexture = _get_item_icon_texture(item)
	if tex == null:
		return
	var tw: float = float(tex.get_width())
	var th: float = float(tex.get_height())
	var pad_box: Vector2 = box_rect.size - Vector2(6.0, 6.0)
	var scale_f: float = minf(pad_box.x / maxf(1.0, tw), pad_box.y / maxf(1.0, th))
	var draw_size := Vector2(tw * scale_f, th * scale_f).round()
	var center: Vector2 = box_rect.get_center().round()
	draw_texture_rect(tex, Rect2((center - draw_size * 0.5).round(), draw_size), false)


func _draw() -> void:
	if not visible:
		return

	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG_DIM, true)

	var panel_pos: Vector2 = _get_panel_pos()
	var font: Font = ThemeDB.fallback_font

	# Main dark navy/mahogany panel with double brass trim
	_draw_framed_panel(Rect2(panel_pos, PANEL_SIZE), COL_PANEL_BG, COL_BRASS, COL_BRASS_DIM)

	# Calm header bar
	var header_rect := Rect2(panel_pos + Vector2(4.0, 4.0), Vector2(PANEL_SIZE.x - 8.0, 44.0))
	draw_rect(header_rect, COL_HEADER_BG, true)
	draw_line(
		Vector2(header_rect.position.x, header_rect.end.y),
		Vector2(header_rect.end.x, header_rect.end.y),
		COL_BRASS_DIM,
		1.5
	)

	_draw_sharp_text(font, panel_pos + Vector2(18.0, 33.0), "SCHIFFS-BLAUPAUSE & FRACHT (8x6)", 20, COL_GOLD)
	_draw_sharp_text(font, panel_pos + Vector2(514.0, 33.0), "BEUTE-LAGER", 18, COL_TEXT_LIGHT)
	_draw_sharp_text(font, panel_pos + Vector2(786.0, 33.0), "SCHIFFSWERTE", 18, COL_TEXT_LIGHT)

	var close_rect := Rect2(panel_pos + CLOSE_BTN_REL.position, CLOSE_BTN_REL.size)
	var close_bg: Color = Color(0.68, 0.24, 0.22, 1.0) if _hover_close else Color(0.46, 0.17, 0.16, 0.95)
	_draw_clean_box(close_rect, close_bg, COL_BRASS)
	_draw_sharp_text(font, close_rect.position + Vector2(0.0, 23.0), "X", 18, COL_TEXT_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, int(close_rect.size.x))

	if dredge_grid == null:
		_draw_sharp_text(font, panel_pos + Vector2(30.0, 110.0), "Kein DredgeGrid verbunden.", 16, COL_TEXT_LIGHT)
		return

	_draw_ship_blueprint_and_grid(panel_pos, font)
	_draw_stash_panel(panel_pos, font)
	_draw_stats_panel(panel_pos, font)

	var mouse_pos: Vector2 = get_local_mouse_position()
	if _dragging_item != null:
		_draw_dragging_ghost(mouse_pos, panel_pos, font)
	elif _hovered_item != null:
		_draw_tooltip(mouse_pos, _hovered_item, font)


func _draw_ship_blueprint_and_grid(panel_pos: Vector2, font: Font) -> void:
	var grid_origin: Vector2 = (panel_pos + GRID_OFFSET).round()
	var grid_px_size := Vector2(float(DredgeGrid.GRID_WIDTH) * CELL_SIZE, float(DredgeGrid.GRID_HEIGHT) * CELL_SIZE)
	var cy: float = grid_origin.y + grid_px_size.y * 0.5

	# Stylized Top-Down Ship Deck Blueprint Silhouette:
	# Rounded quarterdeck/stern on left (-X), pointed prow/bowsprit on right (+X)
	var left_x: float = grid_origin.x - 36.0
	var gx0: float = grid_origin.x - 6.0
	var gx1: float = grid_origin.x + grid_px_size.x + 4.0
	var bow_tip_x: float = gx1 + 48.0
	var top_y: float = grid_origin.y - 16.0
	var bot_y: float = grid_origin.y + grid_px_size.y + 16.0

	var hull_poly := PackedVector2Array([
		Vector2(left_x + 6.0, top_y + 28.0),   # Stern top-left curve
		Vector2(left_x + 18.0, top_y + 8.0),
		Vector2(gx0 + 28.0, top_y),            # Port bulwark start
		Vector2(gx1 - 16.0, top_y),            # Port bulwark end
		Vector2(gx1 + 22.0, top_y + 38.0),     # Bow shoulder top
		Vector2(bow_tip_x, cy),                # Pointed bow tip (+X)
		Vector2(gx1 + 22.0, bot_y - 38.0),     # Bow shoulder bottom
		Vector2(gx1 - 16.0, bot_y),            # Starboard bulwark end
		Vector2(gx0 + 28.0, bot_y),            # Starboard bulwark start
		Vector2(left_x + 18.0, bot_y - 8.0),
		Vector2(left_x + 6.0, bot_y - 28.0)    # Stern bottom-left curve
	])

	# Blueprint hull fill & subtle plank lines
	draw_colored_polygon(hull_poly, Color(0.14, 0.11, 0.12, 0.94))

	# Subtle deck plank lines in stern & bow extensions (low contrast, clean)
	for i in range(-4, 5):
		var py: float = cy + float(i) * 28.0
		var inset_x: float = absf(float(i)) * 7.0
		draw_line(
			Vector2(left_x + 18.0 + inset_x, py),
			Vector2(gx1 + 22.0 - inset_x * 1.4, py),
			Color(0.28, 0.22, 0.18, 0.35),
			1.5
		)

	# Outer brass hull outline + subtle inner blueprint border
	var hull_closed := hull_poly.duplicate()
	hull_closed.append(hull_poly[0])
	draw_polyline(hull_closed, COL_BRASS, 2.0, true)

	# Bowsprit spar at pointed bow (+X)
	draw_line(Vector2(bow_tip_x - 10.0, cy), Vector2(bow_tip_x + 16.0, cy), COL_BRASS, 3.0)
	draw_line(Vector2(bow_tip_x + 3.0, cy - 8.0), Vector2(bow_tip_x + 3.0, cy + 8.0), COL_BRASS_DIM, 1.5)

	# Quarterdeck stern railing & helm wheel icon at left (-X)
	var helm_c := Vector2(grid_origin.x - 20.0, cy)
	draw_line(Vector2(grid_origin.x - 4.0, top_y + 12.0), Vector2(grid_origin.x - 4.0, bot_y - 12.0), COL_BRASS_DIM, 1.5)
	draw_arc(helm_c, 10.0, 0.0, TAU, 20, COL_BRASS_DIM, 1.5)
	draw_circle(helm_c, 3.5, COL_BRASS)

	# Gunport notches along Port (top) & Starboard (bottom) rails
	for gx in range(DredgeGrid.GRID_WIDTH):
		var port_x: float = grid_origin.x + (float(gx) + 0.5) * CELL_SIZE
		draw_rect(Rect2(port_x - 5.0, top_y - 2.0, 10.0, 5.0), Color(0.32, 0.56, 0.72, 0.90), true)
		draw_rect(Rect2(port_x - 5.0, bot_y - 3.0, 10.0, 5.0), Color(0.68, 0.36, 0.34, 0.90), true)

	# Clear blueprint directional labels
	_draw_sharp_text(
		font,
		Vector2(grid_origin.x, top_y - 6.0),
		"BACKBORD (Q)",
		14,
		Color(0.54, 0.84, 0.96),
		HORIZONTAL_ALIGNMENT_CENTER,
		int(grid_px_size.x)
	)
	_draw_sharp_text(
		font,
		Vector2(grid_origin.x, bot_y + 19.0),
		"STEUERBORD (E)",
		14,
		Color(0.95, 0.58, 0.52),
		HORIZONTAL_ALIGNMENT_CENTER,
		int(grid_px_size.x)
	)

	# Clean inset frame for the 8x6 Grid
	_draw_clean_box(Rect2(grid_origin - Vector2(3.0, 3.0), grid_px_size + Vector2(6.0, 6.0)), COL_PANEL_INSET, COL_BRASS_DIM)

	for gy in range(DredgeGrid.GRID_HEIGHT):
		for gx in range(DredgeGrid.GRID_WIDTH):
			var slot_type: int = dredge_grid.get_slot_type(gx, gy)
			var cell_rect := Rect2(
				grid_origin + Vector2(float(gx) * CELL_SIZE, float(gy) * CELL_SIZE),
				Vector2(CELL_SIZE, CELL_SIZE)
			)
			_draw_clean_box(cell_rect, _slot_fill_color(slot_type), _slot_border_color(slot_type))

	# Blueprint Mast Ring & Zone Watermarks (subtle, crisp, never cluttered)
	var mast_center := Vector2(grid_origin.x + 4.0 * CELL_SIZE, grid_origin.y + 3.0 * CELL_SIZE)
	draw_arc(mast_center, CELL_SIZE * 0.78, 0.0, TAU, 32, Color(0.85, 0.66, 0.29, 0.28), 1.5)
	draw_line(
		mast_center + Vector2(0.0, -CELL_SIZE * 0.92),
		mast_center + Vector2(0.0, CELL_SIZE * 0.92),
		Color(0.85, 0.66, 0.29, 0.24),
		2.0
	)
	_draw_sharp_text(
		font,
		Vector2(grid_origin.x + 2.0 * CELL_SIZE, grid_origin.y + 3.0 * CELL_SIZE + 6.0),
		"MAST",
		16,
		Color(0.92, 0.78, 0.42, 0.42),
		HORIZONTAL_ALIGNMENT_CENTER,
		int(4.0 * CELL_SIZE),
		0
	)
	_draw_sharp_text(
		font,
		Vector2(grid_origin.x + 4.0, grid_origin.y + 4.0 * CELL_SIZE + 26.0),
		"FRACHTRAUM",
		16,
		Color(0.82, 0.76, 0.66, 0.36),
		HORIZONTAL_ALIGNMENT_CENTER,
		int(grid_px_size.x - 8.0),
		0
	)

	# Placed Items
	var synergy_cells: Array[Vector2i] = dredge_grid.get_adjacent_synergy_cells()
	for item in dredge_grid.placed_items:
		var eff_size: Vector2i = item.get_effective_size()
		var item_rect := Rect2(
			grid_origin + Vector2(float(item.grid_pos.x) * CELL_SIZE + 2.0, float(item.grid_pos.y) * CELL_SIZE + 2.0),
			Vector2(float(eff_size.x) * CELL_SIZE - 4.0, float(eff_size.y) * CELL_SIZE - 4.0)
		)
		# Calm dark slate background with a whisper of item tint + crisp rarity frame
		var tile_bg: Color = Color(0.11, 0.11, 0.16, 0.94).lerp(item.primary_color, 0.10)
		var border: Color = _affix_color(item.affix, item.rarity)
		if _hovered_item == item:
			border = COL_GOLD
		_draw_clean_box(item_rect, tile_bg, border)
		draw_line(
			item_rect.position + Vector2(1.0, 1.0),
			Vector2(item_rect.end.x - 1.0, item_rect.position.y + 1.0),
			Color(1.0, 1.0, 1.0, 0.10),
			1.5
		)
		_draw_item_sprite(item_rect, item, item.rotated)
		if item.affix != Contracts.ItemAffix.STANDARD:
			var tag: String = "R" if item.affix == Contracts.ItemAffix.RUSTED else ("M" if item.affix == Contracts.ItemAffix.MASTERWORK else "V")
			_draw_sharp_text(font, item_rect.position + Vector2(5.0, 17.0), tag, 14, border)

	# Golden synergy highlights
	var pulse_alpha: float = 0.58 + 0.35 * sin(_pulse_time * 5.0)
	var syn_border := Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, pulse_alpha)
	for sc in synergy_cells:
		var s_rect := Rect2(
			grid_origin + Vector2(float(sc.x) * CELL_SIZE + 2.0, float(sc.y) * CELL_SIZE + 2.0),
			Vector2(CELL_SIZE - 4.0, CELL_SIZE - 4.0)
		)
		draw_rect(s_rect, Color(1.0, 0.84, 0.22, 0.14), true)
		draw_rect(s_rect, syn_border, false, 2.0)

	# Legend & Controls neatly below ship blueprint
	var ly: float = bot_y + 36.0
	var lx: float = panel_pos.x + 20.0
	_draw_legend_chip(Vector2(lx, ly), Contracts.SlotType.DECK_PORT, "Backbord (Q)", font)
	_draw_legend_chip(Vector2(lx + 210.0, ly), Contracts.SlotType.DECK_STARBOARD, "Steuerbord (E)", font)
	_draw_legend_chip(Vector2(lx, ly + 24.0), Contracts.SlotType.MAST, "Mast (Segel)", font)
	_draw_legend_chip(Vector2(lx + 210.0, ly + 24.0), Contracts.SlotType.CARGO_HOLD, "Frachtraum", font)

	var class_title: String = _get_class_title()
	_draw_sharp_text(font, Vector2(lx, ly + 62.0), "Schiffsklasse: %s" % class_title, 16, COL_TURQUOISE)
	_draw_sharp_text(font, Vector2(lx, ly + 84.0), "Ziehen: Bewegen  •  [R] / Rechtsklick: Drehen", 14, COL_TEXT_LIGHT)
	_draw_sharp_text(font, Vector2(lx, ly + 104.0), "Gold-Rahmen: Pulver / Quartier neben Kanone!", 14, COL_GOLD)
	_draw_sharp_text(font, Vector2(lx, ly + 124.0), "[I / Tab / Esc] Inventar schließen", 14, COL_TEXT_DIM)


func _get_class_title() -> String:
	var tier: int = dredge_grid.hull_tier if dredge_grid != null else 0
	if ship_physics != null:
		tier = ship_physics.hull_tier
	match tier:
		Contracts.ShipClass.BRIGANTINE:
			return "Brigg"
		Contracts.ShipClass.FRIGATE:
			return "Schwere Fregatte"
		_:
			return "Schaluppe"


func _draw_legend_chip(pos: Vector2, slot_type: int, label: String, font: Font) -> void:
	_draw_clean_box(Rect2(pos.round(), Vector2(16.0, 16.0)), _slot_fill_color(slot_type), _slot_border_color(slot_type))
	_draw_sharp_text(font, pos + Vector2(22.0, 13.0), label, 14, COL_TEXT_LIGHT)


func _draw_stash_panel(panel_pos: Vector2, font: Font) -> void:
	var sr := Rect2((panel_pos + STASH_RECT_REL.position).round(), STASH_RECT_REL.size.round())
	_draw_framed_panel(sr, COL_PANEL_INSET, COL_BRASS_DIM, Color(0.22, 0.18, 0.14, 0.55))
	_draw_sharp_text(
		font,
		sr.position + Vector2(12.0, 24.0),
		"Gegenstände (%d)" % dredge_grid.stash_items.size(),
		15,
		COL_TEXT_DIM
	)

	var list_top: float = sr.position.y + STASH_HEADER_HEIGHT
	var max_visible: int = int(floor((sr.size.y - STASH_HEADER_HEIGHT - 4.0) / STASH_ROW_HEIGHT))
	if dredge_grid.stash_items.is_empty():
		_draw_sharp_text(font, Vector2(sr.position.x + 14.0, list_top + 32.0), "Leer. Ziehe Items hierher.", 14, COL_TEXT_DIM)
	else:
		var drawn_row: int = 0
		for i in range(max_visible + 1):
			if drawn_row >= max_visible:
				break
			var idx: int = _stash_scroll + i
			if idx >= dredge_grid.stash_items.size():
				break
			var item: Contracts.GridItemData = dredge_grid.stash_items[idx]
			if item == _dragging_item:
				continue
			var row_rect := Rect2(
				sr.position.x + 8.0,
				list_top + float(drawn_row) * STASH_ROW_HEIGHT,
				sr.size.x - 16.0,
				STASH_ROW_HEIGHT - 5.0
			)
			var border: Color = _affix_color(item.affix, item.rarity)
			var is_hov: bool = (_hovered_item == item)
			var card_bg: Color = Color(0.17, 0.16, 0.23, 0.96) if is_hov else COL_PANEL_CARD
			_draw_clean_box(row_rect, card_bg, COL_GOLD if is_hov else border)

			var icon_box := Rect2(row_rect.position + Vector2(5.0, 4.0), Vector2(47.0, 47.0))
			_draw_clean_box(icon_box, COL_PANEL_INSET, Color(border.r, border.g, border.b, 0.45))
			_draw_stash_item_sprite(icon_box, item)

			var short_name: String = item.get_display_name()
			if short_name.length() > 21:
				short_name = short_name.substr(0, 20) + "."
			_draw_sharp_text(font, row_rect.position + Vector2(58.0, 22.0), short_name, 14, border)
			_draw_sharp_text(
				font,
				row_rect.position + Vector2(58.0, 43.0),
				"%dx%d • %d Gold" % [item.width, item.height, item.get_effective_gold_value()],
				14,
				COL_TEXT_DIM
			)
			drawn_row += 1

	var hint_pos := Vector2(sr.position.x + 6.0, sr.position.y + sr.size.y + 22.0)
	_draw_sharp_text(font, hint_pos, "Mausrad: Stash scrollen", 14, COL_TEXT_DIM)


func _draw_stats_panel(panel_pos: Vector2, font: Font) -> void:
	var st_rect := Rect2((panel_pos + STATS_RECT_REL.position).round(), STATS_RECT_REL.size.round())
	_draw_framed_panel(st_rect, COL_PANEL_INSET, COL_BRASS_DIM, Color(0.22, 0.18, 0.14, 0.55))

	var stats: Contracts.ShipStats = dredge_grid.current_stats
	var cur_hp: float = ship_physics.hp if ship_physics != null else stats.max_hp
	var x: float = st_rect.position.x + 12.0
	var bar_w: float = st_rect.size.x - 24.0
	var y: float = st_rect.position.y + 24.0

	# 1. Rumpf-HP Progress Bar
	var hp_ratio: float = clampf(cur_hp / maxf(1.0, stats.max_hp), 0.0, 1.0)
	var hp_col: Color = Color(0.32, 0.82, 0.46) if hp_ratio > 0.35 else Color(0.92, 0.30, 0.28)
	_draw_stat_bar(
		Vector2(x, y), bar_w,
		"Rumpf-HP", "%d/%d" % [int(round(cur_hp)), int(round(stats.max_hp))],
		hp_ratio, hp_col, COL_TEXT_LIGHT, font
	)
	y += 38.0

	# 2. Geschwindigkeit Progress Bar
	var spd_ratio: float = clampf(stats.max_speed / 260.0, 0.0, 1.0)
	_draw_stat_bar(
		Vector2(x, y), bar_w,
		"Geschwindigkeit", "%d kn" % int(round(stats.max_speed * 0.14)),
		spd_ratio, COL_TURQUOISE, COL_TURQUOISE, font
	)
	y += 38.0

	# 3. Traglast Progress Bar
	var weight_ratio: float = clampf(stats.total_weight / maxf(1.0, stats.max_safe_weight), 0.0, 1.0)
	var over_w: bool = stats.cargo_weight_penalty > 0.0
	var weight_col: Color = Color(0.94, 0.34, 0.30) if over_w else (COL_GOLD if weight_ratio > 0.80 else Color(0.46, 0.86, 0.52))
	var weight_txt: String = "%.0f/%.0f" % [stats.total_weight, stats.max_safe_weight]
	if over_w:
		weight_txt += " (-%d%%)" % int(round(stats.cargo_weight_penalty * 100.0))
	_draw_stat_bar(
		Vector2(x, y), bar_w,
		"Traglast", weight_txt,
		weight_ratio, weight_col, weight_col, font
	)
	y += 40.0

	# Secondary compact stats
	_draw_stat_line(Vector2(x, y), bar_w, "Panzerung:", "%.1f" % stats.armor, COL_TEXT_LIGHT, font)
	y += 23.0
	_draw_stat_line(Vector2(x, y), bar_w, "Wendung:", "%.2f" % stats.turn_speed, COL_TEXT_LIGHT, font)
	y += 16.0

	# Broadsides Section with firepower bars
	draw_line(Vector2(x, y), Vector2(x + bar_w, y), COL_BRASS_DIM, 1.5)
	y += 22.0
	_draw_sharp_text(font, Vector2(x, y), "BREITSEITEN-FEUERKRAFT", 15, COL_GOLD)
	y += 24.0

	var max_salvo_ref: float = maxf(60.0, maxf(stats.port_salvo_damage, stats.starboard_salvo_damage))
	_draw_stat_bar(
		Vector2(x, y), bar_w,
		"Backbord (%dx)" % stats.port_cannons.size(),
		"%d DMG" % int(round(stats.port_salvo_damage)),
		clampf(stats.port_salvo_damage / max_salvo_ref, 0.0, 1.0),
		Color(0.42, 0.76, 0.96), Color(0.62, 0.86, 1.0), font
	)
	y += 38.0
	_draw_stat_bar(
		Vector2(x, y), bar_w,
		"Steuerbord (%dx)" % stats.starboard_cannons.size(),
		"%d DMG" % int(round(stats.starboard_salvo_damage)),
		clampf(stats.starboard_salvo_damage / max_salvo_ref, 0.0, 1.0),
		Color(0.94, 0.48, 0.44), Color(0.98, 0.64, 0.58), font
	)
	y += 36.0

	# Synergies Section
	draw_line(Vector2(x, y), Vector2(x + bar_w, y), COL_BRASS_DIM, 1.5)
	y += 22.0
	_draw_sharp_text(font, Vector2(x, y), "SYNERGIEN", 15, COL_GOLD)
	y += 24.0

	var syn_cells: int = dredge_grid.get_adjacent_synergy_cells().size()
	var syn_txt: String = "Aktiv!" if syn_cells > 0 else "Keine"
	var syn_col: Color = COL_GOLD if syn_cells > 0 else COL_TEXT_DIM
	_draw_stat_line(Vector2(x, y), bar_w, "Lade-Boost:", syn_txt, syn_col, font)
	y += 22.0
	var haz_col: Color = Color(0.96, 0.44, 0.32) if stats.explosion_hazard_damage > 0.0 else COL_TEXT_DIM
	_draw_stat_line(Vector2(x, y), bar_w, "Expl.-Risiko:", "+%.0f" % stats.explosion_hazard_damage, haz_col, font)
	y += 22.0
	if stats.passive_repair_rate > 0.0:
		_draw_stat_line(Vector2(x, y), bar_w, "Reparatur:", "+%.1f/s" % stats.passive_repair_rate, Color(0.50, 0.92, 0.58), font)
		y += 22.0
	if stats.ram_damage_bonus > 0.0:
		_draw_stat_line(Vector2(x, y), bar_w, "Ramm-Bonus:", "+%.0f" % stats.ram_damage_bonus, Color(0.86, 0.90, 0.98), font)
		y += 22.0
	if stats.vision_bonus > 0.0:
		_draw_stat_line(Vector2(x, y), bar_w, "Ausguck:", "+%.0fpx" % stats.vision_bonus, COL_GOLD, font)


func _draw_stat_bar(
	pos: Vector2,
	width: float,
	label: String,
	val_text: String,
	ratio: float,
	bar_color: Color,
	val_color: Color,
	font: Font
) -> void:
	_draw_sharp_text(font, pos, label, 14, COL_TEXT_DIM)
	_draw_sharp_text(font, pos, val_text, 14, val_color, HORIZONTAL_ALIGNMENT_RIGHT, int(width))
	var bar_rect := Rect2(pos.x, pos.y + 7.0, width, 10.0)
	draw_rect(bar_rect, Color(0.05, 0.05, 0.08, 0.95), true)
	var fill_w: float = floor(width * clampf(ratio, 0.0, 1.0))
	if fill_w > 0.0:
		draw_rect(Rect2(bar_rect.position, Vector2(fill_w, bar_rect.size.y)), bar_color, true)
		draw_rect(Rect2(bar_rect.position, Vector2(fill_w, 2.0)), Color(1.0, 1.0, 1.0, 0.25), true)
	draw_rect(bar_rect, Color(0.32, 0.28, 0.24, 0.85), false, 1.5)


func _draw_stat_line(pos: Vector2, width: float, label: String, value: String, val_color: Color, font: Font) -> void:
	_draw_sharp_text(font, pos, label, 14, COL_TEXT_DIM)
	_draw_sharp_text(font, pos, value, 14, val_color, HORIZONTAL_ALIGNMENT_RIGHT, int(width))


func _draw_dragging_ghost(mouse_pos: Vector2, panel_pos: Vector2, font: Font) -> void:
	var grid_origin: Vector2 = (panel_pos + GRID_OFFSET).round()
	var grid_rect := _get_grid_rect(panel_pos)
	var eff_w: int = _dragging_item.height if _drag_rot else _dragging_item.width
	var eff_h: int = _dragging_item.width if _drag_rot else _dragging_item.height

	if grid_rect.has_point(mouse_pos):
		var origin: Vector2i = _get_drag_target_origin(mouse_pos, panel_pos)
		var is_valid: bool = dredge_grid.can_place_item(_dragging_item, origin.x, origin.y, _drag_rot)
		var preview_col: Color = COL_VALID if is_valid else COL_INVALID
		var preview_border: Color = Color(0.38, 0.94, 0.56) if is_valid else Color(0.96, 0.34, 0.34)

		var cells: Array[Vector2i] = dredge_grid.get_item_cells(_dragging_item, origin.x, origin.y, _drag_rot)
		for c in cells:
			if c.x < 0 or c.x >= DredgeGrid.GRID_WIDTH or c.y < 0 or c.y >= DredgeGrid.GRID_HEIGHT:
				continue
			var cr := Rect2(
				grid_origin + Vector2(float(c.x) * CELL_SIZE, float(c.y) * CELL_SIZE),
				Vector2(CELL_SIZE, CELL_SIZE)
			)
			_draw_clean_box(cr, preview_col, preview_border)

		if is_valid:
			var syn_preview: Array[Vector2i] = dredge_grid.get_synergy_pairs_for_preview(_dragging_item, origin.x, origin.y, _drag_rot)
			for sc in syn_preview:
				var sr := Rect2(
					grid_origin + Vector2(float(sc.x) * CELL_SIZE + 2.0, float(sc.y) * CELL_SIZE + 2.0),
					Vector2(CELL_SIZE - 4.0, CELL_SIZE - 4.0)
				)
				draw_rect(sr, Color(1.0, 0.84, 0.22, 0.30), true)
				draw_rect(sr, COL_GOLD, false, 2.0)

	# Floating sprite with calm dark backdrop, drop shadow, golden selection frame & [R] Drehen hint
	var scale_up: float = 1.12
	var ghost_size := Vector2(float(eff_w) * CELL_SIZE * scale_up, float(eff_h) * CELL_SIZE * scale_up).round()
	var ghost_rect := Rect2((mouse_pos - ghost_size * 0.5).round(), ghost_size)
	var shadow_rect := Rect2(ghost_rect.position + Vector2(5.0, 6.0), ghost_rect.size)

	draw_rect(shadow_rect, Color(0.02, 0.02, 0.05, 0.50), true)
	draw_rect(ghost_rect, Color(0.10, 0.09, 0.15, 0.90), true)
	_draw_item_sprite(ghost_rect, _dragging_item, _drag_rot, Color.WHITE)
	draw_rect(ghost_rect, COL_GOLD, false, 2.0)
	draw_rect(Rect2(ghost_rect.position - Vector2(1.0, 1.0), ghost_rect.size + Vector2(2.0, 2.0)), COL_OUTLINE, false, 1.0)

	var hint_rect := Rect2(ghost_rect.position.x, ghost_rect.end.y + 5.0, maxf(110.0, ghost_rect.size.x), 24.0)
	_draw_clean_box(hint_rect, Color(0.08, 0.07, 0.12, 0.92), COL_BRASS_DIM)
	_draw_sharp_text(font, hint_rect.position + Vector2(0.0, 17.0), "[R] Drehen", 14, COL_GOLD, HORIZONTAL_ALIGNMENT_CENTER, int(hint_rect.size.x))


func _category_label(cat: int) -> String:
	match cat:
		Contracts.ItemCategory.CANNON:
			return "Kanone"
		Contracts.ItemCategory.POWDER_BARREL:
			return "Pulverfass"
		Contracts.ItemCategory.SAIL:
			return "Segel"
		Contracts.ItemCategory.HULL:
			return "Rumpf"
		Contracts.ItemCategory.CREW_MOD:
			return "Crew-Modul"
		Contracts.ItemCategory.TREASURE:
			return "Schatz"
		_:
			return "Handelsgut"


func _draw_tooltip(mouse_pos: Vector2, item: Contracts.GridItemData, font: Font) -> void:
	var lines: Array[String] = []
	lines.append("%s (%dx%d)" % [_category_label(item.category), item.width, item.height])

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
	if item.explosion_hazard > 0.0:
		lines.append("Risiko: +%.0f Trefferschaden" % item.explosion_hazard)
	if item.speed_bonus > 0.0:
		lines.append("Tempo: +%.1f kn" % (item.speed_bonus * mult))
	if item.turn_bonus > 0.0:
		lines.append("Wendung: +%.2f" % (item.turn_bonus * mult))
	if item.max_hp_bonus > 0.0:
		lines.append("Max-HP: +%.0f" % (item.max_hp_bonus * mult))
	if item.armor_bonus > 0.0:
		lines.append("Panzerung: +%.1f" % (item.armor_bonus * mult))
	if item.ram_damage_bonus > 0.0:
		lines.append("Ramm-Schaden: +%.0f" % (item.ram_damage_bonus * mult))
	if item.passive_repair_rate > 0.0:
		lines.append("Rumpf-Reparatur: +%.1f HP/s" % (item.passive_repair_rate * mult))
	if item.vision_bonus > 0.0:
		lines.append("Ziel-Reichweite: +%.0f px" % (item.vision_bonus * mult))

	lines.append("Gewicht: %.1f kg • Wert: %d Gold" % [item.weight, item.get_effective_gold_value()])

	var box_w: float = 360.0
	var box_h: float = 46.0 + float(lines.size()) * 22.0
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		vp_size = size
	var pos: Vector2 = (mouse_pos + Vector2(18.0, 18.0)).floor()
	if pos.x + box_w > vp_size.x - 8.0:
		pos.x = mouse_pos.x - box_w - 14.0
	if pos.y + box_h > vp_size.y - 8.0:
		pos.y = vp_size.y - box_h - 8.0
	pos.x = maxf(8.0, pos.x)
	pos.y = maxf(8.0, pos.y)

	var accent: Color = _affix_color(item.affix, item.rarity)
	_draw_framed_panel(Rect2(pos, Vector2(box_w, box_h)), Color(0.09, 0.08, 0.13, 0.97), accent, COL_BRASS_DIM)
	_draw_sharp_text(font, pos + Vector2(14.0, 26.0), item.get_display_name(), 17, accent, HORIZONTAL_ALIGNMENT_LEFT, int(box_w - 28.0))
	var ly: float = pos.y + 50.0
	for line in lines:
		_draw_sharp_text(font, Vector2(pos.x + 14.0, ly), line, 14, COL_TEXT_LIGHT, HORIZONTAL_ALIGNMENT_LEFT, int(box_w - 28.0))
		ly += 22.0

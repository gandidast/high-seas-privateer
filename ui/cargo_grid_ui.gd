class_name CargoGridUI
extends Control
## Dredge-inspired 1280x720 HD ship cargo & rigging blueprint UI.
## Uses CargoSlotRenderer + UIThemeHelper with TEXTURE_FILTER_NEAREST pixel-art
## item icons and clean drag/drop/rotate interaction.

const PANEL_SIZE: Vector2 = CargoSlotRenderer.PANEL_SIZE
const CELL_SIZE: float = CargoSlotRenderer.CELL_SIZE
const GRID_OFFSET: Vector2 = CargoSlotRenderer.GRID_OFFSET
const STASH_RECT_REL: Rect2 = CargoSlotRenderer.STASH_RECT_REL
const STATS_RECT_REL: Rect2 = CargoSlotRenderer.STATS_RECT_REL
const CLOSE_BTN_REL: Rect2 = CargoSlotRenderer.CLOSE_BTN_REL
const STASH_ROW_HEIGHT: float = CargoSlotRenderer.STASH_ROW_HEIGHT
const STASH_HEADER_HEIGHT: float = CargoSlotRenderer.STASH_HEADER_HEIGHT
const SYNERGY_PULSE_INTERVAL: float = 0.07 # ~14 Hz pulse when visible with active synergies

var dredge_grid: DredgeGrid = null
var ship_physics: ShipPhysics = null

var _renderer: CargoSlotRenderer = CargoSlotRenderer.new()
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
var _pulse_accum: float = 0.0


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
	if visible:
		queue_redraw()


func setup(grid: DredgeGrid, p_ship_physics: ShipPhysics = null) -> void:
	bind_grid(grid, p_ship_physics)


func set_dredge_grid(grid: DredgeGrid) -> void:
	bind_grid(grid, ship_physics)


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse_time += delta
	if _dragging_item != null:
		queue_redraw()
		return
	if dredge_grid != null and not dredge_grid.get_adjacent_synergy_cells().is_empty():
		_pulse_accum += delta
		if _pulse_accum >= SYNERGY_PULSE_INTERVAL:
			_pulse_accum = 0.0
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

	var rotate_pressed: bool = (InputMap.has_action("rotate_item") and event.is_action_pressed("rotate_item")) \
		or (event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_R)

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
				_stash_scroll = mini(maxi(0, dredge_grid.stash_items.size() - max_vis), _stash_scroll + 1)
				queue_redraw()
				accept_event()
			return

		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _dragging_item != null:
				_drag_rot = not _drag_rot
				queue_redraw()
				accept_event()
				return
			var cell: Vector2i = _screen_to_grid_cell(mpos, panel_pos)
			var clicked: Contracts.GridItemData = dredge_grid.get_item_at(cell.x, cell.y)
			if clicked != null:
				dredge_grid.rotate_item_in_grid(clicked)
				queue_redraw()
				accept_event()
				return

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if Rect2(panel_pos + CLOSE_BTN_REL.position, CLOSE_BTN_REL.size).has_point(mpos):
					_toggle_open(false)
					accept_event()
					return
				if _dragging_item == null:
					_try_begin_drag(mpos, panel_pos)
				else:
					_try_drop_drag(mpos, panel_pos)
				queue_redraw()
				accept_event()
			elif _dragging_item != null and _drag_moved:
				_try_drop_drag(mpos, panel_pos)
				queue_redraw()
				accept_event()


func _get_panel_pos() -> Vector2:
	var vp_size: Vector2 = _get_vp_size()
	return ((vp_size - PANEL_SIZE) * 0.5).floor()


func _get_vp_size() -> Vector2:
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		vp_size = size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		return Vector2(1280.0, 720.0)
	return vp_size


func _get_grid_rect(panel_pos: Vector2) -> Rect2:
	return Rect2(panel_pos + GRID_OFFSET, Vector2(float(DredgeGrid.GRID_WIDTH) * CELL_SIZE, float(DredgeGrid.GRID_HEIGHT) * CELL_SIZE))


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
	var rel: Vector2 = screen_pos - (panel_pos + GRID_OFFSET)
	var top_left: Vector2 = rel - Vector2(float(eff_w) * CELL_SIZE * 0.5, float(eff_h) * CELL_SIZE * 0.5) + Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)
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
	var idx: int = _stash_scroll + int(floor((screen_pos.y - list_top) / STASH_ROW_HEIGHT))
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
	if _get_grid_rect(panel_pos).has_point(screen_pos):
		var origin: Vector2i = _get_drag_target_origin(screen_pos, panel_pos)
		if dredge_grid.can_place_item(_dragging_item, origin.x, origin.y, _drag_rot):
			dredge_grid.place_item(_dragging_item, origin.x, origin.y, _drag_rot)
			_dragging_item = null
			return
	if Rect2(panel_pos + STASH_RECT_REL.position, STASH_RECT_REL.size).has_point(screen_pos):
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


func _draw() -> void:
	if not visible:
		return
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	draw_rect(Rect2(Vector2.ZERO, size), UIThemeHelper.COL_BG_DIM_CARGO, true)

	var panel_pos: Vector2 = _get_panel_pos()
	var font: Font = UIThemeHelper.get_font()
	UIThemeHelper.draw_framed_panel(self, Rect2(panel_pos, PANEL_SIZE), UIThemeHelper.COL_PANEL_BG, UIThemeHelper.COL_BRASS, UIThemeHelper.COL_BRASS_DIM)

	var header_rect := Rect2(panel_pos + Vector2(4.0, 4.0), Vector2(PANEL_SIZE.x - 8.0, 44.0))
	draw_rect(header_rect, UIThemeHelper.COL_HEADER_BG, true)
	draw_line(Vector2(header_rect.position.x, header_rect.end.y), Vector2(header_rect.end.x, header_rect.end.y), UIThemeHelper.COL_BRASS_DIM, 1.5)

	UIThemeHelper.draw_sharp_text(self, font, panel_pos + Vector2(18.0, 33.0), "SCHIFFS-BLAUPAUSE & FRACHT (8x6)", 20, UIThemeHelper.COL_GOLD)
	UIThemeHelper.draw_sharp_text(self, font, panel_pos + Vector2(514.0, 33.0), "BEUTE-LAGER", 18, UIThemeHelper.COL_IVORY)
	UIThemeHelper.draw_sharp_text(self, font, panel_pos + Vector2(786.0, 33.0), "SCHIFFSWERTE", 18, UIThemeHelper.COL_IVORY)

	var close_rect := Rect2(panel_pos + CLOSE_BTN_REL.position, CLOSE_BTN_REL.size)
	var close_bg: Color = Color(0.68, 0.24, 0.22, 1.0) if _hover_close else Color(0.46, 0.17, 0.16, 0.95)
	UIThemeHelper.draw_clean_box(self, close_rect, close_bg, UIThemeHelper.COL_BRASS)
	UIThemeHelper.draw_sharp_text(self, font, close_rect.position + Vector2(0.0, 23.0), "X", 18, UIThemeHelper.COL_IVORY, HORIZONTAL_ALIGNMENT_CENTER, int(close_rect.size.x))

	if dredge_grid == null:
		UIThemeHelper.draw_sharp_text(self, font, panel_pos + Vector2(30.0, 110.0), "Kein DredgeGrid verbunden.", 16, UIThemeHelper.COL_IVORY)
		return

	_renderer.draw_ship_blueprint_and_grid(self, panel_pos, font, dredge_grid, ship_physics, _hovered_item, _pulse_time)
	_renderer.draw_stash_panel(self, panel_pos, font, dredge_grid, _stash_scroll, _dragging_item, _hovered_item)
	_renderer.draw_stats_panel(self, panel_pos, font, dredge_grid, ship_physics)

	var mouse_pos: Vector2 = get_local_mouse_position()
	if _dragging_item != null:
		var origin: Vector2i = _get_drag_target_origin(mouse_pos, panel_pos)
		_renderer.draw_dragging_ghost(self, mouse_pos, panel_pos, font, dredge_grid, _dragging_item, _drag_rot, origin)
	elif _hovered_item != null:
		_renderer.draw_tooltip(self, mouse_pos, _get_vp_size(), _hovered_item, font)

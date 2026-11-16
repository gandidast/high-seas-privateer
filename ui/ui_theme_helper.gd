class_name UIThemeHelper
extends RefCounted
## Shared HD dark-navy / mahogany / brass / ivory theme helper for UILayer controls.
## Centralizes palette constants, StyleBoxFlat builders, Label/Button factories,
## cached fallback font, and reusable canvas draw helpers.

const COL_BG_DIM_CARGO: Color = Color(0.03, 0.04, 0.07, 0.72)
const COL_BG_DIM_HARBOR: Color = Color(0.03, 0.04, 0.07, 0.68)
const COL_PANEL_BG: Color = Color(0.10, 0.09, 0.14, 0.95)
const COL_HUD_PANEL_BG: Color = Color(0.10, 0.09, 0.14, 0.90)
const COL_PANEL_CARD: Color = Color(0.13, 0.12, 0.18, 0.94)
const COL_PANEL_CARD_INNER: Color = Color(0.16, 0.14, 0.21, 0.95)
const COL_PANEL_INSET: Color = Color(0.08, 0.07, 0.11, 0.96)
const COL_HUD_INSET: Color = Color(0.07, 0.07, 0.11, 0.94)
const COL_HEADER_BG: Color = Color(0.15, 0.11, 0.12, 0.98)

const COL_BRASS: Color = Color(0.85, 0.66, 0.29, 0.95)
const COL_BRASS_DIM: Color = Color(0.46, 0.35, 0.18, 0.75)
const COL_OUTLINE: Color = Color(0.05, 0.04, 0.08, 0.85)
const COL_OUTLINE_SOLID: Color = Color(0.05, 0.04, 0.08, 0.95)
const COL_SHADOW: Color = Color(0.03, 0.03, 0.06, 0.70)
const COL_IVORY: Color = Color(0.97, 0.94, 0.88, 1.0)
const COL_MUTED: Color = Color(0.75, 0.72, 0.68, 1.0)
const COL_GOLD: Color = Color(0.96, 0.79, 0.27, 1.0)
const COL_TURQUOISE: Color = Color(0.40, 0.88, 0.92, 1.0)

static var _cached_font: Font = null
static var _chamfer_outer: PackedVector2Array = PackedVector2Array([
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO
])
static var _chamfer_outer_closed: PackedVector2Array = PackedVector2Array([
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO
])
static var _chamfer_inner_closed: PackedVector2Array = PackedVector2Array([
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO
])


static func get_font() -> Font:
	if _cached_font == null:
		_cached_font = ThemeDB.fallback_font
	return _cached_font


static func make_box_style(
	bg: Color,
	border: Color,
	corner_rad: int = 3,
	border_w: int = 1,
	margin: int = 5
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(corner_rad)
	sb.set_content_margin_all(margin)
	return sb


static func apply_text_style(ctrl: Control, font_size: int, color: Color) -> void:
	ctrl.add_theme_font_size_override("font_size", maxi(14, font_size))
	ctrl.add_theme_color_override("font_color", color)
	ctrl.add_theme_color_override("font_outline_color", COL_OUTLINE)
	ctrl.add_theme_constant_override("outline_size", 2)
	ctrl.add_theme_color_override("font_shadow_color", COL_SHADOW)
	ctrl.add_theme_constant_override("shadow_offset_x", 1)
	ctrl.add_theme_constant_override("shadow_offset_y", 2)


static func make_label(txt: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	apply_text_style(lbl, font_size, color)
	return lbl


static func make_button(txt: String, bg: Color, font_size: int = 15) -> Button:
	var btn := Button.new()
	btn.text = txt
	apply_text_style(btn, font_size, COL_IVORY)
	btn.add_theme_stylebox_override("normal", make_box_style(bg, COL_BRASS, 4, 1, 8))
	btn.add_theme_stylebox_override("hover", make_box_style(bg.lightened(0.14), COL_GOLD, 4, 1, 8))
	btn.add_theme_stylebox_override("pressed", make_box_style(bg.darkened(0.18), COL_GOLD, 4, 1, 8))
	btn.add_theme_stylebox_override(
		"disabled",
		make_box_style(Color(0.14, 0.13, 0.16, 0.90), Color(0.32, 0.29, 0.28, 0.80), 4, 1, 8)
	)
	return btn


static func affix_color(affix: int, rarity: int) -> Color:
	match affix:
		Contracts.ItemAffix.RUSTED:
			return Color(0.72, 0.58, 0.48, 1.0)
		Contracts.ItemAffix.RARE:
			return Color(0.38, 0.84, 0.98, 1.0)
		Contracts.ItemAffix.MASTERWORK:
			return Color(1.0, 0.84, 0.30, 1.0)
		Contracts.ItemAffix.CURSED:
			return Color(0.92, 0.30, 0.96, 1.0)
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


static func slot_fill_color(slot_type: int) -> Color:
	match slot_type:
		Contracts.SlotType.DECK_PORT:
			return Color(0.11, 0.19, 0.27, 0.95)
		Contracts.SlotType.DECK_STARBOARD:
			return Color(0.25, 0.13, 0.14, 0.95)
		Contracts.SlotType.MAST:
			return Color(0.23, 0.19, 0.12, 0.95)
		_:
			return Color(0.15, 0.12, 0.11, 0.95)


static func slot_border_color(slot_type: int) -> Color:
	match slot_type:
		Contracts.SlotType.DECK_PORT:
			return Color(0.32, 0.56, 0.72, 0.85)
		Contracts.SlotType.DECK_STARBOARD:
			return Color(0.68, 0.36, 0.34, 0.85)
		Contracts.SlotType.MAST:
			return Color(0.72, 0.58, 0.28, 0.85)
		_:
			return Color(0.34, 0.27, 0.22, 0.85)


static func draw_sharp_text(
	canvas: CanvasItem,
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
	canvas.draw_string(font, p + Vector2(1.0, 2.0), text, align, width, font_size, COL_SHADOW)
	if outline_sz > 0:
		canvas.draw_string_outline(font, p, text, align, width, font_size, outline_sz, COL_OUTLINE)
	canvas.draw_string(font, p, text, align, width, font_size, color)


static func _fill_chamfer_pts(buf: PackedVector2Array, x0: float, y0: float, x1: float, y1: float, c: float, closed: bool) -> void:
	buf[0] = Vector2(x0 + c, y0)
	buf[1] = Vector2(x1 - c, y0)
	buf[2] = Vector2(x1, y0 + c)
	buf[3] = Vector2(x1, y1 - c)
	buf[4] = Vector2(x1 - c, y1)
	buf[5] = Vector2(x0 + c, y1)
	buf[6] = Vector2(x0, y1 - c)
	buf[7] = Vector2(x0, y0 + c)
	if closed:
		buf[8] = buf[0]


static func draw_chamfered_panel(
	canvas: CanvasItem,
	rect: Rect2,
	fill: Color,
	border: Color = COL_BRASS,
	inner_border: Color = COL_BRASS_DIM,
	chamfer: float = 4.0
) -> void:
	var x0: float = rect.position.x
	var y0: float = rect.position.y
	var x1: float = rect.end.x
	var y1: float = rect.end.y
	var c: float = minf(chamfer, minf(rect.size.x, rect.size.y) * 0.25)

	_fill_chamfer_pts(_chamfer_outer, x0, y0, x1, y1, c, false)
	canvas.draw_colored_polygon(_chamfer_outer, fill)
	_fill_chamfer_pts(_chamfer_outer_closed, x0, y0, x1, y1, c, true)
	canvas.draw_polyline(_chamfer_outer_closed, border, 1.0, true)

	if rect.size.x > 10.0 and rect.size.y > 10.0:
		var ic: float = maxf(1.0, c - 1.0)
		_fill_chamfer_pts(_chamfer_inner_closed, x0 + 2.0, y0 + 2.0, x1 - 2.0, y1 - 2.0, ic, true)
		canvas.draw_polyline(_chamfer_inner_closed, inner_border, 1.0, true)


static func draw_framed_panel(
	canvas: CanvasItem,
	rect: Rect2,
	fill: Color,
	outer_border: Color = COL_BRASS,
	inner_border: Color = COL_BRASS_DIM
) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	canvas.draw_rect(r, fill, true)
	canvas.draw_rect(r, outer_border, false, 1.0)
	if r.size.x > 6.0 and r.size.y > 6.0:
		canvas.draw_rect(Rect2(r.position + Vector2(2.0, 2.0), r.size - Vector2(4.0, 4.0)), inner_border, false, 1.0)


static func draw_clean_box(
	canvas: CanvasItem,
	rect: Rect2,
	fill: Color,
	border: Color = COL_OUTLINE_SOLID
) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	canvas.draw_rect(r, fill, true)
	canvas.draw_rect(r, border, false, 1.0)


static func draw_progress_bar(
	canvas: CanvasItem,
	rect: Rect2,
	ratio: float,
	fill_col: Color,
	bg_col: Color,
	border_col: Color,
	highlight_h: float = 2.0
) -> void:
	canvas.draw_rect(rect, bg_col, true)
	var fill_w: float = floor(rect.size.x * clampf(ratio, 0.0, 1.0))
	if fill_w > 0.0:
		canvas.draw_rect(Rect2(rect.position, Vector2(fill_w, rect.size.y)), fill_col, true)
		if highlight_h > 0.0:
			canvas.draw_rect(Rect2(rect.position, Vector2(fill_w, highlight_h)), Color(1.0, 1.0, 1.0, 0.25), true)
	canvas.draw_rect(rect, border_col, false, 1.5)

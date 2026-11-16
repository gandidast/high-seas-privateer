class_name PixelCamera
extends Camera2D
## Smooth 2D pixel-art follow camera with integer sub-pixel snapping,
## velocity lookahead, and trauma-based screen shake.

@export var follow_smoothing: float = 8.5
@export var lookahead_factor: float = 0.28
@export var max_lookahead_px: float = 44.0
@export var trauma_decay: float = 1.9
@export var max_shake_px: float = 9.0

var _follow_target: Node2D = null
var _target_has_smooth_pos: bool = false
var _smooth_pos: Vector2 = Vector2.ZERO
var _prev_target_pos: Vector2 = Vector2.ZERO
var _has_prev_target_pos: bool = false
var _lookahead_offset: Vector2 = Vector2.ZERO
var _trauma: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	enabled = true
	position_smoothing_enabled = false
	_smooth_pos = global_position


func _get_target_world_pos() -> Vector2:
	if is_instance_valid(_follow_target):
		if _target_has_smooth_pos:
			return _follow_target.call("get_smooth_world_pos")
		return _follow_target.global_position
	return Vector2.ZERO


func set_follow_target(target: Node2D) -> void:
	_follow_target = target
	_target_has_smooth_pos = is_instance_valid(_follow_target) and _follow_target.has_method("get_smooth_world_pos")
	_has_prev_target_pos = false
	if is_instance_valid(_follow_target):
		_prev_target_pos = _get_target_world_pos()
		_has_prev_target_pos = true


func snap_to_pos(world_pos: Vector2) -> void:
	_smooth_pos = world_pos
	_lookahead_offset = Vector2.ZERO
	if is_instance_valid(_follow_target):
		_prev_target_pos = _get_target_world_pos()
		_has_prev_target_pos = true
	global_position = _smooth_pos.round()


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + maxf(0.0, amount), 0.0, 1.0)


func get_view_world_rect(margin: float = 0.0) -> Rect2:
	var vp := get_viewport()
	var vp_size := Vector2(640.0, 360.0)
	if vp != null:
		vp_size = vp.get_visible_rect().size
		if vp is SubViewport:
			var sv := vp as SubViewport
			if sv.size.x > 0 and sv.size.y > 0:
				vp_size = Vector2(sv.size)
	var zoom_safe := Vector2(maxf(0.25, zoom.x), maxf(0.25, zoom.y))
	var world_size: Vector2 = vp_size / zoom_safe
	return Rect2(get_screen_center_position() - world_size * 0.5, world_size).grow(margin)


func get_world_mouse_pos() -> Vector2:
	if not is_inside_tree():
		return global_position
	var vp := get_viewport()
	if vp == null:
		return global_position
	if vp is SubViewport:
		var container := vp.get_parent() as SubViewportContainer
		if container != null and container.size.x > 0.0 and container.size.y > 0.0:
			var local_mouse: Vector2 = container.get_local_mouse_position()
			var vp_size := Vector2((vp as SubViewport).size)
			if vp_size.x > 0.0 and vp_size.y > 0.0:
				var vp_mouse: Vector2 = local_mouse * (vp_size / container.size)
				return get_canvas_transform().affine_inverse() * vp_mouse
	return get_global_mouse_position()


func _process(delta: float) -> void:
	if is_instance_valid(_follow_target):
		var target_pos: Vector2 = _get_target_world_pos()
		var est_vel := Vector2.ZERO
		if _has_prev_target_pos and delta > 0.0001:
			var raw_vel: Vector2 = (target_pos - _prev_target_pos) / delta
			if raw_vel.length() < 900.0:
				est_vel = raw_vel
		_prev_target_pos = target_pos
		_has_prev_target_pos = true

		var desired_lookahead: Vector2 = (est_vel * lookahead_factor).limit_length(max_lookahead_px)
		_lookahead_offset = _lookahead_offset.lerp(desired_lookahead, minf(1.0, delta * 4.5))

		var desired_pos: Vector2 = target_pos + _lookahead_offset
		_smooth_pos = _smooth_pos.lerp(desired_pos, minf(1.0, delta * follow_smoothing))

	# Integer sub-pixel snap locks 1:1 pixel-art grid at 640x360
	global_position = _smooth_pos.round()

	# Quadratic trauma screen shake snapped to whole pixels
	if _trauma > 0.0:
		var shake: float = _trauma * _trauma * max_shake_px
		offset = Vector2(
			round(_rng.randf_range(-1.0, 1.0) * shake),
			round(_rng.randf_range(-1.0, 1.0) * shake)
		)
		_trauma = maxf(0.0, _trauma - trauma_decay * delta)
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO

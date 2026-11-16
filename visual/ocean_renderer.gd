class_name OceanRenderer
extends Node2D
## Renders the deterministic 2D pixel-art ocean, islands, wind streaks,
## dynamic weather (clear/fog/storm + lightning), procedural harbor piers,
## coastal fort foundations/markers, and crisp island name banners.

const SHADER_PATH := "res://visual/ocean_shader.gdshader"
const OUTLINE_COLOR := Color(0.094, 0.078, 0.145, 1.0) # #181425 crisp dark outline
const MIN_QUAD_SIZE := Vector2(768.0, 448.0)
const DEPTH_MAP_RES: int = 1024
const DEPTH_MAP_HALF_EXTENT: float = Contracts.WORLD_HALF_EXTENT
const SHADOW_COLOR := Color(0.06, 0.05, 0.09, 0.28)

static var _depth_tex_cache: Dictionary = {} # world_seed -> ImageTexture

var _world_seed: int = Contracts.DEFAULT_WORLD_SEED
var _camera_center: Vector2 = Vector2.ZERO
var _quad_world_size: Vector2 = MIN_QUAD_SIZE
var _wind_dir: Vector2 = Vector2(1.0, 0.0)
var _wind_strength: float = 1.0
var _islands: Array[Contracts.IslandData] = []
var _time_accum: float = 0.0

var _weather_state: int = Contracts.WeatherState.CLEAR
var _weather_intensity: float = 0.0
var _target_weather_intensity: float = 0.0
var _lightning_amount: float = 0.0
var _lightning_world_pos: Vector2 = Vector2.ZERO

var _ocean_sprite: Sprite2D
var _shader_mat: ShaderMaterial
var _harbor_root: Node2D
var _pier_texture: ImageTexture
var _harbor_buoy_markers: Array[Dictionary] = []
var _harbor_props: Array[Dictionary] = [] # { "node": Node2D, "pos": Vector2, "margin": float }
var _forts: Dictionary = {} # fort_id -> { "pos": Vector2, "island_index": int, "hp": float, "max_hp": float, "hit_flash": float }

# Cached last-uploaded shader uniforms to avoid redundant GPU uploads
var _last_shader_seed: int = -999999999
var _last_shader_cam: Vector2 = Vector2(INF, INF)
var _last_shader_vp: Vector2 = Vector2(-1.0, -1.0)
var _last_shader_wind_dir: Vector2 = Vector2(INF, INF)
var _last_shader_wind_str: float = -1.0
var _last_shader_weather: int = -1
var _last_shader_weather_int: float = -1.0
var _last_shader_lightning_amt: float = -1.0
var _last_shader_lightning_pos: Vector2 = Vector2(INF, INF)
var _had_visible_drawables: bool = false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_nodes()
	_connect_signals()
	setup(_world_seed)


func _ensure_nodes() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _ocean_sprite != null:
		return

	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var white_tex := ImageTexture.create_from_image(img)

	_shader_mat = ShaderMaterial.new()
	var shader_res: Shader = load(SHADER_PATH) as Shader
	if shader_res != null:
		_shader_mat.shader = shader_res

	_ocean_sprite = Sprite2D.new()
	_ocean_sprite.name = "OceanQuad"
	_ocean_sprite.texture = white_tex
	_ocean_sprite.centered = false
	_ocean_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ocean_sprite.z_index = -100
	_ocean_sprite.material = _shader_mat
	add_child(_ocean_sprite)

	_harbor_root = Node2D.new()
	_harbor_root.name = "HarborProps"
	_harbor_root.z_index = -10
	_harbor_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_harbor_root)

	_pier_texture = _bake_pier_texture()


func _connect_signals() -> void:
	var bus: Contracts = Contracts.bus()
	if bus == null:
		return
	if not bus.wind_changed.is_connected(_on_wind_changed):
		bus.wind_changed.connect(_on_wind_changed)
	if not bus.world_initialized.is_connected(_on_world_initialized):
		bus.world_initialized.connect(_on_world_initialized)
	if not bus.weather_changed.is_connected(_on_weather_changed):
		bus.weather_changed.connect(_on_weather_changed)
	if not bus.lightning_flash.is_connected(_on_lightning_flash):
		bus.lightning_flash.connect(_on_lightning_flash)
	if not bus.fort_spawned.is_connected(_on_fort_spawned):
		bus.fort_spawned.connect(_on_fort_spawned)
	if not bus.fort_damaged.is_connected(_on_fort_damaged):
		bus.fort_damaged.connect(_on_fort_damaged)
	if not bus.fort_destroyed.is_connected(_on_fort_destroyed):
		bus.fort_destroyed.connect(_on_fort_destroyed)


func setup(world_seed: int = Contracts.DEFAULT_WORLD_SEED) -> void:
	_ensure_nodes()
	_world_seed = world_seed
	_islands = Contracts.get_islands(_world_seed)
	_apply_world_uniforms()
	_rebuild_harbor_props()
	_sync_quad_transform()
	_update_prop_culling()


func set_camera_center(world_pos: Vector2) -> void:
	_ensure_nodes()
	_camera_center = world_pos
	_sync_quad_transform()
	_update_prop_culling()


func set_wind(direction: Vector2, strength: float) -> void:
	_ensure_nodes()
	if direction.length_squared() > 0.0001:
		_wind_dir = direction.normalized()
	_wind_strength = maxf(0.0, strength)
	if _shader_mat != null:
		if not _wind_dir.is_equal_approx(_last_shader_wind_dir):
			_last_shader_wind_dir = _wind_dir
			_shader_mat.set_shader_parameter("wind_dir", _wind_dir)
		if not is_equal_approx(_wind_strength, _last_shader_wind_str):
			_last_shader_wind_str = _wind_strength
			_shader_mat.set_shader_parameter("wind_strength", _wind_strength)


func set_weather(weather_state: int, intensity: float = 1.0) -> void:
	_ensure_nodes()
	_weather_state = clampi(weather_state, Contracts.WeatherState.CLEAR, Contracts.WeatherState.STORM)
	_target_weather_intensity = 0.0 if _weather_state == Contracts.WeatherState.CLEAR else clampf(intensity, 0.0, 1.0)
	_weather_intensity = _target_weather_intensity
	_apply_weather_uniforms()


func trigger_lightning(world_pos: Vector2) -> void:
	_ensure_nodes()
	_lightning_world_pos = world_pos
	_lightning_amount = 1.0
	_apply_weather_uniforms()


func _process(delta: float) -> void:
	_time_accum += delta

	if _lightning_amount > 0.0:
		_lightning_amount = maxf(0.0, _lightning_amount - delta * 2.8)

	if not is_equal_approx(_weather_intensity, _target_weather_intensity):
		_weather_intensity = move_toward(_weather_intensity, _target_weather_intensity, delta * 0.65)

	for fid in _forts.keys():
		var f: Dictionary = _forts[fid]
		if float(f["hit_flash"]) > 0.0:
			f["hit_flash"] = maxf(0.0, float(f["hit_flash"]) - delta)

	var vp := get_viewport()
	if vp != null:
		var vp_size: Vector2 = vp.get_visible_rect().size
		if vp is SubViewport:
			var sv := vp as SubViewport
			if sv.size.x > 0 and sv.size.y > 0:
				vp_size = Vector2(sv.size)
		var zoom_safe := Vector2.ONE
		var cam := vp.get_camera_2d()
		if cam != null:
			_camera_center = cam.get_screen_center_position()
			zoom_safe = Vector2(maxf(0.25, cam.zoom.x), maxf(0.25, cam.zoom.y))
		var world_view := vp_size / zoom_safe + Vector2(128.0, 128.0)
		var even_w: float = maxf(MIN_QUAD_SIZE.x, ceil(world_view.x * 0.5) * 2.0)
		var even_h: float = maxf(MIN_QUAD_SIZE.y, ceil(world_view.y * 0.5) * 2.0)
		_quad_world_size = Vector2(even_w, even_h)

	_sync_quad_transform()
	_apply_weather_uniforms()
	var has_visible: bool = _update_prop_culling()
	if has_visible or _had_visible_drawables:
		_had_visible_drawables = has_visible
		queue_redraw()


func _get_cull_rect() -> Rect2:
	return Rect2(_camera_center - _quad_world_size * 0.5, _quad_world_size)


func _update_prop_culling() -> bool:
	var cam_rect: Rect2 = _get_cull_rect()
	for prop in _harbor_props:
		var node := prop["node"] as Node2D
		if is_instance_valid(node):
			var margin: float = float(prop["margin"])
			node.visible = cam_rect.grow(margin).has_point(prop["pos"] as Vector2)

	for marker in _harbor_buoy_markers:
		if cam_rect.grow(float(marker["radius"]) + 16.0).has_point(marker["pos"] as Vector2):
			return true
	for fid in _forts.keys():
		if cam_rect.grow(36.0).has_point(_forts[fid]["pos"] as Vector2):
			return true
	return false


func _draw() -> void:
	var cam_rect: Rect2 = _get_cull_rect()

	# 1. Subtle dotted pixel-art harbor zone rings & buoy glints on the water (culled)
	for marker in _harbor_buoy_markers:
		var center: Vector2 = marker["pos"]
		var radius: float = float(marker["radius"])
		if not cam_rect.grow(radius + 16.0).has_point(center):
			continue
		var segments: int = 24
		var pulse: float = 0.55 + 0.25 * sin(_time_accum * 2.4 + float(marker["index"]))
		var ring_col := Color(0.957, 0.855, 0.451, 0.36 * pulse)
		var base_rot: float = _time_accum * 0.08
		for i in range(0, segments, 2):
			var a0: float = (float(i) / float(segments)) * TAU + base_rot
			var a1: float = (float(i) + 0.55) / float(segments) * TAU + base_rot
			var p0: Vector2 = center + Vector2(cos(a0), sin(a0)) * radius
			var p1: Vector2 = center + Vector2(cos(a1), sin(a1)) * radius
			draw_line(p0.round(), p1.round(), ring_col, 1.0, false)

	# 2. Subtle pixel ground shadow under forts (culled)
	var shadow_rect: Rect2 = cam_rect.grow(36.0)
	for fid in _forts.keys():
		var fpos: Vector2 = (_forts[fid]["pos"] as Vector2).round()
		if shadow_rect.has_point(fpos):
			draw_circle(fpos + Vector2(1, 2), 20.0, SHADOW_COLOR)


func _sync_quad_transform() -> void:
	if _ocean_sprite == null or _shader_mat == null:
		return
	var snapped_center: Vector2 = _camera_center.round()
	var half_size: Vector2 = (_quad_world_size * 0.5).round()
	_ocean_sprite.position = snapped_center - half_size
	_ocean_sprite.scale = _quad_world_size * 0.5

	if snapped_center != _last_shader_cam:
		_last_shader_cam = snapped_center
		_shader_mat.set_shader_parameter("camera_world_pos", snapped_center)
	if _quad_world_size != _last_shader_vp:
		_last_shader_vp = _quad_world_size
		_shader_mat.set_shader_parameter("viewport_size", _quad_world_size)


func _apply_world_uniforms() -> void:
	if _shader_mat == null:
		return
	if _world_seed != _last_shader_seed:
		_last_shader_seed = _world_seed
		var depth_tex: ImageTexture = _get_or_bake_depth_texture(_world_seed)
		_shader_mat.set_shader_parameter("world_seed", _world_seed)
		_shader_mat.set_shader_parameter("world_depth_tex", depth_tex)
		_shader_mat.set_shader_parameter("world_half_extent", DEPTH_MAP_HALF_EXTENT)
		_shader_mat.set_shader_parameter("has_baked_depth", true)
	if not _wind_dir.is_equal_approx(_last_shader_wind_dir):
		_last_shader_wind_dir = _wind_dir
		_shader_mat.set_shader_parameter("wind_dir", _wind_dir)
	if not is_equal_approx(_wind_strength, _last_shader_wind_str):
		_last_shader_wind_str = _wind_strength
		_shader_mat.set_shader_parameter("wind_strength", _wind_strength)


func _apply_weather_uniforms() -> void:
	if _shader_mat == null:
		return
	if _weather_state != _last_shader_weather:
		_last_shader_weather = _weather_state
		_shader_mat.set_shader_parameter("weather_state", _weather_state)
	if not is_equal_approx(_weather_intensity, _last_shader_weather_int):
		_last_shader_weather_int = _weather_intensity
		_shader_mat.set_shader_parameter("weather_intensity", _weather_intensity)
	if not is_equal_approx(_lightning_amount, _last_shader_lightning_amt):
		_last_shader_lightning_amt = _lightning_amount
		_shader_mat.set_shader_parameter("lightning_amount", _lightning_amount)
	if not _lightning_world_pos.is_equal_approx(_last_shader_lightning_pos):
		_last_shader_lightning_pos = _lightning_world_pos
		_shader_mat.set_shader_parameter("lightning_world_pos", _lightning_world_pos)


static func _get_or_bake_depth_texture(world_seed: int) -> ImageTexture:
	if _depth_tex_cache.has(world_seed):
		return _depth_tex_cache[world_seed]

	var res: int = DEPTH_MAP_RES
	var half_ext: float = DEPTH_MAP_HALF_EXTENT
	var full_span: float = half_ext * 2.0
	var world_step: float = full_span / float(res)
	var transition_band: float = 140.0

	# Fill base image with deep-water sentinel (sd = 1.0 -> R = 255, G = 255, B = 0, A = 255)
	var base_img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	base_img.fill(Color(1.0, 1.0, 0.0, 1.0))
	var data: PackedByteArray = base_img.get_data()

	for idx in range(Contracts.ISLAND_COUNT):
		var center: Vector2 = Contracts.get_island_center(idx, world_seed)
		var base_r: float = Contracts.get_island_radius(idx, world_seed)
		var phase: float = Contracts.get_island_phase(idx, world_seed)
		var harbor_angle: float = Contracts.get_island_harbor_angle(idx, world_seed)
		var max_r: float = base_r * 1.35 + transition_band * 1.5
		var max_r_sq: float = max_r * max_r

		var px_min: int = clampi(int(floor((center.x - max_r + half_ext) / world_step)), 0, res - 1)
		var px_max: int = clampi(int(ceil((center.x + max_r + half_ext) / world_step)), 0, res - 1)
		var py_min: int = clampi(int(floor((center.y - max_r + half_ext) / world_step)), 0, res - 1)
		var py_max: int = clampi(int(ceil((center.y + max_r + half_ext) / world_step)), 0, res - 1)

		for py in range(py_min, py_max + 1):
			var wy: float = ((float(py) + 0.5) / float(res) - 0.5) * full_span
			var dy: float = wy - center.y
			var dy_sq: float = dy * dy
			var row_off: int = py * res * 4
			for px in range(px_min, px_max + 1):
				var wx: float = ((float(px) + 0.5) / float(res) - 0.5) * full_span
				var dx: float = wx - center.x
				var dist_sq: float = dx * dx + dy_sq
				if dist_sq > max_r_sq:
					continue
				var dist: float = sqrt(dist_sq)
				var theta: float = atan2(dy, dx) if dist > 0.0001 else 0.0
				var wave: float = (
					0.14 * sin(theta * 3.0 + phase)
					+ 0.09 * cos(theta * 5.0 - phase * 1.3)
					+ 0.05 * sin(theta * 7.0 + phase * 2.1)
				)
				var angle_diff: float = wrapf(theta - harbor_angle, -PI, PI)
				var cove: float = exp(-(angle_diff * angle_diff) / 0.18)
				var coast_r: float = base_r * (1.0 + wave - 0.28 * cove)
				var sd: float = (dist - coast_r) / transition_band
				if sd >= 1.0:
					continue

				var r_byte: int = clampi(int(round(clampf((sd + 1.0) * 0.5, 0.0, 1.0) * 255.0)), 0, 255)
				var off: int = row_off + px * 4
				if r_byte < data[off]:
					data[off] = r_byte
					data[off + 1] = clampi(int(round(clampf((sd + 0.24) / 0.48, 0.0, 1.0) * 255.0)), 0, 255)

	var baked_img := Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, data)
	var tex := ImageTexture.create_from_image(baked_img)
	_depth_tex_cache[world_seed] = tex
	return tex


func _rebuild_harbor_props() -> void:
	if _harbor_root == null:
		return
	for child in _harbor_root.get_children():
		child.queue_free()
	_harbor_buoy_markers.clear()
	_harbor_props.clear()

	for isl in _islands:
		var coast_r: float = Contracts.get_island_coast_radius(isl.index, isl.harbor_angle, _world_seed)
		var dir := Vector2(cos(isl.harbor_angle), sin(isl.harbor_angle))

		if isl.has_harbor:
			var pier_pos: Vector2 = (isl.center + dir * (coast_r + 14.0)).round()
			var pier_sprite := Sprite2D.new()
			pier_sprite.name = "Pier_%d" % isl.index
			pier_sprite.texture = _pier_texture
			pier_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			pier_sprite.position = pier_pos
			pier_sprite.rotation = isl.harbor_angle
			_harbor_root.add_child(pier_sprite)
			_harbor_props.append({ "node": pier_sprite, "pos": pier_pos, "margin": 48.0 })

			_harbor_buoy_markers.append({
				"index": isl.index,
				"pos": isl.harbor_pos,
				"radius": isl.harbor_radius
			})

		var banner := _create_island_banner(isl.name, isl.has_harbor)
		var banner_anchor: Vector2 = (isl.center + dir * (coast_r - 22.0) + Vector2(0.0, -26.0)).round()
		banner.position = banner_anchor
		_harbor_root.add_child(banner)
		_harbor_props.append({ "node": banner, "pos": banner_anchor, "margin": 96.0 })


func _create_island_banner(island_name: String, is_safe_harbor: bool = true) -> Node2D:
	var holder := Node2D.new()
	holder.z_index = 22

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.094, 0.075, 0.114, 0.94)
	style.border_color = Color(0.847, 0.663, 0.294, 1.0) if is_safe_harbor else Color(0.745, 0.314, 0.267, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0.04, 0.03, 0.07, 0.55)
	style.shadow_size = 2
	style.shadow_offset = Vector2(1.0, 2.0)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = island_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.969, 0.941, 0.878, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.08, 0.88))
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.03, 0.06, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	panel.add_child(label)

	panel.position = Vector2(-60.0, -13.0)
	panel.custom_minimum_size = Vector2(120.0, 18.0)
	holder.add_child(panel)
	return holder


func _bake_pier_texture() -> ImageTexture:
	var w: int = 44
	var h: int = 18
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var wood_dark := Color(0.380, 0.220, 0.145, 1.0)
	var wood_mid := Color(0.561, 0.337, 0.231, 1.0)
	var wood_light := Color(0.722, 0.435, 0.314, 1.0)
	var wood_hi := Color(0.851, 0.627, 0.400, 1.0)
	var foam := Color(0.918, 0.969, 0.976, 0.90)
	var brass := Color(0.957, 0.706, 0.106, 1.0)
	var lantern := Color(1.0, 0.875, 0.451, 1.0)

	for x in range(3, 41):
		var is_seam: bool = (x % 3 == 0)
		for y in range(5, 13):
			var c: Color = wood_mid
			if is_seam:
				c = wood_dark
			elif y == 5:
				c = wood_hi
			elif y == 6 or y == 7:
				c = wood_light
			elif y == 12:
				c = wood_dark
			img.set_pixel(x, y, c)

	for x in range(35, 42):
		for y in range(3, 15):
			var c: Color = wood_mid if (x % 3 != 0) else wood_dark
			if y == 3 or x == 35:
				c = wood_hi
			elif y == 14:
				c = wood_dark
			img.set_pixel(x, y, c)

	for px in [8, 17, 26, 36, 40]:
		for py in [4, 13]:
			img.set_pixel(px, py, wood_dark)
			img.set_pixel(px + 1, py, wood_light)
			if px >= 17:
				var fy: int = py - 1 if py == 4 else py + 1
				if fy >= 0 and fy < h:
					img.set_pixel(px, fy, foam)

	img.set_pixel(39, 4, brass)
	img.set_pixel(39, 13, lantern)
	img.set_pixel(38, 13, brass)
	img.set_pixel(40, 13, lantern)

	var copy := img.duplicate() as Image
	for y in range(h):
		for x in range(w):
			if copy.get_pixel(x, y).a > 0.0:
				continue
			var has_solid := false
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + dir.x
				var ny: int = y + dir.y
				if nx >= 0 and nx < w and ny >= 0 and ny < h:
					if copy.get_pixel(nx, ny).a > 0.95:
						has_solid = true
						break
			if has_solid:
				img.set_pixel(x, y, OUTLINE_COLOR)

	return ImageTexture.create_from_image(img)


func _on_wind_changed(direction: Vector2, strength: float) -> void:
	set_wind(direction, strength)


func _on_world_initialized(world_seed: int, _islands_arr: Array) -> void:
	_forts.clear()
	setup(world_seed)


func _on_weather_changed(weather_state: int, intensity: float) -> void:
	set_weather(weather_state, intensity)


func _on_lightning_flash(world_pos: Vector2) -> void:
	trigger_lightning(world_pos)


func _on_fort_spawned(fort_id: int, world_pos: Vector2, island_index: int, max_hp: float) -> void:
	_forts[fort_id] = {
		"pos": world_pos,
		"island_index": island_index,
		"hp": max_hp,
		"max_hp": maxf(1.0, max_hp),
		"hit_flash": 0.0
	}


func _on_fort_damaged(fort_id: int, hp: float, max_hp: float, world_pos: Vector2) -> void:
	if not _forts.has(fort_id):
		_on_fort_spawned(fort_id, world_pos, -1, max_hp)
	var fort: Dictionary = _forts[fort_id]
	fort["hp"] = hp
	fort["max_hp"] = maxf(1.0, max_hp)
	fort["pos"] = world_pos
	fort["hit_flash"] = 0.14


func _on_fort_destroyed(fort_id: int, _world_pos: Vector2) -> void:
	_forts.erase(fort_id)

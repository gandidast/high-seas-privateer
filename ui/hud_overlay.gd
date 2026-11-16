class_name HudOverlay
extends Control
## Crisp 1280x720+ HD nautical HUD (rendered outside the 640x360 SubViewport):
## - Top-left: Ship class, gold, hull HP bar, 3-stage sail bar, Port/Starboard/Bow reload bars.
## - Top-center: Weather, Royal Navy wanted stars, active quest directional tracker, death countdown banner.
## - Top-right: Chart-style MinimapRenderer (click or [M] opens fullscreen WorldMapOverlay).
## - Bottom-center: Brass Compass & Windrose medallion with wind strength & heading readout.

const DEFAULT_VIEWPORT_W: float = 1280.0
const DEFAULT_VIEWPORT_H: float = 720.0
const COMPASS_RADIUS: float = 44.0
const PERIODIC_REFRESH_INTERVAL: float = 0.085 # ~11.8 Hz minimap/compass refresh
const ANIM_REFRESH_INTERVAL: float = 0.04      # ~25 Hz while reload/toast actively animates

var player_ship: Node = null
var world_map_ref: Node = null
var combat_system_ref: CombatSystem = null
var loot_system_ref: LootSystem = null
var all_ships_ref: Dictionary = {}

var wind_dir: Vector2 = Vector2(1.0, 0.25).normalized()
var wind_strength: float = 0.7
var _display_wind_angle: float = 0.0
var gold_amount: int = 120
var current_harbor_idx: int = -1
var current_harbor_name: String = ""
var active_quests: Array = []

var current_weather: int = Contracts.WeatherState.CLEAR
var wanted_level: int = 0
var _player_class_title: String = "Schaluppe"
var _tracked_forts: Dictionary = {}
var _tracked_sea_monster: Dictionary = {}

var _toast_text: String = ""
var _toast_timer: float = 0.0
var _pulse_time: float = 0.0

var _death_active: bool = false
var _death_gold_lost: int = 20
var _death_countdown: float = 0.0

var _minimap: MinimapRenderer = null
var _world_map: WorldMapOverlay = null
var _labels: HudLabelsView = HudLabelsView.new()
var _hud_dirty: bool = true
var _minimap_dirty: bool = true
var _periodic_accum: float = 0.0
var _anim_accum: float = 0.0
var _last_vp_size: Vector2 = Vector2.ZERO
var _last_player_ref: Node = null

var _last_hp: float = -1.0
var _last_max_hp: float = -1.0
var _last_sail_state: int = -1
var _last_port_ready: float = -1.0
var _last_sb_ready: float = -1.0
var _last_bow_ready: float = -1.0
var _last_heading_q: float = -999.0
var _last_wind_q: float = -999.0

var _arrow_poly: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _wind_vane_poly: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func _bus() -> Contracts:
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		return st.root.get_node_or_null("EventBus") as Contracts
	return null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_minimap = MinimapRenderer.new()
	_minimap.name = "MinimapRenderer"
	_minimap.world_map_toggle_requested.connect(toggle_world_map)
	add_child(_minimap)

	_labels.build(self)

	_world_map = WorldMapOverlay.new()
	_world_map.name = "WorldMapOverlay"
	add_child(_world_map)

	_sync_dynamic_layout()
	_connect_signals()
	_bake_maps_from_world()
	_mark_dirty(true, true)


func toggle_world_map() -> void:
	if _world_map != null:
		_world_map.toggle_map()


func set_world_map_open(open: bool) -> void:
	if _world_map != null:
		_world_map.set_open(open)


func is_world_map_open() -> bool:
	return _world_map != null and _world_map.visible


func setup(
	p_player_ship: Node,
	p_world_map: Node,
	p_combat_system: CombatSystem,
	p_loot_system: LootSystem,
	p_all_ships: Dictionary,
	p_starting_gold: int = 120
) -> void:
	player_ship = p_player_ship
	_last_player_ref = p_player_ship
	world_map_ref = p_world_map
	combat_system_ref = p_combat_system
	loot_system_ref = p_loot_system
	all_ships_ref = p_all_ships
	gold_amount = p_starting_gold
	_tracked_forts.clear()
	_tracked_sea_monster.clear()
	wanted_level = 0
	current_weather = Contracts.WeatherState.CLEAR
	_death_active = false
	_death_countdown = 0.0

	if world_map_ref != null:
		var wd: Variant = world_map_ref.get("wind_direction")
		var ws: Variant = world_map_ref.get("wind_strength")
		if wd is Vector2: wind_dir = wd
		if ws is float or ws is int: wind_strength = float(ws)
		var cw: Variant = world_map_ref.get("current_weather")
		if cw is int: current_weather = cw

	if combat_system_ref != null:
		for fid_var in combat_system_ref.forts.keys():
			var f: Dictionary = combat_system_ref.forts[fid_var]
			_tracked_forts[int(fid_var)] = {
				"pos": f.get("world_pos", Vector2.ZERO),
				"destroyed": bool(f.get("destroyed", false)),
				"island_index": int(f.get("island_index", -1))
			}

	_display_wind_angle = wind_dir.angle()
	_bake_maps_from_world()
	_sync_map_refs()
	_update_labels()
	_mark_dirty(true, true)


func set_ships_dict(p_ships: Dictionary) -> void:
	all_ships_ref = p_ships
	if _minimap != null:
		_minimap.all_ships_ref = p_ships
	if _world_map != null:
		_world_map.all_ships_ref = p_ships


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_dynamic_layout()
		_mark_dirty(true, true)


func _process(delta: float) -> void:
	_pulse_time += delta
	_periodic_accum += delta
	_anim_accum += delta

	if player_ship != _last_player_ref:
		_last_player_ref = player_ship
		_sync_map_refs()
		_mark_dirty(true, true)

	if _get_hud_size() != _last_vp_size:
		_sync_dynamic_layout()
		_mark_dirty(true, true)

	var is_sunk_now: bool = player_ship != null and bool(player_ship.get("is_sunk"))
	if is_sunk_now:
		if not _death_active:
			_death_active = true
			_death_gold_lost = 20
			_death_countdown = 10.0
			_hud_dirty = true
		else:
			var prev_sec: int = int(ceil(_death_countdown))
			_death_countdown = maxf(0.0, _death_countdown - delta)
			if int(ceil(_death_countdown)) != prev_sec:
				_hud_dirty = true
	elif _death_active:
		if player_ship != null:
			_death_active = false
			_death_countdown = 0.0
			_hud_dirty = true
		else:
			var prev_sec_null: int = int(ceil(_death_countdown))
			_death_countdown = maxf(0.0, _death_countdown - delta)
			if _death_countdown <= 0.0:
				_death_active = false
			if _death_active == false or int(ceil(_death_countdown)) != prev_sec_null:
				_hud_dirty = true

	var target_ang: float = wind_dir.angle()
	var wind_moving: bool = absf(angle_difference(_display_wind_angle, target_ang)) > 0.004
	if wind_moving:
		_display_wind_angle = lerp_angle(_display_wind_angle, target_ang, clampf(delta * 4.5, 0.0, 1.0))

	var toast_fading: bool = false
	if _toast_timer > 0.0:
		var prev_alpha: float = clampf(_toast_timer, 0.0, 1.0)
		_toast_timer = maxf(0.0, _toast_timer - delta)
		var new_alpha: float = clampf(_toast_timer, 0.0, 1.0)
		if _labels.lbl_toast != null:
			_labels.lbl_toast.visible = _toast_timer > 0.0
			_labels.lbl_toast.modulate.a = new_alpha
		toast_fading = (_toast_timer <= 0.0 or absf(new_alpha - prev_alpha) > 0.001)

	var reloads := _read_broadside_ready()
	var bow_ready: float = _read_bow_ready()
	var reloading: bool = (reloads.x < 0.999 or reloads.y < 0.999 or (bow_ready >= 0.0 and bow_ready < 0.999))
	var reload_changed: bool = absf(reloads.x - _last_port_ready) > 0.006 or absf(reloads.y - _last_sb_ready) > 0.006 or absf(bow_ready - _last_bow_ready) > 0.006
	if (reload_changed and _anim_accum >= ANIM_REFRESH_INTERVAL) or (reloading and reload_changed and (reloads.x >= 0.999 or reloads.y >= 0.999 or bow_ready >= 0.999)):
		_anim_accum = 0.0
		_hud_dirty = true
	if toast_fading and (_toast_timer <= 0.0 or _anim_accum >= ANIM_REFRESH_INTERVAL):
		_anim_accum = 0.0
		_hud_dirty = true

	if _periodic_accum >= PERIODIC_REFRESH_INTERVAL:
		_periodic_accum = 0.0
		_check_periodic_changes(wind_moving)

	if _hud_dirty:
		_hud_dirty = false
		_update_labels()
		queue_redraw()
	if _minimap_dirty:
		_minimap_dirty = false
		if _minimap != null:
			_minimap.pulse_time = _pulse_time
			_minimap.queue_redraw()
		if _world_map != null and _world_map.visible:
			_world_map.pulse_time = _pulse_time
			_world_map.queue_redraw()
	elif _world_map != null and _world_map.visible and _periodic_accum == 0.0:
		_world_map.pulse_time = _pulse_time
		_world_map.queue_redraw()


func _check_periodic_changes(wind_moving: bool) -> void:
	if wind_moving and absf(angle_difference(_display_wind_angle, _last_wind_q)) > 0.008:
		_last_wind_q = _display_wind_angle
		_hud_dirty = true

	if player_ship != null:
		var hp: float = float(player_ship.get("hp"))
		var max_hp: float = float(player_ship.get("max_hp"))
		var sail: int = int(player_ship.get("sail_state"))
		var heading: float = float(player_ship.get("heading"))
		if absf(hp - _last_hp) > 0.25 or absf(max_hp - _last_max_hp) > 0.25 or sail != _last_sail_state or absf(angle_difference(heading, _last_heading_q)) > 0.008 or not active_quests.is_empty():
			_hud_dirty = true
		if absf(float(player_ship.get("speed"))) > 1.0 or absf(angle_difference(heading, _last_heading_q)) > 0.01 or not all_ships_ref.is_empty() or not active_quests.is_empty() or bool(_tracked_sea_monster.get("active", false)):
			_minimap_dirty = true
	elif not all_ships_ref.is_empty() or bool(_tracked_sea_monster.get("active", false)):
		_minimap_dirty = true
	_update_labels()


func _mark_dirty(hud: bool = true, minimap: bool = false) -> void:
	if hud: _hud_dirty = true
	if minimap: _minimap_dirty = true


func _read_broadside_ready() -> Vector2:
	if player_ship == null or combat_system_ref == null:
		return Vector2.ZERO
	var sid: int = int(player_ship.get("ship_id"))
	return Vector2(
		float(combat_system_ref.get_broadside_cone(sid, false).get("ready_ratio", 0.0)),
		float(combat_system_ref.get_broadside_cone(sid, true).get("ready_ratio", 0.0))
	)


func _read_bow_ready() -> float:
	if player_ship == null:
		return -1.0
	var st: Variant = player_ship.get("stats")
	var has_bow: bool = (st is Contracts.ShipStats) and not (st as Contracts.ShipStats).bow_cannons.is_empty()
	if combat_system_ref != null and combat_system_ref.has_method("get_bow_cone"):
		var sid: int = int(player_ship.get("ship_id"))
		var bc: Dictionary = combat_system_ref.call("get_bow_cone", sid)
		if int(bc.get("total_count", 0)) > 0:
			return float(bc.get("ready_ratio", 0.0))
	return 1.0 if has_bow else -1.0


func _get_hud_size() -> Vector2:
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0: vp_size = size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0: return Vector2(DEFAULT_VIEWPORT_W, DEFAULT_VIEWPORT_H)
	return vp_size


func _get_top_bar_rect(vp_size: Vector2) -> Rect2:
	var right_limit: float = vp_size.x - MinimapRenderer.CARD_SIZE.x - 32.0
	var bar_w: float = minf(520.0, maxf(260.0, right_limit - 436.0))
	var bar_x: float = clampf(round(vp_size.x * 0.5 - bar_w * 0.5), 436.0, maxf(436.0, right_limit - bar_w))
	return Rect2(bar_x, 16.0, bar_w, 44.0)


func _get_compass_center(vp_size: Vector2) -> Vector2:
	return Vector2(round(vp_size.x * 0.5), vp_size.y - 68.0)


func _draw() -> void:
	var vp_size: Vector2 = _get_hud_size()
	_draw_ship_panel()
	UIThemeHelper.draw_chamfered_panel(self, _get_top_bar_rect(vp_size), UIThemeHelper.COL_HUD_PANEL_BG, UIThemeHelper.COL_BRASS, UIThemeHelper.COL_BRASS_DIM, 7.0)
	_draw_quest_arrow(vp_size)
	_draw_bottom_compass_and_windrose(vp_size)
	_draw_toast_and_harbor_bg(vp_size)


func _draw_ship_panel() -> void:
	var reloads := _read_broadside_ready()
	var bow_ready: float = _read_bow_ready()
	_last_port_ready = reloads.x; _last_sb_ready = reloads.y; _last_bow_ready = bow_ready

	var panel_h: float = 178.0 if bow_ready >= 0.0 else 156.0
	UIThemeHelper.draw_chamfered_panel(self, Rect2(16.0, 16.0, 404.0, panel_h), UIThemeHelper.COL_HUD_PANEL_BG, UIThemeHelper.COL_BRASS, UIThemeHelper.COL_BRASS_DIM, 8.0)
	var hp: float = float(player_ship.get("hp")) if player_ship != null else 0.0
	var max_hp: float = maxf(1.0, float(player_ship.get("max_hp"))) if player_ship != null else 120.0
	var sail_state: int = int(player_ship.get("sail_state")) if player_ship != null else Contracts.SailState.ANCHORED
	_last_hp = hp; _last_max_hp = max_hp; _last_sail_state = sail_state

	var hp_ratio: float = clampf(hp / max_hp, 0.0, 1.0)
	var hp_col: Color = Color(0.28, 0.80, 0.44) if hp_ratio > 0.35 else Color(0.92, 0.28, 0.26)
	UIThemeHelper.draw_progress_bar(self, Rect2(96.0, 54.0, 212.0, 16.0), hp_ratio, hp_col, Color(0.14, 0.08, 0.09, 0.95), Color(0.36, 0.30, 0.24, 0.90), 3.0)

	for i in range(3):
		var sr := Rect2(240.0 + float(i) * 56.0, 84.0, 50.0, 16.0)
		var seg_col: Color = Color(0.14, 0.13, 0.19, 0.95)
		var seg_border: Color = Color(0.32, 0.28, 0.24, 0.80)
		if i <= sail_state:
			if sail_state == Contracts.SailState.ANCHORED: seg_col = Color(0.56, 0.46, 0.28, 0.95); seg_border = UIThemeHelper.COL_BRASS
			elif sail_state == Contracts.SailState.HALF_SAIL: seg_col = Color(0.26, 0.68, 0.76, 0.95); seg_border = UIThemeHelper.COL_TURQUOISE
			else: seg_col = Color(0.88, 0.68, 0.22, 0.95); seg_border = UIThemeHelper.COL_GOLD
		draw_rect(sr, seg_col, true)
		draw_rect(sr, seg_border, false, 1.5)

	UIThemeHelper.draw_progress_bar(self, Rect2(30.0, 140.0, 182.0, 14.0), reloads.x, UIThemeHelper.COL_GOLD if reloads.x >= 0.99 else Color(0.34, 0.64, 0.84), Color(0.11, 0.11, 0.16, 0.95), UIThemeHelper.COL_GOLD if reloads.x >= 0.99 else Color(0.34, 0.30, 0.25), 2.0)
	UIThemeHelper.draw_progress_bar(self, Rect2(224.0, 140.0, 182.0, 14.0), reloads.y, UIThemeHelper.COL_GOLD if reloads.y >= 0.99 else Color(0.84, 0.44, 0.30), Color(0.11, 0.11, 0.16, 0.95), UIThemeHelper.COL_GOLD if reloads.y >= 0.99 else Color(0.34, 0.30, 0.25), 2.0)

	if bow_ready >= 0.0:
		UIThemeHelper.draw_progress_bar(self, Rect2(260.0, 165.0, 146.0, 14.0), bow_ready, UIThemeHelper.COL_GOLD if bow_ready >= 0.99 else Color(0.82, 0.62, 0.24), Color(0.11, 0.11, 0.16, 0.95), UIThemeHelper.COL_GOLD if bow_ready >= 0.99 else Color(0.34, 0.30, 0.25), 2.0)


func _draw_quest_arrow(vp_size: Vector2) -> void:
	if active_quests.is_empty() or player_ship == null:
		return
	var to_target: Vector2 = _resolve_quest_target_pos(active_quests[0]) - player_ship.get("world_pos")
	var dir: Vector2 = to_target.normalized() if to_target.length_squared() > 1.0 else Vector2.RIGHT
	var top_bar := _get_top_bar_rect(vp_size)
	var q_box := Rect2(top_bar.position.x, 68.0, top_bar.size.x, 46.0)
	UIThemeHelper.draw_chamfered_panel(self, q_box, UIThemeHelper.COL_HUD_PANEL_BG, UIThemeHelper.COL_BRASS, UIThemeHelper.COL_BRASS_DIM, 7.0)

	var arrow_c := Vector2(q_box.position.x + 28.0, q_box.position.y + 23.0)
	draw_circle(arrow_c, 14.0, UIThemeHelper.COL_HUD_INSET)
	draw_arc(arrow_c, 14.0, 0.0, TAU, 24, UIThemeHelper.COL_BRASS_DIM, 1.5)
	var tip: Vector2 = arrow_c + dir * 11.0
	var perp: Vector2 = dir.rotated(PI * 0.5) * 5.5
	draw_line(arrow_c - dir * 8.0, tip, UIThemeHelper.COL_GOLD, 2.5)
	_arrow_poly[0] = tip; _arrow_poly[1] = tip - dir * 8.0 + perp; _arrow_poly[2] = tip - dir * 8.0 - perp
	draw_colored_polygon(_arrow_poly, Color(1.0, 0.94, 0.65))


func _draw_bottom_compass_and_windrose(vp_size: Vector2) -> void:
	var cc := _get_compass_center(vp_size)
	var wing_rect := Rect2(cc.x - 196.0, cc.y - 34.0, 392.0, 68.0)
	UIThemeHelper.draw_chamfered_panel(self, wing_rect, UIThemeHelper.COL_HUD_PANEL_BG, UIThemeHelper.COL_BRASS, UIThemeHelper.COL_BRASS_DIM, 8.0)
	UIThemeHelper.draw_progress_bar(self, Rect2(wing_rect.position.x + 70.0, wing_rect.position.y + 39.0, 72.0, 10.0), wind_strength, UIThemeHelper.COL_TURQUOISE, UIThemeHelper.COL_HUD_INSET, UIThemeHelper.COL_BRASS_DIM, 0.0)

	draw_circle(cc, COMPASS_RADIUS + 5.0, Color(0.09, 0.08, 0.13, 0.98))
	draw_arc(cc, COMPASS_RADIUS + 5.0, 0.0, TAU, 48, UIThemeHelper.COL_BRASS, 2.0, true)
	draw_arc(cc, COMPASS_RADIUS, 0.0, TAU, 40, UIThemeHelper.COL_BRASS_DIM, 1.5, true)
	for i in range(8):
		var dir_v := Vector2.from_angle(float(i) * PI * 0.25)
		draw_line(cc + dir_v * (COMPASS_RADIUS - (9.0 if i % 2 == 0 else 5.0)), cc + dir_v * COMPASS_RADIUS, UIThemeHelper.COL_BRASS if i % 2 == 0 else UIThemeHelper.COL_BRASS_DIM, 1.5)

	var wind_vec := Vector2.from_angle(_display_wind_angle)
	var wind_tip: Vector2 = cc + wind_vec * (COMPASS_RADIUS - 10.0)
	var wind_perp: Vector2 = wind_vec.rotated(PI * 0.5) * 6.5
	draw_line(cc - wind_vec * 13.0, wind_tip, UIThemeHelper.COL_TURQUOISE, 3.0)
	_wind_vane_poly[0] = wind_tip; _wind_vane_poly[1] = wind_tip - wind_vec * 10.0 + wind_perp; _wind_vane_poly[2] = wind_tip - wind_vec * 10.0 - wind_perp
	draw_colored_polygon(_wind_vane_poly, Color(0.78, 0.98, 1.0))

	if player_ship != null:
		var heading: float = float(player_ship.get("heading"))
		_last_heading_q = heading
		var h_tip: Vector2 = cc + Vector2.from_angle(heading) * 24.0
		draw_line(cc, h_tip, UIThemeHelper.COL_GOLD, 3.0)
		draw_circle(h_tip, 3.0, Color(1.0, 0.95, 0.72))

	draw_circle(cc, 4.5, UIThemeHelper.COL_BRASS)
	draw_circle(cc, 2.0, UIThemeHelper.COL_IVORY)


func _draw_toast_and_harbor_bg(vp_size: Vector2) -> void:
	if _death_active:
		var death_w: float = minf(620.0, vp_size.x - 40.0)
		UIThemeHelper.draw_chamfered_panel(
			self,
			Rect2(round(vp_size.x * 0.5 - death_w * 0.5), 132.0, death_w, 50.0),
			Color(0.24, 0.06, 0.08, 0.95),
			Color(0.96, 0.36, 0.30, 0.98),
			UIThemeHelper.COL_GOLD,
			8.0
		)
	if _toast_timer > 0.0 and not _toast_text.is_empty():
		var alpha: float = clampf(_toast_timer, 0.0, 1.0)
		var box_w: float = minf(620.0, vp_size.x - 40.0)
		UIThemeHelper.draw_chamfered_panel(
			self,
			Rect2(round(vp_size.x * 0.5 - box_w * 0.5), vp_size.y - 220.0, box_w, 40.0),
			Color(UIThemeHelper.COL_HUD_PANEL_BG.r, UIThemeHelper.COL_HUD_PANEL_BG.g, UIThemeHelper.COL_HUD_PANEL_BG.b, 0.92 * alpha),
			Color(UIThemeHelper.COL_BRASS.r, UIThemeHelper.COL_BRASS.g, UIThemeHelper.COL_BRASS.b, alpha),
			Color(UIThemeHelper.COL_BRASS_DIM.r, UIThemeHelper.COL_BRASS_DIM.g, UIThemeHelper.COL_BRASS_DIM.b, 0.7 * alpha),
			7.0
		)
	if current_harbor_idx >= 0:
		var h_w: float = minf(600.0, vp_size.x - 40.0)
		UIThemeHelper.draw_chamfered_panel(self, Rect2(round(vp_size.x * 0.5 - h_w * 0.5), vp_size.y - 170.0, h_w, 44.0), Color(0.13, 0.10, 0.11, 0.94), UIThemeHelper.COL_GOLD, UIThemeHelper.COL_BRASS_DIM, 7.0)


func _sync_dynamic_layout() -> void:
	var vp_size: Vector2 = _get_hud_size()
	_last_vp_size = vp_size
	if _minimap != null:
		_minimap.position = Vector2(vp_size.x - MinimapRenderer.CARD_SIZE.x - 16.0, 16.0).round()
	_labels.sync_layout(vp_size, _get_top_bar_rect(vp_size), _get_compass_center(vp_size), COMPASS_RADIUS)


func _update_labels() -> void:
	var q_pos: Vector2 = _resolve_quest_target_pos(active_quests[0]) if not active_quests.is_empty() else Vector2.ZERO
	_player_class_title = _labels.update(
		player_ship,
		_read_broadside_ready(),
		wind_strength,
		gold_amount,
		current_weather,
		wanted_level,
		active_quests,
		q_pos,
		current_harbor_idx,
		current_harbor_name,
		_read_bow_ready(),
		_death_active,
		_death_gold_lost,
		_death_countdown
	)


func _resolve_quest_target_pos(q: Contracts.QuestData) -> Vector2:
	if q.quest_type == Contracts.QuestType.BOUNTY and q.target_ship_id != -1 and all_ships_ref.has(q.target_ship_id):
		var boss: Node = all_ships_ref[q.target_ship_id]
		if boss != null and not bool(boss.get("is_sunk")):
			return boss.get("world_pos")
	return q.target_pos


func _get_islands() -> Array:
	if world_map_ref != null:
		var arr: Variant = world_map_ref.get("islands")
		if arr is Array and not arr.is_empty(): return arr
	return Contracts.get_islands()


func _bake_maps_from_world() -> void:
	var seed_val: int = int(world_map_ref.get("world_seed")) if (world_map_ref != null and world_map_ref.get("world_seed") != null) else Contracts.DEFAULT_WORLD_SEED
	var isls: Array = _get_islands()
	if _minimap != null:
		_minimap.bake_static_map(seed_val, isls)
	if _world_map != null:
		_world_map.bake_static_map(seed_val, isls)


func _sync_map_refs() -> void:
	if _minimap != null:
		_minimap.player_ship = player_ship; _minimap.combat_system_ref = combat_system_ref
		_minimap.loot_system_ref = loot_system_ref; _minimap.all_ships_ref = all_ships_ref
		_minimap.tracked_forts = _tracked_forts; _minimap.tracked_sea_monster = _tracked_sea_monster
		_minimap.active_quests = active_quests
	if _world_map != null:
		_world_map.player_ship = player_ship; _world_map.combat_system_ref = combat_system_ref
		_world_map.loot_system_ref = loot_system_ref; _world_map.all_ships_ref = all_ships_ref
		_world_map.tracked_forts = _tracked_forts; _world_map.tracked_sea_monster = _tracked_sea_monster
		_world_map.active_quests = active_quests
		_world_map.islands_ref = _get_islands()


func _connect_signals() -> void:
	var bus := _bus()
	if bus == null: return
	bus.world_initialized.connect(func(ws: int, isls: Array) -> void:
		if _minimap != null: _minimap.bake_static_map(ws, isls)
		if _world_map != null: _world_map.bake_static_map(ws, isls)
		_mark_dirty(true, true))
	bus.wind_changed.connect(func(dir: Vector2, st: float) -> void: wind_dir = dir.normalized(); wind_strength = st; _mark_dirty(true, false))
	bus.gold_changed.connect(func(ng: int, _d: int) -> void: gold_amount = ng; _mark_dirty(true, false))
	bus.harbor_entered.connect(func(sid: int, idx: int, nm: String) -> void:
		if player_ship != null and sid == int(player_ship.get("ship_id")): current_harbor_idx = idx; current_harbor_name = nm; _mark_dirty(true, false))
	bus.harbor_exited.connect(func(sid: int, _idx: int) -> void:
		if player_ship != null and sid == int(player_ship.get("ship_id")): current_harbor_idx = -1; current_harbor_name = ""; _mark_dirty(true, false))
	bus.quest_list_updated.connect(func(qs: Array) -> void:
		active_quests = qs.duplicate()
		if _minimap != null: _minimap.active_quests = active_quests
		if _world_map != null: _world_map.active_quests = active_quests
		_mark_dirty(true, true))
	bus.quest_accepted.connect(func(q: Contracts.QuestData) -> void:
		if q != null and not active_quests.has(q): active_quests.append(q)
		if _minimap != null: _minimap.active_quests = active_quests
		if _world_map != null: _world_map.active_quests = active_quests
		_mark_dirty(true, true))
	bus.quest_completed.connect(func(q: Contracts.QuestData) -> void:
		if q == null: return
		for i in range(active_quests.size() - 1, -1, -1):
			if active_quests[i].id == q.id: active_quests.remove_at(i)
		if _minimap != null: _minimap.active_quests = active_quests
		if _world_map != null: _world_map.active_quests = active_quests
		_mark_dirty(true, true))
	bus.notification_posted.connect(func(msg: String, _cat: String) -> void:
		_toast_text = msg; _toast_timer = 3.2
		if _labels.lbl_toast != null: _labels.lbl_toast.text = msg; _labels.lbl_toast.visible = true; _labels.lbl_toast.modulate.a = 1.0
		_mark_dirty(true, false))
	bus.weather_changed.connect(func(ws: int, _i: float) -> void: current_weather = ws; _mark_dirty(true, false))
	bus.wanted_level_changed.connect(func(nl: int) -> void: wanted_level = nl; _mark_dirty(true, false))
	bus.ship_class_upgraded.connect(func(sid: int, _t: int, ct: String) -> void:
		if player_ship != null and sid == int(player_ship.get("ship_id")): _player_class_title = ct; _mark_dirty(true, false))
	bus.player_death_penalty.connect(func(sid: int, gold_lost: int, respawn_sec: float) -> void:
		if player_ship == null or sid == int(player_ship.get("ship_id")):
			_death_active = true
			_death_gold_lost = gold_lost
			_death_countdown = maxf(0.0, respawn_sec)
			_mark_dirty(true, false))
	bus.broadside_fired.connect(func(sid: int, _sb: bool, _o: Vector2, _d: Vector2, _c: Array) -> void:
		if player_ship != null and sid == int(player_ship.get("ship_id")): _mark_dirty(true, false))
	bus.ship_repaired.connect(func(sid: int, _nhp: float, _mhp: float, _c: int) -> void:
		if player_ship != null and sid == int(player_ship.get("ship_id")): _mark_dirty(true, false))
	bus.ship_damaged.connect(func(sid: int, _dmg: float, _nhp: float, _mhp: float, _wp: Vector2) -> void:
		if player_ship != null and sid == int(player_ship.get("ship_id")): _mark_dirty(true, false))
	bus.loot_spawned.connect(func(_ld: Contracts.LootDropData) -> void: _mark_dirty(false, true))
	bus.loot_collected.connect(func(_did: int, _csid: int, _ld: Contracts.LootDropData) -> void: _mark_dirty(false, true))
	bus.ship_spawned.connect(func(_sid: int, _sd: Dictionary) -> void: _mark_dirty(false, true))
	bus.ship_despawned.connect(func(_sid: int) -> void: _mark_dirty(false, true))
	bus.fort_spawned.connect(func(fid: int, wp: Vector2, ii: int, _mhp: float) -> void:
		_tracked_forts[fid] = { "pos": wp, "destroyed": false, "island_index": ii }
		_mark_dirty(false, true))
	bus.fort_destroyed.connect(func(fid: int, wp: Vector2) -> void:
		var prev_ii: int = int(_tracked_forts.get(fid, {}).get("island_index", -1))
		_tracked_forts[fid] = { "pos": wp, "destroyed": true, "island_index": prev_ii }
		_mark_dirty(false, true))
	bus.sea_monster_spawned.connect(func(mid: int, wp: Vector2, mhp: float) -> void:
		_tracked_sea_monster = { "monster_id": mid, "pos": wp, "hp": mhp, "max_hp": mhp, "active": true }
		if _minimap != null: _minimap.tracked_sea_monster = _tracked_sea_monster
		if _world_map != null: _world_map.tracked_sea_monster = _tracked_sea_monster
		_mark_dirty(false, true))
	bus.sea_monster_updated.connect(func(mid: int, wp: Vector2, hp: float, mhp: float, _ph: int) -> void:
		_tracked_sea_monster = { "monster_id": mid, "pos": wp, "hp": hp, "max_hp": mhp, "active": hp > 0.0 }
		if _minimap != null: _minimap.tracked_sea_monster = _tracked_sea_monster
		if _world_map != null: _world_map.tracked_sea_monster = _tracked_sea_monster
		_mark_dirty(false, true))
	bus.sea_monster_defeated.connect(func(_mid: int, _wp: Vector2) -> void:
		_tracked_sea_monster["active"] = false
		_mark_dirty(false, true))

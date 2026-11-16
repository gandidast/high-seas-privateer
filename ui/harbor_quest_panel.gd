class_name HarborQuestPanel
extends RefCounted
## Modular Harbor Quest generator & card builder helper for HarborUI.

const CAPTAINS: Array[String] = [
	"Korsar Vane", "Rotbart Morgan", "Schwarze Anne", "Eisenkiefer Flint", "Käpt'n Blutsturm"
]

var _quest_card_style: StyleBoxFlat = null


func _init() -> void:
	_quest_card_style = UIThemeHelper.make_box_style(
		UIThemeHelper.COL_PANEL_CARD_INNER, UIThemeHelper.COL_BRASS_DIM, 6, 1, 10
	)


func generate_harbor_quests(island_idx: int, harbor_quests: Dictionary, rng: RandomNumberGenerator, islands: Array, find_water_cb: Callable) -> void:
	harbor_quests[island_idx] = [
		make_quest_of_type(island_idx, Contracts.QuestType.BOUNTY, rng, islands, find_water_cb),
		make_quest_of_type(island_idx, Contracts.QuestType.DELIVERY, rng, islands, find_water_cb),
		make_quest_of_type(island_idx, Contracts.QuestType.SALVAGE, rng, islands, find_water_cb)
	]


func replace_completed_harbor_quest(island_idx: int, q_type: int, harbor_quests: Dictionary, rng: RandomNumberGenerator, islands: Array, find_water_cb: Callable) -> void:
	if not harbor_quests.has(island_idx):
		return
	var list: Array = harbor_quests[island_idx]
	for i in range(list.size()):
		var q: Contracts.QuestData = list[i]
		if q.quest_type == q_type and q.completed:
			list[i] = make_quest_of_type(island_idx, q_type, rng, islands, find_water_cb)
			return


func make_quest_of_type(island_idx: int, q_type: int, rng: RandomNumberGenerator, islands: Array, find_water_cb: Callable) -> Contracts.QuestData:
	var q := Contracts.QuestData.new()
	q.id = "q_%d_%d_%d" % [island_idx, q_type, rng.randi_range(1000, 99999)]
	q.quest_type = q_type
	q.source_island_idx = island_idx
	var src_isl: Contracts.IslandData = islands[clampi(island_idx, 0, islands.size() - 1)]

	match q_type:
		Contracts.QuestType.BOUNTY:
			var cap_name: String = CAPTAINS[rng.randi_range(0, CAPTAINS.size() - 1)]
			var spawn_dir := Vector2.from_angle(rng.randf_range(-PI, PI))
			q.title = "Jagd auf %s" % cap_name
			q.description = "Versenke die gefürchtete Piraten-Brigg '%s' vor %s." % [cap_name, src_isl.name]
			q.target_pos = find_water_cb.call(src_isl.harbor_pos + spawn_dir * rng.randf_range(360.0, 560.0))
			q.reward_gold = rng.randi_range(160, 240)
			q.cargo_item_id = cap_name
		Contracts.QuestType.DELIVERY:
			var target_idx: int = (island_idx + rng.randi_range(1, maxi(1, islands.size() - 1))) % islands.size()
			var dst_isl: Contracts.IslandData = islands[target_idx]
			q.target_island_idx = target_idx
			q.target_pos = dst_isl.harbor_pos
			q.cargo_item_id = "spice_crates_1x2"
			q.title = "Eilfracht nach %s" % dst_isl.name
			q.description = "Liefere versiegelte Gewürzkisten sicher in den Hafen von %s." % dst_isl.name
			q.reward_gold = rng.randi_range(115, 175)
		Contracts.QuestType.SALVAGE:
			var angle: float = rng.randf_range(-PI, PI)
			var wreck_pos: Vector2 = find_water_cb.call(Vector2(cos(angle), sin(angle)) * rng.randf_range(260.0, 640.0))
			q.target_pos = wreck_pos
			q.title = "Versunkenes Wrack bergen"
			q.description = "Berge die verlorene Schatztruhe bei den Wrack-Koordinaten (%d, %d)." % [int(wreck_pos.x), int(wreck_pos.y)]
			q.reward_gold = rng.randi_range(130, 195)
	return q


func refresh_quest_list(
	quest_list: VBoxContainer,
	offered: Array,
	current_island_index: int,
	is_active_cb: Callable,
	on_accept_cb: Callable,
	on_complete_cb: Callable
) -> void:
	if quest_list == null:
		return
	for child in quest_list.get_children():
		child.queue_free()
	for q_var in offered:
		var q: Contracts.QuestData = q_var
		if q != null:
			quest_list.add_child(_create_quest_card(q, current_island_index, is_active_cb, on_accept_cb, on_complete_cb))


func _create_quest_card(
	q: Contracts.QuestData,
	current_island_index: int,
	is_active_cb: Callable,
	on_accept_cb: Callable,
	on_complete_cb: Callable
) -> PanelContainer:
	var accent: Color = Color(0.94, 0.46, 0.42)
	var type_tag: String = "KOPFGELD"
	if q.quest_type == Contracts.QuestType.DELIVERY:
		type_tag = "LIEFERUNG"
		accent = UIThemeHelper.COL_TURQUOISE
	elif q.quest_type == Contracts.QuestType.SALVAGE:
		type_tag = "BERGUNG"
		accent = UIThemeHelper.COL_GOLD

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _quest_card_style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vbox.add_child(top)
	top.add_child(UIThemeHelper.make_label("[%s]" % type_tag, 14, accent))
	var title_lbl := UIThemeHelper.make_label(q.title, 16, UIThemeHelper.COL_IVORY)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(title_lbl)
	top.add_child(UIThemeHelper.make_label("+%d G" % q.reward_gold, 16, UIThemeHelper.COL_GOLD))

	var desc_lbl := UIThemeHelper.make_label(q.description, 14, UIThemeHelper.COL_MUTED)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	if bool(is_active_cb.call(q.id)):
		if q.quest_type == Contracts.QuestType.DELIVERY and q.target_island_idx == current_island_index:
			var turn_in_btn := UIThemeHelper.make_button("Lieferung abgeben (+%d G)" % q.reward_gold, Color(0.18, 0.42, 0.24), 15)
			turn_in_btn.pressed.connect(on_complete_cb.bind(q.id))
			btn_row.add_child(turn_in_btn)
		else:
			btn_row.add_child(UIThemeHelper.make_label("Auftrag aktiv (siehe Kompass-HUD)", 14, Color(0.50, 0.90, 0.56)))
	else:
		var accept_btn := UIThemeHelper.make_button("Auftrag annehmen", Color(0.20, 0.32, 0.46), 15)
		accept_btn.pressed.connect(on_accept_cb.bind(q))
		btn_row.add_child(accept_btn)
	return card

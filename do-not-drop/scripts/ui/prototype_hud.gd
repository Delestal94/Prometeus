extends "res://scripts/ui/hud/hud_pause.gd"
## Lightweight prototype UI: no gameplay decisions or direct physics references.


func _ready() -> void:
	var level: Node = get_parent()
	_is_endless = level != null and &"distance_traveled" in level
	_local_merit_total = int(CrewProgression.merit.get(NetworkManager.local_id(), 0))
	_build_ui()
	EventBus.vehicle_telemetry.connect(_on_speed)
	EventBus.package_integrity_changed.connect(_on_integrity)
	EventBus.package_state_changed.connect(_on_package_state)
	EventBus.package_damaged.connect(_on_damage)
	EventBus.route_progress_changed.connect(_on_progress)
	EventBus.delivery_status_changed.connect(_on_delivery)
	EventBus.run_started.connect(_on_started)
	EventBus.run_ended.connect(_on_ended)
	EventBus.interaction_prompt_changed.connect(_on_interaction_prompt)
	EventBus.carry_changed.connect(_on_carry_changed)
	EventBus.package_lid_hint_changed.connect(_on_lid_hint_changed)
	EventBus.cargo_registered.connect(_on_cargo_registered)
	EventBus.package_hint_changed.connect(_on_package_hint)
	EventBus.ping_sent.connect(_on_ping)
	EventBus.quick_fade_requested.connect(_on_quick_fade_requested)
	EventBus.team_money_changed.connect(_on_team_money_changed)
	EventBus.merit_changed.connect(_on_merit_changed)
	EventBus.card_changed.connect(_on_card_changed)
	EventBus.route_event_started.connect(_on_route_event_started)
	EventBus.route_event_updated.connect(_on_route_event_updated)
	EventBus.route_event_resolved.connect(_on_route_event_resolved)
	EventBus.unlock_earned.connect(_on_unlock_earned)
	EventBus.depot_orders_posted.connect(func(orders: Array) -> void: _orders = orders)
	EventBus.depot_station_opened.connect(_on_depot_station_opened)
	EventBus.depot_notice.connect(_toast)
	var truck_view: Node = get_tree().get_first_node_in_group(&"vehicle")
	if truck_view != null:
		var spectator: Node = truck_view.find_child("SpectatorCamera", true, false)
		if spectator != null:
			spectator.connect(&"availability_changed", func(available: bool) -> void:
				if available:
					_toast("Tu caja ya no tiene arreglo  ·  %s: ver desde afuera" % _key("Tab", "Back")))
	EventBus.house_refused_package.connect(func(house_index: int, expected: String) -> void:
		_toast("Casa %d: \"Ese no es mío, pedí %s\"" % [house_index + 1, expected.to_lower()]))
	NetworkManager.roster_changed.connect(_on_roster_changed)
	NetworkManager.session_failed.connect(_on_connection_lost)
	GameSettings.input_device_changed.connect(_on_input_device_changed)
	GameSettings.hud_scale_changed.connect(func(_scale: float) -> void: _apply_hud_scale())
	root.resized.connect(_apply_hud_scale)
	_apply_hud_scale()
	_refresh_session()
	_refresh_shortcut_text()
	_refresh_card()
	_show_start()


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(root)
	add_child(root)
	risk_vignette = ColorRect.new()
	risk_vignette.color = Color(0.62, 0.05, 0.04, 0.0)
	risk_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	risk_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	risk_vignette.material = _vignette_material()
	root.add_child(risk_vignette)
	hud_layer = Control.new()
	hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_layer)
	var margin := MarginContainer.new()
	hud_layer.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard = VBoxContainer.new()
	margin.add_child(dashboard)
	dashboard.add_theme_constant_override("separation", 12)
	dashboard.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# --- Top: who's playing (left), the van's numbers (right) ---
	var top := HBoxContainer.new()
	dashboard.add_child(top)
	top.add_theme_constant_override("separation", 16)
	# This corner used to be a permanent "DO NOT DROP / PRUEBA DE RUTA / 01"
	# logo. It says who's in the session now -- and, hosting over LAN, the
	# IP friends need, which the menu only ever showed for the single frame
	# before loading the level.
	var brand := _panel(top, Vector2.ZERO)
	brand.get_parent().size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	brand.add_theme_constant_override("separation", 6)
	UiTheme.title(brand, "TAKE MY PACKAGE", 22)
	session_label = UiTheme.tag(brand, "", MINT, -1.5, 14)
	var stretch := Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(stretch)
	var metrics := _panel(top, Vector2(210, 0))
	metrics.get_parent().size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	metrics.add_theme_constant_override("separation", 6)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	metrics.add_child(speed_row)
	speed_label = UiTheme.title(speed_row, "00", 50)
	speed_unit_label = UiTheme.label(speed_row, "km/h", 16, MUTED)
	speed_unit_label.size_flags_vertical = Control.SIZE_SHRINK_END
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	metrics.add_child(chips)
	time_label = UiTheme.chip(chips, "00:00", UiTheme.SKY, 17)
	economy_label = UiTheme.chip(chips, "$%d" % CrewProgression.team_money, YELLOW, 17)
	card_label = _rich(metrics, 14)
	card_label.custom_minimum_size.x = 190
	card_label.add_theme_color_override("default_color", INK)

	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard.add_child(space)

	# --- Bottom: the cargo (left), the objective (right) ---
	var bottom := HBoxContainer.new()
	dashboard.add_child(bottom)
	bottom.add_theme_constant_override("separation", 16)
	var cargo := _panel(bottom, Vector2(330, 0))
	cargo.get_parent().size_flags_vertical = Control.SIZE_SHRINK_END
	UiTheme.tag(cargo, "CARGA", UiTheme.CARDBOARD, -2.0, 15)
	cargo_rows_box = VBoxContainer.new()
	cargo_rows_box.add_theme_constant_override("separation", 10)
	cargo.add_child(cargo_rows_box)
	cargo_hint_label = _label(cargo, "", 15, MUTED)
	cargo_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cargo_hint_label.custom_minimum_size.x = 285
	var delivery := _panel(bottom, Vector2.ZERO)
	delivery.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delivery.get_parent().size_flags_vertical = Control.SIZE_SHRINK_END
	delivery.add_theme_constant_override("separation", 8)
	section_label = UiTheme.tag(delivery, "PREPARACIÓN", MINT, -1.5, 15)
	# Used to open on "220 m hasta la entrega", a leftover from the fixed
	# route: the real one is random and runs closer to 2000 m.
	distance_label = UiTheme.title(delivery, "", 30)
	route_bar = UiTheme.bar(delivery, MINT, 16)
	route_bar.visible = not _is_endless
	hint_label = _rich(delivery, 16)

	var shortcut_pill := PanelContainer.new()
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Color(INK, 0.82)
	pill_style.set_corner_radius_all(99)
	pill_style.content_margin_left = 18
	pill_style.content_margin_right = 18
	pill_style.content_margin_top = 5
	pill_style.content_margin_bottom = 6
	shortcut_pill.add_theme_stylebox_override("panel", pill_style)
	shortcut_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shortcut_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard.add_child(shortcut_pill)
	shortcut_label = _rich(shortcut_pill, 15)
	shortcut_label.add_theme_color_override("default_color", PAPER)
	shortcut_label.fit_content = true
	shortcut_label.autowrap_mode = TextServer.AUTOWRAP_OFF

	ping_label = UiTheme.floating_label(hud_layer, "", 26, YELLOW, 560, 20)
	ping_indicator = UiTheme.floating_label(hud_layer, "", 34, YELLOW, 260, 0)
	ping_indicator.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ping_indicator.offset_left = -130
	ping_indicator.offset_right = 130
	ping_indicator.offset_top = -190
	ping_indicator.offset_bottom = -145
	toast_label = UiTheme.floating_label(hud_layer, "", 21, MINT, 560, 64)
	event_label = UiTheme.floating_label(hud_layer, "", 23, YELLOW, 760, 104)
	interaction_label = UiTheme.floating_label(hud_layer, "", 25, PAPER, 560, 0)
	# Just under the crosshair, where the eye already is when reaching for
	# something -- not with the banners along the top.
	interaction_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	interaction_label.offset_left = -280
	interaction_label.offset_right = 280
	interaction_label.offset_top = 45
	interaction_label.offset_bottom = 95

	overlay = ColorRect.new()
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(UiTheme.BACKDROP, 0.72)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card = _panel(center, Vector2(640, 0))
	card.add_theme_constant_override("separation", 14)
	overlay_kicker = UiTheme.tag(card, "", YELLOW, -2.0, 16)
	overlay_title = UiTheme.title(card, "¡A REPARTIR!", 62)
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 14)
	card.add_child(hero)
	score_label = UiTheme.chip(hero, "", YELLOW, 40)
	record_label = UiTheme.tag(hero, "¡NUEVO RÉCORD!", UiTheme.GRAPE, 4.0, 20)
	record_label.add_theme_color_override("font_color", UiTheme.WHITE)
	record_label.get_parent().size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_set_hero(false)
	overlay_body = _label(card, "", 21, INK)
	overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_body.custom_minimum_size.x = 575
	overlay_stats = _label(card, "", 17, MUTED)
	overlay_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_stats.custom_minimum_size.x = 575
	# What the residents had to say, and the photos that answer them. Both
	# stay hidden unless the run actually produced any.
	complaints_label = _label(card, "", 17, STATE_TEXT[1])
	complaints_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	complaints_label.custom_minimum_size.x = 575
	complaints_label.visible = false
	photo_strip = HBoxContainer.new()
	photo_strip.add_theme_constant_override("separation", 14)
	photo_strip.visible = false
	card.add_child(photo_strip)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	card.add_child(actions)
	action_button = _button(actions, "Empezar entrega", true)
	action_button.pressed.connect(_primary_action)
	second_button = _button(actions, "Reiniciar", false)
	second_button.pressed.connect(_request_restart)
	# Pausing was a dead end: continue or restart, with no way to reach the
	# options or leave the level at all
	# (docs/critica-diseno-abogado-del-diablo.md section 4).
	options_button = _button(actions, "Opciones", false)
	options_button.pressed.connect(_open_options)
	menu_button = _button(actions, "Menú", false)
	menu_button.pressed.connect(_leave_to_menu)

	options_panel = OptionsPanel.new()
	options_panel.name = "OptionsPanel"
	root.add_child(options_panel)
	depot_panel = DepotPanel.new()
	depot_panel.name = "DepotPanel"
	root.add_child(depot_panel)
	# Back to the button that opened it: otherwise a gamepad player comes
	# back from the options with nothing focused and no way to move.
	options_panel.closed.connect(func() -> void:
		_refresh_card()
		if overlay.visible:
			options_button.grab_focus())

	# Added last so it paints over everything else, including the pause/
	# results overlay above -- a quick black flash to soften a hard camera
	# cut (boarding a seat) or a scene reload (restarting), not a UI panel.
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(fade_rect)


func _process(delta: float) -> void:
	time_label.text = "%02d:%02d" % [int(RunManager.elapsed_seconds) / 60, int(RunManager.elapsed_seconds) % 60]
	_refresh_role()
	_refresh_hint(delta)
	_refresh_shortcuts()
	_refresh_restart_hold(delta)
	_refresh_risk_vignette(delta)
	if overlay_mode == "pause" and not _soft_pause and not get_tree().paused:
		overlay.hide()
		overlay_mode = "run" if RunManager.is_running else "preparation"
	# A panel with buttons keeps the cursor free, even if something captured
	# it after the panel opened (the local player spawns after the start
	# screen shows, and its _ready() grabs the mouse for looking around).
	if overlay.visible and overlay_mode in ["start", "pause", "results", "disconnected"] 			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_cargo_hint()
	if overlay_mode == "preparation" and not RunManager.is_running:
		_prep_refresh -= delta
		if _prep_refresh <= 0.0:
			_prep_refresh = 0.25
			distance_label.text = _preparation_text()
	if _is_endless and RunManager.is_running:
		distance_label.text = "%d m recorridos" % roundi(float(get_parent().get(&"distance_traveled")))
	if ping_seconds_left > 0.0:
		ping_seconds_left -= delta
		if ping_seconds_left <= 0.0:
			ping_label.text = ""
			ping_indicator.text = ""
	if toast_seconds_left > 0.0:
		toast_seconds_left -= delta
		if toast_seconds_left <= 0.0:
			toast_label.text = ""
	if event_seconds_left > 0.0:
		event_seconds_left -= delta
		if event_seconds_left <= 0.0:
			event_label.text = ""


func _on_roster_changed(_peer_ids: Array) -> void:
	_refresh_session()


func _refresh_session() -> void:
	if session_label == null:
		return
	var mode: String = "ENDLESS" if _is_endless else "ENTREGA"
	if not NetworkManager.is_online():
		session_label.text = "%s  ·  SOLO" % mode
		_session_color(MINT)
		return
	var count: int = NetworkManager.peer_ids.size()
	var players: String = "%d jugador%s" % [count, "" if count == 1 else "es"]
	if not NetworkManager.is_host():
		session_label.text = "EN SALA  ·  %s" % players
		_session_color(UiTheme.SKY)
	elif NetworkManager.active_transport == NetworkManager.Transport.ENET:
		var address: String = NetworkManager.lan_address()
		session_label.text = "SALA LAN  ·  %s\nIP  %s" % [players, address if not address.is_empty() else "sin red local"]
		_session_color(UiTheme.SKY)
	else:
		session_label.text = "SALA STEAM  ·  %s\nInvitá desde la lista de amigos" % players
		_session_color(UiTheme.GRAPE)


## The session tape changes colour with the mode: mint solo, sky on LAN or
## as a guest, grape on Steam -- readable at a glance before the words are.
func _session_color(color: Color) -> void:
	var holder: PanelContainer = session_label.get_parent() as PanelContainer
	var style: StyleBoxFlat = holder.get_theme_stylebox("panel").duplicate()
	style.bg_color = color
	holder.add_theme_stylebox_override("panel", style)


func _on_started(_route: StringName, _players: Array) -> void:
	if WorldMood.active.has("description"):
		_toast("Ruta de hoy: %s" % String(WorldMood.active["description"]).to_lower())
	overlay.hide()
	overlay_mode = "run"
	dashboard.show()
	action_button.release_focus()
	_interaction_prompt = ""
	interaction_label.text = ""
	if _is_endless:
		section_label.text = "ENDLESS"
		distance_label.text = "0 m recorridos"


## The score as a sum you can check (tareas de Slatex #89): one line per
## thing that earned or cost points, the shared-chaos multiplier, the total.
static func score_breakdown_text(results: Dictionary, score: int) -> String:
	return preload("res://scripts/ui/hud/hud_results.gd").format_score_breakdown(results, score)

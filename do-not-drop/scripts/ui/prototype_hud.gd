extends "res://scripts/ui/hud/hud_notices.gd"
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


## The score chip and record ribbon only belong on the results card.
func _set_hero(visible_: bool, score: int = 0, new_best: bool = false) -> void:
	var hero: Control = score_label.get_parent().get_parent() as Control
	hero.visible = visible_
	score_label.text = "%d PTS" % score
	record_label.get_parent().get_parent().visible = new_best


## One place decides which overlay buttons exist on each screen -- the
## endless results used to inherit whatever the start screen had left on.
## An empty primary text hides the primary button.
func _set_buttons(primary: String, restart: bool, options: bool, menu: bool) -> void:
	action_button.visible = not primary.is_empty()
	action_button.text = primary
	second_button.visible = restart and _can_restart()
	options_button.visible = options
	menu_button.visible = menu
	var first: Button = action_button if action_button.visible else menu_button
	first.grab_focus()


func _show_start() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay_mode = "start"
	overlay.visible = true
	dashboard.visible = false
	overlay_kicker.text = "%s  ·  PROTOTIPO 0.1" % ("MODO ENDLESS" if _is_endless else "PRUEBA DE RUTA")
	overlay_title.text = "¡A REPARTIR!"
	_set_hero(false)
	overlay_body.text = "Arrancás en el depósito, con el camión estacionado adentro.\nLa entrega sale apenas alguien toma el volante con carga a bordo; el portón se cierra detrás de ustedes."
	overlay_stats.text = "1.  Leé la pizarra de pedidos: cada casa espera un paquete de un estante (A-1, B-6...).\n2.  Buscalo, presioná %s para agarrarlo y %s en el rack del camión para dejarlo.\n3.  Antes de salir: vestuario, taller y mostrador de suministros.\n4.  Subite al asiento del conductor (%s) y salí por el portón.\n\nCada cosa te muestra su indicación cuando te acercás." % [_key("E", "A"), _key("E", "A"), _key("E", "A")]
	_set_buttons("Preparar entrega", false, true, true)


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


func _request_restart() -> void:
	if _can_restart():
		EventBus.restart_requested.emit()


func _refresh_restart_hold(delta: float) -> void:
	var playing: bool = overlay_mode == "run" or overlay_mode == "preparation"
	if playing and _can_restart() and Input.is_action_pressed(&"run_restart"):
		_restart_hold += delta
		toast_label.text = "Reiniciando…  soltá para cancelar"
		toast_seconds_left = 0.2
		if _restart_hold >= RESTART_HOLD_SECONDS:
			_restart_hold = 0.0
			_request_restart()
	else:
		_restart_hold = 0.0


func _on_input_device_changed(_gamepad: bool) -> void:
	_refresh_shortcut_text()
	_refresh_card()
	_render_interaction_prompt()
	if overlay_mode == "start":
		_show_start()
	elif overlay_mode == "pause":
		overlay_stats.text = _pause_stats()


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


func _unhandled_input(event: InputEvent) -> void:
	if depot_panel != null and depot_panel.visible:
		return
	if event.is_action_pressed("ui_pause"):
		match overlay_mode:
			"pause":
				_resume()
			"run", "preparation":
				_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("run_restart"):
		# Instant only where it's clearly a menu choice; during play it's the
		# hold in _refresh_restart_hold().
		if overlay_mode == "pause" or overlay_mode == "results":
			_request_restart()
			get_viewport().set_input_as_handled()


func _pause() -> void:
	if NetworkManager.is_online():
		_soft_pause = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		EventBus.pause_requested.emit()
		if not get_tree().paused:
			return
	overlay_mode = "pause"
	overlay.show()
	overlay_kicker.text = "PAUSA"
	overlay_title.text = "EN PAUSA" if not _soft_pause else "MENÚ"
	overlay_body.text = "Tu entrega puede esperar." if not _soft_pause else "La partida sigue corriendo para el resto del equipo."
	overlay_stats.text = _pause_stats()
	complaints_label.visible = false
	photo_strip.visible = false
	_set_hero(false)
	_set_buttons("Continuar", true, true, true)


func _pause_stats() -> String:
	return "%s para volver a la ruta." % _key("Esc", "Start")


func _resume() -> void:
	if _soft_pause:
		_soft_pause = false
		overlay.hide()
		overlay_mode = "run" if RunManager.is_running else "preparation"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		EventBus.pause_requested.emit()


func _open_options() -> void:
	options_panel.open()


## Leaving mid-run has to put the session back the way the menu expects it:
## unpaused, with the cursor back, and with no half-finished run left in
## RunManager for the next level to inherit.
func _leave_to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	RunManager.reset_run()
	if NetworkManager.is_online():
		NetworkManager.leave_session()
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/main_menu.tscn")


func _primary_action() -> void:
	match overlay_mode:
		"start":
			overlay.hide()
			overlay_mode = "preparation"
			dashboard.show()
			action_button.release_focus()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			section_label.text = "PREPARACIÓN"
			distance_label.text = _preparation_text()
		"pause": _resume()
		"results": _request_restart()
		"disconnected": _leave_to_menu()


## The objective while still in the depot: each house's order and whether
## it's aboard yet, read off the boxes themselves.
func _preparation_text() -> String:
	if _orders.is_empty():
		return "Cargá paquetes y tomá el volante"
	var parts: PackedStringArray = []
	for order: Dictionary in _orders:
		var aboard: bool = false
		for package: Node in get_tree().get_nodes_in_group(&"cargo"):
			if StringName(package.get(&"package_id")) == StringName(order.package_id):
				aboard = bool(package.get(&"is_loaded"))
				break
		parts.append("Casa %d: %s %s" % [int(order.house) + 1, order.code, "(a bordo)" if aboard else "(falta)"])
	return "   ".join(parts)


func _on_depot_station_opened(station: StringName) -> void:
	if overlay_mode != "preparation" or RunManager.is_running:
		return
	var level: Node = get_parent()
	depot_panel.open(station, level.get(&"depot") if level != null and &"depot" in level else null)


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


## A client whose host vanished used to be left driving a frozen puppet van
## with no word of what happened and only Alt+F4 to get out.
func _on_connection_lost(reason: String) -> void:
	get_tree().paused = false
	_soft_pause = false
	overlay_mode = "disconnected"
	overlay.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay_kicker.text = "MULTIJUGADOR"
	overlay_title.text = "SIN CONEXIÓN"
	overlay_body.text = reason
	overlay_stats.text = "La partida del anfitrión ya no está disponible."
	_set_hero(false)
	complaints_label.visible = false
	photo_strip.visible = false
	_set_buttons("Volver al menú", false, false, false)


func _on_ended(score: int, results: Dictionary) -> void:
	_soft_pause = false
	overlay_mode = "results"
	overlay.show()
	overlay_kicker.text = "RESULTADO"
	var new_best: bool = bool(results.get("is_new_best", false))
	_set_hero(true, score, new_best)
	var best_line: String = "" if new_best else "\nRécord: %d pts" % int(results.get("best_score", 0))
	var retry: String = "Volver a intentar" if _can_restart() else ""
	var client_line: String = "" if _can_restart() else "\n\nSolo el anfitrión puede reiniciar. Para otra vuelta, volvé al menú y unite de nuevo a la sala."
	if results.has("distance_traveled"):
		# Endless (docs/tareas-nacho.md #52): no delivery zone, so there's no
		# "success" state, only how far the run got before it ended.
		overlay_title.text = "FIN DEL RECORRIDO"
		overlay_body.text = String(results["reason"])
		overlay_stats.text = "%.0f m recorridos   ·   %.1f s%s%s" % [float(results["distance_traveled"]), results["elapsed_seconds"], best_line, client_line]
		complaints_label.visible = false
		photo_strip.visible = false
		_set_buttons(retry, false, false, true)
		return
	var success: bool = results["delivered"]
	var total: int = int(results.get("cargo_total", 0))
	var intact: int = int(results.get("cargo_intact", 0))
	var ruined: int = int(results.get("cargo_ruined", 0))
	var delivered_doors: int = int(results.get("houses_delivered", 0))
	var missed_doors: int = int(results.get("houses_missed", 0))
	# Reaching the end without a single door isn't a delivery, whatever the
	# run's own success flag says -- the headline shouldn't cheer over it.
	if not success:
		overlay_title.text = "OTRA VUELTA"
	elif delivered_doors == 0 and missed_doors > 0:
		overlay_title.text = "RUTA TERMINADA"
	else:
		overlay_title.text = "¡ENTREGADO!"
	overlay_body.text = _delivery_summary(delivered_doors, missed_doors, total, ruined, intact) if success else String(results["reason"])
	var chaos: float = float(results.get("chaos_multiplier", 1.0))
	var chaos_line: String = "\nBonus por caos compartido: x%.1f" % chaos if chaos > 1.0 else ""
	var door_line: String = "\nPuertas: %d pts" % int(results.get("delivery_points", 0)) if results.has("delivery_points") else ""
	if results.has("breakdown"):
		overlay_stats.text = score_breakdown_text(results, score) + best_line + client_line
	else:
		overlay_stats.text = "En ruta: %.1f s\nCarga: %d pts   +   Rapidez: %d pts%s%s%s%s" % [results["elapsed_seconds"], results["cargo_points"], results["time_bonus"], door_line, chaos_line, best_line, client_line]
	_show_complaints(results.get("complaints", []))
	_show_photos()
	_set_buttons(retry, false, false, true)


## The score as a sum you can check (tareas de Slatex #89): one line per
## thing that earned or cost points, the shared-chaos multiplier, the total.
static func score_breakdown_text(results: Dictionary, score: int) -> String:
	var lines: PackedStringArray = ["En ruta: %.1f s" % float(results.get("elapsed_seconds", 0.0))]
	for line: Dictionary in results.get("breakdown", []):
		var points: int = int(line["points"])
		lines.append("%s   %s%d" % [String(line["label"]), "+" if points >= 0 else "−", absi(points)])
	var chaos: float = float(results.get("chaos_multiplier", 1.0))
	if chaos > 1.0:
		lines.append("Caos compartido   ×%.1f" % chaos)
	lines.append("Total   %d pts" % score)
	return "\n".join(lines)


## The headline leads with the doors, because that's where the run is
## actually won -- what's still in the van is the leftover, not the point.
func _delivery_summary(delivered_doors: int, missed_doors: int, aboard: int, ruined: int, intact: int) -> String:
	var lines: PackedStringArray = []
	if delivered_doors > 0:
		lines.append("Entregaste en %d puerta%s." % [delivered_doors, "" if delivered_doors == 1 else "s"])
	if missed_doors > 0:
		lines.append("1 vecino se quedó esperando." if missed_doors == 1 else "%d vecinos se quedaron esperando." % missed_doors)
	if aboard > 0:
		var back: int = aboard - ruined
		if back == 1:
			lines.append("Volvió 1 paquete en la furgoneta%s." % (", intacto" if intact >= 1 else ""))
		elif back > 1:
			lines.append("Volvieron %d paquetes en la furgoneta, %d intactos." % [back, intact])
	return "\n".join(lines) if not lines.is_empty() else "Llegaste, y eso ya es algo."


## Residents who got a battered box speak up afterwards. The photo taken at
## their door is what settles it -- that's the whole reason to stop and take
## one instead of running straight back to the van.
func _show_complaints(complaints: Array) -> void:
	if complaints.is_empty():
		complaints_label.visible = false
		return
	var lines: PackedStringArray = []
	for complaint: Dictionary in complaints:
		var house: int = int(complaint["house"]) + 1
		if bool(complaint["dismissed"]):
			lines.append("Casa %d reclamó que llegó roto — les mostraste la foto. Caso cerrado." % house)
		else:
			lines.append("Casa %d reclamó que llegó roto y no tenías foto. Te lo descuentan." % house)
	complaints_label.text = "\n".join(lines)
	complaints_label.visible = true


## The shots themselves, as a contact sheet under the numbers. Nothing is
## drawn headless (no framebuffer to capture), so this simply stays hidden.
func _show_photos() -> void:
	for child: Node in photo_strip.get_children():
		child.queue_free()
	var photos: Dictionary = RunManager.delivery_photos
	if photos.is_empty():
		photo_strip.visible = false
		return
	var houses: Array = photos.keys()
	houses.sort()
	for index: int in range(houses.size()):
		var house: int = houses[index]
		# Polaroids, each stuck on at its own slight angle.
		var frame := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = UiTheme.WHITE
		style.border_color = INK
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
		style.set_content_margin_all(6)
		style.content_margin_bottom = 22
		style.shadow_color = INK
		style.shadow_size = 1
		style.shadow_offset = Vector2(0, 4)
		frame.add_theme_stylebox_override("panel", style)
		frame.rotation_degrees = [-3.0, 2.0, -1.5, 3.0][index % 4]
		var thumbnail := TextureRect.new()
		thumbnail.texture = photos[house]
		thumbnail.custom_minimum_size = Vector2(160, 90)
		thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(thumbnail)
		photo_strip.add_child(frame)
	photo_strip.visible = true

class_name HudPause
extends Node
## Start, pause, restart-hold and disconnect screens, and the depot stations' panels.

## Set by Hud before this is added as its child.
var hud: Hud
var _restart_hold: float = 0.0


func _ready() -> void:
	EventBus.depot_station_opened.connect(_on_depot_station_opened)
	NetworkManager.session_failed.connect(_on_connection_lost)
	GameSettings.input_device_changed.connect(_on_input_device_changed)


func show_start() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.overlay_mode = "start"
	hud.overlay.visible = true
	hud.dashboard.visible = false
	hud.overlay_kicker.text = "%s  ·  PROTOTIPO 0.1" % ("MODO ENDLESS" if hud.is_endless else "PRUEBA DE RUTA")
	hud.overlay_title.text = "¡A REPARTIR!"
	hud.results.set_hero(false)
	hud.overlay_body.text = "Arrancás en el depósito, con el camión estacionado adentro.\nLa entrega sale apenas alguien toma el volante con carga a bordo; el portón se cierra detrás de ustedes."
	hud.overlay_stats.text = "1.  Leé la pizarra de pedidos: cada casa espera un paquete de un estante (A-1, B-6...).\n2.  Buscalo, presioná %s para agarrarlo y %s en el rack del camión para dejarlo.\n3.  Antes de salir: vestuario, taller y mostrador de suministros.\n4.  Subite al asiento del conductor (%s) y salí por el portón.\n\nCada cosa te muestra su indicación cuando te acercás." % [hud.key_hint("E", "A"), hud.key_hint("E", "A"), hud.key_hint("E", "A")]
	hud.results.set_buttons("Preparar entrega", false, true, true)


func request_restart() -> void:
	if hud.prompts.can_restart():
		EventBus.restart_requested.emit()


func refresh_restart_hold(delta: float) -> void:
	var playing: bool = hud.overlay_mode == "run" or hud.overlay_mode == "preparation"
	if playing and hud.prompts.can_restart() and Input.is_action_pressed(&"run_restart"):
		_restart_hold += delta
		hud.notices.set_notice(&"information", &"restart", "Reiniciando…  soltá para cancelar", 100, Hud.YELLOW, 0.25)
		if _restart_hold >= Hud.RESTART_HOLD_SECONDS:
			_restart_hold = 0.0
			request_restart()
	else:
		_restart_hold = 0.0
		hud.notices.clear_notice(&"information", &"restart")


func _on_input_device_changed(_gamepad: bool) -> void:
	hud.prompts.refresh_shortcut_text()
	hud.notices.refresh_card()
	hud.prompts.render_interaction_prompt()
	if hud.overlay_mode == "start":
		show_start()
	elif hud.overlay_mode == "pause":
		hud.overlay_stats.text = _pause_stats()


func _unhandled_input(event: InputEvent) -> void:
	if hud.depot_panel != null and hud.depot_panel.visible:
		return
	if event.is_action_pressed("ui_pause"):
		match hud.overlay_mode:
			"pause":
				_resume()
			"run", "preparation":
				_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("run_restart"):
		if hud.overlay_mode == "pause" or hud.overlay_mode == "results":
			request_restart()
			get_viewport().set_input_as_handled()


func _pause() -> void:
	if NetworkManager.is_online():
		hud.soft_pause = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		EventBus.pause_requested.emit()
		if not get_tree().paused:
			return
	hud.overlay_mode = "pause"
	hud.overlay.show()
	hud.overlay_kicker.text = "PAUSA"
	hud.overlay_title.text = "EN PAUSA" if not hud.soft_pause else "MENÚ"
	hud.overlay_body.text = "Tu entrega puede esperar." if not hud.soft_pause else "La partida sigue corriendo para el resto del equipo."
	hud.overlay_stats.text = _pause_stats()
	hud.complaints_label.visible = false
	hud.photo_strip.visible = false
	hud.results.set_hero(false)
	hud.results.set_buttons("Continuar", true, true, true)


func _pause_stats() -> String:
	return "Equipo: $%d\n%s para volver a la ruta." % [CrewProgression.team_money, hud.key_hint("Esc", "Start")]


func _resume() -> void:
	if hud.soft_pause:
		hud.soft_pause = false
		hud.overlay.hide()
		hud.overlay_mode = "run" if RunManager.is_running else "preparation"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		EventBus.pause_requested.emit()


func open_options() -> void:
	hud.options_panel.open()


func leave_to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	RunManager.reset_run()
	if NetworkManager.is_online():
		NetworkManager.leave_session()
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/main_menu.tscn")


func primary_action() -> void:
	match hud.overlay_mode:
		"start":
			hud.overlay.hide()
			hud.overlay_mode = "preparation"
			hud.dashboard.show()
			hud.economy_label.show()
			hud.action_button.release_focus()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			hud.section_label.text = "PREPARACIÓN"
			hud.distance_label.text = preparation_text()
		"pause": _resume()
		"results": request_restart()
		"disconnected": leave_to_menu()


func preparation_text() -> String:
	if hud.orders.is_empty():
		return "Cargá paquetes y tomá el volante"
	var parts: PackedStringArray = []
	for order: Dictionary in hud.orders:
		var aboard: bool = false
		for package: Node in get_tree().get_nodes_in_group(&"cargo"):
			if StringName(package.get(&"package_id")) == StringName(order.package_id):
				aboard = bool(package.get(&"is_loaded"))
				break
		parts.append("Casa %d: %s %s" % [int(order.house) + 1, order.code, "(a bordo)" if aboard else "(falta)"])
	return "   ".join(parts)


func _on_depot_station_opened(station: StringName) -> void:
	if hud.overlay_mode != "preparation" or RunManager.is_running:
		return
	var level: Node = hud.get_parent()
	hud.depot_panel.open(station, level.get(&"depot") if level != null and &"depot" in level else null)


func _on_connection_lost(reason: String) -> void:
	get_tree().paused = false
	hud.soft_pause = false
	hud.notices.clear_all_notices()
	hud.overlay_mode = "disconnected"
	hud.overlay.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.overlay_kicker.text = "MULTIJUGADOR"
	hud.overlay_title.text = "SIN CONEXIÓN"
	hud.overlay_body.text = reason
	hud.overlay_stats.text = "La partida del anfitrión ya no está disponible."
	hud.results.set_hero(false)
	hud.complaints_label.visible = false
	hud.photo_strip.visible = false
	hud.results.set_buttons("Volver al menú", false, false, false)

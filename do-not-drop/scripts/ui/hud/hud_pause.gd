extends "res://scripts/ui/hud/hud_results.gd"
## Overlay lifecycle: start/preparation, pause, safe restart, options,
## disconnect recovery and leaving the session.


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

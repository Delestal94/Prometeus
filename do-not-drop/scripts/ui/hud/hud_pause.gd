class_name HudPause
extends Node
## Start, pause, restart-hold and disconnect screens, and the depot stations' panels.

const RUN_TALLY = preload("res://scripts/core/run_tally.gd")

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
	hud.overlay_kicker.text = tr("HUD_START_KICKER") % (tr("HUD_MODE_ENDLESS") if hud.is_endless else tr("HUD_MODE_ROUTE"))
	hud.overlay_title.text = tr("HUD_START_TITLE")
	hud.results.set_hero(false)
	hud.overlay_body.text = tr("HUD_START_BODY")
	hud.overlay_stats.text = tr("HUD_START_STEPS") % [hud.key_hint("E", "A"), hud.key_hint("E", "A"), hud.key_hint("E", "A")]
	hud.results.set_buttons(tr("HUD_PREPARE_DELIVERY"), false, true, true)


func request_restart() -> void:
	if hud.prompts.can_restart():
		EventBus.restart_requested.emit()


func refresh_restart_hold(delta: float) -> void:
	var playing: bool = hud.overlay_mode == "run" or hud.overlay_mode == "preparation"
	if playing and hud.prompts.can_restart() and Input.is_action_pressed(&"run_restart"):
		_restart_hold += delta
		hud.notices.set_notice(&"information", &"restart", tr("HUD_RESTARTING"), 100, Hud.YELLOW, 0.25)
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
	if hud.options_panel != null and hud.options_panel.visible:
		return
	if event.is_action_pressed("ui_cancel") and hud.overlay_mode in ["pause", "results", "disconnected"]:
		match hud.overlay_mode:
			"pause": _resume()
			"results", "disconnected": leave_to_menu()
		get_viewport().set_input_as_handled()
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
	hud.overlay_kicker.text = tr("HUD_KICKER_PAUSE")
	hud.overlay_title.text = tr("HUD_PAUSED") if not hud.soft_pause else tr("HUD_MENU_TITLE")
	hud.overlay_body.text = tr("HUD_PAUSE_BODY") if not hud.soft_pause else tr("HUD_SOFT_PAUSE_BODY")
	hud.overlay_stats.text = _pause_stats()
	hud.complaints_label.visible = false
	hud.photo_strip.visible = false
	hud.results.set_hero(false)
	hud.results.set_buttons(tr("HUD_CONTINUE"), true, true, true)


func _pause_stats() -> String:
	return tr("HUD_PAUSE_STATS") % [CrewProgression.team_money, hud.key_hint("Esc", "Start")]


func _resume() -> void:
	if hud.soft_pause:
		hud.soft_pause = false
		hud.overlay.hide()
		hud.action_button.release_focus()
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
			hud.set_economy_visible(true)
			hud.action_button.release_focus()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			hud.section_label.text = tr("HUD_PREPARATION")
			hud.distance_label.text = preparation_text()
			hud.prompts.refresh_shortcut_text()
		"pause": _resume()
		"results": request_restart()
		"disconnected": leave_to_menu()


func preparation_text() -> String:
	if hud.orders.is_empty():
		return tr("HUD_PREP_LOAD_AND_DRIVE")
	var parts: PackedStringArray = []
	for order: Dictionary in hud.orders:
		var aboard: bool = false
		for package: Node in get_tree().get_nodes_in_group(&"cargo"):
			if StringName(package.get(&"package_id")) == StringName(order.package_id):
				aboard = bool(package.call(&"is_aboard"))
				break
		parts.append(tr("HUD_PREP_ORDER") % [int(order.house) + 1, order.code, tr("HUD_PREP_ABOARD") if aboard else tr("HUD_PREP_MISSING")])
	return "   ".join(parts)


func _on_depot_station_opened(station: StringName) -> void:
	if hud.overlay_mode != "preparation" or RunManager.is_running:
		return
	var level: Node = hud.get_parent()
	hud.depot_panel.open(station, level.get(&"depot") if level != null and &"depot" in level else null)


func _on_connection_lost(reason: String) -> void:
	get_tree().paused = false
	hud.soft_pause = false
	hud.prompts.session_lost = true
	# N-222: results already up are how the run ended, the host's last word.
	# They stay; only the way on changes (HudResults.show_host_gone()).
	if hud.overlay_mode == "results":
		hud.results.show_host_gone()
		return
	hud.notices.clear_all_notices()
	hud.overlay_mode = "disconnected"
	hud.overlay.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.overlay_kicker.text = tr("HUD_KICKER_MULTIPLAYER")
	hud.overlay_title.text = tr("HUD_DISCONNECTED")
	hud.overlay_body.text = reason
	hud.overlay_stats.text = tr("HUD_HOST_GONE")
	# N-222: the host's results will never come, so what this peer saw of the
	# run is what the crew gets to keep on screen.
	if RUN_TALLY.has_unfinished_run(RunManager):
		hud.overlay_stats.text += "\n" + RUN_TALLY.describe(RUN_TALLY.of(RunManager))
	hud.results.set_hero(false)
	hud.complaints_label.visible = false
	hud.photo_strip.visible = false
	hud.results.set_buttons(tr("HUD_BACK_TO_MENU"), false, false, false)

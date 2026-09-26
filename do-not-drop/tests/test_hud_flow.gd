extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_hud_flow.gd
##
## The HUD's own rules, driven directly: which buttons each overlay offers,
## prompts that follow the device in hand, a restart that has to be held
## during play instead of firing on one stray key, and a client that loses
## its host getting told so instead of being left in a frozen world.

var failures: int = 0
var _restarts: int = 0
const COUCH_HUD_SCALE: float = 0.6
const SCALE_720_TO_1080: float = 1080.0 / 720.0
const MIN_EFFECTIVE_FONT_SIZE: float = 14.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: Node = root.get_node("GameSettings")
	var bus: Node = root.get_node("EventBus")
	var network: Node = root.get_node("NetworkManager")
	var hud: CanvasLayer = load("res://scripts/ui/prototype_hud.gd").new()
	root.add_child(hud)
	await process_frame
	bus.restart_requested.connect(func() -> void: _restarts += 1)

	# --- the start screen ---
	_expect(hud.overlay_mode == "start" and hud.overlay.visible, "Opens on the start screen")
	_expect(hud.action_button.visible and hud.options_button.visible and hud.menu_button.visible,
		"Start offers begin, options and menu")
	_expect(not hud.second_button.visible, "Nothing to restart before anything started")
	_expect(hud.route_bar.visible, "Outside endless the route bar is shown")
	_expect(String(hud.session_label.text).contains("SOLO"), "Offline, the session corner says so")

	# --- prompts follow the device ---
	bus.interaction_prompt_changed.emit("Agarrar paquete")
	_expect(hud.interaction_label.text == "[ E ]  Agarrar paquete", "Keyboard prompt shows only the key")
	settings.using_gamepad = true
	settings.input_device_changed.emit(true)
	_expect(hud.interaction_label.text == "[ A ]  Agarrar paquete", "Switching to a gamepad re-renders the prompt")
	_expect(String(hud.shortcut_label.text).contains("Start"), "Shortcut line switches to gamepad buttons")
	settings.using_gamepad = false
	settings.input_device_changed.emit(false)
	bus.interaction_prompt_changed.emit("")
	_expect(hud.interaction_label.text == "", "An empty prompt clears the line")

	# --- the in-game HUD scales as one layer, still covering the screen ---
	# Put back whatever the player had: this writes their real settings file.
	var player_hud_scale: float = settings.hud_scale
	settings.hud_scale = 0.75
	var layer: Control = hud.hud_layer
	_expect(is_equal_approx(layer.scale.x, 0.75), "HUD scale setting resizes the HUD layer live")
	_expect(layer.size.is_equal_approx(hud.root.size / 0.75), "A scaled HUD still spans the whole screen")
	_expect(hud.overlay.get_parent() == hud.root and is_equal_approx(hud.overlay.get_global_transform().get_scale().x, 1.0),
		"The pause/results card keeps its own size")
	settings.hud_scale = player_hud_scale
	var player_menu_scale: float = settings.menu_text_scale
	var volume_slider: HSlider = hud.options_panel.get("_volume_slider") as HSlider
	var menu_caption := (volume_slider.get_parent().get_child(0) as HBoxContainer).get_child(0) as Label
	var hud_font_size: int = hud.speed_label.get_theme_font_size("font_size")
	settings.menu_text_scale = 1.5
	_expect(menu_caption.get_theme_font_size("font_size") == 24,
		"The 150% menu setting enlarges menu text live")
	_expect(hud.speed_label.get_theme_font_size("font_size") == hud_font_size,
		"Menu text scale stays independent from HUD scale")
	settings.menu_text_scale = player_menu_scale

	# --- restart has to be held during play ---
	hud._primary_action()
	_expect(hud.overlay_mode == "preparation" and not hud.overlay.visible, "Begin reveals the level")
	_expect(hud.economy_label.visible, "Team money is visible while making depot decisions")

	# --- fixed hierarchy: one message in each zone, never on top of another ---
	bus.route_event_started.emit(&"inspection", {
		"title": "INSPECCIÓN", "prompt": "Asegurá la carga", "remaining": 45.0,
	})
	bus.interaction_prompt_changed.emit("Agarrar paquete")
	bus.depot_notice.emit("Carta obtenida")
	await process_frame
	_expect(String(hud.event_label.text).contains("INSPECCIÓN"), "Critical event owns the top-centre zone")
	_expect(String(hud.interaction_label.text).contains("Agarrar paquete"), "Interaction owns the bottom-centre zone")
	_expect(String(hud.toast_label.text).contains("Carta obtenida"), "Toast owns the information zone")
	_expect(not _overlap(hud.event_label, hud.interaction_label)
		and not _overlap(hud.event_label, hud.toast_label)
		and not _overlap(hud.interaction_label, hud.toast_label),
		"Critical, context and information zones do not overlap")
	hud._set_notice(&"information", &"low", "Aviso normal", 1, Color.WHITE)
	hud._set_notice(&"information", &"high", "Aviso prioritario", 90, Color.WHITE)
	_expect(hud.toast_label.text == "Aviso prioritario", "The notice queue shows its highest priority")
	hud._clear_notice(&"information", &"high")
	_expect(hud.toast_label.text == "Carta obtenida", "Clearing a priority notice resumes the queued toast")
	hud._set_notice(&"information", &"brief", "Aviso breve", 95, Color.WHITE, 0.01)
	hud._process_notices(0.02)
	_expect(hud.toast_label.text == "Carta obtenida", "An expired priority notice resumes the queue (got '%s')" % hud.toast_label.text)

	# --- cargo state never relies on red/green alone ---
	var run_manager: Node = root.get_node("RunManager")
	run_manager.cargo[&"accessible_box"] = {"integrity": 35.0, "maximum": 100.0, "state": 1}
	bus.cargo_registered.emit(&"accessible_box", "Frágil")
	bus.package_state_changed.emit(&"accessible_box", 1)
	var accessible_row: Dictionary = hud.cargo_rows[&"accessible_box"]
	_expect(String((accessible_row["label"] as Label).text).contains("EN RIESGO !"),
		"At-risk cargo has a shape marker as well as a colour")
	_expect_hud_text_readable(hud)
	var original_palette: bool = settings.colorblind_palette
	settings.colorblind_palette = true
	var fill := (accessible_row["bar"] as ProgressBar).get_theme_stylebox("fill") as StyleBoxFlat
	_expect(fill.bg_color.is_equal_approx(UiTheme.OKABE_ORANGE),
		"The colour-blind option switches cargo state colours to Okabe-Ito")
	var original_subtitles: bool = settings.sound_subtitles
	settings.sound_subtitles = true
	bus.interaction_prompt_changed.emit("")
	hud._refresh_sound_subtitle()
	_expect(String(hud.interaction_label.text).contains("[vidrio que cruje]"),
		"An at-risk fragile trap captions its sound in the context zone")
	run_manager.cargo[&"accessible_box"]["state"] = 2
	bus.package_state_changed.emit(&"accessible_box", 2)
	_expect(String((accessible_row["label"] as Label).text).contains("ARRUINADA ✕"),
		"Ruined cargo has an X marker")
	settings.colorblind_palette = original_palette
	settings.sound_subtitles = original_subtitles

	# --- shortcut teaching can be automatic or explicitly overridden ---
	var unlocks: Node = root.get_node("UnlockManager")
	var original_runs: int = int(unlocks.completed_runs)
	var original_help: int = int(settings.control_help_mode)
	unlocks.completed_runs = 0
	settings.control_help_mode = settings.ControlHelp.BEGINNING
	hud._shortcut_learning_seconds = 0.0
	hud._refresh_shortcuts()
	_expect(hud.shortcut_label.get_parent().visible, "Beginning mode teaches a new player")
	hud._shortcut_learning_seconds = 60.0
	hud._refresh_shortcuts()
	_expect(not hud.shortcut_label.get_parent().visible, "Beginning mode hides after 60 seconds")
	hud._shortcut_learning_seconds = 0.0
	unlocks.completed_runs = 3
	hud._refresh_shortcuts()
	_expect(not hud.shortcut_label.get_parent().visible, "Beginning mode hides after three completed runs")
	settings.control_help_mode = settings.ControlHelp.ALWAYS
	hud._refresh_shortcuts()
	_expect(hud.shortcut_label.get_parent().visible, "Always mode keeps shortcuts visible")
	settings.control_help_mode = settings.ControlHelp.NEVER
	hud._refresh_shortcuts()
	_expect(not hud.shortcut_label.get_parent().visible, "Never mode hides shortcuts")
	settings.control_help_mode = original_help
	unlocks.completed_runs = original_runs

	hud._on_started(&"delivery", [])
	_expect(not hud.economy_label.visible, "Team money is hidden while driving")
	_expect(String(hud._pause_stats()).contains("$%d" % int(root.get_node("CrewProgression").team_money)),
		"Pause shows team money")
	Input.action_press(&"run_restart")
	await create_timer(0.3).timeout
	_expect(_restarts == 0, "A tap of R mid-play doesn't throw the run away")
	await create_timer(0.9).timeout
	Input.action_release(&"run_restart")
	_expect(_restarts == 1, "Holding R restarts exactly once")
	await process_frame

	# --- results offer retry and menu, nothing left over from other screens ---
	bus.run_ended.emit(120, {"distance_traveled": 340.0, "reason": "Volcaste.", "elapsed_seconds": 42.0, "best_score": 90})
	await process_frame
	_expect(hud.overlay_mode == "results", "Results open")
	_expect(hud.action_button.visible and hud.menu_button.visible, "Results offer retry and menu")
	_expect(not hud.options_button.visible and not hud.second_button.visible, "Results don't carry stale buttons")
	_expect(String(hud.overlay_stats.text).contains("$%d" % int(root.get_node("CrewProgression").team_money)),
		"Results show team money")

	# --- losing the host ---
	network.session_failed.emit("Se cortó la conexión con el anfitrión.")
	await process_frame
	_expect(hud.overlay_mode == "disconnected" and hud.overlay.visible, "Losing the host opens its own screen")
	_expect(hud.action_button.text == "Volver al menú", "The only way forward is back to the menu")
	_expect(not hud.second_button.visible and not hud.options_button.visible, "No restart into a dead session")

	hud.free()
	if failures == 0:
		print("PASS: overlay buttons, device-aware prompts, held restart and connection loss")
	quit(failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1


func _expect_hud_text_readable(hud: CanvasLayer) -> void:
	var too_small: PackedStringArray = []
	for node: Node in hud.hud_layer.find_children("*", "Control", true, false):
		var base_size: int = 0
		if node is RichTextLabel:
			base_size = (node as RichTextLabel).get_theme_font_size(&"normal_font_size")
		elif node is Label:
			base_size = (node as Label).get_theme_font_size(&"font_size")
		else:
			continue
		var effective_size: float = float(base_size) * COUCH_HUD_SCALE * SCALE_720_TO_1080
		if effective_size < MIN_EFFECTIVE_FONT_SIZE:
			too_small.append("%s: %.1f px" % [str(hud.hud_layer.get_path_to(node)), effective_size])
	_expect(too_small.is_empty(),
		"Every HUD label stays at least 14 px at 60%% scale and 1080p (%s)" % ", ".join(too_small))


func _overlap(a: Control, b: Control) -> bool:
	return not a.text.is_empty() and not b.text.is_empty() and a.get_global_rect().intersects(b.get_global_rect())

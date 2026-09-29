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
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	bus.restart_requested.connect(func() -> void: _restarts += 1)

	# --- F10 clean capture mode (debug builds only) ---
	var capture_mode: Node = hud.get_node_or_null(^"CaptureMode")
	_expect(capture_mode != null, "Debug HUD exposes the F10 capture switch")
	var phone_overlay := CanvasLayer.new()
	phone_overlay.name = "CaptureTestPhone"
	root.add_child(phone_overlay)
	var viewmodel := Node3D.new()
	viewmodel.name = "CaptureTestViewmodel"
	viewmodel.add_to_group(&"viewmodel")
	root.add_child(viewmodel)
	if capture_mode != null:
		var f10 := InputEventKey.new()
		f10.keycode = KEY_F10
		f10.pressed = true
		capture_mode.call(&"_unhandled_input", f10)
		_expect(not hud.visible and not phone_overlay.visible and not viewmodel.visible,
			"F10 capture mode hides every HUD layer and the viewmodel")
		var late_overlay := CanvasLayer.new()
		late_overlay.name = "CaptureTestLateOverlay"
		root.add_child(late_overlay)
		await process_frame
		_expect(not late_overlay.visible, "Capture mode also hides overlays created while it is active")
		capture_mode.call(&"set_enabled", false)
		_expect(hud.visible and phone_overlay.visible and viewmodel.visible and late_overlay.visible,
			"Leaving capture mode restores each previous visibility state")
		late_overlay.free()
	phone_overlay.free()
	viewmodel.free()

	# --- the start screen ---
	_expect(hud.overlay_mode == "start" and hud.overlay.visible, "Opens on the start screen")
	_expect(hud.action_button.visible and hud.options_button.visible and hud.menu_button.visible,
		"Start offers begin, options and menu")
	_expect(not hud.second_button.visible, "Nothing to restart before anything started")
	_expect(hud.route_bar.visible, "Outside endless the route bar is shown")
	_expect(String(hud.session_label.text).contains("SOLO"), "Offline, the session corner says so")
	for action_id: StringName in [&"grab", &"drop", &"sit", &"bell", &"photo", &"horn", &"ping", &"open_box",
			&"use_card"]:
		_expect(UiTheme.action_icon(action_id) != null, "%s has an action icon" % action_id)
	_expect(UiTheme.action_icon(&"unknown") == null, "Unknown actions keep the text-only fallback")

	# --- prompts follow the device ---
	bus.interaction_prompt_changed.emit("Agarrar paquete")
	_expect(hud.interaction_label.text == "[ E ]  Agarrar paquete", "Keyboard prompt shows only the key")
	_expect(hud.interaction_icon.visible
		and hud.interaction_icon.texture == UiTheme.action_icon(&"grab"),
		"Interaction prompt shows the matching action icon")
	settings.using_gamepad = true
	settings.input_device_changed.emit(true)
	_expect(hud.interaction_label.text == "[ A ]  Agarrar paquete", "Switching to a gamepad re-renders the prompt")
	_expect(String(hud.shortcut_label.text).contains("Start"), "Shortcut line switches to gamepad buttons")
	settings.using_gamepad = false
	settings.input_device_changed.emit(false)
	bus.interaction_prompt_changed.emit("")
	_expect(hud.interaction_label.text == "", "An empty prompt clears the line")
	_expect(not hud.interaction_icon.visible, "An empty prompt clears its action icon")

	# --- the in-game HUD scales as one layer, still covering the screen ---
	# Put back whatever the player had: this writes their real settings file.
	var player_hud_scale: float = settings.hud_scale
	settings.hud_scale = 0.75
	var layer: Control = hud.hud_layer
	# 0.75 on top of the window-shape correction (layout_scale()).
	var expected_scale: float = hud.call(&"layout_scale", 0.75, hud.root.size)
	_expect(is_equal_approx(layer.scale.x, expected_scale), "HUD scale setting resizes the HUD layer live")
	_expect(layer.size.is_equal_approx(hud.root.size / expected_scale), "A scaled HUD still spans the whole screen")
	_expect(hud.overlay.get_parent() == hud.root and is_equal_approx(hud.overlay.get_global_transform().get_scale().x, 1.0),
		"The pause/results card keeps its own size")
	_expect(is_equal_approx(hud.overlay_center.scale.x, hud.call(&"layout_scale", 1.0, hud.root.size)),
		"The card takes only the window-shape correction, not the player's HUD scale")
	settings.hud_scale = player_hud_scale
	# Window shapes: the HUD keeps its 16:9 text size in taller windows and
	# only gains room in wider ones.
	_expect(is_equal_approx(hud.call(&"layout_scale", 1.0, Vector2(1280, 960)), 960.0 / 720.0),
		"At 4:3 the HUD scales back up to its 16:9 size instead of shrinking to 75%")
	_expect(is_equal_approx(hud.call(&"layout_scale", 1.0, Vector2(1720, 720)), 1.0),
		"At 21:9 the HUD keeps its size and just gets more room")
	_expect(is_equal_approx(hud.call(&"layout_scale", 0.75, Vector2(1280, 800)), 0.75 * 800.0 / 720.0),
		"The player's HUD scale still applies on top of the window shape")
	# The prompt sits in the dashboard's flow right above the bottom bar, never on it.
	var prompt_index: int = hud.interaction_label.get_index()
	_expect(hud.interaction_label.get_parent() == hud.dashboard
			and hud.dashboard.get_child(prompt_index + 1).is_ancestor_of(hud.cargo_rows_box),
		"The interaction prompt stands right above the bottom bar")
	var player_menu_scale: float = settings.menu_text_scale
	var volume_slider: HSlider = hud.options_panel.get("_volume_slider") as HSlider
	var impact_effects_check := hud.options_panel.get("_impact_effects_check") as CheckBox
	_expect(impact_effects_check != null and impact_effects_check.text == "Efectos de impacto",
		"Options exposes the impact-effects accessibility switch")
	var menu_caption := (volume_slider.get_parent().get_child(0) as HBoxContainer).get_child(0) as Label
	var hud_font_size: int = hud.speed_label.get_theme_font_size("font_size")
	settings.menu_text_scale = 1.5
	_expect(menu_caption.get_theme_font_size("font_size") == 24,
		"The 150% menu setting enlarges menu text live")
	_expect(hud.speed_label.get_theme_font_size("font_size") == hud_font_size,
		"Menu text scale stays independent from HUD scale")
	settings.menu_text_scale = player_menu_scale

	# --- restart has to be held during play ---
	hud.pause.primary_action()
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
	hud.notices.set_notice(&"information", &"low", "Aviso normal", 1, Color.WHITE)
	hud.notices.set_notice(&"information", &"high", "Aviso prioritario", 90, Color.WHITE)
	_expect(hud.toast_label.text == "Aviso prioritario", "The notice queue shows its highest priority")
	hud.notices.clear_notice(&"information", &"high")
	_expect(hud.toast_label.text == "Carta obtenida", "Clearing a priority notice resumes the queued toast")
	hud.notices.set_notice(&"information", &"brief", "Aviso breve", 95, Color.WHITE, 0.01)
	hud.notices.process_notices(0.02)
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
	hud.prompts.refresh_sound_subtitle()
	_expect(String(hud.interaction_label.text).contains("[vidrio que cruje]"),
		"An at-risk fragile trap captions its sound in the context zone")
	run_manager.cargo[&"accessible_box"]["state"] = 2
	bus.package_state_changed.emit(&"accessible_box", 2)
	_expect(String((accessible_row["label"] as Label).text).contains("ARRUINADA ✕"),
		"Ruined cargo has an X marker")
	settings.colorblind_palette = original_palette
	settings.sound_subtitles = original_subtitles

	# --- ruined cargo gets a local-only soft flash, never global slow motion ---
	var original_impact_effects: bool = settings.impact_effects
	settings.impact_effects = true
	var time_scale_before: float = Engine.time_scale
	hud.cargo._on_ruin_impact(&"accessible_box", "test")
	_expect(hud.ruin_vignette.color.r > 0.99 and hud.ruin_vignette.color.a > 0.0,
		"A ruined package flashes a soft white edge vignette")
	_expect(is_equal_approx(Engine.time_scale, time_scale_before),
		"The HUD ruin flash never changes global time scale")
	hud.cargo.refresh_ruin_impact(0.4)
	_expect(is_zero_approx(hud.ruin_vignette.color.a), "The ruin flash clears after 0.35 seconds")
	settings.impact_effects = false
	hud.cargo._on_ruin_impact(&"accessible_box", "disabled")
	_expect(is_zero_approx(hud.ruin_vignette.color.a), "Impact effects can be disabled for accessibility")
	settings.impact_effects = original_impact_effects

	# --- shortcut teaching can be automatic or explicitly overridden ---
	var unlocks: Node = root.get_node("UnlockManager")
	var original_runs: int = int(unlocks.completed_runs)
	var original_help: int = int(settings.control_help_mode)
	unlocks.completed_runs = 0
	settings.control_help_mode = settings.ControlHelp.BEGINNING
	hud.prompts._shortcut_learning_seconds = 0.0
	hud.prompts.refresh_shortcuts()
	_expect(hud.shortcut_label.get_parent().visible, "Beginning mode teaches a new player")
	hud.prompts._shortcut_learning_seconds = 60.0
	hud.prompts.refresh_shortcuts()
	_expect(not hud.shortcut_label.get_parent().visible, "Beginning mode hides after 60 seconds")
	hud.prompts._shortcut_learning_seconds = 0.0
	unlocks.completed_runs = 3
	hud.prompts.refresh_shortcuts()
	_expect(not hud.shortcut_label.get_parent().visible, "Beginning mode hides after three completed runs")
	settings.control_help_mode = settings.ControlHelp.ALWAYS
	hud.prompts.refresh_shortcuts()
	_expect(hud.shortcut_label.get_parent().visible, "Always mode keeps shortcuts visible")
	settings.control_help_mode = settings.ControlHelp.NEVER
	hud.prompts.refresh_shortcuts()
	_expect(not hud.shortcut_label.get_parent().visible, "Never mode hides shortcuts")
	settings.control_help_mode = original_help
	unlocks.completed_runs = original_runs

	var posted: Array = [{"house": 0, "code": "A-1", "trap": "Frágil", "content": "Vajilla"}]
	bus.emit_signal(&"depot_orders_posted", posted)
	_expect(hud.orders == posted, "The HUD keeps the depot's posted orders for the orders station")

	hud._on_started(&"delivery", [])
	_expect(not hud.economy_label.visible and not hud.economy_label.get_parent().visible,
		"Team money is hidden while driving, chip and all (no empty yellow pill)")
	_expect(String(hud.pause._pause_stats()).contains("$%d" % int(root.get_node("CrewProgression").team_money)),
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

	# --- delivery results explain each stop and what comes next ---
	var original_score: int = int(unlocks.total_score)
	var original_deliveries: int = int(unlocks.successful_deliveries)
	var original_unlocked: Dictionary = unlocks.unlocked.duplicate(true)
	unlocks.total_score = 0
	unlocks.successful_deliveries = 0
	unlocks.unlocked = {&"starter_kit": true}
	hud.results._on_ended(175, {
		"delivered": true,
		"reason": "",
		"elapsed_seconds": 40.0,
		"cargo_total": 0,
		"cargo_intact": 0,
		"cargo_ruined": 0,
		"cargo_points": 0,
		"time_bonus": 0,
		"houses_delivered": 1,
		"houses_missed": 1,
		"breakdown": [{"label": "Entregas perfectas (1)", "points": 150}],
		"best_score": 175,
		"complaints": [],
		"deliveries": [
			{"house": 0, "trap": "FRÁGIL", "outcome": &"delivered_ok", "photo": true},
			{"house": 1, "trap": "RUIDOSO", "outcome": &"missed", "photo": false},
		],
		"awards": [{"title": "MVP", "peer": network.local_id()}],
		"route_event": {"title": "Inspección sorpresa", "success": true},
	})
	await process_frame
	_expect(hud.result_rows_box.get_child_count() == 2, "Delivery results show one row per house")
	_expect(String(hud.result_awards_label.text).contains("MVP"), "Delivery results show merit awards")
	_expect(String(hud.result_event_label.text).contains("RESUELTO"), "Delivery results show how the route event ended")
	_expect(hud.result_progress_bar.visible and String(hud.result_progress_label.text).contains("Te faltan"),
		"Delivery results show progress toward the next unlock")
	unlocks.total_score = original_score
	unlocks.successful_deliveries = original_deliveries
	unlocks.unlocked = original_unlocked

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

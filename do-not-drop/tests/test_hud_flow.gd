extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_hud_flow.gd
##
## The HUD's own rules, driven directly: which buttons each overlay offers,
## prompts that follow the device in hand, a restart that has to be held
## during play instead of firing on one stray key, and a client that loses
## its host getting told so instead of being left in a frozen world.

var failures: int = 0
var _restarts: int = 0


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
	settings.hud_scale = 0.75
	var layer: Control = hud.hud_layer
	_expect(is_equal_approx(layer.scale.x, 0.75), "HUD scale setting resizes the HUD layer live")
	_expect(layer.size.is_equal_approx(hud.root.size / 0.75), "A scaled HUD still spans the whole screen")
	_expect(hud.overlay.get_parent() == hud.root and is_equal_approx(hud.overlay.get_global_transform().get_scale().x, 1.0),
		"The pause/results card keeps its own size")
	settings.hud_scale = 1.0

	# --- restart has to be held during play ---
	hud._primary_action()
	_expect(hud.overlay_mode == "preparation" and not hud.overlay.visible, "Begin reveals the level")
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

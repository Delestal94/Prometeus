extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_phone_frame.gd
##
## S-304: the phone's UI frame (scripts/ui/phone_frame.gd), the body around
## the camera viewfinder. Checks that:
## - it builds as a full-screen Control that lets the mouse through (the
##   middle is the camera; only the shutter button takes clicks);
## - the clock reads HH:MM, starts at an hour that fits the session's time of
##   day (WorldMood) and ticks forward while the phone is up, wrapping at
##   midnight;
## - the battery is decorative but deterministic: always in [0, 1], drains
##   slowly and stops at its floor, and assigning it clamps;
## - the shutter button sits in the right bezel, vertically centred, and a
##   left click on it emits `shutter_pressed` (other buttons don't);
## - status and hint lines go through set_status() / set_hint();
## - PhoneCamera builds its viewfinder on a PhoneFrame and wires the shutter
##   button to shoot(), so clicking it files a shot like the input action.
##
## Nothing is drawn headless: the rounded bezel itself is for revisor-visual.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var saved_mood: Dictionary = WorldMood.active

	var frame := PhoneFrame.new()
	root.add_child(frame)
	await process_frame
	_expect(frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The frame lets the mouse through to the camera")
	_expect(frame.size.x > 0.0 and frame.size.y > 0.0, "The frame fills the screen (size %s)" % frame.size)
	_expect(frame.shutter_button != null, "The frame has a shutter button")

	# --- the clock ---
	var pattern := RegEx.create_from_string("^([01][0-9]|2[0-3]):[0-5][0-9]$")
	_expect(pattern.search(frame.clock_text()) != null, "The clock reads HH:MM (got '%s')" % frame.clock_text())
	WorldMood.active = {"time": WorldMood.TimeOfDay.DAY}
	_expect(frame.clock_text() == "14:05", "Daytime starts in the afternoon (got %s)" % frame.clock_text())
	WorldMood.active = {"time": WorldMood.TimeOfDay.NIGHT}
	_expect(frame.clock_text() == "23:40", "Night starts late in the evening (got %s)" % frame.clock_text())
	frame._process(PhoneFrame.SECONDS_PER_GAME_MINUTE * 25.0)
	_expect(frame.clock_text() == "00:05", "The clock ticks on and wraps at midnight (got %s)" % frame.clock_text())
	_expect(pattern.search(frame.clock_text()) != null, "The clock still reads HH:MM after ticking")
	WorldMood.active = {}
	_expect(pattern.search(frame.clock_text()) != null, "The clock works before any world has picked a mood")

	# --- the battery ---
	_expect(frame.battery >= 0.0 and frame.battery <= 1.0, "The battery is a fraction (got %f)" % frame.battery)
	var before: float = frame.battery
	frame._process(60.0)
	_expect(frame.battery < before, "The battery drains while the phone is up")
	frame._process(1.0e6)
	_expect(is_equal_approx(frame.battery, PhoneFrame.BATTERY_FLOOR),
		"The battery stops at its floor (got %f)" % frame.battery)
	frame.battery = 5.0
	_expect(is_equal_approx(frame.battery, 1.0), "Assigning the battery clamps to 1")
	frame.battery = -2.0
	_expect(is_equal_approx(frame.battery, 0.0), "Assigning the battery clamps to 0")

	# --- the shutter button ---
	var button: Control = frame.shutter_button
	_expect(button.mouse_filter == Control.MOUSE_FILTER_STOP, "The shutter button takes the mouse")
	_expect(button.focus_mode == Control.FOCUS_NONE, "The shutter button doesn't steal gamepad focus")
	var centre: Vector2 = button.position + button.size * 0.5
	_expect(centre.x > frame.size.x - PhoneFrame.BEZEL_SIDE, "The shutter sits in the right bezel (x %f)" % centre.x)
	_expect(absf(centre.y - frame.size.y * 0.5) < 2.0, "The shutter is centred vertically (y %f)" % centre.y)
	var presses: Array[int] = [0]
	frame.shutter_pressed.connect(func() -> void: presses[0] += 1)
	button._gui_input(_click(MOUSE_BUTTON_LEFT, true))
	_expect(presses[0] == 1, "A left click on the shutter emits shutter_pressed (got %d)" % presses[0])
	button._gui_input(_click(MOUSE_BUTTON_LEFT, false))
	_expect(presses[0] == 1, "Releasing the button doesn't shoot again")
	button._gui_input(_click(MOUSE_BUTTON_RIGHT, true))
	_expect(presses[0] == 1, "A right click doesn't shoot")
	frame.press_shutter()
	_expect(presses[0] == 2, "press_shutter() emits shutter_pressed")

	# --- status and hint ---
	frame.set_status("status line", PhoneFrame.MINT)
	frame.set_hint("hint line")
	_expect(frame.status_text() == "status line" and frame.hint_text() == "hint line", "Status and hint are settable")
	_expect(tr("HUD_PHONE_SHUTTER") != "HUD_PHONE_SHUTTER", "The shutter tooltip has a translated text")
	frame.free()

	# --- PhoneCamera builds on it ---
	# Loaded, not named: PhoneCamera talks to autoloads (EventBus), and naming
	# the class would compile it before --script has them.
	var phone: CanvasLayer = load("res://scripts/presentation/phone_camera.gd").new()
	root.add_child(phone)
	await process_frame
	var inner: PhoneFrame = null
	for child: Node in phone.get_children():
		if child is PhoneFrame:
			inner = child
	_expect(inner != null, "PhoneCamera contains a PhoneFrame")
	if inner != null:
		_expect(not inner.visible, "The frame stays hidden until the phone is pulled out")
		_expect(not inner.is_processing(), "A put-away phone doesn't tick its clock or battery")
		_expect(inner.shutter_pressed.is_connected(Callable(phone, &"shoot")),
			"The shutter button is wired to PhoneCamera.shoot")
		_expect(not inner.hint_text().is_empty(), "The frame shows the control hint")
		inner.press_shutter()
		await process_frame
		_expect(inner.hint_text() == phone.tr("HUD_PHONE_NOTHING_TO_PROVE"),
			"Clicking the shutter files a shot like the input action (hint: '%s')" % inner.hint_text())
	phone.free()

	WorldMood.active = saved_mood
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: the phone frame draws the clock, battery and shutter, and PhoneCamera shoots through it")
	quit(_failures)


func _click(button_index: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	return event


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

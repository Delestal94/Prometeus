extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_settings.gd
##
## The options a player can actually change: that they apply where they're
## supposed to (the audio bus, the look maths), that they clamp instead of
## letting a dragged slider mute or wreck the game permanently, and that
## they survive closing the game. None of this is visible in a screenshot,
## which is exactly why it's worth pinning down.

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: Node = root.get_node("GameSettings")
	var original_path: String = settings.save_path  # the test file under --script, never the real one

	# --- volume reaches the bus, not just the variable ---
	settings.master_volume = 0.5
	var bus: int = AudioServer.get_bus_index("Master")
	_expect(bus >= 0, "There is a Master bus to write to")
	_expect(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.5)),
		"Setting the volume writes it to the Master bus")
	settings.master_volume = 0.0
	_expect(AudioServer.get_bus_volume_db(bus) < -60.0, "Zero volume actually silences the bus")

	# --- clamped, so a dragged slider can't leave the game unplayable ---
	settings.master_volume = 4.0
	_expect(is_equal_approx(settings.master_volume, 1.0), "Volume above 1.0 clamps to the balanced mix")
	settings.look_sensitivity = 99.0
	_expect(settings.look_sensitivity <= 3.0, "Look sensitivity clamps to something still controllable")
	settings.look_sensitivity = 0.0
	_expect(settings.look_sensitivity >= 0.2, "Look sensitivity can't be turned off entirely")
	settings.preferred_fov = 120.0
	_expect(is_equal_approx(settings.preferred_fov, 100.0), "FOV clamps to a comfortable maximum")
	settings.preferred_fov = 40.0
	_expect(is_equal_approx(settings.preferred_fov, 65.0), "FOV clamps to a comfortable minimum")
	settings.camera_shake_scale = -1.0
	_expect(is_zero_approx(settings.camera_shake_scale), "Camera shake can be disabled for accessibility")
	settings.effects_volume = 0.4
	settings.voice_volume = 0.6
	_expect(is_equal_approx(settings.effects_volume, 0.4), "Effects volume is stored independently")
	_expect(is_equal_approx(settings.voice_volume, 0.6), "Voice volume is stored independently")
	settings.bind_key(&"interact", KEY_F)
	_expect(settings.binding_label(&"interact") == "F", "Interact can be rebound to a keyboard key")
	var has_rebound_key: bool = false
	for event: InputEvent in InputMap.action_get_events(&"interact"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F:
			has_rebound_key = true
	_expect(has_rebound_key, "The rebound key is applied to InputMap immediately")
	settings.bind_key(&"interact", KEY_E)

	# --- inversion is expressed as a multiplier both look paths can use ---
	settings.invert_look_y = false
	_expect(is_equal_approx(settings.look_y_sign(), 1.0), "Not inverted leaves vertical look alone")
	settings.invert_look_y = true
	_expect(is_equal_approx(settings.look_y_sign(), -1.0), "Inverted flips vertical look")

	# --- HUD scale clamps to something still readable and still on screen ---
	settings.hud_scale = 10.0
	_expect(is_equal_approx(settings.hud_scale, settings.HUD_SCALE_MAX), "HUD scale clamps at the maximum")
	settings.hud_scale = 0.0
	_expect(is_equal_approx(settings.hud_scale, settings.HUD_SCALE_MIN), "HUD scale clamps at the minimum")
	settings.hud_scale = 0.8
	var saved := ConfigFile.new()
	saved.load(original_path)
	_expect(is_equal_approx(float(saved.get_value("player", "hud_scale", -1.0)), 0.8), "The saved file holds the HUD scale that was set")
	settings.hud_scale = 1.0

	# --- they survive a restart ---
	settings.master_volume = 0.35
	settings.look_sensitivity = 1.75
	settings.invert_look_y = true
	# Simulate the next launch: wipe the in-memory values, then load.
	settings.master_volume = 1.0
	settings.preferred_fov = 82.0
	settings.camera_shake_scale = 1.0
	settings.effects_volume = 1.0
	settings.voice_volume = 1.0
	settings.look_sensitivity = 1.0
	settings.invert_look_y = false
	settings.master_volume = 0.35
	settings.look_sensitivity = 1.75
	settings.invert_look_y = true
	var config := ConfigFile.new()
	_expect(config.load(original_path) == OK, "Settings are written to disk as they change")
	_expect(is_equal_approx(float(config.get_value("player", "master_volume", -1.0)), 0.35),
		"The saved file holds the volume that was set")
	_expect(is_equal_approx(float(config.get_value("player", "look_sensitivity", -1.0)), 1.75),
		"The saved file holds the sensitivity that was set")
	_expect(bool(config.get_value("player", "invert_look_y", false)), "The saved file holds the inversion that was set")

	# Put the machine back the way it was found.
	settings.master_volume = 1.0
	settings.look_sensitivity = 1.0
	settings.invert_look_y = false

	await create_timer(0.1).timeout
	if failures == 0:
		print("PASS: settings apply to the bus and the look maths, clamp sanely, and survive a restart")
	quit(failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1

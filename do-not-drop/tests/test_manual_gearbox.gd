extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_manual_gearbox.gd
##
## The old manual van (tareas de Nacho N-114): a truck variant ("vintage",
## vehicle.gd VARIANTS) with a five-gear manual box (vehicle_gearbox.gd) the
## driver changes by hand, paid better as compensation.
##   - the gearbox rules on their own: gears stay in 1..5, a shift takes the
##     clutch time during which a second one is refused, each gear pulls up to
##     its own limit and no further, low gears pull harder, a high gear lugs at
##     a crawl, an over-fast downshift brakes, and an automatic box does nothing;
##   - on real physics frames: stuck in first the van tops out at that gear's
##     limit, shifting up frees it gear by gear to the van's top speed, a
##     downshift at speed slows it down, and the gear resets to first when the
##     run is over;
##   - the classic and the agile are automatic: no gear, no shifts, their
##     numbers untouched (test_vehicle_handling.gd keeps measuring them);
##   - the engine sound follows the driver's gear (vehicle_presentation.gd);
##   - the driver's input: the two shift actions exist with a key and a
##     bumper each, and are rebindable in Options (game_settings.gd);
##   - the compensation: unlocked by deliveries and score like every truck, and
##     the payout (CrewProgression.award_delivery) is multiplied, with the bonus
##     shown separately; the ordinary trucks pay as before.

const Gearbox = preload("res://scripts/gameplay/vehicle/vehicle_gearbox.gd")
const UnlockScript = preload("res://scripts/core/unlock_manager.gd")
const TOP_KMH: float = 68.0
const TEST_PATH := "user://manual_gearbox_test.json"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_rules()
	await _check_physics()
	await _check_automatic_trucks()
	await _check_engine_follows_gear()
	_check_input()
	await _check_network_contract()
	await _check_hud()
	await _check_look()
	await _check_unlock_and_pay()
	if _failures == 0:
		print("PASS: the manual van shifts by hand, pays more, and leaves the automatic trucks alone")
	quit(_failures)


## The box alone, no truck.
func _check_rules() -> void:
	var box := Gearbox.new()
	_expect(not box.request_shift(1), "An automatic box refuses to shift")
	_expect(is_equal_approx(box.drive_multiplier(10.0, TOP_KMH), 1.0) and box.engine_brake(200.0, TOP_KMH) == 0.0,
			"An automatic box changes nothing about pull or braking")
	box.enabled = true
	_expect(box.gear == 1, "It starts in first")
	_expect(not box.request_shift(-1) and box.gear == 1, "Cannot go below first")
	var seen: Array[int] = []
	box.gear_changed.connect(func(new_gear: int) -> void: seen.append(new_gear))
	_expect(box.request_shift(1) and box.gear == 2, "One gear up")
	_expect(box.request_shift(1) and box.gear == 2,
			"A second request inside the clutch time waits in the queue: the gear holds")
	box.tick(Gearbox.SHIFT_SECONDS + 0.01)
	_expect(box.gear == 3, "...and is applied the moment the clutch is out (got %d)" % box.gear)
	_expect(box.shift_left > 0.0, "...which puts the clutch in again")
	box.tick(1.0)
	_expect(box.gear == 3, "An empty queue shifts nothing")
	# The queue holds one: two presses in the window end two gears up; a third
	# replaces the waiting one instead of stacking.
	box.reset()
	box.request_shift(1)
	box.request_shift(1)
	box.tick(Gearbox.SHIFT_SECONDS + 0.01)
	_expect(box.gear == 3, "Two quick +1 presses end two gears up (got %d)" % box.gear)
	box.request_shift(1)
	box.request_shift(1)
	box.request_shift(-1)
	box.tick(Gearbox.SHIFT_SECONDS + 0.01)
	_expect(box.gear == 2, "A newer request replaces the waiting one, never stacking (got %d)" % box.gear)
	box.tick(1.0)
	box.reset()
	box.request_shift(1)
	box.request_shift(1)
	box.reset()
	box.tick(1.0)
	_expect(box.gear == 1, "reset() drops a waiting shift")
	box.gear = 3
	for step: int in range(6):
		box.tick(1.0)
		box.request_shift(1)
	_expect(box.gear == Gearbox.TOP_GEAR, "Cannot go past fifth (got %d)" % box.gear)
	box.tick(1.0)
	_expect(box.request_shift(-1) and box.gear == 4, "One gear down")
	_expect(seen.size() >= 4 and seen[0] == 2, "It announces each change of gear (got %s)" % str(seen))
	box.tick(1.0)
	_expect(box.request_shift(0) == false, "Shift 0 does nothing")

	# Pull: each gear up to its limit, and not a km/h beyond.
	box.reset()
	for gear: int in range(Gearbox.FIRST_GEAR, Gearbox.TOP_GEAR + 1):
		box.gear = gear
		var cap: float = Gearbox.gear_cap_kmh(gear, TOP_KMH)
		_expect(box.drive_multiplier(cap * 0.9, TOP_KMH) > 0.0, "Gear %d pulls just under its limit" % gear)
		_expect(box.drive_multiplier(cap + 0.1, TOP_KMH) == 0.0,
				"Gear %d stops pulling at its limit (%.1f km/h)" % [gear, cap])
		if gear > Gearbox.FIRST_GEAR:
			_expect(cap > Gearbox.gear_cap_kmh(gear - 1, TOP_KMH), "Gear %d goes faster than the one below" % gear)
	_expect(is_equal_approx(Gearbox.gear_cap_kmh(Gearbox.TOP_GEAR, TOP_KMH), TOP_KMH),
			"Fifth reaches the van's top speed")
	box.gear = 1
	var first_pull: float = box.drive_multiplier(3.0, TOP_KMH)
	box.gear = 5
	_expect(first_pull > box.drive_multiplier(40.0, TOP_KMH), "First pulls harder than fifth at cruising speed")
	_expect(box.drive_multiplier(0.0, TOP_KMH) < 0.5 * first_pull, "Fifth from a standstill lugs: far weaker")
	_expect(box.drive_multiplier(0.0, TOP_KMH) > 0.0, "...but it never stalls")
	box.gear = 2
	var second_cap: float = Gearbox.gear_cap_kmh(2, TOP_KMH)
	_expect(box.engine_brake(second_cap - 1.0, TOP_KMH) == 0.0, "No engine braking under the limit")
	_expect(box.engine_brake(second_cap + 30.0, TOP_KMH) > 5.0, "A downshift taken too fast brakes the van")
	_expect(box.engine_brake(500.0, TOP_KMH) <= Gearbox.ENGINE_BRAKE_CEILING, "Engine braking has a ceiling")
	_expect(box.at_limit(second_cap, TOP_KMH), "At the top of a gear the driver is told to shift up")
	_expect(not box.at_limit(5.0, TOP_KMH), "...and not at a crawl")
	_expect(Gearbox.gear_for_speed(0.0, TOP_KMH) == 1 and Gearbox.gear_for_speed(TOP_KMH, TOP_KMH) == 5,
			"The gear for a speed runs from first to fifth")
	box.reset()
	_expect(box.gear == 1 and box.shift_left == 0.0, "reset() goes back to first with the clutch out")
	box.free()


func _world(variant: StringName) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1200.0, 1.0, 1200.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	world.add_child(ground)
	var van: VehicleBody3D = _new_van()
	van.set(&"variant_id", variant)
	van.position = Vector3(0.0, 0.8, 500.0)
	world.add_child(van)
	van.set(&"controls_enabled", false)
	for tick: int in range(40):
		await physics_frame
	return {"world": world, "van": van}


func _drive(van: VehicleBody3D, seconds: float, throttle: float = 1.0) -> void:
	for tick: int in range(roundi(seconds * Engine.physics_ticks_per_second)):
		van.call(&"set_controls", throttle, 0.0, false)
		await physics_frame


func _set_running(running: bool) -> void:
	root.get_node(^"/root/RunManager").set(&"is_running", running)


## Real frames, the vintage van: limits, shifting through, downshift, reset.
func _check_physics() -> void:
	_set_running(true)
	var setup: Dictionary = await _world(&"vintage")
	var van: VehicleBody3D = setup.van
	var box: Node = van.get(&"gearbox")
	_expect(bool(van.call(&"has_manual_gearbox")) and bool(box.get(&"enabled")),
			"The vintage variant turns the gearbox on")
	_expect(is_equal_approx(float(van.get(&"maximum_speed_kmh")), TOP_KMH),
			"The vintage tops out at %d km/h" % int(TOP_KMH))
	_expect(van.call(&"gear_text") == "1", "It starts in first (got '%s')" % van.call(&"gear_text"))

	await _drive(van, 7.0)
	var first_cap: float = Gearbox.gear_cap_kmh(1, TOP_KMH)
	var speed: float = van.get(&"speed_kmh")
	_expect(speed > first_cap * 0.6, "In first it gets going (%.1f km/h)" % speed)
	_expect(speed < first_cap * 1.25,
			"In first it tops out near the gear's limit %.1f, not past it (%.1f km/h)" % [first_cap, speed])
	var first_gear_speed: float = speed

	# Shift up as a driver would: when the gear is spent, through to fifth.
	var reached: Array[int] = [1]
	for tick: int in range(roundi(45.0 * Engine.physics_ticks_per_second)):
		van.call(&"set_controls", 1.0, 0.0, false)
		if box.call(&"at_limit", van.get(&"speed_kmh"), TOP_KMH):
			van.call(&"request_gear_shift", 1)
		if int(box.get(&"gear")) != reached[-1]:
			reached.append(int(box.get(&"gear")))
		await physics_frame
	speed = van.get(&"speed_kmh")
	print("GEARBOX vintage: first gear tops at %.1f km/h, fifth reaches %.1f km/h after 45 s of shifting" % [
			first_gear_speed, speed])
	_expect(reached == [1, 2, 3, 4, 5], "It went up through every gear in order (got %s)" % str(reached))
	_expect(speed > TOP_KMH * 0.9 and speed < TOP_KMH * 1.1,
			"In fifth it reaches the van's top speed (%.1f of %.0f km/h)" % [speed, TOP_KMH])

	# A downshift at speed: the engine holds the van back.
	while int(box.get(&"gear")) > 2:
		await _drive(van, 0.4, 0.0)
		van.call(&"request_gear_shift", -1)
	var before: float = van.get(&"speed_kmh")
	await _drive(van, 0.4, 0.0)
	var after: float = van.get(&"speed_kmh")
	_expect(after < before - 1.0,
			"Downshifting at speed slows the van with the engine (%.1f -> %.1f km/h)" % [before, after])

	# Shifting takes the clutch: no pull while it is in.
	await _drive(van, 1.0, 0.0)
	van.call(&"request_gear_shift", 1)
	_expect(float(box.get(&"shift_left")) > 0.0, "A shift puts the clutch in")
	_expect(is_zero_approx(van.engine_force), "...and the van isn't pulling while it is in")
	await _drive(van, 0.1, 1.0)
	_expect(is_zero_approx(van.engine_force), "Still no pull 0.1 s into the shift (engine %.0f)" % van.engine_force)
	await _drive(van, 0.4, 1.0)
	_expect(van.engine_force < -1.0, "Pulls again once the clutch is out (engine %.0f)" % van.engine_force)

	# Reverse isn't a gear: brake from a standstill and it backs up.
	setup.world.free()
	setup = await _world(&"vintage")
	van = setup.van
	await _drive(van, 2.5, -1.0)
	_expect(van.linear_velocity.dot(van.global_basis.z) > 1.0, "Braking from a standstill backs the van up")
	_expect(van.call(&"gear_text") == "R", "...and the readout says R (got '%s')" % van.call(&"gear_text"))

	# The end of a run puts the gear back to first.
	box = van.get(&"gearbox")
	box.set(&"gear", 4)
	_set_running(false)
	await physics_frame
	await physics_frame
	_expect(int(box.get(&"gear")) == 1,
			"With no run going the gearbox is back in first (got %d)" % int(box.get(&"gear")))
	setup.world.free()


## The ordinary trucks have no gears at all.
func _check_automatic_trucks() -> void:
	_set_running(true)
	for variant: StringName in [&"classic", &"agile"]:
		var setup: Dictionary = await _world(variant)
		var van: VehicleBody3D = setup.van
		var box: Node = van.get(&"gearbox")
		_expect(not bool(van.call(&"has_manual_gearbox")) and not bool(box.get(&"enabled")),
				"%s has no manual gearbox" % variant)
		van.call(&"request_gear_shift", 1)
		_expect(int(box.get(&"gear")) == 1, "%s ignores a shift request" % variant)
		_expect(van.call(&"gear_text") == "", "%s shows no gear" % variant)
		await _drive(van, 3.0)
		var speed: float = van.get(&"speed_kmh")
		_expect(speed > 40.0, "%s picks up speed with no gear to shift (%.1f km/h)" % [variant, speed])
		setup.world.free()
	_set_running(false)


## The rev counter reads the driver's gear, each with its own revs.
func _check_engine_follows_gear() -> void:
	_set_running(true)
	var setup: Dictionary = await _world(&"vintage")
	var van: VehicleBody3D = setup.van
	var visual: Node = van.get_node(^"VehiclePresentation")
	var box: Node = van.get(&"gearbox")
	visual.set(&"engine_gear", 0)
	visual.set(&"shift_remaining", 0.0)
	visual.set(&"engine_rpm", 0.0)
	visual.call(&"update_rev_counter", 0.016, 15.0, 0.5)
	_expect(int(visual.get(&"engine_gear")) == 0, "In first the rev counter is in first")
	for tick: int in range(60):
		visual.call(&"update_rev_counter", 0.016, 15.0, 0.5)
	var revs_in_first: float = float(visual.get(&"engine_rpm"))
	box.set(&"gear", 3)
	visual.call(&"update_rev_counter", 0.016, 15.0, 0.5)
	var shown_gear: int = int(visual.get(&"engine_gear")) + 1
	_expect(shown_gear == 3, "After the driver's shift to third the rev counter is in third (got %d)" % shown_gear)
	_expect(float(visual.get(&"shift_remaining")) > 0.0, "The change drops the revs for a moment, like the clutch")
	for tick: int in range(90):
		visual.call(&"update_rev_counter", 0.016, 15.0, 0.5)
	var revs_in_third: float = float(visual.get(&"engine_rpm"))
	_expect(revs_in_third < revs_in_first - 300.0,
			"The same speed in a higher gear sounds lower: %.0f rpm in first, %.0f in third" % [
			revs_in_first, revs_in_third])
	# The automatic trucks keep shifting for themselves.
	setup.world.free()
	var classic: Dictionary = await _world(&"classic")
	var classic_visual: Node = (classic.van as Node).get_node(^"VehiclePresentation")
	for tick: int in range(200):
		classic_visual.call(&"update_rev_counter", 0.016, 70.0, 1.0)
	_expect(int(classic_visual.get(&"engine_gear")) > 0, "The classic's rev counter still changes gear by itself")
	classic.world.free()
	_set_running(false)


func _check_input() -> void:
	for action: StringName in [&"drive_shift_up", &"drive_shift_down"]:
		_expect(InputMap.has_action(action), "%s is an input action" % action)
		var has_key: bool = false
		var has_button: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			has_key = has_key or event is InputEventKey
			has_button = has_button or event is InputEventJoypadButton
		_expect(has_key and has_button, "%s has a key and a gamepad button" % action)
	var settings: Node = root.get_node(^"/root/GameSettings")
	for action: StringName in [&"drive_shift_up", &"drive_shift_down"]:
		_expect(action in settings.REBINDABLE_ACTIONS, "%s is rebindable in Options" % action)
		_expect(settings.DEFAULT_KEY_BINDINGS.has(action), "%s has a default key" % action)
	var up_buttons: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(&"drive_shift_up"):
		if event is InputEventJoypadButton:
			up_buttons.append((event as InputEventJoypadButton).button_index)
	_expect(up_buttons == [JOY_BUTTON_RIGHT_SHOULDER], "Shift up is the right bumper (got %s)" % str(up_buttons))
	var input_script: Script = load("res://scripts/gameplay/vehicle/vehicle_input_component.gd")
	_expect(input_script.source_code.contains("drive_shift_up")
			and input_script.source_code.contains("request_gear_shift"),
			"The driver's input component sends the shifts to the host")


## What goes over the wire: the gear is replicated on spawn and on change, and
## the shift request only takes a +1 or -1 from the truck's host.
func _check_network_contract() -> void:
	var van: VehicleBody3D = _new_van()
	var config: SceneReplicationConfig = null
	for child: Node in van.get_children():
		if child is MultiplayerSynchronizer:
			config = (child as MultiplayerSynchronizer).replication_config
	_expect(config != null, "The truck has its synchronizer")
	if config != null:
		var gear_path := NodePath("Gearbox:gear")
		_expect(gear_path in config.get_properties(), "Gearbox:gear is in the truck's replication config")
		_expect(config.property_get_spawn(gear_path),
				"...sent with the spawn, so a late joiner starts in the right gear")
		_expect(config.property_get_replication_mode(gear_path) == SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE,
				"...and on change, not every tick")
	van.free()

	_set_running(true)
	var setup: Dictionary = await _world(&"vintage")
	var vintage: VehicleBody3D = setup.van
	var box: Node = vintage.get(&"gearbox")
	vintage.call(&"request_gear_shift", 2)
	_expect(int(box.get(&"gear")) == 1, "A request for 2 gears at once is refused")
	vintage.call(&"request_gear_shift", 0)
	vintage.call(&"request_gear_shift", -7)
	_expect(int(box.get(&"gear")) == 1, "...and so are 0 and -7")
	vintage.call(&"request_gear_shift", 1)
	_expect(int(box.get(&"gear")) == 2, "+1 is taken")
	var source: String = _vehicle_script().source_code
	_expect(source.contains("sender_id != 0 and sender_id != driver_peer_id"),
			"The request compares the sender with the driver explicitly (nobody at the wheel lets no remote through)")
	_expect(source.contains("absi(direction) != 1"), "The request checks the direction itself")
	setup.world.free()
	_set_running(false)


## The HUD shows a shift at once, not with the next telemetry.
func _check_hud() -> void:
	_set_running(true)
	var setup: Dictionary = await _world(&"vintage")
	var van: VehicleBody3D = setup.van
	var hud: CanvasLayer = _new_hud()
	root.add_child(hud)
	await process_frame
	await process_frame
	var cargo: Node = hud.get(&"cargo")
	var label: Label = cargo.get(&"gear_label")
	_expect(label != null and label.visible, "A manual truck in the level gets its gear drawn without telemetry")
	_expect(label.text.contains("1"), "It starts in first (%s)" % label.text)
	var box: Node = van.get(&"gearbox")
	box.set(&"gear", 3)
	_expect(label.text.contains("3"), "A change of gear shows at once (%s)" % label.text)
	box.set(&"gear", 2)
	_expect(label.text.contains("2"), "...every time (%s)" % label.text)
	var shift_label: Label = cargo.get(&"shift_up_label")
	_expect(not shift_label.visible, "No shift-up prompt at a crawl")
	root.get_node(^"/root/EventBus").emit_signal(&"vehicle_telemetry", Gearbox.gear_cap_kmh(2, TOP_KMH))
	_expect(shift_label.visible and not shift_label.text.is_empty(),
			"At the top of the gear the big prompt shows (%s)" % shift_label.text)
	_expect(shift_label.get_theme_font_size("font_size") >= 24, "...in a big size")
	box.set(&"gear", 3)
	_expect(not shift_label.visible, "...and goes once the gear changes")
	hud.free()
	setup.world.free()
	# An automatic truck draws nothing.
	var plain: Dictionary = await _world(&"classic")
	var hud_plain: CanvasLayer = _new_hud()
	root.add_child(hud_plain)
	await process_frame
	await process_frame
	root.get_node(^"/root/EventBus").emit_signal(&"vehicle_telemetry", 30.0)
	_expect(hud_plain.get(&"cargo").get(&"gear_label") == null, "The classic's HUD has no gear readout")
	hud_plain.free()
	plain.world.free()
	_set_running(false)


## The old van looks like one, and its keys read as arrows.
func _check_look() -> void:
	var settings: Node = root.get_node(^"/root/GameSettings")
	_expect(settings.binding_label(&"drive_shift_up") == "↑" and settings.binding_label(&"drive_shift_down") == "↓",
			"The gear keys read as arrows, not as 'Up' and 'Down'")
	_expect(settings.binding_label(&"drive_horn") == "H", "Other keys keep their name")
	var colours: Dictionary = {}
	for variant: StringName in [&"classic", &"agile", &"vintage"]:
		var setup: Dictionary = await _world(variant)
		var reference: Node = (setup.van as Node).get_node(^"ReferenceTruck")
		var body: BaseMaterial3D = reference.get(&"_paint_materials")["DT_White"]
		colours[variant] = body.albedo_color
		var has_chrome: bool = (setup.van as Node).get_node_or_null(^"BodyVisuals/RetroChrome") != null
		_expect(has_chrome == (variant == &"vintage"),
				"%s %s the retro chrome" % [variant, "has" if has_chrome else "has no"])
		if variant == &"vintage":
			var van: Node = setup.van
			van.set(&"paint_id", &"violet")
			_expect(body.albedo_color.is_equal_approx(Color("7b52b9")),
					"A paint the crew picked still wins over the factory cream")
			van.set(&"paint_id", &"white")
			_expect(body.albedo_color.is_equal_approx(colours[variant]), "...and white gives the factory cream back")
			van.set(&"variant_id", &"classic")
			_expect(van.get_node_or_null(^"BodyVisuals/RetroChrome") == null,
					"Leaving the old van takes the chrome off")
		setup.world.free()
	var classic: Color = colours[&"classic"]
	var vintage: Color = colours[&"vintage"]
	_expect(classic.is_equal_approx(colours[&"agile"]), "The classic and the agile share the white body")
	var distance: float = absf(vintage.h - classic.h) + absf(vintage.s - classic.s)
	_expect(vintage.s > 0.2 and distance > 0.15,
			"The old van's body is a clearly different colour (%s)" % vintage)


func _check_unlock_and_pay() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	var profile := UnlockScript.new()
	profile.storage_path = TEST_PATH
	profile.reset_profile()
	_expect(not profile.is_unlocked(&"vintage_van"), "The old van starts locked")
	_expect(not profile.select_truck(&"vintage"), "A locked truck can't be picked")
	var listed: bool = false
	for choice: Dictionary in profile.truck_choices():
		if choice["id"] == &"vintage":
			listed = true
			_expect(not bool(choice["available"]), "The depot lists the old van as not available yet")
			_expect(String(choice["title"]) == "UI_TRUCK_VINTAGE" and String(choice["detail"]) == "UI_TRUCK_MANUAL",
					"The depot row names the van and says what it gives (manual gears, more pay)")
	_expect(listed, "The depot lists the old van among the trucks")
	for run: int in range(5):
		profile.record_run(120, {"delivered": true})
	_expect(not profile.is_unlocked(&"vintage_van"), "Five deliveries and 600 points are not enough")
	profile.record_run(0, {"delivered": true})
	_expect(profile.is_unlocked(&"vintage_van"), "Six deliveries and 550 points unlock the old van")
	_expect(profile.select_truck(&"vintage") and profile.selected_truck == &"vintage", "...and it can be picked")
	_expect(not profile.has_method(&"selected_truck_pay_multiplier"),
			"The profile no longer keeps a second copy of the pay multiplier")
	var restored := UnlockScript.new()
	restored.storage_path = TEST_PATH
	restored.load_profile()
	_expect(restored.is_unlocked(&"vintage_van"), "The unlock survives a save and load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	profile.free()
	restored.free()

	# The payout's multiplier is the truck on the road's (Vehicle.VARIANTS, the
	# one source), not anything in the results dictionary or the profile.
	var crew: Node = root.get_node(^"/root/CrewProgression")
	crew.call(&"reset_campaign")
	var start_money: int = int(crew.get(&"team_money"))
	var ordinary: Dictionary = {"cargo_points": 100, "delivery_points": 150}
	crew.call(&"award_delivery", ordinary, [1])
	_expect(int(ordinary["payout"]) == 250 and int(ordinary["pay_bonus"]) == 0,
			"With no truck in the level the pay is doors + cargo, no bonus")
	var classic: Dictionary = await _world(&"classic")
	var classic_results: Dictionary = {"cargo_points": 100, "delivery_points": 150}
	crew.call(&"award_delivery", classic_results, [1])
	_expect(int(classic_results["payout"]) == 250 and int(classic_results["pay_bonus"]) == 0,
			"An ordinary truck pays doors + cargo, no bonus")
	classic.world.free()
	var vintage: Dictionary = await _world(&"vintage")
	var variants: Dictionary = _vehicle_script().get_script_constant_map()["VARIANTS"]
	var expected: float = float(variants[&"vintage"]["pay_multiplier"])
	_expect(is_equal_approx(float(vintage.van.call(&"pay_multiplier")), expected),
			"The truck answers with its variant's multiplier")
	var old_van: Dictionary = {"cargo_points": 100, "delivery_points": 150, "score": 250}
	crew.call(&"award_delivery", old_van, [1])
	_expect(int(old_van["payout"]) == 313 and int(old_van["pay_bonus"]) == 63,
			"The old van pays 25 percent more: 250 -> 313 (got %d, bonus %d)" % [
			int(old_van["payout"]), int(old_van["pay_bonus"])])
	_expect(int(old_van["score"]) == 250, "The score is the same: the compensation is money, not points")
	_expect(int(crew.get(&"team_money")) == start_money + 250 + 250 + 313, "The bonus reaches the team's wallet")
	var claimed: Dictionary = {"cargo_points": 100, "delivery_points": 0, "pay_multiplier": 9.0}
	crew.call(&"award_delivery", claimed, [1])
	_expect(int(claimed["payout"]) == 125,
			"A multiplier already in the results is not believed (got %d)" % int(claimed["payout"]))
	var endless: Dictionary = {"distance_traveled": 500.0}
	crew.call(&"award_delivery", endless, [1])
	_expect(int(endless["payout"]) == 0, "No doors or cargo, no payout, multiplier or not")
	vintage.world.free()
	crew.call(&"reset_campaign")


## Loaded at run time: they name the autoloads, which are not up while this compiles.
func _new_van() -> VehicleBody3D:
	return (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D


func _new_hud() -> CanvasLayer:
	return load("res://scripts/ui/hud/hud.gd").new()


func _vehicle_script() -> GDScript:
	return load("res://scripts/gameplay/vehicle/vehicle.gd") as GDScript


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

extends SceneTree
## Run WITHOUT --headless (it checks what gets drawn):
##   <godot> --path do-not-drop --script res://tests/check_interpolation.gd
##
## Physics interpolation (project.godot) was tried once before and dropped
## (docs/colaboracion-equipo.md, 2026-09-24): the parked, frozen truck sent
## its wheels to the world origin, door animations didn't show and a box set
## on the rack vanished. This checks exactly those, comparing where each thing
## is DRAWN (get_global_transform_interpolated) with where it really is:
##   - wheels stay on their axles while the truck is frozen (see the "parked"
##     shot; vehicle.gd keeps a frozen truck out of interpolation for this),
##     and when driving;
##   - a door swing is drawn frame by frame, not skipped;
##   - a box mounted on the rack is drawn on the rack;
##   - the seated driver's view moves every frame at speed.
## Also saves user://check_interpolation_*.png to look at.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("check_interpolation needs a rendering display; omit --headless.")
		quit(2)
		return
	if "--no-interpolation" in OS.get_cmdline_user_args():
		physics_interpolation = false  # For comparison shots only.
	else:
		_expect(physics_interpolation, "Physics interpolation is on for this project")
	root.get_node(^"/root/NetworkManager").set(&"world_seed", 4242)
	var level: Node3D = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	var van: VehicleBody3D = level.vehicle
	for _i: int in range(10):
		await process_frame

	# 1. Parked and frozen: wheels drawn on the truck, not at the origin.
	_expect(van.freeze, "The truck starts parked (frozen)")
	for _i: int in range(20):
		await process_frame
		_check_wheels(van, "parked")
	# The wheel bug lives in the renderer (the nodes themselves are fine), so
	# no API call sees it -- look at the "parked" shot. What can be checked is
	# the workaround: a frozen truck stays out of interpolation.
	_expect(van.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF or not physics_interpolation, "A frozen truck is kept out of interpolation (its wheels vanish otherwise)")
	var outside := Camera3D.new()
	level.add_child(outside)
	level.get_node(^"HUD").hide()
	# Right front quarter: the cab door that swings below, and both right wheels.
	outside.global_position = van.global_transform * Vector3(6.0, 1.8, -5.0)
	outside.look_at(van.global_transform * Vector3(0.8, 0.7, -0.5))
	outside.make_current()
	outside.reset_physics_interpolation()
	await _shot("parked")

	# 2. A door swing is drawn while it happens.
	var hinge: Node3D = van.find_child("CabDoor_Right_HINGE_Z", true, false) as Node3D
	_expect(hinge != null, "Found the right cab door hinge")
	if hinge != null:
		var drawn: Array[Basis] = []
		var worst: float = 0.0
		van.call(&"set_door_open", &"cab_right", true)
		for _i: int in range(40):
			await process_frame
			var shown: Basis = hinge.get_global_transform_interpolated().basis
			drawn.append(shown)
			worst = maxf(worst, (shown.z - hinge.global_basis.z).length())
		var distinct: int = 0
		for index: int in range(1, drawn.size()):
			if not drawn[index].is_equal_approx(drawn[index - 1]):
				distinct += 1
		_expect(distinct >= 8, "The door swing is drawn over many frames (%d distinct poses)" % distinct)
		_expect(worst < 0.25, "The drawn door stays with the real one (%.3f off)" % worst)
		await _shot("door_open")
		van.call(&"set_door_open", &"cab_right", false)
		level.get_node(^"HUD").show()

	# 3. A box put on the rack is drawn on the rack.
	level.call(&"start_debug_delivery")
	for _i: int in range(3):
		await process_frame
	var mounted: Node3D = null
	for package: Node in level.get(&"packages"):
		if is_instance_valid(package) and package.get(&"is_loaded"):
			mounted = package as Node3D
	_expect(mounted != null, "The debug start mounted a box")
	if mounted != null:
		for _i: int in range(10):
			await process_frame
			var off: float = mounted.get_global_transform_interpolated().origin.distance_to(mounted.global_position)
			_expect(off < 0.05, "The mounted box is drawn where it is (%.3f m off)" % off)
			var visible_meshes: int = 0
			for mesh: Node in mounted.find_children("*", "MeshInstance3D", true, false):
				if (mesh as MeshInstance3D).is_visible_in_tree():
					visible_meshes += 1
			_expect(visible_meshes > 0, "The mounted box is visible")

	# 4. Driving: wheels still on the truck, and the view advances every frame.
	van.get_node(^"VehicleInputComponent").set_physics_process(false)
	await physics_frame
	await physics_frame
	_expect(van.freeze or van.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_INHERIT, "Released, the truck is interpolated again")
	var still: int = 0
	var frames: int = 0
	var last: Vector3 = Vector3.INF
	for _i: int in range(360):
		van.call(&"set_controls", 1.0, 0.0, false)
		await process_frame
		_check_wheels(van, "driving")
		var camera: Camera3D = root.get_viewport().get_camera_3d()
		if van.linear_velocity.length() > 8.0 and camera != null:
			var at: Vector3 = camera.get_global_transform_interpolated().origin
			if last != Vector3.INF:
				frames += 1
				if at.distance_to(last) < 0.001:
					still += 1
			last = at
	_expect(frames > 30 and still * 10 < frames, "At speed the driver's view moves every frame (%d still of %d)" % [still, frames])
	await _shot("driving")

	if _failures == 0:
		print("PASS: interpolation draws the parked wheels, door swings, mounted boxes and the moving view where they really are")
	quit(_failures)


var _wheel_failures_reported: int = 0


func _check_wheels(van: VehicleBody3D, context: String) -> void:
	var body: Vector3 = van.get_global_transform_interpolated().origin
	for wheel: Node in van.get_children():
		if not wheel is VehicleWheel3D:
			continue
		for part: Node in [wheel] + wheel.find_children("*", "MeshInstance3D", true, false):
			var distance: float = (part as Node3D).get_global_transform_interpolated().origin.distance_to(body)
			if distance > 4.0 and _wheel_failures_reported < 5:
				_wheel_failures_reported += 1
				_expect(false, "%s: %s is drawn %.1f m away from the truck" % [context, part.name, distance])


func _shot(label: String) -> void:
	for _i: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var suffix: String = "_off" if not physics_interpolation else ""
	var path: String = "user://check_interpolation_%s%s.png" % [label, suffix]
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

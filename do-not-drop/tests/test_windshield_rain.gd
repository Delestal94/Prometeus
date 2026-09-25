extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_windshield_rain.gd
##
## Rain on the windshield (N-303, windshield_rain.gd, windshield_rain.gdshader):
## - the truck carries a copy of its windshield, with UVs across and up the
##   glass, facing into the cab (so from outside it's culled);
## - it's shown only while it rains and the camera is inside the truck;
## - with the engine running in the rain the two wipers sweep, in step, from
##   the same clock the shader clears the drops with, and at rest they lie
##   flat, side by side (never crossing) and within the glass.

const SHADER: Shader = preload("res://shaders/windshield_rain.gdshader")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 4242)
	network.set(&"world_house_count", 1)
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	var van: VehicleBody3D = level.get(&"vehicle")
	var rain := van.find_child("WindshieldRain", true, false) as WindshieldRain
	_expect(rain != null, "The truck has rain for its windshield")
	if rain == null:
		quit(_failures)
		return
	var mesh: Mesh = rain.overlay.mesh
	_expect(mesh != null and mesh.get_faces().size() >= 6, "The overlay is the windshield's shape (%d vertices)" % (mesh.get_faces().size() if mesh != null else 0))
	var arrays: Array = mesh.surface_get_arrays(0)
	var uv_low := Vector2(INF, INF)
	var uv_high := Vector2(-INF, -INF)
	for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array:
		uv_low = uv_low.min(uv)
		uv_high = uv_high.max(uv)
	_expect(uv_low.x < 0.1 and uv_high.x > 0.9 and uv_low.y < 0.1 and uv_high.y > 0.9, "UVs span the glass (%s - %s)" % [uv_low, uv_high])
	var into_cab: Vector3 = van.global_basis.inverse() * (rain.global_basis.z)
	_expect(into_cab.z > 0.5, "It faces into the cab, behind the glass (normal %s in the truck's space)" % into_cab)
	_expect(rain.width > 1.2 and rain.height > 0.5, "It measures a windshield (%.2f x %.2f m)" % [rain.width, rain.height])

	var seat: Camera3D = null
	for camera: Camera3D in van.get_node(^"VehiclePresentation").get(&"_seat_cameras"):
		seat = camera
		break
	var outside := Camera3D.new()
	level.add_child(outside)
	outside.global_position = van.to_global(Vector3(0.0, 2.0, -9.0))
	WorldMood.active["rain"] = false
	if seat != null:
		seat.make_current()
	await process_frame
	_expect(not rain.overlay.visible, "Dry weather: no drops")
	WorldMood.active["rain"] = true
	await process_frame
	_expect(rain.overlay.visible, "Rain, from a seat: the drops show")
	outside.make_current()
	await process_frame
	_expect(not rain.overlay.visible, "Rain, from outside the truck: nothing drawn")

	# A tandem pair: at rest both lie the same way, the first parked short
	# of the second's pivot and the second short of the glass's edge -- they
	# never cross (the first version's pair met in an X in the middle).
	var reach: float = WindshieldRain.BLADE_REACH * rain.height
	var first_tip: float = (WindshieldRain.PIVOTS[0] - 0.5) * rain.width + reach
	var second_pivot: float = (WindshieldRain.PIVOTS[1] - 0.5) * rain.width
	var second_tip: float = second_pivot + reach
	_expect(first_tip < second_pivot and second_tip < rain.width * 0.5,
		"The blades rest side by side, on the glass (tips at %.2f and %.2f; second pivot %.2f; edge %.2f)" % [first_tip, second_tip, second_pivot, rain.width * 0.5])
	for arm: Node3D in rain.arms:
		_expect((arm.get_child(0) as Node3D).position.x > 0.0, "%s rests lying toward +x" % arm.name)
	# The model's own static blades are hidden: only the animated pair shows.
	var model_blades: Array[Node] = van.find_children("Wiper*", "MeshInstance3D", true, false).filter(func(node: Node) -> bool: return ReferenceTruck.is_model_wiper(node.name))
	_expect(not model_blades.is_empty() and model_blades.all(func(blade: Node) -> bool: return not (blade as MeshInstance3D).visible),
		"The truck model's static wiper blades are hidden (%d)" % model_blades.size())
	# Drops are drawn in their own pale colour, not darkened by their alpha
	# twice (they read as soot).
	_expect(not SHADER.code.contains("colour = mix(colour,"), "The drop shader doesn't blend drops into black before applying their alpha")

	# Wipers: the engine on in the rain.
	_expect(absf(rain.arms[0].rotation.z) < 0.01 and absf(rain.arms[1].rotation.z) < 0.01, "Parked, the blades rest flat")
	level.call(&"start_debug_delivery")
	outside.make_current()
	for frame: int in range(90):
		await process_frame
	var t: float = rain.wiper_time
	_expect(t > 0.5, "With the engine on in the rain, the wipers run (%.2f s)" % t)
	var angle: float = WindshieldRain.sweep_angle(t)
	_expect(is_equal_approx(rain.arms[0].rotation.z, angle) and is_equal_approx(rain.arms[1].rotation.z, angle),
		"Both blades follow the shared clock, in step (%.2f / %.2f, expected %.2f)" % [rain.arms[0].rotation.z, rain.arms[1].rotation.z, angle])
	_expect(is_equal_approx(float(rain.material.get_shader_parameter(&"wiper_time")), t), "The shader clears the glass on the same clock")
	var peak: float = 0.0
	for step: int in range(40):
		peak = maxf(peak, WindshieldRain.sweep_angle(float(step) * WindshieldRain.PERIOD / 40.0))
	_expect(absf(peak - WindshieldRain.SWEEP) < 0.05, "A stroke goes all the way up the glass (%.2f rad)" % peak)

	WorldMood.active["rain"] = false
	level.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	if _failures == 0:
		print("PASS: drops on the windshield only in the rain and only from inside, wiped by the blades' own clock")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

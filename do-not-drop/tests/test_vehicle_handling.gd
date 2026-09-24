extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_vehicle_handling.gd
## How the truck drives, in numbers (tareas de Nacho N-104), for each
## variant (vehicle.gd VARIANTS), on flat ground:
##   - 0 to 50 km/h, in seconds;
##   - braking distance from 50 km/h to a stop;
##   - turning circle radius at 20 km/h, full lock;
##   - whether it rolls taking the route's sharpest bend (a 70 degree
##     CurveSegment) at a given speed, held on the line by a driver.
## Targets (docs/parametros-diseno.md, "Manejo") are the truck as it drives
## today, measured on 2026-09-24 and kept on purpose until there's
## playtesting to argue with them: this test fails when a change moves any of
## them more than TOLERANCE, so the feel never shifts by accident. Neither
## truck rolls in the sharp bend at any speed it can reach; rolling comes from
## obstacles, and taking the bend at 45 km/h is checked every run.
## Pass -- --measure to print every number (and sweep the rollover speed up
## to 80 km/h) without checking anything.

## The sharpest bend route.gd builds: route.gd CURVE_TURN_MAX_DEG, chords
## of CurveSegment.CHORD_LENGTH every DEGREES_PER_CHORD.
const SHARP_TURN_DEG: float = 70.0
## Rolled: the roof leans more than 60 degrees off vertical.
const ROLLED_UP_Y: float = 0.5
const TOLERANCE: float = 0.1
const TARGETS: Dictionary = {
	&"classic": {"zero_to_50": 2.42, "brake_from_50": 6.4, "turn_radius_20": 14.6},
	&"agile": {"zero_to_50": 1.78, "brake_from_50": 5.6, "turn_radius_20": 12.0},
}

var _failures: int = 0
var _measuring: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_measuring = "--measure" in OS.get_cmdline_user_args()
	root.get_node(^"/root/RunManager").set(&"is_running", true)
	var results: Dictionary = {}
	for variant: StringName in [&"classic", &"agile"]:
		results[variant] = {
			"zero_to_50": await _zero_to_50(variant),
			"brake_from_50": await _brake_from_50(variant),
			"turn_radius_20": await _turn_radius(variant, 20.0),
		}
		var rolls_at: float = INF
		for kmh: float in ([35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0, 70.0, 75.0, 80.0] if _measuring else [45.0]):
			if await _rolls_in_sharp_bend(variant, kmh):
				rolls_at = kmh
				break
		results[variant]["rolls_at"] = rolls_at
		print("HANDLING %s: 0-50 %.2f s, brake from 50 %.1f m, turn radius at 20 %.1f m, rolls in the sharp bend at %s km/h" % [
			variant, results[variant].zero_to_50, results[variant].brake_from_50, results[variant].turn_radius_20,
			"never (up to 80)" if rolls_at == INF else str(rolls_at)])
	root.get_node(^"/root/RunManager").set(&"is_running", false)
	if _measuring:
		quit(0)
		return

	for variant: StringName in TARGETS:
		for key: String in TARGETS[variant]:
			var target: float = TARGETS[variant][key]
			var got: float = results[variant][key]
			_expect(absf(got - target) <= target * TOLERANCE,
				"%s %s: %.2f, target %.2f (+-%d%%)" % [variant, key, got, target, roundi(TOLERANCE * 100.0)])
		_expect(results[variant].rolls_at == INF, "%s takes the sharp bend at 45 km/h without rolling" % variant)
	_expect(results[&"agile"].zero_to_50 < results[&"classic"].zero_to_50, "The agile is quicker off the line than the classic")

	if _failures == 0:
		print("PASS: both trucks accelerate, brake, turn and hold the sharp bend as measured")
	quit(_failures)


func _world(variant: StringName) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600.0, 1.0, 600.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	world.add_child(ground)
	var van := (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	van.set(&"variant_id", variant)
	van.position = Vector3(0.0, 0.8, 200.0)
	world.add_child(van)
	van.set(&"controls_enabled", false)
	for tick: int in range(40):
		await physics_frame
	return {"world": world, "van": van}


func _zero_to_50(variant: StringName) -> float:
	var setup: Dictionary = await _world(variant)
	var van: VehicleBody3D = setup.van
	var seconds: float = 0.0
	while van.get(&"speed_kmh") < 50.0 and seconds < 20.0:
		van.call(&"set_controls", 1.0, 0.0, false)
		await physics_frame
		seconds += 1.0 / Engine.physics_ticks_per_second
	setup.world.free()
	return seconds


func _brake_from_50(variant: StringName) -> float:
	var setup: Dictionary = await _world(variant)
	var van: VehicleBody3D = setup.van
	while van.get(&"speed_kmh") < 50.0:
		van.call(&"set_controls", 1.0, 0.0, false)
		await physics_frame
	var start: Vector3 = van.global_position
	var ticks: int = 0
	while van.get(&"speed_kmh") > 0.5 and ticks < 600:
		van.call(&"set_controls", -1.0, 0.0, false)
		await physics_frame
		ticks += 1
	var distance: float = Vector2(van.global_position.x - start.x, van.global_position.z - start.z).length()
	setup.world.free()
	return distance


## Full lock at a steady speed: radius from speed over yaw rate.
func _turn_radius(variant: StringName, kmh: float) -> float:
	var setup: Dictionary = await _world(variant)
	var van: VehicleBody3D = setup.van
	var samples: Array[float] = []
	for tick: int in range(360):
		var throttle: float = 1.0 if van.get(&"speed_kmh") < kmh - 1.0 else (-0.3 if van.get(&"speed_kmh") > kmh + 1.0 else 0.2)
		van.call(&"set_controls", throttle, 1.0, false)
		await physics_frame
		if tick > 240 and absf(van.angular_velocity.y) > 0.01:
			samples.append(van.linear_velocity.length() / absf(van.angular_velocity.y))
	setup.world.free()
	var total: float = 0.0
	for radius: float in samples:
		total += radius
	return total / maxf(1.0, samples.size())


## Drives the sharp bend's circle (flat, same radius) at `kmh`, following
## the arc like a driver would, and reports whether the truck rolled.
func _rolls_in_sharp_bend(variant: StringName, kmh: float) -> bool:
	var chords: int = maxi(CurveSegment.MIN_CHORDS, roundi(SHARP_TURN_DEG / CurveSegment.DEGREES_PER_CHORD))
	var radius: float = CurveSegment.CHORD_LENGTH * chords / deg_to_rad(SHARP_TURN_DEG)
	var setup: Dictionary = await _world(variant)
	var van: VehicleBody3D = setup.van
	# Circle centre to the truck's right; it starts on the circle heading -Z.
	var centre: Vector3 = van.global_position + Vector3(radius, 0.0, 0.0)
	var rolled: bool = false
	for tick: int in range(480):
		var here: Vector3 = van.global_position
		var from_centre := Vector2(here.x - centre.x, here.z - centre.z)
		# A point ~12 m further round the circle, the way the truck is going.
		var angle: float = from_centre.angle() + 12.0 / radius
		var target := Vector3(centre.x + cos(angle) * radius, here.y, centre.z + sin(angle) * radius)
		var local: Vector3 = van.global_transform.affine_inverse() * target
		var steer: float = clampf(atan2(local.x, -local.z) * 2.2, -1.0, 1.0)
		var speed: float = van.get(&"speed_kmh")
		var throttle: float = 1.0 if speed < kmh - 1.5 else (-0.4 if speed > kmh + 2.0 else 0.4)
		van.call(&"set_controls", throttle, steer, false)
		if tick == 1:
			# Already at speed as it enters the bend (the first tick unparks it).
			van.linear_velocity = -van.global_basis.z * kmh / 3.6
		await physics_frame
		if van.global_basis.y.y < ROLLED_UP_Y:
			rolled = true
			break
	setup.world.free()
	return rolled


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

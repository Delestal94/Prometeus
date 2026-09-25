extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_start_yard.gd
##
## Leaving the depot (#170): the truck used to nose-dive and throw its loose
## cargo right past the yard, at ~15 m/s. Two causes, both measured:
## - a route could open with a hill at the door, and the yard's flat zone
##   squeezed its first 12 m into a 0 -> 27 % ramp (route.gd _plan_pick);
## - the truck's own continuous collision detection held its position still
##   for several ticks when the cargo bay floor met what rode on it, while
##   the cargo kept flying at 14 m/s -- into the bulkhead and through it
##   (vehicle.tscn: CCD is on the boxes and clutter, not the truck).
## Checked here: no route starts with a hill or a tunnel, the truck carries
## no CCD, and driving out flat out the truck doesn't pitch more than
## MAX_PITCH_RATE, with a loose box in the back staying aboard.

const MAX_PITCH_RATE: float = 20.0  # degrees a second

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var route_script: Script = load("res://scripts/gameplay/route/route.gd")
	var openers: Dictionary = {}
	for seed_value: int in range(1, 401):
		var first: Script = (route_script.call(&"plan_spine", seed_value, 2, true) as Dictionary).segments[0].script
		var name: String = first.get_global_name()
		openers[name] = int(openers.get(name, 0)) + 1
	_expect(not openers.has("HillSegment") and not openers.has("TunnelSegment"),
		"No route opens with a hill or a tunnel at the depot's door (%s)" % openers)

	var network: Node = root.get_node(^"/root/NetworkManager")
	for seed_value: int in [4242, 11]:
		network.set(&"world_seed", seed_value)
		network.set(&"world_house_count", 1)
		var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
		root.add_child(level)
		current_scene = level
		await process_frame
		await physics_frame
		var van: VehicleBody3D = level.get(&"vehicle")
		_expect(not van.continuous_cd, "The truck itself runs without CCD")
		level.call(&"start_debug_delivery")
		await physics_frame
		van.call(&"set_door_open", &"rear", false)
		# A loose box standing in the aisle of the cargo bay.
		var loose: RigidBody3D = (load("res://scenes/gameplay/package/package.tscn") as PackedScene).instantiate()
		level.add_child(loose)
		loose.global_position = van.to_global(Vector3(0.0, 0.6, 1.6))
		await physics_frame
		var worst_rate: float = 0.0
		var previous_pitch: float = van.global_basis.get_euler().x
		for tick: int in range(60 * 6):
			van.call(&"set_controls", 1.0, 0.0, false)
			await physics_frame
			var pitch: float = van.global_basis.get_euler().x
			var z: float = van.global_position.z
			# The yard edge and the first metres of road (a speed bump may follow,
			# on purpose, from ~15 m).
			if z < 4.0 and z > -12.0:
				worst_rate = maxf(worst_rate, absf(rad_to_deg(pitch - previous_pitch)) * 60.0)
			previous_pitch = pitch
			if z < -40.0:
				break
		_expect(worst_rate < MAX_PITCH_RATE, "seed %d: out of the yard the truck pitches at most %.0f°/s (%.1f)" % [seed_value, MAX_PITCH_RATE, worst_rate])
		_expect(bool(van.call(&"carries", loose.global_position, 0.3)), "seed %d: the loose box is still in the back" % seed_value)
		level.queue_free()
		await process_frame
		root.get_node(^"/root/RunManager").call(&"reset_run")
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	if _failures == 0:
		print("PASS: out of the depot the road starts level, the truck keeps its nose steady and the cargo stays aboard")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

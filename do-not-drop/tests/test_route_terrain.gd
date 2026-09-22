extends SceneTree
const Terrain = preload("res://scripts/gameplay/route/route_terrain.gd")
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func expect(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1

func _run() -> void:
	var terrain := Terrain.new()
	root.add_child(terrain)
	terrain.add_span(Vector3(0, 0, 20), Vector3(0, 0, -250))
	terrain.add_span(Vector3(0, 0, -250), Vector3(60, 0, -300), true)
	terrain.add_span(Vector3(60, 0, -300), Vector3(90, 0, -250))
	terrain.pads.append(Vector3(12, terrain.base_height(Vector2(12, -220)) - 0.08, -220))
	var before: int = Time.get_ticks_msec()
	terrain.build()
	print("Terrain fixture build: %d ms, %d tiles" % [Time.get_ticks_msec() - before, terrain.get_child_count()])
	await physics_frame
	await physics_frame
	var state := root.world_3d.direct_space_state
	# Both sides, the old box edges, tile joins, curves and former void.
	var checks: int = 0
	for z: float in [8.3, -30.01, -32.0, -32.01, -64.0, -159.7, -220.0, -250.0, -270.5]:
		for x: float in [-42.0, -32.0, -14.0, -12.0, -6.0, 0.0, 6.0, 12.0, 14.0, 32.0, 42.0]:
			var p := Vector3(x, 0.0, z)
			var height: float = terrain.height_at(p)
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, height + 3.0, z), Vector3(x, height - 3.0, z), 1)
			var hit: Dictionary = state.intersect_ray(ray)
			expect(not hit.is_empty(), "Missing collision at %s" % p)
			if not hit.is_empty():
				expect(absf(hit.position.y - height) < 0.01, "Visual/collision mismatch at %s" % p)
			checks += 1
	var lowest: float = INF
	var highest: float = -INF
	for z: int in range(-240, -140):
		var a: float = terrain.height_at(Vector3(0, 0, z))
		var b: float = terrain.height_at(Vector3(0, 0, z + 1))
		expect(absf(a - b) < 0.2, "Abrupt driving slope at %d" % z)
		lowest = minf(lowest, a)
		highest = maxf(highest, a)
	expect(highest - lowest > 1.0, "Road must have real relief")
	var wall_ray := PhysicsRayQueryParameters3D.create(Vector3(0, 24, -100), Vector3(150, 24, -100), 1)
	expect(not state.intersect_ray(wall_ray).is_empty(), "Exterior boundary must stop players before the void")
	var player: CharacterBody3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	player.position = Vector3(1, 1, 1)
	root.add_child(player)
	# Headless cannot capture the mouse. Drive the real CharacterBody physics
	# explicitly, then use the same recovery hook as the on-foot controller.
	for i: int in range(45):
		await physics_frame
		player.velocity.y -= 18.0 / 60.0
		player.move_and_slide()
		player._update_ground_safety()
	expect(player.is_on_floor(), "Player settles on the rendered terrain")
	var safe: Vector3 = player.global_position
	player.global_position.y -= 20.0
	for i: int in range(3):
		await physics_frame
		player._update_ground_safety()
	expect(player.global_position.distance_to(safe) < 1.0, "Falling player returns to their last grounded position")
	player.free()
	# Exercise actual wheel suspension across tile seams and a long climb.
	var van: VehicleBody3D = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
	van.position = Vector3(0, terrain.height_at(Vector3(0, 0, -150)) + 0.9, -150)
	root.add_child(van)
	van.controls_enabled = false
	root.get_node("RunManager").is_running = true
	var travelled: float = 0.0
	for i: int in range(900):
		van.set_controls(0.65, 0.0, false)
		await physics_frame
		var clearance: float = van.position.y - terrain.height_at(van.position)
		expect(clearance > -0.2 and clearance < 3.0, "Wheel suspension left terrain at %s" % van.position)
		expect(van.global_basis.y.dot(Vector3.UP) > 0.8, "Van destabilized on a gentle hill")
		travelled = -150.0 - van.position.z
		if travelled > 75.0:
			break
	expect(travelled > 75.0, "Van traverses the hill without getting stuck")
	root.get_node("RunManager").is_running = false
	van.free()
	terrain.free()
	await process_frame
	if failures == 0:
		print("PASS: %d terrain rays, seams, hills, boundary and on-foot recovery" % checks)
	quit(failures)

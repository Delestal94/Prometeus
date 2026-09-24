extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_flock_crossing.gd
## The flock of sheep (tareas de Nacho N-106), with the real truck: straight
## through at speed runs one over (a fine and a jolt, and the HUD says so);
## stopping short lets the whole flock amble across to the other side; a
## honk scatters it off the road.

var _failures: int = 0
var _banners: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bus: Node = root.get_node(^"/root/EventBus")
	bus.connect(&"route_event_started", func(_id: StringName, event: Dictionary) -> void: _banners.append(String(event.get("title", ""))))
	var crew: Node = root.get_node(^"/root/CrewProgression")
	var run_manager: Node = root.get_node(^"/root/RunManager")
	run_manager.set(&"is_running", true)

	# Straight through at 20 m/s, from well back: the flock starts crossing as
	# the truck comes into range and is on the road when it arrives.
	var fast := await _setup(130.0)
	if crew.has_method(&"reset_run"):
		crew.call(&"reset_run")
	var money_before: int = int(crew.get(&"team_money"))
	for tick: int in range(700):
		fast.van.set_controls(0.5, 0.0, false)
		if not fast.flock.hit:
			fast.van.linear_velocity = Vector3(0.0, fast.van.linear_velocity.y, -20.0)
		await physics_frame
		if fast.flock.hit and fast.van.global_position.z < -30.0:
			break
	_expect(fast.flock.hit, "Straight through at speed, the truck runs a sheep over")
	_expect(money_before - int(crew.get(&"team_money")) == mini(FlockCrossing.FINE, money_before), "The team pays the fine")
	_expect(_banners.any(func(title: String) -> bool: return title.contains("oveja")), "The HUD says what happened (%s)" % str(_banners))
	fast.world.free()

	# Stopped short: they all cross.
	var patient := await _setup(30.0)
	patient.van.freeze = true
	for tick: int in range(60 * 20):
		await physics_frame
		if patient.flock.state == FlockCrossing.State.DONE:
			break
	_expect(patient.flock.state == FlockCrossing.State.DONE and not patient.flock.hit, "Waiting, the whole flock crosses and nobody gets hurt")
	var all_across: bool = true
	for animal: Node3D in patient.flock.sheep:
		if animal.position.x > -FlockCrossing.ROAD_HALF_WIDTH:
			all_across = false
	_expect(all_across, "Every sheep ends up on the far side, off the road")
	patient.world.free()

	# A honk scatters them.
	var honked := await _setup(30.0)
	honked.van.freeze = true
	for tick: int in range(150):
		await physics_frame
	_expect(honked.flock.blocking_road(), "Mid-crossing, sheep are on the road")
	bus.call(&"request_horn")
	for tick: int in range(60 * 4):
		await physics_frame
	_expect(not honked.flock.blocking_road(), "A honk clears the road within a few seconds")
	honked.world.free()

	run_manager.set(&"is_running", false)
	if _failures == 0:
		print("PASS: sheep cross when you wait, scatter when you honk, and cost a fine when you plough through")
	quit(_failures)


## Ground, a flock (on the +X shoulder) at the origin and a truck `distance`
## metres before it, facing it.
func _setup(distance: float) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 400.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	world.add_child(ground)
	var flock := FlockCrossing.new()
	flock.side = 1.0
	flock.flock_seed = 12345
	world.add_child(flock)
	var van := (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	van.position = Vector3(-1.5, 0.7, distance)
	world.add_child(van)
	van.controls_enabled = false
	for tick: int in range(20):
		await physics_frame
	return {"world": world, "flock": flock, "van": van}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

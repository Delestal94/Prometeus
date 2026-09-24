extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_chasing_dog.gd
## The village dog (tareas de Nacho N-106): when the truck drives past it
## runs alongside, barking, never touching it, for up to CHASE_LENGTH metres
## and then goes home; a honk sends it home at once.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node(^"/root/RunManager").set(&"is_running", true)

	var chase := await _setup()
	var closest: float = INF
	var farthest_while_chasing: float = 0.0
	var started: bool = false
	var caught_up: bool = false
	for tick: int in range(60 * 30):
		_drive(chase.van, 8.0)
		await physics_frame
		var gap: float = ChasingDog._flat(chase.van.global_position - chase.dog.dog.global_position).length()
		if chase.dog.state == ChasingDog.State.CHASING:
			started = true
			closest = minf(closest, gap)
			# Measured once it's alongside: it notices the truck from afar.
			caught_up = caught_up or gap < 10.0
			if caught_up:
				farthest_while_chasing = maxf(farthest_while_chasing, gap)
		if started and chase.dog.state != ChasingDog.State.CHASING:
			break
	_expect(started, "The dog notices the truck going past and gives chase")
	_expect(chase.dog.barks >= 3, "It barks while it runs (%d barks)" % chase.dog.barks)
	_expect(closest > 2.5, "It never touches the truck (closest %.1f m)" % closest)
	_expect(caught_up and farthest_while_chasing < 16.0, "Once alongside, it keeps up beside the truck (at most %.1f m off)" % farthest_while_chasing)
	_expect(chase.dog.run_distance <= ChasingDog.CHASE_LENGTH + 5.0 and chase.dog.state != ChasingDog.State.CHASING,
		"It gives up after about %.0f m (ran %.0f)" % [ChasingDog.CHASE_LENGTH, chase.dog.run_distance])
	chase.world.free()

	var scared := await _setup()
	for tick: int in range(60 * 8):
		_drive(scared.van, 8.0)
		await physics_frame
		if scared.dog.state == ChasingDog.State.CHASING and scared.dog.run_distance > 10.0:
			break
	root.get_node(^"/root/EventBus").call(&"request_horn")
	_expect(scared.dog.state == ChasingDog.State.GIVING_UP, "A honk sends it home")
	scared.world.free()

	root.get_node(^"/root/RunManager").set(&"is_running", false)
	if _failures == 0:
		print("PASS: the dog chases the truck alongside, barking, without touching it, and a honk sends it home")
	quit(_failures)


## Holds a steady speed down -Z on the centre of the lane.
func _drive(van: VehicleBody3D, speed: float) -> void:
	van.set_controls(0.4, 0.0, false)
	van.linear_velocity = Vector3(0.0, van.linear_velocity.y, -speed)


func _setup() -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 800.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	world.add_child(ground)
	var dog := ChasingDog.new()
	dog.side = 1.0
	world.add_child(dog)
	var van := (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	van.position = Vector3(-1.5, 0.7, 40.0)
	world.add_child(van)
	van.controls_enabled = false
	for tick: int in range(20):
		await physics_frame
	return {"world": world, "dog": dog, "van": van}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

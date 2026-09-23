extends SceneTree

var failures := 0
var collision_events := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var manager: Node = root.get_node("RunManager")
	manager.set(&"is_running", true)
	var event_bus: Node = root.get_node("EventBus")
	event_bus.connect("package_collision", func(_a: StringName, _b: StringName, _strength: float) -> void: collision_events += 1)
	var scene := load("res://scenes/gameplay/package/package.tscn") as PackedScene
	var left := scene.instantiate() as DeliveryPackage
	var right := scene.instantiate() as DeliveryPackage
	left.package_id = &"collision_left"
	right.package_id = &"collision_right"
	left.trap_definition = load("res://data/traps/fragile.tres")
	right.trap_definition = load("res://data/traps/fragile.tres")
	left.gravity_scale = 0.0
	right.gravity_scale = 0.0
	left.spawn_grace_time = 0.0
	right.spawn_grace_time = 0.0
	left.position = Vector3(-2.0, 1.0, 0.0)
	right.position = Vector3(2.0, 1.0, 0.0)
	world.add_child(left)
	world.add_child(right)
	await physics_frame
	left.linear_velocity = Vector3(6.5, 0.0, 0.0)
	right.linear_velocity = Vector3(-6.5, 0.0, 0.0)
	var initial_integrity: float = left.integrity + right.integrity
	for i: int in 90:
		await physics_frame
	_expect(collision_events >= 2, "Un choque entre paquetes debe avisar a ambos paquetes")
	_expect(left.linear_velocity.x < 1.0 and right.linear_velocity.x > -1.0, "Las cajas deben rebotar físicamente")
	_expect(left.angular_velocity.length() > 0.05 or right.angular_velocity.length() > 0.05, "El choque debe generar giro visible")
	_expect(left.integrity + right.integrity < initial_integrity, "Un choque fuerte debe dañar cajas frágiles")
	manager.set(&"is_running", false)
	world.free()
	if failures == 0:
		print("PASS: packages collide, bounce, spin and apply chained impact damage.")
	quit(failures)

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

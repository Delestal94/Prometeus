extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_cargo_clutter.gd
## The toolbox and thermos riding in the cargo bay (cargo_clutter.gd) are
## simulated separately on every peer and never replicated (tareas de Nacho
## N-201). That is only safe while they can't change anything that is:
## - they sit on no collision layer and only look for the ground and the
##   truck, so no package or player ever touches them;
## - a client's copy of the truck is frozen and posed by the host, so that
##   client's clutter can't push the truck everyone else sees;
## - on the host they are too light to matter to the one truck that is
##   simulated, whose pose everyone then receives as is.

const PACKAGE_LAYER: int = 4
const PLAYER_LAYER: int = 8
const VEHICLE_LAYER: int = 2

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var vehicle_scene: PackedScene = load("res://scenes/gameplay/vehicle/vehicle.tscn")

	var world := Node3D.new()
	root.add_child(world)
	var host_truck: VehicleBody3D = vehicle_scene.instantiate()
	world.add_child(host_truck)
	# The clutter spawns deferred, once the level has placed the truck.
	await process_frame
	await process_frame
	var items: Array[RigidBody3D] = []
	for child: Node in world.get_children():
		if child is RigidBody3D and String(child.name).begins_with("CargoClutter"):
			items.append(child)
	_expect(items.size() == 2, "The host's truck gets its toolbox and thermos (found %d)" % items.size())
	var clutter_mass: float = 0.0
	for item: RigidBody3D in items:
		clutter_mass += item.mass
		_expect(item.collision_layer == 0, "%s sits on no layer: nothing looks for it" % item.name)
		_expect(item.collision_mask & (PACKAGE_LAYER | PLAYER_LAYER) == 0,
			"%s never touches packages or players" % item.name)
		_expect(item.collision_mask & VEHICLE_LAYER != 0, "%s still rattles against the truck's walls" % item.name)
		_expect(host_truck.to_local(item.global_position).length() < 3.0, "%s starts inside the truck" % item.name)
	_expect(not host_truck.freeze, "The host's truck is the one really simulated")
	_expect(clutter_mass < host_truck.mass * 0.01,
		"All the clutter together is under 1%% of the truck's mass (%.1f of %.0f kg)" % [clutter_mass, host_truck.mass])
	world.free()

	var client_world := Node3D.new()
	root.add_child(client_world)
	var client_truck: VehicleBody3D = vehicle_scene.instantiate()
	# Another peer owns it: this is a client's copy of the host's truck.
	client_truck.set_multiplayer_authority(2)
	client_world.add_child(client_truck)
	await process_frame
	await process_frame
	_expect(client_truck.freeze,
		"A client's copy of the truck is frozen, so its local clutter can't push it off the host's pose")
	client_world.free()

	if _failures == 0:
		print("PASS: the cargo bay clutter can't make the truck differ between peers")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

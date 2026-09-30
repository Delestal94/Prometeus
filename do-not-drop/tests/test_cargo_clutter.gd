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
## N-139: their look is a low-poly GLB each (assets/models/props/cargo/), not
## primitive meshes, and the collision is untouched by that:
## - each has the GLB's scene as a child, with its Toolbox / Thermos mesh, and
##   no BoxMesh or CylinderMesh left over from the old look;
## - the toolbox's body (bar the handle, on top) stays inside its BoxShape, and
##   the thermos sits on the floor of its shape, within its radius bar the handle;
## - the shapes are still a 0.36 x 0.2 x 0.2 box and a r 0.045, h 0.26 cylinder.

const PACKAGE_LAYER: int = 4
const PLAYER_LAYER: int = 8
const VEHICLE_LAYER: int = 2
const SHELL_LAYER: int = 64
const TOOLBOX_GLB: String = "res://assets/models/props/cargo/sm_prop_cargo_toolbox.glb"
const THERMOS_GLB: String = "res://assets/models/props/cargo/sm_prop_cargo_thermos.glb"
## Slack (m) on the look-versus-collision comparisons.
const TOLERANCE: float = 0.005

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
		_expect(item.collision_mask & SHELL_LAYER != 0,
			"%s still rattles against the truck's walls (its cargo shell)" % item.name)
		_expect(item.collision_mask & VEHICLE_LAYER == 0, "%s never pushes the truck's own body" % item.name)
		_expect(host_truck.to_local(item.global_position).length() < 3.0, "%s starts inside the truck" % item.name)
	_check_looks(items)
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


## The look (a GLB per item) and the collision that must not have moved.
func _check_looks(items: Array[RigidBody3D]) -> void:
	var toolbox: RigidBody3D = null
	var thermos: RigidBody3D = null
	for item: RigidBody3D in items:
		if item.name == &"CargoClutterToolbox":
			toolbox = item
		elif item.name == &"CargoClutterThermos":
			thermos = item
	_expect(toolbox != null and thermos != null, "Both the toolbox and the thermos are there to inspect")
	if toolbox == null or thermos == null:
		return
	_check_model(toolbox, TOOLBOX_GLB, "Toolbox")
	_check_model(thermos, THERMOS_GLB, "Thermos")

	var box := _shape_of(toolbox) as BoxShape3D
	_expect(box != null and box.size.is_equal_approx(Vector3(0.36, 0.2, 0.2)),
		"The toolbox still collides as a 0.36 x 0.2 x 0.2 box")
	var cylinder := _shape_of(thermos) as CylinderShape3D
	_expect(cylinder != null and is_equal_approx(cylinder.radius, 0.045) and is_equal_approx(cylinder.height, 0.26),
		"The thermos still collides as a cylinder of radius 0.045 and height 0.26")

	if box != null:
		var body_box: AABB = _visual_bounds(toolbox, "Toolbox")
		var half: Vector3 = box.size * 0.5
		_expect(body_box.position.x >= -half.x - TOLERANCE and body_box.end.x <= half.x + TOLERANCE,
			"The toolbox's look is no longer than its box (%s)" % body_box)
		_expect(body_box.position.z >= -half.z - TOLERANCE and body_box.end.z <= half.z + TOLERANCE,
			"The toolbox's look is no wider than its box (%s)" % body_box)
		_expect(absf(body_box.position.y + half.y) <= TOLERANCE,
			"The toolbox's base rests on the box's floor, not floating or sunk (%s)" % body_box)
		_expect(body_box.end.y > half.y and body_box.end.y <= half.y + 0.1,
			"Only the handle rises above the box (%s)" % body_box)
	if cylinder != null:
		var thermos_box: AABB = _visual_bounds(thermos, "Thermos")
		var half_height: float = cylinder.height * 0.5
		_expect(absf(thermos_box.position.y + half_height) <= TOLERANCE,
			"The thermos' base rests on the cylinder's floor (%s)" % thermos_box)
		_expect(thermos_box.end.y <= half_height + 0.05,
			"The thermos' cap barely rises above its shape (%s)" % thermos_box)
		var r: float = cylinder.radius
		_expect(absf(thermos_box.position.z) <= r + 0.005 and absf(thermos_box.end.z) <= r + 0.005
				and thermos_box.position.x >= -r - 0.005 and thermos_box.end.x <= r + 0.03,
			"The thermos is as wide as its shape, bar the handle (%s)" % thermos_box)


## `body`'s look is the GLB `scene_path`: its scene as a child, holding the
## `mesh_name` mesh, and no primitive mesh anywhere in the body.
func _check_model(body: RigidBody3D, scene_path: String, mesh_name: String) -> void:
	var from_glb: bool = false
	for child: Node in body.get_children():
		if child.scene_file_path == scene_path:
			from_glb = true
	_expect(from_glb, "%s's look is the scene %s" % [body.name, scene_path])
	_expect(body.find_child(mesh_name, true, false) is MeshInstance3D,
		"%s has the model's %s mesh" % [body.name, mesh_name])
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		_expect(mesh != null and not (mesh is PrimitiveMesh),
			"%s's mesh %s is modelled, not a primitive" % [body.name, node.name])


func _shape_of(body: RigidBody3D) -> Shape3D:
	for child: Node in body.get_children():
		if child is CollisionShape3D:
			return (child as CollisionShape3D).shape
	return null


## The `mesh_name` mesh's bounds in `body`'s own space (rotation-free, so the
## random turn it spawns with doesn't matter).
func _visual_bounds(body: RigidBody3D, mesh_name: String) -> AABB:
	var mesh := body.find_child(mesh_name, true, false) as MeshInstance3D
	if mesh == null:
		return AABB()
	return body.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

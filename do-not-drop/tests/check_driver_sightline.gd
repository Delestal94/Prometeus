extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/check_driver_sightline.gd
## Visual meshes have no collision, so a physics raycast can't see them.
## This walks every MeshInstance3D in the van and tests the driver's forward
## ray against each one's world AABB -- catching exactly the class of bug
## where a dashboard, a wheel or an opaque "glass" pane sits in the way.
##
## Two hits are legitimate and are not failures:
##   - a mesh the eye sits inside of, as long as it culls back faces
##     (the cabin shell is invisible from within);
##   - a mesh whose material is transparent (the windshield is glass).

const RAY_LENGTH: float = 4.0
var _blockers: Array[String] = []
var _allowed: Array[String] = []


func _initialize() -> void:
	var vehicle: Node3D = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
	root.add_child(vehicle)
	await process_frame

	var eye: Node3D = vehicle.get_node(^"CabinInterior/DriverEyePoint")
	var origin: Vector3 = eye.global_position
	var forward: Vector3 = -eye.global_basis.z

	for mesh: MeshInstance3D in _all_meshes(vehicle):
		var aabb: AABB = mesh.global_transform * mesh.get_aabb()
		var inside: bool = aabb.has_point(origin)
		if not inside and aabb.intersects_ray(origin, forward * RAY_LENGTH) == null:
			continue
		var material: BaseMaterial3D = _material_of(mesh)
		if material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			_allowed.append("%s (transparent)" % mesh.name)
		elif inside and material != null and material.cull_mode == BaseMaterial3D.CULL_BACK:
			_allowed.append("%s (eye inside, back faces culled)" % mesh.name)
		elif inside:
			_blockers.append("%s (eye INSIDE an opaque, non-culling mesh)" % mesh.name)
		else:
			_blockers.append("%s at %.2fm" % [mesh.name, aabb.get_center().distance_to(origin)])

	print("Eye at %s looking toward %s" % [origin, forward])
	if not _allowed.is_empty():
		print("  see-through, as intended: ", ", ".join(_allowed))
	if _blockers.is_empty():
		print("SIGHTLINE PASS: the driver can see the road ahead")
	else:
		print("SIGHTLINE BLOCKED by: ", ", ".join(_blockers))
	vehicle.free()
	quit(0 if _blockers.is_empty() else 1)


func _material_of(mesh: MeshInstance3D) -> BaseMaterial3D:
	if mesh.material_override is BaseMaterial3D:
		return mesh.material_override as BaseMaterial3D
	if mesh.mesh != null and mesh.mesh.surface_get_material(0) is BaseMaterial3D:
		return mesh.mesh.surface_get_material(0) as BaseMaterial3D
	return null


func _all_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		found.append_array(_all_meshes(child))
	return found

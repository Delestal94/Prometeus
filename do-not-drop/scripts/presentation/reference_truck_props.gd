class_name ReferenceTruckProps
extends RefCounted
## Shared helpers of the reference truck's art (reference_truck.gd and the
## ReferenceTruckCab / ReferenceTruckCargo / ReferenceTruckPanelLines builders):
## finding the model's meshes and materials, and the plain boxes and cylinders
## the dressing is made of. Pure functions, no state.


static func meshes(model: Node3D) -> Array[Node]:
	return model.find_children("*", "MeshInstance3D", true, false)


static func material_named(model: Node3D, material_name: String) -> Material:
	for mesh: MeshInstance3D in meshes(model):
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.mesh.surface_get_material(surface)
			if material != null and material.resource_name == material_name:
				return material
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(0.55, 0.58, 0.6) if material_name == "DT_Steel" else Color(0.08, 0.09, 0.1)
	return fallback


static func uses_material(mesh: MeshInstance3D, material_name: String) -> bool:
	for surface in range(mesh.mesh.get_surface_count()):
		var material := mesh.mesh.surface_get_material(surface)
		if material != null and material.resource_name == material_name:
			return true
	return false


static func flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	return material


static func add_box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh


static func prop_box(
	parent: Node3D, size: Vector3, at: Vector3, material: Material, rotation_euler: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var mesh := add_box(parent, size, at, material)
	mesh.rotation = rotation_euler
	return mesh


static func prop_cylinder(
	parent: Node3D, radius: float, height: float, at: Vector3, rotation_euler: Vector3, material: Material
) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 12
	mesh.mesh = cylinder
	mesh.material_override = material
	mesh.position = at
	mesh.rotation = rotation_euler
	parent.add_child(mesh)
	return mesh

extends RouteSegment
class_name SpeedBumpSegment
## One speed bump with warning stripes -- forces the driver to slow down or
## risk shaking the cargo.


func _init() -> void:
	length = 24.0


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)
	var bump_z: float = -length * 0.5
	_build_bump(bump_z)
	for stripe: int in range(7):
		_box("BumpApproachStripe", Vector3(0.7, 0.015, 0.3), Vector3(-4.5 + float(stripe) * 1.5, 0.03, bump_z + 3.2), WARNING)


func _build_bump(z: float) -> void:
	# Bevelled trapezoid: 1.45 m ramps and a 0.7 m flat crown, no vertical lip.
	var points := PackedVector3Array([
		Vector3(-5.6, -0.03, 1.8), Vector3(5.6, -0.03, 1.8),
		Vector3(-5.6, 0.19, 0.35), Vector3(5.6, 0.19, 0.35),
		Vector3(-5.6, 0.19, -0.35), Vector3(5.6, 0.19, -0.35),
		Vector3(-5.6, -0.03, -1.8), Vector3(5.6, -0.03, -1.8),
	])
	var body := StaticBody3D.new()
	body.name = "SpeedBump"
	body.position.z = z
	body.collision_layer = 1
	body.collision_mask = 6
	add_child(body)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles: Array[int] = [0, 2, 1, 1, 2, 3, 2, 4, 3, 3, 4, 5, 4, 6, 5, 5, 6, 7, 0, 6, 2, 2, 6, 4, 1, 3, 7, 3, 5, 7, 0, 1, 6, 1, 7, 6]
	for vertex: int in triangles:
		surface.add_vertex(points[vertex])
	surface.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = surface.commit()
	# Its own double-sided copy: the hand-listed triangles above don't share
	# one winding, and the base sits just under the ground so the underside
	# never shows through the terrain.
	var bump_material := _material(WARNING).duplicate() as StandardMaterial3D
	bump_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = bump_material
	body.add_child(mesh_instance)

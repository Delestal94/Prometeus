extends RefCounted
## District-specific scenery on the existing route height field. Coast placement
## follows the seeded city orientation, outside every street, parcel and park.

const WALK := preload("res://modules/town_gen/town_walkways.gd")
const ART := preload("res://scripts/gameplay/town/town_art.gd")
const WATER_LEVEL: float = -1.4
const CRATE := "res://assets/models/environment/props/sm_env_prop_wooden_crate.glb"
const BOLLARD := "res://assets/models/environment/depot/sm_env_depot_bollard.glb"
const WATER := preload("res://shaders/town_water.gdshader")
const WOOD := preload("res://assets/textures/detail/tx_detail_wood_planks_512.png")


static func configure(terrain: TerrainField, plan: Dictionary, districts: PackedInt32Array) -> void:
	if 5 in districts:
		terrain.set(&"mountain_outline", plan.districts[5].outline)
	if 4 not in districts:
		return
	var center := Vector2.ZERO
	for district: Dictionary in plan.districts:
		center += district.center / 6
	var direction: Vector2 = (plan.districts[4].center - center).normalized()
	var support: float = -INF
	for node: Vector2 in plan.nodes:
		support = maxf(support, node.dot(direction) + 12)
	for lot: Dictionary in plan.lots:
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var at: Vector2 = lot.position + (corner * lot.size * .5).rotated(lot.angle)
			support = maxf(support, at.dot(direction) + 4)
	for green: Dictionary in plan.green_areas:
		support = maxf(support, green.position.dot(direction) + green.radius + 4)
	var start: Vector2 = plan.nodes[plan.districts[4].node_ids[0]]
	for id: int in plan.districts[4].node_ids:
		if plan.nodes[id].dot(direction) > start.dot(direction):
			start = plan.nodes[id]
	var shore: Vector2 = start + direction * (support + 40 - start.dot(direction))
	var coast: Dictionary = {"shore": shore, "direction": direction}
	# Reuse the parcel visibility graph; parks also remain clear of the approach.
	var obstacles: Dictionary = plan.duplicate(true)
	for green: Dictionary in plan.green_areas:
		obstacles.lots.append(
			{"position": green.position, "size": Vector2.ONE * green.radius * 2, "angle": 0.0}
		)
	var path: PackedVector2Array = WALK._clear_path(obstacles, start, shore)
	coast["access"] = path
	terrain.set(&"coast", coast)
	for i: int in range(1, path.size()):
		var a: Vector2 = path[i - 1]
		var b: Vector2 = path[i]
		terrain.platforms.append(
			{
				"centre": (a + b) * .5,
				"along": (b - a).normalized(),
				"half": Vector2(3, a.distance_to(b) * .5 + 2),
				"height": 0.0
			}
		)
	terrain.call(&"cover_coast")


static func build(town: Node3D, terrain: TerrainField) -> void:
	var coast: Dictionary = terrain.get(&"coast")
	if coast.is_empty():
		return
	_water(town, terrain, coast)
	var shore: Vector2 = coast.shore
	var direction: Vector2 = coast.direction
	var pier := Node3D.new()
	pier.name = "PortPier"
	pier.position = Vector3(shore.x, 0, shore.y)
	pier.rotation.y = atan2(direction.x, direction.y)
	pier.set_meta(&"district", 4)
	town.add_child(pier)
	_box(town, pier, "Deck", Vector3(6, .4, 42), Vector3(0, 0, 19))
	_box(town, pier, "Head", Vector3(32, .4, 7), Vector3(0, 0, 39))
	for side: float in [-1, 1]:
		for z: float in [0, 8, 16, 24, 32]:
			_box(town, pier, "RailPost", Vector3(.18, 1, .18), Vector3(side * 2.8, .7, z))
		for z: float in [4, 14, 24, 34]:
			_box(town, pier, "Pile", Vector3(.5, 6, .5), Vector3(side * 2.8, -2.5, z))
		_box(town, pier, "Rail", Vector3(.18, .18, 34), Vector3(side * 2.8, 1.05, 16))
		ART.model(pier, "Mooring", BOLLARD, Vector3(side * 13, .2, 39), 0, true)
		ART.model(pier, "Cargo", CRATE, Vector3(side * 10, .2, 39), 0, true)
		_box(town, pier, "HeadSideRail", Vector3(.18, .18, 7), Vector3(side * 15.8, 1.05, 39))
		for z: float in [35.7, 42.3]:
			_box(town, pier, "HeadPost", Vector3(.18, 1, .18), Vector3(side * 15.8, .7, z))
	for x: float in [-14, -7, 0, 7, 14]:
		_box(town, pier, "HeadPile", Vector3(.5, 6, .5), Vector3(x, -2.5, 39))
		_box(town, pier, "EndPost", Vector3(.18, 1, .18), Vector3(x, .7, 42.3))
	_box(town, pier, "EndRail", Vector3(32, .18, .18), Vector3(0, 1.05, 42.3))
	var path: PackedVector2Array = coast.access
	for i: int in range(1, path.size()):
		var a: Vector2 = path[i - 1]
		var b: Vector2 = path[i]
		var part: Node3D = _box(
			town,
			town,
			"PortAccess",
			Vector3(2, .12, a.distance_to(b) + .1),
			Vector3((a.x + b.x) * .5, .14, (a.y + b.y) * .5)
		)
		part.rotation.y = atan2(b.x - a.x, b.y - a.y)
		part.set_meta(&"pedestrian_surface", true)


static func _box(town: Node3D, parent: Node3D, title: String, size: Vector3, at: Vector3) -> Node3D:
	var part: Node3D = town.call(&"_box", parent, title, size, at, Color("876f50"), true)
	var material: StandardMaterial3D = (part.get_child(0) as MeshInstance3D).material_override
	material.albedo_texture = WOOD
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / 3
	return part


static func _water(town: Node3D, terrain: TerrainField, coast: Dictionary) -> void:
	var direction: Vector2 = coast.direction
	var across: Vector2 = direction.orthogonal()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	# Clip triangles against the actual carved ground, including the far bank.
	for side: int in range(-190, 190, 2):
		for along: int in range(-16, 156, 2):
			var corners: Array[Vector2] = []
			for delta: Vector2 in [Vector2.ZERO, Vector2(2, 0), Vector2(2, 2), Vector2(0, 2)]:
				corners.append(
					coast.shore + across * (side + delta.x) + direction * (along + delta.y)
				)
			for triangle: PackedInt32Array in [
				PackedInt32Array([0, 1, 2]), PackedInt32Array([0, 2, 3])
			]:
				var points := PackedVector2Array()
				for index: int in triangle:
					points.append(corners[index])
				var clipped: PackedVector2Array = _wet_polygon(terrain, points)
				for i: int in range(1, clipped.size() - 1):
					for at: Vector2 in [clipped[0], clipped[i], clipped[i + 1]]:
						vertices.append(Vector3(at.x, WATER_LEVEL, at.y))
						normals.append(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = WATER
	var view := MeshInstance3D.new()
	view.name = "PortWater"
	view.mesh = mesh
	view.material_override = material
	town.add_child(view)


## Cut crossing triangles at the shore instead of discarding whole 2 m cells.
static func _wet_polygon(terrain: TerrainField, points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i: int in range(points.size()):
		var a: Vector2 = points[(i + points.size() - 1) % points.size()]
		var b: Vector2 = points[i]
		var first: bool = terrain.height_at(Vector3(a.x, 0, a.y)) < WATER_LEVEL - .02
		var second: bool = terrain.height_at(Vector3(b.x, 0, b.y)) < WATER_LEVEL - .02
		if first != second:
			var wet: Vector2 = a if first else b
			var dry: Vector2 = b if first else a
			for step: int in range(8):
				var at: Vector2 = (wet + dry) * .5
				if terrain.height_at(Vector3(at.x, 0, at.y)) < WATER_LEVEL - .02:
					wet = at
				else:
					dry = at
			result.append(wet)
		if second:
			result.append(b)
	return result

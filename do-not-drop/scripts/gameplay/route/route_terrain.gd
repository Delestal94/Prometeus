extends Node3D
## One world-space height field, shared by rendering, physics and prop placement.
## Sparse square tiles cannot overlap at bends, even if the route doubles back.
const TILE: float = 32.0
const STEP: float = 2.0
const HALO: float = 64.0
const CELLS: int = 16
var spans: Array[Dictionary] = []
var pads: Array[Vector3] = []
var paths: Array[Dictionary] = []
var _buckets: Dictionary = {}
var _tiles: Dictionary = {}
var _samples: Dictionary = {}
var _material: ShaderMaterial


func add_span(a: Vector3, b: Vector3, gravel: bool = false, width: float = 6.0) -> void:
	var entry: Dictionary = {"a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z), "gravel": gravel, "width": width}
	spans.append(entry)
	var low := Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2.ONE * HALO
	var high := Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2.ONE * HALO
	for x: int in range(floori(low.x / TILE), floori(high.x / TILE) + 1):
		for z: int in range(floori(low.y / TILE), floori(high.y / TILE) + 1):
			var key := Vector2i(x, z)
			if not _buckets.has(key):
				_buckets[key] = []
			_buckets[key].append(entry)
			_tiles[key] = true


func nearest(p: Vector2) -> Vector3:
	var best: float = HALO * 4.0
	var gravel: float = 0.0
	var width: float = 6.0
	var key := Vector2i(floori(p.x / TILE), floori(p.y / TILE))
	var bucket: Array = _buckets.get(key, [])
	if bucket.is_empty():
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				bucket.append_array(_buckets.get(key + Vector2i(dx, dz), []))
	for span: Dictionary in bucket:
		var a: Vector2 = span.a
		var edge: Vector2 = span.b - a
		var t: float = clampf((p - a).dot(edge) / maxf(edge.length_squared(), 0.001), 0.0, 1.0)
		var d: float = p.distance_to(a + edge * t)
		if d < best:
			best = d
			gravel = 1.0 if span.gravel else 0.0
			width = span.width
	return Vector3(best, gravel, width)


func base_height(p: Vector2) -> float:
	# Flat loading apron; long, gentle climbs with no change to the route's yaw.
	var fade: float = smoothstep(120.0, 210.0, p.length())
	return fade * (2.6 * sin(p.x * 0.014 + p.y * 0.019) + 1.4 * sin(p.y * 0.031 - p.x * 0.011))


func _sample(key: Vector2i) -> Vector3:
	if _samples.has(key):
		return _samples[key]
	var p := Vector2(key) * STEP
	var road: Vector3 = nearest(p)
	var offroad: float = smoothstep(12.0, 29.0, road.x)
	var hills: float = 1.7 + 1.4 * sin(p.x * 0.087 + p.y * 0.039) + 0.8 * cos(p.y * 0.11 - p.x * 0.043)
	var height: float = base_height(p) - smoothstep(5.5, 9.0, road.x) * 0.08 + offroad * hills
	# A rising forest ridge gives the playable corridor a visible boundary.
	height += smoothstep(38.0, 61.0, road.x) * 12.0
	for pad: Vector3 in pads:
		var weight: float = 1.0 - smoothstep(5.0, 11.0, p.distance_to(Vector2(pad.x, pad.z)))
		height = lerpf(height, pad.y, weight)
	var result := Vector3(height, road.x - road.z + 6.0, road.y)
	_samples[key] = result
	return result


func height_at(p: Vector3) -> float:
	# Interpolate the actual rendered triangle, not a second approximation.
	var grid := Vector2(p.x, p.z) / STEP
	var k := Vector2i(floori(grid.x), floori(grid.y))
	var f := grid - Vector2(k)
	var a: float = _sample(k).x
	var b: float = _sample(k + Vector2i(1, 0)).x
	var c: float = _sample(k + Vector2i(0, 1)).x
	var d: float = _sample(k + Vector2i(1, 1)).x
	if f.x + f.y <= 1.0:
		return a + (b - a) * f.x + (c - a) * f.y
	return d + (c - d) * (1.0 - f.x) + (b - d) * (1.0 - f.y)


func build() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/route_terrain.gdshader")
	for surface: String in ["asphalt", "earth", "grass", "gravel"]:
		_material.set_shader_parameter(surface + "_detail", load("res://assets/textures/detail/tx_detail_%s_512.png" % surface))
	for key: Vector2i in _tiles:
		_build_tile(key)


func _build_tile(key: Vector2i) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for z: int in range(CELLS + 1):
		for x: int in range(CELLS + 1):
			var k := key * CELLS + Vector2i(x, z)
			var data: Vector3 = _sample(k)
			var p := Vector3(float(k.x) * STEP, data.x, float(k.y) * STEP)
			vertices.append(p)
			uv.append(Vector2(data.y, data.z))
			var dx: float = _sample(k + Vector2i(1, 0)).x - _sample(k - Vector2i(1, 0)).x
			var dz: float = _sample(k + Vector2i(0, 1)).x - _sample(k - Vector2i(0, 1)).x
			normals.append(Vector3(-dx, STEP * 2.0, -dz).normalized())
			var path_weight: float = 0.0
			for path: Dictionary in paths:
				var a: Vector2 = path.a
				var edge: Vector2 = path.b - a
				var point := Vector2(p.x, p.z)
				var t: float = clampf((point - a).dot(edge) / maxf(edge.length_squared(), 0.001), 0.0, 1.0)
				path_weight = maxf(path_weight, 1.0 - smoothstep(0.6, 2.1, point.distance_to(a + edge * t)))
			colors.append(Color(path_weight, 0.0, 0.0))
	for z: int in range(CELLS):
		for x: int in range(CELLS):
			var a: int = z * (CELLS + 1) + x
			indices.append_array(PackedInt32Array([a, a + 1, a + CELLS + 1, a + 1, a + CELLS + 2, a + CELLS + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var body := StaticBody3D.new()
	body.name = "Terrain_%d_%d" % [key.x, key.y]
	body.collision_layer = 1
	body.collision_mask = 6
	add_child(body)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material
	body.add_child(visual)
	var collider := CollisionShape3D.new()
	collider.shape = mesh.create_trimesh_shape()
	body.add_child(collider)
	# Close only exterior tile edges; internal joins have no walls or seams.
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if _tiles.has(key + direction):
			continue
		var wall := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.5, 80.0, TILE) if direction.x != 0 else Vector3(TILE, 80.0, 0.5)
		wall.shape = box
		wall.position = Vector3((float(key.x) + 0.5) * TILE + float(direction.x) * TILE * 0.5, 15.0, (float(key.y) + 0.5) * TILE + float(direction.y) * TILE * 0.5)
		body.add_child(wall)


## Warp authored road furniture (including its collision) onto the height field.
## Imported props/houses instead move as rigid objects in route.gd.
func conform_geometry(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var source: Mesh = node.mesh
		if source is BoxMesh:
			source = source.duplicate()
			source.subdivide_width = maxi(0, ceili(source.size.x / STEP) - 1)
			source.subdivide_depth = maxi(0, ceili(source.size.z / STEP) - 1)
		var surface := SurfaceTool.new()
		surface.create_from(source, 0)
		var arrays: Array = surface.commit_to_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i: int in range(vertices.size()):
			var p: Vector3 = to_local(node.to_global(vertices[i]))
			p.y += height_at(p)
			vertices[i] = node.to_local(to_global(p))
		arrays[Mesh.ARRAY_VERTEX] = vertices
		# Keep the source's own normals. Regenerating them here merged every
		# vertex that shares a position, so a box's corners got averaged and
		# barriers, cones and rails shaded like soft pillows. The ground under
		# them is gentle enough that unwarped normals light them correctly.
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		node.mesh = mesh
		var parent: Node = node.get_parent()
		if parent is StaticBody3D:
			for child: Node in parent.get_children():
				if child is CollisionShape3D:
					child.shape = mesh.create_trimesh_shape()
					child.transform = node.transform
		return
	if node is Area3D or node is Label3D:
		var p: Vector3 = to_local(node.global_position)
		node.global_position.y += height_at(p)
		return
	for child: Node in node.get_children():
		conform_geometry(child)

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
## Crests the road climbs over (HillSegment, tareas #56): {"a", "b": Vector2
## ends of that stretch of road, "height": metres at the top}. The rise
## follows the road's length as sin^2 (flat at both ends, so it joins the
## neighbouring segments smoothly) and fades out sideways, so the ground
## beside the road climbs with it.
var crests: Array[Dictionary] = []
## Riverbeds a NarrowBridgeSegment crosses: {"a", "b": Vector2 ends of that
## stretch (its own centreline, straight -- the segment never turns),
## "depth": metres the ground drops away by, "full_width": half-width of the
## flat riverbed floor, "bank_width": how far out it's still fading back to
## the ambient ground}. Unlike a crest this never touches the segment's own
## furniture (deck, rails, posts, the authored water/bank model) --
## conform_geometry() skips it for anything under a node flagged
## &"ignore_river" (see NarrowBridgeSegment._build()), so the bridge floats
## over the drop instead of sinking into it with the rest of the ground.
## Fades to nothing at both ends of the span (RIVER_TAPER) so it never leaves
## a seam against neighbouring, river-free terrain, and route.gd shrinks
## `bank_width` on its own to keep a long river from cutting into another
## stretch of road, a house or the depot yard (_clamp_river_reach()).
## Meanders a little (a smooth, position-seeded wobble, not the session's
## RNG) so it doesn't read as a perfectly straight ditch, and its edges
## wobble too so the shoreline is organic rather than a rectangle.
var rivers: Array[Dictionary] = []
## How far in from each end of a river's span the drop is still fading in --
## matches the authored bank model's own taper (build_route_pieces.py
## bridge_water(): half_len=18, banks slope over the last 3.2 m).
const RIVER_TAPER: float = 3.2
## Defaults for a river entry that doesn't specify its own (only the tests'
## fixtures don't -- route.gd always sets both, see NarrowBridgeSegment's
## river_width/river_reach). Full depth out to RIVER_FULL_WIDTH from the
## (meandered) centreline, fading back up to the ambient ground by
## RIVER_BANK_WIDTH -- far enough to be lost in the landscape rather than
## read as a rectangular pool, but still short of the forest ridge that
## starts at 61 m (see _sample()).
const RIVER_FULL_WIDTH: float = 18.0
const RIVER_BANK_WIDTH: float = 60.0
## Level rectangles (x/z) the ground is flattened to height 0 inside of, then
## blends back out over FLAT_ZONE_BLEND -- the depot's footprint and yard
## (route.gd start_yard), so no hill ever pushes through its floor or walls.
var flat_zones: Array[Rect2] = []
const FLAT_ZONE_BLEND: float = 10.0
const FLAT_ZONE_HEIGHT: float = -0.02
const HILL_FLANK: float = 55.0
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
	return fade * (2.6 * sin(p.x * 0.014 + p.y * 0.019) + 1.4 * sin(p.y * 0.031 - p.x * 0.011)) + _hill_height(p)


func _hill_height(p: Vector2) -> float:
	var total: float = 0.0
	for hill: Dictionary in crests:
		var a: Vector2 = hill.a
		var edge: Vector2 = hill.b - a
		var t: float = clampf((p - a).dot(edge) / maxf(edge.length_squared(), 0.001), 0.0, 1.0)
		var side: float = p.distance_to(a + edge * t)
		var along: float = sin(PI * t)
		total += float(hill.height) * along * along * (1.0 - smoothstep(8.0, HILL_FLANK, side))
	return total


## The ground's height before any river carves into it -- shared by
## _sample() (the actual rendered/collidable terrain) and
## height_without_rivers() (what a bridge's own furniture and authored water
## model measure themselves against, so they float over the drop instead of
## sinking into it).
func _natural_height(p: Vector2) -> float:
	var road: Vector3 = nearest(p)
	var offroad: float = smoothstep(12.0, 29.0, road.x)
	var hills: float = 1.7 + 1.4 * sin(p.x * 0.087 + p.y * 0.039) + 0.8 * cos(p.y * 0.11 - p.x * 0.043)
	var height: float = base_height(p) - smoothstep(5.5, 9.0, road.x) * 0.08 + offroad * hills
	# A rising forest ridge gives the playable corridor a visible boundary.
	height += smoothstep(38.0, 61.0, road.x) * 12.0
	for pad: Vector3 in pads:
		var weight: float = 1.0 - smoothstep(5.0, 11.0, p.distance_to(Vector2(pad.x, pad.z)))
		height = lerpf(height, pad.y, weight)
	for zone: Rect2 in flat_zones:
		var outside := Vector2(maxf(maxf(zone.position.x - p.x, p.x - zone.end.x), 0.0), maxf(maxf(zone.position.y - p.y, p.y - zone.end.y), 0.0))
		height = lerpf(height, FLAT_ZONE_HEIGHT, 1.0 - smoothstep(0.0, FLAT_ZONE_BLEND, outside.length()))
	return height


## A deterministic wobble for `river`, purely a function of its own fixed
## endpoints -- no RNG, so every peer (and a rebuilt terrain) agrees, and two
## different bridges don't all meander in lockstep.
func _river_phase(river: Dictionary) -> float:
	var a: Vector2 = river.a
	return fmod(a.x * 0.037 + a.y * 0.029, TAU)


## 0..1: how much `river` affects `p`, combining the fade at both ends of its
## span (RIVER_TAPER) with the sideways fade from its (meandered) centreline
## out past its bank. Shared by _river_drop() (the actual carved ground) and
## the water mesh (_build_river_water()) so the visible water can never float
## above dry, uncarved ground or cut off in a straight line the terrain
## doesn't follow -- both read the exact same shape.
## Meander/wobble amplitudes (see _river_factor()) and their combined worst
## case -- how far a "wet" point can ever sit past a river's nominal
## `bank_width` in either direction. route.gd's _clamp_river_reach() has to
## clear a hazard by at least this much (its own margin on top for comfort),
## or the meander could still swing the actual carved/visible river into
## whatever it was supposed to stop short of.
const RIVER_MEANDER_MAX: float = 7.0
const RIVER_WOBBLE_MAX: float = 2.1
const RIVER_MAX_DRIFT: float = RIVER_MEANDER_MAX + RIVER_WOBBLE_MAX


func _river_factor(river: Dictionary, p: Vector2) -> float:
	var a: Vector2 = river.a
	var edge: Vector2 = river.b - a
	var length: float = maxf(edge.length(), 0.001)
	var dir: Vector2 = edge / length
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var s: float = clampf((p - a).dot(dir), 0.0, length)
	var phase: float = _river_phase(river)
	# A gentle meander (the centreline itself drifts sideways along the
	# span) plus a smaller wobble on where the bank actually sits, so the
	# river reads as a real, organic crossing instead of a straight ditch
	# with a ruler-straight rectangle of water in it.
	var meander: float = sin(s * 0.05 + phase) * 5.0 + sin(s * 0.13 + phase * 1.7) * 2.0
	var side: float = absf((p - a).dot(perp) - meander)
	var wobble: float = sin(s * 0.21 + phase * 2.3) * 1.5 + sin(side * 0.4 + phase) * 0.6
	var full_width: float = maxf(float(river.get("full_width", RIVER_FULL_WIDTH)) + wobble, 1.0)
	var bank_width: float = maxf(float(river.get("bank_width", RIVER_BANK_WIDTH)) + wobble, full_width + 1.0)
	var along: float = smoothstep(0.0, RIVER_TAPER, s) * smoothstep(0.0, RIVER_TAPER, length - s)
	var lateral: float = 1.0 - smoothstep(full_width, bank_width, side)
	return along * lateral


## How far the ground drops for a river at `p`, 0 outside every registered
## span. Smooth on every axis (see _river_factor()): never a hole, never a
## seam against untouched ground.
func _river_drop(p: Vector2) -> float:
	var total: float = 0.0
	for river: Dictionary in rivers:
		total += float(river.depth) * _river_factor(river, p)
	return total


## Public alias of _river_drop() for anything outside this script that needs
## to know "is this spot in a riverbed" without caring about the carved
## height itself -- RouteDresser's placement rules (no tree, pole, car or
## roadside prop belongs in the water or the bare bed beside it).
func river_depth_at(p: Vector2) -> float:
	return _river_drop(p)


func _sample(key: Vector2i) -> Vector3:
	if _samples.has(key):
		return _samples[key]
	var p := Vector2(key) * STEP
	var road: Vector3 = nearest(p)
	var height: float = _natural_height(p) - _river_drop(p)
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


## Same interpolation as height_at(), but ignoring every river: what a
## bridge's own deck, rails and authored water model are measured against
## (see conform_geometry()'s &"ignore_river" flag) so they read as a real
## span over the drop instead of sinking into it. Not cached -- only called
## while placing a bridge's own handful of nodes, never per frame.
func height_without_rivers(p: Vector3) -> float:
	var grid := Vector2(p.x, p.z) / STEP
	var k := Vector2i(floori(grid.x), floori(grid.y))
	var f := grid - Vector2(k)
	var a: float = _natural_height(Vector2(k) * STEP)
	var b: float = _natural_height(Vector2(k + Vector2i(1, 0)) * STEP)
	var c: float = _natural_height(Vector2(k + Vector2i(0, 1)) * STEP)
	var d: float = _natural_height(Vector2(k + Vector2i(1, 1)) * STEP)
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
	for river: Dictionary in rivers:
		_build_river_water(river)


## The wide, organic water surface over a carved riverbed -- one flat-ish
## mesh per river, built once here (never per frame). Every vertex sits
## exactly on the already-carved ground (height_at(), which already includes
## this same river's drop) plus a hair of clearance, so it can never float
## over dry land or leave a gap against the bank; a quad is only emitted when
## all four of its corners are "wet" per the same _river_factor() the carving
## itself uses, so the shoreline follows the actual meander and bank wobble
## instead of the grid's straight rows -- no rectangle, no seam.
const RIVER_WATER_STEP: float = 3.0
const RIVER_WATER_THRESHOLD: float = 0.08
const RIVER_WATER_CLEARANCE: float = 0.03
const RIVER_WATER_COLOR := Color(0.29, 0.58, 0.74, 0.72)


func _build_river_water(river: Dictionary) -> void:
	var a: Vector2 = river.a
	var edge: Vector2 = river.b - a
	var length: float = maxf(edge.length(), 0.001)
	var dir: Vector2 = edge / length
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var reach: float = float(river.get("bank_width", RIVER_BANK_WIDTH)) + 6.0
	var along_steps: int = maxi(1, ceili(length / RIVER_WATER_STEP))
	var side_steps: int = maxi(1, ceili((reach * 2.0) / RIVER_WATER_STEP))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var wet: Dictionary = {}
	var index_of: Dictionary = {}
	for i: int in range(along_steps + 1):
		var s: float = clampf(float(i) * RIVER_WATER_STEP, 0.0, length)
		for j: int in range(side_steps + 1):
			var lateral: float = -reach + float(j) * RIVER_WATER_STEP
			var p: Vector2 = a + dir * s + perp * lateral
			var factor: float = _river_factor(river, p)
			var key := Vector2i(i, j)
			var is_wet: bool = factor > RIVER_WATER_THRESHOLD
			wet[key] = is_wet
			if is_wet:
				var h: float = height_at(Vector3(p.x, 0.0, p.y)) + RIVER_WATER_CLEARANCE
				index_of[key] = vertices.size()
				vertices.append(Vector3(p.x, h, p.y))
				normals.append(Vector3.UP)
				# Alpha eases in from the threshold: the coastline blends
				# into the bank instead of cutting off hard.
				colors.append(Color(1.0, 1.0, 1.0, clampf((factor - RIVER_WATER_THRESHOLD) * 4.0, 0.0, 1.0)))
	for i: int in range(along_steps):
		for j: int in range(side_steps):
			var k00 := Vector2i(i, j)
			var k10 := Vector2i(i + 1, j)
			var k01 := Vector2i(i, j + 1)
			var k11 := Vector2i(i + 1, j + 1)
			if wet.get(k00, false) and wet.get(k10, false) and wet.get(k01, false) and wet.get(k11, false):
				indices.append_array(PackedInt32Array([index_of[k00], index_of[k10], index_of[k01], index_of[k10], index_of[k11], index_of[k01]]))
	if indices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = RIVER_WATER_COLOR
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.05
	material.metallic = 0.1
	# Back faces culled, same reasoning as _material(): a double-sided plane
	# right above a slope this shallow shadowed its own underside.
	mesh.surface_set_material(0, material)
	var visual := MeshInstance3D.new()
	visual.name = "RiverWater"
	visual.mesh = mesh
	add_child(visual)


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
## `ignore_rivers` sticks once set (a node flagged &"ignore_river", or any
## ancestor already carrying the flag down the recursion) so a whole bridge
## -- deck, rails, posts and its authored water/bank model alike -- measures
## itself against the ground as if no river had carved under it, and floats
## over the drop instead of sinking into it with everything else.
func conform_geometry(node: Node, ignore_rivers: bool = false) -> void:
	ignore_rivers = ignore_rivers or (node is Node3D and (node as Node3D).has_meta(&"ignore_river"))
	if node is MeshInstance3D and node.mesh != null:
		var source: Mesh = node.mesh
		if source is BoxMesh:
			source = source.duplicate()
			source.subdivide_width = maxi(0, ceili(source.size.x / STEP) - 1)
			source.subdivide_depth = maxi(0, ceili(source.size.z / STEP) - 1)
		# Every surface, each with its own material: rebuilt from the first
		# surface alone and without materials, an imported model (the road
		# barrier: white board, red stripes, orange legs) came out in the
		# default grey -- "no textures" (playtest 2026-09-25).
		var mesh := ArrayMesh.new()
		for index: int in range(source.get_surface_count()):
			var surface := SurfaceTool.new()
			surface.create_from(source, index)
			var arrays: Array = surface.commit_to_arrays()
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i: int in range(vertices.size()):
				var p: Vector3 = to_local(node.to_global(vertices[i]))
				p.y += height_without_rivers(p) if ignore_rivers else height_at(p)
				vertices[i] = node.to_local(to_global(p))
			arrays[Mesh.ARRAY_VERTEX] = vertices
			# Keep the source's own normals. Regenerating them here merged every
			# vertex that shares a position, so a box's corners got averaged and
			# barriers, cones and rails shaded like soft pillows. The ground under
			# them is gentle enough that unwarped normals light them correctly.
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(index, source.surface_get_material(index))
		node.mesh = mesh
		var parent: Node = node.get_parent()
		if parent is StaticBody3D:
			for child: Node in parent.get_children():
				if child is CollisionShape3D:
					child.shape = mesh.create_trimesh_shape()
					child.transform = node.transform
		return
	# Parts that move later (a barrier arm, a train car) ride the terrain as
	# rigid pieces: warping their vertices would bend them out of shape.
	if node is Area3D or node is Label3D or (node is Node3D and node.has_meta(&"animated")):
		var p: Vector3 = to_local(node.global_position)
		node.global_position.y += height_without_rivers(p) if ignore_rivers else height_at(p)
		return
	for child: Node in node.get_children():
		conform_geometry(child, ignore_rivers)

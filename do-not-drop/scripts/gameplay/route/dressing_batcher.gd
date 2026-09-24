extends RefCounted
class_name DressingBatcher
## Render batching for the route's static dressing. RouteDresser places every
## tree, plant, rail and prop as its own scene instance -- the right shape for
## placement rules and their tests, but tens of thousands of MeshInstance3D
## nodes, and GL Compatibility draws each one with its own draw call (shadow
## splits draw them again). Measured on a 2 km route: ~16k draw calls a frame
## and 20 ms frames, with dips when the road opened onto dense forest.
##
## bake() folds every piece that is pure geometry (no script, no animation,
## no collision, not mirrored) into one MultiMeshInstance3D per model per
## CELL-sized patch of ground: one draw call for all the ferns of a patch
## instead of one per fern. Patches keep frustum culling useful, and each
## batch gets a draw distance by object size, so grass stops being drawn
## long before the fog would hide it anyway.
##
## Anything that fails the checks (animals, the windmill's turning rotor,
## mirrored curve signs) stays a regular node, untouched.

const CELL: float = 48.0
const GROUPS: Array[String] = ["ForestDressing", "RoadsideDressing", "LandmarkDressing"]
## Draw distance by the batched mesh's largest dimension (metres). Past
## ~350 m the fog (density 0.008) has swallowed everything anyway.
const SMALL_SIZE: float = 1.6
const MEDIUM_SIZE: float = 5.0
const SMALL_RANGE: float = 85.0
const MEDIUM_RANGE: float = 190.0
const LARGE_RANGE: float = 380.0
## Pieces that move after placement even without a script of their own.
const ANIMATED_PARTS: Array[String] = ["WindmillRotor"]

## Tests only: a headless run has a dummy renderer that can't hand instance
## transforms back, so when set each batch also keeps a copy as metadata.
static var record_instances: bool = false

## Collision for the dressing (docs/tareas-nacho.md #39). Until this nothing
## on the roadside was solid: the truck drove through trees, rails and parked
## cars alike. Solid kinds get one shape each in a single StaticBody per
## patch (cheap: static, never moving); a tree is a trunk cylinder, the rest
## the box of their model. Small loose things become sleeping rigid bodies
## instead, so the truck knocks them flying rather than stopping dead.
const SOLID_RULES: Array[StringName] = [&"tree", &"landmark", &"parked_vehicle", &"guardrail", &"bus_stop", &"hazard_sign", &"delivery_sign", &"crossing_sign"]
const KNOCKABLE_RULES: Array[StringName] = [&"roadworks", &"village_furniture", &"farm_props", &"milestone", &"yard"]
## Bigger than this and it isn't something a truck bats aside (a barn).
const KNOCKABLE_MAX_SIZE: float = 2.5
const TRUNK_RADIUS: float = 0.3
const TRUNK_HEIGHT: float = 4.0
const KNOCKABLE_DENSITY: float = 140.0
const SINK_CLEARANCE: float = 0.1

## Merged model meshes, shared by every route: scene file -> Mesh.
static var _model_cache: Dictionary = {}


## Returns how many pieces were folded into batches (and freed). `extra_groups`
## are more nodes whose children are placed pieces (a house's Yard).
static func bake(route: Node3D, segments: Array, extra_groups: Array = []) -> int:
	var to_route: Transform3D = route.global_transform.affine_inverse()
	var cells: Dictionary = {}
	var baked: int = 0
	var groups: Array[Node] = []
	for segment: Node in segments:
		for group_name: String in GROUPS:
			var group: Node = segment.get_node_or_null(NodePath(group_name))
			if group != null:
				groups.append(group)
	for group: Node in extra_groups:
		if group != null:
			groups.append(group)
	var solids: Dictionary = {}
	for group: Node in groups:
		for piece: Node in group.get_children():
			var parts: Array[MeshInstance3D] = _static_parts(piece)
			if parts.is_empty():
				continue
			var rule: StringName = StringName(piece.get_meta(&"rule", &""))
			var mesh: Mesh = _model_mesh(piece as Node3D, parts)
			if rule in KNOCKABLE_RULES and not piece.get_meta(&"on_porch", false) and mesh.get_aabb().get_longest_axis_size() < KNOCKABLE_MAX_SIZE:
				_make_knockable(piece as Node3D, mesh.get_aabb())
				continue
			var origin: Vector3 = to_route * (piece as Node3D).global_position
			var cell := Vector2i(floori(origin.x / CELL), floori(origin.z / CELL))
			if not cells.has(cell):
				cells[cell] = {}
			var batches: Dictionary = cells[cell]
			if rule in SOLID_RULES:
				if not solids.has(cell):
					solids[cell] = []
				(solids[cell] as Array).append([rule, to_route * (piece as Node3D).global_transform, mesh.get_aabb()])
			var shadow: int = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for part: MeshInstance3D in parts:
				shadow = maxi(shadow, part.cast_shadow)
			var key: String = "%d|%d" % [mesh.get_instance_id(), shadow]
			if not batches.has(key):
				batches[key] = {"mesh": mesh, "shadow": shadow, "xforms": []}
			(batches[key].xforms as Array).append(to_route * (piece as Node3D).global_transform)
			group.remove_child(piece)
			piece.free()
			baked += 1
	var holder := Node3D.new()
	holder.name = "BatchedDressing"
	route.add_child(holder)
	for cell: Vector2i in cells:
		var cell_node := Node3D.new()
		cell_node.name = "Cell_%d_%d" % [cell.x, cell.y]
		holder.add_child(cell_node)
		var batches: Dictionary = cells[cell]
		for key: String in batches:
			cell_node.add_child(_multimesh_instance(batches[key]))
		if solids.has(cell):
			cell_node.add_child(_colliders(solids[cell]))
	return baked


## One static body holding every solid piece of a patch.
static func _colliders(pieces: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "DressingColliders"
	body.collision_layer = 1
	body.collision_mask = 0
	for entry: Array in pieces:
		var rule: StringName = entry[0]
		var xform: Transform3D = entry[1]
		var bounds: AABB = entry[2]
		var scale: Vector3 = xform.basis.get_scale()
		var shape := CollisionShape3D.new()
		if rule == &"tree":
			var trunk := CylinderShape3D.new()
			trunk.radius = TRUNK_RADIUS * scale.x
			trunk.height = TRUNK_HEIGHT * scale.y
			shape.shape = trunk
			# Upright whatever the tree's lean: it's the trunk that stops you.
			shape.transform = Transform3D(Basis.IDENTITY, xform.origin + Vector3.UP * trunk.height * 0.5)
		else:
			var box := BoxShape3D.new()
			box.size = (bounds.size * scale).max(Vector3.ONE * 0.1)
			shape.shape = box
			shape.transform = Transform3D(xform.basis.orthonormalized(), xform * bounds.get_center())
		body.add_child(shape)
	return body


## A loose roadside thing (a cone, a bench, a hay bale) as a real body, asleep
## until something hits it. The model rides inside unchanged.
static func _make_knockable(piece: Node3D, bounds: AABB) -> void:
	var group: Node = piece.get_parent()
	var scale: Vector3 = piece.basis.get_scale()
	var body := RigidBody3D.new()
	body.name = "Knockable" + String(piece.name)
	body.transform = Transform3D(piece.basis.orthonormalized(), piece.position)
	body.collision_layer = 1
	body.collision_mask = 1 | 2
	var size: Vector3 = (bounds.size * scale).max(Vector3.ONE * 0.1)
	body.mass = clampf(size.x * size.y * size.z * KNOCKABLE_DENSITY, 4.0, 90.0)
	body.can_sleep = true
	for meta: StringName in piece.get_meta_list():
		body.set_meta(meta, piece.get_meta(meta))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	# Pieces are sunk a few centimetres so no foot floats; the box starts just
	# above that, or the solver would pop every cone out of the ground at load.
	shape.position = bounds.get_center() * scale + Vector3.UP * SINK_CLEARANCE
	box.size.y = maxf(box.size.y - SINK_CLEARANCE, 0.1)
	body.add_child(shape)
	group.remove_child(piece)
	piece.transform = Transform3D(Basis.from_scale(scale), Vector3.ZERO)
	body.add_child(piece)
	group.add_child(body)
	# Where it was placed, before physics had any say (tests compare this).
	body.set_meta(&"placed_transform", body.transform)
	# Asleep only once in the world: set any earlier and the body wakes anyway.
	body.sleeping = true


## The piece's meshes, or [] when it can't be batched: anything scripted,
## animated, physical, hidden or mirrored has to stay a real node.
static func _static_parts(piece: Node) -> Array[MeshInstance3D]:
	var parts: Array[MeshInstance3D] = []
	if not piece is Node3D or piece.get_script() != null or not (piece as Node3D).visible:
		return parts
	if (piece as Node3D).global_basis.determinant() <= 0.0:
		return parts  # A MultiMesh can't flip winding per instance.
	var nodes: Array[Node] = [piece]
	nodes.append_array(piece.find_children("*", "", true, false))
	for node: Node in nodes:
		if node.get_script() != null or String(node.name) in ANIMATED_PARTS:
			return [] as Array[MeshInstance3D]
		if node is MeshInstance3D:
			var part := node as MeshInstance3D
			if part.skeleton != NodePath() and part.skin != null:
				return [] as Array[MeshInstance3D]
			if part.mesh == null or not part.visible:
				continue
			parts.append(part)
		elif node.get_class() != "Node3D":
			return [] as Array[MeshInstance3D]
	return parts


## The whole model as ONE mesh, in the piece's own space: its parts (a tree
## is a trunk plus several leaf blobs, each authored as its own mesh) merged
## into one surface per material, so a batch costs a draw call per material
## instead of one per part. Built once per model file and shared.
static func _model_mesh(piece: Node3D, parts: Array[MeshInstance3D]) -> Mesh:
	var path: String = piece.scene_file_path
	if path != "" and _model_cache.has(path):
		return _model_cache[path]
	var inverse: Transform3D = piece.global_transform.affine_inverse()
	var tools: Dictionary = {}
	var materials: Dictionary = {}
	for part: MeshInstance3D in parts:
		var local: Transform3D = inverse * part.global_transform
		for surface: int in range(part.mesh.get_surface_count()):
			var material: Material = part.material_override
			if material == null and surface < part.get_surface_override_material_count():
				material = part.get_surface_override_material(surface)
			if material == null:
				material = part.mesh.surface_get_material(surface)
			var id: int = material.get_instance_id() if material != null else 0
			if not tools.has(id):
				tools[id] = SurfaceTool.new()
				materials[id] = material
			(tools[id] as SurfaceTool).append_from(part.mesh, surface, local)
	var merged := ArrayMesh.new()
	for id: int in tools:
		(tools[id] as SurfaceTool).commit(merged)
		merged.surface_set_material(merged.get_surface_count() - 1, materials[id])
	if path != "":
		_model_cache[path] = merged
	return merged


static func _multimesh_instance(batch: Dictionary) -> MultiMeshInstance3D:
	var xforms: Array = batch.xforms
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = batch.mesh
	multimesh.instance_count = xforms.size()
	# One upload instead of one call per instance: 12 floats each, the 3x4
	# matrix row by row (basis row, then that row's origin component).
	var buffer := PackedFloat32Array()
	buffer.resize(xforms.size() * 12)
	for index: int in range(xforms.size()):
		var xform: Transform3D = xforms[index]
		var at: int = index * 12
		buffer[at] = xform.basis.x.x
		buffer[at + 1] = xform.basis.y.x
		buffer[at + 2] = xform.basis.z.x
		buffer[at + 3] = xform.origin.x
		buffer[at + 4] = xform.basis.x.y
		buffer[at + 5] = xform.basis.y.y
		buffer[at + 6] = xform.basis.z.y
		buffer[at + 7] = xform.origin.y
		buffer[at + 8] = xform.basis.x.z
		buffer[at + 9] = xform.basis.y.z
		buffer[at + 10] = xform.basis.z.z
		buffer[at + 11] = xform.origin.z
	multimesh.buffer = buffer
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = batch.shadow
	var size: float = (batch.mesh as Mesh).get_aabb().get_longest_axis_size()
	var draw_range: float = SMALL_RANGE if size < SMALL_SIZE else (MEDIUM_RANGE if size < MEDIUM_SIZE else LARGE_RANGE)
	# The graphics quality level scales it (world_quality.gd), from this.
	instance.set_meta(WorldQuality.BASE_RANGE_META, draw_range)
	instance.visibility_range_end = draw_range * WorldQuality.setting("range_scale")
	instance.visibility_range_end_margin = 6.0
	if record_instances:
		instance.set_meta(&"instance_transforms", xforms.duplicate())
	return instance


## The segments' own road furniture -- edge lines, dashes, kerbs, bridge
## rails, chicane blocks -- is built from hundreds of small boxes, each its
## own draw call. Once the terrain has warped them into place they never
## move again, so each segment's boxes are merged into one mesh (a surface
## per material). The nodes that own their collision stay exactly as they
## are; only their MeshInstance3D children are replaced.
static func merge_segment_geometry(segments: Array) -> int:
	var merged_count: int = 0
	for segment: Node in segments:
		var inverse: Transform3D = (segment as Node3D).global_transform.affine_inverse()
		var tools: Dictionary = {}
		var materials: Dictionary = {}
		var shadows: Dictionary = {}
		var merged_parts: Array[MeshInstance3D] = []
		for part: MeshInstance3D in _segment_parts(segment):
			var local: Transform3D = inverse * part.global_transform
			if local.basis.determinant() <= 0.0:
				continue
			for surface: int in range(part.mesh.get_surface_count()):
				var material: Material = part.material_override
				if material == null and surface < part.get_surface_override_material_count():
					material = part.get_surface_override_material(surface)
				if material == null:
					material = part.mesh.surface_get_material(surface)
				var key: String = "%d|%d" % [material.get_instance_id() if material != null else 0, part.cast_shadow]
				if not tools.has(key):
					tools[key] = SurfaceTool.new()
					materials[key] = material
					shadows[key] = part.cast_shadow
				(tools[key] as SurfaceTool).append_from(part.mesh, surface, local)
			merged_parts.append(part)
		if merged_parts.is_empty():
			continue
		var by_shadow: Dictionary = {}
		for key: String in tools:
			var shadow: int = shadows[key]
			if not by_shadow.has(shadow):
				by_shadow[shadow] = ArrayMesh.new()
			var mesh: ArrayMesh = by_shadow[shadow]
			(tools[key] as SurfaceTool).commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
		for shadow: int in by_shadow:
			var instance := MeshInstance3D.new()
			instance.name = "MergedGeometry"
			instance.mesh = by_shadow[shadow]
			instance.cast_shadow = shadow
			segment.add_child(instance)
		for part: MeshInstance3D in merged_parts:
			part.get_parent().remove_child(part)
			part.free()
			merged_count += 1
	return merged_count


## Static, unscripted meshes that belong to the segment itself: not its
## dressing (batched separately) and not anything with behaviour of its own
## (a deer crossing, anything a script might move or hide later).
static func _segment_parts(segment: Node) -> Array[MeshInstance3D]:
	var parts: Array[MeshInstance3D] = []
	for node: Node in segment.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null or not part.visible or part.skin != null or part.get_script() != null:
			continue
		var owned: bool = true
		var ancestor: Node = part.get_parent()
		while ancestor != segment:
			if ancestor.get_script() != null or String(ancestor.name).ends_with("Dressing") or not (ancestor as Node3D).visible or ancestor.has_meta(&"animated"):
				owned = false
				break
			ancestor = ancestor.get_parent()
		if owned:
			parts.append(part)
	return parts


## Replaces every static mesh under `root` (a house, say: a few hundred
## authored parts) with a single MeshInstance3D holding them merged, one
## surface per material. Same model file, same merged mesh, built once.
## Does nothing if anything under `root` has behaviour of its own.
static func merge_into_one(root: Node3D) -> void:
	var parts: Array[MeshInstance3D] = _static_parts(root)
	if parts.size() < 2:
		return
	var merged := MeshInstance3D.new()
	merged.name = "MergedModel"
	merged.mesh = _model_mesh(root, parts)
	var shadow: int = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for part: MeshInstance3D in parts:
		shadow = maxi(shadow, part.cast_shadow)
		part.get_parent().remove_child(part)
		part.free()
	merged.cast_shadow = shadow
	root.add_child(merged)

class_name StreetBatcher
extends RefCounted
## A world cell's street pieces drawn as a few meshes instead of a mesh per box (expansion D-2012.2).
##
## EdgeCellContent gives a cell one RouteSegment per piece of street, and a piece builds itself out of
## boxes: a straight one is 17 meshes on 16 holders, a bridge 690. The company map's default view held
## 15,362 nodes and drew 2,598 calls at its worst, most of them these. bake() runs once over a cell that
## is in the tree (CompanyCells hands it to the streamer as its second pass, WorldCellStreamer.finish_for)
## and leaves, under the cell:
## - `Streets`: every roadway and verge box of the cell (the ones StreetSurface dressed) as one mesh, a
##   surface per street surface, drawn by StreetSurface.batched_material(). street_surface.gdshader
##   reads each box's own x and heading, which a merged mesh no longer has: they ride in the vertices
##   (UV.x, UV.y), so the wheel tracks, the edges and the lift at a crossing come out the same.
## - `MergedStatic` and `MergedModels`: the rest of what is pure geometry (lane lines, kerbs, blocks, a
##   bridge's deck and rails, barriers), folded by StaticMerger (modules/render_budget) with the holders
##   that carried it.
## - `Verge`: the collision of every verge box of the cell as the shapes of one StaticBody3D, with the
##   verge's footstep surface and roughness (StreetSurface.UNDERFOOT). Nothing reads a piece's `Ground`
##   by itself, and its top is 0.3 m under the roadway's.
## The lane lines StreetSurface hid (a street that is not asphalt) are freed: nothing shows them again.
## What stays in each piece is what something reads or what does something: the piece itself (a
## RouteSegment where its street puts it), its `Road` body with its box (the roadway's collision, footstep
## surface and roughness), every other body, the SurfaceGrip, triggers, lights, labels, sounds, and
## whatever moves or has a script (cones, a train, mud). What is not safe to merge is left as it was.
##
## Nothing changes where anything is: the meshes are the same triangles in the same place with the same
## materials, and the shapes the same boxes with the same layers.

const STREETS_NAME: StringName = &"Streets"
const VERGE_NAME: StringName = &"Verge"
## RouteSegment's solid boxes (modules/route_gen, RouteSegment._box()).
const SOLID_LAYER: int = 1
const SOLID_MASK: int = 6
## Vertices of a box drawn as loose triangles: 6 faces of 2.
const BOX_VERTICES: int = 36

## A BoxMesh of 1 m, as loose triangles: its corners and their normals, read once from the engine's own
## box so the merged ones wind and shade exactly like it.
static var _unit_corners := PackedVector3Array()
static var _unit_normals := PackedVector3Array()


## Bakes the street pieces (RouteSegment children) of `holder`, a cell's node or anything that holds
## pieces the same way, which must be in the tree. Returns {"pieces", "surfaces": street boxes folded,
## "parts": other meshes merged, "freed": nodes freed, "verges": verge bodies folded}; an empty
## Dictionary when the holder has no piece.
static func bake(holder: Node3D) -> Dictionary:
	var pieces: Array[Node] = []
	for child: Node in holder.get_children():
		if child is RouteSegment:
			pieces.append(child)
	if pieces.is_empty():
		return {}
	var job := _Job.new()
	job.to_holder = holder.global_transform.affine_inverse()
	var merged: Dictionary = StaticMerger.merge(holder, pieces, true, _claim.bind(job))
	_add_streets(holder, job)
	var verges: int = _add_verge(holder, job)
	return {
		"pieces": pieces.size(), "surfaces": job.boxes, "parts": merged.parts,
		"freed": int(merged.freed) + verges * 2, "verges": verges,
	}


## StaticMerger's question about a mesh it would leave: true for the ones this takes. A roadway or verge
## box StreetSurface dressed goes into the job (its body too, if it is a verge's); a lane line
## StreetSurface hid (a street that is not asphalt) is never shown again.
static func _claim(mesh: MeshInstance3D, job: _Job) -> bool:
	if not mesh.visible:
		return StreetSurface.is_line(mesh)
	if not (mesh.mesh is BoxMesh):
		return false
	var surface: StringName = StreetSurface.surface_drawn_by(mesh.material_override)
	if surface == &"":
		return false
	# Flat on the ground and not scaled: the shader lifts a box along its own up.
	var basis: Basis = mesh.global_basis
	if not basis.y.is_equal_approx(Vector3.UP) or not basis.x.is_normalized() or not basis.z.is_normalized():
		return false
	var key: String = "%s|%d" % [surface, mesh.cast_shadow]
	if not job.surfaces.has(key):
		job.surfaces[key] = _Surface.new(surface, mesh.cast_shadow)
	_append_box(job.surfaces[key], job.to_holder * mesh.global_transform, (mesh.mesh as BoxMesh).size,
			absf(basis.z.x))
	job.boxes += 1
	if surface == StreetSurface.VERGE and mesh.get_parent() is StaticBody3D:
		job.verges.append(mesh.get_parent())
	return true


## A verge body that is only that once its box is drawn elsewhere: RouteSegment's solid box and
## StreetSurface's tag, nothing else on it.
static func _is_plain_verge(body: StaticBody3D) -> bool:
	if body.get_script() != null or not body.get_groups().is_empty() or body.get_child_count() != 1:
		return false
	if body.collision_layer != SOLID_LAYER or body.collision_mask != SOLID_MASK:
		return false
	if body.physics_material_override != null or body.get_meta_list().size() != 2:
		return false
	var tag: Array = StreetSurface.UNDERFOOT[StreetSurface.VERGE]
	if body.get_meta(StreetSurface.AUDIO_META, &"") != tag[0]:
		return false
	if not is_equal_approx(float(body.get_meta(StreetSurface.ROUGHNESS_META, -1.0)), float(tag[1])):
		return false
	var collider := body.get_child(0) as CollisionShape3D
	return collider != null and collider.shape is BoxShape3D and not collider.disabled


## Adds a box of `size` at `box` (its transform in the holder's space) to the surface.
static func _append_box(surface: _Surface, box: Transform3D, size: Vector3, heading: float) -> void:
	_read_unit_box()
	surface.vertices.append_array(box.scaled_local(size) * _unit_corners)
	surface.normals.append_array(Transform3D(box.basis, Vector3.ZERO) * _unit_normals)
	var at: int = surface.own.size()
	surface.own.resize(at + BOX_VERTICES)
	for index: int in BOX_VERTICES:
		surface.own[at + index] = Vector2(_unit_corners[index].x * size.x, heading)


static func _read_unit_box() -> void:
	if not _unit_corners.is_empty():
		return
	var arrays: Array = BoxMesh.new().surface_get_arrays(0)
	var corners: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index: int in arrays[Mesh.ARRAY_INDEX] as PackedInt32Array:
		_unit_corners.append(corners[index])
		_unit_normals.append(normals[index])


## One `Streets` mesh per shadow setting, a surface per street surface.
static func _add_streets(holder: Node3D, job: _Job) -> void:
	var by_shadow: Dictionary = {}
	for key: String in job.surfaces:
		var surface: _Surface = job.surfaces[key]
		if not by_shadow.has(surface.shadow):
			by_shadow[surface.shadow] = ArrayMesh.new()
		var mesh: ArrayMesh = by_shadow[surface.shadow]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface.vertices
		arrays[Mesh.ARRAY_NORMAL] = surface.normals
		arrays[Mesh.ARRAY_TEX_UV] = surface.own
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, StreetSurface.batched_material(surface.name))
	for shadow: int in by_shadow:
		var instance := MeshInstance3D.new()
		instance.name = STREETS_NAME
		instance.mesh = by_shadow[shadow]
		instance.cast_shadow = shadow as GeometryInstance3D.ShadowCastingSetting
		holder.add_child(instance, true)


## The verge bodies folded into one, each box a shape of its own where it was. Returns how many.
static func _add_verge(holder: Node3D, job: _Job) -> int:
	var verge := StaticBody3D.new()
	verge.name = VERGE_NAME
	verge.collision_layer = SOLID_LAYER
	verge.collision_mask = SOLID_MASK
	var tag: Array = StreetSurface.UNDERFOOT[StreetSurface.VERGE]
	verge.set_meta(StreetSurface.AUDIO_META, tag[0])
	verge.set_meta(StreetSurface.ROUGHNESS_META, tag[1])
	var folded: int = 0
	for body: StaticBody3D in job.verges:
		if not is_instance_valid(body) or not _is_plain_verge(body):
			continue
		var collider := body.get_child(0) as CollisionShape3D
		var owner_id: int = verge.create_shape_owner(verge)
		verge.shape_owner_set_transform(owner_id, job.to_holder * collider.global_transform)
		verge.shape_owner_add_shape(owner_id, collider.shape)
		body.free()
		folded += 1
	if folded == 0:
		verge.free()
		return 0
	# In the tree with all its shapes at once: one body for the physics server to build.
	holder.add_child(verge)
	return folded


class _Job extends RefCounted:
	var to_holder: Transform3D
	## "surface|shadow" -> _Surface
	var surfaces: Dictionary = {}
	## The bodies whose verge box was folded: the ones that are only that fold too.
	var verges: Array[StaticBody3D] = []
	var boxes: int = 0


## The boxes of one street surface: loose triangles, with each vertex's own x and its box's heading.
class _Surface extends RefCounted:
	var name: StringName
	var shadow: int
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var own := PackedVector2Array()

	func _init(surface: StringName, cast_shadow: int) -> void:
		name = surface
		shadow = cast_shadow

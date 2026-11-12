class_name StaticMerger
extends RefCounted
## Folds the static meshes of many nodes into a few nodes of one holder, and frees the ones that were
## there only to carry them. DressingBatcher.merge_segment_geometry() merges one segment's boxes into
## that segment and leaves their holders; this is the pass for a world built out of many small
## code-built pieces (a streamed cell of street pieces), where the count that hurts is the nodes as
## much as the draw calls: a piece of road is 17 boxes on 16 holders, a bridge 690 parts, and a cell
## holds twenty pieces.
##
## merge(holder, roots) walks every root and leaves under `holder`:
## - `MergedStatic`: every mesh that is pure geometry, as one mesh per shadow setting and render
##   layers, a surface per material;
## - `MergedModels`: every imported model that is nothing but geometry (a bridge's railing module, a
##   barrier), as one MultiMeshInstance3D per model: its parts merged once into one mesh, kept while
##   something draws it, and an instance per copy. A model costs its transform, not its triangles.
## A mesh is left alone, with everything under it, when it could move or change by itself: a script,
## the `animated` meta, a skin, an AnimationPlayer beside it, a hidden branch, a body that is not
## static, a `...Dressing` group (DressingBatcher's), a mirrored or sheared transform. So is one whose
## look depends on being its own object: a ShaderMaterial (it may read its own space), a transparent
## or billboard material, triplanar mapping in local space, an overlay, a visibility range.
##
## `claim` is the caller's say over what merge() would leave: it is asked about every bare mesh (no
## children, script, group or meta) of a static branch that is hidden or drawn with a material merge()
## does not fold, and a `true` means "I have taken what I wanted from it, it can go" (a game's own
## shader, folded with what it needs baked into the vertices; a mesh the game hid for good).
##
## A plain holder the pass leaves with nothing (a Node3D or a merged MeshInstance3D with no script,
## group or meta) is freed, a whole branch at a time, so an imported model that merged whole goes
## whole. Bodies, their collision shapes, areas, lights, labels and sounds stay where they are. With
## `drop_hidden`, a hidden BoxMesh straight under a StaticBody3D is freed too: the drawing of a
## collision-only box (RouteSegment._hide_box_visual), which nothing shows again.
##
## The roots themselves are never freed. Call it once the roots are in the tree (it reads global
## transforms) and have built themselves. begin() / fold() / finish() are the same pass a root at a time,
## for a caller that spreads it over frames.
##
## It is meant to run while the game plays (a cell that streams in), so it does not go through
## SurfaceTool: the triangles are moved as whole arrays. A BoxMesh is the engine's own 1 m box scaled;
## any other mesh is read once, and kept if it comes from a file (an imported model's parts, the same
## for every instance of the model). The merged mesh is loose triangles (no index); tangents are
## carried only for a material that reads them (a normal map, anisotropy or a height map outside
## triplanar mapping). A model is checked part by part the first time; a later copy with the same
## nodes, all shown and unscripted, and the same materials is taken as the same model: the parts of a
## model that a game moves by hand have to be marked `animated` (on the model) to be left out.

## Name of the merged MeshInstance3D (a second one, for another shadow setting, gets a number).
const MERGED_NAME: String = "MergedStatic"
## Name of each MultiMeshInstance3D of a model's copies.
const MODELS_NAME: String = "MergedModels"
## Metadata that marks a branch as moving (DressingBatcher's convention).
const ANIMATED_META: StringName = &"animated"
const DRESSING_SUFFIX: String = "Dressing"
## Metadata of a `MergedModels` with its instances' transforms, when DressingBatcher.record_instances
## is on (tests: a headless renderer hands none back).
const INSTANCES_META: StringName = &"instance_transforms"
## What a branch came to: nothing taken; something taken from under it; the whole branch can go.
enum { KEPT, TOOK, SPENT }
## What is known of a material: it draws the same merged; it reads the mesh's tangents.
const MERGES: int = 1
const TANGENTS: int = 2
## Which arrays a surface has besides its vertices (_Source.format).
const HAS_NORMALS: int = 1
const HAS_UVS: int = 2
const HAS_UV2S: int = 4
const HAS_COLORS: int = 8
const HAS_TANGENTS: int = 16

## The surfaces of the meshes that come from a file, read once: "<mesh id>|<surface>" -> _Source. A mesh
## made at run time is read every time: there is one per box, and keeping them would grow for ever.
static var _sources: Dictionary = {}
## The merged mesh of each model, by what it is made of (its file, its nodes and its materials): a
## WeakRef of its ArrayMesh, so it lasts as long as something draws it and is made again after that.
static var _models: Dictionary = {}
static var _unit_box: _Source


## Merges what is static under `roots` into `holder`. Returns {"parts": meshes merged, "freed": nodes
## freed, "meshes": the MeshInstance3D and MultiMeshInstance3D added to `holder`}.
static func merge(
		holder: Node3D, roots: Array, drop_hidden: bool = false, claim: Callable = Callable()) -> Dictionary:
	var job: RefCounted = begin(holder, drop_hidden, claim)
	for root: Variant in roots:
		fold(job, root as Node3D)
	return finish(job, holder)


## merge() in steps, for a caller that spreads the work over several frames: begin() once, fold() each root
## (or fold_branch() each of its children; they need not all come in one frame, and nothing is added to
## `holder` meanwhile), then finish() once, which adds the merged meshes and returns what merge() returns. The
## roots fold into the meshes as they stand in the tree when each is folded; `holder` must not move in between.
static func begin(holder: Node3D, drop_hidden: bool = false, claim: Callable = Callable()) -> RefCounted:
	var job := _Job.new()
	job.to_holder = holder.global_transform.affine_inverse()
	job.drop_hidden = drop_hidden
	job.claim = claim
	return job


## Folds what is static under `root` (not `root` itself, which is never freed) into the job begin() made.
static func fold(job: RefCounted, root: Node3D) -> void:
	if root == null or not is_instance_valid(root) or not root.visible:
		return
	for child: Node in root.get_children():
		fold_branch(job, child)


## fold() of a single child of a root, for a caller that slices finer than a root: the branch is folded and,
## if nothing of it is left, freed.
static func fold_branch(job: RefCounted, branch: Node) -> void:
	if branch != null and is_instance_valid(branch) and _fold(branch, job as _Job) == SPENT:
		branch.free()


## Adds the job's merged meshes to `holder`. Returns {"parts", "freed", "meshes"}, as merge().
static func finish(job_ref: RefCounted, holder: Node3D) -> Dictionary:
	var job := job_ref as _Job
	var made: Array[GeometryInstance3D] = []
	for key: int in job.groups:
		var group: _Group = job.groups[key]
		var instance := MeshInstance3D.new()
		instance.name = MERGED_NAME
		instance.mesh = group.mesh()
		_add(holder, instance, group.shadow, group.layers, made)
	for key: String in job.models:
		var batch: _Batch = job.models[key]
		var copies := MultiMeshInstance3D.new()
		copies.name = MODELS_NAME
		copies.multimesh = batch.multimesh()
		if DressingBatcher.record_instances:
			copies.set_meta(INSTANCES_META, batch.transforms.duplicate())
		_add(holder, copies, batch.shadow, batch.layers, made)
	return {"parts": job.parts, "freed": job.freed, "meshes": made}


## True for a mesh merge() would fold: static geometry with materials that draw the same merged.
static func is_mergeable(part: MeshInstance3D) -> bool:
	return _mergeable(part, null)


## True for a node that is geometry and nothing else, so what is under it can be folded: a Node3D, a
## StaticBody3D or a MeshInstance3D with no behaviour of its own, shown, not marked as moving.
static func is_static_branch(node: Node) -> bool:
	if node.get_script() != null:
		return false
	var kind: String = node.get_class()
	if kind != "Node3D" and kind != "MeshInstance3D" and kind != "StaticBody3D":
		return false
	if not (node as Node3D).visible or node.has_meta(ANIMATED_META):
		return false
	if String(node.name).ends_with(DRESSING_SUFFIX):
		return false
	if node.get_child_count() > 0:
		for child: Node in node.get_children():
			if child is AnimationPlayer:
				return false
	return true


static func _add(holder: Node3D, instance: GeometryInstance3D, shadow: int, layers: int, made: Array) -> void:
	instance.cast_shadow = shadow as GeometryInstance3D.ShadowCastingSetting
	instance.layers = layers
	# A readable name when there are several: MergedStatic2, not @MeshInstance3D@N.
	holder.add_child(instance, true)
	made.append(instance)


static func _mergeable(part: MeshInstance3D, job: _Job) -> bool:
	var mesh: Mesh = part.mesh
	if mesh == null or part.skin != null or part.material_overlay != null:
		return false
	if part.visibility_range_end > 0.0 or part.visibility_range_begin > 0.0 or part.transparency > 0.0:
		return false
	var basis: Basis = part.global_basis
	if basis.determinant() <= 0.0 or not basis.is_conformal():
		return false  # Mirrored, the merged triangles would face the other way; sheared, so would the normals.
	var arrays := mesh as ArrayMesh
	for surface: int in mesh.get_surface_count():
		if arrays != null and arrays.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		if _flags(part.get_active_material(surface), job) & MERGES == 0:
			return false
	return true


## MERGES and TANGENTS of a material, looked at once per job.
static func _flags(material: Material, job: _Job) -> int:
	if material == null:
		return MERGES
	var id: int = material.get_instance_id()
	if job != null and job.materials.has(id):
		return job.materials[id]
	var flags: int = (MERGES if _merges(material) else 0) | (TANGENTS if _reads_tangents(material) else 0)
	if job != null:
		job.materials[id] = flags
	return flags


static func _merges(material: Material) -> bool:
	var base := material as BaseMaterial3D
	if base == null:
		return false
	if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return false
	if base.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return false
	if (base.uv1_triplanar and not base.uv1_world_triplanar) or (base.uv2_triplanar and not base.uv2_world_triplanar):
		return false
	return true


static func _reads_tangents(material: Material) -> bool:
	var base := material as BaseMaterial3D
	if base == null or base.uv1_triplanar:
		return false
	return base.normal_enabled or base.anisotropy_enabled or base.heightmap_enabled


## Folds what is static under `node` and says what the branch came to. A SPENT branch is not freed
## here: whoever holds it frees it whole, in one go.
static func _fold(node: Node, job: _Job) -> int:
	if not is_static_branch(node):
		if not _is_dead(node, job):
			return KEPT
		job.freed += 1
		return SPENT
	if not node.scene_file_path.is_empty():
		var copied: int = _fold_model(node as Node3D, job)
		if copied > 0:
			job.freed += copied
			return SPENT
	var took: bool = false
	var spent: Array[Node] = []
	var children: Array[Node] = node.get_children()
	for child: Node in children:
		var state: int = _fold(child, job)
		if state == SPENT:
			spent.append(child)
		took = took or state != KEPT
	var part := node as MeshInstance3D
	var mine: bool = false
	if part != null:
		if _mergeable(part, job):
			_append(job, job.group_of(part), part, job.to_holder * part.global_transform)
			job.parts += 1
			mine = true
		elif children.is_empty() and job.claim.is_valid() and _is_bare(part) and job.claim.call(part):
			mine = true
	# Only a holder this pass emptied: one that was empty before may be somebody's marker.
	if (mine or took) and spent.size() == children.size() and (part == null or mine) and _is_bare(node):
		job.freed += 1
		return SPENT
	if mine:
		part.mesh = null
	for child: Node in spent:
		child.free()
	return TOOK if (mine or took) else KEPT


## A Node3D or a MeshInstance3D that is nobody's but its parent's: no group and no meta (and, being
## in a static branch, no script).
static func _is_bare(node: Node) -> bool:
	if node.get_class() == "StaticBody3D":
		return false
	return node.get_groups().is_empty() and node.get_meta_list().is_empty()


## A mesh outside the static branches that goes all the same: a hidden collision-only box, or what
## the caller claims of what is hidden.
static func _is_dead(node: Node, job: _Job) -> bool:
	var part := node as MeshInstance3D
	if part == null or part.visible or part.get_script() != null or part.get_child_count() > 0:
		return false
	if not part.get_groups().is_empty() or not part.get_meta_list().is_empty():
		return false
	if job.drop_hidden and part.mesh is BoxMesh and part.get_parent() is StaticBody3D:
		return true
	return job.claim.is_valid() and job.claim.call(part)


## Appends `part`, placed by `local` in the space of whatever the group becomes.
static func _append(job: _Job, group: _Group, part: MeshInstance3D, local: Transform3D) -> void:
	# Unit normals whatever the part's scale: the basis is conformal (_mergeable).
	var turn := Transform3D(local.basis.orthonormalized(), Vector3.ZERO)
	var mesh: Mesh = part.mesh
	var box := mesh as BoxMesh
	var plain_box: bool = box != null and box.subdivide_width == 0 and box.subdivide_height == 0 \
			and box.subdivide_depth == 0
	var placed: Transform3D = local.scaled_local(box.size) if plain_box else local
	for surface: int in mesh.get_surface_count():
		var material: Material = part.get_active_material(surface)
		var source: _Source = _box_source() if plain_box else _source_of(mesh, surface)
		var tangents: bool = _flags(material, job) & TANGENTS != 0
		group.target_of(material, source, tangents).append(source, placed, turn)


## The engine's BoxMesh of 1 m, read once: every plain box is this one scaled to its size.
static func _box_source() -> _Source:
	if _unit_box == null:
		_unit_box = _Source.new(BoxMesh.new().surface_get_arrays(0))
	return _unit_box


static func _source_of(mesh: Mesh, surface: int) -> _Source:
	if mesh.resource_path.is_empty():
		return _Source.new(mesh.surface_get_arrays(surface))
	var key: String = "%d|%d" % [mesh.get_instance_id(), surface]
	if not _sources.has(key):
		var source := _Source.new(mesh.surface_get_arrays(surface))
		# Holds the mesh: its id is the key, and a freed mesh's id can be given to another.
		source.mesh = mesh
		_sources[key] = source
	return _sources[key] as _Source


## `model` (the root of an instanced scene) as one more copy of its merged mesh, if all of it is static
## geometry that nothing else holds. Returns how many nodes it is (they can go), 0 to leave it to be
## folded part by part.
static func _fold_model(model: Node3D, job: _Job) -> int:
	if not _is_bare(model) or model.global_basis.determinant() <= 0.0:
		return 0
	var nodes: Array[Node] = model.find_children("*", "", true, false)
	var parts: Array[MeshInstance3D] = []
	var made_of := PackedInt64Array([nodes.size()])
	var shadow: int = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var layers: int = -1
	nodes.push_front(model)
	for node: Node in nodes:
		var part := node as MeshInstance3D
		if part == null or part.mesh == null:
			# What is not a mesh has to be a plain, shown Node3D; the rest is looked at below, once.
			if node != model and (not (node is Node3D) or node.get_script() != null or not (node as Node3D).visible):
				return 0
			continue
		if node != model and (part.get_script() != null or not part.visible):
			return 0
		if layers != -1 and part.layers != layers:
			return 0
		layers = part.layers
		shadow = maxi(shadow, part.cast_shadow)
		parts.append(part)
		for surface: int in part.mesh.get_surface_count():
			var material: Material = part.get_active_material(surface)
			made_of.append(material.get_instance_id() if material != null else 0)
	if parts.is_empty():
		return 0
	made_of.append(shadow)
	made_of.append(layers)
	var key: String = model.scene_file_path + "|" + made_of.to_byte_array().hex_encode()
	if job.not_models.has(key):
		return 0
	if not job.models.has(key):
		var mesh: ArrayMesh = _model_mesh(key, model, parts, job)
		if mesh == null:
			job.not_models[key] = true
			return 0
		job.models[key] = _Batch.new(mesh, shadow, layers)
	(job.models[key] as _Batch).transforms.append(job.to_holder * model.global_transform)
	job.parts += parts.size()
	return nodes.size()


## The model's parts as one mesh in the model's own space, a surface per material: the one already
## made for `key` while something still draws it. Null if the model is more than static geometry.
static func _model_mesh(key: String, model: Node3D, parts: Array[MeshInstance3D], job: _Job) -> ArrayMesh:
	var mesh: ArrayMesh = null
	if _models.has(key):
		mesh = (_models[key] as WeakRef).get_ref() as ArrayMesh
	if mesh != null:
		return mesh
	if not _is_all_static(model, job):
		return null
	var inverse: Transform3D = model.global_transform.affine_inverse()
	var group := _Group.new(0, 0)
	for part: MeshInstance3D in parts:
		_append(job, group, part, inverse * part.global_transform)
	mesh = group.mesh()
	# The meshes nothing draws any more leave their key behind: swept here, so the list stays short.
	for old: String in _models.keys():
		if (_models[old] as WeakRef).get_ref() == null:
			_models.erase(old)
	_models[key] = weakref(mesh)
	return mesh


## True if everything under `node` is static geometry of its own: bare nodes and meshes that merge.
static func _is_all_static(node: Node, job: _Job) -> bool:
	for child: Node in node.get_children():
		if not is_static_branch(child) or not _is_bare(child):
			return false
		var part := child as MeshInstance3D
		if part != null and part.mesh != null and not _mergeable(part, job):
			return false
		if not _is_all_static(child, job):
			return false
	var own := node as MeshInstance3D
	return own == null or own.mesh == null or _mergeable(own, job)


class _Job extends RefCounted:
	var to_holder: Transform3D
	var drop_hidden: bool = false
	var claim: Callable
	## (shadow << 32 | layers) -> _Group
	var groups: Dictionary = {}
	## What a model is made of (StaticMerger._fold_model's key) -> _Batch
	var models: Dictionary = {}
	## The same key for the models that turned out to be more than geometry.
	var not_models: Dictionary = {}
	## material id -> MERGES | TANGENTS
	var materials: Dictionary = {}
	var parts: int = 0
	var freed: int = 0

	func group_of(part: MeshInstance3D) -> _Group:
		var key: int = (part.cast_shadow << 32) | part.layers
		if not groups.has(key):
			groups[key] = _Group.new(part.cast_shadow, part.layers)
		return groups[key] as _Group


## What becomes one MeshInstance3D: the parts of one shadow setting and render layers.
class _Group extends RefCounted:
	var shadow: int
	var layers: int
	## material id -> { which arrays (_Source.format, and HAS_TANGENTS if carried) -> _Target }: a surface each.
	var targets: Dictionary = {}

	func _init(cast_shadow: int, render_layers: int) -> void:
		shadow = cast_shadow
		layers = render_layers

	func target_of(material: Material, source: _Source, with_tangents: bool) -> _Target:
		var id: int = material.get_instance_id() if material != null else 0
		var format: int = source.format
		if not with_tangents:
			format &= ~HAS_TANGENTS
		if not targets.has(id):
			targets[id] = {}
		var formats: Dictionary = targets[id]
		if not formats.has(format):
			var made := _Target.new()
			made.material = material
			made.with_tangents = format & HAS_TANGENTS != 0
			formats[format] = made
		return formats[format] as _Target

	func mesh() -> ArrayMesh:
		var made := ArrayMesh.new()
		for id: int in targets:
			var formats: Dictionary = targets[id]
			for format: int in formats:
				var target: _Target = formats[format]
				made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, target.arrays())
				made.surface_set_material(made.get_surface_count() - 1, target.material)
		return made


## The copies of one model: its merged mesh and where each copy stands, in the holder's space.
class _Batch extends RefCounted:
	var model: ArrayMesh
	var shadow: int
	var layers: int
	var transforms: Array[Transform3D] = []

	func _init(mesh: ArrayMesh, cast_shadow: int, render_layers: int) -> void:
		model = mesh
		shadow = cast_shadow
		layers = render_layers

	func multimesh() -> MultiMesh:
		var made := MultiMesh.new()
		made.transform_format = MultiMesh.TRANSFORM_3D
		made.mesh = model
		made.instance_count = transforms.size()
		# One upload: 12 numbers a copy, the 3x4 matrix row by row (a basis row, then its origin).
		var buffer := PackedFloat32Array()
		buffer.resize(transforms.size() * 12)
		for index: int in transforms.size():
			var basis: Basis = transforms[index].basis
			var origin: Vector3 = transforms[index].origin
			var at: int = index * 12
			buffer[at] = basis.x.x
			buffer[at + 1] = basis.y.x
			buffer[at + 2] = basis.z.x
			buffer[at + 3] = origin.x
			buffer[at + 4] = basis.x.y
			buffer[at + 5] = basis.y.y
			buffer[at + 6] = basis.z.y
			buffer[at + 7] = origin.y
			buffer[at + 8] = basis.x.z
			buffer[at + 9] = basis.y.z
			buffer[at + 10] = basis.z.z
			buffer[at + 11] = origin.z
		made.buffer = buffer
		return made


## One surface of a mesh as loose triangles (three vertices each, no index).
class _Source extends RefCounted:
	var mesh: Mesh
	## Which arrays it has: HAS_NORMALS | HAS_UVS...
	var format: int = 0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	## Four numbers a vertex, as the engine keeps them: the direction and the bitangent's sign.
	var tangents := PackedFloat32Array()

	func _init(arrays: Array) -> void:
		var index := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			index = arrays[Mesh.ARRAY_INDEX]
		if arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			vertices = _loose(arrays[Mesh.ARRAY_VERTEX], index)
		if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
			normals = _loose(arrays[Mesh.ARRAY_NORMAL], index)
		if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
			uvs = _loose(arrays[Mesh.ARRAY_TEX_UV], index)
		if arrays[Mesh.ARRAY_TEX_UV2] is PackedVector2Array:
			uv2s = _loose(arrays[Mesh.ARRAY_TEX_UV2], index)
		if arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
			colors = _loose(arrays[Mesh.ARRAY_COLOR], index)
		if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
			var packed: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			if index.is_empty():
				tangents = packed
			else:
				for at: int in index:
					tangents.append_array(packed.slice(at * 4, at * 4 + 4))
		format = (0 if normals.is_empty() else HAS_NORMALS) | (0 if uvs.is_empty() else HAS_UVS) \
				| (0 if uv2s.is_empty() else HAS_UV2S) | (0 if colors.is_empty() else HAS_COLORS) \
				| (0 if tangents.is_empty() else HAS_TANGENTS)

	## `values` (any packed array, one entry a vertex) in the order `index` draws them.
	func _loose(values: Variant, index: PackedInt32Array) -> Variant:
		if index.is_empty():
			return values
		var loose: Variant = values.duplicate()
		loose.resize(index.size())
		for at: int in index.size():
			loose[at] = values[index[at]]
		return loose


## One surface of the merged mesh.
class _Target extends RefCounted:
	var material: Material
	var with_tangents: bool = false
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var tangents := PackedFloat32Array()

	## Adds `source` placed by `placed`, its directions turned by `turn` (a rotation).
	func append(source: _Source, placed: Transform3D, turn: Transform3D) -> void:
		vertices.append_array(placed * source.vertices)
		normals.append_array(turn * source.normals)
		uvs.append_array(source.uvs)
		uv2s.append_array(source.uv2s)
		colors.append_array(source.colors)
		if with_tangents:
			var at: int = tangents.size()
			tangents.append_array(source.tangents)
			for first: int in range(at, tangents.size(), 4):
				var turned: Vector3 = turn.basis * Vector3(tangents[first], tangents[first + 1], tangents[first + 2])
				tangents[first] = turned.x
				tangents[first + 1] = turned.y
				tangents[first + 2] = turned.z

	func arrays() -> Array:
		var made: Array = []
		made.resize(Mesh.ARRAY_MAX)
		made[Mesh.ARRAY_VERTEX] = vertices
		if not normals.is_empty():
			made[Mesh.ARRAY_NORMAL] = normals
		if not uvs.is_empty():
			made[Mesh.ARRAY_TEX_UV] = uvs
		if not uv2s.is_empty():
			made[Mesh.ARRAY_TEX_UV2] = uv2s
		if not colors.is_empty():
			made[Mesh.ARRAY_COLOR] = colors
		if with_tangents:
			made[Mesh.ARRAY_TANGENT] = tangents
		return made

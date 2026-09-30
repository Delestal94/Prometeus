class_name GoalLotKit
extends RefCounted
## Building blocks for the goal lot (route_goal_lot.gd): coloured boxes folded
## into one mesh, and authored models folded into one mesh per model. The lot
## is dozens of pieces; in GL Compatibility every MeshInstance3D is a draw
## call, so it is built as a handful of meshes instead.

## One shared material for every vertex-coloured mesh (roughness like the
## route's own boxes, RouteProps.material()).
static var _coloured: StandardMaterial3D
static var _glass: StandardMaterial3D
static var _unit_box: Array = []
## path|season|night|variant -> Mesh, shared by every lot of the session.
static var _merged: Dictionary = {}


static func coloured_material() -> StandardMaterial3D:
	if _coloured == null:
		_coloured = StandardMaterial3D.new()
		_coloured.vertex_color_use_as_albedo = true
		_coloured.roughness = 0.95
	return _coloured


## The pane material of the parked trucks: see-through like the driven truck's
## (reference_truck.gd _make_glass_transparent()).
static func glass_material() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.resource_name = "LotTruckGlass"
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.albedo_color = Color(0.62, 0.82, 0.9, 0.16)
		_glass.roughness = 0.06
		_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glass.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		_glass.disable_receive_shadows = true
	return _glass


## Boxes of any size, turn and colour, gathered into one mesh with a colour
## per vertex. Nothing is drawn until build().
class Boxes:
	extends RefCounted

	var count: int = 0
	var _tool := SurfaceTool.new()

	func _init() -> void:
		_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	## A box of `size` at `xform` (its centre), flat colour.
	func add(size: Vector3, xform: Transform3D, color: Color) -> void:
		var unit: Array = GoalLotKit.unit_box()
		var vertices: PackedVector3Array = unit[0]
		var normals: PackedVector3Array = unit[1]
		var indices: PackedInt32Array = unit[2]
		for index: int in indices:
			_tool.set_color(color)
			_tool.set_normal((xform.basis * normals[index]).normalized())
			_tool.add_vertex(xform * (vertices[index] * size))
		count += 1

	## Same, from a corner-based description: the box sits on `bottom_centre`.
	func add_standing(size: Vector3, bottom_centre: Vector3, color: Color, yaw: float = 0.0) -> void:
		add(size, Transform3D(Basis(Vector3.UP, yaw), bottom_centre + Vector3.UP * size.y * 0.5), color)

	func build(material: Material = null) -> MeshInstance3D:
		var instance := MeshInstance3D.new()
		if count == 0:
			return instance
		instance.mesh = _tool.commit()
		instance.material_override = material if material != null else GoalLotKit.coloured_material()
		return instance


## A unit box's [vertices, normals, indices], from Godot's own BoxMesh so the
## winding is the engine's.
static func unit_box() -> Array:
	if _unit_box.is_empty():
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		var arrays: Array = box.get_mesh_arrays()
		_unit_box = [arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], arrays[Mesh.ARRAY_INDEX]]
	return _unit_box


## A scene's meshes folded into one mesh in the scene root's space, a surface
## per material. `prepare` (optional) gets the fresh instance first, to pose
## it or swap materials. `variant` tells poses apart in the cache.
static func merged_model(path: String, variant: String = "", prepare: Callable = Callable(),
		apply_palette: bool = true) -> Mesh:
	var key: String = "%s|%d|%.2f|%s" % [path, DetailMaterials.season, DetailMaterials.night_level, variant]
	if _merged.has(key):
		return _merged[key]
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate() as Node3D
	if apply_palette:
		LowpolyMaterials.apply(root)
	if prepare.is_valid():
		prepare.call(root)
	var mesh: Mesh = merge_parts(root)
	root.free()
	_merged[key] = mesh
	return mesh


## Every MeshInstance3D under `root`, in root's space, one surface per material.
static func merge_parts(root: Node3D) -> ArrayMesh:
	var tools: Dictionary = {}
	var materials: Dictionary = {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null or not part.visible:
			continue
		var local: Transform3D = relative_transform(part, root)
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
	return merged


## `node`'s transform in `root`'s space, for a scene that is not in the tree.
static func relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var walker: Node = node
	while walker != root and walker is Node3D:
		result = (walker as Node3D).transform * result
		walker = walker.get_parent()
	return result


## A MultiMesh of `mesh` at `xforms` (parent space).
static func multimesh_instance(mesh: Mesh, xforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = xforms.size()
	for index: int in range(xforms.size()):
		multimesh.set_instance_transform(index, xforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	return instance

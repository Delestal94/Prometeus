extends Node3D
class_name RouteSegment
## Base for a chainable, streamable route piece. Each segment builds itself
## in local space, centred on its own length along -Z (entry at z=0, exit at
## z=-length) so RouteStreamer can place the next one right after it without
## either segment knowing about the other's contents.
##
## Deliberately code-built, no .tscn, same convention as the handcrafted
## route.gd -- there's no art yet, so a script is the actual source of truth.

@export var length: float = 20.0

## Where the NEXT segment should start, in THIS segment's own local space.
## Every existing segment (straight, bump, chicane, bridge, gravel,
## construction, S-curve) still exits at local (0,0,-length) with no turn --
## that's the default below and none of them need to touch it. Only a
## segment that actually bends the road (CurveSegment) overrides these after
## computing where its arc really ends up, so the chain (RouteStreamer, or
## route.gd's own procedural spine) can place the next piece correctly no
## matter which kind of segment came before it.
var exit_offset: Vector3
var exit_turn: float = 0.0
var continuous_terrain: bool = false

const ROAD := Color("394a50")
const SHOULDER := Color("63736f")
const MARKING := Color("d4d9c2")
const WARNING := Color("e7be51")
const CONCRETE := Color("8c9791")

var _materials: Dictionary = {}


func _ready() -> void:
	exit_offset = Vector3(0.0, 0.0, -length)
	_build()


## Local-space transforms roughly `spacing` apart along the segment's ACTUAL
## path, for the caller to hang dressing (trees, props) off of without it
## floating away from a curved road -- default assumes a straight local -Z
## run, true for every segment except CurveSegment, which overrides this to
## walk its own chord chain instead of this straight-line approximation.
func get_dressing_slots(spacing: float) -> Array[Transform3D]:
	var slots: Array[Transform3D] = []
	var z: float = 0.0
	while z > -length:
		slots.append(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, z)))
		z -= spacing
	return slots


## Overridden by each concrete segment type.
func _build() -> void:
	pass


func _box(node_name: String, size: Vector3, location: Vector3, color: Color, solid: bool = false) -> Node3D:
	if continuous_terrain and node_name in ["Ground", "Road", "BridgeDeck", "WaterPlaceholder"]:
		return null
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root.name = node_name
	root.position = location
	add_child(root)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _material(color)
	root.add_child(mesh)
	if solid:
		var body := root as StaticBody3D
		body.collision_layer = 1
		body.collision_mask = 6
		var collider := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		collider.shape = box_shape
		body.add_child(collider)
	return root


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[color] = material
	return _materials[color] as StandardMaterial3D

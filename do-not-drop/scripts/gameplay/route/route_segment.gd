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

## How tall the obstacles' collision is (see _block()).
const BLOCK_COLLISION_HEIGHT: float = 1.6
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


## Runtime route pieces remain code-built, but no longer have to rebuild every
## visible prop from cubes.  Keep collision primitives separate from imported
## art: the former are deterministic and cheap, while the latter can evolve
## without changing driving physics.
func _model(node_name: String, path: String, location: Vector3, rotation_y: float = 0.0, scale_factor: float = 1.0) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Missing route model: " + path)
		return null
	var model := scene.instantiate() as Node3D
	model.name = node_name
	model.position = location
	model.rotation.y = rotation_y
	model.scale = Vector3.ONE * scale_factor
	add_child(model)
	return model


## A concrete block the truck must steer round (chicane, S-curve): drawn at
## its real size, but solid up to BLOCK_COLLISION_HEIGHT. At the drawn 0.8 m it
## was taller than the truck's ground clearance and lower than what its wheels
## reach, so a truck that clipped one at an angle could end up sitting on top
## with its front wheels in the air (N-803). The solid node keeps `node_name`.
func _block(node_name: String, size: Vector3, location: Vector3, color: Color) -> Node3D:
	_box(node_name + "Visual", size, location, color)
	var solid_size := Vector3(size.x, BLOCK_COLLISION_HEIGHT, size.z)
	var solid: Node3D = _box(node_name, solid_size, Vector3(location.x, location.y - size.y * 0.5 + BLOCK_COLLISION_HEIGHT * 0.5, location.z), color, true)
	_hide_box_visual(solid)
	return solid


func _hide_box_visual(body: Node3D) -> void:
	if body == null:
		return
	for child: Node in body.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
		# Back faces culled: double-sided, the underside of every flat marking
		# z-fought the terrain a few millimetres below it (flicker) and box
		# sides shadowed themselves in fine stripes.
		_materials[color] = material
	return _materials[color] as StandardMaterial3D

class_name CargoGull
extends Node3D
## The gull that goes for the cargo (N-109.1), built from primitives with the
## palette so it reads as one from the driver's seat and from the rack: white
## body and head, grey back and wings with dark tips, a yellow beak with a red
## spot, orange legs and feet. The bird of the roadside is a brown blob at this
## size; this one has the silhouette -- spread wings when it swoops, folded
## ones when it perches. Front is -Z like every model here.
##
## Nothing in here moves by itself: cargo_animal_view.gd calls pose() with its
## own clock each frame, so every peer and every capture draws the same frame.
## Cost: 13 meshes, shared materials and meshes across every gull.

## Real size: body 0.6 m long, wingspan 1.3 m. The view scales it up a little
## so the species is readable from across the depot.

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}

var _wing_left: Node3D
var _wing_right: Node3D
var _tip_left: Node3D
var _tip_right: Node3D
var _body: Node3D
var _legs: Node3D
var _head: Node3D


func _init() -> void:
	name = "Gull"
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	# Torso: a rounded egg, the chest forward and up.
	_part(_body, "Torso", _sphere(&"sphere"), &"white", Vector3(0.0, 0.0, 0.0), Vector3(0.26, 0.24, 0.46))
	_part(_body, "Back", _sphere(&"sphere"), &"grey", Vector3(0.0, 0.08, 0.05), Vector3(0.24, 0.14, 0.38))
	_part(_body, "Tail", _box(&"tail", Vector3(0.14, 0.03, 0.2)), &"white", Vector3(0.0, 0.03, 0.36), Vector3(1, 1, 1),
			Vector3(0.18, 0.0, 0.0))
	_part(_body, "TailTip", _box(&"tailtip", Vector3(0.14, 0.032, 0.05)), &"dark", Vector3(0.0, 0.03, 0.47),
			Vector3(1, 1, 1),
			Vector3(0.18, 0.0, 0.0))
	# Neck, head and beak, on one pivot so the bird can hunch on a low shelf.
	_head = Node3D.new()
	_head.name = "HeadGroup"
	_body.add_child(_head)
	_part(_head, "Neck", _sphere(&"sphere"), &"white", Vector3(0.0, 0.13, -0.2), Vector3(0.12, 0.15, 0.14))
	_part(_head, "Head", _sphere(&"sphere"), &"white", Vector3(0.0, 0.22, -0.3), Vector3(0.16, 0.16, 0.18))
	_part(_head, "Beak", _box(&"beak", Vector3(0.045, 0.04, 0.14)), &"yellow", Vector3(0.0, 0.2, -0.46),
			Vector3(1, 1, 1),
			Vector3(-0.12, 0.0, 0.0))
	_part(_head, "BeakSpot", _box(&"beakspot", Vector3(0.048, 0.02, 0.035)), &"red", Vector3(0.0, 0.175, -0.5))
	_part(_head, "EyeL", _sphere(&"sphere"), &"dark", Vector3(-0.075, 0.25, -0.35), Vector3(0.035, 0.035, 0.035))
	_part(_head, "EyeR", _sphere(&"sphere"), &"dark", Vector3(0.075, 0.25, -0.35), Vector3(0.035, 0.035, 0.035))
	# Wings: a shoulder pivot each, the grey arm, and a dark tip that hangs off it.
	_wing_left = _make_wing("WingL", -1.0)
	_wing_right = _make_wing("WingR", 1.0)
	_tip_left = _wing_left.get_node("Tip") as Node3D
	_tip_right = _wing_right.get_node("Tip") as Node3D
	# Legs: two orange sticks with flat feet, tucked when it flies.
	_legs = Node3D.new()
	_legs.name = "Legs"
	_legs.position = Vector3(0.0, -0.06, 0.03)
	_body.add_child(_legs)
	for side: float in [-1.0, 1.0]:
		_part(_legs, "Leg", _box(&"leg", Vector3(0.025, 0.08, 0.025)), &"orange", Vector3(side * 0.06, -0.04, 0.0))
		_part(_legs, "Foot", _box(&"foot", Vector3(0.07, 0.015, 0.1)), &"orange", Vector3(side * 0.06, -0.08, -0.03))
	pose(false, 0.0)


## `flying`: wings beating wide; otherwise perched, wings folded against the
## body with a little shiver. `time` is the view's own clock.
func pose(flying: bool, time: float) -> void:
	if flying:
		var beat: float = sin(time * 13.0)
		var arm: float = -0.05 + beat * 0.6
		_wing_left.rotation = Vector3(0.0, 0.0, arm)
		_wing_right.rotation = Vector3(0.0, 0.0, -arm)
		_tip_left.rotation = Vector3(0.0, 0.0, -beat * 0.35 + 0.1)
		_tip_right.rotation = Vector3(0.0, 0.0, beat * 0.35 - 0.1)
		_wing_left.scale = Vector3.ONE
		_wing_right.scale = Vector3.ONE
		_legs.visible = false
		_body.rotation.x = -0.12 + beat * 0.03
		_head.position = Vector3.ZERO
		_head.rotation.x = 0.0
		_body.position.y = beat * 0.02
	else:
		var shiver: float = sin(time * 9.0) * 0.03
		# Wings folded: swung back along the flanks, shorter and narrower, the dark
		# tips reaching past the tail like a real gull's.
		_wing_left.rotation = Vector3(0.0, PI * 0.5, shiver)
		_wing_right.rotation = Vector3(0.0, -PI * 0.5, -shiver)
		_wing_left.scale = Vector3(0.55, 1.0, 0.55)
		_wing_right.scale = Vector3(0.55, 1.0, 0.55)
		_tip_left.rotation = Vector3.ZERO
		_tip_right.rotation = Vector3.ZERO
		_legs.visible = true
		_body.rotation.x = 0.0
		_body.position.y = 0.13 + absf(sin(time * 5.0)) * 0.01
		_head.position = Vector3(0.0, -0.03, 0.02)
		_head.rotation.x = 0.25


func _make_wing(wing_name: String, side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = wing_name
	pivot.position = Vector3(side * 0.14, 0.1, -0.03)
	_body.add_child(pivot)
	# The arm: out from the shoulder along x.
	_part(pivot, "Arm", _box(&"arm", Vector3(0.36, 0.028, 0.26)), &"grey", Vector3(side * 0.18, 0.0, 0.03))
	var tip := Node3D.new()
	tip.name = "Tip"
	tip.position = Vector3(side * 0.36, 0.0, 0.0)
	pivot.add_child(tip)
	_part(tip, "Feathers", _box(&"feathers", Vector3(0.3, 0.022, 0.2)), &"dark", Vector3(side * 0.15, 0.0, 0.08))
	return pivot


func _part(parent: Node3D, part_name: String, mesh: Mesh, material_key: StringName, at: Vector3,
		part_scale: Vector3 = Vector3.ONE, part_rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = _material(material_key)
	instance.position = at
	instance.scale = part_scale
	instance.rotation = part_rotation
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## A unit sphere (diameter 1): every round part is this, scaled.
static func _sphere(key: StringName) -> Mesh:
	if not _meshes.has(key):
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 10
		mesh.rings = 6
		_meshes[key] = mesh
	return _meshes[key]


static func _box(key: StringName, size: Vector3) -> Mesh:
	if not _meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	return _meshes[key]


static func _material(key: StringName) -> Material:
	if not _materials.has(key):
		var colors: Dictionary = {
			&"white": Color("f4f1e8"), &"grey": Color("a7b0b8"), &"dark": Color("3b4048"),
			&"yellow": Color("f5b71e"), &"red": Color("d8402e"), &"orange": Color("e5822d"),
		}
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[key]
		material.roughness = 0.9
		_materials[key] = material
	return _materials[key]

extends Node3D
## The comic tow truck that drags a bogged van out of the mud (N-108), built
## from primitives: a yellow chassis, a cab, a boom with a hook, a spinning
## beacon and a "GRUA" board. Purely visual and local to every peer: MudSegment
## says where it stands and when it goes (the tow itself is the host's).
## Faces -Z like everything else; its hook hangs off the back (+Z).

const BODY := Color("e0a526")
const CAB := Color("f0efe6")
const DARK := Color("2b2f33")
const RED := Color("c43b2b")
const SIZE := Vector3(2.6, 0.7, 6.0)
## Where the cable leaves the boom, in the crane's own frame.
const HOOK_LOCAL := Vector3(0.0, 2.1, 3.6)
## Fixed materials for the whole session (a crane is rare; still no reason to
## make eight materials each time).
static var _materials: Dictionary = {}

var _beacon: MeshInstance3D
var _body: Node3D
var _time: float = 0.0


func _init() -> void:
	name = "MudCrane"
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_part("Chassis", SIZE, Vector3(0.0, 0.85, 0.0), BODY)
	_part("Cab", Vector3(2.3, 1.2, 1.9), Vector3(0.0, 1.8, -1.9), CAB)
	_part("Windshield", Vector3(2.0, 0.6, 0.06), Vector3(0.0, 2.0, -2.88), DARK)
	_part("Bumper", Vector3(2.7, 0.35, 0.3), Vector3(0.0, 0.6, -3.1), RED)
	# The boom leans back over the tail; the hook hangs from its tip.
	var boom := _part("Boom", Vector3(0.35, 0.35, 3.6), Vector3(0.0, 2.6, 1.8), DARK)
	boom.rotation.x = deg_to_rad(-16.0)
	_part("Hook", Vector3(0.18, 0.5, 0.18), HOOK_LOCAL - Vector3(0.0, 0.3, 0.0), RED)
	for side: float in [-1.0, 1.0]:
		for z: float in [-2.0, 2.0]:
			var wheel := _part("Wheel", Vector3(0.45, 1.0, 1.0), Vector3(side * 1.3, 0.5, z), DARK)
			wheel.name = "Wheel"
	_beacon = _part("Beacon", Vector3(0.4, 0.3, 0.4), Vector3(0.0, 2.55, -1.9), Color("ffb020"), true)
	var board := Label3D.new()
	board.name = "Board"
	board.text = tr("WORLD_MUD_CRANE_LABEL")
	board.font_size = 56
	board.pixel_size = 0.008
	board.outline_size = 10
	board.modulate = Color("1c1c1c")
	board.outline_modulate = Color("f2d26b")
	board.position = Vector3(1.32, 1.05, 0.0)
	board.rotation.y = PI * 0.5
	add_child(board)
	var board_left := board.duplicate() as Label3D
	board_left.name = "BoardLeft"
	board_left.position = Vector3(-1.32, 1.05, 0.0)
	board_left.rotation.y = -PI * 0.5
	add_child(board_left)


func _process(delta: float) -> void:
	_time += delta
	# Rattles on its springs and the beacon spins: a cartoon, not a vehicle.
	_body.position.y = sin(_time * 14.0) * 0.025
	_body.rotation.z = sin(_time * 9.0) * 0.012
	_beacon.rotation.y += delta * 9.0
	_beacon.scale = Vector3.ONE * (1.0 + 0.25 * sin(_time * 18.0))


## The hook's position in world space, where the cable starts.
func hook_position() -> Vector3:
	return to_global(HOOK_LOCAL - Vector3(0.0, 0.5, 0.0))


func _part(part_name: String, size: Vector3, location: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = part_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color, glow)
	mesh.position = location
	_body.add_child(mesh)
	return mesh


static func _material(color: Color, glow: bool) -> StandardMaterial3D:
	var key := [color, glow]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.7
		if glow:
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 1.5
		_materials[key] = material
	return _materials[key] as StandardMaterial3D

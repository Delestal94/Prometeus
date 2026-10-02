extends Node3D
## The comic tow truck that drags a bogged van out of the mud (N-108): a yellow
## chassis, a cream cab, a boom with a hook, a spinning beacon and a "GRUA"
## board. The body is a low-poly model (N-321, sm_vehicle_tow_crane.glb, baked
## AO, same size and orientation as the box version it replaced); this script
## only rattles it, spins the beacon and hangs the boards. Purely visual and
## local to every peer: MudSegment says where it stands and when it goes (the
## tow itself is the host's).
## Faces -Z like everything else; its hook hangs off the back (+Z).

const MODEL_PATH: String = "res://assets/models/vehicles/sm_vehicle_tow_crane.glb"
const SIZE := Vector3(2.6, 0.7, 6.0)
## Where the cable leaves the boom, in the crane's own frame.
const HOOK_LOCAL := Vector3(0.0, 2.1, 3.6)
## The model's headlamps glow after dark, like the parked cars' (N-304).
const NIGHT_LIGHTS: Array = ["lamp"]
## Loaded once for the whole session (a crane is rare, and each one is only an
## instance of this scene with the shared palette materials).
static var _packed: PackedScene

var _beacon: Node3D
var _body: Node3D
var _time: float = 0.0


func _init() -> void:
	name = "MudCrane"
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_build_model()
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
	if _beacon != null:
		_beacon.rotation.y += delta * 9.0
		_beacon.scale = Vector3.ONE * (1.0 + 0.25 * sin(_time * 18.0))


## The hook's position in world space, where the cable starts.
func hook_position() -> Vector3:
	return to_global(HOOK_LOCAL - Vector3(0.0, 0.5, 0.0))


## The model hangs under Body so the whole truck rattles together; its own
## materials go through the palette like every other vehicle on the roadside.
func _build_model() -> void:
	if _packed == null:
		_packed = load(MODEL_PATH) as PackedScene
	if _packed == null:
		push_error("MudCrane: cannot load %s" % MODEL_PATH)
		return
	var model := _packed.instantiate() as Node3D
	model.name = "Model"
	_body.add_child(model)
	LowpolyMaterials.apply(model)
	LowpolyMaterials.light_up(model, NIGHT_LIGHTS)
	_beacon = model.find_child("Beacon", true, false) as Node3D

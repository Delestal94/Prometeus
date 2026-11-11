class_name PalletJackView
extends Node3D
## The manual pallet jack as the players see and work it in the shed (expansion D-0605.b, "Modo Empresa").
##
## It only DRAWS state: where it stands (CompanyPallets.jack_at) and the pallet on its forks (PalletJack.carrying)
## are the host's and equal on every peer, so no RPC and no random roll here. Grey-box stand-in made of boxes
## (docs/expansion-distritos/arte-pendiente/D-0605.md): two forks, the body with its wheels, and a tiller with its
## handle, 1.6 x 0.55 x 1.2 m. The node's origin is on the floor at the middle of the forks, the handle at -X:
## a pallet on the forks (PalletBox) is centred on that origin.
##
## Interaction: a PalletJackPoint over the forks (pick a pallet up, or put the carried one down) and one at the
## handle (push); they forward their `used` here. Like PickingCartView, moving it is a jump of the node to the
## spot the host decided (place_at()); only the look slides.

signal used(action: StringName, peer_id: int, from: Vector3)

const LENGTH: float = 1.6
const WIDTH: float = 0.55
const HEIGHT: float = 1.2
const FORK_LENGTH: float = 1.15
const FORK_WIDTH: float = 0.16
const FORK_HEIGHT: float = 0.09
const FORK_Z: float = 0.195
## Heights: a pallet rides this much over the floor on the forks.
const LIFT_M: float = 0.06
const HANDLE_X: float = -0.95
const FRAME_COLOR: Color = Color(0.58, 0.59, 0.61)
const SLIDE_SECONDS: float = 0.25

## The point over the forks and the point at the handle.
var work_point: PalletJackPoint
var push_point: PalletJackPoint

var _look: Node3D
var _carried: Node3D
var _carried_id: StringName = &""
var _slide: Tween


## A jack standing at `local` (the shed's frame, on the floor).
static func make(local: Vector3) -> PalletJackView:
	var view := PalletJackView.new()
	view.name = "PalletJack"
	view.position = local
	view._build()
	return view


## Draws `pallet` ({id, product, qty}) on the forks, or nothing for {}.
func show_carried(pallet: Dictionary) -> void:
	var id := StringName(pallet.get("id", &""))
	if id == _carried_id:
		return
	_carried_id = id
	if _carried != null:
		_look.remove_child(_carried)
		_carried.queue_free()
		_carried = null
	if id == &"":
		return
	_carried = PalletBox.build(pallet)
	_carried.position = Vector3(0.0, LIFT_M, 0.0)
	_look.add_child(_carried)


## The id of the pallet drawn on the forks, &"" for none.
func carried_id() -> StringName:
	return _carried_id


## Stands the jack at `local` (the shed's frame). With `slide` the look rolls there from where it was.
func place_at(local: Vector3, slide: bool = false) -> void:
	if local == position and not slide:
		return
	var from: Vector3 = position
	position = local
	if _slide != null and _slide.is_valid():
		_slide.kill()
	_look.position = Vector3.ZERO
	if slide and is_inside_tree() and from != local:
		_look.position = from - local
		_slide = create_tween()
		_slide.tween_property(_look, "position", Vector3.ZERO, SLIDE_SECONDS)


func _build() -> void:
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	_build_look()
	work_point = PalletJackPoint.make(PalletJackPoint.ACTION_WORK, Vector3(0.0, 0.5, 0.0), 0.6)
	push_point = PalletJackPoint.make(PalletJackPoint.ACTION_PUSH, Vector3(HANDLE_X - 0.05, 0.95, 0.0), 0.3)
	for point: PalletJackPoint in [work_point, push_point]:
		point.used.connect(func(how: StringName, peer_id: int, origin: Vector3) -> void:
			used.emit(how, peer_id, origin))
		add_child(point)


## The grey box: the forks, the body over the wheels, the tiller and its handle.
func _build_look() -> void:
	var material: StandardMaterial3D = DepotKit.flat(FRAME_COLOR)
	for side: float in [-1.0, 1.0]:
		_part("Fork", Vector3(FORK_LENGTH, FORK_HEIGHT, FORK_WIDTH),
			Vector3(0.0, FORK_HEIGHT * 0.5, side * FORK_Z), material)
		_part("FrontWheel", Vector3(0.1, 0.1, 0.06),
			Vector3(FORK_LENGTH * 0.5 - 0.1, 0.05, side * FORK_Z), material)
	var body_x: float = -FORK_LENGTH * 0.5 - 0.15
	_part("Body", Vector3(0.3, 0.2, WIDTH), Vector3(body_x, 0.1, 0.0), material)
	var tiller: float = HEIGHT - 0.2
	_part("Tiller", Vector3(0.05, tiller, 0.05), Vector3(HANDLE_X, 0.2 + tiller * 0.5, 0.0), material)
	_part("HandleBar", Vector3(0.05, 0.04, 0.3), Vector3(HANDLE_X, HEIGHT - 0.02, 0.0), material)


func _part(part_name: String, size: Vector3, at: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	part.mesh = mesh
	part.position = at
	_look.add_child(part)

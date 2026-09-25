extends Node3D
class_name TownSign
## The sign at each end of a village (tareas de Nacho N-601 / N-305): a green
## board on two posts with the town's name. Entering, it says tr("WORLD_TOWN_WELCOME")
## over the name; leaving, the name is crossed out with a red bar, the way
## real town-limit signs read. RouteDresser puts one where the road enters a
## village zone and one where it leaves it, on the driver's right, facing the
## traffic (+Z: the truck drives toward -Z).
##
## The names come from NAMES, dealt like a deck by the session seed
## (names_for_seed()), so every peer calls the same village the same thing and
## a route never repeats one until all twelve are used.

const NAMES: Array[String] = [
	"Villa Frágil", "Paso del Golpe", "Bajada Lenta", "Cuesta Abajo", "San Ceferino del Bache",
	"Colonia Esquina", "Puerto Sin Mar", "Loma Movida", "Villa Caja Vacía", "Arroyo Chueco",
	"El Pozo Hondo", "Tres Pozos",
]
const BOARD_SIZE := Vector2(3.4, 1.25)
const BOARD_HEIGHT: float = 2.1
const POST_GAP: float = 2.6
const BOARD_COLOR := Color("1f5e3b")
const TEXT_COLOR := Color("f1efe2")
const BAR_COLOR := Color("c8352b")
const POST_COLOR := Color("8c9791")
const FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")

@export var town_name: String = ""
@export var is_exit: bool = false


## Every name once, in a seeded order: names_for_seed(seed)[i] is the i-th
## village along the road (it wraps after twelve).
static func names_for_seed(seed_value: int) -> Array[String]:
	var deck: Array[String] = NAMES.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, &"town_names"])
	for i: int in range(deck.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: String = deck[i]
		deck[i] = deck[j]
		deck[j] = swap
	return deck


func _ready() -> void:
	var board_y: float = BOARD_HEIGHT + BOARD_SIZE.y * 0.5
	for x: float in [-POST_GAP * 0.5, POST_GAP * 0.5]:
		_box("Post", Vector3(0.1, board_y, 0.1), Vector3(x, board_y * 0.5, -0.08), POST_COLOR)
	_box("Board", Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.08), Vector3(0.0, board_y, 0.0), BOARD_COLOR)
	# A thin white border, like a real road sign's.
	_box("Border", Vector3(BOARD_SIZE.x - 0.12, BOARD_SIZE.y - 0.12, 0.085), Vector3(0.0, board_y, 0.0), TEXT_COLOR)
	_box("Face", Vector3(BOARD_SIZE.x - 0.2, BOARD_SIZE.y - 0.2, 0.09), Vector3(0.0, board_y, 0.0), BOARD_COLOR)
	var front: float = 0.05
	if is_exit:
		_text("Name", town_name, Vector3(0.0, board_y, front), 64)
		var bar := _box("Bar", Vector3(BOARD_SIZE.x * 0.95, 0.12, 0.02), Vector3(0.0, board_y, front + 0.01), BAR_COLOR)
		bar.rotation.z = atan2(BOARD_SIZE.y * 0.7, BOARD_SIZE.x)
	else:
		_text("Welcome", tr("WORLD_TOWN_WELCOME"), Vector3(0.0, board_y + 0.34, front), 34)
		_text("Name", town_name, Vector3(0.0, board_y - 0.1, front), 64)
	# Only the posts are solid: the truck stops against a post, it doesn't
	# climb a board.
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	for x: float in [-POST_GAP * 0.5, POST_GAP * 0.5]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.14, board_y, 0.14)
		shape.shape = box
		shape.position = Vector3(x, board_y * 0.5, -0.08)
		body.add_child(shape)
	add_child(body)


func _box(node_name: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = at
	add_child(node, true)
	return node


func _text(node_name: String, text: String, at: Vector3, font_size: int) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font = FONT
	label.font_size = font_size
	label.pixel_size = 0.0055
	label.modulate = TEXT_COLOR
	label.outline_size = 0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = (BOARD_SIZE.x - 0.4) / label.pixel_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = at
	add_child(label)

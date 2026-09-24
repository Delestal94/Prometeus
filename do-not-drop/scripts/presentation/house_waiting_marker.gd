extends Node3D
class_name HouseWaitingMarker
## What tells the crew, from far off, which house is still waiting for its
## box (tareas de Nacho N-501): the porch light on with a glow around it, a
## yellow balloon on a tall pole over the yard, a mailbox with the house
## number on every side the road can see, and a V-shaped sign in the front
## yard with the code of the box it ordered -- the same code the depot's
## board and the shelf show ("A-3"). Once the house is resolved (delivered,
## ruined, or driven past) the light goes out and the sign and balloon come
## down.
##
## The house stands side-on to a truck coming down the road, so nothing here
## may only face the road square on: the sign's two boards each face one way
## along it, and the balloon reads from anywhere. Sizes from the visual
## review: the code reads at ~40 m; at 120 m it's the balloon (day) and the
## glow (night) that say "this one".
##
## Presentation only, the same on every peer: it listens to
## EventBus.house_delivery_recorded, which the host relays to everyone, since
## DeliveryHouse.delivered only ever changes on the host.
##
## Space: the house's own, front facing -Z toward the road (DeliveryHouse).

const LIGHT_COLOR := Color("ffd27a")
const SIGN_COLOR := Color("ffc93c")
## Deeper than the sign's yellow: against a pale sky it has to pop.
const BALLOON_COLOR := Color("ffae00")
const POST_COLOR := Color("5b4a3a")
const INK := Color("1e2235")
const FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const BOARD_SIZE := Vector2(2.4, 1.4)
const BOARD_HEIGHT: float = 2.2
## Each board turns this far off the house front, toward one way along the
## road: at 30 a road arriving nearly parallel to the front saw the board
## too edge-on to read; 40 keeps the V 1.5 m deep.
const BOARD_ANGLE_DEG: float = 40.0
## Where things stand, measured from the front of the house model (porch
## and eaves included, `house_bounds`): the V's tip, the mailbox.
const SIGN_TIP_X: float = 2.9
const SIGN_TIP_AHEAD: float = 2.0
const MAILBOX_X: float = -2.0
const MAILBOX_AHEAD: float = 1.2
## Over the door, where DeliveryHouse puts its doorbell and resident.
const PORCH_LIGHT_AT := Vector3(0.0, 2.35, -2.75)
## The balloon floats this far over the roof, so it stands against the sky
## and not the wall; never lower than BALLOON_MIN_HEIGHT.
const BALLOON_OVER_ROOF: float = 1.5
const BALLOON_MIN_HEIGHT: float = 4.8
const BALLOON_RADIUS: float = 1.2
## The balloon's string stands this far out from the sign's tip, toward the
## road, so it never crosses a board's code.
const BALLOON_AHEAD: float = 0.7
## Widest the trap's name may run on a board, in metres.
const TRAP_TEXT_WIDTH: float = 2.1
const BALLOON_BOB_SECONDS: float = 1.2
## Used when the house has no model to measure (tests building a bare house).
const DEFAULT_BOUNDS := AABB(Vector3(-3.0, 0.0, -2.7), Vector3(6.0, 3.2, 5.4))

var house_index: int = 0
## The house model's extent in its own space; set before adding the marker.
var house_bounds: AABB = DEFAULT_BOUNDS
var waiting: bool = true
var porch_light: OmniLight3D
var sign_board: Node3D
var balloon: Node3D
## One per board of the V; code_label is the first, for whoever needs one.
var code_labels: Array[Label3D] = []
var trap_labels: Array[Label3D] = []
var code_label: Label3D
var number_labels: Array[Label3D] = []
var number_label: Label3D
var _bulb_material: StandardMaterial3D
var _halo: MeshInstance3D
var _bob: Tween


func _ready() -> void:
	_build_porch_light()
	_build_mailbox()
	_build_sign()
	_build_balloon()
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"house_delivery_recorded", _on_house_delivery_recorded)
	set_waiting(waiting)


## The code of the box this house waits for, e.g. "Frágil A-3": the last
## word (the shelf code) goes big on the sign, the trap small under it.
func set_order(label: String) -> void:
	var words: PackedStringArray = label.strip_edges().split(" ", false)
	# No order yet (or any box will do): the sign still says a delivery is due.
	var code: String = words[-1].to_upper() if not words.is_empty() else "ENTREGA"
	var trap: String = " ".join(words.slice(0, words.size() - 1)).to_upper() if words.size() > 1 else ""
	for label_node: Label3D in code_labels:
		label_node.text = code
		# A shelf code ("A-3") fills the board; anything longer has to fit it.
		label_node.font_size = 150 if code.length() <= 4 else 70
	# Long names ("PESO CRECIENTE") shrink to fit the board instead of
	# running off it; LilitaOne is ~0.6 of its size wide per letter.
	var trap_size: int = mini(64, floori(TRAP_TEXT_WIDTH / (maxf(trap.length(), 1.0) * 0.6 * 0.007)))
	for label_node: Label3D in trap_labels:
		label_node.text = trap
		label_node.font_size = trap_size


func set_number(number: int) -> void:
	for label_node: Label3D in number_labels:
		label_node.text = str(number)


func set_waiting(value: bool) -> void:
	waiting = value
	if porch_light == null:
		return
	porch_light.visible = value
	_bulb_material.emission_enabled = value
	_halo.visible = value
	sign_board.visible = value
	balloon.visible = value
	if _bob != null:
		if value:
			_bob.play()
		else:
			_bob.pause()


func _on_house_delivery_recorded(index: int, _outcome: StringName, _package_id: StringName) -> void:
	if index == house_index:
		set_waiting(false)


func _build_porch_light() -> void:
	var bulb := MeshInstance3D.new()
	bulb.name = "PorchBulb"
	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	sphere.radial_segments = 8
	sphere.rings = 4
	bulb.mesh = sphere
	_bulb_material = StandardMaterial3D.new()
	_bulb_material.albedo_color = LIGHT_COLOR
	_bulb_material.emission = LIGHT_COLOR
	_bulb_material.emission_energy_multiplier = 7.0
	bulb.material_override = _bulb_material
	bulb.position = PORCH_LIGHT_AT
	add_child(bulb)
	# A soft glow around the bulb: at night, from far off, a point of light
	# a few pixels wide is all the porch gets otherwise.
	_halo = MeshInstance3D.new()
	_halo.name = "PorchGlow"
	var glow := SphereMesh.new()
	glow.radius = 0.35
	glow.height = 0.7
	glow.radial_segments = 10
	glow.rings = 5
	_halo.mesh = glow
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.albedo_color = Color(LIGHT_COLOR, 0.35)
	_halo.material_override = glow_material
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position = PORCH_LIGHT_AT
	add_child(_halo)
	porch_light = OmniLight3D.new()
	porch_light.name = "PorchLight"
	porch_light.light_color = LIGHT_COLOR
	porch_light.light_energy = 2.2
	porch_light.omni_range = 7.0
	porch_light.shadow_enabled = false
	porch_light.position = PORCH_LIGHT_AT + Vector3(0.0, -0.1, -0.25)
	add_child(porch_light)


func _build_mailbox() -> void:
	var mailbox := Node3D.new()
	mailbox.name = "Mailbox"
	mailbox.position = Vector3(MAILBOX_X, 0.0, house_bounds.position.z - MAILBOX_AHEAD)
	add_child(mailbox)
	_box(mailbox, Vector3(0.1, 1.1, 0.1), Vector3(0.0, 0.55, 0.0), POST_COLOR)
	_box(mailbox, Vector3(0.42, 0.34, 0.6), Vector3(0.0, 1.27, 0.0), Color("c0392b"))
	# The number on both flanks: coming down the road, it's a flank that
	# faces the truck. Not on the end too -- seen from the front a flank and
	# the end together read "11".
	for face: Array in [[Vector3(0.22, 1.27, 0.0), -PI * 0.5], [Vector3(-0.22, 1.27, 0.0), PI * 0.5]]:
		var label := _label(mailbox, "0", face[0], face[1], 120, Color.WHITE, 0.004)
		label.outline_size = 18
		label.outline_modulate = INK
		number_labels.append(label)
	number_label = number_labels[0]
	number_label.name = "Number"


## A V of two boards with its tip toward the road, each board facing one
## way along it, so the truck reads one of them coming from either side.
func _build_sign() -> void:
	sign_board = Node3D.new()
	sign_board.name = "OrderSign"
	sign_board.position = _sign_tip()
	add_child(sign_board)
	for index: int in range(2):
		# Face 0 looks toward +X down the road, face 1 toward -X.
		var turn: float = deg_to_rad(BOARD_ANGLE_DEG) * (-1.0 if index == 0 else 1.0)
		var face := Node3D.new()
		face.name = "Face%d" % index
		face.rotation.y = turn
		# The board runs back from the tip, away from the side it faces.
		var along: float = BOARD_SIZE.x * 0.5 * (1.0 if index == 0 else -1.0)
		face.position = Basis(Vector3.UP, turn) * Vector3(along, 0.0, 0.0)
		sign_board.add_child(face)
		var post_height: float = BOARD_HEIGHT + BOARD_SIZE.y * 0.5
		for leg_x: float in [-BOARD_SIZE.x * 0.5 + 0.1, BOARD_SIZE.x * 0.5 - 0.1]:
			_box(face, Vector3(0.08, post_height, 0.08), Vector3(leg_x, post_height * 0.5, 0.05), POST_COLOR)
		var board := _box(face, Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.05), Vector3(0.0, BOARD_HEIGHT, 0.0), SIGN_COLOR)
		# Unshaded: it has to read at noon as much as at night.
		(board.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var code := _label(face, "ENTREGA", Vector3(0.0, BOARD_HEIGHT + 0.15, -0.035), 0.0, 150, INK, 0.007)
		code.name = "Code"
		code_labels.append(code)
		var trap := _label(face, "", Vector3(0.0, BOARD_HEIGHT - 0.42, -0.035), 0.0, 64, INK, 0.007)
		trap.name = "Trap"
		trap_labels.append(trap)
	code_label = code_labels[0]


## A yellow balloon on a tall pole at the sign's tip, over the roof line: at
## 120 m no sign can be read, but a spot of bright yellow against the sky,
## gently bobbing, says "here".
func _build_balloon() -> void:
	balloon = Node3D.new()
	balloon.name = "Balloon"
	balloon.position = _sign_tip() + Vector3(0.0, 0.0, -BALLOON_AHEAD)
	add_child(balloon)
	var height: float = maxf(house_bounds.end.y + BALLOON_OVER_ROOF, BALLOON_MIN_HEIGHT)
	# A string, not a post: thin, and no shadow slashed across the house.
	var string := _box(balloon, Vector3(0.025, height, 0.025), Vector3(0.0, height * 0.5, 0.0), Color("3a3a3a"))
	string.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BALLOON_RADIUS
	sphere.height = BALLOON_RADIUS * 2.3
	sphere.radial_segments = 12
	sphere.rings = 6
	ball.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = BALLOON_COLOR
	# Fog would wash it to the grey of the sky, the one thing it must not be.
	material.disable_fog = true
	ball.material_override = material
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.position = Vector3(0.0, height + BALLOON_RADIUS, 0.0)
	balloon.add_child(ball)
	_bob = create_tween().set_loops()
	_bob.tween_property(ball, "scale", Vector3.ONE * 1.1, BALLOON_BOB_SECONDS * 0.5).set_trans(Tween.TRANS_SINE)
	_bob.tween_property(ball, "scale", Vector3.ONE * 0.9, BALLOON_BOB_SECONDS * 0.5).set_trans(Tween.TRANS_SINE)


## The V's front tip: ahead of the house's front (porch, eaves), beside the path.
func _sign_tip() -> Vector3:
	return Vector3(SIGN_TIP_X, 0.0, house_bounds.position.z - SIGN_TIP_AHEAD)


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh


## Readable from its parent's -Z turned by `yaw` (Label3D reads from +Z).
func _label(parent: Node3D, text: String, at: Vector3, yaw: float, size: int, color: Color, pixel: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = FONT
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 0
	label.position = at
	label.rotation.y = PI + yaw
	label.double_sided = false
	parent.add_child(label)
	return label

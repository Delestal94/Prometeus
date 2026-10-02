extends RouteSegment
class_name ServiceStopSegment
## A straight stretch with an optional service station beside it (tareas de
## Nacho N-110): a lay-by (dársena) off the asphalt where the truck can pull
## in and brake, the station itself (ServiceStop: canopy, pumps, kiosk with the
## counter, price pole) and two signs that announce it well before -- the
## delivery route's RouteDresser and Endless both get it from here, since
## Endless has no dresser to put signs up.
##
## Laid by RoutePlanner (through ServiceStopRules.insert_into_plan()) on a
## long delivery and by RouteStreamer every so often in Endless, never as one
## of the random picks. The station stands on the driver's right.

const LENGTH: float = 110.0
## The station's spec, in this segment's space (entry at z = 0, exit at
## z = -LENGTH). The lay-by is LAY_BY_START..LAY_BY_END along the road and
## LAY_BY_NEAR..LAY_BY_FAR out from the centre line; the station stands behind it.
const LAY_BY_START: float = -52.0
const LAY_BY_END: float = -88.0
const LAY_BY_NEAR: float = 6.0
const LAY_BY_FAR: float = 12.4
const STATION_Z: float = -70.0
const SIGN_LATERAL: float = 7.8
## Where the two announcing signs stand: a long way before the lay-by, and at
## its start. A truck at cruise (12.8 m/s) has ~4 s from the first to the lay-by.
const SIGN_FAR_Z: float = -4.0
const SIGN_NEAR_Z: float = -40.0
## The ground beside the road in Endless, where the segment has to build its
## own (the delivery route's terrain replaces it).
const GROUND_TOP: float = -0.3
const STOP_SCRIPT: String = "res://scripts/gameplay/route/service_stop.gd"
const SIGN_FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const SIGN_ACCENT := Color("65b5a1")
const SIGN_BOARD := Color("263b3e")
const SIGN_SIZE := Vector2(4.4, 1.4)

## The station, once built (its counter and shop hang from it).
var stop: Node3D


func _init() -> void:
	length = LENGTH


func _build() -> void:
	_box("Ground", Vector3(48.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)
	for z: int in range(-2, -int(length), -6):
		for side: float in [-1.0, 1.0]:
			_box("EdgeMarking", Vector3(0.12, 0.015, 4.0), Vector3(side * 5.7, 0.03, float(z)), MARKING)
		_box("CenterMarking", Vector3(0.12, 0.012, 2.0), Vector3(0.0, 0.028, float(z)), Color("8c9994"))
	_build_lay_by()
	_sign("ServiceSignFar", tr("WORLD_SERVICE_SIGN_TITLE"), tr("WORLD_SERVICE_SIGN_FAR"), SIGN_FAR_Z)
	_sign("ServiceSignNear", tr("WORLD_SERVICE_SIGN_TITLE"), tr("WORLD_SERVICE_SIGN_NEAR"), SIGN_NEAR_Z)
	stop = (load(STOP_SCRIPT) as Script).new() as Node3D
	stop.name = "ServiceStop"
	# On the delivery route the terrain is the ground (each rigid part rides it
	# up from 0); in Endless it is this segment's own Ground box.
	stop.set(&"ground_y", 0.0 if continuous_terrain else GROUND_TOP)
	stop.position = Vector3(0.0, 0.0, STATION_Z)
	add_child(stop)


## The lay-by: an asphalt apron alongside the road (a hair above the terrain
## so the two never fight), a white line at its outer edge and a stop line at
## each end. Level with the road, so braking into it is just leaving the lane.
func _build_lay_by() -> void:
	var span: float = LAY_BY_START - LAY_BY_END
	var middle: float = (LAY_BY_START + LAY_BY_END) * 0.5
	var width: float = LAY_BY_FAR - LAY_BY_NEAR
	_box("LayBy", Vector3(width, 0.4, span), Vector3(LAY_BY_NEAR + width * 0.5, -0.18, middle), ROAD, true)
	_box("LayByEdge", Vector3(0.14, 0.015, span - 1.0), Vector3(LAY_BY_FAR - 0.25, 0.04, middle), MARKING)
	for z: float in [LAY_BY_START - 0.5, LAY_BY_END + 0.5]:
		_box("LayByLine", Vector3(width - 0.9, 0.015, 0.14), Vector3(LAY_BY_NEAR + width * 0.5, 0.04, z), MARKING)


## A route board on a post at the road's right, facing the traffic that
## comes toward -Z: title on top, message under it.
func _sign(node_name: String, title: String, message: String, z: float) -> void:
	var post_height: float = 3.3
	var board_y: float = post_height - SIGN_SIZE.y * 0.5 - 0.1
	_box(node_name + "Post", Vector3(0.16, post_height, 0.16),
			Vector3(SIGN_LATERAL, GROUND_TOP + post_height * 0.5, z - 0.15), CONCRETE, true)
	_box(node_name + "Board", Vector3(SIGN_SIZE.x, SIGN_SIZE.y, 0.12),
			Vector3(SIGN_LATERAL, GROUND_TOP + board_y, z), SIGN_BOARD)
	_box(node_name + "Stripe", Vector3(SIGN_SIZE.x, 0.1, 0.13),
			Vector3(SIGN_LATERAL, GROUND_TOP + board_y + SIGN_SIZE.y * 0.5 - 0.05, z), SIGN_ACCENT)
	_label(node_name + "Title", title, Vector3(SIGN_LATERAL, GROUND_TOP + board_y + 0.28, z + 0.075), 72, MARKING)
	_label(node_name + "Text", message, Vector3(SIGN_LATERAL, GROUND_TOP + board_y - 0.27, z + 0.075), 40,
			SIGN_ACCENT.lerp(MARKING, 0.35))


func _label(node_name: String, text: String, at: Vector3, font_size: int, colour: Color) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font = SIGN_FONT
	label.font_size = font_size
	label.pixel_size = 0.0055
	label.modulate = colour
	label.outline_size = 0
	label.position = at
	label.double_sided = false
	# A longer word in another language must not run off the board.
	var wide: float = SIGN_FONT.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x \
			* label.pixel_size
	if wide > SIGN_SIZE.x - 0.3:
		label.font_size = maxi(int(floor(font_size * (SIGN_SIZE.x - 0.3) / wide)), 8)
	add_child(label)

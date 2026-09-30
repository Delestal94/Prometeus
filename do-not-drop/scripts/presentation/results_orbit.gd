extends Camera3D
## Drives the results shot built by SpectatorCamera.orbit_results(): a slow
## circle around the truck, a little above it, looking at the cab.
##
## Parked in the base's free bay (N-116.4) it does not circle: the back wall
## and the neighbouring trucks are in the way. It sways to and fro over an arc
## in the lot, out in front of the bay, higher and further back, so the truck,
## the row of bays and the company's sign all fit.

const RADIUS: float = 9.0
const HEIGHT: float = 3.2
const TURN_SPEED: float = 0.18
const LOT_RADIUS: float = 13.0
const LOT_HEIGHT: float = 4.5
const LOT_LOOK_HEIGHT: float = 2.2
const LOT_ARC: float = 0.9
const LOT_SWAY_SPEED: float = 0.25

var target: Node3D
var radius: float = RADIUS
var height: float = HEIGHT
var look_height: float = 1.0
## Where the camera looks, beside the truck (world offset).
var look_shift: Vector3 = Vector3.ZERO
## Middle of the sway (radians, as the orbit's own angle) and how far it goes
## each way; 0 = the plain circle.
var arc_centre: float = 0.0
var arc_half: float = 0.0
var _angle: float = 0.6
var _clock: float = 0.0


## Frames the truck as parked in the base: `outward` is the direction (world,
## flat) from the truck toward where the camera should be, `focus` how far to
## look off to one side of the truck.
func frame_parked(outward: Vector3, focus: Vector3 = Vector3.ZERO) -> void:
	radius = LOT_RADIUS
	height = LOT_HEIGHT
	look_height = LOT_LOOK_HEIGHT
	look_shift = focus
	arc_centre = atan2(outward.z, outward.x)
	arc_half = LOT_ARC
	_angle = arc_centre


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if arc_half > 0.0:
		_clock += delta
		_angle = arc_centre + arc_half * sin(_clock * LOT_SWAY_SPEED)
	else:
		_angle += TURN_SPEED * delta
	var centre: Vector3 = target.get_global_transform_interpolated().origin
	global_position = centre + Vector3(cos(_angle) * radius, height, sin(_angle) * radius)
	look_at(centre + look_shift + Vector3.UP * look_height, Vector3.UP)

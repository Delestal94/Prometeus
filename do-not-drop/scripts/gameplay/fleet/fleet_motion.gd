extends RefCounted
## How a fleet vehicle moves, as the cargo and the crew need to know it (expansion D-0209).
##
## One per vehicle, made by the vehicle's own script with itself as `body`, like FleetCargo.
## The cargo reads the motion through this interface instead of through a VehicleBody3D, so a
## boat, a plane or a bike (hull, wings, pedals: no wheels) answers the same questions as the
## van. `body` is any Node3D; its velocity comes from a RigidBody3D, a CharacterBody3D
## (`velocity`) or, for anything else, a `linear_velocity` property.
## Preloaded, not by class_name: a new global class isn't in the class cache until the
## editor imports again, and headless runs load the van first.
##
## The interface is this object's methods, which the vehicle node exposes as its `fleet_motion`
## property (the van does, and so does a stand-in in a test, over its own FleetMotion; it adds no
## methods to the van):
## - speed_kmh(), forward(), right(), to_local(v) (a world direction in the vehicle's own space);
## - ground_contact() -> float: 0..1, 1 = resting on the ground (wheels on the road, hull in
##   the water, skids down); 0 = airborne;
## - cargo_acceleration() -> Vector3: what the boxes feel, in the vehicle's own space.
## The static `*_of()` readers below are what a consumer that holds the vehicle only by name
## calls (package_rescue.gd): they ask `fleet_motion` and, for a Node3D that doesn't have one
## (the plain fakes tests put in the "vehicle" group), fall back to its transform.
## Not here: how it drives, and who rides along (fleet_cargo.gd).

## How fast the smoothed acceleration follows the raw one (1/s): the same constant the care
## model has always used for a box (package_rescue.gd), so both feel alike.
const ACCELERATION_SMOOTHING: float = 8.0

## What answers ground_contact(); returns 0..1. Set by the owner (the van counts its wheels
## in contact). Unset: the vehicle is taken to rest on the ground.
var ground_probe: Callable

var _body: Node3D
var _rigid: RigidBody3D
var _character: CharacterBody3D
var _acceleration := Vector3.ZERO
var _last_velocity := Vector3.ZERO
var _sampled: bool = false


func _init(body: Node3D) -> void:
	_body = body
	_rigid = body as RigidBody3D
	_character = body as CharacterBody3D


## The world velocity of the body, in km/h.
func speed_kmh() -> float:
	return linear_velocity().length() * 3.6


## Where the body points, in the world (-Z).
func forward() -> Vector3:
	return -_body.global_basis.z


## The body's right, in the world (+X).
func right() -> Vector3:
	return _body.global_basis.x


## A world direction in the body's own space.
func to_local(direction: Vector3) -> Vector3:
	return _body.global_basis.inverse() * direction


## 1 = resting on the ground, 0 = airborne, in between = partly (some wheels).
func ground_contact() -> float:
	if not ground_probe.is_valid():
		return 1.0
	return clampf(float(ground_probe.call()), 0.0, 1.0)


## What the boxes feel: the body's acceleration in its own space (x right, z back), smoothed.
## Needs sample() once per physics tick.
func cargo_acceleration() -> Vector3:
	return _acceleration


## Once per physics tick, whoever drives the body: updates cargo_acceleration() from the
## change of the body's velocity since the last tick.
## A frozen body (a client's copy, a parked van) feels nothing and starts over when it moves again.
func sample(delta: float) -> void:
	if _rigid != null and _rigid.freeze:
		reset()
		return
	var velocity: Vector3 = linear_velocity()
	if _sampled:
		var raw: Vector3 = to_local((velocity - _last_velocity) / maxf(delta, 0.001))
		_acceleration = _acceleration.lerp(raw, minf(1.0, delta * ACCELERATION_SMOOTHING))
	_last_velocity = velocity
	_sampled = true


## Forget the last tick: after a teleport or a respawn the jump in velocity is not a push.
func reset() -> void:
	_acceleration = Vector3.ZERO
	_sampled = false


func linear_velocity() -> Vector3:
	if _rigid != null:
		return _rigid.linear_velocity
	if _character != null:
		return _character.velocity
	var value: Variant = _body.get(&"linear_velocity")
	return value if value is Vector3 else Vector3.ZERO


## Readers for a consumer that holds the vehicle by name (see the header). A null or freed
## vehicle reads as resting, facing -Z.
static func speed_kmh_of(vehicle: Node3D) -> float:
	var motion: Variant = _motion_of(vehicle)
	return motion.speed_kmh() if motion != null else 0.0


static func forward_of(vehicle: Node3D) -> Vector3:
	var motion: Variant = _motion_of(vehicle)
	return motion.forward() if motion != null else (-vehicle.global_basis.z if _alive(vehicle) else Vector3.FORWARD)


static func right_of(vehicle: Node3D) -> Vector3:
	var motion: Variant = _motion_of(vehicle)
	return motion.right() if motion != null else (vehicle.global_basis.x if _alive(vehicle) else Vector3.RIGHT)


static func local_direction(vehicle: Node3D, direction: Vector3) -> Vector3:
	var motion: Variant = _motion_of(vehicle)
	if motion != null:
		return motion.to_local(direction)
	return vehicle.global_basis.inverse() * direction if _alive(vehicle) else direction


static func ground_contact_of(vehicle: Node3D) -> float:
	var motion: Variant = _motion_of(vehicle)
	return motion.ground_contact() if motion != null else 1.0


static func cargo_acceleration_of(vehicle: Node3D) -> Vector3:
	var motion: Variant = _motion_of(vehicle)
	return motion.cargo_acceleration() if motion != null else Vector3.ZERO


## The vehicle's `fleet_motion`, null when it has none.
static func _motion_of(vehicle: Node3D) -> Variant:
	if not _alive(vehicle):
		return null
	var motion: Variant = vehicle.get(&"fleet_motion")
	if motion is RefCounted and (motion as RefCounted).has_method(&"cargo_acceleration"):
		return motion
	return null


static func _alive(vehicle: Node3D) -> bool:
	return vehicle != null and is_instance_valid(vehicle)

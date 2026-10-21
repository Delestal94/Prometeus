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
## The interface, as the vehicle node offers it (vehicle.gd keeps thin wrappers; a stand-in
## in a test offers the same names over its own FleetMotion):
## - `speed_kmh` (a property, the van's own): how fast it goes;
## - `motion_forward()` / `motion_right()`: its heading and its right, in the world;
## - `motion_to_local(v)`: a world direction in the vehicle's own space;
## - `ground_contact() -> float`: 0..1, 1 = resting on the ground (wheels on the road, hull in
##   the water, skids down); 0 = airborne;
## - `cargo_acceleration() -> Vector3`: what the boxes feel, in the vehicle's own space.
## The static `*_of()` readers below are what a consumer that holds the vehicle only by name
## calls (package_rescue.gd): they ask the interface and, for a Node3D that doesn't offer it
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
	return (-_body.global_basis.z).normalized()


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
func sample(delta: float) -> void:
	var velocity: Vector3 = linear_velocity()
	if _sampled:
		var raw: Vector3 = to_local((velocity - _last_velocity) / maxf(delta, 0.001))
		_acceleration = _acceleration.lerp(raw, minf(1.0, delta * ACCELERATION_SMOOTHING))
	_last_velocity = velocity
	_sampled = true


func linear_velocity() -> Vector3:
	if _rigid != null:
		return _rigid.linear_velocity
	if _character != null:
		return _character.velocity
	var value: Variant = _body.get(&"linear_velocity")
	return value if value is Vector3 else Vector3.ZERO


## Readers for a consumer that holds the vehicle by name (see the header).
static func speed_kmh_of(vehicle: Node3D) -> float:
	var value: Variant = vehicle.get(&"speed_kmh")
	return float(value) if value is float else 0.0


static func forward_of(vehicle: Node3D) -> Vector3:
	if vehicle.has_method(&"motion_forward"):
		return vehicle.call(&"motion_forward")
	return -vehicle.global_basis.z


static func right_of(vehicle: Node3D) -> Vector3:
	if vehicle.has_method(&"motion_right"):
		return vehicle.call(&"motion_right")
	return vehicle.global_basis.x


static func local_direction(vehicle: Node3D, direction: Vector3) -> Vector3:
	if vehicle.has_method(&"motion_to_local"):
		return vehicle.call(&"motion_to_local", direction)
	return vehicle.global_basis.inverse() * direction


static func ground_contact_of(vehicle: Node3D) -> float:
	if vehicle.has_method(&"ground_contact"):
		return float(vehicle.call(&"ground_contact"))
	return 1.0


static func cargo_acceleration_of(vehicle: Node3D) -> Vector3:
	if vehicle.has_method(&"cargo_acceleration"):
		return vehicle.call(&"cargo_acceleration")
	return Vector3.ZERO

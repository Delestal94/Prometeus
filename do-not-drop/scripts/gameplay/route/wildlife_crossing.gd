extends Node3D
class_name WildlifeCrossing
## A deer crossing on a straight stretch. A yellow warning sign stands well
## before it (placed by RouteDresser on the handcrafted route, or by this
## node itself in endless mode); the deer grazes on the shoulder, visible
## from far off. When the truck gets close it bolts across the road, stops
## dead in the middle staring at the headlights, then clears the other side.
##
## Hitting it is the crew's fault, not the deer's: it tumbles away unhurt
## (cartoon, it gets up and runs into the trees), the truck lurches as if it
## hit a wall -- which the cargo feels through the normal vehicle_impact
## path -- and the team pays a fine for the damage.
##
## Multiplayer: every peer runs the same timeline off the same replicated
## truck position, so the deer moves the same everywhere without any extra
## syncing. Only the host decides a hit's consequences (the truck is host
## physics, money is host state); clients just play the tumble when they
## see the same overlap.

const DEER_MODEL: PackedScene = preload("res://assets/models/environment/wildlife/sm_env_animal_stag_rigged.glb")
const SIGN_MODEL: PackedScene = preload("res://assets/models/environment/signs/sm_env_sign_animal_crossing.glb")
const ANIMAL_SCRIPT: Script = preload("res://scripts/presentation/wildlife_animal.gd")

enum State { WAITING, RUNNING_IN, FROZEN, BOLTING, TUMBLING, FLEEING, DONE }

## The truck this far (metres, along the road) before the crossing sets the
## deer off. At full speed that leaves room to brake if the driver reacts
## to the sign or the deer on the shoulder; at full speed without braking,
## the truck arrives while the deer is frozen in the lane.
const TRIGGER_DISTANCE: float = 38.0
const WAIT_LATERAL: float = 8.6
const FREEZE_LATERAL: float = 1.1
const EXIT_LATERAL: float = 13.0
const GONE_LATERAL: float = 28.0
const RUN_SPEED: float = 7.5
const BOLT_SPEED: float = 9.5
const FREEZE_SECONDS: float = 0.7
## The road is 12 m wide; only a deer between the edge lines can be hit.
const ROAD_HALF_WIDTH: float = 6.2
## Truck body in its own space (vehicle.tscn collision), with a small margin.
const TRUCK_HALF_WIDTH: float = 1.3
const TRUCK_FRONT_Z: float = -2.95
const TRUCK_BACK_Z: float = 4.6
const MIN_HIT_SPEED_KMH: float = 6.0
## Speed the truck loses on impact, m/s. Above vehicle.gd's 3 m/s impact
## threshold, so the hit reaches the cargo through vehicle_impact.
const IMPACT_SPEED_LOSS: float = 3.6
const FINE: int = 30
## How long a hit's banner stays up before it's closed (report_incident()).
const INCIDENT_SECONDS: float = 4.0
const SIGN_LEAD: float = 45.0
const SIGN_LATERAL: float = 7.8

## Which shoulder the deer waits on: -1 left, +1 right (driver's view).
@export var side: float = 1.0
## Endless mode has no RouteDresser, so the crossing puts up its own sign.
@export var with_sign: bool = false

var state: State = State.WAITING
var deer: Node3D
var hit: bool = false
var _lateral: float = 0.0
var _timer: float = 0.0
var _tumble_velocity: Vector3 = Vector3.ZERO
var _tumble_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	deer = DEER_MODEL.instantiate() as Node3D
	deer.name = "Deer"
	deer.set_script(ANIMAL_SCRIPT)
	add_child(deer)
	deer.set(&"steered", true)
	_lateral = side * WAIT_LATERAL
	_place_deer(-side)
	if with_sign:
		var warning := SIGN_MODEL.instantiate() as Node3D
		warning.name = "CrossingSign"
		warning.rotation.y = PI  # Authored facing -Z; turned to face the driver.
		warning.position = Vector3(SIGN_LATERAL, 0.0, SIGN_LEAD)
		add_child(warning)
		warning.position.y = _ground_height(warning.position)


func _physics_process(delta: float) -> void:
	if state == State.DONE:
		return
	var vehicle := get_tree().get_first_node_in_group(&"vehicle") as VehicleBody3D
	match state:
		State.WAITING:
			if vehicle != null and _approaching(vehicle):
				state = State.RUNNING_IN
				deer.call(&"run")
		State.RUNNING_IN:
			_lateral = move_toward(_lateral, side * FREEZE_LATERAL, RUN_SPEED * delta)
			_place_deer(-side)
			if is_equal_approx(_lateral, side * FREEZE_LATERAL):
				state = State.FROZEN
				_timer = FREEZE_SECONDS
				deer.call(&"freeze_in_headlights")
		State.FROZEN:
			_timer -= delta
			_place_deer(-side, true)
			if _timer <= 0.0:
				state = State.BOLTING
				deer.call(&"run")
		State.BOLTING:
			_lateral = move_toward(_lateral, -side * EXIT_LATERAL, BOLT_SPEED * delta)
			_place_deer(-side)
			if is_equal_approx(_lateral, -side * EXIT_LATERAL):
				_start_fleeing()
		State.TUMBLING:
			_timer -= delta
			_tumble_velocity.y -= 18.0 * delta
			_tumble_offset += _tumble_velocity * delta
			var ground: float = _ground_height(to_local(deer.global_position))
			deer.position = Vector3(_lateral, 0.0, 0.0) + _tumble_offset
			deer.position.y = maxf(deer.position.y, ground)
			if _timer <= 0.0:
				_lateral = deer.position.x
				deer.position.z = 0.0
				deer.rotation = Vector3.ZERO
				_start_fleeing()
		State.FLEEING:
			var away: float = signf(_lateral) if absf(_lateral) > 0.5 else -side
			_lateral = move_toward(_lateral, away * GONE_LATERAL, BOLT_SPEED * delta)
			_place_deer(away)
			if is_equal_approx(absf(_lateral), GONE_LATERAL):
				state = State.DONE
				deer.visible = false
	if vehicle != null and state in [State.RUNNING_IN, State.FROZEN, State.BOLTING] and absf(_lateral) < ROAD_HALF_WIDTH:
		_check_hit(vehicle)


## The truck is on this stretch, coming toward the crossing (it drives
## toward -Z), within trigger range.
func _approaching(vehicle: Node3D) -> bool:
	var local: Vector3 = to_local(vehicle.global_position)
	return local.z > 4.0 and local.z < TRIGGER_DISTANCE and absf(local.x) < 14.0


func _check_hit(vehicle: VehicleBody3D) -> void:
	if vehicle.linear_velocity.length() * 3.6 < MIN_HIT_SPEED_KMH:
		return
	var in_truck: Vector3 = vehicle.to_local(deer.global_position + Vector3.UP * 0.9)
	if absf(in_truck.x) > TRUCK_HALF_WIDTH or in_truck.z < TRUCK_FRONT_Z or in_truck.z > TRUCK_BACK_Z or in_truck.y < -1.2 or in_truck.y > 3.0:
		return
	hit = true
	state = State.TUMBLING
	_timer = 1.1
	# Knocked ahead of the truck and off to the side it was heading for.
	var push: Vector3 = to_local(deer.global_position + vehicle.linear_velocity) - to_local(deer.global_position)
	_tumble_velocity = Vector3(push.x * 0.4 - side * 3.0, 4.5, push.z * 0.35)
	_tumble_offset = Vector3.ZERO
	deer.call(&"tumble")
	if vehicle.is_multiplayer_authority():
		_apply_consequences(vehicle)


func _apply_consequences(vehicle: VehicleBody3D) -> void:
	var velocity: Vector3 = vehicle.linear_velocity
	if velocity.length() > 0.1:
		vehicle.apply_central_impulse(-velocity.normalized() * vehicle.mass * minf(IMPACT_SPEED_LOSS, velocity.length() * 0.5))
	var fine: int = FINE
	var crew: Node = get_node_or_null(^"/root/CrewProgression")
	if crew != null:
		fine = mini(FINE, int(crew.get(&"team_money")))
		if fine > 0:
			crew.call(&"spend", fine)
	report_incident(get_tree(), &"deer_hit", "¡Chocaste un ciervo!",
		("Salió corriendo, pero la multa por daños es de $%d." % fine) if fine > 0 else "Salió corriendo. Suerte que no había plata para la multa.")


## Host only. Tells every HUD about something that already happened on the
## road (a hit, a fine) through the route-event channel, and closes it again
## after INCIDENT_SECONDS: an incident has nothing to respond to, so it must
## not hang in a banner that waits for a resolution. `duration` 0 says there
## is no countdown. The other roadside hazards use the same shape.
static func report_incident(tree: SceneTree, event_id: StringName, title: String, prompt: String) -> void:
	var bus: Node = tree.root.get_node_or_null(^"/root/EventBus")
	if bus == null:
		return
	bus.call(&"relay", &"route_event_started", [event_id, {
		"title": title,
		"prompt": prompt,
		"incident": true,
		"duration": 0,
	}])
	# Bound to the bus, not to the crossing: it must close even if the
	# stretch has streamed out of the world by then.
	tree.create_timer(INCIDENT_SECONDS).timeout.connect(
		Callable(bus, &"relay").bind(&"route_event_resolved", [event_id, false, 0]))


func _start_fleeing() -> void:
	state = State.FLEEING
	deer.call(&"run")


## Stands the deer at `_lateral` across the road, on the ground there,
## facing `facing` (-1 toward the left shoulder, +1 toward the right).
func _place_deer(facing: float, look_at_truck: bool = false) -> void:
	var spot := Vector3(_lateral, 0.0, 0.0)
	spot.y = _ground_height(spot)
	deer.position = spot
	# Front is -Z: a quarter turn points it across the road; half a turn
	# faces the oncoming truck (it drives toward -Z), headlights-stare.
	deer.rotation = Vector3(0.0, PI if look_at_truck else facing * -PI * 0.5, 0.0)


func _ground_height(local_point: Vector3) -> float:
	var world_point: Vector3 = to_global(local_point)
	var query := PhysicsRayQueryParameters3D.create(world_point + Vector3.UP * 6.0, world_point + Vector3.DOWN * 12.0, 1)
	var hit_info: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit_info.is_empty():
		return local_point.y
	return to_local(hit_info["position"] as Vector3).y

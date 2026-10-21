extends VehicleBody3D
## A deliberately forgiving first delivery van, with physical, loose cargo.
## Visual front is local -Z; VehicleBody3D's native engine direction is +Z.
##
## Host-authoritative: this node's multiplayer authority is the host (the
## Godot default for a static, non-spawned node, never reassigned). On every
## other peer it's a synced puppet -- frozen so the physics engine doesn't
## fight the transform MultiplayerSynchronizer is about to hand it, driven
## only by whatever the host broadcasts. The exception is the client at the
## wheel (N-218, vehicle_prediction.gd): it simulates its copy with its own
## input and eases it toward what the host says.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
## Preloaded, not by class_name: a new global class isn't in the class cache until
## the editor imports again, and headless runs load this script first.
const FleetCargo = preload("res://scripts/gameplay/fleet/fleet_cargo.gd")
const FleetSeats = preload("res://scripts/gameplay/fleet/fleet_seats.gd")
const FleetMotion = preload("res://scripts/gameplay/fleet/fleet_motion.gd")

## Which peer currently holds the wheel, synced to everyone so each client's
## VehicleInputComponent knows whether it's the one that should be reading
## input at all. 0 means nobody's driving.
@export var driver_peer_id: int = 0:
	set(value):
		var changed: bool = value != driver_peer_id
		driver_peer_id = value
		if changed and _prediction != null:
			_prediction.driver_changed(self)
		# The driver got in through the open door: it shuts behind them. When
		# they get out it opens to let them climb down. Host decides, and the
		# door state replicates like any other door toggle.
		if changed and is_node_ready() and is_multiplayer_authority():
			set_door_open(&"cab_left", value == 0)
## Replicated along with driver_peer_id (see vehicle.tscn): the driver's own
## VehicleInputComponent reads it on their machine. It used to live only on
## the host, so a client at the wheel kept the scene's `false` and never sent
## a single throttle sample -- the truck just crept on its brakes.
@export var controls_enabled: bool = true
## The pose the host sends (tareas de Nacho N-208), replicated instead of
## position/rotation (vehicle.tscn): on the host they read the truck itself,
## plus its own clock; on a client each packet goes into NetPoseSmoother,
## which draws the truck a touch in the past, interpolated, instead of
## jumping with every burst of packets.
var net_time: float:
	get:
		return _host_clock
	set(value):
		_net_incoming_time = value
		_net_received |= 1
		_commit_net_pose()
var net_position: Vector3:
	get:
		return position
	set(value):
		_net_incoming_position = value
		_net_received |= 2
		_commit_net_pose()
var net_rotation: Vector3:
	get:
		return rotation
	set(value):
		_net_incoming_rotation = value
		_net_received |= 4
		_commit_net_pose()
## The input the host's pose stands for (N-218): which of the driving
## client's numbered inputs its last step used. The client at the wheel
## compares the pose with its own after that input (vehicle_prediction.gd).
var net_input_seq: int:
	get:
		return _prediction.applied_seq
	set(value):
		_net_incoming_seq = value
		_net_received |= 8
		_commit_net_pose()
## The velocities, the steering and the engine force are replicated through
## these instead of the body's own properties (N-218): a client drawing the
## host's truck takes them as they come, as before; the client at the wheel
## predicts its own and keeps the host's velocities only to compare.
var net_linear_velocity: Vector3:
	get:
		return linear_velocity
	set(value):
		_net_incoming_velocity = value
		if not _prediction.active:
			linear_velocity = value
		_net_received |= 16
		_commit_net_pose()
var net_angular_velocity: Vector3:
	get:
		return angular_velocity
	set(value):
		_net_incoming_spin = value
		if not _prediction.active:
			angular_velocity = value
		_net_received |= 32
		_commit_net_pose()
var net_steering: float:
	get:
		return steering
	set(value):
		if not _prediction.active:
			steering = value
var net_engine_force: float:
	get:
		return engine_force
	set(value):
		if not _prediction.active:
			engine_force = value
## Host: whether its truck is simulated (not frozen for loading, parking or a
## run's end), replicated on change: the client at the wheel predicts only
## while it is.
@export var net_simulating: bool = false
## Every part of a pose packet: time, position, rotation, input, velocities.
const NET_POSE_PARTS: int = 63
var _host_clock: float = 0.0
var _net_smoother := NetPoseSmoother.new()
var _net_incoming_time: float = 0.0
var _net_incoming_position: Vector3 = Vector3.ZERO
var _net_incoming_rotation: Vector3 = Vector3.ZERO
var _net_incoming_seq: int = 0
var _net_incoming_velocity: Vector3 = Vector3.ZERO
var _net_incoming_spin: Vector3 = Vector3.ZERO
var _net_received: int = 0
var _prediction := VehiclePrediction.new()
@export var maximum_engine_force: float = 1700.0
@export var maximum_speed_kmh: float = 72.0
@export var reverse_speed_kmh: float = 18.0
@export var braking_force: float = 55.0
@export var maximum_steering: float = 0.42
@export var steering_response: float = 2.0
## Door states are host-owned and replicated like the driver state, so every
## peer animates the same doors and walks into the same collision. The rear
## pair starts open so the crew can load; the cab doors start shut.
@export var rear_cargo_open: bool = true:
	set(value):
		rear_cargo_open = value
		_apply_door(&"rear", value)
@export var cab_left_door_open: bool = false:
	set(value):
		cab_left_door_open = value
		_apply_door(&"cab_left", value)
@export var cab_right_door_open: bool = false:
	set(value):
		cab_right_door_open = value
		_apply_door(&"cab_right", value)
## The loading ramp is out only while the rear doors are open and the truck is
## parked -- never while driving, where it would scrape the road.
@export var rear_ramp_deployed: bool = true:
	set(value):
		rear_ramp_deployed = value
		var ramp_shape := get_node_or_null(^"RearRamp/Shape") as CollisionShape3D
		if ramp_shape != null:
			ramp_shape.set_deferred(&"disabled", not value)
		var reference_truck := get_node_or_null(^"ReferenceTruck")
		if reference_truck != null:
			reference_truck.call(&"set_ramp_deployed", value)
## Which truck and paint the crew is driving (docs/tareas-nacho.md #85-#89),
## chosen by the host from its unlocks (UnlockManager) and replicated, so
## every peer drives and draws the same one. The variant is a tuning of this
## same model -- no second set of art -- and the paint recolours its body.
const VARIANTS: Dictionary = {
	&"classic": {"maximum_speed_kmh": 72.0, "maximum_engine_force": 1700.0, "maximum_steering": 0.42, "steering_response": 2.0, "mass": 950.0, "trim": Color("6186b5")},
	# Lighter and quicker, with twitchier steering: fast, and a lot less
	# forgiving with fragile cargo.
	&"agile": {"maximum_speed_kmh": 84.0, "maximum_engine_force": 1850.0, "maximum_steering": 0.5, "steering_response": 2.9, "mass": 800.0, "trim": Color("f08a24")},
	# The old classic (N-114): a bit slower and heavier, with a manual gearbox
	# (vehicle_gearbox.gd) the driver works by hand. The compensation is pay:
	# the crew's delivery payout is multiplied by "pay_multiplier".
	&"vintage": {
		"maximum_speed_kmh": 68.0, "maximum_engine_force": 1700.0, "maximum_steering": 0.42,
		"steering_response": 2.0, "mass": 1000.0, "trim": Color("8a5a24"), "factory_body": Color("e6cf98"),
		"retro": true, "manual": true, "pay_multiplier": VehicleGearbox.PAY_MULTIPLIER,
	},
}
const PAINTS: Dictionary = {
	&"white": Color("dde2e8"),
	&"violet": Color("7b52b9"),
}
@export var variant_id: StringName = &"classic":
	set(value):
		variant_id = value if VARIANTS.has(value) else &"classic"
		_apply_variant()
@export var paint_id: StringName = &"white":
	set(value):
		paint_id = value if PAINTS.has(value) else &"white"
		_apply_paint()

## Replicated facts for presentation on frozen client copies.
var presentation_engine_running: bool = false
var presentation_braking: bool = false

var speed_kmh: float:
	get:
		return linear_velocity.length() * 3.6

var _throttle: float = 0.0
var _steering_input: float = 0.0
var _handbrake: bool = false
var _previous_velocity: Vector3 = Vector3.ZERO
var _impact_cooldown: float = 0.0
var _telemetry_time: float = 0.0
var _settling_time: float = 1.0
var _grounded_once: bool = false
## Nobody at the wheel and stopped: the truck is held still (see
## _update_parking) instead of creeping downhill on its brakes.
var _parked: bool = false
const PARK_SPEED_KMH: float = 3.0
## Right after a stop the body still rocks on its springs; frozen then, it
## kept the nose dipped and the ramp hanging off the road for good. It parks
## once it has stopped pitching and rolling for PARK_SETTLE_SECONDS, or after
## PARK_MAX_WAIT_SECONDS whatever happens, so it never creeps off for long.
const PARK_SETTLED_ANGULAR_SPEED: float = 0.03
const PARK_SETTLE_SECONDS: float = 0.5
const PARK_MAX_WAIT_SECONDS: float = 3.0
var _park_settled_time: float = 0.0
var _park_wait_time: float = 0.0
## Suspension attach points as authored; see _pose_frozen_wheels().
var _wheel_mounts: Dictionary = {}
## Each wheel's height in the truck's space (front left, front right, rear
## left, rear right), replicated instead of the four wheel transforms
## (N-228.5: 20 bytes a send, not 208). A client draws its wheels from it,
## `steering` and the speed (_pose_remote_wheels).
var net_wheel_heights: Vector4:
	get:
		var heights := Vector4.ZERO
		for index: int in mini(_wheels.size(), 4):
			heights[index] = _wheels[index].position.y
		return heights
	set(value):
		_net_wheel_heights = value
var _wheels: Array[VehicleWheel3D] = []
var _net_wheel_heights := Vector4.ONE * (TIRE_RADIUS - RIDE_HEIGHT)
var _wheel_spin := PackedFloat32Array()
## A wheel's own axes as VehicleBody3D sets them (vehicle_body_3d.cpp
## _update_wheel): the axle, up, and up x axle -- a mirrored basis.
const WHEEL_AXES: Basis = Basis(Vector3.RIGHT, Vector3.UP, Vector3.FORWARD)

## Ramp hysteresis, in km/h: out below the first, stowed above the second.
const RAMP_DEPLOY_SPEED: float = 2.0
const RAMP_STOW_SPEED: float = 4.0
## Height of the body origin above flat ground once the suspension has
## settled under its own weight (measured, see tests/test_reference_truck.gd).
const RIDE_HEIGHT: float = 0.666
## Radius of the authored tire. The physics wheels in vehicle.tscn are a few
## centimetres larger per axle: VehicleBody3D rests each wheel centre that
## much below its ray contact under load, and the extra radius cancels it so
## the drawn rubber sits exactly on the road.
const TIRE_RADIUS: float = 0.544
## The cargo constants live in FleetCargo (D-0208); kept here under their names,
## which the rest of the game reads (Vehicle.CARGO_BAY, van.SHELL_LAYER ...).
const MOUNT_REFERENCE_HALF_HEIGHT: float = FleetCargo.MOUNT_REFERENCE_HALF_HEIGHT
const CARGO_BAY: AABB = FleetCargo.CARGO_BAY
const CARGO_WALL_INNER_X: float = FleetCargo.CARGO_WALL_INNER_X
const CARGO_WALL_CLEARANCE: float = FleetCargo.CARGO_WALL_CLEARANCE
const SHELL_LAYER: int = FleetCargo.SHELL_LAYER
## What this van does for its cargo (carries, the shell, shelving) and who sits where:
## shared with the other vehicles of the fleet, see scripts/gameplay/fleet/.
var fleet_cargo: FleetCargo
var fleet_seats: FleetSeats
## How this van moves, as the cargo reads it (D-0209): heading, ground contact, what the boxes feel.
var fleet_motion: FleetMotion

## The manual gearbox (N-114): always in the scene, only used by a manual variant.
@onready var gearbox: VehicleGearbox = $Gearbox
var _horn_player: AudioStreamPlayer3D


func _init() -> void:
	fleet_cargo = FleetCargo.new(self)
	fleet_seats = FleetSeats.new(self)
	fleet_motion = FleetMotion.new(self)
	fleet_motion.ground_probe = _wheels_on_ground


func _ready() -> void:
	fleet_cargo.spawn_point = $CargoBay/LeftSeat1PackageMount
	if not is_multiplayer_authority():
		# A remote peer's copy: kinematic from here on, positioned entirely by
		# the MultiplayerSynchronizer. Letting the physics engine run too would
		# fight the incoming synced transform every frame.
		freeze = true
		# The pose buffer and the prediction simulate a bad link only where
		# the transport doesn't (LAN under --net-sim); over Steam the sockets do it.
		configure_net_sim(NetworkManager.pose_net_sim())
		gearbox.gear_changed.connect(_on_remote_gear_changed)
	# Runs on every peer's copy of the van -- horn_honked is already relayed
	# to everyone (see EventBus.request_horn()), so whoever's driving doesn't
	# need to be this peer, or the host, for it to be heard here too.
	_horn_player = AudioStreamPlayer3D.new()
	# Named so vehicle_presentation.gd routes it Interior/Exterior with the
	# engine and the rest of the truck's sounds; SFX only until it does.
	_horn_player.name = "HornAudio"
	_horn_player.bus = &"SFX"
	_horn_player.stream = SynthAudio.honk_horn()
	_horn_player.unit_size = 15.0
	# Measured, like the rest of the world's sounds (world_mix.gd).
	_horn_player.volume_db = WorldMix.HORN_DB
	add_child(_horn_player)
	EventBus.horn_honked.connect(_on_horn_honked)
	for wheel: Node in get_children():
		if wheel is VehicleWheel3D:
			_wheel_mounts[wheel] = (wheel as VehicleWheel3D).position
			_wheels.append(wheel as VehicleWheel3D)
	_wheel_spin.resize(_wheels.size())
	var reference_truck := preload("res://scripts/presentation/reference_truck.gd").new()
	reference_truck.name = "ReferenceTruck"
	add_child(reference_truck)
	# After the reference truck: it adds the bulkhead's collision.
	fleet_cargo.build_shell()
	# Setters ran before the scene was ready (defaults, spawn sync); apply the
	# current state to collision and art once everything exists.
	for door: StringName in [&"rear", &"cab_left", &"cab_right"]:
		_apply_door(door, is_door_open(door))
	rear_ramp_deployed = rear_ramp_deployed
	_apply_variant()
	if is_multiplayer_authority():
		EventBus.package_placed.connect(_on_package_placed)


## Whether a world point is inside the cargo bay, i.e. riding along (FleetCargo.carries).
func carries(world_point: Vector3, margin: float = 0.0) -> bool:
	return fleet_cargo.carries(world_point, margin)


## How fast a point riding in the truck is moving in the world (FleetCargo.point_velocity).
func point_velocity(world_point: Vector3) -> Vector3:
	return fleet_cargo.point_velocity(world_point)


## Whether a rigid body in or around the truck should use continuous collision
## this tick (FleetCargo.needs_sweep).
func needs_sweep(body: RigidBody3D, margin: float = 0.0) -> bool:
	return fleet_cargo.needs_sweep(body, margin)


## What fraction of the wheels is on the road: FleetMotion.ground_contact() for this van. A frozen
## copy (a client's, or parked) is taken to rest on it.
func _wheels_on_ground() -> float:
	if freeze or _wheels.is_empty():
		return 1.0
	var touching: int = 0
	for wheel: VehicleWheel3D in _wheels:
		touching += 1 if wheel.is_in_contact() else 0
	return float(touching) / _wheels.size()


func is_door_open(door: StringName) -> bool:
	match door:
		&"rear":
			return rear_cargo_open
		&"cab_left":
			return cab_left_door_open
		&"cab_right":
			return cab_right_door_open
	return false


## Host only: vehicle_door_interaction.gd calls this from interact(), which always
## runs on the host; the synchronizer carries the result to everyone else.
func set_door_open(door: StringName, open: bool) -> void:
	if not is_multiplayer_authority():
		return
	match door:
		&"rear":
			rear_cargo_open = open
		&"cab_left":
			cab_left_door_open = open
		&"cab_right":
			cab_right_door_open = open


func set_rear_cargo_open(open: bool) -> void:
	set_door_open(&"rear", open)


func _apply_door(door: StringName, open: bool) -> void:
	if door == &"rear":
		for owner_body: Node in [self, fleet_cargo.shell]:
			var blocker := owner_body.get_node_or_null(^"RearDoorCollision") as CollisionShape3D if owner_body != null else null
			if blocker != null:
				blocker.set_deferred(&"disabled", open)
	var reference_truck := get_node_or_null(^"ReferenceTruck")
	if reference_truck != null:
		reference_truck.call(&"set_door_open", door, open)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and fleet_cargo != null:
		fleet_cargo.on_body_transform_changed()


## A box set on the rack rests on its deck whatever its shape (FleetCargo.on_package_placed).
func _on_package_placed(package_id: StringName) -> void:
	fleet_cargo.on_package_placed(package_id)


## A heavy truck left with nobody at the wheel doesn't roll: VehicleBody3D's
## brake never quite holds, so it crept off a few centimetres a second (more
## on a slope), out from under the crew and away from the door they'd just
## climbed out of. Once it's slow and driverless it is frozen in place, and
## let go the moment somebody takes the wheel. Only during a delivery --
## before and after one, the level freezes and releases the truck itself.
func _update_parking(delta: float) -> void:
	if not RunManager.is_running:
		_parked = false
		_park_settled_time = 0.0
		_park_wait_time = 0.0
		return
	# A truck somebody is hauling out of the mud (MudSegment, N-108) sets this meta
	# so it is not frozen under the crane's cable or the crew's shoves.
	var commanded: bool = driver_peer_id != 0 or absf(_throttle) > 0.01 or bool(get_meta(&"keep_awake", false))
	if _parked:
		if commanded:
			_parked = false
			freeze = false
			sleeping = false
		return
	if commanded or freeze or speed_kmh >= PARK_SPEED_KMH:
		_park_settled_time = 0.0
		_park_wait_time = 0.0
		return
	_park_wait_time += delta
	if angular_velocity.length() < PARK_SETTLED_ANGULAR_SPEED:
		_park_settled_time += delta
	else:
		_park_settled_time = 0.0
	if _park_settled_time >= PARK_SETTLE_SECONDS or _park_wait_time >= PARK_MAX_WAIT_SECONDS:
		_parked = true
		_park_settled_time = 0.0
		_park_wait_time = 0.0
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = true


## Host only, first physics tick: sit the truck on whatever ground is under
## its spawn point, so it never hovers while frozen for loading or drops with
## a thud when the delivery starts.
func _snap_to_ground() -> void:
	_grounded_once = true
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 2.0, global_position + Vector3.DOWN * 4.0, 1)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position.y = (hit[&"position"] as Vector3).y + RIDE_HEIGHT


## While frozen the physics server never updates the wheels, so they would
## hang at their suspension attach points (tucked up into the arches). Put
## them where the settled suspension holds them instead; the moment the
## truck unfreezes VehicleBody3D takes the wheel transforms back over.
## Physics interpolation (project.godot) draws the moving truck smoothly
## between ticks, but a FROZEN truck's wheels got drawn stacked at its centre
## (a VehicleWheel3D + interpolation engine quirk -- why the setting was once
## dropped). A frozen truck is parked, or a remote peer's copy positioned by
## the network, so it gains nothing from interpolation: it's switched off
## for the whole truck while frozen and back on, reset, once it's released.
func _match_interpolation_to_freeze() -> void:
	var wanted: Node.PhysicsInterpolationMode = PHYSICS_INTERPOLATION_MODE_OFF if freeze else PHYSICS_INTERPOLATION_MODE_INHERIT
	if physics_interpolation_mode != wanted:
		physics_interpolation_mode = wanted
		reset_physics_interpolation()


func _pose_frozen_wheels() -> void:
	for wheel: VehicleWheel3D in _wheel_mounts:
		var mount: Vector3 = _wheel_mounts[wheel]
		wheel.position = Vector3(mount.x, TIRE_RADIUS - RIDE_HEIGHT, mount.z)
		wheel.rotation = Vector3.ZERO


func _apply_variant() -> void:
	var tuning: Dictionary = VARIANTS[variant_id]
	maximum_speed_kmh = tuning["maximum_speed_kmh"]
	maximum_engine_force = tuning["maximum_engine_force"]
	maximum_steering = tuning["maximum_steering"]
	steering_response = tuning["steering_response"]
	mass = tuning["mass"]
	if is_node_ready():
		gearbox.enabled = bool(tuning.get("manual", false))
		if not gearbox.enabled:
			gearbox.reset()
	_apply_paint()


func _apply_paint() -> void:
	var reference_truck := get_node_or_null(^"ReferenceTruck")
	if reference_truck != null:
		var tuning: Dictionary = VARIANTS[variant_id]
		var body: Color = PAINTS[paint_id]
		# A variant with its own factory colour (the old van's cream) wears it
		# while the crew hasn't picked another paint; a chosen paint still wins.
		if paint_id == &"white" and tuning.has("factory_body"):
			body = tuning["factory_body"]
		reference_truck.call(&"set_paint", body, tuning["trim"])
		if reference_truck.has_method(&"set_retro"):
			reference_truck.call(&"set_retro", bool(tuning.get("retro", false)))


func _on_horn_honked(_peer_id: int) -> void:
	_horn_player.play()


func set_controls(throttle: float, steering_input: float, handbrake: bool) -> void:
	_throttle = clampf(throttle, -1.0, 1.0)
	_steering_input = clampf(steering_input, -1.0, 1.0)
	_handbrake = handbrake
	if absf(_throttle) > 0.01 or absf(_steering_input) > 0.01:
		sleeping = false


## The controls as set_controls left them, for VehiclePrediction to number and send to the host.
func throttle_input() -> float:
	return _throttle


func steer_input() -> float:
	return _steering_input


func handbrake_input() -> bool:
	return _handbrake


## The client at the wheel sends this every physics tick
## (vehicle_prediction.gd), numbered by its own tick: the host plays the inputs
## back one per tick (NetInputBuffer) and its pose says which one it stands for
## (net_input_seq). Unreliable and ordered: a dropped sample just means the
## last one is held a tick, same as UDP game input anywhere else -- resending
## a stale one would be worse than skipping it. Called locally (sender 0) it
## takes effect at once, unnumbered.
@rpc("any_peer", "call_local", "unreliable_ordered")
func submit_driver_input(seq: int, throttle: float, steering_input: float, handbrake: bool) -> void:
	if not is_multiplayer_authority():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != driver_peer_id:
		return  # Ignore stale input from whoever just gave up the wheel.
	# clampf() lets a NaN through, and one NaN in the wheels breaks Jolt (N-221).
	if not RpcGuard.finite_float(throttle) or not RpcGuard.finite_float(steering_input):
		return
	if sender_id == 0:
		set_controls(throttle, steering_input, handbrake)
	else:
		receive_driver_input(seq, throttle, steering_input, handbrake)


## Host: a numbered input from the client at the wheel, played on its tick
## (VehiclePrediction.host_tick).
func receive_driver_input(seq: int, throttle: float, steering_input: float, handbrake: bool) -> void:
	_prediction.receive(seq, clampf(throttle, -1.0, 1.0), clampf(steering_input, -1.0, 1.0), handbrake)


## A client: the host's gear arrived. Predicting its truck (N-218), the copy has the clutch in for the shift as the
## host's had, instead of pulling straight on in the new gear (N-922.7): the host times the clutch, which isn't
## replicated, so the copy times its own from the gear arriving.
func _on_remote_gear_changed(_gear: int) -> void:
	if _prediction.active and gearbox.enabled:
		gearbox.shift_left = VehicleGearbox.SHIFT_SECONDS


## Whether this truck's variant is worked by a manual gearbox (N-114).
func has_manual_gearbox() -> bool:
	return bool(VARIANTS[variant_id].get("manual", false))


## Host only: the driver asks for a gear up (+1) or down (-1). Same packet
## rules as submit_driver_input (only the current driver counts), but reliable
## and not repeated: a shift that got lost would leave the driver in the wrong
## gear with no way to tell. Added with N-114; it spends the sender's request
## budget like every reliable any_peer RPC (N-221, N-238).
@rpc("any_peer", "reliable")
func request_gear_shift(direction: int) -> void:
	if not is_multiplayer_authority() or absi(direction) != 1 or not RpcGuard.allow_request(self):
		return
	# Only the current driver counts. Explicit comparison on purpose: with
	# driver_peer_id == 0 (nobody at the wheel) a remote sender must not pass.
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != driver_peer_id:
		return
	gearbox.request_shift(direction)


## What this truck's variant multiplies the crew's delivery payout by (1.0 for
## the ordinary ones, the manual van's compensation for the old one). The one
## source of it: CrewProgression asks the truck on the road.
func pay_multiplier() -> float:
	return float(VARIANTS[variant_id].get("pay_multiplier", 1.0))


## What the gear readout shows: "1".."5", or "R" while backing up; empty when
## the truck is automatic. Reads replicated state only, so it holds on a client.
func gear_text() -> String:
	if not gearbox.enabled:
		return ""
	if linear_velocity.dot(-global_basis.z) < -0.7:
		return "R"
	return str(gearbox.gear)


func get_cargo_spawn_transform() -> Transform3D:
	return fleet_cargo.get_cargo_spawn_transform()


## All the parts of a packet in (they travel together, in whatever order
## they're applied): hand the pose to the smoother, and to the prediction
## when this client drives (N-218). The very first one also puts the truck
## there at once, so a joining client doesn't see it slide in.
func _commit_net_pose() -> void:
	if _net_received != NET_POSE_PARTS:
		return
	_net_received = 0
	if is_inside_tree() and is_multiplayer_authority():
		return
	var pose := Transform3D(Basis.from_euler(_net_incoming_rotation), _net_incoming_position)
	var first: bool = _net_smoother.is_empty()
	_net_smoother.push(_net_incoming_time, pose, Time.get_ticks_usec() / 1000000.0)
	_prediction.host_state(_net_incoming_seq, pose, _net_incoming_velocity, _net_incoming_spin)
	if first and not _prediction.active:
		transform = pose


## A client draws the host's truck every frame from the smoother (N-208),
## and its wheels -- unless it is predicting its own (N-218): then physics
## moves it and its wheels, as on the host.
func _process(delta: float) -> void:
	if is_multiplayer_authority() or _prediction.active:
		return
	if not _net_smoother.is_empty():
		var pose: Transform3D = _net_smoother.sample(Time.get_ticks_usec() / 1000000.0)
		if pose != Transform3D.IDENTITY:
			transform = _prediction.blend_exit(pose, delta)
	_pose_remote_wheels(delta)


## The bad link a `--net-sim` profile ({lag_ms, jitter_ms, loss_pct}) simulates on this peer's copy: the host's
## poses it draws, and, at the wheel, the inputs it sends and the host's states it compares with (N-922.5). The
## poses and the states come the same way, half the lag as over Steam (N-922.9): with the whole lag on the poses,
## the newest one a prediction starts toward was half a lag older than the host's states it is then compared with.
## The smoother keeps what it had for an empty profile; one with zeros turns everything off.
func configure_net_sim(sim: Dictionary) -> void:
	_net_smoother.configure_sim(sim, 0.5)
	_prediction.configure_sim(sim)


## Whether this peer is the client predicting the truck it drives (N-218).
func is_predicted() -> bool:
	return _prediction.active


## Stops this peer predicting its truck, frozen where it is (N-922): the level, when the host is gone mid-drive and
## this peer, an offline host now, no longer stops on its own.
func stop_prediction() -> void:
	_prediction.halt(self)


## A client's truck is frozen, so physics never moves its wheels: they are put
## where the host's are, from what it sends -- each one's height
## (net_wheel_heights), `steering` on the front pair, and the speed, which
## spins them as VehicleBody3D does (distance along the wheel's heading over
## its radius). Steer about up, then spin about the axle, then WHEEL_AXES.
func _pose_remote_wheels(delta: float) -> void:
	for index: int in range(_wheels.size()):
		var wheel: VehicleWheel3D = _wheels[index]
		var mount: Vector3 = _wheel_mounts[wheel]
		var steer := Basis(Vector3.UP, steering if wheel.use_as_steering else 0.0)
		var rolled: float = linear_velocity.dot(global_basis * (steer * Vector3.BACK)) * delta / wheel.wheel_radius
		_wheel_spin[index] = fposmod(_wheel_spin[index] + rolled, TAU)
		var height: float = _net_wheel_heights[index] if index < 4 else mount.y
		wheel.transform = Transform3D(steer * Basis(Vector3.RIGHT, _wheel_spin[index]) * WHEEL_AXES,
				Vector3(mount.x, height, mount.z))


func _physics_process(delta: float) -> void:
	fleet_motion.sample(delta)
	if not is_multiplayer_authority():
		# The client at the wheel (N-218): sends its input, and while the host's
		# truck is simulated too, predicts its own copy with it.
		if _prediction.client_tick(self, delta, _net_smoother, _net_incoming_velocity, _net_incoming_spin,
				net_simulating):
			_drive(delta, presentation_engine_running)
		_match_interpolation_to_freeze()
		return
	_match_interpolation_to_freeze()
	_host_clock += delta
	if not _grounded_once:
		_snap_to_ground()
	# The remote driver's input for this tick (N-218).
	_prediction.host_tick(self)
	_update_parking(delta)
	net_simulating = not freeze
	if freeze and not _parked:
		_pose_frozen_wheels()
	fleet_cargo.follow(delta)
	if rear_ramp_deployed and (not rear_cargo_open or speed_kmh > RAMP_STOW_SPEED):
		rear_ramp_deployed = false
	elif not rear_ramp_deployed and rear_cargo_open and speed_kmh < RAMP_DEPLOY_SPEED:
		rear_ramp_deployed = true
	var running: bool = RunManager.is_running
	presentation_engine_running = running
	_drive(delta, running)

	_telemetry_time += delta
	if _telemetry_time >= 0.1:
		_telemetry_time = 0.0
		EventBus.relay(&"vehicle_telemetry", [speed_kmh])

	# Velocity discontinuities give the package system a tunable shake signal.
	# Ignore the initial settling fall and continuous gravity while airborne.
	_settling_time = maxf(0.0, _settling_time - delta)
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	var velocity_change: float = (linear_velocity - _previous_velocity).length()
	if running and _settling_time <= 0.0 and _impact_cooldown <= 0.0 and velocity_change >= 3.0:
		EventBus.relay(&"vehicle_impact", [velocity_change, global_position])
		_impact_cooldown = 0.3
	_previous_velocity = linear_velocity


## The truck's own driving for this tick, from the controls: steering, engine
## and brakes. Runs on the host's truck, and on the copy a client at the wheel
## predicts (N-218), which takes `running` and the gear from what the host
## replicates.
func _drive(delta: float, running: bool) -> void:
	var forward_speed: float = linear_velocity.dot(-global_basis.z)
	var throttle: float = _throttle if running else 0.0
	var steer_input: float = _steering_input if running else 0.0
	var steering_scale: float = lerpf(1.0, 0.48, clampf(speed_kmh / maximum_speed_kmh, 0.0, 1.0))
	steering = move_toward(steering, -steer_input * maximum_steering * steering_scale, steering_response * delta)
	engine_force = 0.0
	brake = 0.0

	if not running or _handbrake:
		brake = braking_force
	elif throttle < -0.01 and forward_speed > 0.7:
		brake = braking_force * absf(throttle)
	elif throttle > 0.01 and forward_speed < -0.7:
		brake = braking_force * throttle
	elif throttle > 0.01 and forward_speed * 3.6 < maximum_speed_kmh:
		# 1.0 unless the variant has a manual gearbox (N-114).
		var drive: float = gearbox.drive_multiplier(forward_speed * 3.6, maximum_speed_kmh)
		engine_force = -throttle * maximum_engine_force * drive
	elif throttle < -0.01 and forward_speed * 3.6 > -reverse_speed_kmh:
		engine_force = -throttle * maximum_engine_force * 0.55
	elif absf(throttle) < 0.01:
		brake = 0.6
	# Climbing out pulls the handbrake (seat_point.gd); once parked nobody is
	# on the pedal, so the brake lights go off. Not on driver_peer_id alone:
	# scripted runs (vehicle_network_probe, trailer_shot) brake driverless.
	if is_multiplayer_authority():
		presentation_braking = running and brake > 3.0 and not _parked
	if gearbox.enabled and is_multiplayer_authority():
		gearbox.tick(delta)
		if not running:
			gearbox.reset()
	elif gearbox.enabled:
		# The predicting copy's own clutch (_on_remote_gear_changed) runs out; the shifts are the host's.
		gearbox.shift_left = maxf(gearbox.shift_left - delta, 0.0)
	if gearbox.enabled and running:
		# The engine holds the truck back when it is over its gear's limit;
		# the brake lights stay off for that (decided above).
		brake = maxf(brake, gearbox.engine_brake(forward_speed * 3.6, maximum_speed_kmh))

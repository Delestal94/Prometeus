extends VehicleBody3D
## A deliberately forgiving first delivery van, with physical, loose cargo.
## Visual front is local -Z; VehicleBody3D's native engine direction is +Z.
##
## Host-authoritative: this node's multiplayer authority is the host (the
## Godot default for a static, non-spawned node, never reassigned). On every
## other peer it's a synced puppet -- frozen so the physics engine doesn't
## fight the transform MultiplayerSynchronizer is about to hand it, driven
## only by whatever the host broadcasts.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")

## Which peer currently holds the wheel, synced to everyone so each client's
## VehicleInputComponent knows whether it's the one that should be reading
## input at all. 0 means nobody's driving.
@export var driver_peer_id: int = 0:
	set(value):
		var changed: bool = value != driver_peer_id
		driver_peer_id = value
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
## Suspension attach points as authored; see _pose_frozen_wheels().
var _wheel_mounts: Dictionary = {}

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
## A 0.65 m box's half height: rack markers sit that far above their deck.
const MOUNT_REFERENCE_HALF_HEIGHT: float = 0.325
## The cargo bay's inside in the truck's own space: side wall to side wall,
## floor to roof, cab wall to rear doors (vehicle.tscn's collision shapes).
## Whatever is in here rides with the truck -- see carries().
const CARGO_BAY: AABB = AABB(Vector3(-1.05, 0.0, -0.35), Vector3(2.1, 2.6, 4.95))
## Inner face of each side wall (WallCollision at x = ±1.05, 0.1 thick).
const CARGO_WALL_INNER_X: float = 1.0
## Room a shelved box keeps from the wall: its tape and straps stick out a
## few centimetres past the collider (package_feedback.gd).
const CARGO_WALL_CLEARANCE: float = 0.045

@onready var _package_spawn: Marker3D = $CargoBay/LeftSeat1PackageMount
var _horn_player: AudioStreamPlayer3D


func _ready() -> void:
	if not is_multiplayer_authority():
		# A remote peer's copy: kinematic from here on, positioned entirely by
		# the MultiplayerSynchronizer. Letting the physics engine run too would
		# fight the incoming synced transform every frame.
		freeze = true
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
	var reference_truck := preload("res://scripts/presentation/reference_truck.gd").new()
	reference_truck.name = "ReferenceTruck"
	add_child(reference_truck)
	# Setters ran before the scene was ready (defaults, spawn sync); apply the
	# current state to collision and art once everything exists.
	for door: StringName in [&"rear", &"cab_left", &"cab_right"]:
		_apply_door(door, is_door_open(door))
	rear_ramp_deployed = rear_ramp_deployed
	if is_multiplayer_authority():
		EventBus.package_placed.connect(_on_package_placed)


## Whether a world point is inside the cargo bay, i.e. riding along: players
## standing in the back, boxes, loose clutter. Uses this peer's copy of the
## truck, so on a client it answers for the truck that client actually sees.
##
## `margin` grows the bay on every side: whoever's already aboard passes it,
## so something right at the rear doors doesn't flicker in and out.
func carries(world_point: Vector3, margin: float = 0.0) -> bool:
	return CARGO_BAY.grow(margin).has_point(to_local(world_point))


## How fast a point riding in the truck is moving in the world: what a box
## let go of in the moving bay has to start with, or it slams into the rear
## wall as if dropped from a standstill. linear_velocity is replicated, so
## this holds on a client's copy too.
func point_velocity(world_point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(world_point - global_transform * center_of_mass)


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
		var blocker := get_node_or_null(^"RearDoorCollision") as CollisionShape3D
		if blocker != null:
			blocker.set_deferred(&"disabled", open)
	var reference_truck := get_node_or_null(^"ReferenceTruck")
	if reference_truck != null:
		reference_truck.call(&"set_door_open", door, open)


## A box set on the rack rests on its deck whatever its shape: the markers
## are placed for the standard 0.65 m box, so a tall or flat one is raised or
## lowered by the difference instead of sinking into the deck or hovering.
func _on_package_placed(package_id: StringName) -> void:
	for package: Node in get_tree().get_nodes_in_group(&"cargo"):
		if package.get(&"package_id") != package_id or not package.has_method(&"get_half_extents"):
			continue
		var mount_point: Node = package.get(&"current_mount") as Node
		# A mount's interaction area hangs off its marker; place_at() may also
		# have been handed the marker itself.
		var marker: Node3D = mount_point as Node3D
		if mount_point is Area3D:
			marker = mount_point.get_parent() as Node3D
		if marker == null or not is_ancestor_of(marker):
			continue
		var half: Vector3 = package.call(&"get_half_extents")
		var offset: float = half.y - MOUNT_REFERENCE_HALF_HEIGHT
		var local_center: Vector3 = to_local(marker.global_transform * Vector3(0.0, offset, 0.0))
		# A wide box (the flat one is 0.95 m) centred on a marker laid out for
		# the 0.65 m one reached into the side wall, and its tape and straps
		# showed through on the outside: slide it in until it clears.
		var box_basis: Basis = global_basis.inverse() * marker.global_basis
		var reach_x: float = (absf(box_basis.x.x) * half.x + absf(box_basis.y.x) * half.y
			+ absf(box_basis.z.x) * half.z + CARGO_WALL_CLEARANCE)
		var limit_x: float = maxf(CARGO_WALL_INNER_X - reach_x, 0.0)
		local_center.x = clampf(local_center.x, -limit_x, limit_x)
		(package as Node3D).global_position = to_global(local_center)
		(package as Node3D).reset_physics_interpolation()


## A heavy truck left with nobody at the wheel doesn't roll: VehicleBody3D's
## brake never quite holds, so it crept off a few centimetres a second (more
## on a slope), out from under the crew and away from the door they'd just
## climbed out of. Once it's slow and driverless it is frozen in place, and
## let go the moment somebody takes the wheel. Only during a delivery --
## before and after one, the level freezes and releases the truck itself.
func _update_parking() -> void:
	if not RunManager.is_running:
		_parked = false
		return
	var commanded: bool = driver_peer_id != 0 or absf(_throttle) > 0.01
	if _parked:
		if commanded:
			_parked = false
			freeze = false
			sleeping = false
		return
	if not commanded and not freeze and speed_kmh < PARK_SPEED_KMH:
		_parked = true
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
	_apply_paint()


func _apply_paint() -> void:
	var reference_truck := get_node_or_null(^"ReferenceTruck")
	if reference_truck != null:
		reference_truck.call(&"set_paint", PAINTS[paint_id], VARIANTS[variant_id]["trim"])


func _on_horn_honked(_peer_id: int) -> void:
	_horn_player.play()


func set_controls(throttle: float, steering_input: float, handbrake: bool) -> void:
	_throttle = clampf(throttle, -1.0, 1.0)
	_steering_input = clampf(steering_input, -1.0, 1.0)
	_handbrake = handbrake
	if absf(_throttle) > 0.01 or absf(_steering_input) > 0.01:
		sleeping = false


## Whoever is driving calls this on their own client; it only actually
## applies on the host, which is the only place set_controls() should take
## effect. Unreliable and ordered: a dropped throttle sample just means the
## next one (a 60th of a second later) supersedes it, same as UDP game input
## anywhere else -- resending a stale one would be worse than skipping it.
@rpc("any_peer", "call_local", "unreliable_ordered")
func submit_driver_input(throttle: float, steering_input: float, handbrake: bool) -> void:
	if not is_multiplayer_authority():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != driver_peer_id:
		return  # Ignore stale input from whoever just gave up the wheel.
	set_controls(throttle, steering_input, handbrake)


func get_cargo_spawn_transform() -> Transform3D:
	return _package_spawn.global_transform


func _physics_process(delta: float) -> void:
	_match_interpolation_to_freeze()
	if not is_multiplayer_authority():
		return
	if not _grounded_once:
		_snap_to_ground()
	_update_parking()
	if freeze and not _parked:
		_pose_frozen_wheels()
	if rear_ramp_deployed and (not rear_cargo_open or speed_kmh > RAMP_STOW_SPEED):
		rear_ramp_deployed = false
	elif not rear_ramp_deployed and rear_cargo_open and speed_kmh < RAMP_DEPLOY_SPEED:
		rear_ramp_deployed = true
	var running: bool = RunManager.is_running
	presentation_engine_running = running
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
		engine_force = -throttle * maximum_engine_force
	elif throttle < -0.01 and forward_speed * 3.6 > -reverse_speed_kmh:
		engine_force = -throttle * maximum_engine_force * 0.55
	elif absf(throttle) < 0.01:
		brake = 0.6
	presentation_braking = running and brake > 3.0

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

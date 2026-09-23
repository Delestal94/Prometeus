extends VehicleBody3D
## A deliberately forgiving first delivery van, with physical, loose cargo.
## Visual front is local -Z; VehicleBody3D's native engine direction is +Z.
##
## Host-authoritative: this node's multiplayer authority is the host (the
## Godot default for a static, non-spawned node, never reassigned). On every
## other peer it's a synced puppet -- frozen so the physics engine doesn't
## fight the transform MultiplayerSynchronizer is about to hand it, driven
## only by whatever the host broadcasts.

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
	_horn_player.stream = SynthAudio.honk_horn()
	_horn_player.unit_size = 15.0
	# No volume_db was ever set here -- defaulted to 0 dB, dramatically
	# louder than every other sound in the mix (engine peaks around -21 dB;
	# the impact thud, the loudest deliberate peak elsewhere, around -6 dB).
	# Matched to the impact thud's peak: loud and attention-grabbing on
	# purpose, not an accident of an unset property.
	_horn_player.volume_db = -6.0
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
		var half_height: float = (package.call(&"get_half_extents") as Vector3).y
		var offset: float = half_height - MOUNT_REFERENCE_HALF_HEIGHT
		(package as Node3D).global_position = marker.global_transform * Vector3(0.0, offset, 0.0)


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
func _pose_frozen_wheels() -> void:
	for wheel: VehicleWheel3D in _wheel_mounts:
		var mount: Vector3 = _wheel_mounts[wheel]
		wheel.position = Vector3(mount.x, TIRE_RADIUS - RIDE_HEIGHT, mount.z)
		wheel.rotation = Vector3.ZERO


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
	if not is_multiplayer_authority():
		return
	if not _grounded_once:
		_snap_to_ground()
	if freeze:
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

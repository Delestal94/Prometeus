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
@export var driver_peer_id: int = 0
@export var controls_enabled: bool = true
@export var maximum_engine_force: float = 1700.0
@export var maximum_speed_kmh: float = 72.0
@export var reverse_speed_kmh: float = 18.0
@export var braking_force: float = 55.0
@export var maximum_steering: float = 0.42
@export var steering_response: float = 2.0

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

@onready var _package_spawn: Marker3D = $CargoBay/LeftSeat1PackageMount


func _ready() -> void:
	if not is_multiplayer_authority():
		# A remote peer's copy: kinematic from here on, positioned entirely by
		# the MultiplayerSynchronizer. Letting the physics engine run too would
		# fight the incoming synced transform every frame.
		freeze = true


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
	var running: bool = RunManager.is_running
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

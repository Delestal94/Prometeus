extends Node
## Input is isolated so tests and future network drivers can use set_controls().
##
## This runs identically on every peer's copy of the (shared, non-spawned)
## Vehicle node -- so it has to work out on its own whether *this* peer is
## the one currently driving, and if it isn't the host, forward the reading
## to the host instead of touching the vehicle directly.

@onready var _vehicle: VehicleBody3D = get_parent() as VehicleBody3D


func _physics_process(_delta: float) -> void:
	if not _vehicle.controls_enabled:
		return
	if not _is_local_driver():
		return
	var throttle: float = 0.0
	var steer: float = 0.0
	var handbrake: bool = false
	if RunManager.is_running:
		throttle = Input.get_axis("drive_brake", "drive_accelerate")
		steer = Input.get_axis("drive_left", "drive_right")
		handbrake = Input.is_action_pressed("drive_handbrake")
		if Input.is_action_just_pressed(&"drive_horn"):
			_send_horn()
	if _vehicle.is_multiplayer_authority():
		_vehicle.set_controls(throttle, steer, handbrake)
	else:
		_vehicle.rpc_id(1, &"submit_driver_input", throttle, steer, handbrake)


func _is_local_driver() -> bool:
	if not NetworkManager.is_online():
		return true
	return _vehicle.driver_peer_id == NetworkManager.local_id()


## Same call-direct-or-rpc_id(1,...) split as every other player-initiated
## action that needs the host to decide it "really happened" -- see
## Player._send_ping() for the identical pattern.
func _send_horn() -> void:
	if NetworkManager.is_online() and not NetworkManager.is_host():
		EventBus.rpc_id(1, &"request_horn")
	else:
		EventBus.call(&"request_horn")

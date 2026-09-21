extends Node
## Input is isolated so tests and future network drivers can use set_controls().

@onready var _vehicle: VehicleBody3D = get_parent() as VehicleBody3D


func _physics_process(_delta: float) -> void:
	if not _vehicle.controls_enabled:
		return
	if not RunManager.is_running:
		_vehicle.set_controls(0.0, 0.0, false)
		return
	_vehicle.set_controls(
		Input.get_axis("drive_brake", "drive_accelerate"),
		Input.get_axis("drive_left", "drive_right"),
		Input.is_action_pressed("drive_handbrake")
	)

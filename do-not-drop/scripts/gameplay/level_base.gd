extends Node3D
## Composes the phase-1 sandbox. Physics, trap logic and HUD remain separate.
## The run now starts on its own once the driver's seat and the package
## mount both report an interaction -- no button needed for the real flow.

const STOP_SECONDS: float = 1.0
const DELIVERY_MAX_SPEED: float = 1.5
@onready var vehicle: VehicleBody3D = $World/Vehicle
@onready var package: RigidBody3D = $World/Package
@onready var route: Node3D = $World/Route
@onready var _driver_seat: Area3D = $World/Vehicle/CabinInterior/DriverEyePoint/InteractionArea
@onready var _package_mount: Area3D = $World/Vehicle/CargoBay/LeftSeat1PackageMount/InteractionArea
var stopped_seconds: float = 0.0
var tipped_seconds: float = 0.0
var _driver_seated: bool = false
var _package_loaded: bool = false


func _ready() -> void:
	RunManager.reset_run()
	vehicle.freeze = true
	package.freeze = true
	_driver_seat.interacted.connect(_on_driver_seated)
	_package_mount.interacted.connect(_on_package_loaded)
	EventBus.start_requested.connect(start_debug_delivery)
	EventBus.restart_requested.connect(restart_delivery)
	EventBus.pause_requested.connect(toggle_pause)
	EventBus.run_ended.connect(_on_run_ended)
	# Command line shortcut for smoke checks and development: skips the
	# on-foot loading entirely, same as the HUD's debug button.
	if "--autostart" in OS.get_cmdline_user_args():
		start_debug_delivery.call_deferred()


func start_debug_delivery() -> void:
	if RunManager.is_running or not RunManager.results.is_empty():
		return
	var player: Node = $World/Player
	if not _package_loaded:
		player.pick_up(package)
		_package_mount.interact(player)
	if not _driver_seated:
		_driver_seat.interact(player)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_driver_seated(_player: Node) -> void:
	_driver_seated = true
	_maybe_start()


func _on_package_loaded(_player: Node) -> void:
	_package_loaded = true
	_maybe_start()


func _maybe_start() -> void:
	if _driver_seated and _package_loaded:
		start_delivery()


func start_delivery() -> void:
	if RunManager.is_running or not RunManager.results.is_empty() or not (_driver_seated and _package_loaded):
		return
	vehicle.freeze = false
	package.freeze = false
	RunManager.start_run()


func restart_delivery() -> void:
	get_tree().paused = false
	RunManager.reset_run()
	get_tree().reload_current_scene()


func toggle_pause() -> void:
	if RunManager.results.is_empty():
		get_tree().paused = not get_tree().paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not RunManager.is_running:
		return
	var progress: float = route.get_progress(vehicle.global_position)
	EventBus.route_progress_changed.emit(progress, route.route_length * (1.0 - progress), route.get_section_name(vehicle.global_position))
	if route.is_vehicle_in_delivery and vehicle.linear_velocity.length() < DELIVERY_MAX_SPEED:
		stopped_seconds += delta
	else:
		stopped_seconds = 0.0
	EventBus.delivery_status_changed.emit(route.is_vehicle_in_delivery, stopped_seconds)
	if stopped_seconds >= STOP_SECONDS:
		RunManager.finish_run(true)
		return
	if vehicle.global_basis.y.dot(Vector3.UP) < 0.25:
		tipped_seconds += delta
	else:
		tipped_seconds = 0.0
	if tipped_seconds > 4.0:
		RunManager.finish_run(false, "La camioneta volcó. Tomá las curvas más despacio.")
	elif vehicle.global_position.y < -8.0 or absf(vehicle.global_position.x) > 42.0:
		RunManager.finish_run(false, "Te saliste de la ruta. Reiniciá para intentarlo de nuevo.")
	elif package.global_position.distance_to(vehicle.global_position) > 8.0:
		RunManager.finish_run(false, "Perdiste la carga. El paquete tiene que llegar con vos.")


func _on_run_ended(_score: int, _results: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Defer rigid-body changes: failure can originate in physics integration.
	vehicle.set_deferred("freeze", true)
	package.set_deferred("freeze", true)

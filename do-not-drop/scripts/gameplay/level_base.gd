extends Node3D
## Composes the phase-1/2 sandbox. Physics, trap logic and HUD remain separate.
## The run starts on its own once a driver is seated with at least one package
## loaded -- no button needed for the real flow.

const STOP_SECONDS: float = 1.0
const DELIVERY_MAX_SPEED: float = 1.5
const LOST_CARGO_DISTANCE: float = 8.0
@onready var vehicle: VehicleBody3D = $World/Vehicle
@onready var route: Node3D = $World/Route
@onready var _driver_seat: Area3D = $World/Vehicle/CabinInterior/DriverEyePoint/InteractionArea
var packages: Array[Node] = []
var stopped_seconds: float = 0.0
var tipped_seconds: float = 0.0
var _driver_seated: bool = false
var _loaded_count: int = 0


func _ready() -> void:
	RunManager.reset_run()
	vehicle.freeze = true
	packages.assign(get_tree().get_nodes_in_group(&"cargo"))
	for package: Node in packages:
		package.set(&"freeze", true)
	_driver_seat.interacted.connect(_on_driver_seated)
	for mount: Node in get_tree().get_nodes_in_group(&"package_mount"):
		mount.connect(&"interacted", _on_package_loaded)
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
	if _loaded_count == 0 and not packages.is_empty():
		var mount: Node = get_tree().get_first_node_in_group(&"package_mount")
		player.call(&"pick_up", packages[0])
		mount.call(&"interact", player)
	if not _driver_seated:
		_driver_seat.interact(player)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_driver_seated(_player: Node) -> void:
	_driver_seated = true
	_maybe_start()


func _on_package_loaded(_player: Node) -> void:
	_loaded_count += 1
	_maybe_start()


func _maybe_start() -> void:
	if _driver_seated and _loaded_count > 0:
		start_delivery()


func start_delivery() -> void:
	if RunManager.is_running or not RunManager.results.is_empty():
		return
	if not _driver_seated or _loaded_count == 0:
		return
	vehicle.freeze = false
	for package: Node in packages:
		if bool(package.get(&"is_loaded")):
			package.set(&"freeze", false)
			# Only what's aboard counts: a box left on the rack was never
			# part of this delivery, so it shouldn't drag the score down.
			package.call(&"report_to_run")
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
	_check_lost_cargo()
	if vehicle.global_basis.y.dot(Vector3.UP) < 0.25:
		tipped_seconds += delta
	else:
		tipped_seconds = 0.0
	if tipped_seconds > 4.0:
		RunManager.finish_run(false, "La camioneta volcó. Tomá las curvas más despacio.")
	elif vehicle.global_position.y < -8.0 or absf(vehicle.global_position.x) > 42.0:
		RunManager.finish_run(false, "Te saliste de la ruta. Reiniciá para intentarlo de nuevo.")


func _check_lost_cargo() -> void:
	# A box that falls out is written off on its own. Only losing every last
	# one ends the delivery, and RunManager decides that.
	for package: Node in packages:
		if not bool(package.get(&"is_loaded")):
			continue
		var distance: float = (package.get(&"global_position") as Vector3).distance_to(vehicle.global_position)
		if distance > LOST_CARGO_DISTANCE:
			package.call(&"mark_lost", "Se cayó de la furgoneta.")


func _on_run_ended(_score: int, _results: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Defer rigid-body changes: failure can originate in physics integration.
	vehicle.set_deferred("freeze", true)
	for package: Node in packages:
		package.set_deferred("freeze", true)

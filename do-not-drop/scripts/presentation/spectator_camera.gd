extends Camera3D
## Spectator view (docs/tareas-slatex.md #20): a passenger whose box is
## already ruined -- or who has nothing left to tend -- can stop staring at
## the wreck and watch the run from a chase camera behind the truck instead.
## "spectate_toggle" (Tab / Back) switches in and out; orbit with mouse or
## right stick. Purely local, like every other camera in the game.
##
## Created by VehiclePresentation. Hands the view back on its own the moment
## the player stops qualifying (gets up, takes the wheel, run ends).

signal availability_changed(available: bool)

const DISTANCE: float = 7.5
const HEIGHT: float = 2.8
const FOLLOW_SHARPNESS: float = 5.0
const ORBIT_MOUSE: float = 0.004
const ORBIT_STICK: float = 2.2

var vehicle: VehicleBody3D
var available: bool = false
var _previous: Camera3D
var _orbit: float = 0.0
var _placed: bool = false


func _ready() -> void:
	name = "SpectatorCamera"
	top_level = true
	current = false
	far = 600.0
	fov = 70.0
	# Moved every rendered frame from the truck's drawn pose.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	var now_available: bool = _local_can_spectate()
	if now_available != available:
		available = now_available
		availability_changed.emit(available)
		if not available and current:
			stop()
	if not current:
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_orbit -= Input.get_axis(&"look_left", &"look_right") * ORBIT_STICK * delta
	var truck: Transform3D = vehicle.get_global_transform_interpolated()
	var heading := Basis(Vector3.UP, truck.basis.get_euler().y + _orbit)
	var goal: Vector3 = truck.origin + heading * Vector3(0.0, HEIGHT, DISTANCE)
	global_position = goal if not _placed else global_position.lerp(goal, 1.0 - exp(-FOLLOW_SHARPNESS * delta))
	_placed = true
	look_at(truck.origin + Vector3.UP * 1.2, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if current and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_orbit -= (event as InputEventMouseMotion).relative.x * ORBIT_MOUSE
	if InputMap.has_action(&"spectate_toggle") and event.is_action_pressed(&"spectate_toggle"):
		if current:
			stop()
		elif available:
			start()
		get_viewport().set_input_as_handled()


func start() -> void:
	_previous = get_viewport().get_camera_3d()
	_placed = false
	_orbit = 0.0
	current = true


func stop() -> void:
	current = false
	if _previous != null and is_instance_valid(_previous):
		_previous.current = true
	_previous = null


## Seated as a passenger (not driving) during a run, with no box to save.
func _local_can_spectate() -> bool:
	var manager: Node = get_node_or_null(^"/root/RunManager")
	if manager == null or not bool(manager.get(&"is_running")):
		return false
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	var local_id: int = int(network.call(&"local_id")) if network != null else 1
	if int(vehicle.get(&"driver_peer_id")) == local_id:
		return false
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		if player.get_multiplayer_authority() != local_id:
			continue
		if not bool(player.get(&"_seated")):
			return false
		var tended: Variant = player.get(&"tended_package")
		if tended == null or not is_instance_valid(tended):
			return true
		return int((tended as Node).get(&"trap_state")) == ITrapBehavior.TrapState.RUINED
	return false


## Results shot (docs/tareas-nacho.md #36): once the run ends, a slow orbit
## around the truck behind the results card -- wherever it ended up, dented,
## on its side or at the goal. Takes over from whatever camera was active.
static func orbit_results(truck: VehicleBody3D) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "ResultsCamera"
	camera.top_level = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.far = 600.0
	camera.fov = 55.0
	camera.set_script(preload("res://scripts/presentation/results_orbit.gd"))
	camera.set(&"target", truck)
	truck.add_child(camera)
	camera.make_current()
	return camera

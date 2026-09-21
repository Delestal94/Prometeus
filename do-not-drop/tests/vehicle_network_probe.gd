extends Node3D
## Two real processes, focused on replicated visual state (not full-session readiness).
var van: VehicleBody3D
var presentation: Node3D
var host_mode: bool = false
var peer_id: int = 0
var elapsed: float = 0.0
var driving_time: float = -1.0
var sent_report_request: bool = false
var observed: Dictionary = {"engine": false, "wheel": false, "steer": false, "brake": false, "beam": false}
var initial_wheel: Transform3D


func _ready() -> void:
	host_mode = "--host" in OS.get_cmdline_user_args()
	var port: int = 17887
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	add_child(load("res://scenes/gameplay/route/route.tscn").instantiate())
	van = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
	van.name = "Van"
	van.position.y = 0.9
	add_child(van)
	van.controls_enabled = false
	van.freeze = true
	presentation = van.get_node("VehiclePresentation")
	initial_wheel = van.get_node("FrontLeftWheel").transform
	if not host_mode:
		van.set_physics_process(false)
	NetworkManager.transport = NetworkManager.Transport.ENET
	NetworkManager.session_ready.connect(_on_session_ready)
	NetworkManager.session_failed.connect(func(reason: String) -> void: _fail(reason))
	var error: Error = NetworkManager.host_session(port) if host_mode else NetworkManager.join_session("127.0.0.1", port)
	if error != OK:
		_fail("Cannot open test session: %d" % error)


func _on_session_ready(is_host: bool) -> void:
	if not is_host:
		ready_to_drive.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func ready_to_drive() -> void:
	if not host_mode:
		return
	peer_id = multiplayer.get_remote_sender_id()
	RunManager.start_run()
	van.freeze = false
	van.set_controls(0.8, 0.35, false)
	driving_time = 0.0


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed > 15.0:
		_fail("Test timeout (no gameplay changes or firewall edits attempted)")
		return
	if host_mode and driving_time >= 0.0:
		driving_time += delta
		if driving_time >= 2.0:
			van.set_controls(0.0, 0.0, true)
		if driving_time >= 3.0 and not sent_report_request:
			sent_report_request = true
			report.rpc_id(peer_id)
	elif not host_mode and NetworkManager.is_online():
		observed.engine = observed.engine or van.presentation_engine_running
		observed.wheel = observed.wheel or not van.get_node("FrontLeftWheel").transform.is_equal_approx(initial_wheel)
		observed.steer = observed.steer or absf(van.steering) > 0.03
		observed.brake = observed.brake or van.presentation_braking
		observed.beam = observed.beam or presentation.headlights[0].light_energy > 0.0


@rpc("authority", "call_remote", "reliable")
func report() -> void:
	var passed: bool = not observed.values().has(false) and van.freeze
	print("CLIENT VISUAL CHECK: ", observed, " frozen=", van.freeze)
	acknowledge.rpc_id(1, passed)
	presentation.audio_enabled = false
	presentation.engine_player.stop()
	await get_tree().create_timer(0.2).timeout
	NetworkManager.leave_session()
	print("PASS: client renders replicated wheel poses, steering, brakes and engine" if passed else "FAIL: incomplete replication")
	get_tree().quit(0 if passed else 1)


@rpc("any_peer", "call_remote", "reliable")
func acknowledge(passed: bool) -> void:
	if not host_mode or multiplayer.get_remote_sender_id() != peer_id:
		return
	presentation.audio_enabled = false
	presentation.engine_player.stop()
	await get_tree().create_timer(0.5).timeout
	NetworkManager.leave_session()
	print("PASS: host received client verification" if passed else "FAIL: client visual state mismatch")
	get_tree().quit(0 if passed else 1)


func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)

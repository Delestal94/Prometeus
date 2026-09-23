extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_spectator.gd
## Spectator view (docs/tareas-slatex.md #20): only a seated passenger with
## no box left to save gets the chase camera; it follows the truck, and it
## hands the view straight back once the player no longer qualifies.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var manager: Node = root.get_node(^"/root/RunManager")
	var van: VehicleBody3D = level.vehicle
	var spectator: Camera3D = van.find_child("SpectatorCamera", true, false)
	_expect(spectator != null, "The truck carries a spectator camera")
	if spectator == null:
		quit(1)
		return
	await process_frame
	_expect(not spectator.available, "Nobody can spectate before the run")

	var player: Node = level.local_player
	# A box in the passenger's own bay, then the seat beside it.
	var box: Node = level.get(&"packages")[0]
	player.call(&"pick_up", box.get_path())
	van.get_node(^"CargoBay/RightSeat1PackageMount/InteractionArea").call(&"interact", player)
	# A second box elsewhere, so losing the first doesn't end the whole run.
	player.call(&"pick_up", level.get(&"packages")[1].get_path())
	van.get_node(^"CargoBay/LeftSeat2PackageMount/InteractionArea").call(&"interact", player)
	for package: Node in level.get(&"packages").slice(0, 2):
		package.call(&"report_to_run")
	van.get_node(^"CargoBay/RightSeat1EyePoint/InteractionArea").call(&"interact", player)
	manager.call(&"start_run")
	for _i: int in range(3):
		await process_frame
	_expect(bool(player.get(&"_seated")), "The player sits as a passenger")
	_expect(not spectator.available, "While their box can still be saved, no spectating")
	player.set(&"tended_package", box)
	box.call(&"mark_lost", "test")
	for _i: int in range(3):
		await process_frame
	_expect(spectator.available, "Once their box is ruined, they may spectate")
	var seat_camera: Camera3D = root.get_viewport().get_camera_3d()
	spectator.start()
	for _i: int in range(5):
		await process_frame
	_expect(root.get_viewport().get_camera_3d() == spectator, "The chase camera takes over the view")
	_expect(spectator.global_position.distance_to(van.global_position) < 12.0, "It sits right behind the truck (%.1f m)" % spectator.global_position.distance_to(van.global_position))

	player.call(&"leave_seat")
	for _i: int in range(3):
		await process_frame
	_expect(not spectator.current and not spectator.available, "Getting up ends spectating on its own")
	_expect(root.get_viewport().get_camera_3d() != spectator, "The view goes back to the player (was %s)" % seat_camera)

	manager.call(&"reset_run")
	level.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: only a passenger with nothing left to save spectates, and the view comes back on its own")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

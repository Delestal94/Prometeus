extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/interaction/tests/test_interaction_module.gd
##
## The interaction module on its own (docs/modulos.md), with stand-in
## players and a vehicle defined here: an Interactable sits on the
## configured layer, answers its prompt and finds players by peer id;
## a remote request is honoured only within reach; a SeatPoint's marker turns red when a player's replicated
## seat is this one, its prompt goes quiet then, the driver's seat hands
## the wheel to the boarder and asks their peer to board, a closed door
## keeps them out, the game's hooks can refuse and are told of boarding
## and release, and release_occupant() takes the wheel back.

var _failures: int = 0


class FakePlayer extends Node3D:
	var seat_node_path: NodePath = NodePath()
	var local: bool = true
	var boarded: Array = []

	func is_local() -> bool:
		return local

	func reach_origin() -> Vector3:
		return global_position

	@rpc("authority", "call_local", "reliable")
	func board_seat(camera_path: NodePath, seat_path: NodePath) -> void:
		boarded.append([camera_path, seat_path])
		seat_node_path = seat_path


class FakeVehicle extends Node3D:
	var driver_peer_id: int = 0
	var controls_enabled: bool = false
	var door_open: bool = true
	var controls: Array = []

	func is_door_open(_door: StringName) -> bool:
		return door_open

	func set_controls(throttle: float, steer: float, brake: bool) -> void:
		controls.append([throttle, steer, brake])


class GameSeat extends SeatPoint:
	var refuse: bool = false
	var boarded_peers: Array = []
	var released_peers: Array = []

	func _free_prompt() -> String:
		return "Take the wheel" if role == &"driver" else "Sit"

	func _accept_boarding(_player: Node) -> bool:
		return not refuse

	func _on_boarded(_player: Node, peer_id: int) -> void:
		boarded_peers.append(peer_id)

	func _on_released(peer_id: int) -> void:
		released_peers.append(peer_id)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var player := FakePlayer.new()
	player.add_to_group(Interactable.player_group)
	scene.add_child(player)
	var plain := Interactable.new()
	plain.prompt = "Open"
	scene.add_child(plain)
	var hits: Array = []
	plain.interacted.connect(func(who: Node) -> void: hits.append(who))
	await process_frame
	_expect(plain.collision_layer == Interactable.interaction_layer and not plain.monitoring and plain.monitorable,
		"An interactable sits on the interaction layer, found but not scanning")
	_expect(plain.get_prompt() == "Open" and plain.can_interact(player), "It answers its prompt and can be used")
	_expect(plain.find_player(1) == player and plain.local_player() == player,
		"Players are found by peer id and locality")
	_expect(plain._within_reach(player), "A player beside it is within reach")
	plain.position = Vector3(50.0, 0.0, 0.0)
	_expect(not plain._within_reach(player), "A player far away is out of reach: a remote request is ignored")
	plain.interact(player)
	_expect(hits == [player], "interact() announces who used it")

	var vehicle := FakeVehicle.new()
	scene.add_child(vehicle)
	var anchor := Node3D.new()
	anchor.name = "DriverEye"
	vehicle.add_child(anchor)
	var camera := Camera3D.new()
	anchor.add_child(camera)
	var seat := GameSeat.new()
	seat.role = &"driver"
	seat.required_door = &"cab"
	anchor.add_child(seat)
	seat.seat_camera_path = seat.get_path_to(camera)
	seat.vehicle_path = seat.get_path_to(vehicle)
	await process_frame
	_expect(seat.get_prompt() == "Take the wheel" and not seat.is_occupied(), "A free seat shows the game's prompt")
	_expect(seat._indicator_material.albedo_color == SeatPoint.free_color, "The marker is green while free")
	vehicle.door_open = false
	_expect(not seat.can_interact(player), "A closed door keeps the player out")
	vehicle.door_open = true
	seat.refuse = true
	seat.interact(player)
	_expect(player.boarded.is_empty() and seat.occupant == null, "The game's hook can refuse the boarding")
	seat.refuse = false
	seat.interact(player)
	_expect(seat.occupant == player and vehicle.driver_peer_id == 1 and vehicle.controls_enabled,
		"Boarding the driver's seat hands over the wheel")
	_expect(player.boarded == [[camera.get_path(), anchor.get_path()]],
		"The player is asked to board with the camera and anchor paths")
	_expect(seat.boarded_peers == [1], "The game's hook is told who boarded")
	seat._update_indicator(true)
	_expect(seat.is_occupied() and seat.get_prompt() == "",
		"A seated player's replicated seat makes it occupied and quiet")
	_expect(seat._indicator_material.albedo_color == SeatPoint.taken_color and not seat._indicator.visible,
		"The marker turns red, and hides from the one sitting there")
	_expect(not seat.can_interact(player), "An occupied seat can't be taken")
	seat.release_occupant(1)
	_expect(seat.occupant == null and vehicle.driver_peer_id == 0 and not vehicle.controls_enabled
		and vehicle.controls == [[0.0, 0.0, true]], "Releasing the driver takes the wheel back and brakes")
	_expect(seat.released_peers == [1], "The game's hook is told who left")
	scene.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: interactables and seats work with stand-in players and a vehicle on the module alone")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

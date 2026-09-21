extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_ping.gd
## Covers the non-verbal ping (docs/controles-y-ui.md): EventBus.request_ping
## is the one RPC in this project that can originate from *any* peer, not
## just the host, so it's worth its own coverage of the offline/local path
## (real cross-peer authorization is what net_smoke.gd-style manual tests
## are for, same as the rest of the RPC surface here).

var _failures: int = 0
var _received: Array = []


func _initialize() -> void:
	await process_frame
	var bus: Node = root.get_node(^"/root/EventBus")
	var network: Node = root.get_node(^"/root/NetworkManager")
	bus.connect(&"ping_sent", func(peer_id: int, position: Vector3, label: String) -> void:
		_received.append([peer_id, position, label]))

	bus.call(&"request_ping", Vector3(4.0, 0.0, -12.0), "¡Cuidado!")
	_expect(_received.size() == 1, "A direct (offline-style) call fires ping_sent immediately")
	if not _received.is_empty():
		_expect(int(_received[0][0]) == int(network.call(&"local_id")),
			"An unattributed call (no RPC in flight) is attributed to the local player")
		_expect((_received[0][1] as Vector3).is_equal_approx(Vector3(4.0, 0.0, -12.0)),
			"Position passes through untouched")
		_expect(String(_received[0][2]) == "¡Cuidado!", "Label passes through untouched")

	# Player._send_ping() is what actually calls this in-game -- covering it
	# separately catches a mismatch (wrong label, wrong call vs rpc_id split)
	# that the direct EventBus call above wouldn't.
	_received.clear()
	var player: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	root.add_child(player)
	await process_frame
	player.global_position = Vector3(1.0, 0.0, -2.0)
	player.call(&"_send_ping")
	_expect(_received.size() == 1, "Player._send_ping() reaches EventBus offline, the same as a real key press would")
	if not _received.is_empty():
		_expect((_received[0][1] as Vector3).is_equal_approx(Vector3(1.0, 0.0, -2.0)),
			"Ping carries the sending player's own position")
	player.free()

	if _failures == 0:
		print("PASS: pings reach EventBus with the right sender, position and label")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

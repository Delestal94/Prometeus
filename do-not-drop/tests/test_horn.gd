extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_horn.gd
## Covers the two parts of the horn that don't need a real window/input
## device to test: EventBus.request_horn()'s any-peer attribution (same
## client->host->everyone shape as request_ping, see test_ping.gd), and that
## the synthesized honk waveform is actually valid audio data, not silence.
## The input binding itself (H / gamepad B) is a one-line project.godot
## entry, not worth a headless test.

var _failures: int = 0
var _received: Array = []


func _initialize() -> void:
	await process_frame
	var bus: Node = root.get_node(^"/root/EventBus")
	var network: Node = root.get_node(^"/root/NetworkManager")
	bus.connect(&"horn_honked", func(peer_id: int) -> void:
		_received.append(peer_id))

	bus.call(&"request_horn")
	_expect(_received.size() == 1, "A direct (offline-style) call fires horn_honked immediately")
	if not _received.is_empty():
		_expect(int(_received[0]) == int(network.call(&"local_id")),
			"An unattributed call (no RPC in flight) is attributed to the local player")

	var vehicle: Node = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
	root.add_child(vehicle)
	await process_frame
	var player: AudioStreamPlayer3D = null
	for child: Node in vehicle.get_children():
		if child is AudioStreamPlayer3D:
			player = child
	_expect(player != null, "The van gets its own horn AudioStreamPlayer3D on _ready()")
	if player != null:
		_expect(not player.playing, "Silent until something actually honks")
		bus.call(&"request_horn")
		_expect(player.playing, "horn_honked (relayed, so this fires on every peer's own van) starts playback")
	vehicle.free()

	var stream: AudioStreamWAV = SynthAudio.honk_horn()
	_expect(stream.data.size() > 0, "The synthesized honk actually contains samples, not silence")
	_expect(stream.mix_rate > 0, "Has a real sample rate set")
	var has_signal: bool = false
	for byte: int in stream.data:
		if byte != 0:
			has_signal = true
			break
	_expect(has_signal, "At least some bytes are non-zero -- an all-zero buffer would still 'have data' but be inaudible")

	if _failures == 0:
		print("PASS: the horn attributes correctly to its sender and the synthesized honk is real audio")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

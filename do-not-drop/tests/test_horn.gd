extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_horn.gd
## Covers the two parts of the horn that don't need a real window/input
## device to test: EventBus.request_horn()'s any-peer attribution (same
## client->host->everyone shape as request_ping, see test_ping.gd), and that
## the synthesized honk waveform is actually valid audio data, not silence.
## The input binding itself (H / gamepad B) is a one-line project.godot
## entry, not worth a headless test. Also that the horn scares the crossing
## deer off when it's close ahead (N-107).

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

	await _test_horn_scares_deer(bus)

	if _failures == 0:
		print("PASS: the horn attributes correctly to its sender and the synthesized honk is real audio")
	quit(_failures)


## The horn is a tool, not only comedy (tareas de Nacho N-107): a honk with
## the deer close ahead sends it off -- into the trees if it's still on its
## shoulder, across at once if it's frozen in the lane -- and does nothing
## from far away.
func _test_horn_scares_deer(bus: Node) -> void:
	var grazing := _crossing_with_truck(26.0)
	bus.call(&"request_horn")
	_expect(grazing.crossing.state == WildlifeCrossing.State.FLEEING, "A honk 23 m ahead sends the grazing deer off")
	var closest: float = INF
	for tick: int in range(120):
		await physics_frame
		closest = minf(closest, absf(grazing.crossing.deer.position.x))
	_expect(closest > WildlifeCrossing.ROAD_HALF_WIDTH, "Scared off its shoulder, it never steps onto the road (closest %.1f m)" % closest)
	grazing.world.free()

	var frozen := _crossing_with_truck(20.0)
	frozen.crossing.set(&"_lateral", WildlifeCrossing.FREEZE_LATERAL)
	frozen.crossing.state = WildlifeCrossing.State.FROZEN
	bus.call(&"request_horn")
	_expect(frozen.crossing.state == WildlifeCrossing.State.BOLTING, "Frozen in the lane, a honk makes it bolt across at once")
	frozen.world.free()

	var far := _crossing_with_truck(70.0)
	bus.call(&"request_horn")
	_expect(far.crossing.state == WildlifeCrossing.State.WAITING, "From 67 m away the deer doesn't hear it")
	far.world.free()
	await process_frame


## A deer crossing at the origin and a parked truck `distance` metres before
## it on the road (the truck faces -Z, toward the crossing).
func _crossing_with_truck(distance: float) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var crossing := WildlifeCrossing.new()
	world.add_child(crossing)
	var van := (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	van.position = Vector3(-1.5, 0.7, distance)
	world.add_child(van)
	van.freeze = true
	return {"world": world, "crossing": crossing}


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

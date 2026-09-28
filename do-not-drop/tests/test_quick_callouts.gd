extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_quick_callouts.gd
## Covers N-505 (quick callouts, docs/tareas-nacho.md): the ping wheel's eight
## phrases, the host's 1.5 s per-player anti-spam cooldown in
## EventBus.request_ping(), the driver's HUD entry and the phrase texts in
## strings_ui.csv. The call reaching every peer is the same relay() hop as
## test_ping.gd; the real cross-peer delivery is net_trio's job.

var _failures: int = 0
var _received: Array = []
const PingCatalogData = preload("res://scripts/ui/ping_catalog.gd")


func _initialize() -> void:
	await process_frame
	var bus: Node = root.get_node(^"/root/EventBus")
	var network: Node = root.get_node(^"/root/NetworkManager")
	bus.connect(&"ping_sent", func(peer_id: int, _position: Vector3, label: String) -> void:
		_received.append([peer_id, label]))

	# The phrases: 6-8 of them, each with its own translated text.
	var options: Array[Dictionary] = PingCatalogData.OPTIONS
	_expect(options.size() >= 6 and options.size() <= 8, "The wheel has 6-8 phrases")
	var labels: Array[String] = []
	for option: Dictionary in options:
		labels.append(String(option["label"]))
	for wanted: String in ["¡Frená!", "¡Bache!", "¡Ayuda acá!", "¡Se cae!", "Tengo la cinta", "Esperá", "¡Dale, dale!"]:
		_expect(wanted in labels, "The wheel offers '%s'" % wanted)
	for option: Dictionary in options:
		var key: String = String(option["key"])
		_expect(TranslationServer.translate(key) != key, "%s has a text in strings_ui.csv" % key)
	_expect(PingCatalogData.option("¡Frená!")["key"] == "CALLOUT_BRAKE", "Labels map back to their phrase")

	# Cooldown: the second callout within 1.5 s is dropped, a later one passes.
	bus.call(&"reset_ping_cooldowns")
	_expect(is_equal_approx(float(bus.get(&"ping_cooldown_seconds")), 1.5), "Cooldown is 1.5 s per player")
	bus.call(&"request_ping", Vector3.ZERO, "¡Frená!")
	bus.call(&"request_ping", Vector3.ZERO, "¡Bache!")
	bus.call(&"request_ping", Vector3.ZERO, "¡Se cae!")
	_expect(_received.size() == 1, "Spamming the wheel only lets the first callout through")
	if not _received.is_empty():
		_expect(int(_received[0][0]) == int(network.call(&"local_id")) and String(_received[0][1]) == "¡Frená!",
			"The accepted callout reaches EventBus with its sender and phrase")
	# Wall clock, not create_timer(): run-tests.sh may run the tree faster than real time.
	OS.delay_msec(1600)
	bus.call(&"request_ping", Vector3.ZERO, "Esperá")
	_expect(_received.size() == 2, "Once the cooldown is over the next callout goes through")

	# The driver's HUD: a crewmate's callout goes big in the middle of the screen.
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	var fake_vehicle_script := GDScript.new()
	fake_vehicle_script.source_code = "extends Node\nvar driver_peer_id: int = 0\n"
	fake_vehicle_script.reload()
	var vehicle: Node = fake_vehicle_script.new()
	vehicle.add_to_group(&"vehicle")
	root.add_child(vehicle)
	var brake_text: String = PingCatalogData.display_text("¡Frená!")

	bus.emit_signal(&"ping_sent", 7, Vector3.ZERO, "¡Frená!")
	_expect(hud.ping_indicator.text == "", "A passenger doesn't get the driver's big callout line")
	vehicle.set(&"driver_peer_id", int(network.call(&"local_id")))
	bus.emit_signal(&"ping_sent", 7, Vector3.ZERO, "¡Frená!")
	_expect(hud.ping_indicator.text.contains(brake_text), "The driver sees a crewmate's callout on their HUD")
	bus.emit_signal(&"ping_sent", int(network.call(&"local_id")), Vector3.ZERO, "¡Frená!")
	_expect(hud.ping_indicator.text == "", "The driver's own callout doesn't echo back at them")

	vehicle.free()
	hud.free()
	bus.call(&"reset_ping_cooldowns")
	if _failures == 0:
		print("PASS: quick callouts rate-limit per player and reach the driver's HUD")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/acoustics/tests/test_acoustics.gd
##
## The acoustics module on its own (docs/modulos.md): an AcousticZone covers
## the points inside its box and joins the group AcousticSpace scans;
## listening_space() names the zone the point is in or "open"; apply()
## adds one reverb effect per configured bus at runtime, switches it on for
## a known space with that space's settings, and off again in the open.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var zone := AcousticZone.new()
	zone.size = Vector3(4.0, 3.0, 20.0)
	zone.acoustic_space = &"tunnel"
	zone.position = Vector3(0.0, 0.0, -50.0)
	root.add_child(zone)
	await process_frame
	_expect(zone.is_in_group(AcousticSpace.GROUP), "A zone joins the acoustic_space group")
	_expect(zone.covers(Vector3(1.0, 1.0, -55.0)), "A point inside the box is covered")
	_expect(not zone.covers(Vector3(3.0, 1.0, -55.0)), "A point beside the box is not")
	_expect(AcousticSpace.listening_space(self, Vector3(0.0, 1.0, -45.0)) == &"tunnel",
		"Inside the zone the listener is in a tunnel")
	_expect(AcousticSpace.listening_space(self, Vector3(0.0, 1.0, -30.0)) == &"open",
		"Past its end they're in the open")
	_expect(AcousticSpace.listening_space(null, Vector3.ZERO) == &"open", "No tree, no space")

	# A bare project only has Master: the buses are configuration.
	AcousticSpace.buses = [&"Master"]
	var master: int = AudioServer.get_bus_index(&"Master")
	var effects_before: int = AudioServer.get_bus_effect_count(master)
	AcousticSpace.apply(&"tunnel")
	_expect(AudioServer.get_bus_effect_count(master) == effects_before + 1,
		"One reverb effect is added to the bus, once")
	_expect(AcousticSpace.is_on(), "In a tunnel the reverb is on")
	var reverb: AudioEffectReverb = null
	for index: int in range(AudioServer.get_bus_effect_count(master)):
		var effect: AudioEffect = AudioServer.get_bus_effect(master, index)
		if effect is AudioEffectReverb and effect.resource_name == AcousticSpace.EFFECT_NAME:
			reverb = effect
	_expect(reverb != null and is_equal_approx(reverb.room_size, float(AcousticSpace.spaces[&"tunnel"][0])),
		"The reverb takes the space's room size")
	AcousticSpace.apply(&"tunnel")
	_expect(AudioServer.get_bus_effect_count(master) == effects_before + 1,
		"Applying the same space again adds nothing")
	AcousticSpace.apply(&"open")
	_expect(not AcousticSpace.is_on(), "In the open the reverb is off")
	AcousticSpace.spaces[&"cave"] = [0.5, 0.5, 0.5, 10.0]
	AcousticSpace.apply(&"cave")
	_expect(AcousticSpace.is_on() and is_equal_approx(reverb.room_size, 0.5),
		"A space added by the game works like the defaults")
	zone.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: acoustic zones are found by point and switch the bus reverb")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

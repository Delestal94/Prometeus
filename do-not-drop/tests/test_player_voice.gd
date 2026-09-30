extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_player_voice.gd
## Covers S-402 (wordless voices, docs/tareas-nacho.md), player_voice.gd:
## - every player gets a PlayerVoice head-height speaker on the "Voice" bus, the
##   one GameSettings' "Voces" slider drives;
## - each trigger produces a line: a hit (the flinch), a ragdoll (which voices
##   only the ragdoll, not the yelp too), an intact delivery of the box the
##   player held or tended (and nobody else's), your own box ruined (and not a
##   crewmate's);
## - pitch follows the colour slot, so two crewmates never sound alike;
## - the cooldown stops a pile of hits from machine-gunning;
## - the ping wheel's babble (hud_notices.gd) now goes to the Voice bus too.
## The signals are wired to EventBus (checked with is_connected); the handlers
## are called directly, because emitting package_ruined / house_delivery_recorded
## for real would also run RunManager's bookkeeping.

const PingCatalogData = preload("res://scripts/ui/ping_catalog.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var bus: Node = root.get_node(^"/root/EventBus")
	var settings: Node = root.get_node(^"/root/GameSettings")

	_expect(AudioServer.get_bus_index(&"Voice") >= 0, "The project has a Voice bus")

	# A real player: the component exists for everyone, head high, on Voice.
	var real: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	root.add_child(real)
	await process_frame
	var real_voice: Node = real.get_node_or_null(^"PlayerVoice")
	_expect(real_voice != null, "Every player builds a PlayerVoice")
	if real_voice != null:
		_expect(is_equal_approx(real_voice.position.y, 1.7), "The voice comes from head height")
		_expect((real_voice.get(&"voice") as AudioStreamPlayer3D).bus == &"Voice", "The voice plays on the Voice bus")
		real.set(&"_flinch_time", 0.32)
		real_voice.call(&"_process", 0.0)
		_expect(real_voice.get(&"last_line") == &"hurt", "A real player's flinch makes it yelp")
	real.free()

	# Two crewmates (stand-ins with the properties the component observes).
	var fake_script := GDScript.new()
	fake_script.source_code = "extends Node3D\nvar _flinch_time: float = 0.0\nvar _ragdolled: bool = false\n" \
		+ "var carried_package: Variant = null\nvar tended_package: Variant = null\n"
	fake_script.reload()
	var mia: Node3D = fake_script.new()
	mia.set_multiplayer_authority(2)
	var leo: Node3D = fake_script.new()
	leo.set_multiplayer_authority(3)
	root.add_child(mia)
	root.add_child(leo)
	# Loaded at run time: it names Player, whose script needs the autoloads.
	var voice_script: GDScript = load("res://scripts/gameplay/player/player_voice.gd")
	var mia_voice: Node3D = voice_script.new()
	var leo_voice: Node3D = voice_script.new()
	mia.add_child(mia_voice)
	leo.add_child(leo_voice)
	_expect(mia_voice.name == &"PlayerVoice", "The component names itself")
	var mia_speaker: AudioStreamPlayer3D = mia_voice.get(&"voice")
	var leo_speaker: AudioStreamPlayer3D = leo_voice.get(&"voice")
	_expect(mia_speaker.max_distance >= 40.0 and mia_speaker.unit_size >= 6.0,
		"The voice carries across the van and the street")
	_expect(bus.is_connected(&"package_ruined", Callable(mia_voice, &"_on_package_ruined")),
		"It listens to package_ruined")
	_expect(bus.is_connected(&"house_delivery_recorded", Callable(mia_voice, &"_on_house_delivery_recorded")),
		"It listens to house_delivery_recorded")

	# Hurt: the flinch rising, once, on the Voice bus, in the player's slot.
	mia.set(&"_flinch_time", 0.32)
	mia_voice.call(&"_process", 0.0)
	_expect(mia_voice.get(&"last_line") == &"hurt" and mia_speaker.playing, "A hit makes the player yelp")
	_expect(mia_speaker.stream == SynthAudio.callout_voice(2, 2), "The yelp is the player's own colour voice")
	_expect(mia_speaker.bus == &"Voice", "The yelp is on the Voice bus")
	_expect(leo_voice.get(&"last_line") == &"", "Only the player who was hit yelps")

	# Pitch differs between colour slots, and the two voices are different sounds.
	leo.set(&"_flinch_time", 0.32)
	leo_voice.call(&"_process", 0.0)
	_expect(leo_speaker.stream != mia_speaker.stream and leo_speaker.stream.data != mia_speaker.stream.data,
		"Two colour slots have different voices")
	_expect(mia_voice.get(&"slot") != leo_voice.get(&"slot"), "Peers 2 and 3 sit in different colour slots")

	# Cooldown: a second hit right after the first is dropped, a later one is not.
	_expect(mia_voice.call(&"speak", &"hurt") == false, "A pile of hits doesn't machine-gun the voice")
	mia_voice.set(&"_cooldown_until", Time.get_ticks_msec() - 1)
	_expect(mia_voice.call(&"speak", &"hurt") == true, "Once the cooldown is over the voice speaks again")
	_expect(mia_voice.call(&"speak", &"gibberish") == false, "An unknown line is ignored")

	# Ragdoll: a longer wail, and the same hit doesn't also yelp.
	_reset(mia_voice)
	mia.set(&"_flinch_time", 0.32)
	mia.set(&"_ragdolled", true)
	mia_voice.call(&"_process", 0.0)
	_expect(mia_voice.get(&"last_line") == &"ragdoll", "Being bowled over makes the player wail, not just yelp")
	_expect(mia_speaker.stream == SynthAudio.callout_voice(2, 4), "The ragdoll wail is longer than the hurt yelp")
	_expect(mia_speaker.stream.get_length() > SynthAudio.callout_voice(2, 2).get_length(), "Longer, in seconds")
	mia.set(&"_ragdolled", false)
	mia.set(&"_flinch_time", 0.0)
	mia_voice.call(&"_process", 0.0)

	# Intact delivery: the player who held the box cheers, the crewmate doesn't.
	var box: Node3D = _box(&"box_ok", 0)
	mia.set(&"carried_package", box)
	mia_voice.call(&"_process", 0.0)
	mia.set(&"carried_package", null)  # the door took it out of their hands
	_reset(mia_voice)
	_reset(leo_voice)
	mia_voice.call(&"_on_house_delivery_recorded", 4, &"delivered_ok", &"box_ok")
	leo_voice.call(&"_on_house_delivery_recorded", 4, &"delivered_ok", &"box_ok")
	_expect(mia_voice.get(&"last_line") == &"cheer" and mia_speaker.playing, "The player who brought it cheers")
	_expect(leo_voice.get(&"last_line") == &"", "A crewmate who didn't hold the box stays quiet")
	_expect(mia_speaker.bus == &"Voice", "The cheer is on the Voice bus")
	_reset(mia_voice)
	mia_voice.call(&"_on_house_delivery_recorded", 4, &"delivered_at_risk", &"box_ok")
	mia_voice.call(&"_on_house_delivery_recorded", 4, &"delivered_ruined", &"box_ok")
	_expect(mia_voice.get(&"last_line") == &"", "Only an intact delivery cheers")
	mia_voice.set(&"_box_seen_at", Time.get_ticks_msec() - 60000)
	mia_voice.call(&"_on_house_delivery_recorded", 4, &"delivered_ok", &"box_ok")
	_expect(mia_voice.get(&"last_line") == &"", "A box that left their hands long ago isn't theirs to cheer")

	# Own box ruined: carried, or tended from a seat; never a crewmate's.
	var mine: Node3D = _box(&"box_mine", 0)
	var his: Node3D = _box(&"box_his", 3)
	mia.set(&"carried_package", mine)
	_reset(mia_voice)
	_reset(leo_voice)
	mia_voice.call(&"_on_package_ruined", &"box_mine", "test")
	leo_voice.call(&"_on_package_ruined", &"box_mine", "test")
	_expect(mia_voice.get(&"last_line") == &"ruined" and mia_speaker.playing, "Your own ruined box makes you groan")
	_expect(leo_voice.get(&"last_line") == &"", "Somebody else's ruined box doesn't")
	_reset(mia_voice)
	mia_voice.call(&"_on_package_ruined", &"box_his", "test")
	_expect(mia_voice.get(&"last_line") == &"", "A crewmate's ruined box isn't yours to mourn")
	leo_voice.call(&"_on_package_ruined", &"box_his", "test")
	_expect(leo_voice.get(&"last_line") == &"ruined", "The box at your seat (tender_peer_id) counts as your own")
	_expect(mia_speaker.bus == &"Voice" and leo_speaker.bus == &"Voice", "Every line is on the Voice bus")

	# "Voces" reaches the bus the voices play on.
	var voice_bus: int = AudioServer.get_bus_index(&"Voice")
	settings.set(&"voice_volume", 0.5)
	_expect(is_equal_approx(AudioServer.get_bus_volume_db(voice_bus), linear_to_db(0.5)),
		"The Voces slider writes to the Voice bus")
	_expect(AudioServer.get_bus_index(mia_speaker.bus) == voice_bus, "The voice plays on that same bus")
	settings.set(&"voice_volume", 0.0)
	_expect(AudioServer.get_bus_volume_db(voice_bus) < -60.0, "Voces at zero silences every player's voice")
	settings.set(&"voice_volume", 1.0)

	# The synthesized lines are real audio.
	for syllables: int in [2, 3, 4]:
		var stream: AudioStreamWAV = SynthAudio.callout_voice(2, syllables)
		var peak: int = 0
		for i: int in range(0, stream.data.size() - 1, 2):
			peak = maxi(peak, absi(stream.data.decode_s16(i)))
		_expect(peak > 1000, "The %d-syllable line is not silence" % syllables)

	# Pings: the wheel's babble is on the Voice bus now, from the caller's head.
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	var crewmate := Node3D.new()
	crewmate.set_multiplayer_authority(7)
	crewmate.add_to_group(&"player")
	root.add_child(crewmate)
	bus.emit_signal(&"ping_sent", 7, Vector3.ZERO, "Esperá")
	var ping_voice: Node = crewmate.get_node_or_null(^"CalloutVoice")
	_expect(ping_voice is AudioStreamPlayer3D and (ping_voice as AudioStreamPlayer3D).bus == &"Voice",
		"A crewmate's ping babbles on the Voice bus")
	var local_id: int = int(root.get_node(^"/root/NetworkManager").call(&"local_id"))
	bus.emit_signal(&"ping_sent", local_id, Vector3.ZERO, "¡Frená!")
	var flat: Array[Node] = hud.find_children("CalloutVoice", "AudioStreamPlayer", true, false)
	_expect(not flat.is_empty() and (flat[0] as AudioStreamPlayer).bus == &"Voice",
		"Your own ping babbles on the Voice bus too")
	_expect(PingCatalogData.syllables("Esperá") == 3, "The ping still has its per-phrase syllables")

	crewmate.free()
	hud.free()
	for node: Node in [box, mine, his, mia, leo]:
		node.free()
	if _failures == 0:
		print("PASS: players babble on the Voice bus for hits, ragdolls, intact deliveries and their own ruined boxes")
	quit(_failures)


func _box(id: StringName, tender: int) -> Node3D:
	var package = load("res://scenes/gameplay/package/package.tscn").instantiate()
	package.package_id = id
	root.add_child(package)
	package.add_to_group(&"cargo")
	package.tender_peer_id = tender
	return package


func _reset(component: Node) -> void:
	component.set(&"_cooldown_until", 0)
	component.set(&"last_line", &"")
	(component.get(&"voice") as AudioStreamPlayer3D).stop()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_sound_check.gd
##
## "Sonidos del juego" (playtest 2026-09-25: a noise nobody could name):
## - presentation/sound_audit.gd lists every sound by who plays it and what,
##   so the forklift's engine and the truck's are told apart though they're
##   the same synthesized loop;
## - muting swaps in a silent copy of the same length and loop, the player
##   keeps playing, and unmuting brings the real sound back; "Solo" mutes
##   everything else;
## - a mute reaches players that appear later (a reloaded level);
## - while the list is open, the sounds play through the pause;
## - the options screen opens the list (ui/sound_check_panel.gd).

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var audit: Script = load("res://scripts/presentation/sound_audit.gd")
	var world := Node.new()
	world.name = "World"
	root.add_child(world)
	var forklift_engine: AudioStreamPlayer = _player(world, "Forklift", SynthAudio.engine_loop())
	var truck_engine: AudioStreamPlayer = _player(world, "Truck", SynthAudio.engine_loop())
	var radio: AudioStreamPlayer = _player(world, "Depot", SynthAudio.radio_tune())
	await process_frame

	var labels: Array = audit.groups(self).map(func(group: Dictionary) -> String: return group.label)
	_expect(labels.has("Forklift · Motor") and labels.has("Truck · Motor") and labels.has("Depot · Radio"),
		"Each sound is listed by who plays it and what (got %s)" % str(labels))

	var forklift_key: String = audit.key_of(forklift_engine)
	audit.set_muted(self, forklift_key, true)
	var silent := forklift_engine.stream as AudioStreamWAV
	_expect(silent != SynthAudio.engine_loop() and silent.data.size() == SynthAudio.engine_loop().data.size()
		and silent.loop_mode == SynthAudio.engine_loop().loop_mode and _all_zero(silent.data),
		"Muted, the forklift's engine plays a silent copy of the same length and loop")
	_expect(forklift_engine.playing, "...and keeps playing, so nothing restarts it by surprise")
	_expect(truck_engine.stream == SynthAudio.engine_loop(), "The truck's engine, the same loop, is left alone")

	var late: AudioStreamPlayer = _player(world, "Forklift", SynthAudio.engine_loop(), "LateEngine")
	for i: int in range(30):
		await create_timer(0.05).timeout
		if late.stream != SynthAudio.engine_loop():
			break
	_expect(late.stream != SynthAudio.engine_loop(), "A player that appears later is muted too (a reloaded level)")

	audit.solo(self, audit.key_of(radio))
	_expect(radio.stream == SynthAudio.radio_tune() and truck_engine.stream != SynthAudio.engine_loop()
		and forklift_engine.stream != SynthAudio.engine_loop(), "Solo: only the depot's radio is heard")

	audit.unmute_all(self)
	_expect(forklift_engine.stream == SynthAudio.engine_loop() and truck_engine.stream == SynthAudio.engine_loop()
		and radio.stream == SynthAudio.radio_tune() and late.stream == SynthAudio.engine_loop(),
		"Unmuting brings every real sound back")
	_expect(forklift_engine.playing, "...still playing")

	audit.play_through_pause(self, true)
	_expect(radio.process_mode == Node.PROCESS_MODE_ALWAYS, "With the list open, sounds play through the pause")
	audit.play_through_pause(self, false)
	_expect(radio.process_mode == Node.PROCESS_MODE_INHERIT, "...and go back to pausing with the game once it's closed")

	# --- the options screen opens it ---
	var options: Control = load("res://scripts/ui/options_panel.gd").new()
	root.add_child(options)
	await process_frame
	options.call(&"open")
	var opener: Button = null
	for node: Node in options.find_children("*", "Button", true, false):
		if (node as Button).text.begins_with("Sonidos del juego"):
			opener = node
	_expect(opener != null, "The options screen has a button for the sounds, one by one")
	if opener != null:
		opener.pressed.emit()
		await process_frame
		var panel: Control = options.get_node_or_null(^"SoundCheck")
		_expect(panel != null and panel.visible, "It opens the list of sounds")
		if panel != null:
			var boxes: int = 0
			for node: Node in panel.find_children("*", "CheckBox", true, false):
				if (node as CheckBox).text == "Silenciar":
					boxes += 1
			_expect(boxes == audit.groups(self).size(), "One row with a mute toggle per sound (%d rows, %d sounds)" % [boxes, audit.groups(self).size()])
		options.call(&"close")
		_expect(panel == null or not panel.visible, "Closing the options closes the list too")
	options.queue_free()

	audit.unmute_all(self)
	world.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: every sound can be found, muted, soloed and brought back, from the options screen")
	quit(_failures)


func _player(world: Node, owner_name: String, stream: AudioStream, player_name: String = "Sound") -> AudioStreamPlayer:
	var owner_node: Node = world.get_node_or_null(owner_name)
	if owner_node == null:
		owner_node = Node.new()
		owner_node.name = owner_name
		world.add_child(owner_node)
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	owner_node.add_child(player)
	player.play()
	return player


static func _all_zero(data: PackedByteArray) -> bool:
	for byte: int in data:
		if byte != 0:
			return false
	return true


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

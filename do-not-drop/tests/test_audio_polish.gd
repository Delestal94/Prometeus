extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_audio_polish.gd
## "Cartoon cómico" audio polish pass (2026-09-27): a handful of world sounds
## were reusing another sound's clip as a stand-in, which read as no sound
## having been designed for the moment at all --
##   - the doorbell rang with Frágil's own glass chime (a delivery sounded
##     like a box breaking);
##   - a happy resident cheered with the truck's own horn (a good delivery
##     sounded like someone honking at the door);
##   - the depot's electric forklift shared the diesel truck's own engine
##     loop, just pitched -- the same vehicle sound twice;
##   - every trap but Frágil had no sound at all for the moment it actually
##     failed, only the tint and the confetti.
## Each now has its own cue (synth_audio.gd); this checks they're wired in
## and are genuinely their own clip, not the old stand-in still playing.

const SynthAudio = preload("res://scripts/presentation/synth_audio.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_doorbell_and_cheer()
	_test_forklift_motor()
	await _test_ruin_stinger()
	if _failures == 0:
		print("PASS: doorbell, resident cheer, forklift motor and every trap's ruin stinger are their own sounds, not reused stand-ins")
	quit(_failures)


func _test_doorbell_and_cheer() -> void:
	var house: Node3D = load("res://scripts/gameplay/route/delivery_house.gd").new()
	root.add_child(house)
	await process_frame
	var bell: AudioStreamPlayer3D = house.get(&"_bell_player")
	_expect(bell.stream == SynthAudio.doorbell_ding_dong() and bell.stream != SynthAudio.glass_chime(),
		"The doorbell rings its own ding-dong, not Fragil's glass chime")

	house.call(&"_resolve", DeliveryHouse.OUTCOME_OK, null)
	var reaction: AudioStreamPlayer3D = house.get(&"_reaction_player")
	_expect(reaction.stream == SynthAudio.neighbor_cheer() and reaction.stream != SynthAudio.honk_horn(),
		"A happy resident cheers with their own sound, not the truck's horn")
	_expect(reaction.playing, "...and it actually plays right away")
	house.free()


func _test_forklift_motor() -> void:
	var forklift: AnimatableBody3D = load("res://scripts/gameplay/depot/depot_forklift.gd").new()
	root.add_child(forklift)
	var engine: AudioStreamPlayer3D = forklift.get(&"_engine")
	_expect(engine != null, "The forklift builds its motor player right on add_child()")
	if engine == null:
		forklift.free()
		return
	_expect(engine.stream == SynthAudio.forklift_motor_loop() and engine.stream != SynthAudio.engine_loop(),
		"The electric forklift has its own motor, not the diesel truck's engine loop pitched up")
	forklift.free()


func _test_ruin_stinger() -> void:
	# A plain box (no declared trap) still gets the generic cartoon fail cue.
	var plain: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	root.add_child(plain)
	await process_frame
	var plain_feedback: Node = plain.get_node(^"PackageFeedbackComponent")
	var plain_ruin: AudioStreamPlayer3D = plain_feedback.get(&"_ruin_player")
	_expect(plain_ruin != null and plain_ruin.stream == SynthAudio.comic_ruin_stinger(),
		"Reaching RUINED gets a cartoon fail stinger by default")
	_expect(not plain_ruin.playing, "...silent until the package actually ruins")
	plain_feedback.call(&"_on_package_ruined", plain.get(&"package_id"), "test")
	_expect(plain_ruin.playing, "...and plays once it does")
	plain.free()

	# Explosivo gets its own "BOOM." instead (explosive_trap_behavior.gd's
	# get_hint() literally says that once the timer runs out).
	var bomb: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	bomb.set(&"trap_definition", load("res://data/traps/explosive.tres"))
	root.add_child(bomb)
	await process_frame
	var bomb_feedback: Node = bomb.get_node(^"PackageFeedbackComponent")
	var bomb_ruin: AudioStreamPlayer3D = bomb_feedback.get(&"_ruin_player")
	_expect(bomb_ruin != null and bomb_ruin.stream == SynthAudio.comic_boom() and bomb_ruin.stream != SynthAudio.comic_ruin_stinger(),
		"Explosivo booms instead of the generic stinger when it runs out")
	bomb_feedback.call(&"_on_package_ruined", bomb.get(&"package_id"), "test")
	_expect(bomb_ruin.playing, "...and it plays too")
	bomb.free()
	await create_timer(0.05).timeout


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_trap_audio.gd
## Covers item #43 of docs/especificaciones-visuales.md: each trap now has an
## audible cue of its own (a chime for Frágil, a groan for Ruidoso, a creak
## for Peso Creciente) instead of only the HUD saying anything's wrong.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	_test_fragile_chime()
	await _test_noisy_groan()
	await _test_growing_weight_creak()
	if _failures == 0:
		print("PASS: each trap has its own audible cue (chime, groan, creak)")
	quit(_failures)


func _test_fragile_chime() -> void:
	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	root.add_child(package)
	await process_frame
	var feedback: Node = package.get_node(^"PackageFeedbackComponent")
	var chime: AudioStreamPlayer3D = feedback.get(&"_chime_player")
	_expect(chime != null, "Frágil gets a chime player")
	_expect(not chime.playing, "Silent while intact")

	var package_id: StringName = package.get(&"package_id")
	feedback.call(&"_on_package_state_changed", package_id, 1)  # AT_RISK
	_expect(chime.playing, "Entering AT_RISK plays the chime")
	var at_risk_pitch: float = chime.pitch_scale
	chime.stop()
	feedback.call(&"_on_package_state_changed", package_id, 2)  # RUINED
	_expect(chime.playing and chime.pitch_scale < at_risk_pitch,
		"RUINED plays the same chime pitched down, so it reads as worse than AT_RISK")
	package.free()


func _test_noisy_groan() -> void:
	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	package.set(&"trap_definition", load("res://data/traps/noisy.tres"))
	root.add_child(package)
	await process_frame
	var feedback: Node = package.get_node(^"PackageFeedbackComponent")
	var groan: AudioStreamPlayer3D = feedback.get(&"_groan_player")
	_expect(groan != null, "Ruidoso gets a groan player")

	feedback.call(&"_process", 1.0 / 60.0)
	_expect(not groan.playing, "Calm box doesn't moan in the background")

	var package_id: StringName = package.get(&"package_id")
	feedback.call(&"_on_integrity_changed", package_id, 20.0, 100.0)  # agitated
	feedback.call(&"_process", 1.0 / 60.0)
	_expect(groan.playing, "Agitation starts the groan")
	var agitated_db: float = groan.volume_db

	feedback.call(&"_on_integrity_changed", package_id, 90.0, 100.0)  # calmer
	feedback.call(&"_process", 1.0 / 60.0)
	_expect(groan.volume_db < agitated_db, "Calming down brings the groan back down, not just the visuals")

	feedback.call(&"_on_integrity_changed", package_id, 100.0, 100.0)  # fully calm
	feedback.call(&"_process", 1.0 / 60.0)
	_expect(not groan.playing, "Fully calm stops the groan entirely")
	package.free()
	await create_timer(0.05).timeout


func _test_growing_weight_creak() -> void:
	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	package.set(&"trap_definition", load("res://data/traps/growing_weight.tres"))
	root.add_child(package)
	await process_frame
	var feedback: Node = package.get_node(^"PackageFeedbackComponent")
	var creak: AudioStreamPlayer3D = feedback.get(&"_creak_player")
	_expect(creak != null, "Peso Creciente gets a creak player")

	var package_id: StringName = package.get(&"package_id")
	feedback.call(&"_on_integrity_changed", package_id, 20.0, 100.0)  # heavy distress: frequent creaks
	# The very first creak still waits out the full CREAK_INTERVAL_MAX (it's
	# a countdown that starts at the max and only shortens afterward, so a
	# box that just started struggling doesn't creak instantly) -- budget
	# comfortably past that, not just past the shortened interval.
	var creaked: bool = false
	for _i: int in range(320):  # ~5.3s of frames
		feedback.call(&"_process", 1.0 / 60.0)
		if creak.playing:
			creaked = true
			break
	_expect(creaked, "A heavy box creaks on its own within a few seconds, not only when it fails")

	feedback.call(&"_on_integrity_changed", package_id, 100.0, 100.0)  # solved, no distress
	feedback.call(&"_process", 1.0 / 60.0)
	var countdown_after_calm: float = float(feedback.get(&"_creak_countdown"))
	_expect(countdown_after_calm > 3.0,
		"Solving the puzzle resets the creak schedule (back near the max interval) instead of leaving a short fuse armed")
	package.free()
	await create_timer(0.05).timeout


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

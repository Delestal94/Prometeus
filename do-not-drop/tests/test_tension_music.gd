extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_tension_music.gd
## The in-game music's tension layer (docs/tareas-nacho.md #22/#84): silent
## while the cargo is fine, swelling with damage and at-risk boxes, and not
## stuck at full dread over a box that's already ruined.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var music_script: Script = load("res://scripts/presentation/ingame_music.gd")
	var fine := {&"a": {"integrity": 100.0, "maximum": 100.0, "state": 0}}
	var dented := {&"a": {"integrity": 70.0, "maximum": 100.0, "state": 0}}
	var at_risk := {&"a": {"integrity": 40.0, "maximum": 100.0, "state": 1}}
	var ruined := {&"a": {"integrity": 0.0, "maximum": 100.0, "state": 2}}
	_expect(music_script.cargo_risk({}) == 0.0, "No cargo, no tension")
	_expect(music_script.cargo_risk(fine) == 0.0, "Intact cargo is calm")
	var partial: float = music_script.cargo_risk(dented)
	_expect(partial > 0.2 and partial < 0.8, "Damage raises tension part of the way (%.2f)" % partial)
	_expect(music_script.cargo_risk(at_risk) == 1.0, "A box at risk is full tension")
	_expect(music_script.cargo_risk(ruined) == 0.0, "A box already ruined doesn't hold the tension up")

	var manager: Node = root.get_node(^"/root/RunManager")
	var music: AudioStreamPlayer = music_script.new()
	root.add_child(music)
	await process_frame
	var layer: AudioStreamPlayer = music.get_node(^"TensionLayer")
	_expect(layer.playing and layer.volume_db <= -59.0, "The layer runs silently while calm")
	manager.set(&"is_running", true)
	manager.set(&"cargo", at_risk.duplicate(true))
	for _i: int in range(150):
		await process_frame
	_expect(layer.volume_db > -20.0 and music.pitch_scale > 1.0, "It swells once a box is at risk (%.1f dB)" % layer.volume_db)
	manager.call(&"reset_run")
	music.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: the tension layer follows the cargo's trouble, and lets go of what's already lost")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

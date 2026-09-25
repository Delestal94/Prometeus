extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_tension_music.gd
## The in-game music's tension layer (docs/tareas-nacho.md #22/#84): silent
## while the cargo is fine or merely dented, gently swelling for at-risk boxes.
## Music leaves breathing room between tracks and never changes tuning.

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
	_expect(music_script.cargo_risk(dented) == 0.0, "Old dents don't keep a drone going for the rest of the trip")
	_expect(music_script.cargo_risk(at_risk) == 1.0, "A box at risk is full tension")
	_expect(music_script.cargo_risk(ruined) == 0.0, "A box already ruined doesn't hold the tension up")

	var manager: Node = root.get_node(^"/root/RunManager")
	var music: AudioStreamPlayer = music_script.new()
	root.add_child(music)
	music.set_process(false)  # Advance presentation time explicitly, independent of headless FPS.
	var layer: AudioStreamPlayer = music.get_node(^"TensionLayer")
	_expect(layer.playing and layer.volume_db <= -59.0, "The layer runs silently while calm")
	_expect(music.bus == &"Music" and layer.bus == &"Music", "Both layers respect the music volume setting")
	_expect(not music.playing, "The world is heard first when entering the level")
	_expect(not (music.stream as AudioStreamOggVorbis).loop, "The song can finish instead of looping forever")
	music.call(&"_process", 17.0)
	_expect(not music.playing, "The first pause lasts at least 18 seconds")
	music.call(&"_process", 19.0)
	_expect(music.playing and music.volume_db <= -79.0, "The first track starts quietly within 35 seconds")
	music.call(&"_process", 2.5)
	var half_fade: float = music.volume_db
	_expect(half_fade > -60.0 and half_fade < -17.0, "The song fades in gradually")
	music.call(&"_process", 2.5)
	_expect(music.volume_db > half_fade and music.volume_db <= -14.0, "The fade reaches its modest full level")
	var remaining: float = music.stream.get_length() - 5.0
	music.call(&"_process", remaining - 3.5)
	_expect(music.volume_db < -17.0, "The song fades down before its end")
	music.stop()
	music.finished.emit()  # Exercise the actual end-of-track connection.
	music.call(&"_process", 44.0)
	_expect(not music.playing, "A finished song leaves at least 45 seconds for the environment")
	music.call(&"_process", 42.0)
	_expect(music.playing and music.volume_db <= -79.0, "Music returns quietly within 85 seconds")
	manager.set(&"is_running", true)
	manager.set(&"cargo", at_risk.duplicate(true))
	music.call(&"_process", 0.1)
	_expect(layer.volume_db < -40.0, "Danger does not cause an abrupt loud heartbeat")
	music.call(&"_process", 4.0)
	_expect(layer.volume_db > -30.0 and layer.volume_db <= -22.9, "Risk is audible but restrained (%.1f dB)" % layer.volume_db)
	_expect(music.pitch_scale == 1.0, "Danger never detunes the music")
	manager.set(&"cargo", ruined.duplicate(true))
	music.call(&"_process", 1.0)
	_expect(layer.volume_db > -59.0 and layer.volume_db < -23.0, "Tension fades away instead of cutting off")
	music.call(&"_process", 5.0)
	_expect(layer.volume_db <= -59.0, "A ruined box returns to calm")
	manager.set(&"cargo", at_risk.duplicate(true))
	manager.set(&"is_running", false)
	music.call(&"_process", 5.0)
	_expect(layer.volume_db <= -59.0, "Results and preparation do not raise tension")
	manager.call(&"reset_run")
	music.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: music breathes between tracks, fades gently and keeps stable tuning during danger")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

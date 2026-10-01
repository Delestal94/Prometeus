extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_proximity_voice_playback.gd
##
## Proximity voice playback (N-212.2), proximity_voice.gd on the net_session
## module's VoicePlayback. Steam is a fake; players, seats and the truck are
## stand-ins with what the adapter reads (group, authority, Head,
## seat_node_path, net_in_vehicle, a SeatCamera in the truck):
## - a crewmate's packet ends up in a "VoiceChat" playback hung on *their*
##   player and heard from their head; nobody else gets one, and a peer with
##   no player yet gets none;
## - both in the truck (this peer looks through a seat camera, the speaker sits
##   in a seat): Interior bus, no distance attenuation, heard from their seat;
## - otherwise Exterior with 3D attenuation (gone by 30 m), muffled when one is
##   aboard the truck and the other not (standing in the cargo bay counts as
##   aboard), clear when both are outside;
## - muted, at volume 0 or with voice switched off it goes silent at once, even
##   mid-phrase; the "Voces" slider scales it;
## - a flood of packets never buffers more than the latency cap;
## - a crewmate who leaves (peer_removed), a peer that disconnects and a
##   session that ends free their playbacks; one that fails (the host is gone,
##   session_failed, no roster change) frees them and forgets mutes and
##   volumes; a player respawned in the same frame gets the voice, not the
##   one going away;
## - the sound list (sound_audit.gd) names it "Voz de compañero · Voz", its
##   mute holds through a change of how it carries, and unmuting restores it.

# The fake mirrors GodotSteam's camelCase API, so its names can't be snake_case.
# gdlint: disable=function-name
class FakeSteam extends Object:
	## 40 ms of a quiet tone at 24 kHz, 16-bit mono.
	var pcm := PackedByteArray()

	func _init() -> void:
		pcm.resize(960 * 2)
		for index: int in 960:
			pcm.encode_s16(index * 2, int(sin(index * 0.07) * 2500.0))

	func startVoiceRecording() -> void:
		pass

	func stopVoiceRecording() -> void:
		pass

	func getVoiceOptimalSampleRate() -> int:
		return 24000

	func decompressVoice(_voice: PackedByteArray, _rate: int) -> Dictionary:
		return {"result": 0, "size": pcm.size(), "uncompressed": pcm}
# gdlint: enable=function-name

var _packet := PackedByteArray([7, 7, 7, 7])
var _failures: int = 0
var _crew_script := GDScript.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: Node = root.get_node(^"/root/GameSettings")
	var network: Node = root.get_node(^"/root/NetworkManager")
	var voice: Node = root.get_node(^"/root/ProximityVoice")
	var fake := FakeSteam.new()
	var original_enabled: bool = settings.voice_chat_enabled
	var original_volume: float = settings.voice_volume
	voice.backend = fake
	voice.override_steam_session = 1
	settings.voice_chat_enabled = true
	settings.voice_volume = 1.0

	_crew_script.source_code = "extends Node3D\nvar seat_node_path: NodePath = NodePath()\n" \
		+ "var net_in_vehicle: bool = false\n"
	_crew_script.reload()
	var world := Node3D.new()
	world.name = "VoiceWorld"
	root.add_child(world)
	var truck := Node3D.new()
	truck.name = "Truck"
	truck.add_to_group(&"vehicle")
	world.add_child(truck)
	var driver_eye := _marker(truck, "DriverEyePoint", Vector3(0.5, 1.5, 1.2))
	var bay_eye := _marker(truck, "LeftSeat1EyePoint", Vector3(-0.8, 1.4, -1.5))
	var seat_camera := SeatCamera.new()
	driver_eye.add_child(seat_camera)
	var street_camera := Camera3D.new()
	world.add_child(street_camera)
	street_camera.global_position = Vector3(6.0, 1.6, 0.0)
	var mia: Node3D = _crewmate(world, 2, Vector3(12.0, 0.0, 0.0))
	var leo: Node3D = _crewmate(world, 3, Vector3(-9.0, 0.0, 4.0))
	street_camera.current = true
	await process_frame

	_expect(network.peer_removed.is_connected(voice.release_speaker), "A crewmate who leaves releases their voice")
	_expect(network.roster_changed.is_connected(voice._on_roster_changed), "A roster change checks who is still here")

	# --- on foot, this peer in the street: Exterior, from Mia's head ---
	voice.receive_packet(2, _packet)
	var mia_voice: VoicePlayback = voice.speaker(2)
	_expect(mia_voice != null and mia_voice.get_parent() == mia, "Mia's voice hangs on Mia's player")
	_expect(mia.get_node_or_null(^"VoiceChat") == mia_voice, "...named VoiceChat")
	_expect(voice.speaker(3) == null and leo.get_node_or_null(^"VoiceChat") == null, "Leo, silent, gets none")
	if mia_voice == null:
		await _finish(voice, settings, fake, world, original_enabled, original_volume)
		return
	_expect(mia_voice.queued_frames() > 0, "Her packet is queued to play (got %d frames)" % mia_voice.queued_frames())
	mia_voice.advance(0.0)
	var head: Node3D = mia.get_node(^"Head")
	_expect(mia_voice.follow == head and mia_voice.global_position.is_equal_approx(head.global_position),
		"On foot she is heard from her head (at %s)" % mia_voice.global_position)
	_expect(mia_voice.bus == &"Exterior", "Outside it goes to the Exterior bus (got %s)" % mia_voice.bus)
	_expect(mia_voice.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		and mia_voice.max_distance > 0.0 and mia_voice.max_distance <= 30.0,
		"...and fades with distance, gone by 30 m (max %.1f)" % mia_voice.max_distance)
	_expect(not mia_voice.muffled, "Both outside: nothing in between")

	# --- both in the truck: Interior, everyone heard ---
	mia.seat_node_path = bay_eye.get_path()
	seat_camera.current = true
	voice.receive_packet(2, _packet)
	mia_voice.advance(0.0)
	_expect(mia_voice.bus == &"Interior", "Both seated in the truck: Interior bus (got %s)" % mia_voice.bus)
	_expect(mia_voice.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED
		and is_zero_approx(mia_voice.max_distance),
		"...with no distance attenuation")
	_expect(mia_voice.follow == bay_eye and mia_voice.global_position.is_equal_approx(bay_eye.global_position),
		"Seated, she is heard from her seat, not where she sat down (at %s)" % mia_voice.global_position)
	truck.global_position += Vector3(0.0, 0.0, -30.0)
	mia_voice.advance(0.0)
	_expect(mia_voice.global_position.is_equal_approx(bay_eye.global_position), "...and her voice rides with the truck")

	# --- one in, one out: Exterior, muffled through the sheet metal ---
	mia.seat_node_path = NodePath()
	voice._process(0.0)
	_expect(mia_voice.bus == &"Exterior" and mia_voice.muffled, "This peer seated, Mia on foot: muffled outside")
	mia.net_in_vehicle = true
	voice._process(0.0)
	_expect(mia_voice.bus == &"Exterior" and not mia_voice.muffled,
		"This peer seated, Mia standing in the cargo bay: no sheet metal in between")
	mia.net_in_vehicle = false
	mia.seat_node_path = bay_eye.get_path()
	street_camera.current = true
	voice._process(0.0)
	_expect(mia_voice.bus == &"Exterior" and mia_voice.muffled, "This peer on foot, Mia seated: muffled too")
	var me: Node3D = _crewmate(world, root.multiplayer.get_unique_id(), Vector3(0.0, 1.0, -31.0))
	me.net_in_vehicle = true
	voice._process(0.0)
	_expect(not mia_voice.muffled, "This peer standing in the cargo bay, Mia seated: clear")
	me.free()
	mia.seat_node_path = NodePath()
	voice._process(0.0)
	_expect(mia_voice.bus == &"Exterior" and not mia_voice.muffled and mia_voice.follow == head,
		"Both on foot again: clear, from her head")

	# --- mute, volume and the general switch, on the fly ---
	voice.receive_packet(2, _packet)
	voice.receive_packet(2, _packet)
	_expect(mia_voice.playing, "Mia is playing before the checks")
	voice.set_peer_muted(2, true)
	voice._process(0.0)
	_expect(not mia_voice.playing and mia_voice.queued_frames() == 0, "Muting her silences her mid-phrase")
	voice.receive_packet(2, _packet)
	_expect(mia_voice.queued_frames() == 0, "...and nothing more of hers is queued")
	voice.set_peer_muted(2, false)
	voice.receive_packet(2, _packet)
	_expect(not mia_voice.playing and mia_voice.queued_frames() > 0, "A first 40 ms gathers its cushion first")
	voice.set_peer_muted(2, true)
	voice._process(0.0)
	_expect(mia_voice.queued_frames() == 0,
		"Muting her while it gathers drops it too (got %d)" % mia_voice.queued_frames())
	voice.set_peer_muted(2, false)
	_play(voice, 2)
	voice.set_peer_volume(2, 0.0)
	voice._process(0.0)
	_expect(not mia_voice.playing and mia_voice.queued_frames() == 0, "Her volume at 0 silences her too")
	voice.set_peer_volume(2, 0.5)
	settings.voice_volume = 0.5
	_play(voice, 2)
	_expect(is_equal_approx(mia_voice.gain, 0.25), "Her volume times the Voces slider (gain %.2f)" % mia_voice.gain)
	settings.voice_volume = 1.0
	voice.set_peer_volume(2, 1.0)
	_play(voice, 2)
	settings.voice_chat_enabled = false
	voice._process(0.0)
	_expect(not mia_voice.playing and mia_voice.queued_frames() == 0, "Switching voice off silences everyone at once")
	settings.voice_chat_enabled = true

	# --- a flood never piles up latency ---
	for packet: int in 60:
		voice.receive_packet(2, _packet)
	var cap: int = int(mia_voice.max_latency_seconds * mia_voice.sample_rate)
	_expect(mia_voice.queued_frames() <= cap and mia_voice.dropped_frames > 0,
		"2.4 s of voice at once stays under the cap (queued %d, cap %d)" % [mia_voice.queued_frames(), cap])

	# --- nobody to hear from, and leaving ---
	voice.receive_packet(9, _packet)
	_expect(voice.speaker(9) == null, "A peer with no player yet gets no playback")
	network.peer_removed.emit(2)
	await process_frame
	_expect(voice.speaker(2) == null and not is_instance_valid(mia_voice), "Mia leaving frees her playback")
	voice.receive_packet(3, _packet)
	var leo_voice: VoicePlayback = voice.speaker(3)
	_expect(leo_voice != null and leo_voice.get_parent() == leo, "Leo talking gets his own")
	root.multiplayer.peer_disconnected.emit(3)
	await process_frame
	_expect(voice.speaker(3) == null and not is_instance_valid(leo_voice), "A peer that disconnects frees theirs")
	voice.receive_packet(3, _packet)
	leo_voice = voice.speaker(3)
	voice._on_roster_changed([1, 3])
	await process_frame
	_expect(voice.speaker(3) == null and not is_instance_valid(leo_voice),
		"A session that ends (back to a session of one) frees every playback")
	voice.receive_packet(3, _packet)
	leo.free()
	voice._process(0.0)
	_expect(voice.speaker(3) == null, "A player freed with the level takes their playback along")

	# --- a respawn in the same frame: the new player gets the voice ---
	var ana: Node3D = _crewmate(world, 4, Vector3(3.0, 0.0, 3.0))
	voice.receive_packet(4, _packet)
	var ana_voice: VoicePlayback = voice.speaker(4)
	ana.queue_free()
	var ana_again: Node3D = _crewmate(world, 4, Vector3(3.0, 0.0, 3.0))
	voice.receive_packet(4, _packet)
	_expect(voice.speaker(4) != null and voice.speaker(4).get_parent() == ana_again,
		"Respawned in the same frame, her voice moves to the new player")
	await process_frame
	_expect(not is_instance_valid(ana_voice), "...and the old playback goes with the old one")

	# --- the sound check (sound_audit.gd) can mute a crewmate's voice ---
	await _check_sound_check(voice, voice.speaker(4), seat_camera, street_camera)

	# --- the host is gone: session_failed, with no roster change ---
	voice.set_peer_muted(3, true)
	voice.set_peer_volume(4, 0.4)
	voice.receive_packet(4, _packet)
	var last_voice: VoicePlayback = voice.speaker(4)
	network.session_failed.emit("host_lost")
	await process_frame
	_expect(voice.speaker(4) == null and not is_instance_valid(last_voice),
		"When the session fails (the host left) every playback is freed")
	_expect(not voice.is_peer_muted(3) and is_equal_approx(voice.peer_volume(4), 1.0),
		"...and mutes and volumes don't outlive the session")

	await _finish(voice, settings, fake, world, original_enabled, original_volume)


func _check_sound_check(voice: Node, playback: VoicePlayback, seat_camera: Camera3D, street_camera: Camera3D) -> void:
	var audit: Script = load("res://scripts/presentation/sound_audit.gd")
	if playback == null:
		_expect(false, "A playback to check the sound list with")
		return
	_expect(audit.label_of(playback) == "Voz de compañero · Voz",
		"The sound list names it (got %s)" % audit.label_of(playback))
	var normal_db: float = playback.volume_db
	audit.set_muted(self, audit.key_of(playback), true)
	voice.receive_packet(4, _packet)
	voice._process(0.0)
	_expect(playback.volume_db <= -79.0, "Muted from the sound list, the voice is down (%.1f dB)" % playback.volume_db)
	seat_camera.current = true
	voice._process(0.0)
	_expect(playback.muffled and playback.volume_db <= -79.0, "...and stays down when how it carries changes")
	street_camera.current = true
	voice._process(0.0)
	_expect(playback.volume_db <= -79.0, "...either way")
	audit.unmute_all(self)
	voice._process(0.0)
	_expect(is_equal_approx(playback.volume_db, normal_db),
		"Unmuted, it is back to its volume (%.1f dB)" % playback.volume_db)
	voice.receive_packet(4, _packet)
	_expect(playback.playing, "...and still plays after the sound list restarted it")


func _play(voice: Node, peer_id: int) -> void:
	voice.receive_packet(peer_id, _packet)
	voice.receive_packet(peer_id, _packet)
	voice._process(0.0)


func _finish(voice: Node, settings: Node, fake: FakeSteam, world: Node, enabled: bool, volume: float) -> void:
	voice.clear_peers()
	voice.backend = null
	voice.override_steam_session = -1
	settings.voice_chat_enabled = enabled
	settings.voice_volume = volume
	world.queue_free()
	await process_frame
	fake.free()
	if _failures == 0:
		print("PASS: proximity voice plays each crewmate from their head or seat, in the cab or outside, and lets go")
	quit(_failures)


func _crewmate(parent: Node, peer_id: int, at: Vector3) -> Node3D:
	var crewmate: Node3D = _crew_script.new()
	crewmate.name = "Player_%d" % peer_id
	crewmate.set_multiplayer_authority(peer_id)
	crewmate.add_to_group(&"player")
	parent.add_child(crewmate)
	crewmate.global_position = at
	_marker(crewmate, "Head", Vector3(0.0, 1.6, 0.0))
	return crewmate


func _marker(parent: Node, marker_name: String, at: Vector3) -> Node3D:
	var marker := Node3D.new()
	marker.name = marker_name
	marker.position = at
	parent.add_child(marker)
	return marker


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

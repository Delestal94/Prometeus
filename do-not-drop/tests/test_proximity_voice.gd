extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_proximity_voice.gd
##
## Proximity voice (N-212), first slice. The promise that matters most: with
## the general switch off, the microphone is never opened, whatever key is
## held. Then push-to-talk, open mic, LAN without voice (N-212.4), muting a
## crewmate and the packet-size guard. Steam is a fake that counts calls.

# The fake mirrors GodotSteam's camelCase API, so its names can't be snake_case.
# gdlint: disable=function-name
class FakeSteam extends Object:
	var starts: int = 0
	var stops: int = 0
	var gets: int = 0
	var decompressed: int = 0
	var packet: PackedByteArray = PackedByteArray([1, 2, 3, 4])

	func startVoiceRecording() -> void:
		starts += 1

	func stopVoiceRecording() -> void:
		stops += 1

	func getVoice() -> Dictionary:
		gets += 1
		return {"result": 0, "written": packet.size(), "buffer": packet}

	func getVoiceOptimalSampleRate() -> int:
		return 24000

	func decompressVoice(voice: PackedByteArray, _rate: int) -> Dictionary:
		decompressed += 1
		var pcm := PackedByteArray()
		pcm.resize(voice.size() * 4)
		return {"result": 0, "size": pcm.size(), "uncompressed": pcm}
# gdlint: enable=function-name


var failures: int = 0
var received: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: Node = root.get_node("GameSettings")
	var voice: Node = root.get_node("ProximityVoice")
	var fake := FakeSteam.new()
	voice.backend = fake
	voice.override_steam_session = 1
	voice.voice_received.connect(
		func(peer: int, pcm: PackedByteArray, _rate: int) -> void: received.append([peer, pcm.size()]))
	var original_enabled: bool = settings.voice_chat_enabled
	var original_ptt: bool = settings.voice_push_to_talk

	# --- the general switch off never opens the microphone ---
	_expect(settings.DEFAULT_KEY_BINDINGS.has(&"voice_talk"), "Push-to-talk has a default key")
	_expect(InputMap.has_action(&"voice_talk"), "The push-to-talk action exists in the input map")
	settings.voice_chat_enabled = false
	settings.voice_push_to_talk = false
	for i: int in 5:
		voice.tick(true)
	_expect(fake.starts == 0 and fake.gets == 0, "Voice off: neither holding the key nor open mic records")
	_expect(not voice.talking, "Voice off: never marked as talking")

	# --- push-to-talk: records only while held ---
	settings.voice_chat_enabled = true
	settings.voice_push_to_talk = true
	voice.tick(false)
	_expect(fake.starts == 0, "Push-to-talk: nothing recorded before the key is held")
	voice.tick(true)
	voice.tick(true)
	_expect(fake.starts == 1 and voice.talking, "Push-to-talk: holding the key opens the microphone once")
	_expect(fake.gets == 2, "While talking, the recorded voice is collected every frame")
	voice.tick(false)
	_expect(fake.stops == 1 and not voice.talking, "Releasing the key closes the microphone")
	_expect(fake.gets == 3, "The tail of the phrase is still collected after releasing the key")
	for i: int in voice.DRAIN_FRAMES + 3:
		voice.tick(false)
	_expect(fake.gets == 2 + voice.DRAIN_FRAMES, "Collecting stops a few frames after releasing the key")

	# --- turning the general switch off mid-sentence closes it too ---
	voice.tick(true)
	settings.voice_chat_enabled = false
	voice.tick(true)
	_expect(fake.stops == 2 and not voice.talking, "Switching voice off while talking stops recording")

	# --- open mic, and LAN without voice (N-212.4) ---
	settings.voice_chat_enabled = true
	settings.voice_push_to_talk = false
	voice.tick(false)
	_expect(voice.talking, "Open mic records without holding a key")
	voice.override_steam_session = 0
	voice.tick(true)
	_expect(not voice.talking, "Outside a Steam session (LAN/ENet) the microphone closes")
	var starts_before: int = fake.starts
	voice.tick(true)
	_expect(fake.starts == starts_before, "LAN never opens the microphone")
	voice.override_steam_session = 1
	voice.tick(false)
	voice.backend = null
	voice.tick(true)
	_expect(not voice.talking, "Without GodotSteam (CI, a build without Steam) there is no voice")
	voice.backend = fake
	voice.tick(false)
	settings.voice_push_to_talk = true
	voice.tick(false)

	# --- receiving: muted crewmates and oversized packets are dropped ---
	voice.receive_packet(2, PackedByteArray([9, 9, 9]))
	_expect(received.size() == 1 and received[0] == [2, 12], "A crewmate's packet is decompressed and handed out")
	voice.set_peer_muted(2, true)
	voice.receive_packet(2, PackedByteArray([9, 9, 9]))
	_expect(received.size() == 1, "A muted crewmate is not heard")
	voice.set_peer_muted(2, false)
	voice.set_peer_volume(3, 0.0)
	voice.receive_packet(3, PackedByteArray([9]))
	_expect(received.size() == 1, "A crewmate at zero volume is not even decoded")
	var huge := PackedByteArray()
	huge.resize(voice.MAX_PACKET_BYTES + 1)
	voice.receive_packet(2, huge)
	_expect(received.size() == 1, "An oversized packet never reaches the decoder")
	settings.voice_chat_enabled = false
	voice.receive_packet(2, PackedByteArray([9]))
	_expect(received.size() == 1, "With voice off, nobody else is played either")
	voice.clear_peers()
	_expect(is_equal_approx(voice.peer_volume(3), 1.0), "Per-peer volume resets when a session ends")

	voice.backend = null
	voice.override_steam_session = -1
	settings.voice_chat_enabled = original_enabled
	settings.voice_push_to_talk = original_ptt
	fake.free()

	await create_timer(0.1).timeout
	if failures == 0:
		print("PASS: proximity voice records only when switched on, over Steam, and drops muted or oversized packets")
	quit(failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1

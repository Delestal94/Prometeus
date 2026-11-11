extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_voice.gd
##
## The boss's and NPCs' voices as SynthAudio murmurs plus bubbles (expansion D-1928, decided 2026-10-04: no
## ElevenLabs, no recorded voice):
## - SynthAudio.murmur() gives each character of SynthAudioMurmur.VOICES its own voice (base pitches apart, the boss
##   through a radio band), 16-bit, as long as its syllables at its pace, heard and never clipped, the same stream
##   for the same line (cached); an unknown voice speaks as a customer; a line's syllables are its vowel groups;
## - no voice recording ships: no audio file under res://assets is named or filed as a voice;
## - CompanyVoice: the day's opening (day_phase OPENING) has the boss on the radio, "Jefa: Arrancamos el día N",
##   with her murmur on the Voice bus; anyone else with a spot speaks in a bubble over it with a positional murmur,
##   and the bubble goes after its time; CompanyUi adds it; both languages have the keys.

const KEYS: Array[String] = ["WORLD_VOICE_BOSS", "WORLD_VOICE_BOSS_DAY_OPEN"]
const AUDIO_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3", "flac", "opus"]

var _failures: int = 0


class FakeNet:
	extends Node
	signal event_applied(seq: int, kind: StringName, data: Dictionary)


class FakeRoot:
	extends Node3D
	var net: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in KEYS:
			_expect(TranslationServer.translate(key) != key, "%s has %s" % [locale, key])
	TranslationServer.set_locale("es")
	_test_murmurs()
	_test_no_voice_files("res://assets")
	await _test_voice()
	if _failures == 0:
		print("PASS: every character murmurs in its own synthesized voice, with bubbles, and no voice file ships")
	quit(_failures)


func _test_murmurs() -> void:
	_expect(SynthAudioMurmur.syllables_of("Arrancamos el día") == 6, "syllables are vowel groups (%d)"
		% SynthAudioMurmur.syllables_of("Arrancamos el día"))
	_expect(SynthAudioMurmur.syllables_of("") == 1 and SynthAudioMurmur.syllables_of("a e i o u ".repeat(5))
		== SynthAudioMurmur.MAX_SYLLABLES, "1 to MAX_SYLLABLES")
	var datas: Array[PackedByteArray] = []
	for voice: StringName in SynthAudioMurmur.VOICES:
		var stream: AudioStreamWAV = SynthAudio.murmur(voice, 4)
		var preset: Dictionary = SynthAudioMurmur.VOICES[voice]
		var seconds: float = stream.data.size() / 2.0 / stream.mix_rate
		var expected: float = SynthAudioMurmur.SYLLABLE_SECONDS * float(preset["pace"]) * 4 + 0.08
		_expect(stream.format == AudioStreamWAV.FORMAT_16_BITS and absf(seconds - expected) < 0.01,
			"%s talks %.2f s for 4 syllables" % [voice, seconds])
		var peak: int = 0
		for i: int in range(0, stream.data.size() - 1, 2):
			peak = maxi(peak, absi(stream.data.decode_s16(i)))
		_expect(peak > 3000 and peak < 32767, "%s is heard and not clipped (%d)" % [voice, peak])
		_expect(SynthAudio.murmur(voice, 4) == stream, "%s's line is built once" % voice)
		datas.append(stream.data)
	for a: int in datas.size():
		for b: int in range(a + 1, datas.size()):
			_expect(datas[a] != datas[b], "voices %d and %d sound apart" % [a, b])
	var pitches: Array[float] = []
	for voice: StringName in SynthAudioMurmur.VOICES:
		pitches.append(float(SynthAudioMurmur.VOICES[voice]["pitch"]))
	pitches.sort()
	for i: int in range(1, pitches.size()):
		_expect(pitches[i] / pitches[i - 1] > 1.15, "base pitches stay apart (%s)" % [pitches])
	_expect(bool(SynthAudioMurmur.VOICES[&"boss"]["radio"]), "the boss comes through the radio")
	_expect(SynthAudio.murmur(&"nobody", 3) == SynthAudio.murmur(&"customer", 3), "an unknown voice is a customer")


func _test_no_voice_files(dir: String) -> void:
	for file_name: String in DirAccess.get_files_at(dir):
		var lower: String = file_name.to_lower()
		if AUDIO_EXTENSIONS.has(lower.get_extension()):
			_expect(not (lower.contains("voice") or lower.contains("voz") or lower.begins_with("vo_")
				or dir.to_lower().contains("voice")), "%s/%s is not a recorded voice" % [dir, file_name])
	for sub: String in DirAccess.get_directories_at(dir):
		_test_no_voice_files(dir.path_join(sub))


func _test_voice() -> void:
	var fake_root := FakeRoot.new()
	var net := FakeNet.new()
	fake_root.net = net
	fake_root.add_child(net)
	root.add_child(fake_root)
	var voice: CompanyVoice = CompanyVoice.add_to(fake_root)
	await process_frame
	net.event_applied.emit(1, &"day_phase", {"day": 4, "phase": "OPERATING"})
	_expect(voice.radio_text() == "", "only the opening calls the boss")
	net.event_applied.emit(2, &"day_phase", {"day": 4, "phase": "OPENING"})
	_expect(voice.radio_text() == "Jefa: Arrancamos el día 4. ¡A trabajar!", "the boss opens the day (%s)"
		% voice.radio_text())
	var radio := voice.get_node(^"RadioVoice") as AudioStreamPlayer
	_expect(radio.bus == &"Voice" and radio.stream == SynthAudio.murmur(&"boss", voice.last_line["syllables"]),
		"her murmur on the Voice bus")
	var bubble := voice.say(&"customer", "¡Gracias!", Vector3(1.0, 0.0, 2.0)) as Label3D
	_expect(bubble != null and bubble.text == "¡Gracias!"
		and bubble.global_position.is_equal_approx(Vector3(1.0, 2.2, 2.0)), "a bubble over the speaker")
	var murmur := bubble.get_node_or_null(^"Murmur") as AudioStreamPlayer3D if bubble != null else null
	_expect(murmur != null and murmur.stream == SynthAudio.murmur(&"customer", 2), "with a positional murmur")
	await create_timer(CompanyVoice.BUBBLE_SECONDS + CompanyVoice.PER_SYLLABLE_SECONDS * 2 + 0.2).timeout
	_expect(not is_instance_valid(bubble), "the bubble goes after its time")
	var ui_source: String = FileAccess.get_file_as_string("res://scripts/ui/company_ui.gd")
	_expect(ui_source.contains("CompanyVoice.add_to(root)"), "CompanyUi adds the voices")
	fake_root.queue_free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_shed_music.gd
##
## The shed's adaptive music (expansion D-1911): the work loop SynthAudio composes and ShedMusic's mix.
## - SynthAudio.work_music_layer(0..2) are three 16-bit mono loops (LOOP_FORWARD over the whole stream) of
##   exactly the same length, four bars at LOOP_BPM, each at the music level (RMS near MUSIC_RMS_DB, never
##   clipped), different from each other, quiet at the seam, built once and shared; an unknown layer is the bed;
## - ShedMusic plays them in sync (one AudioStreamSynchronized) on the Music bus and keeps on under the pause;
## - with no work only the bed sounds; business events raise the activity and the groove and then the lead
##   come in, in that order; the clock and the day's phases are not work; a quiet stretch drains it back to
##   the bed; the closing screen (SUMMARY) fades the whole loop out and the next OPENING brings it back;
## - add_to() follows CompanyNet.event_applied, and CompanyRoot adds it.

var _failures: int = 0


class FakeNet:
	extends Node
	signal event_applied(seq: int, kind: StringName, data: Dictionary)


class FakeRoot:
	extends Node
	var net: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_layers()
	await _test_mix()
	_test_root_wiring()
	if _failures == 0:
		print("PASS: the shed's work loop comes in layer by layer with the activity and rests between days")
	quit(_failures)


func _test_layers() -> void:
	var expected: int = SynthAudioWorkMusic.loop_samples()
	var seconds: float = float(expected) / SynthAudioWorkMusic.RATE
	var bars_seconds: float = 16.0 * 60.0 / SynthAudioWorkMusic.LOOP_BPM
	_expect(absf(seconds - bars_seconds) < 0.01, "the loop is four bars (%.2f s)" % seconds)
	var datas: Array[PackedByteArray] = []
	for layer: int in SynthAudioWorkMusic.LAYERS:
		var stream: AudioStreamWAV = SynthAudio.work_music_layer(layer)
		_expect(stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo,
			"layer %d is a 16-bit mono stream" % layer)
		if stream == null:
			return
		_expect(stream.data.size() / 2 == expected, "layer %d has the loop's length" % layer)
		_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0
			and stream.loop_end == expected, "layer %d loops over all of it" % layer)
		var total: float = 0.0
		var peak: int = 0
		for index: int in range(0, stream.data.size() - 1, 2):
			var sample: int = stream.data.decode_s16(index)
			total += float(sample * sample)
			peak = maxi(peak, absi(sample))
		var rms_db: float = linear_to_db(sqrt(total / expected) / 32767.0)
		_expect(absf(rms_db - SynthAudioWorkMusic.MUSIC_RMS_DB) < 1.5, "layer %d sits at the music level (%.1f dB)"
			% [layer, rms_db])
		_expect(peak < 32767, "layer %d is not clipped (peak %d)" % [layer, peak])
		var first: int = absi(stream.data.decode_s16(0))
		var last: int = absi(stream.data.decode_s16(stream.data.size() - 2))
		_expect(first < 600 and last < 600, "layer %d is quiet at the seam (%d, %d)" % [layer, first, last])
		datas.append(stream.data)
	_expect(datas[0] != datas[1] and datas[1] != datas[2] and datas[0] != datas[2], "the three layers differ")
	var again: AudioStreamWAV = SynthAudio.work_music_layer(1)
	_expect(again.data == datas[1] and again == SynthAudio.work_music_layer(1), "a layer is built once and shared")
	_expect(SynthAudio.work_music_layer(9) == SynthAudio.work_music_layer(0), "an unknown layer is the bed")


func _test_mix() -> void:
	var fake_root := FakeRoot.new()
	var net := FakeNet.new()
	fake_root.net = net
	fake_root.add_child(net)
	root.add_child(fake_root)
	var music: ShedMusic = ShedMusic.add_to(fake_root)
	await process_frame
	music.set_process(false)
	var synced := music.stream as AudioStreamSynchronized
	_expect(synced != null and synced.stream_count == SynthAudioWorkMusic.LAYERS, "the layers play in sync")
	if synced != null:
		for layer: int in SynthAudioWorkMusic.LAYERS:
			_expect(synced.get_sync_stream(layer) == SynthAudio.work_music_layer(layer), "stem %d is its layer" % layer)
	_expect(music.bus == &"Music" or AudioServer.get_bus_index(&"Music") < 0, "on the Music bus")
	_expect(music.process_mode == Node.PROCESS_MODE_ALWAYS, "it keeps playing under the pause")
	_expect(music.layer_db(0) > -1.0 and music.layer_db(1) <= ShedMusic.SILENT_DB
		and music.layer_db(2) <= ShedMusic.SILENT_DB, "no work: only the bed")
	_expect(is_equal_approx(synced.get_sync_stream_volume(0), music.layer_db(0)), "the stream carries the mix")
	for kind: StringName in [&"clock_anchor", &"day_phase"]:
		net.event_applied.emit(1, kind, {"phase": "OPERATING"})
	_expect(music.activity == 0.0, "the clock and the phases are not work")
	var groove_at: float = -1.0
	var lead_at: float = -1.0
	for second: int in 60:
		for i: int in 3:
			net.event_applied.emit(10 + second * 3 + i, &"box_placed", {})
		music.advance(1.0)
		if groove_at < 0.0 and music.layer_db(1) > -6.0:
			groove_at = second
		if lead_at < 0.0 and music.layer_db(2) > -6.0:
			lead_at = second
	_expect(groove_at >= 0.0 and lead_at > groove_at, "a busy shed brings the groove, then the lead (%s, %s)"
		% [groove_at, lead_at])
	_expect(music.layer_db(0) > -1.0, "the bed stays")
	for second: int in 120:
		music.advance(1.0)
	_expect(music.layer_db(1) <= ShedMusic.SILENT_DB and music.layer_db(2) <= ShedMusic.SILENT_DB,
		"two quiet minutes drain it back to the bed")
	net.event_applied.emit(500, &"day_phase", {"phase": "SUMMARY"})
	music.advance(3.0)
	_expect(music.layer_db(0) <= ShedMusic.SILENT_DB, "the closing screen fades the loop out")
	net.event_applied.emit(501, &"day_phase", {"phase": "OPENING"})
	music.advance(3.0)
	_expect(music.layer_db(0) > -1.0, "the next day brings it back")
	fake_root.queue_free()
	await process_frame


func _test_root_wiring() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/gameplay/company_root.gd")
	_expect(source.contains("ShedMusic.add_to(self)"), "CompanyRoot adds the shed's music")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1

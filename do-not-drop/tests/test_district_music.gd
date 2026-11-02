extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_district_music.gd
##
## Music by district (expansion D-1929, with D-0343: "9 loops"):
## - SynthAudio.theme_music(0..8) are nine 16-bit loops (LOOP_FORWARD over all of it), four bars at each theme's
##   tempo, at the music level (RMS near MUSIC_RMS_DB, unclipped), quiet at the seam, all different, cached;
## - every zone of data/zones has its own theme (DistrictMusic.THEME_OF, nine apart);
## - DistrictMusic: inside the shed nothing plays and the shed's loop stays (ShedMusic.away false); out in Centro its
##   theme fades in on the Music bus and the shed's loop goes away; crossing into Campo crossfades (the old theme
##   fades out as the new one comes in); back in the shed it all fades out and the shed's loop comes back;
## - CompanyUi adds it.

const LEVELS: String = "res://tests/test_world_audio_levels.gd"

var _failures: int = 0


class FakeShedMusic:
	extends Node
	var away: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_themes()
	await _test_player()
	var ui_source: String = FileAccess.get_file_as_string("res://scripts/ui/company_ui.gd")
	_expect(ui_source.contains("DistrictMusic.add_to(root)"), "CompanyUi adds the district music")
	if _failures == 0:
		print("PASS: nine district themes composed in code, crossfading as the player crosses zones")
	quit(_failures)


func _test_themes() -> void:
	var levels: Script = load(LEVELS)
	var datas: Array[PackedByteArray] = []
	for theme: int in SynthAudioThemeMusic.THEMES.size():
		var stream: AudioStreamWAV = SynthAudio.theme_music(theme)
		var samples: int = SynthAudioThemeMusic.loop_samples(theme)
		_expect(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.data.size() / 2 == samples
			and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == samples,
			"theme %d loops over its four bars" % theme)
		var rms: float = levels.call(&"measure_dbfs", stream, "rms")
		var peak: float = levels.call(&"measure_dbfs", stream, "peak")
		_expect(absf(rms - SynthAudioThemeMusic.MUSIC_RMS_DB) < 4.0 and peak < -0.01,
			"theme %d at the music level (%.1f, peak %.1f)" % [theme, rms, peak])
		_expect(absi(stream.data.decode_s16(0)) < 600 and absi(stream.data.decode_s16(stream.data.size() - 2)) < 600,
			"theme %d is quiet at the seam" % theme)
		_expect(SynthAudio.theme_music(theme) == stream, "theme %d is built once" % theme)
		datas.append(stream.data)
	for a: int in datas.size():
		for b: int in range(a + 1, datas.size()):
			_expect(datas[a] != datas[b], "themes %d and %d differ" % [a, b])
	var zones: Array = CompanyRoot.load_zones()
	var used: Dictionary = {}
	for zone: ZoneDefinition in zones:
		_expect(DistrictMusic.THEME_OF.has(zone.id), "%s has a theme" % zone.id)
		used[DistrictMusic.THEME_OF.get(zone.id, -1)] = true
	_expect(zones.size() == 9 and used.size() == 9, "nine zones, nine themes")


func _test_player() -> void:
	var zones: Array = CompanyRoot.load_zones()
	var by_id: Dictionary = {}
	for zone: ZoneDefinition in zones:
		by_id[zone.id] = zone
	var player := Node3D.new()
	root.add_child(player)
	var shed := FakeShedMusic.new()
	root.add_child(shed)
	var music := DistrictMusic.new()
	music.player_of = func() -> Node3D: return player
	music.zones_of = func() -> Array: return zones
	music.in_shed = func(at: Vector3) -> bool: return at.length() < 20.0
	music.shed_music_of = func() -> Node: return shed
	root.add_child(music)
	await process_frame
	music.set_process(false)
	music.check()
	music.fade(DistrictMusic.FADE_SECONDS)
	_expect(music.theme == -1 and not shed.away and _loud(music) == 0, "in the shed: no district theme")
	player.global_position = _center(by_id[&"centro"])
	music.check()
	_expect(music.theme == DistrictMusic.THEME_OF[&"centro"] and shed.away, "out in Centro: its theme, shed loop away")
	music.fade(DistrictMusic.FADE_SECONDS)
	var centro_player: AudioStreamPlayer = _playing(music, DistrictMusic.THEME_OF[&"centro"])
	_expect(centro_player != null and centro_player.bus == &"Music"
		and is_equal_approx(centro_player.volume_db, DistrictMusic.VOLUME_DB), "Centro's theme up on the Music bus")
	player.global_position = _center(by_id[&"campo"])
	music.check()
	music.fade(DistrictMusic.FADE_SECONDS * 0.5)
	var campo_player: AudioStreamPlayer = _playing(music, DistrictMusic.THEME_OF[&"campo"])
	_expect(campo_player != null and campo_player != centro_player
		and centro_player.volume_db < DistrictMusic.VOLUME_DB - 1.0
		and campo_player.volume_db > DistrictMusic.SILENT_DB,
		"crossing into Campo crossfades")
	music.fade(DistrictMusic.FADE_SECONDS)
	_expect(not centro_player.playing and is_equal_approx(campo_player.volume_db, DistrictMusic.VOLUME_DB),
		"the old theme is gone")
	player.global_position = Vector3.ZERO
	music.check()
	music.fade(DistrictMusic.FADE_SECONDS)
	_expect(music.theme == -1 and not shed.away and _loud(music) == 0, "back in the shed: quiet, the shed loop back")
	music.queue_free()
	shed.queue_free()
	player.queue_free()
	await process_frame


static func _center(zone: ZoneDefinition) -> Vector3:
	var middle: Vector2 = zone.bounds.get_center()
	return Vector3(middle.x, 0.0, middle.y)


static func _playing(music: DistrictMusic, theme: int) -> AudioStreamPlayer:
	for player: AudioStreamPlayer in music.players():
		if player.playing and player.stream == SynthAudio.theme_music(theme):
			return player
	return null


static func _loud(music: DistrictMusic) -> int:
	var count: int = 0
	for player: AudioStreamPlayer in music.players():
		if player.playing and player.volume_db > DistrictMusic.SILENT_DB + 0.5:
			count += 1
	return count


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1

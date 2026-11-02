extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_forklift_cues.gd
##
## What the shed's forklift sounds and shows (expansion D-0606.c3: forklift_cues.gd, fed by forklift_view.gd;
## SynthAudio.forklift_hydraulic_loop):
## - with nobody on it and the forks still: no engine, no hydraulics, the beacon dark and its light off;
## - somebody drives (any peer: it reads the book's state): the motor plays, positional on the Machines bus and audible
##   across the shed, and the amber beacon is lit and its light on; the pump does not play while the forks rest;
## - the forks going up or down (moving_at) bring the pump, a tone lower going down; it stops by itself when the
##   burst ends, whoever has the forklift, and the engine goes on;
## - getting off cuts the engine (after its short fade, no click) and darkens the beacon; nothing keeps running;
## - the pump is a real sound: a looping second, not silence, at the level of the "machine" class (world_mix.gd,
##   test_world_audio_levels) and named in the sound audit.
## Not covered: how it sounds (a human validates it in the game).

const SoundAudit = preload("res://scripts/presentation/sound_audit.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_pump_sound()
	await _test_cues()
	if _failures == 0:
		print("PASS: the shed forklift sounds and lights up while somebody drives and while its forks move")
	quit(_failures)


func _test_pump_sound() -> void:
	var pump: AudioStreamWAV = SynthAudio.forklift_hydraulic_loop()
	_expect(pump == SynthAudio.forklift_hydraulic_loop(), "The pump is built once and shared")
	var peak: int = 0
	for index: int in range(0, pump.data.size() - 1, 2):
		peak = maxi(peak, absi(pump.data.decode_s16(index)))
	_expect(peak > 1000, "The pump is not silence (peak %d)" % peak)
	var seconds: float = float(pump.data.size() / 2) / float(pump.mix_rate)
	_expect(is_equal_approx(seconds, 1.0), "The pump is one second long (%.2f)" % seconds)
	_expect(pump.loop_mode == AudioStreamWAV.LOOP_FORWARD and pump.loop_end == pump.data.size() / 2,
		"The pump loops over the whole clip")
	var first: int = pump.data.decode_s16(0)
	var last: int = pump.data.decode_s16(pump.data.size() - 2)
	_expect(absi(first - last) < 4000, "The pump's seam is smooth (%d -> %d)" % [last, first])
	_expect(SoundAudit.SOUND_NAMES.has(&"forklift_hydraulic_loop") and SoundAudit.SOURCE_NAMES.has("forklift_cues"),
		"The pump and its player are named in the sound audit")


func _test_cues() -> void:
	var view := ForkliftView.make(Vector2(2.0, 2.0), 0.0)
	root.add_child(view)
	var pallets := CompanyPallets.new()
	var cues: ForkliftCues = view.get_node("Cues")
	var engine: AudioStreamPlayer3D = cues.get_node("Motor")
	var pump: AudioStreamPlayer3D = cues.get_node("Hydraulics")
	var light: OmniLight3D = cues.get_node("BeaconLight")
	view.refresh(pallets)
	await _frames(3)
	_expect(not engine.playing and not pump.playing, "Nobody drives and the forks rest: nothing plays")
	_expect(not light.visible and not cues.beacon_on(), "Nobody drives: the beacon is off")
	_expect(not cues.is_processing(), "Nothing is running when nothing happens")

	# Somebody drives (any peer's id: it is the book's state).
	var now: int = Time.get_ticks_msec()
	pallets.forklift.apply(CompanyForklift.state_event(7, Vector2(2.0, 2.0), 0.0, 0, 0.0), now)
	view.refresh(pallets)
	await _frames(3)
	_expect(cues.engine_on() and engine.playing, "A driver: the motor plays")
	_expect(engine.bus == CompanyMix.MACHINES and engine.max_distance >= 20.0 and engine.unit_size > 0.0,
		"The motor is positional on the Machines bus (D-1912) and reaches across the shed")
	_expect(engine.stream == SynthAudio.forklift_motor_loop(), "The motor is the electric one of the depot's forklift")
	_expect(light.visible and cues.beacon_on() and light.light_color.r > light.light_color.b,
		"A driver: the amber beacon is on")
	_expect(not light.shadow_enabled, "The beacon's light casts no shadow")
	_expect(not pump.playing and not cues.hydraulic_on(), "Forks at rest: no pump")

	# The forks go up for a burst, then stop by themselves.
	var burst_msec: int = int(CompanyTuning.FORKLIFT_MAST_BURST_S * 1000.0)
	now = Time.get_ticks_msec()
	pallets.forklift.apply(CompanyForklift.state_event(7, Vector2(2.0, 2.0), 0.0, 1, 0.0), now)
	view.refresh(pallets)
	await _frames(3)
	_expect(cues.hydraulic_on() and pump.playing, "Forks rising: the pump plays")
	var up_pitch: float = pump.pitch_scale
	await create_timer(float(burst_msec) / 1000.0 + 0.3).timeout
	_expect(not cues.hydraulic_on(), "The burst is over: the pump is cut (it follows moving_at)")
	await create_timer(0.5).timeout
	_expect(not pump.playing, "... and fades out until it stops")
	_expect(engine.playing and cues.engine_on(), "The engine goes on while the driver is on")
	now = Time.get_ticks_msec()
	pallets.forklift.apply(CompanyForklift.state_event(7, Vector2(2.0, 2.0), 0.0, -1, 1.0), now)
	view.refresh(pallets)
	await _frames(2)
	_expect(pump.playing and pump.pitch_scale < up_pitch, "Forks sinking: the pump plays a tone lower")

	# The driver gets off with the forks still going: the pump goes on (it is the forks' sound), the engine stops.
	now = Time.get_ticks_msec()
	pallets.forklift.apply(CompanyForklift.state_event(0, Vector2(2.0, 2.0), 0.0, 0, 0.5), now)
	view.refresh(pallets)
	await _frames(2)
	_expect(not cues.engine_on() and not light.visible and not cues.beacon_on(),
		"Off: the engine is cut and the beacon dark")
	await create_timer(0.6).timeout
	_expect(not engine.playing and not pump.playing, "Off: nothing plays after the fade")
	_expect(not cues.is_processing() and not view.is_processing(), "Off: nothing is left running")
	view.queue_free()


func _frames(count: int) -> void:
	for i: int in range(count):
		await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

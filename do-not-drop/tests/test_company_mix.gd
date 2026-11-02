extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_mix.gd
##
## The company world's buses and levels (expansion D-1912, CompanyMix), measured:
## - the layout has Shed (with its hall reverb) sending to SFX, Machines sending to Shed and Districts sending to
##   Exterior, all at 0 dB; each route ends in Master, and Shed and Machines go through SFX (the effects volume);
## - CompanyMix.bus() falls back along the sends when a bus is missing, down to Master;
## - each company sound, measured as test_world_audio_levels measures (stream + its player's volume_db + every bus
##   of its route but the player's own volume buses), lands within TOLERANCE_DB of its class: the clipboard's three
##   cues (handling), the shed's forklift engine and hydraulics on Machines (machine), the shed's work loop with its
##   bed alone (work music);
## - the shed's forklift plays on Machines.

const LEVELS: String = "res://tests/test_world_audio_levels.gd"
const WorldMix = preload("res://scripts/presentation/world_mix.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_layout()
	_test_fallback()
	_test_levels()
	await _test_forklift()
	if _failures == 0:
		print("PASS: the company's buses route to Master and every company sound sits at its measured level")
	quit(_failures)


func _test_layout() -> void:
	var sends: Dictionary = {CompanyMix.SHED: &"SFX", CompanyMix.MACHINES: CompanyMix.SHED,
		CompanyMix.DISTRICTS: &"Exterior"}
	for bus: StringName in sends:
		var index: int = AudioServer.get_bus_index(bus)
		_expect(index >= 0, "the layout has %s" % bus)
		if index < 0:
			continue
		_expect(AudioServer.get_bus_send(index) == sends[bus], "%s sends to %s" % [bus, sends[bus]])
		_expect(AudioServer.get_bus_volume_db(index) == 0.0, "%s stays at 0 dB" % bus)
		_expect(CompanyMix.route(bus).back() == &"Master", "%s ends in Master (%s)" % [bus, CompanyMix.route(bus)])
	var shed: int = AudioServer.get_bus_index(CompanyMix.SHED)
	_expect(shed >= 0 and AudioServer.get_bus_effect_count(shed) > 0
		and AudioServer.get_bus_effect(shed, 0) is AudioEffectReverb, "the shed has its hall reverb")
	for bus: StringName in [CompanyMix.SHED, CompanyMix.MACHINES]:
		_expect(CompanyMix.route(bus).has(&"SFX"), "%s goes through SFX: the effects volume reaches it" % bus)
	_expect(CompanyMix.route(CompanyMix.DISTRICTS).has(&"Exterior"), "the districts get the outdoor reverb")


func _test_fallback() -> void:
	_expect(CompanyMix.bus(CompanyMix.MACHINES) == CompanyMix.MACHINES, "an existing bus is itself")
	var machines: int = AudioServer.get_bus_index(CompanyMix.MACHINES)
	AudioServer.set_bus_name(machines, &"Gone")
	_expect(CompanyMix.bus(CompanyMix.MACHINES) == CompanyMix.SHED, "no Machines: the shed")
	AudioServer.set_bus_name(machines, CompanyMix.MACHINES)
	_expect(CompanyMix.bus(&"Nowhere") == &"Master", "an unknown bus: Master")


func _test_levels() -> void:
	var levels: Script = load(LEVELS)
	var sounds: Array = [
		["clipboard clip up", SynthAudio.clipboard_clip_up(), CompanyClipboard.SFX_DB, &"SFX", "handling", "loudest"],
		["clipboard clip down", SynthAudio.clipboard_clip_down(), CompanyClipboard.SFX_DB, &"SFX", "handling",
			"loudest"],
		["clipboard sheet", SynthAudio.clipboard_sheet(), CompanyClipboard.SFX_DB, &"SFX", "handling", "loudest"],
		["shed forklift engine", SynthAudio.forklift_motor_loop(), WorldMix.SHED_FORKLIFT_ENGINE_DB,
			CompanyMix.MACHINES, "machine", "rms"],
		["shed forklift hydraulics", SynthAudio.forklift_hydraulic_loop(), WorldMix.SHED_FORKLIFT_HYDRAULIC_DB,
			CompanyMix.MACHINES, "machine", "rms"],
		["shed work loop (bed)", SynthAudio.work_music_layer(0), ShedMusic.VOLUME_DB, &"Music", "work music", "rms"],
	]
	for sound: Array in sounds:
		var measured: float = levels.call(&"measure_dbfs", sound[1], sound[5])
		var result: float = measured + float(sound[2]) + CompanyMix.route_gain_db(sound[3])
		var target: float = CompanyMix.TARGETS_DB[sound[4]]
		_expect(absf(result - target) <= CompanyMix.TOLERANCE_DB, "%s lands at %.1f dBFS %s, target %.1f (%s)"
			% [sound[0], result, sound[5], target, sound[4]])


func _test_forklift() -> void:
	var cues: ForkliftCues = ForkliftCues.make()
	root.add_child(cues)
	await process_frame
	var players: Array[Node] = cues.find_children("*", "AudioStreamPlayer3D", true, false)
	_expect(not players.is_empty(), "the forklift has its players")
	for player: Node in players:
		_expect((player as AudioStreamPlayer3D).bus == CompanyMix.MACHINES, "%s plays on Machines" % player.name)
	cues.queue_free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1

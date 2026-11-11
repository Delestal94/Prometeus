extends SceneTree
## S-311.98: all gel emitters follow the listener's Interior/Exterior bus,
## preserve their option sliders and lower pitch as body mass grows.

const PLAYER_SCENE := preload("res://scenes/gameplay/player/player.tscn")
const Mix = preload("res://scripts/gameplay/player/gel/gel_audio_mix.gd")
const Proportions = preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const WorldMix = preload("res://scripts/presentation/world_mix.gd")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var vehicle := Node.new()
	vehicle.name = &"TestVehicle"
	vehicle.add_to_group(&"vehicle")
	var presentation_script := GDScript.new()
	presentation_script.source_code = ("extends Node\nvar inside: bool = false\n"
		+ "func viewer_inside() -> bool:\n\treturn inside\n")
	presentation_script.reload()
	var presentation: Node = presentation_script.new()
	presentation.name = &"VehiclePresentation"
	vehicle.add_child(presentation)
	root.add_child(vehicle)

	var player: Player = PLAYER_SCENE.instantiate()
	player.set_multiplayer_authority(2)
	root.add_child(player)
	await process_frame
	var foley: Node = player.get_node(^"GelEffects/GelAudio")
	var voice: Node = player.get_node(^"PlayerVoice")
	var dance: Node = player.get_node(^"PlayerVoice/GelDanceAudio")

	_expect(Mix.listener_bus(player) == &"Exterior", "an outside listener selects Exterior")
	_check_component_buses(player, voice, dance, &"Exterior")
	presentation.set(&"inside", true)
	foley.call(&"update_audio", player, player.get_node(^"GelEffects/GelKnockout"), 0.0, true)
	voice.call(&"_process", 0.0)
	dance.call(&"_process", 0.0)
	_expect(Mix.listener_bus(player) == &"Interior", "a truck listener selects Interior")
	_check_component_buses(player, voice, dance, &"Interior")

	_check_pitch_policy(player, dance)
	_check_slider_gain(voice)

	player.free()
	vehicle.free()
	if _failures == 0:
		print("PASS: gel audio follows environment buses, body mass, player slot and mix headroom")
	quit(_failures)


func _check_component_buses(player: Player, voice: Node, dance: Node, expected: StringName) -> void:
	for index: int in 4:
		var emitter := player.get_node(NodePath("GelFoley%d" % index)) as AudioStreamPlayer3D
		_expect(emitter.bus == expected, "foley voice %d follows %s" % [index, expected])
	_expect((voice.get(&"voice") as AudioStreamPlayer3D).bus == expected,
		"wordless voice follows %s" % expected)
	_expect((dance.get(&"music") as AudioStreamPlayer3D).bus == expected,
		"dance music follows %s" % expected)


func _check_pitch_policy(player: Player, dance: Node) -> void:
	var small: GelBodyProportions = Proportions.new()
	small.total_height = 0.85
	small.general_thickness = -1.0
	var large: GelBodyProportions = Proportions.new()
	large.total_height = 1.20
	large.general_thickness = 1.0
	_expect(Mix.body_size(small) < 1.0 and Mix.body_size(large) > 1.0,
		"height and thickness produce an ordered body-size measure")
	_expect(Mix.body_pitch(small) > 1.0 and Mix.body_pitch(large) < 1.0,
		"a larger gel receives a lower pitch")
	var other := Node.new()
	other.set_multiplayer_authority(3)
	_expect(not is_equal_approx(Mix.player_pitch(player, small), Mix.player_pitch(other, small)),
		"two player slots add distinct subtle pitch identities")
	other.free()
	var state: Node = player.get_node(^"GelProportions")
	state.set(&"proportions", large)
	dance.call(&"_process", 0.0)
	_expect(is_equal_approx((dance.get(&"music") as AudioStreamPlayer3D).pitch_scale,
		Mix.player_pitch(player, large)), "dance playback applies the live body/player pitch")


func _check_slider_gain(voice: Node) -> void:
	var settings: Node = root.get_node(^"GameSettings")
	settings.set(&"voice_volume", 0.5)
	voice.call(&"_process", 0.0)
	_expect(is_equal_approx((voice.get(&"voice") as AudioStreamPlayer3D).volume_db,
		WorldMix.GEL_VOICE_DB + linear_to_db(0.5)), "environment routing preserves the voice slider")
	settings.set(&"voice_volume", 1.0)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

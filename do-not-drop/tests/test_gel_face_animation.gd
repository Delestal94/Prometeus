extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_face_animation.gd
## S-311.60: blink, contextual gaze and voice-driven mouth opening.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const GelFaceScript := preload("res://scripts/gameplay/player/gel/gel_face.gd")
const Reactions := preload("res://scripts/gameplay/player/gel/gel_face_reactions.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model: Node3D = GEL_SCENE.instantiate() as Node3D
	root.add_child(model)
	var face: BoneAttachment3D = GelFaceScript.new()
	_expect(face.setup(model, PlayerAppearance.find_skeleton(model), 1), "the animated face attaches to the gel rig")
	face.set_face(&"happy")
	var eyes := face.get_node(^"Eyes") as MeshInstance3D
	var mouth := face.get_node(^"Mouth") as MeshInstance3D

	face.set(&"_next_blink", 0.0)
	face.advance_animation(0.01)
	face.advance_animation(GelFaceScript.BLINK_CLOSE)
	_expect((eyes.material_override as StandardMaterial3D).uv1_scale.y > 5.0,
		"the automatic blink closes the eye sheet along its authored eye line")
	face.advance_animation(GelFaceScript.BLINK_HOLD + GelFaceScript.BLINK_OPEN + 0.01)
	_expect(is_equal_approx((eyes.material_override as StandardMaterial3D).uv1_scale.y, 1.0),
		"the blink opens the eyes again")

	face.set_gaze_target(face.to_global(Vector3(1.0, 0.4, -2.0)))
	face.advance_animation(0.5)
	_expect(face.gaze_offset().length() > 0.01,
		"the eyes look toward a world-space target in front of the head (got %s)" % face.gaze_offset())
	var first_gaze: Vector2 = face.gaze_offset()
	face.set_gaze_target(face.to_global(Vector3(-1.0, -0.4, -2.0)))
	face.advance_animation(0.5)
	_expect(face.gaze_offset().dot(first_gaze) < 0.0, "the gaze crosses the face when its target crosses the head")
	face.clear_gaze_target()
	face.advance_animation(0.7)
	_expect(face.gaze_offset().length() < 0.001, "the gaze eases back to centre without a target")

	face.set_voice_amplitude(0.2)
	face.advance_animation(0.25)
	_expect(face.mouth_openness() > 0.8,
		"voice amplitude opens the mouth proportionally")
	_expect((mouth.material_override as StandardMaterial3D).uv1_scale.y < 0.8,
		"mouth opening stretches the authored mouth around its centre")
	face.set_voice_amplitude(0.0)
	face.advance_animation(0.5)
	_expect(face.mouth_openness() < 0.01, "silence closes the mouth smoothly")

	_check_player_inputs()
	face.free()
	model.free()
	if _failures == 0:
		print("PASS: gel face blinks, follows context and opens with proximity voice")
	quit(_failures)


func _check_player_inputs() -> void:
	var player_script := GDScript.new()
	player_script.source_code = "extends Node3D\nvar _ragdolled: bool = false\n" \
		+ "var net_in_vehicle: bool = false\nvar face_eyes: StringName = &\"classic\"\n" \
		+ "var face_mouth: StringName = &\"smile\"\nvar carried_package: Node = null\n" \
		+ "var tended_package: Node = null\nvar assisted_package: Node = null\n" \
		+ "var _body_visual: Node = null\nvar _character_face: Node = null\n"
	player_script.reload()
	var player := player_script.new() as Node3D
	player.add_to_group(&"player")
	root.add_child(player)

	var spy_script := GDScript.new()
	spy_script.source_code = "extends Node\nvar face_id: StringName = &\"none\"\n" \
		+ "var gaze: Vector3 = Vector3.ZERO\nvar level: float = 0.0\n" \
		+ "func set_face(value: StringName) -> void:\n\tface_id = value\n" \
		+ "func set_expression(_eyes: StringName, _mouth: StringName) -> void:\n\tpass\n" \
		+ "func set_gaze_target(value: Vector3) -> void:\n\tgaze = value\n" \
		+ "func clear_gaze_target() -> void:\n\tgaze = Vector3.ZERO\n" \
		+ "func set_voice_amplitude(value: float) -> void:\n\tlevel = value\n"
	spy_script.reload()
	var spy: Node = spy_script.new()
	player.add_child(spy)
	var reactions: Node = Reactions.new()
	player.add_child(reactions)
	reactions.call(&"set_face_target", spy)

	var teammate := Node3D.new()
	teammate.add_to_group(&"player")
	root.add_child(teammate)
	teammate.global_position = Vector3(2.0, 1.5, -1.0)
	var teammate_head := Node3D.new()
	teammate_head.name = &"Head"
	teammate_head.position.y = 1.6
	teammate.add_child(teammate_head)
	reactions.call(&"_process", 0.0)
	_expect((spy.get(&"gaze") as Vector3).is_equal_approx(teammate_head.global_position),
		"without cargo the face follows the nearest crewmate's head")

	var package_script := GDScript.new()
	package_script.source_code = "extends Node3D\nvar package_id: StringName = &\"look_box\"\n" \
		+ "var trap_state: int = 0\nfunc run_state() -> int:\n\treturn trap_state\n"
	package_script.reload()
	var package := package_script.new() as Node3D
	root.add_child(package)
	package.global_position = Vector3(-1.0, 0.8, -0.5)
	player.set(&"carried_package", package)
	reactions.call(&"_process", 0.0)
	_expect((spy.get(&"gaze") as Vector3).is_equal_approx(package.global_position),
		"a carried box takes priority over the nearest crewmate")

	var playback := VoicePlayback.new()
	playback.name = &"VoiceChat"
	player.add_child(playback)
	var pcm := PackedByteArray()
	pcm.resize(400)
	for index: int in 200:
		pcm.encode_s16(index * 2, 9000 if index % 2 == 0 else -9000)
	playback.push_pcm(pcm, 24000)
	reactions.call(&"_process", 0.0)
	_expect(float(spy.get(&"level")) > 0.2,
		"the face receives the live amplitude from this player's proximity voice")

	playback.silence()
	reactions.call(&"_process", 0.0)
	_expect(is_zero_approx(float(spy.get(&"level"))), "muted or ended voice closes the face input")
	package.free()
	teammate.free()
	player.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

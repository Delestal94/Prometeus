extends SceneTree
## Independent selections, persistent profile migration, live preview, per-peer
## face materials, and facial attachments that follow the animated head.
const Catalog = preload("res://scripts/presentation/face_catalog.gd")
const Profile = preload("res://scripts/core/unlock_manager.gd")
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var profile := Profile.new()
	profile.storage_path = "user://faces_test.json"
	profile.reset_profile()
	_expect(profile.select_eyes(&"wink") and profile.select_mouth(&"tongue"), "Face options are selectable")
	profile.select_eyes(&"sleepy")
	_expect(profile.selected_mouth == &"tongue", "Changing eyes preserves the mouth")
	profile.select_mouth(&"laugh")
	_expect(profile.selected_eyes == &"sleepy", "Changing mouth preserves the eyes")
	_expect(not profile.select_eyes(&"../../bad") and not profile.select_mouth(&"missing"), "Unknown IDs are rejected")
	var restored := Profile.new()
	restored.storage_path = profile.storage_path
	restored.load_profile()
	_expect(restored.selected_eyes == &"sleepy" and restored.selected_mouth == &"laugh", "Face survives save/load")
	var file := FileAccess.open(profile.storage_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 2, "selected_cosmetic": "mint_uniform", "selected_eyes": "invalid"}))
	file.close()
	restored.load_profile()
	_expect(restored.selected_eyes == Catalog.DEFAULT_EYES and restored.selected_mouth == Catalog.DEFAULT_MOUTH, "Old/corrupt profiles get valid face defaults")
	_expect(restored.selected_cosmetic == &"mint_uniform", "Migration preserves the old uniform")
	profile.free(); restored.free()
	for kind: String in ["eyes", "mouth"]:
		var choices: Dictionary = Catalog.EYES if kind == "eyes" else Catalog.MOUTHS
		for id: StringName in choices:
			_expect(Catalog.texture(kind, id) != null, "Texture exists: %s/%s" % [kind, id])

	var player_scene: PackedScene = load("res://scenes/gameplay/player/player.tscn")
	var first: Node3D = player_scene.instantiate()
	first.name = "Player_1"
	root.add_child(first)
	var second: Node3D = player_scene.instantiate()
	second.name = "Player_2"
	root.add_child(second)
	await process_frame
	first.set_physics_process(false); second.set_physics_process(false)
	first.face_eyes = &"wink"; first.face_mouth = &"tongue"
	second.face_eyes = &"worried"; second.face_mouth = &"pout"
	var face1 := first.find_child("CharacterFace", true, false) as BoneAttachment3D
	var face2 := second.find_child("CharacterFace", true, false) as BoneAttachment3D
	_expect(face1 != null and face2 != null, "Both players have faces")
	_expect(face1.bone_name == "head", "Face follows the head bone")
	_expect(face1.get_node("Eyes").layers == 2 and face2.get_node("Eyes").layers == 1, "First-person and teammate face layers match their bodies")
	var material1: Material = face1.get_node("Eyes").material_override
	var material2: Material = face2.get_node("Eyes").material_override
	_expect(material1 != material2, "Face materials are per player")
	_expect(material1.albedo_texture == Catalog.texture("eyes", &"wink"), "Selected eyes reach the 3D material")
	_expect(material2.albedo_texture == Catalog.texture("eyes", &"worried"), "Another player's expression does not leak")
	# Blinks squash the eye texture onto its line and fully reopen; the
	# already-closed ^^ eyes never blink. Driven by hand, not by waiting.
	face2.blink()
	face2._process(0.08)
	var squashed: float = (material2 as StandardMaterial3D).uv1_scale.y
	_expect(squashed > 5.0, "A blink shuts the eyes (uv scale %.2f)" % squashed)
	face2._process(0.2)
	_expect(is_equal_approx((material2 as StandardMaterial3D).uv1_scale.y, 1.0), "Eyes reopen after a blink")
	face2.set_expression(&"joyful", &"pout")
	face2.blink()
	face2._process(0.08)
	_expect(is_equal_approx((material2 as StandardMaterial3D).uv1_scale.y, 1.0), "Happy closed eyes never blink")
	face2.set_expression(&"worried", &"pout")
	var sync: MultiplayerSynchronizer = first.get_node("MultiplayerSynchronizer")
	for path: NodePath in [^".:face_eyes", ^".:face_mouth"]:
		_expect(sync.replication_config.has_property(path) and sync.replication_config.property_get_spawn(path), "Face selection replicates at spawn: %s" % path)

	var panel: Control = load("res://scripts/ui/cosmetics_panel.gd").new()
	root.add_child(panel)
	await process_frame
	var preview: Control = panel.find_child("FacePreview", true, false)
	panel.find_child("Eyes_lashes", true, false).pressed.emit()
	panel.find_child("Mouth_grin", true, false).pressed.emit()
	_expect(preview.eyes_id == &"lashes" and preview.mouth_id == &"grin", "2D preview combines the two clicked options")
	_expect(first.face_eyes == &"lashes" and first.face_mouth == &"grin", "Wardrobe selection updates the live local player")
	_expect(second.face_eyes == &"worried", "Local profile changes leave a remote player alone")
	panel.find_child("Eyes_none", true, false).pressed.emit()
	_expect(not face1.get_node("Eyes").visible and face1.get_node("Mouth").visible, "Blank eyes preserve the selected mouth")
	panel.find_child("Mouth_none", true, false).pressed.emit()
	_expect(not face1.get_node("Mouth").visible, "Original faceless look remains available")
	panel.free(); first.free(); second.free()
	if _failures == 0: print("PASS: independent eyes/mouth, persistence, live 2D/3D preview and replicated player face")
	quit(_failures)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		_failures += 1

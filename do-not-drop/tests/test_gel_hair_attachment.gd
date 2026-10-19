extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_hair_attachment.gd
## S-311.64: all hair follows the head extremes and explicit hat rules prevent intersections.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const Catalog := preload("res://scripts/gameplay/player/gel/gel_hair_catalog.gd")
const Attachment := preload("res://scripts/gameplay/player/gel/gel_hair_attachment.gd")
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model: Node3D = GEL_SCENE.instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(model)
	for definition: Dictionary in Catalog.HAIRSTYLES:
		var style_id: StringName = definition[&"id"]
		var attachment: BoneAttachment3D = Attachment.new()
		_expect(attachment.setup(skeleton, style_id, 4), "%s attaches to the real head" % style_id)
		_expect(attachment.bone_name == &"head" and attachment.get_parent() == skeleton,
			"%s follows the animated head bone" % style_id)
		for head_size: float in [0.75, 1.25]:
			for head_shape: float in [-1.0, 1.0]:
				var proportions: Resource = Proportions.new()
				proportions.set(&"head_size", head_size)
				proportions.set(&"head_shape", head_shape)
				attachment.apply_proportions(proportions)
				var hair: Node3D = attachment.hair_root()
				var expected := Vector3(
					(1.0 + head_shape * Attachment.HEAD_SHAPE_X) * head_size,
					(1.0 + head_shape * Attachment.HEAD_SHAPE_Y) * head_size,
					head_size
				)
				attachment.set_hat_rule(Attachment.HatRule.NONE)
				_expect(hair.scale.is_equal_approx(expected) and hair.visible,
					"%s copies head size %.2f and shape %.0f" % [style_id, head_size, head_shape])
				attachment.set_hat_rule(Attachment.HatRule.COMPRESS)
				_expect(hair.visible and hair.scale.y < expected.y and hair.position.y < 0.0,
					"%s compresses below a fitted hat" % style_id)
				attachment.set_hat_rule(Attachment.HatRule.HIDE)
				_expect(not hair.visible, "%s hides under a closed hat" % style_id)
				_expect(hair.transform.is_finite(), "%s remains finite for every head/hat combination" % style_id)
		attachment.queue_free()
	await process_frame
	model.queue_free()
	if _failures == 0:
		print("PASS: every gel hairstyle follows head morphs and obeys hat fitting rules")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

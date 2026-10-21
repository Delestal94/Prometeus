extends SceneTree
## S-311.75: every costume, hairstyle and authored proportion extreme stays compatible.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const CostumeCatalog := preload("res://scripts/gameplay/player/gel/gel_costume_catalog.gd")
const CostumeLibrary := preload("res://scripts/gameplay/player/gel/gel_costume_library.gd")
const CostumeFitter := preload("res://scripts/gameplay/player/gel/gel_costume_fitter.gd")
const HairCatalog := preload("res://scripts/gameplay/player/gel/gel_hair_catalog.gd")
const HairAttachment := preload("res://scripts/gameplay/player/gel/gel_hair_attachment.gd")
const Presets := preload("res://scripts/gameplay/player/gel/gel_proportion_presets.gd")
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const BodyShaper := preload("res://scripts/gameplay/player/gel/gel_body_shaper.gd")

const DEEP_PENETRATION_M: float = 0.025
const EXPECTED_COMBINATIONS: int = 12 * 10 * (6 + Proportions.PACKET_SIZE * 2)

var _failures: int = 0
var _combinations: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gel: Node3D = GEL_SCENE.instantiate()
	root.add_child(gel)
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(gel)
	var shaper := BodyShaper.new()
	_expect(skeleton != null and shaper.setup(gel), "the cosmetic matrix uses the real gel rig")
	if skeleton == null:
		gel.free()
		quit(_failures)
		return

	var cases: Array[Dictionary] = _proportion_cases()
	_expect(cases.size() == 6 + Proportions.PACKET_SIZE * 2,
		"the matrix contains six presets and both endpoints of all seventeen sliders")
	for costume_id: StringName in CostumeCatalog.ids():
		var costume: Node3D = CostumeLibrary.build_costume(costume_id)
		gel.add_child(costume)
		var fitter := CostumeFitter.new()
		_expect(fitter.setup(costume, gel), "%s joins the fitted cosmetic matrix" % costume_id)
		var head_pieces: Array[MeshInstance3D] = _head_pieces(costume)
		var rule: int = _hat_rule(costume)
		for hair_definition: Dictionary in HairCatalog.HAIRSTYLES:
			var hair_id: StringName = hair_definition[&"id"]
			var attachment: BoneAttachment3D = HairAttachment.new()
			_expect(attachment.setup(skeleton, hair_id, 4),
				"%s attaches while testing %s" % [hair_id, costume_id])
			attachment.call(&"set_hat_rule", rule)
			for sample: Dictionary in cases:
				var proportions: GelBodyProportions = sample[&"proportions"]
				shaper.apply(proportions)
				fitter.apply(proportions)
				attachment.apply_proportions(proportions)
				skeleton.force_update_all_bone_transforms()
				_check_combination(costume_id, hair_id, String(sample[&"label"]),
					attachment.hair_root(), head_pieces, rule)
			attachment.free()
		costume.free()

	_expect(_combinations == EXPECTED_COMBINATIONS,
		"the complete 12 x 10 x 40 matrix executes all 4,800 combinations")
	print("MEASURE: %d costume x hair x proportion combinations" % _combinations)
	gel.free()
	if _failures == 0:
		print("PASS: no costume, hairstyle and proportion combination deeply intersects")
	quit(_failures)


func _proportion_cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for preset_id: StringName in Presets.preset_ids():
		var proportions: GelBodyProportions = Presets.load_preset(preset_id)
		_expect(proportions != null, "%s preset loads for the cosmetic matrix" % preset_id)
		if proportions != null:
			result.append({&"label": "preset_%s" % preset_id, &"proportions": proportions})
	for definition: Dictionary in Proportions.parameter_definitions():
		var parameter_name: StringName = definition[&"name"]
		for endpoint: StringName in [&"minimum", &"maximum"]:
			var proportions := Proportions.new()
			proportions.set(parameter_name, float(definition[endpoint]))
			result.append({
				&"label": "%s_%s" % [parameter_name, endpoint],
				&"proportions": proportions,
			})
	return result


func _check_combination(
	costume_id: StringName,
	hair_id: StringName,
	case_label: String,
	hair: Node3D,
	head_pieces: Array[MeshInstance3D],
	rule: int
) -> void:
	_combinations += 1
	var label := "%s + %s + %s" % [costume_id, hair_id, case_label]
	_expect(hair != null and hair.global_transform.is_finite(), "%s stays finite and attached" % label)
	if hair == null:
		return
	if rule == HairAttachment.HatRule.HIDE:
		_expect(not hair.visible, "%s hides hair below a closed headpiece" % label)
		return
	_expect(hair.visible, "%s keeps compatible hair visible" % label)
	for hair_piece: MeshInstance3D in _mesh_pieces(hair):
		var hair_bounds: AABB = hair_piece.global_transform * hair_piece.get_aabb()
		for costume_piece: MeshInstance3D in head_pieces:
			var costume_bounds: AABB = costume_piece.global_transform * costume_piece.get_aabb()
			var overlap: AABB = hair_bounds.intersection(costume_bounds)
			var deeply_intersects: bool = overlap.has_volume() \
				and overlap.size.x > DEEP_PENETRATION_M \
				and overlap.size.y > DEEP_PENETRATION_M \
				and overlap.size.z > DEEP_PENETRATION_M
			_expect(not deeply_intersects,
				"%s: %s penetrates %s by %s" % [label, hair_piece.name, costume_piece.name, overlap.size])


func _head_pieces(costume: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if costume.get_meta(&"gel_costume_id") == &"skeleton":
		return result
	for piece: MeshInstance3D in _mesh_pieces(costume):
		if piece.get_meta(&"gel_costume_bone", &"") == &"head":
			result.append(piece)
	return result


func _mesh_pieces(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		result.append_array(_mesh_pieces(child))
	return result


func _hat_rule(costume: Node3D) -> int:
	match costume.get_meta(&"gel_hat_rule", &"none"):
		&"compress": return HairAttachment.HatRule.COMPRESS
		&"hide": return HairAttachment.HatRule.HIDE
		_: return HairAttachment.HatRule.NONE


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

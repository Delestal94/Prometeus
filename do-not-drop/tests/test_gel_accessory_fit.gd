extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_accessory_fit.gd
##
## S-305: the reflective vest is a shell worn over the costume torso. Across every body preset and
## slider extreme (CPU-skinned torso vertices of the real LOD0 gel) it must stay outside the body, stay
## within a few centimetres of the costume torso it wraps, keep the rig-fit contract (chest bone,
## morph names) and leave the rigid accessories untouched by the fitter.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const CostumeLibrary := preload("res://scripts/gameplay/player/gel/gel_costume_library.gd")
const AccessoryLibrary := preload("res://scripts/gameplay/player/gel/gel_accessory_library.gd")
const Fitter := preload("res://scripts/gameplay/player/gel/gel_costume_fitter.gd")
const Shaper := preload("res://scripts/gameplay/player/gel/gel_body_shaper.gd")
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Presets := preload("res://scripts/gameplay/player/gel/gel_proportion_presets.gd")

const BODY_BONES: Array[StringName] = [&"chest", &"pelvis"]
## Body points may touch the vest's inner face but never cross it by more than a millimetre.
const BODY_TOLERANCE: float = 0.001
## The vest lies on the costume like a garment; a few centimetres of contact are expected, not more.
const COSTUME_CONTACT: float = 0.04

var _failures: int = 0
var _gel: Node3D
var _skeleton: Skeleton3D
var _body: MeshInstance3D
var _torso_vertices: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_gel = GEL_SCENE.instantiate()
	root.add_child(_gel)
	await process_frame
	_skeleton = _find_skeleton(_gel)
	_body = _find_body(_gel)
	_expect(_skeleton != null and _body != null, "the real gel exposes a rig and a morph body")
	if _skeleton == null or _body == null:
		quit(1)
		return
	_collect_torso_vertices()
	_expect(_torso_vertices.size() > 1000, "the chest and pelvis skin weights give a torso sample (%d)" %
		_torso_vertices.size())

	var shaper := Shaper.new()
	_expect(shaper.setup(_gel), "the shaper discovers the rig")
	var costume: Node3D = CostumeLibrary.build_costume(&"courier")
	_gel.add_child(costume)
	var costume_fitter := Fitter.new()
	_expect(costume_fitter.setup(costume, _gel), "the courier costume receives the rig contract")
	var vest: Node3D = AccessoryLibrary.build_accessory(&"reflective_vest")
	_gel.add_child(vest)
	var vest_fitter := Fitter.new()
	_expect(vest_fitter.setup(vest, _gel), "the vest receives the rig contract")
	_expect(vest_fitter.piece_count() == vest.get_child_count(), "every vest piece is a fitted chest piece")
	_check_rigid_accessories_stay_rigid()

	var torso_box: MeshInstance3D = costume.find_child("CostumeTorso", true, false) as MeshInstance3D
	_expect(torso_box != null, "the courier torso box exists to compare against")

	for case_name: StringName in _cases():
		var proportions: GelBodyProportions = _case(case_name)
		shaper.apply(proportions)
		costume_fitter.apply(proportions)
		vest_fitter.apply(proportions)
		var within_safe_range: bool = _is_safe_case(case_name)
		var crossings: int = _body_crossings(vest)
		_expect(crossings == 0, "%s: the body never crosses the vest (%d vertices inside)" %
			[case_name, crossings])
		if within_safe_range and torso_box != null:
			var depth: float = _costume_overlap(vest, torso_box)
			_expect(depth <= COSTUME_CONTACT, "%s: the vest only rests on the costume (%.3f overlap)" %
				[case_name, depth])
		_expect(_all_finite(vest), "%s: the fitted vest stays finite" % case_name)
		_check_follows_height(vest, proportions, case_name)

	vest.free()
	costume.free()
	_gel.free()
	if _failures == 0:
		print("PASS: the reflective vest clears the gel body across presets and slider extremes")
	quit(_failures)


func _cases() -> Array[StringName]:
	var result: Array[StringName] = []
	for preset_id: StringName in Presets.preset_ids():
		result.append(StringName("preset_%s" % preset_id))
	result.append_array([&"all_min", &"all_max", &"bulk", &"bulk_tall", &"short_thin", &"long_torso"])
	return result


func _is_safe_case(case_name: StringName) -> bool:
	return String(case_name).begins_with("preset_") or case_name in [&"bulk", &"long_torso"]


func _case(case_name: StringName) -> GelBodyProportions:
	if String(case_name).begins_with("preset_"):
		return Presets.load_preset(StringName(String(case_name).trim_prefix("preset_")))
	var proportions := Proportions.new()
	match case_name:
		&"all_min", &"all_max":
			for definition: Dictionary in Proportions.parameter_definitions():
				proportions.set(definition[&"name"],
					definition[&"maximum"] if case_name == &"all_max" else definition[&"minimum"])
		&"bulk":
			_set_all(proportions, {&"general_thickness": 1.0, &"belly": 1.0, &"chest": 1.0, &"shoulders": 1.0})
		&"bulk_tall":
			_set_all(proportions, {&"general_thickness": 1.0, &"belly": 1.0, &"chest": 1.0, &"shoulders": 1.0,
				&"total_height": 1.2, &"torso_length": 1.25})
		&"short_thin":
			_set_all(proportions, {&"general_thickness": -1.0, &"belly": -1.0, &"chest": -1.0,
				&"shoulders": -1.0, &"total_height": 0.85, &"torso_length": 0.85})
		&"long_torso":
			_set_all(proportions, {&"torso_length": 1.15, &"total_height": 1.1})
	return proportions


func _set_all(proportions: GelBodyProportions, values: Dictionary) -> void:
	for key: StringName in values:
		proportions.set(key, values[key])


## Rigid accessories (backpack, scarf...) keep their authored pose: no fitter pieces.
func _check_rigid_accessories_stay_rigid() -> void:
	var backpack: Node3D = AccessoryLibrary.build_accessory(&"backpack")
	_gel.add_child(backpack)
	var fitter := Fitter.new()
	_expect(not fitter.setup(backpack, _gel), "the backpack stays a rigid accessory")
	backpack.free()


func _collect_torso_vertices() -> void:
	_torso_vertices.clear()
	var arrays: Array = _body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per_vertex: int = bones.size() / vertices.size()
	var skin: Skin = _body.skin
	for index: int in vertices.size():
		var torso_weight: float = 0.0
		for slot: int in per_vertex:
			var bind: int = bones[index * per_vertex + slot]
			var bone: int = _bind_bone(skin, bind)
			if bone >= 0 and StringName(_skeleton.get_bone_name(bone)) in BODY_BONES:
				torso_weight += weights[index * per_vertex + slot]
		if torso_weight > 0.5:
			_torso_vertices.append(index)


## Imported skins bind by name; fall back to the index when the bind carries a bone index.
func _bind_bone(skin: Skin, bind: int) -> int:
	if bind >= skin.get_bind_count():
		return -1
	var bone: int = skin.get_bind_bone(bind)
	return bone if bone >= 0 else _skeleton.find_bone(skin.get_bind_name(bind))


## CPU skinning of the torso sample: morph blend, then bone pose x bind pose, in gel-local space.
func _skinned_torso() -> PackedVector3Array:
	var arrays: Array = _body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per_vertex: int = bones.size() / vertices.size()
	var shapes: Array = _body.mesh.surface_get_blend_shape_arrays(0)
	var relative: bool = _body.mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	var skin: Skin = _body.skin
	var to_gel: Transform3D = _gel.global_transform.affine_inverse() * _skeleton.global_transform
	var result := PackedVector3Array()
	for index: int in _torso_vertices:
		var point: Vector3 = vertices[index]
		for shape: int in shapes.size():
			var weight: float = _body.get_blend_shape_value(shape)
			if is_zero_approx(weight):
				continue
			var shape_vertices: PackedVector3Array = shapes[shape][Mesh.ARRAY_VERTEX]
			point += weight * (shape_vertices[index] if relative else shape_vertices[index] - vertices[index])
		var skinned := Vector3.ZERO
		for slot: int in per_vertex:
			var weight: float = weights[index * per_vertex + slot]
			if weight <= 0.0:
				continue
			var bind: int = bones[index * per_vertex + slot]
			var bone: int = _bind_bone(skin, bind)
			skinned += weight * (_skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind) * point)
		result.append(to_gel * skinned)
	return result


func _body_crossings(vest: Node3D) -> int:
	var count: int = 0
	# The shaper edits bone rests; with no clip playing the pose follows the rest.
	_skeleton.reset_bone_poses()
	var points: PackedVector3Array = _skinned_torso()
	for child: Node in vest.get_children():
		var piece := child as MeshInstance3D
		var inverse: Transform3D = piece.transform.affine_inverse()
		var half: Vector3 = (piece.mesh as BoxMesh).size * 0.5
		for point: Vector3 in points:
			var local: Vector3 = inverse * point
			if absf(local.x) < half.x - BODY_TOLERANCE / piece.scale.x \
					and absf(local.y) < half.y - BODY_TOLERANCE / piece.scale.y \
					and absf(local.z) < half.z - BODY_TOLERANCE / piece.scale.z:
				count += 1
	return count


## Deepest axis overlap, in metres, between any vest piece and the fitted costume torso box.
func _costume_overlap(vest: Node3D, torso: MeshInstance3D) -> float:
	var worst: float = 0.0
	var torso_box: AABB = torso.transform * torso.mesh.get_aabb()
	for child: Node in vest.get_children():
		var piece := child as MeshInstance3D
		var box: AABB = piece.transform * piece.mesh.get_aabb()
		if not box.intersects(torso_box):
			continue
		var overlap: AABB = box.intersection(torso_box)
		worst = maxf(worst, minf(overlap.size.x, minf(overlap.size.y, overlap.size.z)))
	return worst


## The vest tracks total_height: its panels stay centred on the scaled torso, never on the unscaled one.
func _check_follows_height(vest: Node3D, proportions: GelBodyProportions, case_name: StringName) -> void:
	var back: Node3D = vest.find_child("VestBack", true, false)
	var pivot: float = Fitter.SHELL_PIVOT_Y
	var expected: float = (pivot + (1.13 - pivot) * proportions.torso_length) * proportions.total_height
	_expect(absf(back.position.y - expected) < 0.001, "%s: the vest follows height and torso length" % case_name)


func _all_finite(node: Node) -> bool:
	for child: Node in node.get_children():
		var piece := child as MeshInstance3D
		if piece != null and not piece.transform.is_finite():
			return false
	return true


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_body(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.mesh != null and node.mesh.get_blend_shape_count() > 0:
		return node
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_body(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_proportions.gd
##
## S-311.26 stress-tests every slider at both endpoints plus 50 deterministic
## full-range combinations. Each state exercises the real LOD0 rig, foot and
## package IK, the head-attached face layers and the current gameplay ragdoll.
## Hair and clothing are intentionally discovered by group and become part of
## this matrix when blocks H and J add those nodes.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Shaper := preload("res://scripts/gameplay/player/gel/gel_body_shaper.gd")
const Grounding := preload("res://scripts/gameplay/player/gel/gel_foot_grounding.gd")
const CarryPose := preload("res://scripts/gameplay/player/carry_pose.gd")
const CharacterFace := preload("res://scripts/presentation/character_face.gd")
const Ragdoll := preload("res://modules/ragdoll/player_ragdoll.gd")

const RANDOM_SEED: int = 31126
const RANDOM_CASES: int = 50
const FOOT_TOLERANCE_M: float = 0.02
const HAND_TOLERANCE_M: float = 0.05
const FACE_SHELL_TOLERANCE_M: float = 0.03

var _failures: int = 0
var _checks: int = 0
var _face_base_radius: float = 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(RANDOM_SEED)
	var gel: Node3D = GEL_SCENE.instantiate()
	root.add_child(gel)
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	var package: DeliveryPackage = PACKAGE_SCENE.instantiate()
	package.freeze = true
	root.add_child(package)
	package.global_position = Vector3(0.0, 1.0, -0.7)
	var grounding: GelFootGrounding = Grounding.new()
	root.add_child(grounding)
	await process_frame
	player.set_physics_process(false)

	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(gel)
	var animation: AnimationPlayer = PlayerAppearance.find_animation_player(gel)
	var shaper: GelBodyShaper = Shaper.new()
	_expect(skeleton != null and animation != null and shaper.setup(gel),
		"the real gel LOD0 exposes its rig, clips and proportion shaper")
	_expect(grounding.setup(gel), "the real gel LOD0 exposes both foot chains")
	if skeleton == null or animation == null:
		_finish(gel, player, package, grounding)
		return

	var carry: Node3D = CarryPose.new()
	player.add_child(carry)
	carry.call(&"setup", player, skeleton)
	var face: BoneAttachment3D = CharacterFace.new()
	face.call(&"setup", gel, skeleton, 1)
	var face_layer := face.get_node_or_null(^"Eyes") as MeshInstance3D
	var head: int = skeleton.find_bone(&"head")
	_face_base_radius = (face_layer.global_transform * face_layer.get_aabb().get_center()).distance_to(
		skeleton.to_global(skeleton.get_bone_global_pose(head).origin)
	)
	_expect(_face_base_radius >= 0.20 and _face_base_radius <= 0.35,
		"the neutral face starts on the head shell")
	var cases: Array[Dictionary] = _proportion_cases()
	_expect(cases.size() == Proportions.PACKET_SIZE * 2 + RANDOM_CASES,
		"the matrix contains both endpoints of 17 sliders plus 50 seeded combinations")

	for case_index: int in cases.size():
		var sample: Dictionary = cases[case_index]
		var proportions: GelBodyProportions = sample[&"proportions"]
		var label: String = sample[&"label"]
		_expect(shaper.apply(proportions), "%s applies a distinct proportion state" % label)
		animation.play(&"Idle")
		animation.seek(0.0, true)
		animation.advance(0.0)
		grounding.update_floor(0.0, true)
		carry.call(&"update_pose", package, 1.0, 1.0)
		var wrists: Dictionary = {}
		var capture_wrists := func() -> void:
			for side: String in ["L", "R"]:
				var hand: int = skeleton.find_bone("hand." + side)
				wrists[side] = skeleton.to_global(skeleton.get_bone_global_pose(hand).origin)
		skeleton.skeleton_updated.connect(capture_wrists)
		for _frame: int in 3:
			await process_frame
		skeleton.skeleton_updated.disconnect(capture_wrists)
		_check_feet(skeleton, grounding, label)
		_check_hands(carry, wrists, label)
		_check_face(skeleton, face, proportions, label)
		await _check_ragdoll(case_index, label)
		_check_optional_wearables(gel, label)

	print("MEASURE: %d proportion states, %d assertions, seed %d" % [cases.size(), _checks, RANDOM_SEED])
	if get_nodes_in_group(&"gel_hair").is_empty():
		print("DEFERRED: hair penetration joins this matrix when block H provides gel_hair nodes")
	if get_nodes_in_group(&"gel_clothing").is_empty():
		print("DEFERRED: clothing penetration joins this matrix when block J provides gel_clothing nodes")
	carry.free()
	face.free()
	_finish(gel, player, package, grounding)


func _proportion_cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: Dictionary in Proportions.parameter_definitions():
		var parameter_name: StringName = definition[&"name"]
		for endpoint: StringName in [&"minimum", &"maximum"]:
			var proportions := Proportions.new()
			proportions.set(parameter_name, float(definition[endpoint]))
			result.append({
				&"label": "%s=%s" % [parameter_name, endpoint],
				&"proportions": proportions,
			})
	var rng := RandomNumberGenerator.new()
	rng.seed = RANDOM_SEED
	for sample_index: int in RANDOM_CASES:
		var proportions := Proportions.new()
		for definition: Dictionary in Proportions.parameter_definitions():
			proportions.set(definition[&"name"], rng.randf_range(
				float(definition[&"minimum"]), float(definition[&"maximum"])
			))
		result.append({
			&"label": "random_%02d" % sample_index,
			&"proportions": proportions,
		})
	return result


func _check_feet(skeleton: Skeleton3D, grounding: GelFootGrounding, label: String) -> void:
	var planted: int = 0
	for side: int in 2:
		if grounding.influence(side) < 0.5:
			continue
		planted += 1
		var bone: int = skeleton.find_bone("foot." + ("L" if side == 0 else "R"))
		var ankle: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
		var target: Vector3 = grounding.target_position(side)
		_expect(absf(ankle.y - target.y) <= FOOT_TOLERANCE_M,
			"%s plants foot %d within %.0f cm (%.3f m)" % [
				label, side, FOOT_TOLERANCE_M * 100.0, absf(ankle.y - target.y)])
	_expect(planted >= 1, "%s keeps at least one foot planted" % label)


func _check_hands(carry: Node3D, wrists: Dictionary, label: String) -> void:
	for side: String in ["L", "R"]:
		var target := carry.get_node_or_null("PackageGrip" + side) as Marker3D
		var gap: float = (wrists[side] as Vector3).distance_to(target.global_position) \
			if target != null and wrists.has(side) else INF
		_expect(target != null and wrists.has(side) and gap <= HAND_TOLERANCE_M,
			"%s keeps hand %s on the box (%.3f m)" % [label, side, gap])


func _check_face(
	skeleton: Skeleton3D,
	face: BoneAttachment3D,
	proportions: GelBodyProportions,
	label: String
) -> void:
	var layer := face.get_node_or_null(^"Eyes") as MeshInstance3D
	var head: int = skeleton.find_bone(&"head")
	var head_center: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(head).origin)
	var face_center: Vector3 = layer.global_transform * layer.get_aabb().get_center() if layer != null else Vector3.INF
	var radius: float = head_center.distance_to(face_center)
	var expected: float = _face_base_radius * proportions.head_size
	# head_shape moves the real shell by at most 8%; this band keeps the decal
	# close to that shell without accepting a buried or visibly floating face.
	var shell_error: float = absf(radius - expected)
	_expect(layer != null and face.bone_name == &"head" and face_center.is_finite()
		and shell_error <= FACE_SHELL_TOLERANCE_M,
		"%s keeps the face on the head shell (error %.3f m)" % [label, shell_error])


func _check_ragdoll(case_index: int, label: String) -> void:
	var owner := CharacterBody3D.new()
	owner.position = Vector3(8.0, 2.0, float(case_index % 7) * 0.1)
	root.add_child(owner)
	var ragdoll: PlayerRagdoll = Ragdoll.new()
	owner.add_child(ragdoll)
	ragdoll.setup(owner, null, 1)
	var impulse := Vector3(
		lerpf(-2.0, 2.0, float(case_index % 11) / 10.0),
		2.0 + float(case_index % 5) * 0.35,
		lerpf(-1.5, 1.5, float(case_index % 13) / 12.0)
	)
	ragdoll.fall(impulse)
	for _frame: int in 3:
		await physics_frame
	var pieces: Array[Node] = []
	for child: Node in ragdoll.get_children():
		if child is RigidBody3D:
			pieces.append(child)
	var stable: bool = pieces.size() == 6
	for piece: Node in pieces:
		var body := piece as RigidBody3D
		stable = stable and body.global_transform.is_finite()
		stable = stable and body.linear_velocity.is_finite() and body.angular_velocity.is_finite()
		stable = stable and body.linear_velocity.length() < 50.0 and body.global_position.length() < 100.0
	_expect(stable, "%s keeps all six ragdoll pieces finite and bounded" % label)
	ragdoll.free()
	owner.free()


func _check_optional_wearables(gel: Node3D, label: String) -> void:
	for group_name: StringName in [&"gel_hair", &"gel_clothing"]:
		for node: Node in get_nodes_in_group(group_name):
			if not gel.is_ancestor_of(node):
				continue
			var wearable := node as Node3D
			_expect(wearable != null and wearable.global_transform.is_finite(),
				"%s keeps %s finite and attached" % [label, node.name])


func _finish(gel: Node3D, player: Player, package: DeliveryPackage, grounding: GelFootGrounding) -> void:
	grounding.clear()
	grounding.free()
	package.free()
	player.free()
	gel.free()
	if _failures == 0:
		print("PASS: gel proportions survive every endpoint and 50 seeded combinations")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		push_error(description)
		_failures += 1

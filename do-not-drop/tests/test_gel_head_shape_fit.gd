extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_head_shape_fit.gd
## S-311.16 follow-up: rigid head attachments follow the real head_shape morph of
## gel_body_lod0.glb (+1 narrower and taller about GelFace.HEAD_SHAPE_CENTRE, -1
## the opposite). Checks the asset's head vertices at +/-1 against
## GelFace.head_shape_fit, then that hair, eyebrows, costume head pieces and the
## ragdoll head sphere move in that same direction.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const HairAttachment := preload("res://scripts/gameplay/player/gel/gel_hair_attachment.gd")
const CostumeLibrary := preload("res://scripts/gameplay/player/gel/gel_costume_library.gd")
const CostumeFitter := preload("res://scripts/gameplay/player/gel/gel_costume_fitter.gd")
const Ragdoll := preload("res://scripts/gameplay/player/gel/gel_active_ragdoll.gd")
## Above the neck junction pinch (build_gel_body.py: up to z = 1.45) the morph is
## a pure scale about its centre.
const SHELL_MIN_Y: float = 1.46
const TOLERANCE_M: float = 0.001
## Rest head bounds measured on the asset (y >= 1.40): 0.489 m wide, top 1.755 m.
const REST_WIDTH: float = 0.489
const REST_TOP: float = 1.755

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model: Node3D = GEL_SCENE.instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(model)
	var head: int = skeleton.find_bone(&"head")
	_expect(skeleton.get_bone_global_rest(head).origin.is_equal_approx(GelFace.HEAD_BONE_ORIGIN),
		"GelFace.HEAD_BONE_ORIGIN matches the asset's head bone")
	_check_asset_morph(model)
	await _check_head_visuals(skeleton)
	_check_costume(model)
	_check_ragdoll()
	model.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: hair, face hair, costume and ragdoll follow the real head_shape morph")
	quit(_failures)


## The asset's head shell at +/-1 is head_shape_fit applied to the rest shell,
## so attachments that use the fit land on the real bounds.
func _check_asset_morph(model: Node3D) -> void:
	var body: MeshInstance3D = _morph_body(model)
	_expect(body != null, "the gel asset has a head_shape morph")
	if body == null:
		return
	var rest: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var shape: int = body.find_blend_shape_by_name(&"head_shape")
	var target: PackedVector3Array = body.mesh.surface_get_blend_shape_arrays(0)[shape][Mesh.ARRAY_VERTEX]
	var relative: bool = body.mesh.get_blend_shape_mode() == Mesh.BLEND_SHAPE_MODE_RELATIVE
	var bone_from_model := Transform3D(Basis.IDENTITY, -GelFace.HEAD_BONE_ORIGIN)
	for weight: float in [-1.0, 1.0]:
		var fit: Transform3D = bone_from_model.affine_inverse() * GelFace.head_shape_fit(weight) \
			* bone_from_model
		var worst: float = 0.0
		var real := AABB()
		var first: bool = true
		for index: int in rest.size():
			if rest[index].y < SHELL_MIN_Y:
				continue
			var offset: Vector3 = target[index] if relative else target[index] - rest[index]
			var point: Vector3 = rest[index] + offset * weight
			worst = maxf(worst, point.distance_to(fit * rest[index]))
			real = AABB(point, Vector3.ZERO) if first else real.expand(point)
			first = false
		print("head_shape %+.0f: real head %s, worst vertex off the fit %.5f m" % [weight, real, worst])
		_expect(not first and worst < TOLERANCE_M,
			"head_shape %+.0f: the fit matches every head vertex (worst %.4f m)" % [weight, worst])
		var narrow_and_tall: bool = real.size.x < REST_WIDTH and real.end.y > REST_TOP
		var wide_and_short: bool = real.size.x > REST_WIDTH and real.end.y < REST_TOP
		_expect(narrow_and_tall if weight > 0.0 else wide_and_short,
			"head_shape %+.0f has the measured direction (width %.3f, top %.3f)"
			% [weight, real.size.x, real.end.y])


## Hair and eyebrows keep the points that touch the rest shell (top and side) on
## the morphed shell.
func _check_head_visuals(skeleton: Skeleton3D) -> void:
	var hair := HairAttachment.new()
	_expect(hair.setup(skeleton, &"quiff", 1), "hair attaches to the real head")
	var brows := BoneAttachment3D.new()
	brows.bone_name = &"head"
	skeleton.add_child(brows)
	var brow_visual := Node3D.new()
	brows.add_child(brow_visual)
	var visuals: Array[Node3D] = [hair.hair_root(), brow_visual]
	var proportions := GelBodyProportions.new()
	var centre: Vector3 = GelFace.HEAD_SHAPE_CENTRE
	var probes: Array[Vector3] = [Vector3(0.0, REST_TOP, 0.0), Vector3(REST_WIDTH * 0.5, centre.y, 0.0)]
	proportions.head_shape = 0.0
	_fit_visuals(hair, brow_visual, proportions)
	await process_frame
	var anchors: Dictionary = {}
	for visual: Node3D in visuals:
		var to_local: Transform3D = visual.global_transform.affine_inverse()
		anchors[visual] = probes.map(func(probe: Vector3) -> Vector3: return to_local * probe)
	for weight: float in [-1.0, 1.0]:
		var axes: Vector3 = GelFace.head_shape_axes(weight)
		proportions.head_shape = weight
		_fit_visuals(hair, brow_visual, proportions)
		await process_frame
		for visual: Node3D in visuals:
			var label: String = "hair" if visual == hair.hair_root() else "eyebrows"
			for index: int in probes.size():
				var real: Vector3 = centre + (probes[index] - centre) * axes
				var moved: Vector3 = visual.global_transform * (anchors[visual][index] as Vector3)
				_expect(moved.distance_to(real) < TOLERANCE_M,
					"%s stays on the real head at head_shape %+.0f (%s, expected %s)"
					% [label, weight, moved, real])
	hair.queue_free()
	brows.queue_free()


func _fit_visuals(hair: GelHairAttachment, brow_visual: Node3D, proportions: GelBodyProportions) -> void:
	hair.apply_proportions(proportions)
	HairAttachment.fit_head_visual(brow_visual, proportions)


## Costume head pieces scale and move about the morph centre: +1 narrower with a
## crown piece higher, -1 wider and lower.
func _check_costume(model: Node3D) -> void:
	var costume: Node3D = CostumeLibrary.build_costume(&"chef")
	model.add_child(costume)
	var fitter = CostumeFitter.new()
	_expect(fitter.setup(costume, model), "the chef costume fits the gel body")
	var toque := costume.find_child("toque", true, false) as MeshInstance3D
	_expect(toque != null, "the chef costume has a toque")
	if toque == null:
		costume.queue_free()
		return
	var rest_origin: Vector3 = toque.position
	var rest_scale: Vector3 = toque.basis.get_scale()
	var centre_y: float = GelFace.HEAD_SHAPE_CENTRE.y
	for weight: float in [-1.0, 1.0]:
		var proportions := GelBodyProportions.new()
		proportions.head_shape = weight
		fitter.apply(proportions)
		var axes: Vector3 = GelFace.head_shape_axes(weight)
		var expected_y: float = centre_y + (rest_origin.y - centre_y) * axes.y
		_expect(is_equal_approx(toque.position.y, expected_y)
			and toque.basis.get_scale().is_equal_approx(rest_scale * axes)
			and (toque.position.y > rest_origin.y) == (weight > 0.0),
			"the toque follows head_shape %+.0f (y %.3f, scale %s)"
			% [weight, toque.position.y, toque.basis.get_scale()])
	costume.queue_free()


## The ragdoll head sphere follows the real width: smaller at +1, larger at -1.
func _check_ragdoll() -> void:
	var ragdoll = Ragdoll.new()
	var values: Dictionary = GelBodyProportions.new().as_dictionary()
	var rest: float = ragdoll.call(&"_thickness_factor", &"head", values)
	values[&"head_shape"] = 1.0
	var narrow: float = ragdoll.call(&"_thickness_factor", &"head", values)
	values[&"head_shape"] = -1.0
	var wide: float = ragdoll.call(&"_thickness_factor", &"head", values)
	_expect(is_equal_approx(narrow, rest * GelFace.head_shape_axes(1.0).x) and wide > rest,
		"the ragdoll head follows the real width (%.3f / %.3f / %.3f)" % [wide, rest, narrow])
	ragdoll.free()


func _morph_body(model: Node3D) -> MeshInstance3D:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var body := node as MeshInstance3D
		if body.find_blend_shape_by_name(&"head_shape") >= 0:
			return body
	return null


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

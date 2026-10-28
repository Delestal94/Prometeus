extends SceneTree
## S-311.94: a hard directional collision exceeds ordinary contact squash,
## rebounds past rest and always stays inside positive, finite mesh scales.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const ContactDeformation := preload(
	"res://scripts/gameplay/player/gel/gel_contact_deformation.gd"
)

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var actor := CharacterBody3D.new()
	actor.name = "ExtremeImpactActor"
	root.add_child(actor)
	var model: Node3D = GEL_SCENE.instantiate() as Node3D
	actor.add_child(model)
	PlayerAppearance.set_gel_material(model, false)
	var controller: Node = ContactDeformation.new()
	actor.add_child(controller)
	_expect(controller.setup(model), "the real gel mesh accepts extreme impact deformation")
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(model)
	var transform_before: Transform3D = actor.transform
	var collision_layer_before: int = actor.collision_layer

	controller.trigger_contact(Vector3.RIGHT, ContactDeformation.FULL_IMPACT_SPEED * 4.0)
	_expect(controller.extreme_active()
			and is_equal_approx(controller.extreme_amount(), 1.0),
		"a hard contact reaches the capped extreme compression")
	var packed: float = float(mesh.get_instance_shader_parameter(&"gel_contact_compression"))
	_expect(is_equal_approx(packed, 1.25),
		"the existing contact uniform packs the capped extreme state")
	_check_safe_scales(controller.deformation_scales(), "maximum compression")

	var saw_rebound: bool = false
	var maximum_abs_amount: float = 0.0
	for _frame: int in 480:
		controller.advance(1.0 / 120.0)
		var amount: float = controller.extreme_amount()
		maximum_abs_amount = maxf(maximum_abs_amount, absf(amount))
		saw_rebound = saw_rebound or amount < -0.08
		_check_safe_scales(controller.deformation_scales(), "spring timeline")
	_expect(saw_rebound, "the extreme compression returns through a visible stretch rebound")
	_expect(maximum_abs_amount <= ContactDeformation.MAX_EXTREME_AMOUNT,
		"the spring never exceeds its authored deformation cap")
	_expect(not controller.extreme_active() and is_zero_approx(float(
		mesh.get_instance_shader_parameter(&"gel_contact_compression"))),
		"the damped rebound returns to the exact undeformed shader state")

	controller.trigger_extreme_impact(Vector3.LEFT, INF)
	controller.advance(5.0)
	_expect(is_finite(controller.extreme_amount())
			and absf(controller.extreme_amount()) <= ContactDeformation.MAX_EXTREME_AMOUNT,
		"invalidly large speed and frame time remain finite and capped")
	_check_safe_scales(controller.deformation_scales(), "large frame")
	controller.reset_deformation()
	controller.trigger_contact(Vector3.FORWARD, 4.0)
	_expect(not controller.extreme_active()
			and controller.deformation_amount() <= ContactDeformation.MAX_COMPRESSION,
		"ordinary contact keeps the existing smaller deformation path")

	_expect(actor.transform == transform_before and actor.collision_layer == collision_layer_before,
		"the extreme visual never changes gameplay transform or collision")
	_check_shader_variants(model, mesh)
	actor.free()
	if _failures == 0:
		print("PASS: extreme impact compresses, rebounds and settles inside safe mesh bounds")
	quit(_failures)


func _check_safe_scales(scales: Vector3, context: String) -> void:
	_expect(scales.is_finite() and scales.x >= ContactDeformation.EXTREME_AXIS_MIN
			and scales.x <= ContactDeformation.EXTREME_AXIS_MAX
			and scales.y > 0.0 and scales.z > 0.0,
		"%s keeps every axis finite and positive" % context)
	_expect(absf(scales.x * scales.y * scales.z - 1.0) < 0.00001,
		"%s preserves constant volume" % context)


func _check_shader_variants(model: Node3D, mesh: MeshInstance3D) -> void:
	for opaque: bool in [false, true]:
		PlayerAppearance.set_gel_material(model, opaque)
		var code: String = (mesh.material_override as ShaderMaterial).shader.code
		_expect(code.contains("float extreme_axis_scale = clamp(")
				and code.contains("0.36, 1.65")
				and code.contains("positive bounds"),
			"%s shader clamps the impact before transforming vertices and normals"
				% ("opaque" if opaque else "transparent"))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

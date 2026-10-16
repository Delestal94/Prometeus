extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_squash_stretch.gd
## S-311.45: acceleration-driven shader squash/stretch with constant volume.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const SquashStretch := preload("res://scripts/gameplay/player/gel/gel_squash_stretch.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model: Node3D = GEL_SCENE.instantiate() as Node3D
	root.add_child(model)
	PlayerAppearance.set_gel_material(model, false)
	var controller: Node = SquashStretch.new()
	root.add_child(controller)
	_expect(controller.setup(model), "the real gel mesh accepts its deformation controller")
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(model)
	_expect(is_zero_approx(float(mesh.get_instance_shader_parameter(&"gel_squash_stretch"))),
		"the body starts undeformed")

	controller.advance_motion(Vector3.ZERO, true, 0.1)
	controller.advance_motion(Vector3(0.0, 5.0, 0.0), false, 0.1)
	_expect(controller.deformation_amount() > 0.04, "jump takeoff stretches the body")
	_check_constant_volume(controller.deformation_scales(), "takeoff")

	controller.reset_motion()
	controller.advance_motion(Vector3(0.0, -5.0, 0.0), false, 0.1)
	controller.advance_motion(Vector3.ZERO, true, 0.1)
	_expect(controller.deformation_amount() < -0.04, "landing squashes the body")
	var landing_scales: Vector3 = controller.deformation_scales()
	_expect(landing_scales.y < 1.0 and landing_scales.x > 1.0,
		"landing compression spreads equally across both radial axes")
	_check_constant_volume(landing_scales, "landing")
	_expect(is_equal_approx(
		float(mesh.get_instance_shader_parameter(&"gel_squash_stretch")),
		controller.deformation_amount()), "the controller writes the per-instance shader uniform")

	_check_material_variants(model, mesh, controller)
	_check_instance_isolation(model)
	model.free()
	controller.free()
	if _failures == 0:
		print("PASS: gel squash/stretch reacts to takeoff and landing at constant volume")
	quit(_failures)


func _check_constant_volume(scales: Vector3, context: String) -> void:
	_expect(absf(scales.x * scales.y * scales.z - 1.0) < 0.00001,
		"%s deformation preserves volume" % context)


func _check_material_variants(model: Node3D, mesh: MeshInstance3D, controller: Node) -> void:
	var amount: float = controller.deformation_amount()
	PlayerAppearance.set_gel_material(model, true)
	_expect(float(mesh.get_instance_shader_parameter(&"gel_squash_stretch")) == amount,
		"switching to the opaque material preserves the per-instance deformation")
	var opaque_shader: String = (mesh.material_override as ShaderMaterial).shader.code
	_expect("inversesqrt(vertical_scale)" in opaque_shader,
		"the opaque fallback uses the same constant-volume vertex deformation")
	PlayerAppearance.set_gel_material(model, false)
	var transparent_shader: String = (mesh.material_override as ShaderMaterial).shader.code
	_expect("inversesqrt(vertical_scale)" in transparent_shader,
		"the transparent material deforms in its vertex shader")


func _check_instance_isolation(first_model: Node3D) -> void:
	var other_model: Node3D = GEL_SCENE.instantiate() as Node3D
	root.add_child(other_model)
	PlayerAppearance.set_gel_material(other_model, false)
	var first_mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(first_model)
	var other_mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(other_model)
	_expect(first_mesh.material_override == other_mesh.material_override,
		"deformed players still share one material resource")
	var other_parameter: Variant = other_mesh.get_instance_shader_parameter(&"gel_squash_stretch")
	var other_amount: float = float(other_parameter) if other_parameter != null else 0.0
	_expect(not is_equal_approx(
		float(first_mesh.get_instance_shader_parameter(&"gel_squash_stretch")),
		other_amount),
		"squash/stretch remains isolated per player instance")
	other_model.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

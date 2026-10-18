extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_contact_deformation.gd
## S-311.55: nearby players compress visually without changing gameplay state.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const ContactDeformation := preload("res://scripts/gameplay/player/gel/gel_contact_deformation.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var actor_a := CharacterBody3D.new()
	var actor_b := CharacterBody3D.new()
	actor_a.name = "ContactActorA"
	actor_b.name = "ContactActorB"
	actor_a.add_to_group(&"player")
	actor_b.add_to_group(&"player")
	root.add_child(actor_a)
	root.add_child(actor_b)
	actor_a.global_position = Vector3.ZERO
	actor_b.global_position = Vector3(0.70, 0.0, 0.0)
	actor_a.velocity = Vector3(2.0, 0.0, 0.0)
	actor_b.velocity = Vector3(-2.0, 0.0, 0.0)
	actor_a.collision_layer = 8
	actor_b.collision_layer = 8
	actor_a.collision_mask = 69
	actor_b.collision_mask = 69

	var model_a: Node3D = GEL_SCENE.instantiate() as Node3D
	var model_b: Node3D = GEL_SCENE.instantiate() as Node3D
	actor_a.add_child(model_a)
	actor_b.add_child(model_b)
	PlayerAppearance.set_gel_material(model_a, false)
	PlayerAppearance.set_gel_material(model_b, false)
	var controller_a: Node = ContactDeformation.new()
	var controller_b: Node = ContactDeformation.new()
	actor_a.add_child(controller_a)
	actor_b.add_child(controller_b)
	_expect(controller_a.setup(model_a) and controller_b.setup(model_b),
		"both real gel meshes accept contact deformation")

	var position_a: Vector3 = actor_a.global_position
	var position_b: Vector3 = actor_b.global_position
	var velocity_a: Vector3 = actor_a.velocity
	var velocity_b: Vector3 = actor_b.velocity
	controller_a.update_contact(actor_a, 1.0 / 60.0)
	controller_b.update_contact(actor_b, 1.0 / 60.0)
	_expect(controller_a.deformation_amount() > 0.02 and controller_b.deformation_amount() > 0.02,
		"both players compress on first contact")
	_expect(controller_a.deformation_direction().dot(controller_b.deformation_direction()) < -0.99,
		"the two bodies compress toward one another")
	_check_constant_volume(controller_a.deformation_scales(), "first player")
	_check_constant_volume(controller_b.deformation_scales(), "second player")
	_check_uniform(model_a, controller_a.deformation_amount())

	_expect(actor_a.global_position == position_a and actor_b.global_position == position_b,
		"contact deformation does not move either player")
	_expect(actor_a.velocity == velocity_a and actor_b.velocity == velocity_b,
		"contact deformation does not change gameplay velocity")
	_expect(actor_a.collision_layer == 8 and actor_a.collision_mask == 69,
		"contact deformation leaves collision layers and masks untouched")

	actor_b.global_position = Vector3(2.0, 0.0, 0.0)
	for _frame: int in 60:
		controller_a.update_contact(actor_a, 1.0 / 60.0)
		controller_b.update_contact(actor_b, 1.0 / 60.0)
	_expect(controller_a.deformation_amount() < 0.001 and controller_b.deformation_amount() < 0.001,
		"the contact compression disappears after the players separate")

	_check_material_variants(model_a)
	var packed_player: Node = PLAYER_SCENE.instantiate()
	_expect(packed_player.has_node("GelContact"), "the runtime player scene owns the visual contact controller")
	packed_player.free()
	actor_a.free()
	actor_b.free()
	if _failures == 0:
		print("PASS: player contact deformation is directional, brief and presentation-only")
	quit(_failures)


func _check_constant_volume(scales: Vector3, context: String) -> void:
	_expect(absf(scales.x * scales.y * scales.z - 1.0) < 0.00001,
		"%s contact deformation preserves volume" % context)


func _check_uniform(model: Node3D, expected: float) -> void:
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(model)
	_expect(is_equal_approx(float(mesh.get_instance_shader_parameter(&"gel_contact_compression")), expected),
		"the controller writes compression as a per-instance uniform")
	var direction := mesh.get_instance_shader_parameter(&"gel_contact_direction") as Vector3
	_expect(direction.is_equal_approx((mesh.global_basis.inverse() * Vector3.RIGHT).normalized()),
		"the contact direction is transformed into mesh-local space")


func _check_material_variants(model: Node3D) -> void:
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(model)
	PlayerAppearance.set_gel_material(model, true)
	var opaque_shader: String = (mesh.material_override as ShaderMaterial).shader.code
	_expect("inversesqrt(contact_scale)" in opaque_shader,
		"the opaque fallback uses constant-volume contact deformation")
	PlayerAppearance.set_gel_material(model, false)
	var transparent_shader: String = (mesh.material_override as ShaderMaterial).shader.code
	_expect("gel_contact_direction" in transparent_shader,
		"the transparent shader applies directional contact deformation")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

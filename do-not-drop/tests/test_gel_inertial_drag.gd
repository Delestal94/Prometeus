extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_inertial_drag.gd
## S-311.47: acceleration and turn inertia weighted from neck/shoulder anchors.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const InertialDrag := preload("res://scripts/gameplay/player/gel/gel_inertial_drag.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model: Node3D = GEL_SCENE.instantiate() as Node3D
	root.add_child(model)
	PlayerAppearance.set_gel_material(model, false)
	var drag: Node = InertialDrag.new()
	root.add_child(drag)
	_expect(drag.setup(model), "the real gel mesh accepts its inertial-drag controller")
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(model)
	_check_acceleration(drag, mesh)
	_check_turning(drag)
	_check_limits_and_settle(drag)
	_check_shader_variants(model, mesh)
	_check_instance_isolation(mesh)
	model.free()
	drag.free()
	if _failures == 0:
		print("PASS: gel head and arm vertices lag acceleration and turning")
	quit(_failures)


func _check_acceleration(drag: Node, mesh: MeshInstance3D) -> void:
	drag.reset_motion()
	drag.advance_motion(Vector3.ZERO, 0.0, 0.1)
	drag.advance_motion(Vector3(4.0, 0.0, 0.0), 0.0, 0.1)
	var acceleration: Vector4 = drag.drag_uniform()
	var local_right: Vector3 = (mesh.global_basis.inverse() * Vector3.RIGHT).normalized()
	var acceleration_drag := Vector3(acceleration.x, acceleration.y, acceleration.z)
	_expect(acceleration_drag.dot(local_right) < -0.02,
		"starting right makes soft vertices lag left")
	drag.advance_motion(Vector3.ZERO, 0.0, 0.1)
	var braking: Vector4 = drag.drag_uniform()
	var braking_drag := Vector3(braking.x, braking.y, braking.z)
	_expect(braking_drag.dot(local_right) > 0.02, "braking reverses the inertial lag")
	_expect(mesh.get_instance_shader_parameter(&"gel_inertia") == braking,
		"motion writes the per-instance inertia uniform")


func _check_turning(drag: Node) -> void:
	drag.reset_motion()
	drag.advance_motion(Vector3.ZERO, 0.0, 0.1)
	drag.advance_motion(Vector3.ZERO, 0.5, 0.1)
	_expect(drag.drag_uniform().w < -0.02, "a positive yaw makes head and arms trail the turn")


func _check_limits_and_settle(drag: Node) -> void:
	drag.reset_motion()
	drag.advance_motion(Vector3.ZERO, 0.0, 0.01)
	drag.advance_motion(Vector3(1000.0, 1000.0, 1000.0), PI, 0.01)
	var capped: Vector4 = drag.drag_uniform()
	_expect(Vector3(capped.x, capped.y, capped.z).length() <= InertialDrag.MAX_LINEAR_DRAG + 0.0001,
		"linear drag stays inside its presentation budget")
	_expect(absf(capped.w) <= InertialDrag.MAX_TURN_DRAG + 0.0001,
		"turn drag stays inside its presentation budget")
	for _frame: int in 30:
		drag.advance_motion(Vector3(1000.0, 1000.0, 1000.0), PI, 0.05)
	_expect(drag.drag_uniform().length() < 0.0001, "steady motion settles back to no lag")


func _check_shader_variants(model: Node3D, mesh: MeshInstance3D) -> void:
	var transparent_code: String = (mesh.material_override as ShaderMaterial).shader.code
	_expect("inertial_drag_mask" in transparent_code and "point - shoulder" in transparent_code,
		"the transparent shader weights head and arms by anchor distance")
	PlayerAppearance.set_gel_material(model, true)
	var opaque_code: String = (mesh.material_override as ShaderMaterial).shader.code
	_expect("inertial_drag_mask" in opaque_code and "gel_inertia.w" in opaque_code,
		"the opaque fallback includes linear and turning inertia")
	PlayerAppearance.set_gel_material(model, false)


func _check_instance_isolation(first_mesh: MeshInstance3D) -> void:
	var other_model: Node3D = GEL_SCENE.instantiate() as Node3D
	root.add_child(other_model)
	PlayerAppearance.set_gel_material(other_model, false)
	var other_mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(other_model)
	var other_drag: Node = InertialDrag.new()
	root.add_child(other_drag)
	other_drag.setup(other_model)
	other_drag.advance_motion(Vector3.ZERO, 0.0, 0.1)
	other_drag.advance_motion(Vector3(4.0, 0.0, 0.0), 0.0, 0.1)
	_expect(first_mesh.material_override == other_mesh.material_override,
		"players with different inertia still share one material")
	var first_uniform: Vector4 = first_mesh.get_instance_shader_parameter(&"gel_inertia")
	var other_uniform: Vector4 = other_mesh.get_instance_shader_parameter(&"gel_inertia")
	_expect(first_uniform.length() < 0.0001 and other_uniform.length() > 0.01,
		"inertial drag remains isolated per player")
	other_model.free()
	other_drag.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

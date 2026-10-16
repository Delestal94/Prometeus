extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_impact_waves.gd
## S-311.46: four simultaneous, per-instance shader waves from contact points.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const ImpactWaves := preload("res://scripts/gameplay/player/gel/gel_impact_waves.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model: Node3D = GEL_SCENE.instantiate() as Node3D
	root.add_child(model)
	PlayerAppearance.set_gel_material(model, false)
	var waves: Node = ImpactWaves.new()
	root.add_child(waves)
	_expect(waves.setup(model), "the real gel mesh accepts its impact-wave controller")
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(model)
	_check_world_contact(waves, mesh)
	_check_four_slots(waves, mesh)
	_check_shader_variants(model, mesh)
	_check_expiration(waves, mesh)
	_check_instance_isolation(mesh)
	model.free()
	waves.free()
	if _failures == 0:
		print("PASS: four per-instance gel impact waves propagate and expire")
	quit(_failures)


func _check_world_contact(waves: Node, mesh: MeshInstance3D) -> void:
	var local_contact := Vector3(0.18, 0.92, 0.24)
	waves.add_impact(mesh.to_global(local_contact), 0.65)
	var packed: Vector4 = mesh.get_instance_shader_parameter(&"gel_wave_0")
	_expect(Vector3(packed.x, packed.y, packed.z).is_equal_approx(local_contact),
		"a world contact is uploaded in mesh-local coordinates")
	_expect(is_zero_approx(packed.w), "a new wave starts at age zero")
	waves.advance(0.2)
	packed = mesh.get_instance_shader_parameter(&"gel_wave_0")
	_expect(is_equal_approx(packed.w, 0.2), "wave age advances in its uniform")


func _check_four_slots(waves: Node, mesh: MeshInstance3D) -> void:
	waves.clear()
	for index: int in 5:
		waves.add_local_impact(Vector3(float(index), 0.5, 0.0), 0.2 * float(index + 1))
	_expect(waves.wave_count() == 4, "at most four impacts remain active")
	_expect((waves.wave_at(0)[&"center"] as Vector3).x == 1.0,
		"a fifth impact replaces the oldest wave")
	var strengths: Vector4 = mesh.get_instance_shader_parameter(&"gel_wave_strengths")
	_expect(is_equal_approx(strengths.x, 0.4) and is_equal_approx(strengths.w, 1.0),
		"all four wave strengths occupy distinct uniform channels")
	for slot: int in 4:
		var packed: Vector4 = mesh.get_instance_shader_parameter(&"gel_wave_%d" % slot)
		_expect(packed.w >= 0.0, "wave slot %d is active" % slot)


func _check_shader_variants(model: Node3D, mesh: MeshInstance3D) -> void:
	var transparent_code: String = (mesh.material_override as ShaderMaterial).shader.code
	_expect("impact_wave(VERTEX, gel_wave_3" in transparent_code,
		"the transparent shader evaluates all four wave slots")
	PlayerAppearance.set_gel_material(model, true)
	var opaque_code: String = (mesh.material_override as ShaderMaterial).shader.code
	_expect("impact_wave(VERTEX, gel_wave_3" in opaque_code,
		"the opaque fallback evaluates the same four wave slots")
	PlayerAppearance.set_gel_material(model, false)


func _check_expiration(waves: Node, mesh: MeshInstance3D) -> void:
	waves.advance(ImpactWaves.WAVE_DURATION + 0.01)
	_expect(waves.wave_count() == 0, "expired waves free all four slots")
	var strengths: Vector4 = mesh.get_instance_shader_parameter(&"gel_wave_strengths")
	_expect(strengths.is_zero_approx(), "expired waves upload zero strength")
	for slot: int in 4:
		var packed: Vector4 = mesh.get_instance_shader_parameter(&"gel_wave_%d" % slot)
		_expect(packed.w < 0.0, "expired wave slot %d is disabled" % slot)


func _check_instance_isolation(first_mesh: MeshInstance3D) -> void:
	var other_model: Node3D = GEL_SCENE.instantiate() as Node3D
	root.add_child(other_model)
	PlayerAppearance.set_gel_material(other_model, false)
	var other_mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(other_model)
	var other_waves: Node = ImpactWaves.new()
	root.add_child(other_waves)
	other_waves.setup(other_model)
	other_waves.add_local_impact(Vector3.UP, 1.0)
	_expect(first_mesh.material_override == other_mesh.material_override,
		"players with different impacts still share one material")
	var first_strengths: Vector4 = first_mesh.get_instance_shader_parameter(&"gel_wave_strengths")
	var other_strengths: Vector4 = other_mesh.get_instance_shader_parameter(&"gel_wave_strengths")
	_expect(first_strengths.is_zero_approx() and other_strengths.x == 1.0,
		"impact wave uniforms remain isolated per player")
	other_model.free()
	other_waves.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

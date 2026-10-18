extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_environment_response.gd
## S-311.56: rain ripples, ambient wind sway and persistent wet sheen.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const EnvironmentResponse := preload("res://scripts/gameplay/player/gel/gel_environment_response.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_mood: Dictionary = WorldMood.active.duplicate(true)
	var model: Node3D = GEL_SCENE.instantiate() as Node3D
	root.add_child(model)
	PlayerAppearance.set_gel_material(model, false)
	var controller: Node = EnvironmentResponse.new()
	root.add_child(controller)
	_expect(controller.setup(model, 7), "the real gel mesh accepts environment response")
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(model)
	var original_transform: Transform3D = model.global_transform

	WorldMood.active = {"weather": WorldMood.Weather.RAIN, "rain": true}
	controller.update_environment(0.5)
	var rainy: Vector4 = controller.weather_uniform()
	var rainy_wind: Vector4 = controller.wind_uniform()
	_expect(rainy.z == 1.0 and rainy.w == 1.0, "rain enables ripples and saturates the wet sheen")
	_expect(is_equal_approx(rainy_wind.w, EnvironmentResponse.RAIN_WIND),
		"rain uses the stronger ambient wind response")
	_expect(Vector3(rainy_wind.x, rainy_wind.y, rainy_wind.z).is_normalized(),
		"wind direction is normalized in mesh-local space")
	_expect(mesh.get_instance_shader_parameter(&"gel_weather") == rainy,
		"weather state is isolated in per-instance shader uniforms")
	_expect(mesh.get_instance_shader_parameter(&"gel_wind") == rainy_wind,
		"wind state is isolated in per-instance shader uniforms")
	_expect(model.global_transform == original_transform,
		"environment response never changes the gameplay transform")

	WorldMood.active = {"weather": WorldMood.Weather.CLEAR, "rain": false}
	controller.update_environment(1.0)
	var drying: Vector4 = controller.weather_uniform()
	_expect(drying.z == 0.0 and drying.w > 0.8,
		"ripples stop immediately while wet shine dries gradually")
	_expect(is_equal_approx(controller.wind_uniform().w, EnvironmentResponse.CLEAR_WIND),
		"clear weather keeps only a gentle ambient sway")
	controller.update_environment(8.0)
	_expect(controller.weather_uniform().w < 0.001, "the wet sheen eventually dries completely")

	_check_material_variants(model, mesh)
	_check_instance_isolation(mesh)
	var packed_player: Node = PLAYER_SCENE.instantiate()
	_expect(packed_player.has_node("GelEffects/GelEnvironment"),
		"the runtime player scene owns the environment response controller")
	packed_player.free()
	WorldMood.active = previous_mood
	model.free()
	controller.free()
	if _failures == 0:
		print("PASS: rain ripples, wind sway and wet sheen are presentation-only")
	quit(_failures)


func _check_material_variants(model: Node3D, mesh: MeshInstance3D) -> void:
	var transparent_code: String = (mesh.material_override as ShaderMaterial).shader.code
	_expect("environment_ripple" in transparent_code and "mix(roughness, 0.025" in transparent_code,
		"the transparent gel has small rain waves and a smoother wet surface")
	PlayerAppearance.set_gel_material(model, true)
	var opaque_code: String = (mesh.material_override as ShaderMaterial).shader.code
	_expect("environment_ripple" in opaque_code and "gel_wind.xyz" in opaque_code,
		"the opaque fallback includes the same rain and wind response")
	PlayerAppearance.set_gel_material(model, false)


func _check_instance_isolation(first_mesh: MeshInstance3D) -> void:
	var other_model: Node3D = GEL_SCENE.instantiate() as Node3D
	root.add_child(other_model)
	PlayerAppearance.set_gel_material(other_model, false)
	var other_mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(other_model)
	var other_controller: Node = EnvironmentResponse.new()
	root.add_child(other_controller)
	other_controller.setup(other_model, 23)
	other_controller.advance_environment(true, Vector3.FORWARD, 0.7, 0.25)
	_expect(first_mesh.material_override == other_mesh.material_override,
		"players responding to weather still share one material")
	_expect(first_mesh.get_instance_shader_parameter(&"gel_weather")
		!= other_mesh.get_instance_shader_parameter(&"gel_weather"),
		"rain phase and wetness remain isolated per player")
	other_model.free()
	other_controller.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

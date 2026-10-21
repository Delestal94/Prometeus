extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_animated_skins.gd
## S-311.67: four animated skins cycle, react to night and stay per-instance.

const Catalog := preload("res://scripts/gameplay/player/gel/gel_skin_catalog.gd")
const Definition := preload("res://scripts/gameplay/player/gel/gel_skin_definition.gd")
const Applier := preload("res://scripts/gameplay/player/gel/gel_skin_applier.gd")
const EnvironmentResponse := preload("res://scripts/gameplay/player/gel/gel_environment_response.gd")
const MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body.tres")
const OPAQUE_MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body_opaque.tres")
const EXPECTED_IDS: Array[StringName] = [
	&"cycling_rainbow", &"night_neon", &"slow_lava", &"holographic",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(Catalog.ANIMATED_SKINS.size() == 4, "the catalog has exactly four animated skins")
	_expect(Catalog.animated_ids() == EXPECTED_IDS, "animated skins keep stable IDs and order")
	_expect(Catalog.all_skins().size() == 25, "base, interior and animated catalogs compose")

	for index: int in Catalog.ANIMATED_SKINS.size():
		var definition: Resource = Catalog.ANIMATED_SKINS[index]
		var skin_id: StringName = definition.get(&"id")
		_expect(definition.get_script() == Definition, "%s uses GelSkinDefinition" % skin_id)
		_expect(definition.call(&"is_valid"), "%s has valid animation values" % skin_id)
		_expect(
			int(definition.get(&"animation_mode")) == index + 1,
			"%s owns its stable animation mode" % skin_id
		)
		_expect(Catalog.skin(skin_id) == definition, "%s resolves from the catalog" % skin_id)
		_check_application(definition)

	_check_night_packing()
	_check_shader_contract(MATERIAL.shader, "transparent")
	_check_shader_contract(OPAQUE_MATERIAL.shader, "opaque")
	if _failures == 0:
		print("PASS: cycling rainbow, night neon, slow lava and holographic gel skins")
	quit(_failures)


func _check_application(definition: Resource) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	root.add_child(mesh)
	_expect(Applier.apply(mesh, definition), "%s applies to a geometry instance" % definition.get(&"id"))
	var surface: Vector4 = mesh.get_instance_shader_parameter(&"gel_skin_surface")
	var expected_mode: float = 5.0 + float(definition.get(&"animation_mode"))
	_expect(is_equal_approx(surface.z, expected_mode), "%s packs its shader mode" % definition.get(&"id"))
	mesh.free()


func _check_night_packing() -> void:
	var previous_mood: Dictionary = WorldMood.active.duplicate(true)
	var controller: Node = EnvironmentResponse.new()
	root.add_child(controller)
	WorldMood.active = {
		"weather": WorldMood.Weather.CLEAR,
		"rain": false,
		"time": WorldMood.TimeOfDay.NIGHT,
	}
	controller.update_environment(0.0)
	_expect(controller.weather_uniform().z == 4.0, "night is packed without changing daytime rain values")
	WorldMood.active = previous_mood
	controller.free()


func _check_shader_contract(shader: Shader, label: String) -> void:
	for marker: String in [
		"animated_skin_tint", "weather_night", "TIME",
		"gel_skin_surface.z > 4.5 && gel_skin_surface.z < 5.5",
	]:
		_expect(shader.code.contains(marker), "the %s shader supports %s" % [label, marker])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

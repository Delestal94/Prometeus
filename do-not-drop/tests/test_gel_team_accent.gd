extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_team_accent.gd
## S-311.68: the shirt/team colour accents the gel edge without replacing its skin.

const Appearance := preload("res://scripts/gameplay/player/player_appearance.gd")
const MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body.tres")
const OPAQUE_MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body_opaque.tres")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var first := _mesh(MATERIAL)
	var second := _mesh(MATERIAL)
	var skin := Color(0.72, 0.3, 0.9, 0.84)
	var team := Color(0.96, 0.32, 0.12, 1.0)
	Appearance.set_gel_look(first, skin, 0.78, 1.12)
	Appearance.set_gel_team_accent(first, team)
	Appearance.set_gel_look(second, skin, 0.78, 1.12)
	Appearance.set_gel_team_accent(second, Color(0.1, 0.72, 1.0, 1.0))

	var packed: float = first.get_instance_shader_parameter(&"gel_brightness")
	var decoded: Color = Appearance.unpack_gel_team_color(packed)
	_expect(first.material_override == second.material_override, "team accents keep the shared gel material")
	_expect(first.get_instance_shader_parameter(&"gel_color") == skin, "the team accent does not replace the skin")
	_expect(is_equal_approx(Appearance.unpack_gel_brightness(packed), 1.12), "packing preserves skin brightness")
	_expect(_close_color(decoded, team), "the current shirt colour survives compact per-instance packing")
	_expect(
		first.get_instance_shader_parameter(&"gel_brightness")
		!= second.get_instance_shader_parameter(&"gel_brightness"),
		"different teammates keep isolated edge colours"
	)

	Appearance.set_gel_look(first, Color(0.2, 0.92, 0.5, 0.9), 0.66, 0.84)
	var repacked: float = first.get_instance_shader_parameter(&"gel_brightness")
	_expect(_close_color(Appearance.unpack_gel_team_color(repacked), team), "changing skins preserves the team accent")
	_expect(is_equal_approx(Appearance.unpack_gel_brightness(repacked), 0.84), "changing skins updates brightness")
	var player_code := FileAccess.get_file_as_string("res://scripts/gameplay/player/player.gd")
	_expect(player_code.contains("set_gel_team_accent"), "the runtime feeds its shirt colour to the gel")

	_check_shader(MATERIAL.shader, "transparent")
	_check_shader(OPAQUE_MATERIAL.shader, "opaque")
	first.free()
	second.free()
	if _failures == 0:
		print("PASS: team colour accents the gel edge without replacing the skin")
	quit(_failures)


func _mesh(material: ShaderMaterial) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	mesh.material_override = material
	root.add_child(mesh)
	return mesh


func _close_color(actual: Color, expected: Color) -> bool:
	var tolerance: float = 1.0 / Appearance.TEAM_COLOR_STEPS
	return absf(actual.r - expected.r) <= tolerance \
		and absf(actual.g - expected.g) <= tolerance \
		and absf(actual.b - expected.b) <= tolerance


func _check_shader(shader: Shader, label: String) -> void:
	_expect(shader.code.count("instance uniform") == 16, "%s stays within the instance-uniform limit" % label)
	for marker: String in ["team_accent_color", "team_edge", "smoothstep(0.08, 0.72, fresnel)"]:
		_expect(shader.code.contains(marker), "the %s shader keeps team colour at the edge" % label)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

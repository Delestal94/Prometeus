extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_interior_skins.gd
## S-311.66: five interior skins expose unique modes and apply per-instance shader values.

const Catalog := preload("res://scripts/gameplay/player/gel/gel_skin_catalog.gd")
const Definition := preload("res://scripts/gameplay/player/gel/gel_skin_definition.gd")
const Applier := preload("res://scripts/gameplay/player/gel/gel_skin_applier.gd")
const MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body.tres")
const OPAQUE_MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body_opaque.tres")
const EXPECTED_IDS: Array[StringName] = [
	&"layered_gummy", &"vertical_gradient", &"fruit_bits", &"glitter", &"big_bubbles",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(Catalog.SKINS.size() == 16, "the base palette remains exactly sixteen skins")
	_expect(Catalog.INTERIOR_SKINS.size() == 5, "the catalog has exactly five interior skins")
	_expect(Catalog.interior_ids() == EXPECTED_IDS, "interior skins keep stable IDs and order")
	_expect(Catalog.all_skins().size() >= 21, "base and interior catalogs compose without loss")

	var seen_modes: Dictionary = {}
	for definition: Resource in Catalog.INTERIOR_SKINS:
		var skin_id: StringName = definition.get(&"id")
		var mode: int = definition.get(&"interior_mode")
		_expect(definition.get_script() == Definition, "%s uses GelSkinDefinition" % skin_id)
		_expect(definition.call(&"is_valid"), "%s has valid interior values" % skin_id)
		_expect(mode != Definition.InteriorMode.NONE, "%s enables an interior mode" % skin_id)
		_expect(not seen_modes.has(mode), "%s owns a unique rendering mode" % skin_id)
		_expect(Catalog.skin(skin_id) == definition, "%s resolves from the combined catalog" % skin_id)
		_check_application(definition)
		seen_modes[mode] = true

	_check_shader_contract(MATERIAL.shader, "transparent")
	_check_shader_contract(OPAQUE_MATERIAL.shader, "opaque")
	if _failures == 0:
		print("PASS: layered, gradient, fruit, glitter and big-bubble gel skins")
	quit(_failures)


func _check_application(definition: Resource) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	mesh.material_override = MATERIAL
	root.add_child(mesh)
	_expect(Applier.apply(mesh, definition), "%s applies to a geometry instance" % definition.get(&"id"))
	_expect(mesh.get_instance_shader_parameter(&"gel_color") == definition.get(&"color"),
		"%s applies its base colour" % definition.get(&"id"))
	var applied_surface: Vector4 = mesh.get_instance_shader_parameter(&"gel_skin_surface")
	_expect(is_equal_approx(applied_surface.z, float(definition.get(&"interior_mode"))),
		"%s applies its interior mode" % definition.get(&"id"))
	mesh.free()


func _check_shader_contract(shader: Shader, label: String) -> void:
	for declaration: String in [
		"vec4 gel_skin_surface", "vec4 gel_interior",
	]:
		_expect(shader.code.contains("instance uniform %s" % declaration),
			"the %s shader exposes %s per instance" % [label, declaration])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

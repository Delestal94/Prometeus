extends SceneTree
## S-311.74: every costume receives the real body morph contract and valid bone weights.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const Catalog := preload("res://scripts/gameplay/player/gel/gel_costume_catalog.gd")
const Library := preload("res://scripts/gameplay/player/gel/gel_costume_library.gd")
const Fitter := preload("res://scripts/gameplay/player/gel/gel_costume_fitter.gd")
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gel: Node3D = GEL_SCENE.instantiate()
	root.add_child(gel)
	var expected_morphs: Array[StringName] = []
	for definition: Dictionary in Proportions.parameter_definitions():
		if definition[&"driver"] == &"morph":
			expected_morphs.append(definition[&"name"])
	for costume_id: StringName in Catalog.ids():
		var costume: Node3D = Library.build_costume(costume_id)
		gel.add_child(costume)
		var fitter := Fitter.new()
		_expect(fitter.setup(costume, gel), "%s transfers the real rig contract" % costume_id)
		_expect(costume.is_in_group(&"gel_clothing"), "%s joins the clothing matrix" % costume_id)
		_expect(fitter.morph_names() == expected_morphs, "%s receives all eleven body morphs" % costume_id)
		var proportions := Proportions.new()
		_set_extremes(proportions, costume_id)
		_expect(fitter.apply(proportions), "%s applies an extreme proportion state" % costume_id)
		_expect(not fitter.apply(proportions), "%s skips an unchanged state" % costume_id)
		_check_pieces(costume, expected_morphs, costume_id)
		costume.free()
	gel.free()
	if _failures == 0:
		print("PASS: every costume follows the real morph and bone-weight contract")
	quit(_failures)


func _set_extremes(proportions: GelBodyProportions, costume_id: StringName) -> void:
	var positive: bool = Catalog.ids().find(costume_id) % 2 == 0
	for definition: Dictionary in Proportions.parameter_definitions():
		proportions.set(definition[&"name"], definition[&"maximum"] if positive else definition[&"minimum"])


func _check_pieces(node: Node, expected_morphs: Array[StringName], label: StringName) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var piece := child as MeshInstance3D
			var weights: Dictionary = piece.get_meta(&"gel_costume_weights", {})
			_expect(piece.transform.is_finite(), "%s keeps finite fitted geometry" % label)
			_expect(piece.get_meta(&"gel_costume_morphs", []) == expected_morphs,
				"%s pieces share the body morph names" % label)
			_expect(weights.size() == 1 and is_equal_approx(float(weights.values()[0]), 1.0),
				"%s pieces keep one normalized bone target" % label)
			var material := piece.material_override as StandardMaterial3D
			if bool(piece.get_meta(&"gel_costume_opaque", false)):
				_expect(material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
					"%s opaque pieces keep the depth-writing material path" % label)
		_check_pieces(child, expected_morphs, label)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

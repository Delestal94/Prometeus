extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_body_proportions.gd
##
## GelBodyProportions exposes the six bone-driven lengths and the eleven GLB
## morphs with stable names, visible ranges and Delgada defaults. The metadata,
## exported inspector ranges, current-value dictionary and reset operation stay
## in sync so later shaping, UI and persistence code share one contract.

const GelProportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const BONE_NAMES: Array[StringName] = [
	&"total_height",
	&"leg_length",
	&"arm_length",
	&"torso_length",
	&"neck_length",
	&"head_size",
]
const MORPH_NAMES: Array[StringName] = [
	&"general_thickness",
	&"belly",
	&"chest",
	&"shoulders",
	&"hips",
	&"arm_thickness",
	&"leg_thickness",
	&"hand_size",
	&"foot_size",
	&"head_shape",
	&"neck_thickness",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var proportions: Resource = GelProportions.new()
	var definitions: Array[Dictionary] = GelProportions.parameter_definitions()
	var expected_names: Array[StringName] = BONE_NAMES + MORPH_NAMES

	_expect(definitions.size() == 17, "the contract has 6 bone and 11 morph parameters")
	_expect(_definition_names(definitions) == expected_names, "parameter names and display order are stable")
	_check_definitions(proportions, definitions)
	_check_export_ranges(proportions, definitions)
	_check_helpers(proportions, definitions)

	if _failures == 0:
		print("PASS: gelatin body proportion resource (17 parameters)")
	quit(_failures)


func _check_definitions(proportions: Resource, definitions: Array[Dictionary]) -> void:
	var seen_display_names: Dictionary = {}
	for index: int in definitions.size():
		var definition: Dictionary = definitions[index]
		var parameter_name: StringName = definition.get(&"name", &"")
		var display_name: String = definition.get(&"display_name", "")
		var driver: StringName = definition.get(&"driver", &"")
		var minimum: float = definition.get(&"minimum", NAN)
		var maximum: float = definition.get(&"maximum", NAN)
		var default_value: float = definition.get(&"default", NAN)

		_expect(not display_name.is_empty(), "%s has a display name" % parameter_name)
		_expect(not seen_display_names.has(display_name), "%s has a unique display name" % parameter_name)
		seen_display_names[display_name] = true
		var expected_driver: StringName = &"bone" if index < BONE_NAMES.size() else &"morph"
		_expect(driver == expected_driver, "%s has the expected driver" % parameter_name)
		_expect(
			minimum < default_value and default_value < maximum,
			"%s default lies inside its range" % parameter_name
		)
		_expect(
			is_equal_approx(float(proportions.get(parameter_name)), default_value),
			"%s starts at the Delgada default" % parameter_name
		)

		if driver == &"morph":
			_expect(
				minimum == -1.0 and maximum == 1.0 and default_value == 0.0,
				"%s follows the exported GLB morph contract" % parameter_name
			)

	var height: Dictionary = GelProportions.definition_for(&"total_height")
	_expect(height.get(&"minimum") == 0.85 and height.get(&"maximum") == 1.20, "total height spans 0.85 to 1.20")
	_expect(GelProportions.definition_for(&"unknown").is_empty(), "unknown parameters have no definition")


func _check_export_ranges(proportions: Resource, definitions: Array[Dictionary]) -> void:
	var properties: Dictionary = {}
	for property: Dictionary in proportions.get_property_list():
		properties[property.get(&"name", &"")] = property

	for definition: Dictionary in definitions:
		var parameter_name: StringName = definition[&"name"]
		var property: Dictionary = properties.get(parameter_name, {})
		_expect(not property.is_empty(), "%s is an exported Resource property" % parameter_name)
		if property.is_empty():
			continue
		_expect(
			property.get(&"hint", PROPERTY_HINT_NONE) == PROPERTY_HINT_RANGE,
			"%s has an inspector range" % parameter_name
		)
		var range_parts: PackedStringArray = String(property.get(&"hint_string", "")).split(",")
		_expect(range_parts.size() >= 2, "%s exposes minimum and maximum hints" % parameter_name)
		if range_parts.size() >= 2:
			_expect(
				is_equal_approx(range_parts[0].to_float(), float(definition[&"minimum"])),
				"%s inspector minimum matches metadata" % parameter_name
			)
			_expect(
				is_equal_approx(range_parts[1].to_float(), float(definition[&"maximum"])),
				"%s inspector maximum matches metadata" % parameter_name
			)


func _check_helpers(proportions: Resource, definitions: Array[Dictionary]) -> void:
	proportions.set(&"total_height", 1.17)
	proportions.set(&"belly", 0.63)
	var current: Dictionary = proportions.call(&"as_dictionary")
	_expect(current.size() == definitions.size(), "as_dictionary includes every parameter")
	_expect(current[&"total_height"] == 1.17 and current[&"belly"] == 0.63, "as_dictionary returns current values")

	proportions.call(&"reset_to_delgada")
	for definition: Dictionary in definitions:
		var parameter_name: StringName = definition[&"name"]
		_expect(
			is_equal_approx(float(proportions.get(parameter_name)), float(definition[&"default"])),
			"%s resets to Delgada" % parameter_name
		)

	definitions[0][&"default"] = 99.0
	_expect(
		GelProportions.definition_for(&"total_height")[&"default"] == 1.0,
		"callers cannot mutate the shared contract"
	)


func _definition_names(definitions: Array[Dictionary]) -> Array[StringName]:
	var names: Array[StringName] = []
	for definition: Dictionary in definitions:
		names.append(definition[&"name"])
	return names


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

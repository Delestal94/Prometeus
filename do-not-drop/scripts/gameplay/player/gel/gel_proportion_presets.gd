class_name GelProportionPresets
extends RefCounted
## Named body presets and conservative random combinations for S-311.21.

const PRESET_PATHS: Dictionary = {
	&"delgada": "res://data/gel/proportion_presets/delgada.tres",
	&"flaca": "res://data/gel/proportion_presets/flaca.tres",
	&"rellena": "res://data/gel/proportion_presets/rellena.tres",
	&"petisa": "res://data/gel/proportion_presets/petisa.tres",
	&"cabezona": "res://data/gel/proportion_presets/cabezona.tres",
	&"larguirucha": "res://data/gel/proportion_presets/larguirucha.tres",
}
const LABEL_KEYS: Dictionary = {
	&"delgada": "UI_GEL_PRESET_DELGADA",
	&"flaca": "UI_GEL_PRESET_FLACA",
	&"rellena": "UI_GEL_PRESET_RELLENA",
	&"petisa": "UI_GEL_PRESET_PETISA",
	&"cabezona": "UI_GEL_PRESET_CABEZONA",
	&"larguirucha": "UI_GEL_PRESET_LARGUIRUCHA",
}
const SAFE_RANGES: Dictionary = {
	&"total_height": Vector2(0.90, 1.10),
	&"leg_length": Vector2(0.85, 1.15),
	&"arm_length": Vector2(0.85, 1.15),
	&"torso_length": Vector2(0.85, 1.15),
	&"neck_length": Vector2(0.85, 1.15),
	&"head_size": Vector2(0.85, 1.15),
	&"general_thickness": Vector2(-0.55, 0.60),
	&"belly": Vector2(-0.45, 0.60),
	&"chest": Vector2(-0.45, 0.60),
	&"shoulders": Vector2(-0.55, 0.55),
	&"hips": Vector2(-0.45, 0.60),
	&"arm_thickness": Vector2(-0.55, 0.55),
	&"leg_thickness": Vector2(-0.55, 0.55),
	&"hand_size": Vector2(-0.70, 0.70),
	&"foot_size": Vector2(-0.70, 0.70),
	&"head_shape": Vector2(-0.50, 0.50),
	&"neck_thickness": Vector2(-0.55, 0.55),
}


static func preset_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for preset_id: StringName in PRESET_PATHS:
		result.append(preset_id)
	return result


static func label_key(preset_id: StringName) -> String:
	return String(LABEL_KEYS.get(preset_id, ""))


## Returns a caller-owned resource so editing a preset never mutates the cache.
static func load_preset(preset_id: StringName) -> GelBodyProportions:
	var path: String = String(PRESET_PATHS.get(preset_id, ""))
	if path.is_empty():
		return null
	var source: GelBodyProportions = load(path) as GelBodyProportions
	return source.duplicate(true) as GelBodyProportions if source != null else null


static func apply_preset(preset_id: StringName, target: GelBodyProportions) -> bool:
	var source: GelBodyProportions = load_preset(preset_id)
	if source == null:
		return false
	_copy_values(source, target)
	target.emit_changed()
	return true


## Fills the target once. The editor's random button calls this method.
static func randomize_safe(target: GelBodyProportions, rng: RandomNumberGenerator) -> void:
	for parameter_name: StringName in [
		&"total_height", &"leg_length", &"arm_length", &"torso_length", &"head_size",
		&"general_thickness", &"belly", &"chest", &"hips", &"arm_thickness",
		&"leg_thickness", &"head_shape",
	]:
		_set_random(target, parameter_name, rng)

	var head_size: float = target.head_size
	var neck_min: float = maxf(0.85, 0.90 + maxf(head_size - 1.0, 0.0) * 0.5)
	target.neck_length = rng.randf_range(neck_min, SAFE_RANGES[&"neck_length"].y)
	var neck_thickness_min: float = maxf(-0.55, (head_size - 1.0) * 2.0 - 0.20)
	target.neck_thickness = rng.randf_range(neck_thickness_min, SAFE_RANGES[&"neck_thickness"].y)
	var shoulder_min: float = maxf(-0.55, (head_size - 1.0) * 1.5 - 0.25)
	target.shoulders = rng.randf_range(shoulder_min, SAFE_RANGES[&"shoulders"].y)
	target.hand_size = clampf(
		target.arm_thickness + rng.randf_range(-0.25, 0.25),
		SAFE_RANGES[&"hand_size"].x,
		SAFE_RANGES[&"hand_size"].y
	)
	target.foot_size = clampf(
		target.leg_thickness + rng.randf_range(-0.25, 0.25),
		SAFE_RANGES[&"foot_size"].x,
		SAFE_RANGES[&"foot_size"].y
	)
	target.emit_changed()


static func is_safe(values: Dictionary) -> bool:
	for parameter_name: StringName in SAFE_RANGES:
		var limits: Vector2 = SAFE_RANGES[parameter_name]
		var value: float = float(values.get(parameter_name, INF))
		if value < limits.x - 0.0001 or value > limits.y + 0.0001:
			return false
	var head_size: float = float(values[&"head_size"])
	if float(values[&"neck_length"]) < 0.90 + maxf(head_size - 1.0, 0.0) * 0.5:
		return false
	if float(values[&"neck_thickness"]) < (head_size - 1.0) * 2.0 - 0.20:
		return false
	if float(values[&"shoulders"]) < (head_size - 1.0) * 1.5 - 0.25:
		return false
	if absf(float(values[&"hand_size"]) - float(values[&"arm_thickness"])) > 0.251:
		return false
	return absf(float(values[&"foot_size"]) - float(values[&"leg_thickness"])) <= 0.251


static func _set_random(
	target: GelBodyProportions,
	parameter_name: StringName,
	rng: RandomNumberGenerator
) -> void:
	var limits: Vector2 = SAFE_RANGES[parameter_name]
	target.set(parameter_name, rng.randf_range(limits.x, limits.y))


static func _copy_values(source: GelBodyProportions, target: GelBodyProportions) -> void:
	for definition: Dictionary in GelBodyProportions.parameter_definitions():
		var parameter_name: StringName = definition[&"name"]
		target.set(parameter_name, source.get(parameter_name))

class_name GelBodyProportions
extends Resource
## Editable proportions for the single gelatin body (S-311.19).
##
## Bone parameters are multipliers over the Delgada rest pose. Morph parameters
## map one-to-one to the blend-shape names exported by build_gel_body.py. Delgada
## is the neutral resource: every bone multiplier is 1 and every morph weight is
## 0. Safe cross-parameter combinations are certified separately by S-311.26.

const PARAMETER_DEFINITIONS: Array[Dictionary] = [
	{
		&"name": &"total_height",
		&"label_key": "UI_GEL_PROPORTION_TOTAL_HEIGHT",
		&"driver": &"bone",
		&"minimum": 0.85,
		&"maximum": 1.20,
		&"default": 1.0,
	},
	{
		&"name": &"leg_length",
		&"label_key": "UI_GEL_PROPORTION_LEG_LENGTH",
		&"driver": &"bone",
		&"minimum": 0.75,
		&"maximum": 1.25,
		&"default": 1.0,
	},
	{
		&"name": &"arm_length",
		&"label_key": "UI_GEL_PROPORTION_ARM_LENGTH",
		&"driver": &"bone",
		&"minimum": 0.75,
		&"maximum": 1.25,
		&"default": 1.0,
	},
	{
		&"name": &"torso_length",
		&"label_key": "UI_GEL_PROPORTION_TORSO_LENGTH",
		&"driver": &"bone",
		&"minimum": 0.75,
		&"maximum": 1.25,
		&"default": 1.0,
	},
	{
		&"name": &"neck_length",
		&"label_key": "UI_GEL_PROPORTION_NECK_LENGTH",
		&"driver": &"bone",
		&"minimum": 0.75,
		&"maximum": 1.25,
		&"default": 1.0,
	},
	{
		&"name": &"head_size",
		&"label_key": "UI_GEL_PROPORTION_HEAD_SIZE",
		&"driver": &"bone",
		&"minimum": 0.75,
		&"maximum": 1.25,
		&"default": 1.0,
	},
	{
		&"name": &"general_thickness",
		&"label_key": "UI_GEL_PROPORTION_GENERAL_THICKNESS",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"belly",
		&"label_key": "UI_GEL_PROPORTION_BELLY",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"chest",
		&"label_key": "UI_GEL_PROPORTION_CHEST",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"shoulders",
		&"label_key": "UI_GEL_PROPORTION_SHOULDERS",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"hips",
		&"label_key": "UI_GEL_PROPORTION_HIPS",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"arm_thickness",
		&"label_key": "UI_GEL_PROPORTION_ARM_THICKNESS",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"leg_thickness",
		&"label_key": "UI_GEL_PROPORTION_LEG_THICKNESS",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"hand_size",
		&"label_key": "UI_GEL_PROPORTION_HAND_SIZE",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"foot_size",
		&"label_key": "UI_GEL_PROPORTION_FOOT_SIZE",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"head_shape",
		&"label_key": "UI_GEL_PROPORTION_HEAD_SHAPE",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"neck_thickness",
		&"label_key": "UI_GEL_PROPORTION_NECK_THICKNESS",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
]
const PACKET_SIZE: int = 17

@export_group("Bone lengths")
@export_range(0.85, 1.20, 0.01) var total_height: float = 1.0
@export_range(0.75, 1.25, 0.01) var leg_length: float = 1.0
@export_range(0.75, 1.25, 0.01) var arm_length: float = 1.0
@export_range(0.75, 1.25, 0.01) var torso_length: float = 1.0
@export_range(0.75, 1.25, 0.01) var neck_length: float = 1.0
@export_range(0.75, 1.25, 0.01) var head_size: float = 1.0

@export_group("Morph shapes")
@export_range(-1.0, 1.0, 0.01) var general_thickness: float = 0.0
@export_range(-1.0, 1.0, 0.01) var belly: float = 0.0
@export_range(-1.0, 1.0, 0.01) var chest: float = 0.0
@export_range(-1.0, 1.0, 0.01) var shoulders: float = 0.0
@export_range(-1.0, 1.0, 0.01) var hips: float = 0.0
@export_range(-1.0, 1.0, 0.01) var arm_thickness: float = 0.0
@export_range(-1.0, 1.0, 0.01) var leg_thickness: float = 0.0
@export_range(-1.0, 1.0, 0.01) var hand_size: float = 0.0
@export_range(-1.0, 1.0, 0.01) var foot_size: float = 0.0
@export_range(-1.0, 1.0, 0.01) var head_shape: float = 0.0
@export_range(-1.0, 1.0, 0.01) var neck_thickness: float = 0.0


## A caller-owned copy of the complete slider contract, in display order.
static func parameter_definitions() -> Array[Dictionary]:
	return PARAMETER_DEFINITIONS.duplicate(true)


## The contract for one property, or an empty dictionary for an unknown name.
static func definition_for(parameter_name: StringName) -> Dictionary:
	for definition: Dictionary in PARAMETER_DEFINITIONS:
		if definition[&"name"] == parameter_name:
			return definition.duplicate(true)
	return {}


## Current values keyed by their stable property/morph names.
func as_dictionary() -> Dictionary:
	var values: Dictionary = {}
	for definition: Dictionary in PARAMETER_DEFINITIONS:
		var parameter_name: StringName = definition[&"name"]
		values[parameter_name] = get(parameter_name)
	return values


## Defaults keyed by the stable property names, suitable for profile storage.
static func default_dictionary() -> Dictionary:
	var values: Dictionary = {}
	for definition: Dictionary in PARAMETER_DEFINITIONS:
		values[definition[&"name"]] = definition[&"default"]
	return values


## Host/profile boundary: unknown keys are ignored, non-finite values fall
## back to Delgada and every known value is clamped to its authored range.
static func sanitized_dictionary(values: Dictionary) -> Dictionary:
	var sanitized: Dictionary = {}
	for definition: Dictionary in PARAMETER_DEFINITIONS:
		var parameter_name: StringName = definition[&"name"]
		var fallback: float = float(definition[&"default"])
		var candidate: Variant = values.get(parameter_name, values.get(String(parameter_name), fallback))
		var number: float = float(candidate) if candidate is float or candidate is int else fallback
		if not is_finite(number):
			number = float(definition[&"default"])
		sanitized[parameter_name] = clampf(number, float(definition[&"minimum"]), float(definition[&"maximum"]))
	return sanitized


## Applies profile values in place and reports whether the visible state changed.
func apply_dictionary(values: Dictionary) -> bool:
	var sanitized: Dictionary = sanitized_dictionary(values)
	var changed: bool = false
	for definition: Dictionary in PARAMETER_DEFINITIONS:
		var parameter_name: StringName = definition[&"name"]
		var next_value: float = float(sanitized[parameter_name])
		changed = changed or not is_equal_approx(float(get(parameter_name)), next_value)
		set(parameter_name, next_value)
	if changed:
		emit_changed()
	return changed


## One byte per parameter, in PARAMETER_DEFINITIONS order. This is the whole
## network representation: no names or floats travel with it.
func to_packet() -> PackedByteArray:
	var packet := PackedByteArray()
	packet.resize(PACKET_SIZE)
	for index: int in PACKET_SIZE:
		var definition: Dictionary = PARAMETER_DEFINITIONS[index]
		var minimum: float = float(definition[&"minimum"])
		var maximum: float = float(definition[&"maximum"])
		var value: float = clampf(float(get(definition[&"name"])), minimum, maximum)
		packet[index] = roundi(inverse_lerp(minimum, maximum, value) * 255.0)
	return packet


## Decodes a complete packet. Malformed sizes are rejected without changing
## the resource; byte values themselves can only decode inside each range.
func apply_packet(packet: PackedByteArray) -> bool:
	if packet.size() != PACKET_SIZE:
		return false
	var values: Dictionary = {}
	for index: int in PACKET_SIZE:
		var definition: Dictionary = PARAMETER_DEFINITIONS[index]
		values[definition[&"name"]] = lerpf(
			float(definition[&"minimum"]), float(definition[&"maximum"]), float(packet[index]) / 255.0
		)
	return apply_dictionary(values)


static func packet_from_dictionary(values: Dictionary) -> PackedByteArray:
	var proportions := GelBodyProportions.new()
	proportions.apply_dictionary(values)
	return proportions.to_packet()


## Restores the measured Delgada base without replacing the Resource instance.
func reset_to_delgada() -> void:
	for definition: Dictionary in PARAMETER_DEFINITIONS:
		set(definition[&"name"], definition[&"default"])
	emit_changed()

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
		&"display_name": "Alto total",
		&"driver": &"bone",
		&"minimum": 0.85,
		&"maximum": 1.20,
		&"default": 1.0,
	},
	{
		&"name": &"leg_length",
		&"display_name": "Largo de piernas",
		&"driver": &"bone",
		&"minimum": 0.75,
		&"maximum": 1.25,
		&"default": 1.0,
	},
	{
		&"name": &"arm_length",
		&"display_name": "Largo de brazos",
		&"driver": &"bone",
		&"minimum": 0.75,
		&"maximum": 1.25,
		&"default": 1.0,
	},
	{
		&"name": &"torso_length",
		&"display_name": "Largo de torso",
		&"driver": &"bone",
		&"minimum": 0.75,
		&"maximum": 1.25,
		&"default": 1.0,
	},
	{
		&"name": &"neck_length",
		&"display_name": "Largo de cuello",
		&"driver": &"bone",
		&"minimum": 0.75,
		&"maximum": 1.25,
		&"default": 1.0,
	},
	{
		&"name": &"head_size",
		&"display_name": "Tamaño de cabeza",
		&"driver": &"bone",
		&"minimum": 0.75,
		&"maximum": 1.25,
		&"default": 1.0,
	},
	{
		&"name": &"general_thickness",
		&"display_name": "Grosor general",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"belly",
		&"display_name": "Panza",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"chest",
		&"display_name": "Pecho",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"shoulders",
		&"display_name": "Hombros",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"hips",
		&"display_name": "Cadera",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"arm_thickness",
		&"display_name": "Grosor de brazos",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"leg_thickness",
		&"display_name": "Grosor de piernas",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"hand_size",
		&"display_name": "Tamaño de manos",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"foot_size",
		&"display_name": "Tamaño de pies",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"head_shape",
		&"display_name": "Forma de cabeza",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
	{
		&"name": &"neck_thickness",
		&"display_name": "Grosor de cuello",
		&"driver": &"morph",
		&"minimum": -1.0,
		&"maximum": 1.0,
		&"default": 0.0,
	},
]

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


## Restores the measured Delgada base without replacing the Resource instance.
func reset_to_delgada() -> void:
	for definition: Dictionary in PARAMETER_DEFINITIONS:
		set(definition[&"name"], definition[&"default"])
	emit_changed()

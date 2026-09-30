class_name TrapDefinition
extends Resource
## Immutable content definition of a hazard a carried object can carry: an
## id, a name, the behavior script (an ITrapBehavior) that gives every
## instance its own mutable state, a difficulty and the parameters that
## behavior reads. Portable module (docs/modulos.md): a game adds a hazard
## by saving one of these as a .tres next to a behavior script -- nothing
## else has to change.

@export var id: StringName = &"hazard"
@export var display_name: String = "Hazard"
## The translation key that travels over the network instead of the name:
## each peer translates it into its own language. Empty falls back to
## display_name.
@export var translation_key: String = ""
@export var behavior_script: Script
@export_range(1, 5) var difficulty: int = 1
@export var params: Dictionary = {}
## What an object with this hazard can be carrying (the game's content
## resources). Each object picks one, so the hazard says how it fails and
## the content says what's inside.
@export var contents: Array[Resource] = []


func localized_name() -> String:
	return tr(name_key())


## What travels over the network instead of the name itself.
func name_key() -> String:
	return translation_key if not translation_key.is_empty() else display_name


## Deterministic per object id, so every peer opens the same box without
## the choice having to travel over the network.
func pick_content(object_id: StringName) -> Resource:
	if contents.is_empty():
		return null
	return contents[absi(hash(object_id)) % contents.size()]


func create_behavior() -> Resource:
	if behavior_script == null:
		push_error("TrapDefinition has no behavior script: %s" % id)
		return null
	return behavior_script.new()

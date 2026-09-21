class_name TrapDefinition
extends Resource
## Immutable content definition. Each package creates its own behavior instance.

@export var id: StringName = &"fragile"
@export var display_name: String = "Frágil"
@export var behavior_script: Script
@export_range(1, 5) var difficulty: int = 1
@export var params: Dictionary = {}


func create_behavior() -> Resource:
	if behavior_script == null:
		push_error("TrapDefinition has no behavior script: %s" % id)
		return null
	return behavior_script.new()

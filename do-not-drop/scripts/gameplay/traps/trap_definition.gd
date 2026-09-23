class_name TrapDefinition
extends Resource
## Immutable content definition. Each package creates its own behavior instance.

@export var id: StringName = &"fragile"
@export var display_name: String = "Frágil"
@export var behavior_script: Script
@export_range(1, 5) var difficulty: int = 1
@export var params: Dictionary = {}
## What a package with this trap can be carrying (PackageContent). Each
## package picks one, so the trap says how it fails and the content says
## what's in the box when someone opens it.
@export var contents: Array[Resource] = []


## Deterministic per package id, so every peer opens the same box without
## the choice having to travel over the network.
func pick_content(package_id: StringName) -> Resource:
	if contents.is_empty():
		return null
	return contents[absi(hash(package_id)) % contents.size()]


func create_behavior() -> Resource:
	if behavior_script == null:
		push_error("TrapDefinition has no behavior script: %s" % id)
		return null
	return behavior_script.new()

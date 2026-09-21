class_name Interactable
extends Area3D
## Passive target the player's interaction probe detects and can activate.
## Never monitors on its own -- the player's probe does the scanning; this
## just needs to exist on the interaction_area layer to be found.

signal interacted(player: Node)

@export var prompt: String = "Interactuar"


func _ready() -> void:
	collision_layer = 16  # interaction_area (layer 5)
	collision_mask = 0
	monitoring = false
	monitorable = true


func get_prompt() -> String:
	return prompt


func can_interact(_player: Node) -> bool:
	return not get_prompt().is_empty()


func interact(player: Node) -> void:
	interacted.emit(player)

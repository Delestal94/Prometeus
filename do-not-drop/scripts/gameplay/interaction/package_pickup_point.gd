extends "res://scripts/gameplay/interaction/interactable.gd"
## Lets a nearby player pick up the package this is attached to.

@onready var _package: Node = get_parent()


func get_prompt() -> String:
	return "" if bool(_package.get("is_held")) or bool(_package.get("is_loaded")) else "Agarrar paquete"


func can_interact(player: Node) -> bool:
	return not get_prompt().is_empty() and player.get(&"carried_package") == null


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	if player.has_method(&"pick_up"):
		player.call(&"pick_up", _package)
	interacted.emit(player)

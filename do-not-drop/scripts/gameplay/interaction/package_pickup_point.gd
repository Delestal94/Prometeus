extends "res://scripts/gameplay/interaction/interactable.gd"
## Lets a nearby player pick up the package this is attached to.

@onready var _package: Node = get_parent()


func get_prompt() -> String:
	return "" if bool(_package.get("is_held")) else "Agarrar paquete"


func interact(player: Node) -> void:
	if bool(_package.get("is_held")):
		return
	if player.has_method(&"pick_up"):
		player.call(&"pick_up", _package)
	interacted.emit(player)

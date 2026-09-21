extends "res://scripts/gameplay/interaction/interactable.gd"
## Lets a player carrying a package leave it here, if the mount is free.
## The mount marker itself is the parent -- this only adds the interaction.

var occupied_by: Node = null


func get_prompt() -> String:
	return "" if occupied_by != null else "Dejar paquete acá"


func can_interact(player: Node) -> bool:
	return occupied_by == null and player.get(&"carried_package") != null


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	var carried: Node = player.get(&"carried_package")
	if carried == null:
		return
	var mount: Node3D = get_parent() as Node3D
	carried.call(&"place_at", mount)
	occupied_by = carried
	if player.has_method(&"drop_carried"):
		player.call(&"drop_carried")
	interacted.emit(player)

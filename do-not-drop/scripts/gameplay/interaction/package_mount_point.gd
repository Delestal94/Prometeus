extends "res://scripts/gameplay/interaction/interactable.gd"
## Lets a player carrying a package leave it here, if the mount is free.
## The mount marker itself is the parent -- this only adds the interaction.
##
## interact() only ever runs on the host (see interactable.gd). The package
## itself is host-authoritative too, so place_at() here is the real thing,
## not a copy -- but telling that player their hands are empty again is
## their own local state, so that part goes out as a targeted RPC.

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
		player.rpc_id(int(player.get_multiplayer_authority()), &"drop_carried")
	interacted.emit(player)

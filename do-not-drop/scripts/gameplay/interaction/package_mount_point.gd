extends "res://scripts/gameplay/interaction/interactable.gd"
## Lets a player carrying a package leave it here, if the mount is free.
## The mount marker itself is the parent -- this only adds the interaction.
##
## interact() only ever runs on the host (see interactable.gd). The package
## itself is host-authoritative too, so place_at() here is the real thing,
## not a copy -- but telling that player their hands are empty again is
## their own local state, so place_at() broadcasts that to every peer.

var occupied_by: Node = null


func get_prompt() -> String:
	return "" if occupied_by != null else prompt


func can_interact(player: Node) -> bool:
	return occupied_by == null and player.get(&"carried_package") != null


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	var carried: DeliveryPackage = player.get(&"carried_package") as DeliveryPackage
	if carried == null:
		return
	store(carried)
	# place_at() already empties a carrier's hands; this covers a package
	# handed over without a pickup (the debug start's direct pick_up()).
	if player.get(&"carried_package") == carried:
		player.rpc(&"drop_carried")
	interacted.emit(player)


## The one way a package ends up in this slot, whether a player set it down
## here or boarded the matching seat with it in hand (seat_point.gd).
func store(package: DeliveryPackage) -> void:
	package.place_at(get_parent() as Node3D, self)
	occupied_by = package

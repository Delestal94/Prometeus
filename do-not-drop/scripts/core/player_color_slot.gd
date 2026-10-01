class_name PlayerColorSlot
extends RefCounted
## The one place that answers "which colour does this peer wear" (N-226.2).
## Everything that paints or names a player by colour -- the suit, the crew
## list, the results awards, the depot vote dots, the callout voice, and the
## campaign's merit and cards -- asks for `slot()` and wraps nothing itself.
##
## The index is NetworkManager.color_slot() (the host hands them out in arrival
## order, N-226.1), wrapped to the palette: MAX_PLAYERS is 8 and so is the
## palette (N-228.3), so in a room nobody repeats; the wrap only matters to a
## reader with a shorter palette, or to an id with no announced slot.
##
## Two decisions that live here on purpose:
## - The host is always slot 0, in a room and playing solo. NetworkManager
##   answers 1 offline (posmod(1, 8), the pre-slot behaviour) and 0 in a room;
##   read as is, a host's suit and its saved merit would change the moment it
##   opens a room. The host is HOST_ID in both cases, so it is pinned here.
## - A slot somebody frees goes to the next one in, merit and card included:
##   the slot is the seat in the crew (docs/cartas-y-eventos-de-ruta.md "color
##   estable"), and whoever sits there carries its progress on. Reserving it
##   for the rest of the session would need NetworkManager to remember leavers
##   and would leave a seat unusable while the room is full.

const NETWORK_MANAGER := preload("res://scripts/core/network_manager.gd")


## `peer_id`'s palette index, 0..palette_size-1. With no NetworkManager (a bare
## script) or no announced slot, posmod(peer_id, palette_size).
static func slot(peer_id: int, palette_size: int) -> int:
	if palette_size <= 0:
		return 0
	if peer_id == NETWORK_MANAGER.HOST_ID:
		return 0
	var network: Object = _network()
	var raw: int = int(network.call(&"color_slot", peer_id)) if network != null else peer_id
	return posmod(raw, palette_size)


## Calls `changed` (no arguments) whenever the host's slot map changes, for as
## long as its object lives: a body spawned before the map reached it repaints.
## Does nothing where there is no NetworkManager.
static func follow(changed: Callable) -> void:
	var network: Object = _network()
	if network != null:
		network.connect(&"color_slots_changed", changed.unbind(1))


## The autoload, or null where there is none (a module test, a tool script).
static func _network() -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(^"NetworkManager")

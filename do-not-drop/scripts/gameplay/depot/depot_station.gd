extends "res://scripts/gameplay/interaction/interactable.gd"
class_name DepotStation
## A place in the depot where the crew gets ready: the lockers (uniform), the
## workshop (truck and paint), the supplies counter, the order board.
##
## interact() runs on the host like every Interactable, but what a station
## does is open a screen on the screen of whoever used it -- so the host
## bounces it straight back to that player's own peer, where it becomes a
## local EventBus.depot_station_opened for the HUD to show.
##
## Only before the run: once the truck has left, the depot is behind you.

@export var station_id: StringName = &"orders"
## Floating sign above the station, brightened while it's looked at.
var marker: Label3D


func get_prompt() -> String:
	if _run_started():
		return ""
	return prompt


func highlight(enabled: bool) -> void:
	if marker == null:
		return
	marker.modulate = Color("ffc93c") if enabled else Color("fff6e6")
	marker.scale = Vector3.ONE * (1.12 if enabled else 1.0)


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	var peer: int = int(player.get_multiplayer_authority())
	if multiplayer.multiplayer_peer == null or peer == multiplayer.get_unique_id():
		_open_locally()
	else:
		_open_locally.rpc_id(peer)
	interacted.emit(player)


@rpc("authority", "call_remote", "reliable")
func _open_locally() -> void:
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.emit_signal(&"depot_station_opened", station_id)


func _run_started() -> bool:
	var manager: Node = get_node_or_null(^"/root/RunManager")
	if manager == null:
		return false
	return bool(manager.get(&"is_running")) or not (manager.get(&"results") as Dictionary).is_empty()

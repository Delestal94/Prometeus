extends Interactable
class_name ServiceCounter
## The service station's counter (tareas de Nacho N-110): the road's version
## of the depot's supplies counter (DepotStation). interact() runs on the host
## like every Interactable; what it does is open the shop's vote for the crew
## and then open the supplies screen on the screen of whoever used it, so the
## host bounces it back to that player's own peer, where it becomes a local
## EventBus.service_counter_opened for the HUD (the same round trip as
## DepotStation).
##
## Only while a run is going: before the truck leaves, the depot sells.

## The ServiceStopShop this counter opens (ServiceStop hangs it).
var shop: Node


func _ready() -> void:
	super._ready()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	shape.shape = sphere
	add_child(shape)


func get_prompt() -> String:
	if shop == null or not _run_going():
		return ""
	return tr("WORLD_SERVICE_COUNTER_PROMPT")


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	shop.call(&"open_for_crew")
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
		bus.emit_signal(&"service_counter_opened", shop)


func _run_going() -> bool:
	var manager: Node = get_node_or_null(^"/root/RunManager")
	return manager != null and bool(manager.get(&"is_running"))

extends "res://scripts/gameplay/interaction/interactable.gd"
## Lets a nearby player pick up the package this is attached to.
##
## interact() only ever runs on the host (see interactable.gd), where the
## package is the real, authoritative thing -- set_held() here is applied
## directly, not RPC'd. The picking-up player's own local carry state is
## a separate concern, targeted at their own peer.

@onready var _package: Node = get_parent()
@onready var _feedback: Node = _package.get_node_or_null(^"PackageFeedbackComponent")


## Called by whoever's tracking "am I looking at this" (see player.gd's
## _physics_process) -- delegates to the sibling component that already
## owns the Box's material, so this doesn't fight it over who controls
## material_override.
func highlight(enabled: bool) -> void:
	if _feedback != null:
		_feedback.call(&"highlight", enabled)


func get_prompt() -> String:
	return "" if bool(_package.get("is_held")) or bool(_package.get("is_loaded")) else "Agarrar paquete"


func can_interact(player: Node) -> bool:
	return not get_prompt().is_empty() and player.get(&"carried_package") == null


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	_package.call(&"set_held", true)
	if player.has_method(&"pick_up"):
		player.rpc_id(int(player.get_multiplayer_authority()), &"pick_up", _package.get_path())
	interacted.emit(player)

extends "res://scripts/gameplay/interaction/interactable.gd"
## Lets a nearby player pick up the package this is attached to.
##
## interact() only ever runs on the host (see interactable.gd), where the
## package is the real, authoritative thing -- set_held() here is applied
## directly, not RPC'd. The picking-up player's own local carry state is
## a separate concern, targeted at their own peer.
##
## A box already mounted in the van can be taken back out: that's the only
## way to walk one up to a DeliveryHouse's door and actually deliver it
## (docs/colaboracion-equipo.md flagged this as the gap that blocked the
## whole house flow -- every house resolved as "missed" because no package
## could ever leave the van).

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
	if bool(_package.get("is_held")):
		return ""
	if _package.has_method(&"assist_available") and bool(_package.call(&"assist_available")):
		return String(_package.call(&"assist_prompt"))
	var action: String = tr("HUD_PROMPT_UNLOAD_PACKAGE") if bool(_package.get("is_loaded")) \
		else tr("HUD_PROMPT_PICK_UP_PACKAGE")
	# In the depot every box carries its bin code (depot.gd), which is what
	# the order board asks for: say which one this is.
	if _package.has_meta(&"dispatch_code"):
		var trap: Resource = _package.get(&"trap_definition")
		var trap_name: String = String(trap.call(&"localized_name")) if trap != null else ""
		return "%s %s  ·  %s" % [action, String(_package.get_meta(&"dispatch_code")), trap_name]
	return action


func can_interact(player: Node) -> bool:
	var peer_id: int = player.get_multiplayer_authority()
	if _package.has_method(&"can_assist") and bool(_package.call(&"can_assist", peer_id)):
		var origin: Vector3 = (player.call(&"reach_origin") if player.has_method(&"reach_origin")
				else (player as Node3D).global_position)
		return player.get(&"carried_package") == null \
				and origin.distance_to((_package as Node3D).global_position) <= DeliveryPackage.ASSIST_REACH
	return not get_prompt().is_empty() and player.get(&"carried_package") == null


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	var peer_id: int = player.get_multiplayer_authority()
	if _package.has_method(&"can_assist") and bool(_package.call(&"can_assist", peer_id)):
		if bool(_package.call(&"set_assistant", peer_id)) and player.has_method(&"assist_package"):
			player.rpc_id(peer_id, &"assist_package", _package.get_path())
		interacted.emit(player)
		return
	_package.call(&"take_by", player)
	interacted.emit(player)

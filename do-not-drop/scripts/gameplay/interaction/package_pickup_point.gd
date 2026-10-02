extends Interactable
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

@onready var _package: DeliveryPackage = get_parent() as DeliveryPackage
@onready var _feedback: PackageFeedback = _package.get_node_or_null(^"PackageFeedbackComponent") as PackageFeedback


## Called by whoever's tracking "am I looking at this" (see player.gd's
## _physics_process) -- delegates to the sibling component that already
## owns the Box's material, so this doesn't fight it over who controls
## material_override.
func highlight(enabled: bool) -> void:
	if _feedback != null:
		_feedback.highlight(enabled)


func get_prompt() -> String:
	if _package.is_held:
		return ""
	if _package.assist_available():
		return _package.assist_prompt()
	var action: String = tr("HUD_PROMPT_UNLOAD_PACKAGE") if _package.is_loaded \
		else tr("HUD_PROMPT_PICK_UP_PACKAGE")
	# In the depot every box carries its bin code (depot.gd), which is what
	# the order board asks for: say which one this is.
	if _package.has_meta(&"dispatch_code"):
		var trap: TrapDefinition = _package.trap_definition
		var trap_name: String = trap.localized_name() if trap != null else ""
		return "%s %s  ·  %s" % [action, String(_package.get_meta(&"dispatch_code")), trap_name]
	return action


## The interactable contract hands over any node in the player group; only a
## Player carries anything or has its own reach (a stand-in carries nothing
## and reaches from where it stands).
func can_interact(player: Node) -> bool:
	var carrier: Player = player as Player
	var hands_free: bool = carrier == null or carrier.carried_package == null
	if _package.can_assist(player.get_multiplayer_authority()):
		var origin: Vector3 = carrier.reach_origin() if carrier != null else (player as Node3D).global_position
		return hands_free and origin.distance_to(_package.global_position) <= DeliveryPackage.ASSIST_REACH
	return not get_prompt().is_empty() and hands_free


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	var peer_id: int = player.get_multiplayer_authority()
	if _package.can_assist(peer_id):
		if _package.set_assistant(peer_id) and player is Player:
			player.rpc_id(peer_id, &"assist_package", _package.get_path())
		interacted.emit(player)
		return
	_package.take_by(player)
	interacted.emit(player)

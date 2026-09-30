class_name Interactable
extends Area3D
## Passive target a player's interaction probe detects and can activate.
## Portable module (docs/modulos.md). Never monitors on its own -- the
## player's probe does the scanning; this just needs to exist on
## `interaction_layer` to be found.
##
## interact() always runs on the host: either called directly (the host's
## own player acting), or bounced here through request_interact() for a
## remote player. Every subclass can keep writing interact() as if it were
## always local, single-player logic -- it always is, from the host's point
## of view.
##
## The player contract: nodes in `player_group`, one per peer, whose
## multiplayer authority is that peer; `reach_origin()` (optional) says
## where their reach starts.

signal interacted(player: Node)

## Configuration (static, the game sets it once if its layers differ).
## The physics layer bit interactables sit on for the probe to find them.
static var interaction_layer: int = 16
static var player_group: StringName = &"player"

@export var prompt: String = "Interact"


func _ready() -> void:
	collision_layer = interaction_layer
	collision_mask = 0
	monitoring = false
	monitorable = true


func get_prompt() -> String:
	return prompt


func can_interact(_player: Node) -> bool:
	return not get_prompt().is_empty()


func interact(player: Node) -> void:
	interacted.emit(player)


## A remote player's client calls this (rpc_id(1, ...)) instead of interact()
## directly. Resolves which player sent it and hands off to the same
## interact() the host's own input uses.
@rpc("any_peer", "call_remote", "reliable")
func request_interact() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var player: Node = find_player(sender_id)
	if player != null and _within_reach(player):
		interact(player)


## How far from a player's feet (or seat) something can be and still be
## used: the reach of their interaction probe, plus room for the time the
## request took to arrive. A client can't work a door across the map.
const REMOTE_REACH: float = 4.5


func _within_reach(player: Node) -> bool:
	var origin: Vector3 = (player as Node3D).global_position
	if player.has_method(&"reach_origin"):
		origin = player.call(&"reach_origin")
	return origin.distance_to(global_position) <= REMOTE_REACH


## The player node a peer controls, or null.
func find_player(peer_id: int) -> Node:
	for player: Node in get_tree().get_nodes_in_group(player_group):
		if player.get_multiplayer_authority() == peer_id:
			return player
	return null


## This client's own player (answers is_local()), or null.
func local_player() -> Node:
	for player: Node in get_tree().get_nodes_in_group(player_group):
		if player.has_method(&"is_local") and bool(player.call(&"is_local")):
			return player
	return null

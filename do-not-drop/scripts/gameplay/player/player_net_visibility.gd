extends RefCounted
## Who the host spawns and syncs a player to (N-225.5), split out of player.gd: only the peers whose level is
## loaded, and what a peer that just got this player is told about them (the box in their hands, N-908).
## Player.gd keeps `_on_peer_level_ready()` (it is the callable the NetworkManager signal is connected
## to) and calls this from `_enter_tree()`.


## Spawned into, and synced to, only the peers whose level is loaded (the
## host's call -- NetworkManager.is_peer_ready()). After a host restart each
## client reloads at its own pace; a spawn sent to one still on the old level
## was lost, and that client never saw this player again. Installed from
## _enter_tree(): set up in _ready, the synchronizer had already registered as
## public, and the host's own player started syncing to clients mid-reload --
## who couldn't resolve it and never saw the host move again.
static func limit_to_ready_peers(p: Player) -> void:
	var sync := p.get_node_or_null(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var network: Node = p.get_node_or_null(^"/root/NetworkManager")
	if sync == null or network == null or network.is_connected(&"peer_level_ready", p._on_peer_level_ready):
		return
	sync.add_visibility_filter(func(peer_id: int) -> bool:
		return not p.multiplayer.is_server() or bool(network.call(&"is_peer_ready", peer_id)))
	if network.has_signal(&"peer_level_ready"):
		network.connect(&"peer_level_ready", p._on_peer_level_ready)


## Host: `peer_id`'s level is up, so this player is spawned and synced to it now. What they carry only
## travels in the pick_up broadcast at the moment they took the box (PackageHandling.take_by()): a peer
## that joined late, or reloaded after a restart, saw this player with empty hands, no carry pose and a
## lap that reserved no bay (SeatTending.lap_reserves()). So the host repeats it to that peer alone, right
## after the spawn: both reliable on channel 0, in that order, so the player exists when it lands. On the
## receiving copy pick_up only sets the box (and the arms' grip); the pickup clip and the trap tip are the
## owner's (player_carry.gd apply_pick_up(), is_local()), whose own player is new at this point anyway.
static func refresh_peer(p: Player, peer_id: int) -> void:
	var sync := p.get_node_or_null(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	if sync == null or not p.multiplayer.is_server():
		return
	sync.update_visibility(peer_id)
	if is_instance_valid(p.carried_package) and p.carried_package.is_inside_tree():
		p.rpc_id(peer_id, &"pick_up", p.carried_package.get_path())

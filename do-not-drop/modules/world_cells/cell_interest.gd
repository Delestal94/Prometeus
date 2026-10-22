class_name WorldCellInterest
extends Node
## Which peers get the updates of each tracked body's MultiplayerSynchronizer, by
## distance in cells to each peer's anchor: a peer far from a body gets none of its
## traffic, while the authority (the host) keeps simulating it as before. The cells
## and radii are a WorldCellGrid's, so a peer gets a body exactly while that body is
## inside the cells a streamer would keep loaded around the peer.
##
## On the host, a tracked synchronizer it owns stops being public and is made
## visible (set_visibility_for) to a peer whose anchor lies within
## `grid.load_radius` cells (Chebyshev) of the body; it is hidden from that peer only
## past `grid.unload_radius` (the gap is the hysteresis, as for the cells). A body a
## client owns is left alone (it goes to the host whatever the distance). It stays
## visible, however far, to:
## - the peers `viewers_of.call(body)` lists (who drives or rides it);
## - a peer `anchor_of.call(peer)` can't place (null): the game doesn't know where
##   that one is yet, so it gets everything, as if this node did not exist.
## This node owns the per-peer flags and `public_visibility` of what it tracks
## (untrack() hands them back, and leaving the tree untracks everything). Any other
## condition the game puts on a synchronizer goes in add_visibility_filter(), which
## Godot checks on top of these flags.
##
## RPCs: SceneMultiplayer doesn't send an RPC called on a synchronizer's root to a peer
## that synchronizer is hidden from, broadcasts included. So a broadcast RPC on a
## tracked body silently skips the far peers, and a one-shot event or a removal (a box
## consumed, a vehicle sold) sent that way leaves a stale copy there for good. Such a
## fact travels as an ON_CHANGE property of the synchronizer (it arrives when the peer
## sees the body again), as an RPC on a node that isn't tracked, or after untrack() or
## release(): release(body) untracks the body and takes it out of `groups`, so no later
## look tracks it again (what a removal calls right before its broadcast).
##
## Not for spawned bodies: a body a MultiplayerSpawner put in the world is despawned
## on a peer that stops seeing it, and spawned again later. track() refuses one whose
## parent is the spawn path of a spawner next to it (the usual layouts), with a
## warning; the others are the game's to keep out.
##
## Keepalive: SceneMultiplayer drops a sync whose 16-bit clock looks older than the
## last one that peer got from the synchronizer, and the clock (one tick per network
## frame of the authority to that peer) wraps after 65536. A body hidden from a peer
## for over half of that (9 min at 60 fps) could be ignored for minutes once it is
## back. So every `keepalive_sec` a hidden body is shown to that peer for
## `keepalive_pulse_sec` (at least two of its replication intervals): a handful of
## updates every 20 s, nothing like a stream.
##
## On a client (`hide_far_copies`), the copy of a tracked body the host owns is hidden
## and taken out of physics (visible = false, and the collision layer and mask of
## every CollisionObject3D in it zeroed, areas included, so nobody bumps into or sits
## in a copy that isn't there): past `grid.unload_radius` cells of this peer's own
## anchor; past `grid.load_radius` once no update came for `copy_stale_sec` (the one
## left behind when the host stopped sending); and, near, while no update ever reached
## it `copy_stale_sec` after it was tracked (a late joiner's copy where the scene put
## it). It shows again within `grid.load_radius` once an update arrived after the last
## look, so it shows where it really is: nobody sees it jump. Processing is never
## switched off: whatever moves the copy (a smoother) keeps running. A collision layer or
## mask written into a hidden copy (by an update, through a replicated property's setter,
## or by the game) is kept for the showing and zeroed again, at that update or at the next
## look: the copy stays out of physics. copy_shown tells the game a copy is back, so it can
## derive again the layers it owns (one written as 0 while hidden can't be told from the
## zeroing).
##
## Bodies come in through track(), or by themselves while they are in one of
## `groups` (each MultiplayerSynchronizer child whose root is the body). Only nodes
## of this node's own multiplayer count (one session; a test runs several in one
## tree). step() is what _process runs; a test calls it with its own clock.

## Client: a copy this node hid shows again, its collision layers given back.
signal copy_shown(body: Node3D)

## Only the cell size and the two radii are read.
var grid := WorldCellGrid.new()
## Callable(peer_id: int) -> Variant: where that peer's anchor is (a Vector3), or null.
var anchor_of: Callable
## Callable(body: Node3D) -> Array: ids of the peers that always get this body. Optional.
var viewers_of: Callable
## Nodes in these groups are tracked by themselves (and untracked when they leave).
var groups: Array[StringName] = []
## Seconds between two looks at the anchors and the bodies.
var update_interval_sec: float = 0.25
## A body hidden from a peer is shown to it for `keepalive_pulse_sec` this often.
var keepalive_sec: float = 20.0
var keepalive_pulse_sec: float = 0.1
## Hide (and take out of physics) the copy of a far body on the clients.
var hide_far_copies: bool = true
## A copy with no update for this long counts as stale: longer than a body at rest is
## sent (NetRestThrottle's 0.5 s) and than a first update takes to arrive.
var copy_stale_sec: float = 1.5

## MultiplayerSynchronizer -> _Entry.
var _entries: Dictionary = {}
## MultiplayerSynchronizer -> true: refused by track() (spawned), not asked again.
var _refused: Dictionary = {}
var _last_update: float = -1.0e9
## The clock of the last step(), what an arriving update is stamped with.
var _clock: float = 0.0


class _Entry:
	var body: Node3D
	var from_group: bool = false
	## public_visibility before track(), given back by untrack().
	var was_public: bool = true
	## Host: peer -> whether it gets the body (the last decision).
	var near: Dictionary = {}
	## Host: peer -> when it was last hidden or pulsed (the keepalive's clock).
	var hidden_at: Dictionary = {}
	## Host: peer -> when the running keepalive pulse ends.
	var pulse_until: Dictionary = {}
	## Copy: this node hid it; an update arrived since the last look; when it was tracked and when
	## the last update arrived (-1: never).
	var hidden_here: bool = false
	var fresh: bool = false
	var tracked_at: float = -1.0
	var synced_at: float = -1.0
	## Copy: CollisionObject3D -> [collision_layer, collision_mask] zeroed while hidden.
	var collisions: Dictionary = {}
	var on_sync: Callable


func _process(_delta: float) -> void:
	step(Time.get_ticks_msec() / 1000.0)


## Hands back everything it holds: public_visibility, the per-peer flags, hidden copies.
func _exit_tree() -> void:
	for sync: Variant in _entries.keys():
		if is_instance_valid(sync):
			untrack(sync)
		else:
			_entries.erase(sync)


## Starts deciding who gets `sync`. `body` is what is measured; unset, the
## synchronizer's root. A body a MultiplayerSpawner put in the world is refused.
func track(sync: MultiplayerSynchronizer, body: Node3D = null) -> void:
	if sync == null or _entries.has(sync):
		return
	var measured: Node3D = body if body != null else sync.get_node_or_null(sync.root_path) as Node3D
	if measured != null and _spawned_here(measured):
		push_warning("WorldCellInterest: %s looks spawned by a MultiplayerSpawner (hiding it would despawn it"
			% measured.name + " on the peer); not tracked")
		_refused[sync] = true
		return
	var entry := _Entry.new()
	entry.body = measured
	entry.was_public = sync.public_visibility
	entry.on_sync = _on_synchronized.bind(sync)
	sync.synchronized.connect(entry.on_sync)
	sync.delta_synchronized.connect(entry.on_sync)
	_entries[sync] = entry


## Stops deciding for `sync`: every connected peer's flag is cleared, it is public
## again if it was, and a copy hidden here shows again.
func untrack(sync: MultiplayerSynchronizer) -> void:
	var entry: _Entry = _entries.get(sync)
	if entry == null:
		return
	_entries.erase(sync)
	if not is_instance_valid(sync):
		return
	if sync.synchronized.is_connected(entry.on_sync):
		sync.synchronized.disconnect(entry.on_sync)
		sync.delta_synchronized.disconnect(entry.on_sync)
	if is_inside_tree() and _is_authority(sync) and multiplayer.is_server():
		var connected: Array = _peers()
		for peer: int in entry.near:
			if connected.has(peer):
				sync.set_visibility_for(peer, false)
		sync.public_visibility = entry.was_public
	_show_copy(entry)


## Lets `body` go: every synchronizer tracked for it is untracked (untrack()) and it leaves
## every one of `groups`, so no later look tracks it again (unless the game puts it back). A
## broadcast RPC called on it right after reaches every peer the game's own visibility
## filters let through.
func release(body: Node3D) -> void:
	if body == null:
		return
	for sync: Variant in _entries.keys():
		if not is_instance_valid(sync):
			_entries.erase(sync)
			continue
		var entry: _Entry = _entries[sync]
		if is_instance_valid(entry.body) and entry.body == body:
			untrack(sync)
	for group: StringName in groups:
		if body.is_in_group(group):
			body.remove_from_group(group)


func is_tracked(sync: MultiplayerSynchronizer) -> bool:
	return _entries.has(sync)


func tracked_count() -> int:
	return _entries.size()


## Host: the peers `sync` goes to now, as decided at the last step (a running
## keepalive pulse counts).
func visible_peers(sync: MultiplayerSynchronizer) -> Array[int]:
	var out: Array[int] = []
	var entry: _Entry = _entries.get(sync)
	if entry == null:
		return out
	for peer: int in entry.near:
		if entry.near[peer] or entry.pulse_until.has(peer):
			out.append(peer)
	return out


## Client: this node hid `sync`'s copy (and took it out of physics).
func is_hidden_here(sync: MultiplayerSynchronizer) -> bool:
	var entry: _Entry = _entries.get(sync)
	return entry != null and entry.hidden_here


## One tick: ends the keepalive pulses that are due, and, if it is time, looks
## at the groups, the anchors and every tracked body.
func step(now_sec: float) -> void:
	_clock = now_sec
	_end_pulses(now_sec)
	if not is_inside_tree() or now_sec - _last_update < update_interval_sec:
		return
	_last_update = now_sec
	_scan_groups()
	var is_host: bool = multiplayer.is_server()
	var peers: Array = []
	var anchors: Dictionary = {}
	var local_anchor: Variant = null
	var asked: bool = false
	for sync: Variant in _entries.keys():
		if not is_instance_valid(sync):
			_entries.erase(sync)
			continue
		var typed := sync as MultiplayerSynchronizer
		var entry: _Entry = _entries[typed]
		if not typed.is_inside_tree() or not is_instance_valid(entry.body) or not entry.body.is_inside_tree():
			continue
		if not asked:
			asked = true
			peers = _peers()
			for peer: int in peers:
				anchors[peer] = _anchor(peer)
			local_anchor = _anchor(multiplayer.get_unique_id())
		if typed.is_multiplayer_authority():
			if is_host:
				# A body a client owns goes to the host whatever the distance: only a host decides.
				_decide(typed, entry, peers, anchors, now_sec)
		elif hide_far_copies and not is_host:
			_follow_copy(entry, local_anchor, now_sec)


## Chebyshev distance in cells between two world positions.
func cell_distance(a: Vector3, b: Vector3) -> int:
	var ca: Vector2i = grid.cell_of(a)
	var cb: Vector2i = grid.cell_of(b)
	return maxi(absi(ca.x - cb.x), absi(ca.y - cb.y))


func _decide(sync: MultiplayerSynchronizer, entry: _Entry, peers: Array, anchors: Dictionary, now: float) -> void:
	if sync.public_visibility:
		sync.public_visibility = false
	for peer: int in entry.near.keys():
		if not peers.has(peer):
			# Gone: its flag can't be cleared any more (the session forgot the peer), only forgotten.
			entry.near.erase(peer)
			entry.hidden_at.erase(peer)
			entry.pulse_until.erase(peer)
	var viewers: Array = []
	if viewers_of.is_valid():
		var listed: Variant = viewers_of.call(entry.body)
		if listed is Array:
			viewers = listed
	for peer: int in peers:
		var near: bool = _is_near(entry, peer, anchors.get(peer), viewers)
		entry.near[peer] = near
		if near:
			entry.hidden_at.erase(peer)
			entry.pulse_until.erase(peer)
		elif not entry.hidden_at.has(peer):
			entry.hidden_at[peer] = now
		elif now - float(entry.hidden_at[peer]) >= keepalive_sec:
			entry.hidden_at[peer] = now
			entry.pulse_until[peer] = now + maxf(keepalive_pulse_sec, 2.0 * sync.replication_interval)
		var want: bool = near or entry.pulse_until.has(peer)
		if sync.get_visibility_for(peer) != want:
			sync.set_visibility_for(peer, want)


func _is_near(entry: _Entry, peer: int, anchor: Variant, viewers: Array) -> bool:
	if not (anchor is Vector3) or viewers.has(peer):
		return true
	var distance: int = cell_distance(entry.body.global_position, anchor)
	if distance <= grid.load_radius:
		return true
	if distance > grid.unload_radius:
		return false
	# In the gap: as it was. A peer seen for the first time in the gap doesn't get it yet.
	return bool(entry.near.get(peer, false))


func _end_pulses(now: float) -> void:
	var connected: Array = []
	var asked: bool = false
	for sync: Variant in _entries:
		var entry: _Entry = _entries[sync]
		if entry.pulse_until.is_empty() or not is_instance_valid(sync):
			continue
		var typed := sync as MultiplayerSynchronizer
		if not asked:
			asked = true
			connected = _peers()
		for peer: int in entry.pulse_until.keys():
			if now < float(entry.pulse_until[peer]):
				continue
			entry.pulse_until.erase(peer)
			if connected.has(peer) and not bool(entry.near.get(peer, false)):
				typed.set_visibility_for(peer, false)


## The client's side, the same hysteresis as the host's: hides past the unload radius, or past the
## load radius when stale, or near but never updated once the grace is over; shows within the load
## radius once an update came since the last look.
func _follow_copy(entry: _Entry, local_anchor: Variant, now: float) -> void:
	if not (local_anchor is Vector3):
		_show_copy(entry)
		return
	if entry.tracked_at < 0.0:
		entry.tracked_at = now
	var distance: int = cell_distance(entry.body.global_position, local_anchor)
	var last: float = entry.synced_at if entry.synced_at >= 0.0 else entry.tracked_at
	var stale: bool = now - last > copy_stale_sec
	var out_of_sight: bool = distance > grid.unload_radius or (stale and distance > grid.load_radius) \
		or (stale and entry.synced_at < 0.0)
	if out_of_sight:
		entry.fresh = false
		_hide_copy(entry)
	elif entry.hidden_here:
		if distance <= grid.load_radius and entry.fresh:
			_show_copy(entry)
		else:
			entry.fresh = false


func _hide_copy(entry: _Entry) -> void:
	if entry.hidden_here:
		_keep_hidden_solids(entry)
		return
	entry.hidden_here = true
	entry.body.visible = false
	var found: Array[Node] = entry.body.find_children("*", "CollisionObject3D", true, false)
	found.append(entry.body)
	for node: Node in found:
		var solid := node as CollisionObject3D
		if solid == null:
			continue
		entry.collisions[solid] = [solid.collision_layer, solid.collision_mask]
		solid.collision_layer = 0
		solid.collision_mask = 0


func _show_copy(entry: _Entry) -> void:
	if not entry.hidden_here:
		return
	entry.hidden_here = false
	_keep_hidden_solids(entry)
	if is_instance_valid(entry.body):
		entry.body.visible = true
	for solid: Variant in entry.collisions:
		if is_instance_valid(solid):
			var saved: Array = entry.collisions[solid]
			(solid as CollisionObject3D).collision_layer = int(saved[0])
			(solid as CollisionObject3D).collision_mask = int(saved[1])
	entry.collisions.clear()
	if is_instance_valid(entry.body):
		copy_shown.emit(entry.body)


func _on_synchronized(sync: MultiplayerSynchronizer) -> void:
	var entry: _Entry = _entries.get(sync)
	if entry == null:
		return
	entry.fresh = true
	entry.synced_at = _clock
	if entry.hidden_here:
		_keep_hidden_solids(entry)


## A hidden copy got an update, is looked at again or is about to show: a layer or mask written
## into it since it was hidden (by an update or by the game; non-zero, as a 0 can't be told from
## the zeroing) is what the showing gives back, and the copy stays out of physics meanwhile.
func _keep_hidden_solids(entry: _Entry) -> void:
	for solid: Variant in entry.collisions:
		if not is_instance_valid(solid):
			continue
		var typed := solid as CollisionObject3D
		var saved: Array = entry.collisions[solid]
		if typed.collision_layer != 0:
			saved[0] = typed.collision_layer
			typed.collision_layer = 0
		if typed.collision_mask != 0:
			saved[1] = typed.collision_mask
			typed.collision_mask = 0


## Whether a MultiplayerSpawner next to it has the body's parent as its spawn path.
func _spawned_here(body: Node) -> bool:
	var parent: Node = body.get_parent()
	if parent == null:
		return false
	for holder: Node in [parent, parent.get_parent()]:
		if holder == null:
			continue
		for child: Node in holder.get_children():
			var spawner := child as MultiplayerSpawner
			if spawner != null and spawner.get_node_or_null(spawner.spawn_path) == parent:
				return true
	return false


func _scan_groups() -> void:
	if groups.is_empty() or not is_inside_tree():
		return
	var seen: Dictionary = {}
	for group: StringName in groups:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or not body.is_inside_tree() or body.multiplayer != multiplayer:
				continue
			for child: Node in body.get_children():
				var sync := child as MultiplayerSynchronizer
				if sync == null or sync.get_node_or_null(sync.root_path) != body:
					continue
				seen[sync] = true
				if not _entries.has(sync) and not _refused.has(sync):
					track(sync, body)
					if _entries.has(sync):
						(_entries[sync] as _Entry).from_group = true
	for sync: Variant in _entries.keys():
		if not is_instance_valid(sync):
			_entries.erase(sync)
		elif (_entries[sync] as _Entry).from_group and not seen.has(sync):
			untrack(sync)
	for sync: Variant in _refused.keys():
		if not seen.has(sync):
			_refused.erase(sync)


func _anchor(peer: int) -> Variant:
	return anchor_of.call(peer) if anchor_of.is_valid() else null


func _peers() -> Array:
	return Array(multiplayer.get_peers()) if is_inside_tree() else []


func _is_authority(sync: MultiplayerSynchronizer) -> bool:
	return sync.is_inside_tree() and sync.is_multiplayer_authority()

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/world_cells/tests/test_world_cells_interest.gd
##
## WorldCellInterest (cell_interest.gd, expansion D-0316): a host and two clients on ENet in this
## process (a SceneMultiplayer each), every one with the same bodies (owned by the host, each with a
## MultiplayerSynchronizer sending its position, a StaticBody3D and an Area3D) in a group, and a
## WorldCellInterest stepped by hand:
## - each peer tracks only its own session's bodies (the group holds all three sessions');
## - on the host a body stops being public; the client whose anchor is in the body's cell gets its
##   updates, the one 5 cells away gets none, and its copy is hidden there at once and taken out of
##   physics (a ray finds no solid there, the area's layer and mask are 0), while the near client's
##   copy stays solid;
## - hysteresis on the host: at 3 cells (the unload radius) a peer keeps what it had, at 2 it gets
##   the body, past 3 it loses it; and on the client: a shown copy 3 cells away that keeps getting
##   updates stays shown, 4 cells away it hides;
## - a peer viewers_of lists, and one without an anchor, get it however far;
## - keepalive: a hidden peer is shown the body for a pulse every keepalive_sec, as long as two of
##   its replication intervals when that is longer than keepalive_pulse_sec, and an update reaches
##   it; the far copy stays hidden; after the pulse, nothing more arrives;
## - a far copy shows again (solid again, its area's layers back) only after an update put it back
##   within the load radius: walking up to the stale copy while the body is far keeps it hidden; a
##   copy keep_shown names (D-0316.2: one this peer predicts) shows at the next look however far and
##   stale, and once let go hides as any copy (copy_hidden tells the game, once); a
##   copy no update ever reached (a late joiner's, where the scene put it, next to its player) stays
##   shown during the grace (copy_stale_sec) and hides after it;
## - a client that leaves is forgotten; a body that leaves the group is untracked: public again,
##   its copy shown again; an interest that leaves the tree hands everything back the same way;
## - a body whose parent is a MultiplayerSpawner's spawn path is refused (not tracked);
## - with new interests on a late body (its synchronizer also sends its solid's layer and mask on
##   change): sent to the far client as a viewer while that client hides its copy as far, an update
##   that writes the layer and mask leaves the copy out of physics (both still 0), and showing it
##   gives back the written ones (not the ones it had when hidden); a layer the game itself writes
##   into the hidden copy's area is zeroed again at the next look and given back at the showing;
##   copy_shown fires then, not before;
## - release(): a broadcast RPC on the late body, hidden from the far client, skips that client; right
##   after release() the same RPC reaches it; the body is untracked, its synchronizer public again,
##   out of the interest's groups but still in the game's others, and a later look doesn't track it.
## Expected in the log: one warning for that refused body.

const PORT: int = 24672
const GROUP: StringName = &"interest_test_bodies"
const CELL: float = 256.0
const CONNECT_SECONDS: float = 10.0
const BODIES: Array[String] = ["Body", "Ghost"]
## The late body's group (the new interests follow only it) and a group of the game's, not theirs.
const LATE_GROUP: StringName = &"interest_test_late"
const OTHER_GROUP: StringName = &"interest_test_other"

var _failures: int = 0
## Peer id -> anchor, read by every side's anchor_of.
var _anchors: Dictionary = {}
## Side index -> updates its body's synchronizer received.
var _received: Array[int] = [0, 0, 0]
var _sides: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []
var _ids: Array[int] = []
## The hand-driven clock of the interests.
var _now: float = 0.0


## The late body: a broadcast RPC (mark) leaves its tag here on the peers it reaches.
class LateBody:
	extends Node3D
	var marks: Array = []

	@rpc("authority", "call_remote", "reliable")
	func mark(tag: String) -> void:
		marks.append(tag)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var up: bool = await _connect()
	_expect(up, "a host and two clients connect on localhost:%d" % PORT)
	if up:
		await _test_session()
	await _close()
	if _failures == 0:
		print("PASS: WorldCellInterest sends a body only to the peers near it, with hysteresis,"
			+ " viewers, keepalive pulses and far copies hidden and out of physics")
	quit(_failures)


func _connect() -> bool:
	for index: int in range(3):
		var side := Node.new()
		side.name = "Side%d" % index
		root.add_child(side)
		set_multiplayer(SceneMultiplayer.new(), side.get_path())
		_sides.append(side)
		var peer := ENetMultiplayerPeer.new()
		var made: Error = peer.create_server(PORT, 2) if index == 0 else peer.create_client("127.0.0.1", PORT)
		if made != OK:
			return false
		_peers.append(peer)
		side.multiplayer.multiplayer_peer = peer
	var ok: bool = await _wait_for(func() -> bool:
		if _sides[0].multiplayer.get_peers().size() != 2:
			return false
		for index: int in [1, 2]:
			if _peers[index].get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
				return false
		return true)
	if not ok:
		return false
	for side: Node in _sides:
		_ids.append(side.multiplayer.get_unique_id())
	for index: int in range(3):
		_add_world(index)
	# The second body: every peer puts it where the scene says; the host's is already far from everyone.
	_body(0, "Ghost").position = Vector3(10.0 * CELL + 5.0, 0.0, 5.0)
	return true


## The same bodies and interest on every side; the bodies are the host's (authority 1).
func _add_world(index: int) -> void:
	var side: Node = _sides[index]
	for body_name: String in BODIES:
		_add_body(side, body_name)
	_sync(index).synchronized.connect(func() -> void: _received[index] += 1)
	_add_interest(index, [GROUP])


## Side `index`'s interest, following `groups` and stepped by hand.
func _add_interest(index: int, groups: Array[StringName]) -> WorldCellInterest:
	var interest := WorldCellInterest.new()
	interest.name = "Interest"
	interest.groups = groups
	interest.keepalive_sec = 1000.0
	interest.anchor_of = func(peer: int) -> Variant: return _anchors.get(peer)
	_sides[index].add_child(interest)
	interest.set_process(false)
	return interest


## A body (`made`, or a plain Node3D) in `group` at (5, 0, 5) sending its position every network
## frame, and each of `on_change` when it changes, with a solid 1 m box ("Solid") and an area ("Zone").
func _add_body(parent: Node, body_name: String, made: Node3D = null, group: StringName = GROUP,
		on_change: Array[NodePath] = []) -> MultiplayerSynchronizer:
	var body: Node3D = made if made != null else Node3D.new()
	body.name = body_name
	body.position = Vector3(5.0, 0.0, 5.0)
	body.add_to_group(group)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_interval = 0.0
	var config := SceneReplicationConfig.new()
	config.add_property(^".:position")
	config.property_set_replication_mode(^".:position", SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	for path: NodePath in on_change:
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = config
	body.add_child(sync)
	var solid := StaticBody3D.new()
	solid.name = "Solid"
	solid.add_child(_box_shape())
	body.add_child(solid)
	var zone := Area3D.new()
	zone.name = "Zone"
	zone.add_child(_box_shape())
	body.add_child(zone)
	parent.add_child(body)
	return sync


func _box_shape() -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	shape.shape = box
	return shape


func _test_session() -> void:
	var host_id: int = _ids[0]
	var near_id: int = _ids[1]
	var far_id: int = _ids[2]
	_anchors[host_id] = Vector3(0.0, 0.0, 0.0)
	_anchors[near_id] = Vector3(10.0, 0.0, 10.0)
	_anchors[far_id] = Vector3(5.0 * CELL + 10.0, 0.0, 10.0)
	_step_all()
	var host_sync := _sync(0)
	for index: int in range(3):
		_expect(_interest(index).tracked_count() == 2,
			"side %d tracks only its own session's two bodies (got %d)" % [index, _interest(index).tracked_count()])
	_expect(not host_sync.public_visibility, "the host's tracked synchronizer is no longer public")
	_expect(_interest(0).visible_peers(host_sync) == [near_id],
		"only the near client gets the body (got %s)" % [_interest(0).visible_peers(host_sync)])
	_expect(not _body(2).visible, "the far client hides its far copy at the first look")
	_expect(_body(1, "Ghost").visible, "a near copy no update reached yet stays shown during the grace")
	await _flow(0.4)
	_step_all()
	_expect(_received[1] > 0, "the near client receives the body's updates (got %d)" % _received[1])
	_expect(_received[2] == 0, "the client 5 cells away receives none (got %d)" % _received[2])
	_expect(_interest(2).is_hidden_here(_sync(2)) and not _body(2).visible,
		"the far client's copy is hidden there")
	_expect(not _solid_hit(2, _body(2).position), "a ray finds no solid in the hidden copy")
	var zone := _sides[2].get_node(^"Body/Zone") as Area3D
	_expect(zone.collision_layer == 0 and zone.collision_mask == 0, "the hidden copy's area is out of physics")
	_expect(_body(1).visible and not _interest(1).is_hidden_here(_sync(1)), "the near client's copy shows")
	_expect(_solid_hit(1, _body(1).position), "and it is solid")
	_expect(_interest(0).visible_peers(_sync(0, "Ghost")).is_empty(), "the host sends the far ghost to nobody")
	_step_all()
	_expect(not _body(1, "Ghost").visible and _body(1, "Ghost").position.distance_to(_anchors[near_id]) < 10.0,
		"after the grace, a copy no update reached hides, even next to the player (where the scene put it)")

	# Hysteresis, on the host: 3 cells keeps it hidden, 2 sends it, 3 keeps it, 4 hides it.
	var steps: Array = [[3, false], [2, true], [3, true], [4, false]]
	for entry: Array in steps:
		_anchors[far_id] = Vector3(float(entry[0]) * CELL + 10.0, 0.0, 10.0)
		_step_all()
		_expect(host_sync.get_visibility_for(far_id) == entry[1],
			"a peer %d cells away gets the body: %s (got %s)" % [entry[0], entry[1],
				host_sync.get_visibility_for(far_id)])

	_interest(0).viewers_of = func(_body_node: Node3D) -> Array: return [far_id]
	_step_all()
	_expect(host_sync.get_visibility_for(far_id), "a listed viewer gets the body however far")
	_interest(0).viewers_of = Callable()
	_anchors.erase(far_id)
	_step_all()
	_expect(host_sync.get_visibility_for(far_id), "a peer with no anchor gets everything")
	_anchors[far_id] = Vector3(4.0 * CELL + 10.0, 0.0, 10.0)
	_step_all()
	_expect(not host_sync.get_visibility_for(far_id), "placed 4 cells away again, it loses it")
	await _test_keepalive(host_sync, far_id)
	await _test_stale_copy(host_sync, far_id)
	await _test_leaving(host_sync, near_id, far_id)
	_test_exit_tree()
	_test_spawned_refused()
	await _test_late_body(far_id)


func _test_keepalive(host_sync: MultiplayerSynchronizer, far_id: int) -> void:
	await _flow(0.3)
	var before: int = _received[2]
	_interest(0).keepalive_sec = 2.0
	_interest(0).keepalive_pulse_sec = 0.1
	# Two replication intervals (0.4 s) are longer than keepalive_pulse_sec: the pulse lasts those.
	host_sync.replication_interval = 0.2
	var hidden_since: float = _now
	_now = hidden_since + 1.0
	_interest(0).step(_now)
	_expect(not host_sync.get_visibility_for(far_id), "no pulse before keepalive_sec")
	_now = hidden_since + 2.0
	_interest(0).step(_now)
	_expect(host_sync.get_visibility_for(far_id), "a pulse at keepalive_sec")
	_expect(_interest(0).visible_peers(host_sync).has(far_id), "visible_peers counts the pulse")
	await _flow(0.5)
	_expect(_received[2] > before, "the pulse's update reaches the far client (%d -> %d)" % [before, _received[2]])
	_interest(2).step(_now + 0.5)
	_expect(_interest(2).is_hidden_here(_sync(2)), "a pulse that leaves the copy far keeps it hidden")
	_now += 0.1
	_interest(0).step(_now)
	_expect(host_sync.get_visibility_for(far_id), "the pulse lasts two replication intervals, not 0.1 s")
	_now += 0.35
	_interest(0).step(_now)
	_expect(not host_sync.get_visibility_for(far_id), "the pulse ends after two replication intervals")
	host_sync.replication_interval = 0.0
	await _flow(0.3)
	var after_pulse: int = _received[2]
	await _flow(0.4)
	_expect(_received[2] == after_pulse, "nothing more arrives between pulses (%d -> %d)" % [after_pulse, _received[2]])
	_interest(0).keepalive_sec = 1000.0


func _test_stale_copy(host_sync: MultiplayerSynchronizer, far_id: int) -> void:
	var hidden_told: Array[int] = [0]
	var on_hidden: Callable = func(body: Node3D) -> void:
		if body == _body(2):
			hidden_told[0] += 1
	_interest(2).copy_hidden.connect(on_hidden)
	# The body goes far from everyone; the far client walks up to where its copy stands.
	_body(0).position = Vector3(10.0 * CELL + 5.0, 0.0, 5.0)
	_anchors[far_id] = Vector3(6.0, 0.0, 6.0)
	_step_all()
	await _flow(0.3)
	_step_all()
	_expect(not host_sync.get_visibility_for(far_id), "the body 10 cells away isn't sent to the far client")
	_expect(_interest(2).is_hidden_here(_sync(2)) and not _body(2).visible,
		"walking up to the stale copy doesn't show it (no update put it there)")
	# A copy keep_shown names (one this peer predicts) is shown at the next look however far and stale, and
	# hidden again once it no longer is.
	_interest(2).keep_shown = func(body: Node3D) -> bool: return body == _body(2)
	_step_all()
	_expect(_body(2).visible and not _interest(2).is_hidden_here(_sync(2)) and _solid_hit(2, _body(2).position),
		"a copy keep_shown names shows, solid, however far and stale")
	# Let go, it follows the rules again: past the unload radius it hides, and walking back up to it, stale, it
	# stays hidden.
	_interest(2).keep_shown = Callable()
	_anchors[far_id] = Vector3(4.0 * CELL + 10.0, 0.0, 10.0)
	_step_all()
	_anchors[far_id] = Vector3(6.0, 0.0, 6.0)
	_step_all()
	_expect(_interest(2).is_hidden_here(_sync(2)) and not _body(2).visible,
		"...and once keep_shown lets it go it hides as any copy (past the unload radius, then stale)")
	_expect(hidden_told[0] == 1, "copy_hidden told the game it hid the copy, once (%d)" % hidden_told[0])
	_interest(2).copy_hidden.disconnect(on_hidden)
	_expect(not _solid_hit(2, _body(2).position), "...nor makes it solid")
	# The body comes back next to that client: an update arrives and the copy shows where it is.
	_body(0).position = Vector3(8.0, 0.0, 8.0)
	_step_all()
	await _flow(0.3)
	_step_all()
	_expect(_body(2).visible and not _interest(2).is_hidden_here(_sync(2)),
		"an update within the load radius shows the copy again")
	_expect(_body(2).position.distance_to(_body(0).position) < 0.001,
		"...where the host has it (got %s)" % [_body(2).position])
	_expect(_solid_hit(2, _body(2).position), "...solid again")
	var zone := _sides[2].get_node(^"Body/Zone") as Area3D
	_expect(zone.collision_layer == 1 and zone.collision_mask == 1, "...and its area's layer and mask are back")
	# Hysteresis on the client: 3 cells away and still updated, the copy stays; 4 cells away it hides.
	_anchors[far_id] = Vector3(3.0 * CELL + 10.0, 0.0, 10.0)
	await _flow(0.3)
	_step_all()
	await _flow(0.3)
	_step_all()
	_expect(host_sync.get_visibility_for(far_id) and _body(2).visible,
		"3 cells away and still updated, the client keeps its copy shown")
	_anchors[far_id] = Vector3(4.0 * CELL + 10.0, 0.0, 10.0)
	_step_all()
	_expect(not _body(2).visible, "4 cells away (past the unload radius) the client hides it")


func _test_leaving(host_sync: MultiplayerSynchronizer, near_id: int, far_id: int) -> void:
	_peers[1].close()
	var gone: bool = await _wait_for(func() -> bool: return not _sides[0].multiplayer.get_peers().has(near_id))
	_expect(gone, "the near client leaves the host's session")
	_anchors[far_id] = Vector3(6.0, 0.0, 6.0)
	_step_all()
	_expect(not _interest(0).visible_peers(host_sync).has(near_id), "a client that left is forgotten")
	_expect(_interest(0).visible_peers(host_sync).has(far_id), "the one that stays keeps its decision")
	# The far client's copy hidden again, then the bodies leave the group: everything is handed back.
	_anchors[far_id] = Vector3(9.0 * CELL, 0.0, 0.0)
	_step_all()
	_expect(not _body(2).visible, "the copy hides once its anchor is 9 cells away")
	_set_grouped(false)
	_step_all()
	_expect(_interest(0).tracked_count() == 0 and _interest(2).tracked_count() == 0,
		"a body that leaves the group is untracked")
	_expect(host_sync.public_visibility, "untracked, the host's synchronizer is public again")
	_expect(not host_sync.get_visibility_for(far_id), "and its per-peer flags are cleared")
	_expect(_body(2).visible and _solid_hit(2, _body(2).position), "and the hidden copy shows, solid, again")


## Tracked again, then the interests leave the tree: the same hand-back as untrack().
func _test_exit_tree() -> void:
	_set_grouped(true)
	_step_all()
	var host_sync := _sync(0)
	_expect(not host_sync.public_visibility and not _body(2).visible, "tracked again: private, the far copy hidden")
	for index: int in [0, 2]:
		var interest: WorldCellInterest = _interest(index)
		_sides[index].remove_child(interest)
		interest.free()
	_expect(host_sync.public_visibility, "an interest leaving the tree makes its synchronizers public again")
	_expect(_body(2).visible and _solid_hit(2, _body(2).position), "and shows its hidden copies, solid")


func _test_spawned_refused() -> void:
	var spawn_root := Node3D.new()
	spawn_root.name = "SpawnRoot"
	_sides[0].add_child(spawn_root)
	var spawner := MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawn_root.add_child(spawner)
	spawner.spawn_path = ^".."
	var sync: MultiplayerSynchronizer = _add_body(spawn_root, "Spawned")
	# Before the next network frame: the clients have no such node to resolve.
	sync.public_visibility = false
	var interest := WorldCellInterest.new()
	_sides[0].add_child(interest)
	interest.set_process(false)
	interest.track(sync)
	_expect(not interest.is_tracked(sync), "a body under a MultiplayerSpawner's spawn path is refused")
	interest.free()
	spawn_root.free()


## New interests on the host and the far client follow LATE_GROUP only; its body is also in a group of
## the game's (OTHER_GROUP) and sends its solid's layer and mask on change.
func _test_late_body(far_id: int) -> void:
	for index: int in [0, 2]:
		_add_interest(index, [LATE_GROUP])
	# The client's node first: the host's synchronizer has to find it there.
	for index: int in [2, 0]:
		_add_body(_sides[index], "Late", LateBody.new(), LATE_GROUP,
			[^"Solid:collision_layer", ^"Solid:collision_mask"])
		_body(index, "Late").add_to_group(OTHER_GROUP)
	await _test_update_while_hidden(far_id)
	await _test_release(far_id)


## The host keeps sending the late body to the far client (a viewer) while that client hides its copy
## as far: what an update writes into the hidden copy's layers waits for the showing.
func _test_update_while_hidden(far_id: int) -> void:
	var host_solid := _sides[0].get_node(^"Late/Solid") as StaticBody3D
	var copy_solid := _sides[2].get_node(^"Late/Solid") as StaticBody3D
	var copy_sync := _sync(2, "Late")
	var deltas: Array[int] = [0]
	copy_sync.delta_synchronized.connect(func() -> void: deltas[0] += 1)
	var shown: Array = []
	_interest(2).copy_shown.connect(func(body: Node3D) -> void: shown.append(body))
	_interest(0).viewers_of = func(_body_node: Node3D) -> Array: return [far_id]
	_anchors[far_id] = Vector3(6.0 * CELL, 0.0, 0.0)
	_step_all()
	await _flow(0.3)
	_step_all()
	_expect(_sync(0, "Late").get_visibility_for(far_id) and _interest(2).is_hidden_here(copy_sync)
		and copy_solid.collision_layer == 0, "a far viewer gets the late body, and hides its copy as far")
	var before: int = deltas[0]
	host_solid.collision_layer = 8
	host_solid.collision_mask = 2
	await _flow(0.3)
	_expect(deltas[0] > before, "the new layer and mask reach the hidden copy (%d -> %d)" % [before, deltas[0]])
	_expect(copy_solid.collision_layer == 0 and copy_solid.collision_mask == 0,
		"an update that writes the hidden copy's layer and mask leaves it out of physics (got %d, %d)"
		% [copy_solid.collision_layer, copy_solid.collision_mask])
	_expect(shown.is_empty(), "copy_shown doesn't fire while the copy stays hidden")
	# The game itself writes a layer into the hidden copy's area: zeroed again at the next look.
	var copy_zone := _sides[2].get_node(^"Late/Zone") as Area3D
	copy_zone.collision_layer = 32
	_step_all()
	_expect(_interest(2).is_hidden_here(copy_sync) and copy_zone.collision_layer == 0,
		"a layer the game writes into a hidden copy is zeroed again at the next look (got %d)"
		% copy_zone.collision_layer)
	_anchors[far_id] = Vector3(6.0, 0.0, 6.0)
	await _flow(0.3)
	_step_all()
	_expect(_body(2, "Late").visible and copy_solid.collision_layer == 8 and copy_solid.collision_mask == 2,
		"shown again, the copy gets the layer and mask the update wrote, not the old ones (got %d, %d)"
		% [copy_solid.collision_layer, copy_solid.collision_mask])
	_expect(copy_zone.collision_layer == 32 and copy_zone.collision_mask == 1,
		"...and its area the layer the game wrote, with the mask it had (got %d, %d)"
		% [copy_zone.collision_layer, copy_zone.collision_mask])
	_expect(shown == [_body(2, "Late")], "copy_shown tells the game the copy is back (got %s)" % [shown])
	_interest(0).viewers_of = Callable()


## A broadcast RPC on the late body skips the far client while it is hidden from it; right after
## release() it reaches it, and the body stays untracked.
func _test_release(far_id: int) -> void:
	var host_body := _body(0, "Late") as LateBody
	var copy := _body(2, "Late") as LateBody
	var host_sync := _sync(0, "Late")
	_anchors[far_id] = Vector3(6.0 * CELL, 0.0, 0.0)
	_step_all()
	_expect(_interest(0).is_tracked(host_sync) and not host_sync.get_visibility_for(far_id),
		"6 cells away the far client doesn't get the late body")
	host_body.rpc(&"mark", "hidden")
	await _flow(0.3)
	_expect(copy.marks.is_empty(), "a broadcast RPC on it skips the peer it is hidden from (got %s)" % [copy.marks])
	_interest(0).release(host_body)
	_expect(not _interest(0).is_tracked(host_sync) and host_sync.public_visibility,
		"release() untracks the body: its synchronizer is public again")
	_expect(not host_body.is_in_group(LATE_GROUP) and host_body.is_in_group(OTHER_GROUP),
		"...and takes it out of the interest's groups, not out of the game's others")
	host_body.rpc(&"mark", "released")
	await _flow(0.3)
	_expect(copy.marks == ["released"],
		"right after release() a broadcast RPC on it reaches the far client (got %s)" % [copy.marks])
	_step_all()
	_expect(_interest(0).tracked_count() == 0, "a later look doesn't track it again")


func _set_grouped(grouped: bool) -> void:
	for index: int in [0, 2]:
		for body_name: String in BODIES:
			if grouped:
				_body(index, body_name).add_to_group(GROUP)
			else:
				_body(index, body_name).remove_from_group(GROUP)


## Whether a ray down through `at` hits side `index`'s Body/Solid (every other solid excluded).
func _solid_hit(index: int, at: Vector3) -> bool:
	var exclude: Array[RID] = []
	for side_index: int in range(_sides.size()):
		for body_name: String in BODIES:
			var solid := _sides[side_index].get_node_or_null("%s/Solid" % body_name) as CollisionObject3D
			if solid != null and not (side_index == index and body_name == "Body"):
				exclude.append(solid.get_rid())
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 5.0, at + Vector3.DOWN * 5.0)
	query.exclude = exclude
	return not root.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _step_all() -> void:
	_now += 1.0
	for index: int in range(_sides.size()):
		var interest := _sides[index].get_node_or_null(^"Interest") as WorldCellInterest
		if interest != null and _peers[index].get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
			interest.step(_now)


## Real frames for the network, with the host's bodies nudged every frame so they always have news.
func _flow(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	var wobble: float = 0.0
	while Time.get_ticks_msec() < deadline:
		wobble = 0.001 - wobble
		for body_name: String in ["Body", "Late"]:
			var body := _sides[0].get_node_or_null(body_name) as Node3D
			if body != null:
				body.position.y = wobble
		await process_frame


func _interest(index: int) -> WorldCellInterest:
	return _sides[index].get_node(^"Interest") as WorldCellInterest


func _body(index: int, body_name: String = "Body") -> Node3D:
	return _sides[index].get_node(body_name) as Node3D


func _sync(index: int, body_name: String = "Body") -> MultiplayerSynchronizer:
	return _sides[index].get_node("%s/Sync" % body_name) as MultiplayerSynchronizer


## The bodies go while their sessions are still up, then the sessions.
func _close() -> void:
	for side: Node in _sides:
		for child: Node in side.get_children():
			child.free()
	await process_frame
	for index: int in range(_peers.size() - 1, -1, -1):
		if _peers[index].get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
			_peers[index].close()
	await process_frame
	for side: Node in _sides:
		set_multiplayer(null, side.get_path())
		side.free()


func _wait_for(condition: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(CONNECT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

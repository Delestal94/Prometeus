extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_split_crew.gd
##
## The crew split between the shed and the street (expansion D-0316; CompanyInterest,
## scripts/gameplay/districts/company_interest.gd, over the world_cells module's WorldCellInterest).
## Three ENet peers in this process (a SceneMultiplayer each) hold the same company world stand-in:
## three crew members (CompanyRoot.CREW_GROUP, each owned by its peer and sending its position), a
## vehicle (CompanyTrips.VEHICLE_GROUP) and a loose box riding in its bay
## (CompanyInterest.LOOSE_BOX_GROUP), both the host's and sent by a MultiplayerSynchronizer, and a
## CompanyInterest and CompanyCells fed by CompanyInterest.cell_anchors() as CompanyRoot does (the
## company vehicle doesn't exist yet: D-0302.2). The host and one client ride the vehicle from the
## yard to 1.1 km north and back; the other client stays in the shed.
## - While the vehicle is far, the shed client receives no update of the vehicle nor of the box (the
##   counters of their synchronizers stand still) and its stale copies end up hidden; the rider keeps
##   receiving both. The host stopped sending them to the shed only past the unload radius (3 cells
##   from the shed player) and sent them again from the load radius (2 cells) on the way back.
## - The shed client's cells never load around the trip (only its own player anchors them); the
##   host's and the rider's load the vehicle's cell.
## - Nobody teleports: on every peer, every crew member and every shown copy of the vehicle and the
##   box moves at most TELEPORT_M from one tick to the next, and the shed player never moves.
## - Back in the yard every peer sees the vehicle, the box and the three players in the same place,
##   and the shed client's copies show and receive updates again.

const PORT: int = 24671
const CONNECT_SECONDS: float = 10.0
const CELL: float = CompanyTuning.CELL_SIZE
## Where the shed player stands (CompanyRoot.SPAWN) and where the vehicle waits, at the north exit.
const SHED_SPOT: Vector3 = Vector3(0.0, 1.0, 2.6)
const YARD: Vector3 = Vector3(0.0, 0.0, -8.0)
## How far north the trip goes (cell -5: 5 cells from the shed) and how fast (metres a physics tick).
const FAR_Z: float = -1100.0
const STEP_M: float = 6.0
## The two seats (host, rider) and the bay, in the vehicle's space.
const SEATS: Array[Vector3] = [Vector3(-0.5, 1.2, 0.4), Vector3(0.5, 1.2, 0.4)]
const BAY: Vector3 = Vector3(0.0, 0.6, 1.8)
## A frame stall makes up to 8 physics ticks at once (48 m); a copy shown at an old place and then
## at the real one jumps a cell (256 m) at least.
const TELEPORT_M: float = 100.0
## Updates the host sent before it stopped may still be on their way: the quiet window starts this
## long and this many frames later (a loaded runner draws few frames a second).
const IN_FLIGHT_SEC: float = 0.3
const IN_FLIGHT_FRAMES: int = 10
const SAME_M: float = 0.05
const SETTLE_SECONDS: float = 3.0
const FAR_DWELL_SECONDS: float = 1.0

var _failures: int = 0
var _sides: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []
var _ids: Array[int] = []
## [side][body name] -> updates its synchronizer received.
var _received: Array[Dictionary] = []
## [side][node name] -> last position seen while shown (null when it wasn't), and the worst jump.
var _last_seen: Array[Dictionary] = []
var _worst_jump: Dictionary = {}
var _shed_spot_drift: float = 0.0
## Per far body (Van, Box), what happened to the shed client: when and where the host hid it and
## showed it again, and the counters at the start and end of the quiet window.
var _flips: Dictionary = {}
var _rider_ever_hidden: bool = false
var _rider_copy_ever_hidden: bool = false
var _shed_far_cell_loaded: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var up: bool = await _connect()
	_expect(up, "Three ENet peers connect on localhost:%d" % PORT)
	if up:
		await _trip()
	await _close()
	if _failures == 0:
		print("PASS: split crew: the shed client gets nothing of the far vehicle and box, the riders do,"
			+ " nobody teleports and all see the same on return")
	quit(_failures)


func _connect() -> bool:
	for index: int in range(3):
		var side := Node.new()
		side.name = "Peer%d" % index
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
		return true, CONNECT_SECONDS)
	if not ok:
		return false
	for side: Node in _sides:
		_ids.append(side.multiplayer.get_unique_id())
	for index: int in range(3):
		_add_world(index)
	return true


## The same nodes, at the same places, on every peer.
func _add_world(index: int) -> void:
	var side: Node = _sides[index]
	var world := Node3D.new()
	world.name = "World"
	side.add_child(world)
	var counts: Dictionary = {}
	_received.append(counts)
	_last_seen.append({})
	var places: Array[Vector3] = [YARD + SEATS[0], YARD + SEATS[1], SHED_SPOT]
	for crew: int in range(3):
		var member: Node3D = _body("Crew_%d" % _ids[crew], places[crew], _ids[crew], 1.0 / 30.0)
		member.add_to_group(CompanyRoot.CREW_GROUP)
		world.add_child(member)
	var van: Node3D = _body("Van", YARD, 1, 1.0 / 60.0)
	van.add_to_group(CompanyTrips.VEHICLE_GROUP)
	world.add_child(van)
	var box: Node3D = _body("Box", YARD + BAY, 1, 1.0 / 30.0)
	box.add_to_group(CompanyInterest.LOOSE_BOX_GROUP)
	world.add_child(box)
	for body: Node3D in [van, box]:
		var body_name: String = String(body.name)
		counts[body_name] = 0
		var sync := body.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
		for received: Signal in [sync.synchronized, sync.delta_synchronized]:
			received.connect(func() -> void: counts[body_name] += 1)
	var interest := CompanyInterest.new()
	interest.name = "Interest"
	interest.crew_group = CompanyRoot.CREW_GROUP
	side.add_child(interest)
	var cells := CompanyCells.new()
	cells.name = "WorldCells"
	side.add_child(cells)


## A stand-in body owned by `authority` that sends its position every `interval` seconds.
func _body(body_name: String, pos: Vector3, authority: int, interval: float) -> Node3D:
	var body := Node3D.new()
	body.name = body_name
	body.position = pos
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSynchronizer"
	sync.replication_interval = interval
	var config := SceneReplicationConfig.new()
	config.add_property(^".:position")
	config.property_set_replication_mode(^".:position", SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	body.add_child(sync)
	body.set_multiplayer_authority(authority)
	return body


func _trip() -> void:
	var shed_id: int = _ids[2]
	var rider_id: int = _ids[1]
	var warm: bool = await _ticks_until(func() -> bool:
		for name_key: String in ["Van", "Box"]:
			var sync: MultiplayerSynchronizer = _sync(0, name_key)
			if not _interest(0).is_tracked(sync) or sync.public_visibility:
				return false
			if not (sync.get_visibility_for(shed_id) and sync.get_visibility_for(rider_id)):
				return false
			if int(_received[1][name_key]) < 3 or int(_received[2][name_key]) < 3:
				return false
		return true, CONNECT_SECONDS)
	_expect(warm, "In the yard both clients get the vehicle and the box through the host's interest")
	for name_key: String in ["Van", "Box"]:
		_flips[name_key] = {}
	await _drive_to(FAR_Z)
	await _hold(FAR_DWELL_SECONDS)
	var far_cell: Vector2i = _cells(0).grid.cell_of(_node(0, "Van").global_position)
	_expect(_cells(0).is_loaded(far_cell), "The host's cells load around the far vehicle (%s)" % far_cell)
	_expect(_cells(1).is_loaded(far_cell), "The rider's cells load around the far vehicle (%s)" % far_cell)
	_expect(not _cells(2).is_loaded(far_cell), "The shed client's cells don't load the trip's cell (%s)" % far_cell)
	await _drive_to(YARD.z)
	var same: bool = await _ticks_until(_all_see_the_same, SETTLE_SECONDS)
	_expect(same, "Back in the yard every peer sees the vehicle, the box and the crew in the same place")
	_check_window()
	_check_motion()


## The host drives the vehicle (and its riders and box ride along) until it is at `z`.
func _drive_to(z: float) -> void:
	var van: Node3D = _node(0, "Van")
	while not is_equal_approx(van.position.z, z):
		van.position.z = move_toward(van.position.z, z, STEP_M)
		await physics_frame
		_tick()


func _hold(seconds: float) -> void:
	await _ticks_until(func() -> bool: return false, seconds)


## Every physics tick: the riders follow their copy of the vehicle, the host's box rides in its bay,
## the cells follow the anchors, and what each peer shows is recorded.
func _tick() -> void:
	var host_van: Node3D = _node(0, "Van")
	_node(0, "Box").position = host_van.position + BAY
	_node(0, "Crew_%d" % _ids[0]).position = host_van.position + SEATS[0]
	_node(1, "Crew_%d" % _ids[1]).position = _node(1, "Van").position + SEATS[1]
	for index: int in range(_sides.size()):
		_cells(index).anchors = CompanyInterest.cell_anchors(
			_sides[index], CompanyRoot.CREW_GROUP, CompanyTrips.VEHICLE_GROUP, index == 0)
		_record(index)
	for cell: Vector2i in _cells(2).loaded_cells():
		if cell.y <= -(CompanyTuning.CELL_UNLOAD_RADIUS + 1):
			_shed_far_cell_loaded = true
	_watch_flips()


## Jumps of whatever this peer shows, and the shed player's drift.
func _record(index: int) -> void:
	var names: Array[String] = ["Van", "Box"]
	for id: int in _ids:
		names.append("Crew_%d" % id)
	for node_name: String in names:
		var node: Node3D = _node(index, node_name)
		var last: Variant = _last_seen[index].get(node_name)
		if not node.visible:
			_last_seen[index][node_name] = null
			continue
		if last is Vector3:
			var key: String = "peer %d %s" % [index, node_name]
			_worst_jump[key] = maxf(float(_worst_jump.get(key, 0.0)), node.position.distance_to(last))
		_last_seen[index][node_name] = node.position
	_shed_spot_drift = maxf(_shed_spot_drift, _node(index, "Crew_%d" % _ids[2]).position.distance_to(SHED_SPOT))


## On the host: when it stops and starts sending the far bodies to the shed client, and the shed
## client's counters at the start (IN_FLIGHT_SEC after it stopped) and the end of that window.
func _watch_flips() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	for name_key: String in _flips:
		var flip: Dictionary = _flips[name_key]
		var sync: MultiplayerSynchronizer = _sync(0, name_key)
		var to_shed: bool = sync.get_visibility_for(_ids[2])
		if not sync.get_visibility_for(_ids[1]):
			_rider_ever_hidden = true
		if not _node(1, name_key).visible:
			_rider_copy_ever_hidden = true
		var body_z: float = _node(0, name_key).global_position.z
		if not to_shed and not flip.has("hidden_at"):
			flip["hidden_at"] = now
			flip["hidden_frame"] = Engine.get_process_frames()
			flip["hidden_z"] = body_z
		if flip.has("hidden_at") and not flip.has("start") and now - float(flip["hidden_at"]) >= IN_FLIGHT_SEC \
				and Engine.get_process_frames() - int(flip["hidden_frame"]) >= IN_FLIGHT_FRAMES:
			flip["start"] = [int(_received[2][name_key]), int(_received[1][name_key])]
			flip["shed_copy"] = _node(2, name_key).position
		if to_shed and flip.has("start") and not flip.has("end"):
			flip["shown_z"] = body_z
			flip["end"] = [int(_received[2][name_key]), int(_received[1][name_key])]
			flip["shed_copy_end"] = _node(2, name_key).position
			flip["shed_shown"] = _node(2, name_key).visible


func _check_window() -> void:
	var unload_edge: float = -float(CompanyTuning.CELL_UNLOAD_RADIUS) * CELL
	var load_edge: float = -float(CompanyTuning.CELL_LOAD_RADIUS) * CELL
	for name_key: String in _flips:
		var flip: Dictionary = _flips[name_key]
		_expect(flip.has("start") and flip.has("end"),
			"The host stopped and then started again sending the %s to the shed client (%s)" % [name_key, flip])
		if not (flip.has("start") and flip.has("end")):
			continue
		_expect(float(flip["hidden_z"]) < unload_edge,
			"The %s was hidden from the shed only past the unload radius (z %.0f < %.0f)"
			% [name_key, flip["hidden_z"], unload_edge])
		_expect(float(flip["shown_z"]) >= load_edge,
			"The %s was sent to the shed again only within the load radius (z %.0f >= %.0f)"
			% [name_key, flip["shown_z"], load_edge])
		var start: Array = flip["start"]
		var end: Array = flip["end"]
		_expect(int(end[0]) == int(start[0]),
			"While far, the shed client receives no update of the %s (%d -> %d)" % [name_key, start[0], end[0]])
		_expect(int(end[1]) > int(start[1]) + 30,
			"While far, the rider keeps receiving the %s (%d -> %d)" % [name_key, start[1], end[1]])
		_expect((flip["shed_copy"] as Vector3).is_equal_approx(flip["shed_copy_end"]),
			"The shed client's copy of the %s stands still while far" % name_key)
		_expect(not bool(flip["shed_shown"]),
			"The shed client hides its stale copy of the %s (and takes it out of physics)" % name_key)
		_expect(int(_received[2][name_key]) > int(end[0]),
			"Back near, the shed client receives the %s again (%d -> %d)" % [name_key, end[0], _received[2][name_key]])
		_expect(_node(2, name_key).visible, "Back near, the shed client shows the %s again" % name_key)
	_expect(not _rider_ever_hidden, "The host never stops sending the vehicle and the box to the rider")
	_expect(not _rider_copy_ever_hidden, "The rider never hides the vehicle or the box it rides with")
	_expect(not _shed_far_cell_loaded, "The shed client never loads a cell past its unload radius")


func _check_motion() -> void:
	var worst_key: String = ""
	var worst: float = 0.0
	for key: String in _worst_jump:
		if float(_worst_jump[key]) > worst:
			worst = float(_worst_jump[key])
			worst_key = key
	_expect(worst <= TELEPORT_M, "Nothing shown jumps more than %.0f m in a tick (worst %.1f m: %s)"
		% [TELEPORT_M, worst, worst_key])
	_expect(_worst_jump.size() == 15, "Every body was watched on every peer (got %d)" % _worst_jump.size())
	_expect(_shed_spot_drift < 0.01, "The shed player never moves on any peer (drift %.3f m)" % _shed_spot_drift)


func _all_see_the_same() -> bool:
	for node_name: String in ["Van", "Box", "Crew_%d" % _ids[0], "Crew_%d" % _ids[1], "Crew_%d" % _ids[2]]:
		var reference: Vector3 = _node(0, node_name).position
		for index: int in [1, 2]:
			var node: Node3D = _node(index, node_name)
			if not node.visible or node.position.distance_to(reference) > SAME_M:
				return false
	return true


## Physics ticks (each one a _tick()) until `condition` holds or `seconds` pass.
func _ticks_until(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await physics_frame
		_tick()
	return condition.call()


func _node(index: int, node_name: String) -> Node3D:
	return _sides[index].get_node("World/%s" % node_name) as Node3D


func _sync(index: int, node_name: String) -> MultiplayerSynchronizer:
	return _sides[index].get_node("World/%s/MultiplayerSynchronizer" % node_name) as MultiplayerSynchronizer


func _interest(index: int) -> CompanyInterest:
	return _sides[index].get_node(^"Interest") as CompanyInterest


func _cells(index: int) -> CompanyCells:
	return _sides[index].get_node(^"WorldCells") as CompanyCells


## The worlds go while their sessions are still up, then the sessions.
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


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

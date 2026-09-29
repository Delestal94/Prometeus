extends SceneTree
## Three-process network check (tareas de Nacho N-207): one host and two ENet
## clients on localhost, the second joining late. Run them with
## tools/run-net-trio.sh, which starts all three and compares what they print:
##   Godot --headless --path do-not-drop --script res://tests/net_trio.gd -- --host
##   Godot --headless --path do-not-drop --script res://tests/net_trio.gd -- --client --name=a
##   Godot --headless --path do-not-drop --script res://tests/net_trio.gd -- --client --name=b
##
## Each process loads the real level once its session is ready, waits until
## it sees all three players, and prints one TRIO line: the session seed, the
## number of houses, the depot's orders, a hash of the generated road (every
## segment and house, placed where it stands) and the phase of the first
## rail crossing once the host has set it off. All three lines must match.
## Then both clients reach for the same box at once (N-213: two crew members
## going for the one that fell out): the host resolves it, so exactly one of
## them ends up holding it and every peer names the same holder.
##
## As with net_smoke.gd: on Windows use the plain (non "_console") Godot
## executable, the one the firewall rule was approved for.

const PORT: int = 17991
const TIMEOUT_MSEC: int = 60000
const PLAYERS: int = 3
## After seeing the crossing start, how long to wait before reading its
## phase: inside its first phase (warning, 1.2 s) on every peer.
const CROSSING_READ_SECONDS: float = 0.5
## A client stands this far to one side of the contested box (a to one side,
## b to the other), well inside the host's reach check (interactable.gd).
const GRAB_OFFSET: float = 0.9
## After stepping next to the box, how long a client waits for the host to
## see it there before asking to pick it up.
const GRAB_SETTLE_SECONDS: float = 1.0
## How long every peer waits, from the crossing read, before saying who holds
## the box: the clients' requests go out at GRAB_SETTLE_SECONDS.
const GRAB_READ_SECONDS: float = 3.0

var _network: Node
var _level: Node
var _host: bool = false
var _name: String = "host"


func _initialize() -> void:
	await process_frame
	_network = root.get_node(^"/root/NetworkManager")
	_network.set(&"transport", 2)  # NetworkManager.Transport.ENET
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_host = "--host" in args
	for arg: String in args:
		if arg.begins_with("--name="):
			_name = arg.get_slice("=", 1)
	_network.connect(&"session_ready", func(_is_host: bool) -> void: _load_level.call_deferred())
	# NETLOG, not TRIO: run-net-trio.sh takes the first TRIO line as the result.
	_network.connect(&"session_failed", func(reason: String) -> void:
		print("NETLOG role=%s session failed at %.1f s: %s" % [_name, Time.get_ticks_msec() / 1000.0, reason]))
	var error: Error = _network.call(&"host_session", PORT) if _host else _network.call(&"join_session", "127.0.0.1", PORT)
	if error != OK:
		print("TRIO role=%s FAIL could not %s (error %d)" % [_name, "host" if _host else "join", error])
		quit(1)
		return
	if _host:
		# A session whose road has a rail crossing, so the crossing check
		# always runs, built for the whole crew up front: with fewer houses
		# the host restarts the level 3 s after the last one joins
		# (level_base.gd, _on_peer_level_ready), freeing it mid-check.
		# The clients get the seed in the handshake, like any other session.
		_network.set(&"world_house_count", _crew_houses())
		_network.set(&"world_seed", _seed_with_crossing())
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		root.multiplayer.poll()
		await process_frame
		if _level != null and get_nodes_in_group(&"player").size() >= PLAYERS:
			await _report()
			return
	print("TRIO role=%s FAIL timed out: level %s, %d players seen" % [_name, "loaded" if _level != null else "not loaded", get_nodes_in_group(&"player").size()])
	quit(1)


func _load_level() -> void:
	var began: int = Time.get_ticks_msec()
	_level = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(_level)
	current_scene = _level
	var now: int = Time.get_ticks_msec()
	print("NETLOG role=%s level loaded at %.1f s (took %.1f s)" % [_name, now / 1000.0, (now - began) / 1000.0])


func _report() -> void:
	var route: Node3D = _level.get_node(^"World/Route")
	var crossing: Node = _first_crossing(route)
	var phase: String = "none"
	if crossing != null:
		if _host:
			# Give both clients a moment on the level, then set it off for all.
			await _pump(1.0)
			crossing.rpc(&"_begin_cycle")
		var waited: float = 0.0
		while int(crossing.get(&"state")) == 0 and waited < 10.0:
			await _pump(0.05)
			waited += 0.05
		await _pump(CROSSING_READ_SECONDS)
		phase = str(int(crossing.get(&"state")))
	var grab: String = await _contest_box()
	var orders: Array = []
	for order: Dictionary in _level.get_node(^"World/Depot").get(&"orders"):
		orders.append("%s:%s" % [order.package_id, order.code])
	print("TRIO role=%s seed=%d houses=%d orders=%s route=%d crossing=%s grab=%s" % [
		_name, int(_network.get(&"world_seed")), (route.get(&"houses") as Array).size(), ",".join(orders),
		_route_hash(route), phase, grab])
	# The host stays up a little so the clients' own reads aren't cut short.
	await _pump(4.0 if _host else 1.0)
	_network.call(&"leave_session")
	quit(0)


## Both clients step up to the same box and ask the host for it in the same
## moment (the crossing just synced them). Returns the peer id of whoever
## holds it afterwards, or a FAIL marker if nobody or more than one does.
func _contest_box() -> String:
	var box: Node3D = _contested_box()
	if box == null:
		return "FAIL-no-box"
	if not _host:
		var me: Node3D = _own_player()
		if me == null:
			return "FAIL-no-player"
		var side: float = -1.0 if _name == "a" else 1.0
		me.global_position = box.global_position + Vector3(side * GRAB_OFFSET, 0.0, 0.0)
		await _pump(GRAB_SETTLE_SECONDS)
		box.get_node(^"InteractionArea").rpc_id(1, &"request_interact")
		await _pump(GRAB_READ_SECONDS - GRAB_SETTLE_SECONDS)
	else:
		await _pump(GRAB_READ_SECONDS)
	var holders: PackedStringArray = []
	for player: Node in get_nodes_in_group(&"player"):
		if player.get(&"carried_package") == box:
			holders.append(str(player.get_multiplayer_authority()))
	if holders.size() != 1:
		return "FAIL-%d-holders" % holders.size()
	if holders[0] == "1":
		return "FAIL-host-holds"
	return holders[0]


## The same box on every peer: the level's cargo, first by id.
func _contested_box() -> Node3D:
	var boxes: Array = (_level.get(&"packages") as Array).filter(
			func(p: Node) -> bool: return is_instance_valid(p))
	if boxes.is_empty():
		return null
	boxes.sort_custom(func(x: Node, y: Node) -> bool:
		return String(x.get(&"package_id")) < String(y.get(&"package_id")))
	return boxes[0]


func _own_player() -> Node3D:
	for player: Node in get_nodes_in_group(&"player"):
		if player.get_multiplayer_authority() == root.multiplayer.get_unique_id():
			return player
	return null


func _seed_with_crossing() -> int:
	for candidate: int in range(101, 100000, 2):
		for segment: Dictionary in _route_script().call(&"plan_spine", candidate, _crew_houses()).segments:
			if segment.script == RailCrossingSegment:
				return candidate
	return 101


## Loaded when used, not preloaded: route.gd reads autoloads.
func _route_script() -> Script:
	return load("res://scripts/gameplay/route/route.gd")


## Houses the level would restart to for PLAYERS (route.gd crew_house_count).
func _crew_houses() -> int:
	return int(_route_script().call(&"crew_house_count", PLAYERS))


func _first_crossing(route: Node) -> Node:
	for segment: Node in route.get(&"_segments"):
		if segment is RailCrossingSegment:
			return segment
	return null


## Every segment (type and pose) and every house, rounded to the centimetre.
func _route_hash(route: Node3D) -> int:
	var parts: PackedStringArray = []
	for segment: Node3D in route.get(&"_segments"):
		parts.append("%s@%s" % [segment.get_script().get_global_name(), segment.transform.origin.snapped(Vector3.ONE * 0.01)])
	for house: Node3D in route.get(&"houses"):
		parts.append("house@%s" % house.position.snapped(Vector3.ONE * 0.01))
	return "|".join(parts).hash()


func _pump(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		root.multiplayer.poll()
		await process_frame

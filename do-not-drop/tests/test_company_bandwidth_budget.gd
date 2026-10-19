extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_bandwidth_budget.gd
##
## Bandwidth budget of the company mode's shed (D-2002.1, the numbers are in docs/rendimiento-pc.md):
## what the host sends one client while the crew works in the shed fits 24 KB/s.
## - Model (tests/bandwidth_model.gd, the framing test_net_bandwidth_budget counts with): the real
##   company world (company_root.tscn, solo) is opened and every MultiplayerSynchronizer in it is
##   counted, the shed's own once (the host's) and the player's once per crew member (the host's
##   own, the other clients' relayed by the host); floats as 64-bit and ints as 32-bit (a pose in
##   motion, a clock past 33 s) and a datagram at Steam's ceiling around every packet. On top, the
##   business events (CompanyNet's _apply_event, reliable, sized the same way) of a busy packing
##   line: every player does a business action a second
##   (ACTIONS_PER_PLAYER_PER_SECOND) plus the host's own rules, each the size of the largest real
##   units_moved the root publishes (a drop and a take through CompanyNet), in a datagram of its own.
## - For the crew D-2002 measures with (MEASURED_CREW, 4 peers) it fits 24 KB/s, and nothing in the
##   world sends a property of more than 64 bytes every tick. The full crew
##   (NetworkManager.MAX_PLAYERS) is printed with its culprits in order, and an over_budget line
##   when it doesn't fit: a finding to plan, not a failure.
## - Measured, for both crews: that many ENet peers on localhost in this process (a SceneMultiplayer
##   each), each with a real player per peer (player.tscn, standing still) and a CompanyNet, the
##   host publishing real units_moved at the busy rate, read as the network overlay reads LAN
##   (NetStats, N-216). For MEASURED_CREW what each client receives (the overlay's KB/s plus IP and
##   UDP) fits the budget, stays under the model's ceiling and is over half of the model's data (it
##   did flow; skipped and printed under two frames a player's send), and every client applies
##   every event. The full crew's run is only printed (`skipped` if its session doesn't come up).
## - The late-join snapshot of the furnished shed, a one-off burst, is printed.
## Prints `COMPANY_BW key=value` lines. Pending (D-2002.2): one trip outside (40 KB/s) and two
## vehicles far away (64 KB/s), once the company world has a vehicle.

const MODEL := preload("res://tests/bandwidth_model.gd")
const SCENE: String = "res://scenes/gameplay/company_root.tscn"
## The company saves here (the root saves on leaving), never in the game's slot.
const SAVE_DIR: String = "user://test_company_bandwidth_budget"
const PREFIX: String = "COMPANY_BW"
const KB: float = 1024.0
## D-2002's budgets, host -> one client: in the shed; with one trip outside and with two vehicles
## far away (those two are D-2002.2's, printed only).
const SHED_BUDGET: float = 24.0 * KB
const TRIP_BUDGET: float = 40.0 * KB
const FAR_BUDGET: float = 64.0 * KB
## The crew D-2002 measures with (4 ENet peers); the full crew is NetworkManager.MAX_PLAYERS.
const MEASURED_CREW: int = 4
## A busy packing line: every player does a business action (take, store, place, tape: a request
## the host turns into an event for everyone) a second, plus the host's own rules (orders, the
## clock, the day's phases). A human does one every 2-3 s; RpcGuard caps a peer at 20 a second.
const ACTIONS_PER_PLAYER_PER_SECOND: float = 1.0
const HOST_EVENTS_PER_SECOND: float = 1.0
## As test_net_bandwidth_budget: a property sent every tick is a pose or a flag.
const MAX_ALWAYS_PROPERTY_BYTES: int = 64
## What a drop and a take move (a hand holds CompanyTuning.HAND_MAX_UNITS).
const UNITS: int = 3
## The host's port of the first measured crew; the next one takes the next port.
const PORT: int = 24652
const CONNECT_SECONDS: float = 10.0
## Path caches confirmed and the player's appearance sent before the count starts.
const WARMUP_SECONDS: float = 1.0
const MEASURE_SECONDS: float = 3.0

var _failures: int = 0
var _sync_mtu: int = 1350
var _product: StringName = &""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clean()
	_product = _first_product()
	_expect(_product != &"", "There is a product in %s to move" % CompanyAsk.PRODUCTS_DIR)
	var scene_multiplayer := root.multiplayer as SceneMultiplayer
	if scene_multiplayer != null:
		_sync_mtu = scene_multiplayer.max_sync_packet_size
	var full_crew: int = int(root.get_node(^"/root/NetworkManager").get(&"MAX_PLAYERS"))
	_expect(full_crew >= MEASURED_CREW, "NetworkManager.MAX_PLAYERS is read (got %d)" % full_crew)
	var world: Dictionary = await _open_world()
	var syncs: Dictionary = world.syncs
	var events: Dictionary = world.events
	_line("mtu", str(_sync_mtu))
	_line("player_synchronizers", ", ".join(PackedStringArray(syncs.player_names)))
	_line("shed_synchronizers", ", ".join(PackedStringArray(syncs.shed_names))
		if not syncs.shed_names.is_empty() else "none")
	_line("event_bytes", "%d (%s); largest of any kind %d (%s)" % [
		events.busy_bytes, events.busy_kind, events.largest_bytes, events.largest_kind])
	_line("snapshot_bytes", "%d compressed, %d raw, once per late join" % [world.snapshot_bytes, world.snapshot_raw])
	_expect(not syncs.player.is_empty(), "The local player's synchronizer is found in the company world")
	_expect(int(events.busy_bytes) > 0,
		"A drop and a take publish real units_moved events (got %d B)" % events.busy_bytes)

	var crews: Array[int] = [MEASURED_CREW]
	if full_crew > MEASURED_CREW:
		crews.append(full_crew)
	var shed: Dictionary = {}
	for crew: int in crews:
		shed[crew] = _shed_case(crew, syncs, int(events.busy_bytes))
		_report(crew, shed[crew])
	var gated: Dictionary = shed[MEASURED_CREW]
	_expect(float(gated.total) <= SHED_BUDGET,
		"With %d players in the shed the host sends each client at most %.0f KB/s (model %.1f KB/s)" % [
			MEASURED_CREW, SHED_BUDGET / KB, float(gated.total) / KB])
	_line("budget_trip_kbps", "%.0f pending D-2002.2 (no vehicle in the company world yet)" % (TRIP_BUDGET / KB))
	_line("budget_far_kbps", "%.0f pending D-2002.2 (no vehicle in the company world yet)" % (FAR_BUDGET / KB))

	var measured: Dictionary = {}
	for index: int in range(crews.size()):
		var crew: int = crews[index]
		measured[crew] = await _measure_enet(crew, PORT + index, crew == MEASURED_CREW)
		if not (measured[crew] as Dictionary).is_empty():
			_report_measured(crew, measured[crew])
	var player_interval: float = 1.0
	for entry: Array in syncs.player:
		player_interval = minf(player_interval, float(entry[0]))
	_check_measured(measured.get(MEASURED_CREW, {}), gated, 2.0 / player_interval)
	_clean()
	if _failures == 0:
		print("PASS: the company's shed fits %.0f KB/s a client with %d players (model %.1f, ENet %.1f)" % [
			SHED_BUDGET / KB, MEASURED_CREW, float(gated.total) / KB,
			float((measured.get(MEASURED_CREW, {}) as Dictionary).get("per_client", 0.0)) / KB])
	quit(_failures)


## The company world as --mode=company opens it, solo (the host): its synchronizers
## (_synchronizers()), its events' sizes (_event_sizes()) and its late-join snapshot, then closed
## again with CompanyState reset. {syncs, events, snapshot_bytes, snapshot_raw}.
func _open_world() -> Dictionary:
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = SAVE_DIR
	var opened: Array = []
	root.add_child(level)
	# The day opens deferred (CompanyRoot._open_company_day()): its events are caught here.
	level.net.event_applied.connect(func(seq: int, kind: StringName, data: Dictionary) -> void:
		opened.append([seq, kind, data]))
	current_scene = level
	await process_frame
	for _tick: int in range(30):
		await physics_frame
	var found: Dictionary = {
		"syncs": _synchronizers(level),
		"events": _event_sizes(level.net, level.player.global_position, opened),
	}
	var snapshot: Dictionary = CompanyNet.pack_snapshot(level.net.snapshot())
	var compressed: int = 0
	for chunk: PackedByteArray in snapshot.get("chunks", []):
		compressed += chunk.size()
	found.snapshot_bytes = compressed
	found.snapshot_raw = int(snapshot.get("size", 0))
	level.queue_free()
	current_scene = null
	await process_frame
	state.call(&"reset")
	return found


# --- The model ----------------------------------------------------------------


## Every MultiplayerSynchronizer in the company world: the local player's (one per crew member) and
## the rest (the shed's, the host's). {player, shed: [[interval, entry bytes, name]], player_names,
## shed_names}. A synchronizer with nothing sent every tick only sends ON_CHANGE deltas: listed, not
## counted. Every always-sent property is checked against MAX_ALWAYS_PROPERTY_BYTES.
func _synchronizers(level: CompanyRoot) -> Dictionary:
	var found: Dictionary = {"player": [], "shed": [], "player_names": [], "shed_names": []}
	for node: Node in level.find_children("*", "MultiplayerSynchronizer", true, false):
		var sync := node as MultiplayerSynchronizer
		var on_player: bool = level.player != null and level.player.is_ancestor_of(sync)
		var sync_name: String = (
			"Player/%s" % level.player.get_path_to(sync) if on_player else str(level.get_path_to(sync)))
		var sizes: Dictionary = MODEL.always_properties(sync, true)
		var bytes: int = 0
		for path: NodePath in sizes:
			_expect(int(sizes[path]) <= MAX_ALWAYS_PROPERTY_BYTES,
				"%s %s is sent every tick at %d bytes: make it ON_CHANGE" % [sync_name, path, sizes[path]])
			bytes += int(sizes[path])
		var entry: int = MODEL.SYNC_ENTRY_HEADER + bytes
		var label: String = "%s %s" % [sync_name, (
			"%d B every %.3f s" % [entry, MODEL.interval(sync)] if bytes > 0 else "ON_CHANGE only")]
		found["player_names" if on_player else "shed_names"].append(label)
		if bytes > 0:
			found["player" if on_player else "shed"].append([MODEL.interval(sync), entry, sync_name])
	return found


## The events of a busy shed, from what the root really publishes: the day's opening (`opened`, its
## day_phase and clock_anchor) and a drop and a take of UNITS through CompanyNet (_drop_and_take()).
## Each sized as _apply_event carries it. {busy_bytes, busy_kind: the largest units_moved,
## largest_bytes, largest_kind: of any kind (the day's phases are rare)}.
func _event_sizes(net: CompanyNet, feet: Vector3, opened: Array) -> Dictionary:
	var seen: Array = opened.duplicate()
	seen.append_array(_drop_and_take(net, feet))
	var sizes: Dictionary = {"busy_bytes": 0, "busy_kind": "", "largest_bytes": 0, "largest_kind": ""}
	for event: Array in seen:
		var bytes: int = MODEL.rpc_size(event, true)
		if bytes > int(sizes.largest_bytes):
			sizes.largest_bytes = bytes
			sizes.largest_kind = String(event[1])
		if event[1] == &"units_moved" and bytes > int(sizes.busy_bytes):
			sizes.busy_bytes = bytes
			sizes.busy_kind = "units_moved%s" % (" with pos" if (event[2] as Dictionary).has("pos") else "")
	return sizes


## The host -> one client case for `crew` players in the shed: the model's sync numbers plus the
## events (events_data without their datagrams, events with them) and the culprits ([what, bytes/s
## with its framing, of it datagrams], largest first).
func _shed_case(crew: int, syncs: Dictionary, event_bytes: int) -> Dictionary:
	var groups: Array = []
	var relayed: Array = []
	var owners: Array[String] = []
	for entry: Array in syncs.shed:
		groups.append([entry[0], entry[1], 1])
		owners.append("shed %s" % entry[2])
	for entry: Array in syncs.player:
		groups.append([entry[0], entry[1], 1])
		owners.append("the host's player (%s)" % entry[2])
		relayed.append([entry[0], entry[1], maxi(crew - 2, 0)])
	var case: Dictionary = MODEL.host_to_client(groups, relayed, _sync_mtu)
	var event_rate: float = crew * ACTIONS_PER_PLAYER_PER_SECOND + HOST_EVENTS_PER_SECOND
	case.events_data = event_rate * event_bytes
	case.events = event_rate * (event_bytes + MODEL.PACKET_OVERHEAD_BYTES)
	case.framing = float(case.framing) + event_rate * MODEL.PACKET_OVERHEAD_BYTES
	case.datagrams = float(case.datagrams) + event_rate
	case.total = float(case.total) + float(case.events)
	case.upload = float(case.total) * (crew - 1)
	var culprits: Array = []
	var shares: Array = _host_shares(groups)
	for index: int in range(groups.size()):
		culprits.append([owners[index], shares[index][0], shares[index][1]])
	for entry: Array in syncs.player:
		var count: int = maxi(crew - 2, 0)
		var packets: float = count / float(entry[0])
		var data: float = packets * (MODEL.RELAY_HEADER + MODEL.SYNC_PACKET_HEADER + int(entry[1]))
		var framing: float = packets * MODEL.PACKET_OVERHEAD_BYTES
		culprits.append(["%d other players relayed (%s)" % [count, entry[2]], data + framing, framing])
	culprits.append(["business events (%.0f/s)" % event_rate, float(case.events),
		event_rate * MODEL.PACKET_OVERHEAD_BYTES])
	culprits.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	case.culprits = culprits
	return case


## What each host-owned group costs a client, [bytes/s, of it datagrams]: the packets of its
## interval, headers and datagrams included, shared among the groups in them by bytes.
func _host_shares(groups: Array) -> Array:
	var shares: Array = []
	for group: Array in groups:
		var together: Array = []
		var all: float = 0.0
		for other: Array in groups:
			if is_equal_approx(float(other[0]), float(group[0])):
				for index: int in range(int(other[2])):
					together.append(int(other[1]))
				all += int(other[1]) * int(other[2])
		var packed: Vector2i = MODEL.pack(together, _sync_mtu)
		var share: float = int(group[1]) * int(group[2]) / maxf(all, 1.0) / float(group[0])
		var framing: float = packed.x * MODEL.PACKET_OVERHEAD_BYTES * share
		shares.append([(packed.y + packed.x * MODEL.PACKET_OVERHEAD_BYTES) * share, framing])
	return shares


func _report(crew: int, case: Dictionary) -> void:
	var parts: PackedStringArray = []
	for culprit: Array in case.culprits:
		parts.append("%s %.1f (datagrams %.1f)" % [culprit[0], float(culprit[1]) / KB, float(culprit[2]) / KB])
	var over: bool = float(case.total) > SHED_BUDGET
	_line("crew%d" % crew, "per_client_kbps=%.1f host_upload_kbps=%.1f framing_kbps=%.1f datagrams_s=%.0f%s" % [
		float(case.total) / KB, float(case.upload) / KB, float(case.framing) / KB, float(case.datagrams),
		" over_budget" if over else ""])
	_line("crew%d_culprits" % crew, "; ".join(parts))
	if over:
		_line("over_budget", "%d players: %.1f KB/s of %.0f; first culprit %s" % [
			crew, float(case.total) / KB, SHED_BUDGET / KB, case.culprits[0][0]])


# --- Real events ----------------------------------------------------------------


## The host drops UNITS of _product at `feet` and takes them back, through CompanyNet's own checks
## and _publish (the hands are filled first, as a take from a shelf would). [seq, kind, data] of each
## event, as event_applied gave it.
func _drop_and_take(net: CompanyNet, feet: Vector3) -> Array:
	var seen: Array = []
	var listen: Callable = func(seq: int, kind: StringName, data: Dictionary) -> void:
		seen.append([seq, kind, data])
	net.event_applied.connect(listen)
	var hands: StringName = CompanyNet.hands_location(net.multiplayer.get_unique_id())
	_busy_step(net, hands, feet, true)
	_busy_step(net, hands, feet, false)
	net.event_applied.disconnect(listen)
	_expect(seen.size() == 2, "A drop and a take each publish one units_moved (got %d)" % seen.size())
	return seen


## One busy event on the host: UNITS from its hands onto the floor at `feet` (`drop`), or back from
## that bundle (CompanyNet takes a floor bundle as its own station).
func _busy_step(net: CompanyNet, hands: StringName, feet: Vector3, drop: bool) -> void:
	if drop:
		var held: int = net.inventory.count(_product, hands)
		if held < UNITS:
			net.inventory.receive(_product, UNITS - held, hands)
		net.drop(_product, UNITS, feet)
		return
	for bundle: Variant in net.floor_bundles.to_dict():
		net.request(&"units_take", {"station": StringName(bundle), "product": _product, "qty": UNITS})
		return


# --- Measured on ENet ------------------------------------------------------------


## `crew` ENet peers on localhost, one SceneMultiplayer each under its own side node, the host on
## `port`: a real player per peer on every side (its owner's authority, standing on one floor:
## players don't collide with each other) and a CompanyNet. Once every path is confirmed the host
## drops and takes units at the busy rate while ENet counts what each client receives
## (_count_traffic()). {} when the session didn't come up: a failure when `gated` (the crew the
## budget is checked for), else only a `skipped` line (the full crew is printed, never checked).
func _measure_enet(crew: int, port: int, gated: bool) -> Dictionary:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	var sides: Array[Node] = []
	var peers: Array[ENetMultiplayerPeer] = []
	var problem: String = ""
	for index: int in range(crew):
		var side := Node.new()
		side.name = "Peer%d" % index
		root.add_child(side)
		set_multiplayer(SceneMultiplayer.new(), side.get_path())
		sides.append(side)
		var peer := ENetMultiplayerPeer.new()
		peers.append(peer)
		var made: Error = peer.create_server(port, crew) if index == 0 else peer.create_client("127.0.0.1", port)
		if made != OK:
			problem = "ENet peer %d doesn't start on localhost:%d (error %d)" % [index, port, made]
			break
		side.multiplayer.multiplayer_peer = peer
		var net := CompanyNet.new()
		net.name = "CompanyNet"
		side.add_child(net)
	var up: bool = false
	if problem.is_empty():
		up = await _wait_for(func() -> bool:
			if sides[0].multiplayer.get_peers().size() != crew - 1:
				return false
			for index: int in range(1, crew):
				if peers[index].get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
					return false
			return true, CONNECT_SECONDS)
	if problem.is_empty() and not up:
		problem = "%d ENet peers don't connect on localhost in %.0f s" % [crew, CONNECT_SECONDS]
	if not problem.is_empty():
		if gated:
			_expect(false, problem)
		else:
			_line("enet_crew%d" % crew, "skipped (%s)" % problem)
	var result: Dictionary = {}
	if up:
		result = await _count_traffic(sides, peers)
	# The players go while their sessions are still up (they ask for their peer's id every frame),
	# once nothing is sent any more and what was on its way has landed.
	for side: Node in sides:
		for node: Node in side.find_children("*", "MultiplayerSynchronizer", true, false):
			(node as MultiplayerSynchronizer).public_visibility = false
	await _wait_seconds(0.3)
	for side: Node in sides:
		var world: Node = side.get_node_or_null(^"World")
		if world != null:
			world.free()
	await process_frame
	for index: int in range(peers.size() - 1, -1, -1):
		if peers[index].get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
			peers[index].close()
	await process_frame
	for side: Node in sides:
		set_multiplayer(null, side.get_path())
		side.free()
	floor_body.free()
	return result


## Players on every side, a warm-up, then MEASURE_SECONDS of the busy rate of events. {per_client
## (B/s, IP and UDP included), per_client_enet (what the overlay shows a client: ENet's count),
## datagrams (a client's, a second), host_sent (B/s, the overlay's out on the host), events (sent),
## events_seen (applied, all clients), seconds, fps}.
func _count_traffic(sides: Array[Node], peers: Array[ENetMultiplayerPeer]) -> Dictionary:
	var crew: int = sides.size()
	var ids: Array[int] = []
	for side: Node in sides:
		ids.append(side.multiplayer.get_unique_id())
	var player_scene := load(CompanyRoot.PLAYER_SCENE) as PackedScene
	for side: Node in sides:
		var world := Node3D.new()
		world.name = "World"
		side.add_child(world)
		for index: int in range(crew):
			var player := player_scene.instantiate() as Node3D
			player.name = "Player_%d" % ids[index]
			player.position = Vector3(2.0 * index - crew, 0.1, 0.0)
			player.rotation.y = 0.37 + index
			player.set_multiplayer_authority(ids[index])
			world.add_child(player)
	var host_net := sides[0].get_node(^"CompanyNet") as CompanyNet
	var hands: StringName = CompanyNet.hands_location(CompanyNet.HOST_ID)
	var applied: Array[int] = [0]
	for index: int in range(1, crew):
		var net := sides[index].get_node(^"CompanyNet") as CompanyNet
		# Every client holds what the host's hands will hold, as a snapshot would have said.
		net.inventory.receive(_product, UNITS, hands)
		net.event_applied.connect(func(_seq: int, _kind: StringName, _data: Dictionary) -> void:
			applied[0] += 1)
	await _wait_seconds(WARMUP_SECONDS)
	# The players stand still from here on: what they send doesn't depend on their processing (the
	# same bytes with 4 players either way), and crew * crew full players in one process would hold
	# the frame rate under their sync rate (8: 61 fps, a send every other frame at best).
	for side: Node in sides:
		for player: Node in side.get_node(^"World").get_children():
			player.process_mode = Node.PROCESS_MODE_DISABLED
	var feet: Vector3 = (sides[0].get_node(NodePath("World/Player_%d" % ids[0])) as Node3D).global_position
	var rate: float = crew * ACTIONS_PER_PLAYER_PER_SECOND + HOST_EVENTS_PER_SECOND
	# KB/s as the network overlay reads them on LAN (N-216: NetStats, ENet's host counters), a
	# NetStats per peer; the datagrams from the same counters, for IP and UDP.
	var stats: Array[NetStats] = []
	for peer: ENetMultiplayerPeer in peers:
		stats.append(NetStats.new())
		stats.back().sample(peer, ids, Time.get_ticks_usec())
		peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
	var start: int = Time.get_ticks_usec()
	var sent: int = 0
	var frames: int = 0
	while Time.get_ticks_usec() - start < int(MEASURE_SECONDS * 1e6):
		frames += 1
		var due: int = floori((Time.get_ticks_usec() - start) / 1e6 * rate)
		while sent < due:
			# A drop, then the take back: both units_moved, as _event_sizes() sized them.
			_busy_step(host_net, hands, feet, sent % 2 == 0)
			sent += 1
		await process_frame
	var now: int = Time.get_ticks_usec()
	var seconds: float = (now - start) / 1e6
	var host_sent: float = float(stats[0].sample(peers[0], ids, now).out_kbps) * KB
	var received: float = 0.0
	var datagrams: float = 0.0
	for index: int in range(1, crew):
		received += float(stats[index].sample(peers[index], ids, now).in_kbps) * KB
		datagrams += peers[index].host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS) / seconds
	await _wait_for(func() -> bool: return applied[0] >= sent * (crew - 1), CONNECT_SECONDS)
	var clients: float = crew - 1.0
	return {
		"per_client": (received + datagrams * MODEL.IP_UDP_HEADER) / clients, "per_client_enet": received / clients,
		"datagrams": datagrams / clients, "host_sent": host_sent, "events": sent,
		"events_seen": applied[0], "seconds": seconds, "fps": frames / seconds,
	}


func _report_measured(crew: int, measured: Dictionary) -> void:
	var over: bool = float(measured.per_client) > SHED_BUDGET
	_line("enet_crew%d" % crew, ("per_client_kbps=%.1f (ENet %.1f + IP/UDP %.1f) datagrams_s=%.0f"
		+ " host_upload_kbps=%.1f events=%d seconds=%.2f fps=%.0f%s") % [
			float(measured.per_client) / KB, float(measured.per_client_enet) / KB,
			(float(measured.per_client) - float(measured.per_client_enet)) / KB, float(measured.datagrams),
			float(measured.host_sent) / KB, measured.events, measured.seconds, float(measured.fps),
			" over_budget" if over else ""])


## MEASURED_CREW's measurement (`measured`) against the budget and the model's `case`. The check that
## the streams flowed needs `min_fps` (two frames a player's send): slower, the frame rate holds the
## sync rate down and it is only printed as skipped.
func _check_measured(measured: Dictionary, case: Dictionary, min_fps: float) -> void:
	_expect(not measured.is_empty(), "%d players are measured on ENet" % MEASURED_CREW)
	if measured.is_empty():
		return
	var per_client: float = measured.per_client
	var model_data: float = float(case.host) + float(case.relayed) + float(case.events_data)
	_expect(per_client <= SHED_BUDGET, "Measured on ENet, %d players: each client gets at most %.0f KB/s (got %.1f)"
		% [MEASURED_CREW, SHED_BUDGET / KB, per_client / KB])
	_expect(per_client <= float(case.total), "The measurement stays under the model's ceiling (%.1f <= %.1f KB/s)"
		% [per_client / KB, float(case.total) / KB])
	if float(measured.fps) < min_fps:
		_line("enet_crew%d_flow_check" % MEASURED_CREW, "skipped (%.0f fps, under %.0f: fewer sends than the game's)"
			% [float(measured.fps), min_fps])
	else:
		_expect(float(measured.per_client_enet) >= 0.5 * model_data,
			"The streams flowed: ENet counted over half the model's data (%.1f of %.1f KB/s)"
			% [float(measured.per_client_enet) / KB, model_data / KB])
	var events: int = measured.events
	_expect(events > 0 and int(measured.events_seen) == events * (MEASURED_CREW - 1),
		"Every client applied the host's %d events (applied %d of %d)"
		% [events, measured.events_seen, events * (MEASURED_CREW - 1)])


# --- Helpers --------------------------------------------------------------------


func _first_product() -> StringName:
	var files: PackedStringArray = DirAccess.get_files_at(CompanyAsk.PRODUCTS_DIR)
	files.sort()
	for file: String in files:
		if file.ends_with(".tres"):
			return StringName(file.get_basename())
	return &""


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _wait_seconds(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _line(key: String, value: String) -> void:
	print("%s %s=%s" % [PREFIX, key, value])


func _clean() -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_DIR))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

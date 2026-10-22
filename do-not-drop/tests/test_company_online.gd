extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_online.gd
##
## The company world as a session (the D-0214 follow-up; company_root.gd, network_manager.gd): two
## ENet peers in one process, the host on the NetworkManager autoload and the client on a second
## copy of network_manager.gd under its own SceneMultiplayer, each in the real company_root.tscn
## (the client's handed its session and a CompanyState of its own: CompanyRoot.session and
## company_state, set before it enters the tree; a stand-in takes the host's CrewProgression RPC).
## - Alone, the host's world is a crew of one: its player at SPAWN, nothing else spawned.
## - The handshake sends the joiner to company_root.tscn (it is in LEVEL_SCENES), and the host has
##   no player for it while its world isn't up.
## - The client's world says it is up by itself (CompanyRoot -> level_ready()); with nothing called
##   by hand (no peer_level_ready emitted, no send_snapshot or wait_for_snapshot) the host admits
##   it, spawns its player through World/PlayerSpawner and CompanyNet sends the snapshot. Both
##   peers end with the same two players in company_crew (join_crew() on both copies), each driven
##   by its own peer, CREW_SPACING apart around SPAWN (crew_spawn()); the client's own one is its
##   `player`, and its CompanyNet stops waiting with the host's seq, stock and company.
## - Trips out (D-0302.2.a): only the host's world has a CompanyTrips, both have a TripsView on their
##   CompanyNet, and each DayCycle reads its own (CompanyTrips on the host, the view on the client);
##   a van the host's gate sees leave with a packed order shows in the client's view with that
##   order, and is gone from it once the van is back.
## - The client takes 2 units into its hands (a stand-in station where its player stands) and
##   leaves the session: on the host what it held lies in one new floor:<n> bundle where its player
##   stood, in one units_moved (CompanyNet, D-2006: peer_removed comes before its player goes), the
##   total unchanged; then its player is gone from the host, which keeps its own; the client's
##   CompanyState is put back as it was, and with its session gone its world and build mode let go of
##   its freed player (CompanyRoot.player, ShedBuilder.player).
## - free_spawn(): a newcomer takes the first spawn spot nobody stands on (host, A and B in spots
##   0-2, A leaves, C comes: C on A's spot, never on B; someone standing near a spot keeps it taken).
## - No engine error on the way (warnings aside).

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
## The autoload's script: the client's session is a second copy of it.
const NETWORK_MANAGER := preload("res://scripts/core/network_manager.gd")
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const CREW_PROGRESSION: String = "res://scripts/core/crew_progression.gd"
## The host's world saves here (it saves on leaving), never in the game's slot.
const DIR: String = "user://test_company_online"
const PORT: int = 24662
const WAIT_SECONDS: float = 20.0

var _failures: int = 0
var _catcher := ErrorCatcher.new()
var _host_session: NetSession
var _host_root: CompanyRoot
var _client_side: Node
var _client_session: NetSession
var _client_state: Node
var _client_root: CompanyRoot
var _client_id: int = 0
## Players in the host's world when the handshake sent the client to its level (-1: never sent).
var _host_crew_at_handshake: int = -1


## Errors (not warnings) logged while the peers come and go.
class ErrorCatcher extends Logger:
	var _mutex := Mutex.new()
	var _messages: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		_messages.append("%s (%s:%d in %s)"
			% [rationale if not rationale.is_empty() else code, file, line, function])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var out: Array[String] = _messages.duplicate()
		_messages.clear()
		_mutex.unlock()
		return out


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clean()
	RpcGuard.reset()
	_host_session = root.get_node(^"/root/NetworkManager") as NetSession
	var host_state: Node = root.get_node(^"/root/CompanyState")
	host_state.call(&"reset")
	OS.add_logger(_catcher)
	_catcher.take()
	_host_session.transport = NetSession.Transport.ENET
	# As the menu's _host_session() does: the room's level first, then the room.
	_host_session.session_scene = SCENE
	var hosted: bool = _host_session.host_session(PORT) == OK
	_expect(hosted, "The host opens an ENet room on localhost:%d" % PORT)
	_check_free_spawn()
	if hosted:
		await _check_host_alone()
		if await _check_join():
			await _check_trips()
			await _check_leave()
	var errors: Array[String] = _catcher.take()
	OS.remove_logger(_catcher)
	_expect(errors.is_empty(), "No engine error while a client joins the company world and leaves (got %s)"
		% [errors])
	await _tear_down()
	host_state.call(&"reset")
	_clean()
	if _failures == 0:
		print("PASS: the company world online: the joiner is sent to it, its world reports itself up,"
			+ " the host spawns its player and sends the snapshot, 2 crew on both peers, gone when it leaves")
	quit(_failures)


## The host's world alone: a crew of one, its own player at SPAWN.
func _check_host_alone() -> void:
	_host_root = _instantiate()
	root.add_child(_host_root)
	# As the loading screen leaves it: the session hands joiners the current scene.
	current_scene = _host_root
	await process_frame
	await process_frame
	var crew: Array[Player] = _crew_of(_host_root)
	_expect(crew.size() == 1 and crew[0] == _host_root.player and crew[0].name == &"Player_1"
		and _flat(crew[0].global_position).distance_to(_flat(CompanyRoot.SPAWN)) < 0.05,
		"Alone, the host's world is a crew of one: Player_1 at SPAWN (got %s)" % [_describe(crew)])
	_expect(_host_root.get_node_or_null(^"World/PlayerSpawner") is MultiplayerSpawner,
		"The host's world spawns its crew through World/PlayerSpawner")


## The client joins: sent to the company world, its world reports itself up, the host spawns its
## player and sends the snapshot. False when it never got that far.
func _check_join() -> bool:
	_client_side = Node.new()
	_client_side.name = "ClientSide"
	root.add_child(_client_side)
	set_multiplayer(SceneMultiplayer.new(), _client_side.get_path())
	_client_session = NETWORK_MANAGER.new() as NetSession
	_client_session.name = "NetworkManager"
	_client_side.add_child(_client_session)
	_client_side.add_child(_client_crew_progression())
	_client_state = (load(STATE_SCRIPT) as GDScript).new()
	_client_state.name = "CompanyState"
	_client_side.add_child(_client_state)
	_client_state.call(&"reset")
	_client_session.transport = NetSession.Transport.ENET
	_client_session.session_ready.connect(_on_client_session_ready)
	_expect(_client_session.join_session("127.0.0.1", PORT) == OK, "The client starts joining")
	var sent: bool = await _wait_for(func() -> bool: return _client_root != null)
	_expect(sent and _client_session.session_scene == SCENE,
		"The handshake sends the joiner to the company world (got '%s')" % _client_session.session_scene)
	_expect(_host_crew_at_handshake == 1,
		"...and the host spawns nothing for it while its world isn't up (host crew %d)"
		% _host_crew_at_handshake)
	if not sent:
		return false
	var joined: bool = await _wait_for(func() -> bool:
		return (_crew_of(_host_root).size() == 2 and _crew_of(_client_root).size() == 2
			and _client_root.player != null and not _client_root.net.awaiting_snapshot()))
	_client_id = _client_side.multiplayer.get_unique_id()
	_expect(joined, "Once its world is up the host spawns the client's player and sends the snapshot"
		+ " (host crew %s, client crew %s, waiting for a snapshot %s)"
		% [_describe(_crew_of(_host_root)), _describe(_crew_of(_client_root)),
			_client_root.net.awaiting_snapshot()])
	if not joined:
		return false
	_check_crew(_host_root, "host")
	_check_crew(_client_root, "client")
	var own: Player = _client_root.player as Player
	_expect(own != null and own.name == StringName("Player_%d" % _client_id) and own.is_local(),
		"The client's `player` is its own, driven by it (got %s)" % [own.name if own != null else &"none"])
	var host_net: CompanyNet = _host_root.net
	var client_net: CompanyNet = _client_root.net
	_expect(client_net.seq == host_net.seq and client_net.inventory.to_dict() == host_net.inventory.to_dict(),
		"The client's CompanyNet holds the host's seq and stock (seq %d, host %d)" % [client_net.seq, host_net.seq])
	_expect(_client_state.call(&"is_active") and _company(_client_state) == _company(host_net.company),
		"...and the host's company in the client's own CompanyState")
	return true


## The trips out reach the client's world (D-0302.2.a): the host's gate decides, its TripsView
## publishes, the client's view follows and its DayCycle reads it.
func _check_trips() -> void:
	var trips: CompanyTrips = _host_root.trips
	var view: CompanyTripsView = _client_root.trips_view
	_expect(trips != null and _client_root.trips == null and view != null
		and view.net == _client_root.net and _host_root.trips_view.net == _host_root.net,
		"Only the host's world has CompanyTrips; both have a TripsView on their CompanyNet")
	if trips == null or view == null:
		return
	_expect(_host_root.day_cycle.trips_out == trips.trips_out
		and _client_root.day_cycle.trips_out == view.trips_out,
		"Each DayCycle reads its own trips out: CompanyTrips on the host, the view on the client")
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	trips.book.add(Order.make(&"o_online", "Ana", &"centro", &"house_1",
		[{"product": &"hen", "qty": 1}], 0, products))
	trips.book.mark_packed(&"o_online", &"box_online")
	trips.stage_cargo(&"van_online", [&"o_online"], [&"box_online"])
	var stage: int = int(_host_root.net.company.get(&"warehouse_stage"))
	var exit: Vector3 = _host_root.shed.to_global(
		Vector3(0.0, 0.0, -WarehouseStages.floor_size_m(stage).y * 0.5))
	trips.track(&"van_online", exit + Vector3(0.0, 0.0, 1.0))
	trips.track(&"van_online", exit + Vector3(0.0, 0.0, -2.0))
	var seen: bool = await _wait_for(func() -> bool: return view.is_out(&"van_online"))
	_expect(seen and view.trip_of(&"van_online").get("orders") == [&"o_online"]
		and int(_client_root.day_cycle.trips_out.call()) == 1,
		"The van the host's gate saw leave is out in the client's view, with its order (got %s)"
		% [view.trip_of(&"van_online")])
	trips.track(&"van_online", exit + Vector3(0.0, 0.0, 1.0))
	var back: bool = await _wait_for(func() -> bool: return view.trips_out() == 0)
	_expect(back and trips.trips_out() == 0, "...and gone from it once the van is back")


## Both copies of the crew on one peer: Player_1 (the host's) at SPAWN and the client's
## CREW_SPACING beside it, each driven by its peer, both in company_crew.
func _check_crew(world: CompanyRoot, label: String) -> void:
	var host_player: Player = world.get_node_or_null(^"World/Player_1") as Player
	var client_player: Player = world.get_node_or_null(NodePath("World/Player_%d" % _client_id)) as Player
	_expect(host_player != null and client_player != null,
		"On the %s, both players are under World (got %s)" % [label, _describe(_crew_of(world))])
	if host_player == null or client_player == null:
		return
	_expect(host_player.get_multiplayer_authority() == 1
		and client_player.get_multiplayer_authority() == _client_id,
		"On the %s, each player is driven by its own peer (authorities %d, %d)"
		% [label, host_player.get_multiplayer_authority(), client_player.get_multiplayer_authority()])
	var apart: float = _flat(host_player.global_position).distance_to(_flat(client_player.global_position))
	_expect(apart > CompanyRoot.CREW_SPACING * 0.75,
		"On the %s, the two players don't land on each other (%.2f m apart)" % [label, apart])
	var beside: Vector3 = CompanyRoot.crew_spawn(1)
	_expect(_flat(client_player.global_position).distance_to(_flat(beside)) < 0.2,
		"On the %s, the client's player starts at crew_spawn(1) %s (got %s)"
		% [label, beside, client_player.global_position])


## The client takes units into its hands and leaves: what it held lies on the host's floor in one
## new bundle where its player stood (CompanyNet, D-2006: the session's peer_removed comes while its
## player is still there), the total unchanged; then its player goes from the host's world.
func _check_leave() -> void:
	var host_net: CompanyNet = _host_root.net
	var hands: StringName = CompanyNet.hands_location(_client_id)
	var host_copy: Player = _host_root.get_node_or_null(NodePath("World/Player_%d" % _client_id)) as Player
	var source: Array = _stocked(host_net.inventory)
	var taken: int = await _take_into_hands(source, host_copy)
	var total: int = host_net.inventory.total_units()
	var feet: Vector3 = host_copy.global_position if host_copy != null else Vector3.INF
	var moved: Array[Dictionary] = []
	host_net.event_applied.connect(func(_seq: int, kind: StringName, data: Dictionary) -> void:
		if kind == &"units_moved":
			moved.append(data))
	_client_session.leave_session()
	var gone: bool = await _wait_for(func() -> bool:
		return _crew_of(_host_root).size() == 1 and _host_session.peer_ids == [1])
	_expect(gone and _crew_of(_host_root)[0] == _host_root.player,
		"The client leaves: its player is gone from the host's world, the host's stays (got %s)"
		% [_describe(_crew_of(_host_root))])
	if taken > 0:
		var bundle: StringName = StringName(moved[0].get("to", &"")) if moved.size() == 1 else &""
		_expect(moved.size() == 1 and moved[0].get("from") == hands and int(moved[0].get("qty", 0)) == taken
			and FloorBundles.is_floor(bundle),
			"What it held goes to one floor bundle in one units_moved, not twice (got %s)" % [moved])
		var at: Variant = host_net.floor_bundles.position_of(bundle)
		_expect(at is Vector3 and (at as Vector3).distance_to(feet) < 0.3,
			"...lying where its player stood, %s (got %s)" % [feet, at])
		_expect(host_net.inventory.contents_at(hands).is_empty() and host_net.inventory.total_units() == total
			and host_net.inventory.count(StringName(source[0]), bundle) == taken,
			"...its hands empty and the stock's total unchanged (%d, got %d)"
			% [total, host_net.inventory.total_units()])
	# The host's spawns go with the client's session: nothing here keeps pointing at its player. A
	# freed object compares equal to null, so typeof() tells "let go" from "holds a freed one".
	var let_go: bool = await _wait_for(func() -> bool:
		return typeof(_client_root.player) == TYPE_NIL and typeof(_client_root.builder.player) == TYPE_NIL)
	_expect(let_go, "With its session gone the client's world and build mode let go of its freed player"
		+ " (player %s, build mode's %s)" % [_client_root.player, _client_root.builder.player])
	_client_root.queue_free()
	await process_frame
	_expect(not bool(_client_state.call(&"is_active")),
		"Leaving the world puts the client's CompanyState back as it was (off)")


## free_spawn() alone: a newcomer takes the first spawn spot nobody stands on. With a crew of the
## host, A and B (spots 0, 1, 2), A leaving and C coming puts C on A's spot, not on B.
func _check_free_spawn() -> void:
	var none: Array[Vector3] = []
	_expect(CompanyRoot.free_spawn(none) == CompanyRoot.SPAWN, "An empty world spawns at SPAWN")
	var three: Array[Vector3] = [CompanyRoot.crew_spawn(0), CompanyRoot.crew_spawn(1), CompanyRoot.crew_spawn(2)]
	_expect(CompanyRoot.free_spawn(three) == CompanyRoot.crew_spawn(3),
		"With spots 0 to 2 taken the next is spot 3 (got %s)" % CompanyRoot.free_spawn(three))
	var a_left: Array[Vector3] = [CompanyRoot.crew_spawn(0), CompanyRoot.crew_spawn(2)]
	var for_c: Vector3 = CompanyRoot.free_spawn(a_left)
	_expect(for_c == CompanyRoot.crew_spawn(1),
		"A leaves, C comes: C takes A's spot %s, not B's (got %s)" % [CompanyRoot.crew_spawn(1), for_c])
	var near: float = CompanyRoot.CREW_SPACING * CompanyRoot.SPAWN_CLEARANCE * 0.8
	var crowded: Array[Vector3] = [CompanyRoot.crew_spawn(0), CompanyRoot.crew_spawn(1) + Vector3(0.0, 0.0, near)]
	var past: Vector3 = CompanyRoot.free_spawn(crowded)
	_expect(past == CompanyRoot.crew_spawn(2),
		"Someone standing %.2f m off spot 1 keeps it taken (got %s)" % [near, past])
	var clearance: float = CompanyRoot.CREW_SPACING * CompanyRoot.SPAWN_CLEARANCE
	for taken: Array[Vector3] in [three, a_left, crowded]:
		var spot: Vector3 = CompanyRoot.free_spawn(taken)
		for at: Vector3 in taken:
			_expect(Vector2(at.x - spot.x, at.z - spot.z).length() >= clearance,
				"A free spot %s is at least %.2f m from %s" % [spot, clearance, at])


## The client asks for up to 2 units of `source` [product, location, qty] at a stand-in station
## where its player stands (CompanyRoot gives CompanyNet no stations yet, D-0611): how many it took.
func _take_into_hands(source: Array, host_copy: Player) -> int:
	_expect(not source.is_empty() and host_copy != null,
		"The host's shed has stock to take and the client's player (stock %s)" % [source])
	if source.is_empty() or host_copy == null:
		return 0
	var host_net: CompanyNet = _host_root.net
	var client_net: CompanyNet = _client_root.net
	var product: StringName = source[0]
	var location: StringName = source[1]
	var qty: int = mini(2, int(source[2]))
	var spot: Vector3 = host_copy.global_position
	host_net.stations = func(id: StringName) -> Dictionary:
		return {"location": location, "spot": spot} if id == &"test_bin" else {}
	client_net.request(&"units_take", {"station": &"test_bin", "product": product, "qty": qty})
	var hands: StringName = CompanyNet.hands_location(_client_id)
	var held: bool = await _wait_for(func() -> bool:
		return host_net.inventory.count(product, hands) == qty and client_net.seq == host_net.seq)
	_expect(held, "The client takes %d %s into its hands, on both peers (host sees %d)"
		% [qty, product, host_net.inventory.count(product, hands)])
	return qty if held else 0


## The first stock of `stock` on a shelf or pallet, [product, location, qty]; [] when there is none.
static func _stocked(stock: Inventory) -> Array:
	var by_product: Dictionary = stock.to_dict().get("stock", {})
	for product: Variant in by_product:
		var locations: Dictionary = by_product[product]
		for location: Variant in locations:
			var where: String = String(location)
			if not where.begins_with(CompanyNet.HANDS_PREFIX) and not FloorBundles.is_floor(StringName(where)):
				return [StringName(product), StringName(where), int(locations[location])]
	return []


func _tear_down() -> void:
	if _client_root != null and is_instance_valid(_client_root):
		_client_root.queue_free()
	if _client_session != null and is_instance_valid(_client_session):
		_client_session.leave_session()
	if _host_root != null and is_instance_valid(_host_root):
		_host_root.queue_free()
	current_scene = null
	_host_session.leave_session()
	_host_session.transport = NetSession.Transport.AUTO
	await process_frame
	await process_frame
	if _client_side != null and is_instance_valid(_client_side):
		set_multiplayer(null, _client_side.get_path())
		_client_side.free()
	RpcGuard.reset()


## Client: the handshake picked its level; it is built next frame, as the menu's loader would.
func _on_client_session_ready(is_host: bool) -> void:
	if is_host:
		return
	_host_crew_at_handshake = _crew_of(_host_root).size()
	_enter_client_world.call_deferred()


func _enter_client_world() -> void:
	var level: CompanyRoot = _instantiate()
	level.session = _client_session
	level.company_state = _client_state
	_client_side.add_child(level)
	_client_root = level


## The client's own CrewProgression autoload (each process has its own; the client's tree here has
## none): the host's sends the crew's campaign to whoever joins (_receive_campaign). The real
## script's RPCs and nothing else (its _ready() loads and listens to nothing), compiled at run time:
## a class here extending it would compile it, and RunManager with it, before the autoloads exist.
func _client_crew_progression() -> Node:
	var script := GDScript.new()
	script.source_code = "extends \"%s\"\n\n\nfunc _ready() -> void:\n\tpass\n" % CREW_PROGRESSION
	var stand_in: Node = script.new() if script.reload() == OK else Node.new()
	stand_in.name = "CrewProgression"
	return stand_in


func _instantiate() -> CompanyRoot:
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	return level


## The players of `world` (one peer's copy of the crew), in tree order.
func _crew_of(world: CompanyRoot) -> Array[Player]:
	var crew: Array[Player] = []
	if world == null or not is_instance_valid(world):
		return crew
	for node: Node in get_nodes_in_group(CompanyRoot.CREW_GROUP):
		if world.is_ancestor_of(node) and not node.is_queued_for_deletion() and node is Player:
			crew.append(node as Player)
	return crew


static func _describe(crew: Array[Player]) -> String:
	var names: PackedStringArray = []
	for member: Player in crew:
		names.append("%s@%s" % [member.name, member.global_position])
	return "[%s]" % ", ".join(names)


static func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)


## CompanyState.to_dict() without its stored stock: what must match across peers.
static func _company(state: Object) -> Dictionary:
	var data: Dictionary = state.call(&"to_dict")
	data.erase("inventory")
	return data


func _wait_for(done: Callable, seconds: float = WAIT_SECONDS) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return bool(done.call())


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

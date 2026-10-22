extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_sealed_package.gd
##
## The package a taped box becomes, on every peer (D-0715.b: CompanyPackages, as CompanyTableNet's
## `packages`, from box_sealed; contract docs/expansion-distritos/diseno/red-autoridad.md section 2
## row 15 and rule 10):
## - solo, with a parent for the packages: taping box_1 puts Package_box_1 there, once, at the
##   table's spot with the event's basis, package id box_1, the event's trap, absorption, and quality
##   and trap intensity in BoxToPackage.META_TRAP_PLAN; without a parent box_sealed applies the same
##   and builds nothing;
## - a box_sealed whose package fields don't fit is not applied and changes nothing (tables, stock,
##   wallet, no drift, no node): pos NaN, infinite, out of the world or not a Vector3; basis NaN,
##   flattened or not a Basis; quality 101, -1, NaN or text; an unknown trap, a path, another case,
##   none; trap_intensity 1.5; absorption -0.1 or NaN; node_name of another box, without its
##   prefix, missing; a name already taken under the parent. The same event with good fields
##   applies, and the event's trap (fragile) wins over the box's own (the hen's noisy);
## - host and an ENet client in one process, each with its Packages node at the same path: the
##   client opens a box and puts a hen in, the host labels and tapes it; both get Package_box_1 with
##   the same transform, trap, absorption, quality and intensity. On the host its synchronizer
##   reaches nobody while the event is being sent (rule 10) and the client once it went out; the
##   client's copy then gets the host's updates (its synchronizer resolved);
## - a third peer joining late gets no Package_box_1 and the host's synchronizer never reaches it
##   (its world coming up doesn't open it); a box it seals itself afterwards (Package_box_2) is on
##   the three peers, equal, and reaches the client and it; once the client leaves neither package
##   reaches it any more.
## D-0318.1 (the host's package frozen in a cell that isn't loaded) is test_company_root's.

const PORT: int = 24675
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const T := preload("res://scripts/core/company/company_table_net.gd")
const TAKE: StringName = &"units_take"
const HEN: String = "res://data/products/hen.tres"
const SPOT := Vector3(0.0, 0.0, 1.0)

var _failures: int = 0
var _host: Peer
var _client: Peer
var _late: Peer


## One peer: its side of the session, its company, its CompanyNet, its packages' node and what it saw.
class Peer:
	extends RefCounted
	var side: Node
	var state: Node
	var net: CompanyNet
	var packages: Node3D
	var refusals: Array = []
	var restored: Array[int] = []
	## {node name: facts of the package when it went in} (_facts()).
	var made: Dictionary = {}
	## {node name: synchronized signals its synchronizer fired here}.
	var synced: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_check_solo()
	_check_bad_fields()
	await _check_network()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: a sealed box becomes the same package on every peer, checked first, its"
			+ " synchronizer held back until the event went out and only to the peers it went to")
	quit(_failures)


# --- Solo ---


func _check_solo() -> void:
	var state: Node = _new_state("SoloState")
	state.call(&"new_company", "Solo SRL")
	var net := CompanyNet.new()
	net.name = "SoloNet"
	net.company = state
	root.add_child(net)
	net.inventory = Inventory.new()
	net.stations = func(id: StringName) -> Dictionary: return _stations().get(id, {})
	net.player_origin = func(_peer: int) -> Variant: return Vector3.ZERO
	var heard: Array = []
	net.request_rejected.connect(func(rid: int, reason: StringName) -> void: heard.append([rid, reason]))
	var sealed: Array[Dictionary] = []
	net.event_applied.connect(func(_seq: int, kind: StringName, data: Dictionary) -> void:
		if kind == T.SEALED:
			sealed.append(data))
	var holder := Node3D.new()
	holder.name = "Packages"
	root.add_child(holder)
	net.table.packages.parent = holder
	var added: Array = []
	net.table.packages.added.connect(func(package: DeliveryPackage) -> void: added.append(package))
	net.inventory.receive(&"hen", 2, CompanyNet.hands_location(1))
	var order: Dictionary = Order.make(&"o1", "Ana", &"centro", &"centro_house_12",
		[{"product": &"hen", "qty": 1}], 0, {})
	net.table.order_of = func(_table: StringName) -> Dictionary: return order
	var steps: Array = [
		[T.START, {"station": &"table_1", "size": &"S"}],
		[T.PLACE, _cell(0, 0, 0, &"hen")],
		[T.LABEL, {"station": &"table_1"}],
		[T.TAPE, {"station": &"table_1"}],
	]
	for step: Array in steps:
		_expect(_ask(net, heard, step[0], step[1]) == &"", "Solo, %s goes through" % step[0])
	var package := holder.get_node_or_null(^"Package_box_1") as DeliveryPackage
	_expect(package != null and added == [package] and holder.get_child_count() == 1,
		"Taping box_1 puts one Package_box_1 under the packages' parent (children %d)"
		% holder.get_child_count())
	if package != null and not sealed.is_empty():
		var data: Dictionary = sealed[0]
		var plan: Dictionary = package.get_meta(BoxToPackage.META_TRAP_PLAN, {})
		_expect(package.package_id == &"box_1" and package.global_position.is_equal_approx(SPOT)
			and package.global_basis.is_equal_approx(Basis.IDENTITY),
			"...package box_1 at the table's spot, upright (%s at %s)"
			% [package.package_id, package.global_position])
		_expect(package.trap_definition.id == data["trap"]
			and is_equal_approx(package.impact_absorption, data["absorption"])
			and is_equal_approx(plan.get("quality", -1.0), data["quality"])
			and is_equal_approx(plan.get("intensity", -1.0), data["trap_intensity"])
			and package.get_meta(BoxToPackage.META_ORDER_ID, &"") == &"o1",
			"...with the event's trap %s, absorption %.2f, quality %.1f and intensity %.2f (plan %s)"
			% [data["trap"], data["absorption"], data["quality"], data["trap_intensity"], plan])
	var plain := CompanyTableNet.new()
	_expect(not plain.packages.active() and plain.packages.make(PackedBox.new(&"S"), {}) == null,
		"Without a parent nothing is built (the tables alone, as test_company_shared_table)")
	net.free()
	holder.free()
	state.free()


## A table with box_4 (one hen) loaded from a snapshot part; every bad box_sealed changes nothing.
func _check_bad_fields() -> void:
	var box := PackedBox.new(&"M")
	box.place(load(HEN), Vector3i.ZERO)
	var part: Dictionary = {"serial": 4, "tables": {"table_1": {
		"box_id": "box_4", "box": box.to_dict(), "supplies": StationSupplies.full().to_dict(),
	}}}
	var mirror := CompanyTableNet.new()
	var holder := Node3D.new()
	holder.name = "MirrorPackages"
	root.add_child(holder)
	mirror.packages.parent = holder
	var state: Node = _new_state("FieldsState")
	state.call(&"new_company", "Fields SRL")
	var stock := Inventory.new()
	stock.receive(&"hen", 1, T.box_location(&"box_4"))
	_expect(mirror.put_snapshot(part), "The mirror takes a table holding box_4")
	var money: int = int(state.get(&"money"))
	var good: Dictionary = {
		"table": &"table_1", "order": &"", "package_id": &"box_4", "node_name": &"Package_box_4",
		"trap": &"fragile", "trap_intensity": 0.25, "contents": {&"hen": 1}, "absorption": 0.8,
		"quality": 75.0, "pos": Vector3(1.0, 0.5, 2.0), "basis": Basis(Vector3.UP, 0.5),
		"money": money - CompanyTuning.TAPE_COST, "minute": 600,
	}
	var bad: Array = [
		["pos", Vector3(NAN, 0.0, 0.0), "a NaN pos"],
		["pos", Vector3(INF, 0.0, 0.0), "an infinite pos"],
		["pos", Vector3(2.0e6, 0.0, 0.0), "a pos out of the world"],
		["pos", Vector2(1.0, 2.0), "a pos that isn't a Vector3"],
		["basis", Basis(Vector3(NAN, 0.0, 0.0), Vector3.UP, Vector3.BACK), "a NaN basis"],
		["basis", Basis(Vector3.ZERO, Vector3.UP, Vector3.BACK), "a flattened basis"],
		["basis", Quaternion.IDENTITY, "a basis that isn't a Basis"],
		["quality", 101.0, "quality 101"],
		["quality", -1.0, "quality -1"],
		["quality", NAN, "a NaN quality"],
		["quality", "90", "quality as text"],
		["trap", &"unicorn", "an unknown trap"],
		["trap", &"../traps/fragile", "a trap path"],
		["trap", &"Fragile", "a trap in another case"],
		["trap", null, "no trap"],
		["trap_intensity", 1.5, "trap_intensity 1.5"],
		["absorption", -0.1, "absorption -0.1"],
		["absorption", NAN, "a NaN absorption"],
		["node_name", &"Package_box_5", "another box's node name"],
		["node_name", &"box_4", "a node name without its prefix"],
		["node_name", null, "no node name"],
	]
	var before: Array = [mirror.to_dict(), stock.to_dict(), int(state.get(&"money"))]
	for case: Array in bad:
		var data: Dictionary = _with(good, case[0], case[1])
		if case[1] == null:
			data.erase(case[0])
		_expect(not mirror.apply(state, stock, T.SEALED, data)
			and [mirror.to_dict(), stock.to_dict(), int(state.get(&"money"))] == before
			and not mirror.take_drift() and holder.get_child_count() == 0,
			"A box_sealed with %s is not applied and changes nothing" % case[2])
	var squatter := Node3D.new()
	squatter.name = "Package_box_4"
	holder.add_child(squatter)
	_expect(not mirror.apply(state, stock, T.SEALED, good) and mirror.to_dict() == before[0],
		"...nor one whose node name is already taken under the parent")
	squatter.free()
	_expect(mirror.apply(state, stock, T.SEALED, good) and not mirror.has_box(&"table_1")
		and stock.count(&"hen", T.package_location(&"box_4")) == 1,
		"The same event with good fields applies: box_4 leaves the table, its hen is in package:box_4")
	var package := holder.get_node_or_null(^"Package_box_4") as DeliveryPackage
	_expect(package != null and package.trap_definition.id == &"fragile"
		and package.global_transform.is_equal_approx(Transform3D(good["basis"], good["pos"]))
		and is_equal_approx(package.impact_absorption, 0.8)
		and is_equal_approx(package.get_meta(BoxToPackage.META_TRAP_PLAN, {}).get("quality", -1.0), 75.0),
		"...and Package_box_4 stands at the event's pose with its trap (fragile, not the hen's noisy),"
		+ " absorption and quality")
	holder.free()
	state.free()


# --- Network ---


func _check_network() -> void:
	_host = _make_peer("HostSide")
	_client = _make_peer("ClientSide")
	_late = _make_peer("LateSide")
	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	var late := ENetMultiplayerPeer.new()
	var up: bool = server.create_server(PORT, 3) == OK
	_host.side.multiplayer.multiplayer_peer = server
	_host.state.call(&"new_company", "Package SRL")
	var stock := Inventory.new()
	stock.receive(&"hen", 8, &"shelf:s_0")
	stock.reserve(&"hen", 1, &"o1")
	_host.state.call(&"store_stock", stock)
	_add_net(_host)
	_host.net.inventory = _host.state.call(&"stock")
	_host.net.stations = func(id: StringName) -> Dictionary: return _stations().get(id, {})
	_host.net.player_origin = func(_peer: int) -> Variant: return Vector3.ZERO
	var order: Dictionary = Order.make(&"o1", "Bea", &"campo", &"campo_house_3",
		[{"product": &"hen", "qty": 1}], 0, {})
	_host.net.table.order_of = func(table: StringName) -> Dictionary:
		return order if table == &"table_1" else {}
	up = up and client.create_client("127.0.0.1", PORT) == OK
	_client.side.multiplayer.multiplayer_peer = client
	_add_net(_client)
	_client.net.wait_for_snapshot()
	var connected: bool = await _wait_for(_connected.bind(_client, 1))
	_expect(up and connected, "The client connects to the host on localhost:%d" % PORT)
	if connected:
		await _play(client, late)
	# Each world goes before its connection, as when a session ends: a package left behind would
	# ask a closed peer who it is every frame.
	_drop_world(_client)
	client.close()
	_drop_world(_late)
	late.close()
	_drop_world(_host)
	server.close()
	await process_frame
	for peer: Peer in [_host, _client, _late]:
		set_multiplayer(null, peer.side.get_path())
		peer.side.free()
		peer.state.free()


func _play(client: ENetMultiplayerPeer, late: ENetMultiplayerPeer) -> void:
	_expect(await _join(_client), "The client gets the host's snapshot")
	var steps: Array = [
		[_client, T.START, {"station": &"table_1", "size": &"S"}, "the client opens a box"],
		[_client, TAKE, _take(), "takes a hen"],
		[_client, T.PLACE, _cell(0, 0, 0, &"hen"), "puts it in"],
		[_host, T.LABEL, {"station": &"table_1"}, "the host labels it for o1"],
	]
	for step: Array in steps:
		_expect(await _do(step[0], step[1], step[2], [_client]) == &"",
			"On the shared table %s" % step[3])
	var client_id: int = _client.side.multiplayer.get_unique_id()
	_expect(_ask(_host.net, _host.refusals, T.TAPE, {"station": &"table_1"}) == &"",
		"The host tapes it")
	var mine := _host.packages.get_node_or_null(^"Package_box_1") as DeliveryPackage
	var gates: CompanyPackages = _host.net.table.packages
	_expect(mine != null and not gates.sends_to(mine, client_id),
		"The host's Package_box_1 is there and its synchronizer reaches nobody yet (rule 10)")
	var arrived: bool = await _wait_for(func() -> bool:
		return _client.packages.has_node(^"Package_box_1") and gates.sends_to(mine, client_id))
	_expect(arrived, "The client builds Package_box_1 from the event and the host's synchronizer"
		+ " reaches it once the event went out")
	_expect_same(&"Package_box_1", [_host, _client])
	_expect(await _wait_for(func() -> bool: return int(_client.synced.get(&"Package_box_1", 0)) > 0),
		"The client's copy gets the host's updates (its synchronizer resolved: %d)"
		% int(_client.synced.get(&"Package_box_1", 0)))
	await _check_late_join(late, mine, client_id)
	_drop_world(_client)
	client.close()
	_expect(await _wait_for(func() -> bool:
		return not _host.side.multiplayer.get_peers().has(client_id)), "The client leaves")
	var second := _host.packages.get_node_or_null(^"Package_box_2") as DeliveryPackage
	_expect(not gates.sends_to(mine, client_id)
		and (second == null or not gates.sends_to(second, client_id)),
		"Once the client left neither package reaches it")


## A third peer comes up after Package_box_1 was made: it never gets that one; one it seals itself
## afterwards is on every peer.
func _check_late_join(late: ENetMultiplayerPeer, first: DeliveryPackage, client_id: int) -> void:
	var up: bool = late.create_client("127.0.0.1", PORT) == OK
	_late.side.multiplayer.multiplayer_peer = late
	_add_net(_late)
	_late.net.wait_for_snapshot()
	var connected: bool = await _wait_for(_connected.bind(_late, 2))
	_expect(up and connected, "A third peer connects late")
	if not connected:
		return
	_expect(await _join(_late), "...and gets the snapshot")
	var late_id: int = _late.side.multiplayer.get_unique_id()
	var gates: CompanyPackages = _host.net.table.packages
	_expect(not _late.packages.has_node(^"Package_box_1") and not gates.sends_to(first, late_id)
		and gates.sends_to(first, client_id),
		"The late peer has no Package_box_1 and the host's synchronizer doesn't reach it (its world"
		+ " coming up doesn't open it); it still reaches the client")
	var everyone: Array = [_client, _late]
	var steps: Array = [
		[_late, T.START, {"station": &"table_2", "size": &"S"}, "the late peer opens a box"],
		[_late, TAKE, _take(), "takes a hen"],
		[_late, T.PLACE, _cell(0, 0, 0, &"hen", &"table_2"), "puts it in"],
		[_late, T.TAPE, {"station": &"table_2"}, "and tapes it"],
	]
	for step: Array in steps:
		_expect(await _do(step[0], step[1], step[2], everyone) == &"", "With three peers, %s" % step[3])
	var second := _host.packages.get_node_or_null(^"Package_box_2") as DeliveryPackage
	_expect(second != null and await _wait_for(func() -> bool:
		return gates.sends_to(second, late_id) and gates.sends_to(second, client_id)),
		"Package_box_2 reaches the client and the late peer")
	_expect_same(&"Package_box_2", [_host, _client, _late])


# --- Helpers ---


## `peer`'s packages go, while its connection is still up.
static func _drop_world(peer: Peer) -> void:
	for package: Node in peer.packages.get_children():
		peer.packages.remove_child(package)
		package.free()


## What every peer must agree on about a package, read as it went in.
static func _facts(package: DeliveryPackage) -> Array:
	var plan: Dictionary = package.get_meta(BoxToPackage.META_TRAP_PLAN, {})
	return [package.global_transform, package.package_id, package.trap_definition.id,
		package.impact_absorption, plan.get("quality"), plan.get("intensity"),
		package.get_meta(BoxToPackage.META_ORDER_ID, &"")]


func _expect_same(node_name: StringName, peers: Array) -> void:
	var first: Peer = peers[0]
	for peer: Peer in peers:
		_expect(peer.made.has(node_name), "%s built %s" % [peer.side.name, node_name])
	for peer: Peer in peers.slice(1):
		_expect(peer.made.get(node_name) == first.made.get(node_name),
			"%s's %s is the host's: same pose, id, trap, absorption, quality and intensity (%s / %s)"
			% [peer.side.name, node_name, peer.made.get(node_name), first.made.get(node_name)])


static func _stations() -> Dictionary:
	return {
		&"table_1": {"location": &"table:table_1", "spot": SPOT},
		&"table_2": {"location": &"table:table_2", "spot": Vector3(1.0, 0.0, 1.0)},
		&"shelf_hen": {"location": &"shelf:s_0", "spot": Vector3(0.0, 0.0, -1.0)},
	}


static func _cell(cx: int, cy: int, cz: int, product: StringName,
		station: StringName = &"table_1") -> Dictionary:
	return {"station": station, "cx": cx, "cy": cy, "cz": cz, "product": product, "rot": 0}


static func _take() -> Dictionary:
	return {"station": &"shelf_hen", "product": &"hen", "qty": 1}


func _connected(peer: Peer, peers: int) -> bool:
	return peer.side.multiplayer.get_peers().has(1) \
		and _host.side.multiplayer.get_peers().size() == peers


func _make_peer(side_name: String) -> Peer:
	var peer := Peer.new()
	peer.side = Node.new()
	peer.side.name = side_name
	root.add_child(peer.side)
	set_multiplayer(SceneMultiplayer.new(), peer.side.get_path())
	peer.state = _new_state(side_name + "State")
	peer.packages = Node3D.new()
	peer.packages.name = "Packages"
	peer.side.add_child(peer.packages)
	return peer


func _add_net(peer: Peer) -> void:
	peer.net = CompanyNet.new()
	peer.net.name = "CompanyNet"
	peer.net.company = peer.state
	peer.side.add_child(peer.net)
	peer.net.table.packages.parent = peer.packages
	peer.net.table.packages.added.connect(func(package: DeliveryPackage) -> void:
		peer.made[StringName(package.name)] = _facts(package)
		var sync := package.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
		sync.synchronized.connect(func() -> void:
			peer.synced[StringName(package.name)] = int(peer.synced.get(StringName(package.name), 0)) + 1))
	peer.net.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		peer.refusals.append([rid, reason]))
	peer.net.company_state_restored.connect(func(seq: int) -> void: peer.restored.append(seq))


## The host sends `peer` its snapshot as when that peer's world comes up; true once it is in.
func _join(peer: Peer) -> bool:
	var id: int = peer.side.multiplayer.get_unique_id()
	var network: Node = root.get_node_or_null(^"/root/NetworkManager")
	if network != null and network.has_signal(&"peer_level_ready"):
		network.emit_signal(&"peer_level_ready", id)
	else:
		_host.net.send_snapshot(id)
	return await _wait_for(func() -> bool:
		return not peer.restored.is_empty() and peer.net.seq == _host.net.seq)


func _do(peer: Peer, kind: StringName, data: Dictionary, followers: Array) -> StringName:
	var seq: int = _host.net.seq
	var rid: int = peer.net.request(kind, data)
	await _wait_for(func() -> bool:
		return (_reason_heard(peer.refusals, rid) != &""
			or (_host.net.seq > seq and _at_host_seq(followers))))
	return _reason_heard(peer.refusals, rid)


func _at_host_seq(followers: Array) -> bool:
	for peer: Peer in followers:
		if peer.net.seq != _host.net.seq:
			return false
	return true


func _ask(net: CompanyNet, heard: Array, kind: StringName, data: Dictionary) -> StringName:
	return _reason_heard(heard, net.request(kind, data))


static func _reason_heard(heard: Array, rid: int) -> StringName:
	for entry: Array in heard:
		if entry[0] == rid:
			return entry[1]
	return &""


func _new_state(state_name: String) -> Node:
	var state: Node = (load(STATE_SCRIPT) as GDScript).new()
	state.name = state_name
	root.add_child(state)
	state.call(&"reset")
	return state


static func _with(data: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy[key] = value
	return copy


func _wait_for(done: Callable, seconds: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return bool(done.call())


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

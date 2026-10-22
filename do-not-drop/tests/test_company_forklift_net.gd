extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_forklift_net.gd
##
## The shed's forklift over the wire (expansion D-0606.b: CompanyForklift, ForkliftView, CompanyNet fork_act /
## fork_state and _let_go), with a host and a client as ENet peers in one process (each with its CompanyNet and a
## CompanyShed following it, the client starting from the host's snapshot), the client's player driving:
## - the host puts the client on the forklift (PalletJackUse with the client's peer id, as CompanyRoot does when the
##   client uses the seat): the client's view takes the keys (the interact override), the host's does not, and the
##   client's player is marked `driving`;
## - the client's mast key: held, the forks rise on both peers with its requests; let go, the host stops them at the
##   height the client drew (the stop's at_height, within what the forks cover in the client's ENet round trip:
##   CompanyForklift.stop_height()), and both peers agree;
## - the client's interact key (the override) takes the first pallet off the truck's bed: one jack_picked `by` the
##   forklift, on the forks on both peers;
## - the client drops out (its connection closes, its player still there): the host lets the forklift go at once
##   (CompanyNet._let_go on peer_disconnected, well under ForkliftView.GONE_SECONDS) where the client's player stood,
##   the pallet still on the forks;
## - every event reaches the client in order.

const PORT: int = 24685
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const HEN: StringName = &"hen"
const LAMP: StringName = &"antique_lamp"
const DAY: int = 2

var _failures: int = 0
var _host: Peer
var _client: Peer
var _schedule := SupplierSchedule.new()
var _company := FakeCompany.new()
var _driver: FakePlayer
## The host's forklift after every fork_state: [since_msec, height, dir].
var _host_forks: Array = []


## One peer: its side of the session, its CompanyNet and CompanyShed, its company and what it heard.
class Peer:
	extends RefCounted
	var side: Node
	var state: Node
	var net: CompanyNet
	var shed: CompanyShed
	var seqs: Array[int] = []
	var refusals: Array = []
	var restored: Array[int] = []


## The client's player: a body in the group, with its peer, hands and reach.
class FakePlayer extends Node3D:
	var carried_package: Variant = null

	func reach_origin() -> Vector3:
		return global_position + Vector3.UP * 0.6


## What the supplier truck reads of the company (day, stage).
class FakeCompany extends RefCounted:
	var day: int = DAY
	var warehouse_stage: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	await _check_network()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: a client drives the shed's forklift over ENet: gets on, raises the mast, takes a pallet off the"
			+ " truck, and the host lets it go the moment the client drops out")
	quit(_failures)


func _check_network() -> void:
	_host = _make_peer("HostSide")
	_client = _make_peer("ClientSide")
	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	var up: bool = server.create_server(PORT, 2) == OK
	_expect(up, "The test hosts an ENet session on localhost:%d" % PORT)
	_host.side.multiplayer.multiplayer_peer = server
	# What CompanyRoot does on the host: the company with its default shed, then the world and the day's truck.
	_host.state.call(&"new_company", "Fork SRL")
	DefaultShed.load_default().apply_to(_host.state)
	_add_world(_host)
	_host.net.inventory = _host.state.call(&"stock")
	_host.shed.rebuild(_host.state, _host.net.inventory)
	_host.net.stations = _host.shed.station_for
	var truck := _make_truck(_host)
	_schedule.place(DAY - 1, [{"product": HEN, "qty": 30}, {"product": LAMP, "qty": 10}])
	var loaded: Dictionary = _host.net.pallets.loaded_event(DAY, _schedule.pallets_for(DAY), _host.net.inventory)
	_expect(_host.net.publish(CompanyPallets.LOADED, loaded) and truck.bed_open(),
		"The day's truck is parked with its pallets on the bed")
	_host.net.event_applied.connect(func(_seq: int, kind: StringName, _data: Dictionary) -> void:
		if kind == CompanyPallets.FORK:
			var fork: CompanyForklift = _host.net.pallets.forklift
			_host_forks.append([fork.since_msec, fork.mast.fork_height, fork.mast_dir]))
	up = up and client.create_client("127.0.0.1", PORT) == OK
	_client.side.multiplayer.multiplayer_peer = client
	_add_world(_client)
	_client.net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return _client.side.multiplayer.get_peers().has(1) and _host.side.multiplayer.get_peers().size() == 1)
	_expect(up and connected, "The client connects to the host")
	if connected:
		await _play(client)
	Input.action_release(&"forklift_mast_up")
	client.close()
	server.close()
	await process_frame
	if is_instance_valid(_driver):
		_driver.free()
	truck.free()
	for peer: Peer in [_host, _client]:
		set_multiplayer(null, peer.side.get_path())
		peer.side.free()
		peer.state.free()


func _play(client: ENetMultiplayerPeer) -> void:
	var id: int = _client.side.multiplayer.get_unique_id()
	_host.net.send_snapshot(id)
	var joined: bool = await _wait_for(func() -> bool:
		return not _client.restored.is_empty() and _client.net.seq == _host.net.seq)
	_expect(joined, "The client gets the host's snapshot (restored %s)" % [_client.restored])
	await process_frame
	var host_view: ForkliftView = _host.shed.yard.forklift if _host.shed.yard != null else null
	var view: ForkliftView = _client.shed.yard.forklift if _client.shed.yard != null else null
	_expect(view != null and host_view != null and view.net == _client.net,
		"Both peers draw the forklift, the client's wired to its own CompanyNet")
	if view == null or host_view == null:
		return
	var host_fork: CompanyForklift = _host.net.pallets.forklift
	var fork: CompanyForklift = _client.net.pallets.forklift

	# Getting on: the host for the client, as CompanyRoot does when the client uses the seat.
	_driver = FakePlayer.new()
	_driver.name = "ClientPlayer"
	_driver.set_multiplayer_authority(id)
	root.add_child(_driver)
	_driver.add_to_group(&"player")
	_stand(PalletYardView.fork_home(0), PI)
	_expect(PalletJackUse.use(_host.net, _host.shed.yard, PalletJackPoint.ACTION_BOARD, id, _driver.global_position)
		== PalletJackUse.RESULT_BOARDED and await _synced(), "The host puts the client on the forklift")
	await process_frame
	_expect(host_fork.driver == id and fork.driver == id and view.is_local_driving()
		and not host_view.is_local_driving() and _driver.has_meta(&"interact_override")
		and _driver.has_meta(ForkliftView.DRIVING_META),
		"The client drives on both peers: its view has the keys, the host's does not, its player is marked")

	# The mast, by the client's key: up for a while, then let go right after one of its requests came back.
	view.keys_need_capture = false
	Input.action_press(&"forklift_mast_up")
	await create_timer(0.8).timeout
	var seq_held: int = _client.net.seq
	await _wait_for(func() -> bool: return _client.net.seq > seq_held, 1.0)
	await process_frame
	_expect(host_fork.mast_dir == 1 and fork.mast_dir == 1 and fork.height_at(Time.get_ticks_msec()) > 0.2,
		"Held, the forks rise on both peers (%.2f m)" % fork.height_at(Time.get_ticks_msec()))
	var before: Array = _host_forks.back()
	Input.action_release(&"forklift_mast_up")
	var drawn: float = view.fork_height()
	var round_trip: float = NetStats.round_trip_seconds(_host.side.multiplayer.multiplayer_peer, id)
	var stopped: bool = await _wait_for(func() -> bool:
		return host_fork.mast_dir == 0 and _client.net.seq == _host.net.seq and fork.mast_dir == 0)
	var was := CompanyForklift.new()
	was.mast.set_height(before[1])
	was.mast_dir = before[2]
	was.since_msec = before[0]
	var host_had: float = was.height_at(host_fork.since_msec)
	var expected: float = CompanyForklift.stop_height(host_had, drawn, round_trip)
	var now: int = Time.get_ticks_msec()
	_expect(stopped and absf(host_fork.height_at(now) - expected) < 0.005,
		"Let go, the host stops the forks at what the client drew within its round trip (drew %.3f, the host had %.3f,"
		% [drawn, host_had] + " stopped at %.3f, round trip %.3f s)" % [host_fork.height_at(now), round_trip])
	_expect(absf(fork.height_at(now) - host_fork.height_at(now)) < 0.001 and absf(view.fork_height()
		- host_fork.height_at(now)) < 0.02, "... and both peers hold and draw that height")

	# The client's interact key takes the first pallet off the bed (forks down, the bed's rear in front of them).
	_host.net.publish(CompanyPallets.FORK, CompanyForklift.state_event(id, host_view.pose()["body"],
		host_view.pose()["yaw"], 0, 0.0))
	var rear: Vector2 = SupplierTruckView.rear_of(0)
	_stand(rear + Vector2(0.0, -CompanyTuning.FORKLIFT_TIP_M - 0.3), PI)
	await _synced()
	await process_frame
	var seq_work: int = _host.net.seq
	((_driver.get_meta(&"interact_override") as Dictionary)["use"] as Callable).call()
	var took: bool = await _wait_for(func() -> bool:
		return _host.net.seq > seq_work and _client.net.seq == _host.net.seq)
	var lamp: StringName = &"d2_antique_lamp_1"
	_expect(took and _host.net.pallets.book.carrying == lamp and host_fork.holds and _client.net.pallets.book.carrying
		== lamp and fork.holds, "The client's key takes the first pallet of the bed onto the forks, on both peers")
	await process_frame
	_expect(view.carried_id() == lamp and host_view.carried_id() == lamp, "... drawn on the forks by both")

	# The client drops out with its player still there: let go at once, where that player stood.
	_stand(Vector2(-2.0, 2.5), 0.6)
	await process_frame
	var expected_seqs: Array[int] = []
	for number: int in range(_client.seqs.front() if not _client.seqs.is_empty() else 1, _host.net.seq + 1):
		expected_seqs.append(number)
	_expect(_client.seqs == expected_seqs and _client.net.seq == _host.net.seq,
		"The client applied every event after its snapshot in order (%s)" % [_client.seqs])
	var dropped: int = Time.get_ticks_msec()
	client.close()
	var let_go: bool = await _wait_for(func() -> bool: return host_fork.driver == 0, 3.0)
	var after: float = (Time.get_ticks_msec() - dropped) / 1000.0
	var parked: bool = host_fork.at is Vector2 and (host_fork.at as Vector2).is_equal_approx(Vector2(-2.0, 2.5))
	_expect(let_go and after < 1.0 and parked and absf(host_fork.yaw - 0.6) < 0.001,
		"The client drops out: the host lets the forklift go in %.2f s where its player stood (%s, %.2f)"
		% [after, host_fork.at, host_fork.yaw])
	_expect(host_fork.holds and _host.net.pallets.book.carrying == lamp and host_view.carried_id() == lamp
		and not host_view.seat_point.taken, "... the pallet still on its forks, and the seat free again")


# --- Helpers ---


func _make_peer(side_name: String) -> Peer:
	var peer := Peer.new()
	peer.side = Node.new()
	peer.side.name = side_name
	root.add_child(peer.side)
	set_multiplayer(SceneMultiplayer.new(), peer.side.get_path())
	peer.state = (load(STATE_SCRIPT) as GDScript).new()
	peer.state.name = side_name + "State"
	root.add_child(peer.state)
	peer.state.call(&"reset")
	return peer


## The world of one peer, as CompanyRoot builds it: CompanyNet and the shed following it.
func _add_world(peer: Peer) -> void:
	peer.net = CompanyNet.new()
	peer.net.name = "CompanyNet"
	peer.net.company = peer.state
	peer.side.add_child(peer.net)
	peer.shed = CompanyShed.new()
	peer.shed.name = "Shed"
	peer.side.add_child(peer.shed)
	peer.shed.follow(peer.net)
	peer.net.event_applied.connect(func(seq: int, _kind: StringName, _data: Dictionary) -> void:
		peer.seqs.append(seq))
	peer.net.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		peer.refusals.append([rid, reason]))
	peer.net.company_state_restored.connect(func(seq: int) -> void: peer.restored.append(seq))


## The day's supplier truck on `peer`'s shed, parked half an hour after it arrives.
func _make_truck(peer: Peer) -> SupplierTruckView:
	var truck := SupplierTruckView.new()
	truck.schedule = _schedule
	truck.company = _company
	truck.minute_now = func() -> float: return float(SupplierSchedule.arrival_minute()) + 30.0
	truck.pallets = peer.net.pallets.book
	root.add_child(truck)
	peer.shed.truck = truck
	return truck


## Stands the client's player at `body` (shed frame) facing `heading`.
func _stand(body: Vector2, heading: float) -> void:
	_driver.global_position = Vector3(body.x, 0.0, body.y)
	_driver.rotation = Vector3(0.0, heading, 0.0)


func _synced() -> bool:
	return await _wait_for(func() -> bool: return _client.net.seq == _host.net.seq)


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

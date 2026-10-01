extends Node
## Two-process gameplay race check. Run through tools/run-net-pair.sh.
## Also checks that the F3 network overlay (N-216) reads the live ENet link
## on both sides: ping and KB/s in and out (NETSTATS lines).
## N-235: once the client is in, both ends drop a silent peer within the
## session timeout (20 s), not the load budget; a joiner's level load within
## 10 s of that budget prints a NETLOG WARNING line.
## Next to last stage (N-221): the client that left holding a box joins again
## from the same running game and gets its colour slot and merit back under its
## new peer id.
## Last stage (N-221 follow-up): the client vanishes without a word while
## carrying a box in crisis -- its link is left open but nobody polls it, a
## pulled cable -- and joins again before the host noticed. The host drops the
## old connection as a ghost when the new one says who it is; the box's rescue
## window is held right then (NetworkManager.peer_removed), not when the ghost's
## connection closes 0.5-2 s later, once its player let go of the box.

const PORT: int = 17992
const TIMEOUT_SECONDS: float = 40.0
const CLIENT_COSMETIC: StringName = &"mint_uniform"
const CLIENT_NICKNAME: String = "Ana"
const NEWS_DESK: Script = preload("res://scripts/presentation/newspaper/news_desk.gd")
## N-235.2: the joiner loads its level with ENet's polling blocked, and the
## host drops it if that outlasts NetworkManager's load budget (45 s). A load
## within this margin of the budget prints a WARNING (35 s today), a sign the
## pair is about to start failing on a slower runner.
const SLOW_LOAD_MARGIN_SECONDS: float = 10.0

var _network: Node
var _level: Node
var _host: bool = false
var _failed: bool = false
var _finished: bool = false
var _client_peer_id: int = 0
var _pickup_sent: bool = false
var _race_sent: bool = false
var _reports: Dictionary = {}
## Client: how the disconnect stage went, reported with the final result.
var _disconnect_ok: bool = false
## Client: when to give up waiting for the host, pushed back by the rejoin.
var _deadline: int = 0
var _paper: Dictionary = {}
var _order: Array = []
## Client: the link it vanished from, kept so it isn't freed -- freeing it
## closes it, and the host would hear of it.
var _vanished_peer: MultiplayerPeer


func _ready() -> void:
	_network = get_node(^"/root/NetworkManager")
	_network.set(&"transport", 2)  # NetworkManager.Transport.ENET
	_host = "--host" in OS.get_cmdline_user_args()
	# Deliberately different local profiles: order difficulty must come from
	# the host through the handshake, never from the joiner's save.
	get_node(^"/root/UnlockManager").set(&"completed_runs", 6 if _host else 0)
	if not _host:
		# Starter cosmetic, but deliberately not the automatic team colour.
		get_node(^"/root/UnlockManager").set(&"selected_cosmetic", CLIENT_COSMETIC)
		get_node(^"/root/UnlockManager").set(&"nickname", CLIENT_NICKNAME)
		var bus: Node = get_node(^"/root/EventBus")
		bus.connect(&"newspaper_ready", func(paper: Dictionary) -> void:
			_paper = paper
			_order.append("paper"))
		bus.connect(&"run_ended", func(_score: int, _results: Dictionary) -> void: _order.append("ended"))
	_network.connect(&"session_ready", func(_is_host: bool) -> void: _load_level.call_deferred())
	# Without this a dropped join only showed up as a bare timeout 40 s later.
	# NETLOG, not PAIR: run-net-pair.sh takes the first PAIR line as the result.
	_network.connect(&"session_failed", func(reason: String) -> void:
		print("NETLOG role=%s session failed at %.1f s: %s" % [_role(), _seconds(), reason]))
	_network.connect(&"session_ready", func(_is_host: bool) -> void:
		print("NETLOG role=%s session ready at %.1f s" % [_role(), _seconds()]))
	var error: Error = _network.call(&"host_session", PORT) if _host else _network.call(&"join_session", "127.0.0.1", PORT)
	if error != OK:
		print("PAIR role=%s FAIL could not %s (error %d)" % [_role(), "host" if _host else "join", error])
		get_tree().quit(1)
		return
	if _host:
		_run_host.call_deferred()
	else:
		_watch_client.call_deferred()


func _load_level() -> void:
	if _level != null:
		return
	var began: float = _seconds()
	_level = load("res://scenes/gameplay/level_base.tscn").instantiate()
	get_tree().root.add_child(_level)
	var took: float = _seconds() - began
	print("NETLOG role=%s level loaded at %.1f s (took %.1f s)" % [_role(), _seconds(), took])
	if not _host:
		_warn_if_slow_load(took)
	# The F3 overlay (N-216) reads the live ENet link from here on; its last
	# reading is checked before the client leaves (_overlay_reads_link).
	_overlay().call(&"set_shown", true)


func _run_host() -> void:
	if not await _wait_until(func() -> bool:
		return _level != null and get_tree().get_nodes_in_group(&"player").size() >= 2):
		await _finish(false, "timed out waiting for both spawned players")
		return
	_client_peer_id = int(get_tree().root.multiplayer.get_peers()[0])
	var host_player: Player = _player(1)
	var client_player: Player = _player(_client_peer_id)
	if host_player == null or client_player == null:
		await _finish(false, "spawned player paths are missing")
		return
	rpc_id(_client_peer_id, &"_client_check_order", _order_ids(), int(_network.get(&"world_completed_runs")))
	await _wait_for_report(&"order")

	# N-235: admitted and loaded, both ends drop a silent peer within the
	# session timeout, not the 45 s load budget -- once the host's settle
	# margin (settle_delay_seconds) has passed.
	var settled: bool = await _wait_until(func() -> bool:
		return int(_network.call(&"enet_timeout_msec", _client_peer_id)) == _session_timeout_msec())
	_expect(settled, "host drops a silent client within the session timeout once it's in (got %d ms)"
		% int(_network.call(&"enet_timeout_msec", _client_peer_id)))
	rpc_id(_client_peer_id, &"_client_check_timeout")
	await _wait_for_report(&"timeout")

	# The client owns this property. The host must see the selected uniform.
	var cosmetic_arrived: bool = await _wait_until(func() -> bool:
		return client_player.cosmetic_id == CLIENT_COSMETIC)
	_expect(cosmetic_arrived, "host sees the client's selected uniform")
	var nickname_arrived: bool = await _wait_until(func() -> bool:
		return String(client_player.get_node("PlayerNickname").get(&"nickname")) == CLIENT_NICKNAME)
	_expect(nickname_arrived, "host sees the client's nickname, replicated with the appearance")

	# The client sends its pickup request and a sibling notification in one
	# frame. Whichever request the host processes first may win; only one may.
	var package: DeliveryPackage = _level.packages[0]
	var pickup: Node = package.get_node(^"InteractionArea")
	rpc_id(_client_peer_id, &"_client_attempt_pickup", package.get_path(), pickup.get_path())
	if not await _wait_until(func() -> bool: return _pickup_sent):
		await _finish(false, "client never sent the pickup race")
		return
	pickup.call(&"interact", host_player)
	await _pump(1.0)
	var carriers: Array[Player] = _players_holding(package)
	_expect(carriers.size() == 1, "simultaneous pickup leaves exactly one player holding the package")
	_expect(package.carrier == carriers[0] if carriers.size() == 1 else false,
		"host authority agrees with the one visible carrier")
	rpc_id(_client_peer_id, &"_client_check_pickup", package.get_path())
	await _wait_for_report(&"pickup")

	# Reset through the real host-authoritative drop path before the seat race.
	if package.is_held:
		package.call(&"request_drop", Transform3D(Basis.IDENTITY, package.global_position), false)
	await _pump(0.7)

	var seat: Node = _level.get_node(^"World/Vehicle/CargoBay/CenterSeatEyePoint/InteractionArea")
	seat.call(&"interact", host_player)
	await _pump(0.4)
	rpc_id(_client_peer_id, &"_client_attempt_occupied_seat", seat.get_path())
	await _pump(1.0)
	_expect(seat.get(&"occupant") == host_player, "occupied seat keeps its first occupant")
	_expect(client_player.seat_node_path.is_empty(), "client is rejected from the occupied seat")
	rpc_id(_client_peer_id, &"_client_check_seat", host_player.get_path(), client_player.get_path(), seat.get_parent().get_path())
	await _wait_for_report(&"seat")
	host_player.call(&"leave_seat")
	await _pump(0.6)

	# Put the package in the client's hands, then have that client request a
	# handoff and a drop in the same frame. Dropping cancels the in-flight
	# handoff: nobody may retain a second copy in their hands.
	package.call(&"take_by", client_player)
	await _pump(0.8)
	_expect(client_player.carried_package == package, "client holds the package before the transfer/drop race")
	rpc_id(_client_peer_id, &"_client_transfer_then_drop", package.get_path(), host_player.get_path())
	if not await _wait_until(func() -> bool: return _race_sent):
		await _finish(false, "client never sent the transfer/drop race")
		return
	await _pump(1.5)
	_expect(not package.is_held and package.carrier == null, "package ends loose on the floor after transfer/drop")
	_expect(host_player.carried_package == null and client_player.carried_package == null,
		"neither host nor client keeps the dropped package in hand")
	rpc_id(_client_peer_id, &"_client_check_drop", package.get_path())
	await _wait_for_report(&"drop")

	# The host's next-day newspaper (N-606.2) reaches the client as the same ids and
	# slots, before the results, from the run really ending on the host.
	var chronicle: Node = _level.get_node(^"RunChronicle")
	var run: Node = get_node(^"/root/RunManager")
	run.call(&"start_run")
	await _pump(0.6)
	run.call(&"finish_run", true)
	_expect(NEWS_DESK.call(&"is_valid", chronicle.get(&"paper")),
		"host writes a readable paper when the results are decided")
	rpc_id(_client_peer_id, &"_client_check_paper", chronicle.get(&"paper"))
	await _wait_for_report(&"paper")
	await _wait_for_report(&"paper_order")

	# The client leaves on purpose: its carried box must become loose on the
	# host. Before that it earns some merit and its colour slot is noted, for
	# the rejoin (_check_rejoin).
	var old_client: int = _client_peer_id
	var old_slot: int = int(_network.call(&"color_slot", old_client))
	_expect(old_slot != int(_network.call(&"color_slot", 1)), "host and client wear different colour slots")
	var crew: Node = get_node(^"/root/CrewProgression")
	crew.call(&"award_action", old_client, &"net_pair:rejoin", 30)
	var old_merit: int = int((crew.get(&"merit") as Dictionary).get(old_client, 0))
	package.call(&"take_by", client_player)
	await _pump(0.8)
	_expect(client_player.carried_package == package and package.carrier == client_player,
		"client holds the package before disconnecting")
	_print_network_metrics("host")
	_expect(_overlay_reads_link("host"), "host's network overlay reads the client's ENet link")
	rpc_id(_client_peer_id, &"_client_disconnect_while_carrying", package.get_path())
	var disconnected: bool = await _wait_until(func() -> bool:
		return get_tree().root.multiplayer.get_peers().is_empty())
	_expect(disconnected, "host observes the client disconnect")
	await _pump(0.8)
	_expect(is_instance_valid(package) and package.is_inside_tree(), "disconnected client's package remains in the world")
	_expect(not package.is_held and package.carrier == null and package.collision_layer == 4,
		"disconnected client's package is loose on the host")
	await _check_rejoin(old_client, old_slot, old_merit)
	if _client_peer_id > 0:
		await _check_ghost_rejoin(old_slot)
	await _finish(not _failed, "all pair checks passed")


## N-221: the client comes back from the same running game (same identity in
## its ready reply) under a new peer id. The host gives it its slot back, and
## with it the merit CrewProgression keeps under that slot.
func _check_rejoin(old_client: int, old_slot: int, old_merit: int) -> void:
	_client_peer_id = 0
	var rejoins: Array = []
	_network.connect(&"peer_rejoined", func(old_id: int, new_id: int) -> void: rejoins.append([old_id, new_id]))
	var came_back: bool = await _wait_until(func() -> bool:
		var peers: PackedInt32Array = get_tree().root.multiplayer.get_peers()
		return peers.size() == 1 and _player(peers[0]) != null, TIMEOUT_SECONDS * 2.0)
	if not came_back:
		_expect(false, "the client that left joins the session again")
		return
	_client_peer_id = int(get_tree().root.multiplayer.get_peers()[0])
	await _pump(0.4)
	var crew: Node = get_node(^"/root/CrewProgression")
	var slot: int = int(_network.call(&"color_slot", _client_peer_id))
	var merit: int = int((crew.get(&"merit") as Dictionary).get(_client_peer_id, -1))
	_expect(_client_peer_id != old_client, "the rejoined client has a new peer id")
	_expect(rejoins == [[old_client, _client_peer_id]], "the host recognises who came back (got %s)" % [rejoins])
	_expect(slot == old_slot, "the rejoined client gets its colour slot back (slot %d, was %d)" % [slot, old_slot])
	_expect(merit == old_merit, "the rejoined client gets its merit back (%d, was %d)" % [merit, old_merit])
	# Not its suit: this client wears a uniform on purpose (test_network_rejoin covers the suit).
	rpc_id(_client_peer_id, &"_client_check_rejoin", _client_peer_id, old_slot)
	await _wait_for_report(&"rejoin")


## N-221 follow-up: back from a pulled cable before the host noticed. The
## client's link is a ghost the host only drops when the new one says who it
## is; it closes 0.5-2 s later, after the level freed the ghost's player.
func _check_ghost_rejoin(slot: int) -> void:
	var package: DeliveryPackage = _level.packages[0]
	var ghost: int = _client_peer_id
	var client_player: Player = _player(ghost)
	package.call(&"take_by", client_player)
	package.care = DeliveryPackage.CareModel.new()
	package.care.begin_crisis(&"fragile")
	package.care.crisis_left = 5.0
	await _pump(0.8)
	_expect(client_player.carried_package == package and package.carrier == client_player,
		"client holds a box in crisis before vanishing")
	# The host must not notice the silence before the client is back: that
	# takes a level load.
	var enet := get_tree().root.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	enet.get_peer(ghost).set_timeout(32, 120000, 120000)
	var removed: Array = []
	_network.connect(&"peer_removed", func(id: int) -> void: removed.append(id))
	_client_peer_id = 0
	rpc_id(ghost, &"_client_vanish_and_rejoin")
	var came_back: bool = await _wait_until(func() -> bool:
		for peer: int in get_tree().root.multiplayer.get_peers():
			if peer != ghost and _player(peer) != null:
				return true
		return false, TIMEOUT_SECONDS * 2.0)
	if not came_back:
		_expect(false, "the client that vanished joins the session again")
		return
	for peer: int in get_tree().root.multiplayer.get_peers():
		if peer != ghost:
			_client_peer_id = peer
	await _pump(0.3)  # The level frees the ghost's player at the end of the frame it was dropped in.
	_expect(not (_network.get(&"peer_ids") as Array).has(ghost) and removed == [ghost],
		"the host drops the ghost as the client comes back (removed %s)" % [removed])
	_expect(not package.is_held and package.carrier == null, "the ghost's box is loose on the host")
	var window: float = package.care.crisis_left
	_expect(window >= DeliveryPackage.CareModel.CRISIS_SECONDS - 1.0,
		"the box's rescue window was held when the ghost was dropped (%.1f s left)" % window)
	# SceneMultiplayer lets go of it as it is dropped, not when its link closes
	# 0.5-2 s later: nothing more is sent to a closing link ("max channels: 0"),
	# and the other clients hear it left.
	_expect(not get_tree().root.multiplayer.get_peers().has(ghost),
		"the host's multiplayer lets go of the ghost as it is dropped")
	await _pump(2.5)
	_expect(removed == [ghost], "the ghost's link closing removes nothing more (removed %s)" % [removed])
	rpc_id(_client_peer_id, &"_client_check_ghost_rejoin", _client_peer_id, slot)
	await _wait_for_report(&"ghost_rejoin")


func _watch_client() -> void:
	# Joining waits out the host's level load and then this process loads its
	# own: on a slow CI runner that alone took 35 of the 40 s. The budget for
	# the host's commands starts once the level is in.
	var load_deadline: int = Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 2.0 * 1000.0)
	while _level == null and Time.get_ticks_msec() < load_deadline:
		await get_tree().process_frame
	_deadline = Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 1000.0)
	while not _finished and Time.get_ticks_msec() < _deadline:
		await get_tree().process_frame
	if not _finished:
		print("PAIR role=client FAIL timed out waiting for host commands")
		_network.call(&"leave_session")
		get_tree().quit(1)


@rpc("authority", "call_remote", "reliable")
func _client_attempt_pickup(_package_path: NodePath, pickup_path: NodePath) -> void:
	var pickup: Node = get_node_or_null(pickup_path)
	if pickup != null:
		pickup.rpc_id(1, &"request_interact")
	rpc_id(1, &"_client_pickup_sent")


@rpc("any_peer", "call_remote", "reliable")
func _client_pickup_sent() -> void:
	if _host and get_tree().root.multiplayer.get_remote_sender_id() == _client_peer_id:
		_pickup_sent = true


@rpc("authority", "call_remote", "reliable")
func _client_check_pickup(package_path: NodePath) -> void:
	await _pump(0.4)
	var package: DeliveryPackage = get_node_or_null(package_path) as DeliveryPackage
	var ok: bool = package != null and _players_holding(package).size() == 1 and package.is_held
	_report(&"pickup", ok, "client sees exactly one carrier")


@rpc("authority", "call_remote", "reliable")
func _client_attempt_occupied_seat(seat_path: NodePath) -> void:
	var seat: Node = get_node_or_null(seat_path)
	if seat != null:
		seat.rpc_id(1, &"request_interact")


@rpc("authority", "call_remote", "reliable")
func _client_check_seat(host_path: NodePath, client_path: NodePath, seat_path: NodePath) -> void:
	await _pump(0.4)
	var host_player: Player = get_node_or_null(host_path) as Player
	var client_player: Player = get_node_or_null(client_path) as Player
	var ok: bool = host_player != null and client_player != null \
		and host_player.seat_node_path == seat_path and client_player.seat_node_path.is_empty()
	_report(&"seat", ok, "client sees the first occupant and remains standing")


@rpc("authority", "call_remote", "reliable")
func _client_transfer_then_drop(package_path: NodePath, recipient_path: NodePath) -> void:
	var package: DeliveryPackage = get_node_or_null(package_path) as DeliveryPackage
	var player: Player = _player(get_tree().root.multiplayer.get_unique_id())
	if package != null and player != null:
		package.rpc_id(1, &"request_transfer", recipient_path)
		player.call(&"_drop_carried")
	rpc_id(1, &"_client_race_sent")


@rpc("any_peer", "call_remote", "reliable")
func _client_race_sent() -> void:
	if _host and get_tree().root.multiplayer.get_remote_sender_id() == _client_peer_id:
		_race_sent = true


@rpc("authority", "call_remote", "reliable")
func _client_check_drop(package_path: NodePath) -> void:
	await _pump(0.4)
	var package: DeliveryPackage = get_node_or_null(package_path) as DeliveryPackage
	var ok: bool = package != null and not package.is_held and _players_holding(package).is_empty() \
		and package.collision_layer == 4
	_report(&"drop", ok, "client sees the loose package on the floor")


@rpc("authority", "call_remote", "reliable")
func _client_check_paper(host_paper: Dictionary) -> void:
	await _pump(0.4)
	var ok: bool = not _paper.is_empty() and _paper == host_paper and NEWS_DESK.call(&"is_valid", _paper)
	_report(&"paper", ok, "client receives the host's newspaper as it is (got %s)" % str(_paper).left(80))
	var hud: Node = _level.get_node(^"HUD")
	_report(&"paper_order", _order == ["paper", "ended"] and hud.newspaper.is_open(),
		"client gets the paper before run_ended, and its page is up (order %s, page %s)"
		% [str(_order), hud.newspaper.is_open()])


@rpc("authority", "call_remote", "reliable")
func _client_check_order(host_order: Array, host_completed_runs: int) -> void:
	await _pump(0.4)
	var ok: bool = host_completed_runs == 6 \
		and int(_network.get(&"world_completed_runs")) == host_completed_runs \
		and _order_ids() == host_order
	_report(&"order", ok, "client uses the host's progression and posts the same order")


@rpc("authority", "call_remote", "reliable")
func _client_check_timeout() -> void:
	# The host settles its own end first, then tells this one.
	var settled: bool = await _wait_until(func() -> bool:
		return int(_network.call(&"enet_timeout_msec", 1)) == _session_timeout_msec())
	_report(&"timeout", settled, "client drops a silent host within the session timeout once it's in (got %d ms)"
		% int(_network.call(&"enet_timeout_msec", 1)))


@rpc("authority", "call_remote", "reliable")
func _client_disconnect_while_carrying(package_path: NodePath) -> void:
	var package: DeliveryPackage = get_node_or_null(package_path) as DeliveryPackage
	var player: Player = _player(get_tree().root.multiplayer.get_unique_id())
	var ok: bool = package != null and player != null and player.carried_package == package
	_print_network_metrics("client")
	var overlay_ok: bool = _overlay_reads_link("client")
	# NETLOG, not PAIR: run-net-pair.sh takes the first PAIR line as the result.
	print("NETLOG role=client disconnect while carrying: %s%s" % ["ok" if ok and overlay_ok else "FAIL",
		"" if overlay_ok else " (the network overlay did not read the host's link)"])
	_disconnect_ok = ok and overlay_ok
	await _pump(0.2)
	_network.call(&"leave_session")
	_level.queue_free()
	_level = null
	await _pump(1.0)
	# Back into the same session, from the same running game (N-221). A new
	# level load: the wait for the host starts over.
	_deadline = Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 2.0 * 1000.0)
	var error: Error = _network.call(&"join_session", "127.0.0.1", PORT)
	if error != OK:
		print("PAIR role=client FAIL could not rejoin (error %d)" % error)
		get_tree().quit(1)


## A pulled cable: the link stays open, unpolled (_vanished_peer), and the
## session ends on this side only. Then the game joins again.
@rpc("authority", "call_remote", "reliable")
func _client_vanish_and_rejoin() -> void:
	await _pump(0.2)
	var api: MultiplayerAPI = get_tree().root.multiplayer
	_vanished_peer = api.multiplayer_peer
	api.multiplayer_peer = OfflineMultiplayerPeer.new()
	_network.call(&"leave_session")  # Nothing reaches the host: the link isn't closed.
	_level.queue_free()
	_level = null
	await _pump(1.0)
	_deadline = Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 2.0 * 1000.0)
	var error: Error = _network.call(&"join_session", "127.0.0.1", PORT)
	if error != OK:
		print("PAIR role=client FAIL could not rejoin after vanishing (error %d)" % error)
		get_tree().quit(1)


@rpc("authority", "call_remote", "reliable")
func _client_check_ghost_rejoin(my_id: int, slot: int) -> void:
	await _pump(0.4)
	var me: int = get_tree().root.multiplayer.get_unique_id()
	var seen: int = int(_network.call(&"color_slot", me))
	var ok: bool = me == my_id and seen == slot and _player(me) != null
	_report(&"ghost_rejoin", ok,
		"the client back after vanishing wears its slot again (slot %d, sees %d)" % [slot, seen])


@rpc("authority", "call_remote", "reliable")
func _client_check_rejoin(my_id: int, slot: int) -> void:
	await _pump(0.4)
	var me: int = get_tree().root.multiplayer.get_unique_id()
	var seen: int = int(_network.call(&"color_slot", me))
	var ok: bool = me == my_id and seen == slot and _player(me) != null
	_report(&"rejoin", ok, "the rejoined client sees its own colour slot again (slot %d, sees %d)" % [slot, seen])


func _report(stage: StringName, ok: bool, detail: String) -> void:
	rpc_id(1, &"_receive_report", stage, ok, detail)


@rpc("any_peer", "call_remote", "reliable")
func _receive_report(stage: StringName, ok: bool, detail: String) -> void:
	if not _host or get_tree().root.multiplayer.get_remote_sender_id() != _client_peer_id:
		return
	_reports[stage] = ok
	_expect(ok, detail)


@rpc("authority", "call_remote", "reliable")
func _finish_client(ok: bool) -> void:
	_finished = true
	var passed: bool = ok and _disconnect_ok
	print("PAIR role=client %s" % ("PASS" if passed else "FAIL"))
	await _pump(0.3)
	_network.call(&"leave_session")
	get_tree().quit(0 if passed else 1)


func _finish(ok: bool, detail: String) -> void:
	if not ok:
		_failed = true
		push_error(detail)
	var passed: bool = not _failed
	if _client_peer_id > 0:
		rpc_id(_client_peer_id, &"_finish_client", passed)
	print("PAIR role=host %s: %s" % ["PASS" if passed else "FAIL", detail])
	await _pump(0.8)
	_network.call(&"leave_session")
	get_tree().quit(0 if passed else 1)


func _print_network_metrics(role: String) -> void:
	var multiplayer_peer: MultiplayerPeer = get_tree().root.multiplayer.multiplayer_peer
	if not multiplayer_peer is ENetMultiplayerPeer:
		return
	var remote_id: int = 1 if role == "client" else _client_peer_id
	var packet_peer: ENetPacketPeer = (multiplayer_peer as ENetMultiplayerPeer).get_peer(remote_id)
	if packet_peer == null:
		return
	var loss_epoch_ms: int = int(packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS_EPOCH))
	var loss_percent: String = "NA"
	if loss_epoch_ms >= 10000:
		loss_percent = "%.3f" % (packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) * 100.0 / ENetPacketPeer.PACKET_LOSS_SCALE)
	print("NETMETRIC transport=enet topology=localhost role=%s rtt_ms=%.1f rtt_variance_ms=%.1f packet_loss_pct=%s packet_loss_epoch_ms=%d" % [
		role,
		packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
		packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE),
		loss_percent,
		loss_epoch_ms,
	])


func _overlay() -> Node:
	return _network.get_node(^"NetStatsOverlay")


## The overlay's last reading (it refreshes itself twice a second): LAN, one
## row for the other side with a ping, and traffic both ways. Prints NETSTATS.
func _overlay_reads_link(role: String) -> bool:
	var sample: Dictionary = _overlay().get(&"last_sample")
	var rows: Array = sample.get("peers", [])
	var ping: int = int(rows[0].ping_ms) if rows.size() == 1 else -1
	var in_kbps: float = float(sample.get("in_kbps", -1.0))
	var out_kbps: float = float(sample.get("out_kbps", -1.0))
	print("NETSTATS role=%s transport=%s rows=%d ping_ms=%d in_kbps=%.1f out_kbps=%.1f" % [role,
		sample.get("transport", &"?"), rows.size(), ping, in_kbps, out_kbps])
	return sample.get("transport") == &"enet" and rows.size() == 1 and ping >= 0 and in_kbps > 0.0 and out_kbps > 0.0


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failed = true
		push_error(description)


func _order_ids() -> Array:
	var result: Array = []
	if _level == null:
		return result
	var depot: Node = _level.get_node(^"World/Depot")
	for order: Dictionary in depot.get(&"orders"):
		result.append(StringName(order.package_id))
	return result


func _wait_for_report(stage: StringName) -> bool:
	var arrived: bool = await _wait_until(func() -> bool: return _reports.has(stage))
	_expect(arrived, "client did not report stage %s" % stage)
	return arrived and bool(_reports.get(stage, false))


func _wait_until(predicate: Callable, seconds: float = TIMEOUT_SECONDS) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


func _seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func _session_timeout_msec() -> int:
	return int(_network.get(&"ENET_PEER_TIMEOUT_SESSION_MSEC"))


## N-235.2: NETLOG, not PAIR (run-net-pair.sh repeats it as a WARNING line).
func _warn_if_slow_load(took: float) -> void:
	var budget: float = minf(float(_network.get(&"JOIN_HANDSHAKE_TIMEOUT")),
		int(_network.get(&"ENET_PEER_TIMEOUT_MAX_MSEC")) / 1000.0)
	if took > budget - SLOW_LOAD_MARGIN_SECONDS:
		print(("NETLOG role=%s WARNING slow level load: %.1f s, over %.0f s"
			+ " (the network waits %.0f s for a loading peer)")
			% [_role(), took, budget - SLOW_LOAD_MARGIN_SECONDS, budget])


func _pump(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _player(peer_id: int) -> Player:
	if _level == null:
		return null
	return _level.get_node_or_null(NodePath("World/Player_%d" % peer_id)) as Player


func _players_holding(package: DeliveryPackage) -> Array[Player]:
	var holders: Array[Player] = []
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and player.carried_package == package:
			holders.append(player)
	return holders


func _role() -> String:
	return "host" if _host else "client"

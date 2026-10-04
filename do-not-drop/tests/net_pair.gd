extends Node
## Two-process gameplay race check. Run through tools/run-net-pair.sh.
## Also checks that the F3 network overlay (N-216) reads the live ENet link
## on both sides: ping and KB/s in and out (NETSTATS lines).
## N-235: once the client is in, both ends drop a silent peer within the
## session timeout (20 s), not the load budget; a joiner's level load within
## 10 s of that budget prints a NETLOG WARNING line.
## Next to last stage (N-221): the client that left holding a box joins again
## from the same running game and gets its colour slot and merit back under its
## new peer id. N-908: the host picked a box up while it was away, and the
## client back in sees it in the host's hands (the player repeats its pick_up to
## a peer whose level is up: player_net_visibility.gd). N-221 rejoin restore:
## it comes back where it stood, with the box it dropped by leaving back in its
## hands, on the host and in its own view (rejoin_keepsake.gd).
## Last stage (N-221 follow-up): the client vanishes without a word while
## carrying a box in crisis -- its link is left open but nobody polls it, a
## pulled cable -- and joins again before the host noticed. The host drops the
## old connection as a ghost when the new one says who it is; the box's rescue
## window is held right then (NetworkManager.peer_removed), not when the ghost's
## connection closes 0.5-2 s later, once its player let go of the box; the one
## who came back gets that box in its hands again once the ghost's player is
## gone (rejoin_keepsake.gd), its window still held.
## N-228.5: a box left alone sends its pose twice a second (NetRestThrottle);
## moved, it goes out at once and at full rate again, not at the next slow
## send.
## N-218: the client takes the wheel (which starts the run) and drives for two
## seconds: its copy of the truck is predicted (unfrozen, simulated with its own
## input), the host plays its numbered inputs and its truck moves with them, no
## correction moves the client's copy more than 10 cm a tick, and once the
## client gets out its copy is frozen again (DRIVE lines with the numbers).
## N-922.5: then it drives with the standard `--net-sim` profile on its truck
## (Vehicle.configure_net_sim, what `--net-sim` does on a LAN): its inputs and
## the host's states are held back half the lag each (several of each on the
## way at any time, none on the clean link), the host's states come in at
## least 3 ticks later than on the clean link, and still no correction moves
## it more than 10 cm a tick. N-922.9: that drive weaves the wheel all along
## and switches the profile on a second into it: the host's pose is stamped
## ahead of the input it played for well under a second (its input counter
## re-anchors; before, for the rest of the drive), and from a second after
## the switch the client's mean error grows by less than 15 cm over the one
## before it.

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
## N-922.9, the drive into --net-sim: the wheel weaves this far (of full lock) every this many seconds...
const NET_SIM_WEAVE: float = 0.6
const NET_SIM_WEAVE_PERIOD: float = 1.5
## ...and from a second after the switch, the mean error grows by less than this (m) over the one before it: the
## truck is faster by then and 2 % of its inputs are lost (2.4-7 cm measured, against 1.6 cm before). What it guards
## against is a counter that keeps moving, or a correction that doesn't settle; one left ahead for good is caught by
## the host's count of ticks stamped ahead (at these speeds its error is only ~3 cm).
const MAX_NET_SIM_ERROR_GROWTH: float = 0.15
## ...and on the host, the pose is stamped ahead of the input it played this many ticks in a row at most: the gap as
## the profile goes on (half its lag and jitter, 4-6 ticks), NetInputBuffer.REANCHOR_TICKS inputs landing behind the
## counter and the ticks that jitter or a slow frame leave without one meanwhile (20-28 measured). Before N-922.9 the
## counter stayed ahead for the whole drive (~200).
const MAX_STAMP_AHEAD_TICKS: int = 60

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
	# The route builds over several frames, as in the game, even headless (N-408): the host
	# spawns nobody and the client reports no "ready" until its road stands.
	var route_script: GDScript = load("res://scripts/gameplay/route/route.gd") as GDScript
	route_script.set(&"always_slice", true)
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

	# N-228.5: the last box is left alone until its synchronizer rests, then
	# moved (frozen, so it stays where it's put).
	var resting: DeliveryPackage = _level.packages[-1]
	_expect(resting != _level.packages[0], "the rest stage leaves the first box to the pickup race")
	var throttle: Node = resting.get_node(^"NetRestThrottle")
	var was_frozen: bool = resting.freeze
	var was_at: Vector3 = resting.global_position
	resting.freeze = true
	var rested: bool = await _wait_until(func() -> bool: return bool(throttle.call(&"is_resting")))
	_expect(rested, "a box left alone drops to its rest interval on the host")
	resting.global_position = was_at + Vector3(0.6, 0.0, 0.0)
	rpc_id(_client_peer_id, &"_client_check_rest", resting.get_path(), resting.global_position,
		float(throttle.get(&"rest_interval")))
	await _wait_for_report(&"rest")
	resting.global_position = was_at
	resting.freeze = was_frozen

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

	await _check_client_drives(client_player)

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
	var left_at: Vector3 = client_player.global_position
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
	var held: DeliveryPackage = _level.packages[1]
	held.call(&"take_by", host_player)
	await _check_rejoin(old_client, old_slot, old_merit, held, package, left_at)
	if held.is_held:
		held.call(&"request_drop", Transform3D(Basis.IDENTITY, held.global_position), false)
	await _pump(0.7)
	if _client_peer_id > 0:
		await _check_ghost_rejoin(old_slot)
	await _finish(not _failed, "all pair checks passed")


## N-218: the client at the wheel predicts its truck; the host's still moves only with its inputs.
func _check_client_drives(client_player: Player) -> void:
	var vehicle: VehicleBody3D = _level.get(&"vehicle")
	vehicle.call(&"set_door_open", &"cab_left", true)
	_level.get_node(^"World/Vehicle/CabinInterior/DriverEyePoint/InteractionArea").call(&"interact", client_player)
	var seated: bool = await _wait_until(func() -> bool: return int(vehicle.driver_peer_id) == _client_peer_id)
	_expect(seated, "the client takes the wheel")
	var start: Vector3 = vehicle.global_position
	# The client gets out before it reports, and a change of driver puts the
	# host's input number back to 0 (N-922): the highest one it played counts.
	# N-922.9: [highest played, ticks in a row the pose was stamped ahead of the
	# input played, the most of those]. A loss or the gap as --net-sim goes on
	# hold one input a few ticks; a counter that stays ahead is the bug.
	var played: Array[int] = [0, 0, 0]
	var inputs: NetInputBuffer = (vehicle.get(&"_prediction") as VehiclePrediction).inputs
	var track_seq := func() -> void:
		played[0] = maxi(played[0], int(vehicle.get(&"net_input_seq")))
		played[1] = played[1] + 1 if inputs.tick_seq() > inputs.played_seq() else 0
		played[2] = maxi(played[2], played[1])
	get_tree().physics_frame.connect(track_seq)
	rpc_id(_client_peer_id, &"_client_drive", vehicle.get_path())
	await _wait_for_report(&"drive")
	get_tree().physics_frame.disconnect(track_seq)
	var moved: float = vehicle.global_position.distance_to(start)
	print(("DRIVE role=host moved %.1f m, played up to input %d,"
		+ " stamped ahead of the input played %d ticks in a row at most") % [moved, played[0], played[2]])
	_expect(moved > 2.0, "the host's truck drives with the client's inputs (moved %.1f m)" % moved)
	_expect(played[0] > 0, "the host plays the client's numbered inputs")
	_expect(played[2] <= MAX_STAMP_AHEAD_TICKS,
		("the host's pose is stamped with the input it played again soon after --net-sim goes on (stamped ahead %d"
			+ " ticks in a row, at most %d)") % [played[2], MAX_STAMP_AHEAD_TICKS])
	var left: bool = await _wait_until(func() -> bool: return int(vehicle.driver_peer_id) == 0)
	_expect(left, "the client gets out of the driver's seat")
	_expect(int(vehicle.get(&"net_input_seq")) == 0, "with the client out, the host's pose stands for no input")
	await _pump(0.5)


@rpc("authority", "call_remote", "reliable")
func _client_drive(vehicle_path: NodePath) -> void:
	var vehicle: VehicleBody3D = get_node_or_null(vehicle_path) as VehicleBody3D
	if vehicle == null:
		_report(&"drive", false, "client has no truck to drive")
		return
	var predicting: bool = await _wait_until(func() -> bool: return bool(vehicle.call(&"is_predicted")), 10.0)
	var start: Vector3 = vehicle.global_position
	var clean: Dictionary = await _drive_for(vehicle, 2.0)
	var moved: float = vehicle.global_position.distance_to(start)
	print("DRIVE role=client predicted %s moved %.1f m, worst correction %.3f m/tick, error median %.3f worst %.3f" % [
		predicting, moved, clean.worst_shift, clean.median_error, clean.worst_error]
		+ ", host %d ticks behind" % clean.behind)
	# N-922.5: driving with the standard --net-sim profile, which on a LAN only the game can simulate: the inputs out
	# and the host's states back are held half its lag each (75-95 ms, 4-6 ticks), so the host's states come in later
	# -- and the corrections still stay under 10 cm a tick. N-922.9: the wheel weaving all along and the profile
	# switched on mid-drive, the host's input counter runs on through the first gap and the inputs land behind it; it
	# re-anchors a cushion behind them within a quarter second, so the host's states are stamped with the input they
	# come after again and the error doesn't grow (before, the counter stayed 3 ticks ahead for good, and the client
	# was corrected all along toward a truck that steered late).
	# Three seconds in all: about 25 m on the yard, short of the bump past it (contacts each peer feels its own way).
	var simulated: Dictionary = await _drive_into_net_sim(vehicle, 1.0, 2.0)
	var still_predicting: bool = bool(vehicle.call(&"is_predicted"))
	print(("DRIVE role=client --net-sim %s switched on mid-drive, the wheel weaving: worst correction %.3f m/tick,"
		+ " mean error %.3f m before, %.3f m the first second (worst %.3f), %.3f m after (worst %.3f),"
		+ " host %d ticks behind, %d inputs and %d host states held") % [
		NetStats.describe_sim(NetStats.STANDARD_SIM), simulated.worst_shift, simulated.clean_error,
		simulated.settling_error, simulated.settling_worst, simulated.settled_error, simulated.worst_error,
		simulated.behind, simulated.inputs_held, simulated.states_held])
	var player: Player = _player(get_tree().root.multiplayer.get_unique_id())
	if player != null:
		player.call(&"leave_seat")
	var frozen_again: bool = await _wait_until(func() -> bool: return vehicle.freeze, 5.0)
	var sim_ok: bool = still_predicting and int(simulated.inputs_held) >= 3 and int(simulated.states_held) >= 1 \
			and int(simulated.behind) - int(clean.behind) >= 3 and float(simulated.worst_shift) <= 0.1001 \
			and int(clean.inputs_held) == 0 and int(clean.states_held) == 0
	var steady: bool = float(simulated.settled_error) <= float(simulated.clean_error) + MAX_NET_SIM_ERROR_GROWTH
	var ok: bool = predicting and moved > 2.0 and float(clean.worst_shift) <= 0.1001 and frozen_again and sim_ok \
			and steady
	_report(&"drive", ok,
		("client at the wheel: predicted %s, moved %.1f m, worst correction %.3f m/tick, frozen again %s;"
		+ " with --net-sim: predicted %s, %d inputs and %d host states held, host %d ticks behind (clean %d),"
		+ " worst correction %.3f m/tick, mean error %.3f m once settled against %.3f m before it") % [
			predicting, moved, clean.worst_shift, frozen_again, still_predicting, simulated.inputs_held,
			simulated.states_held, simulated.behind, clean.behind, simulated.worst_shift, simulated.settled_error,
			simulated.clean_error])


## Client at the wheel: accelerates for `seconds`, then holds the handbrake for one. Returns the worst correction
## in a tick, the median and worst error measured, and how many ticks behind the client's newest input the host's
## newest state was (median).
func _drive_for(vehicle: VehicleBody3D, seconds: float) -> Dictionary:
	var prediction: VehiclePrediction = vehicle.get(&"_prediction")
	var worst_shift: float = 0.0
	var errors: Array[float] = []
	var behind: Array[int] = []
	var held_out: Array[int] = []
	var held_back: Array[int] = []
	Input.action_press(&"drive_accelerate")
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		worst_shift = maxf(worst_shift, prediction.last_shift)
		errors.append(prediction.reconciler.last_error)
		if prediction.host_seq > 0:
			behind.append(prediction.applied_seq - prediction.host_seq)
		held_out.append(prediction.uplink.pending())
		held_back.append(prediction.downlink.pending())
	Input.action_release(&"drive_accelerate")
	Input.action_press(&"drive_handbrake")
	await _pump(1.0)
	Input.action_release(&"drive_handbrake")
	return {
		"worst_shift": worst_shift,
		"median_error": _median(errors),
		"worst_error": errors.max() if not errors.is_empty() else INF,
		"behind": int(_median(behind)),
		"inputs_held": int(_median(held_out)),
		"states_held": int(_median(held_back)),
	}


## N-922.9: the client accelerates with the wheel weaving for `clean_seconds`, then the standard --net-sim profile is
## switched on mid-drive for `sim_seconds` more, then the handbrake for a second and the profile off again. Returns
## the reconciler's mean error before the switch, over the first second after it (the host's counter lands ahead of
## the inputs and re-anchors: the ticks it held an input meanwhile are corrected once) and over the rest; the worst
## correction in a tick since the switch; over the rest also the worst error, how many ticks behind the client's
## newest input the host's newest state was, and the inputs and states held (medians).
func _drive_into_net_sim(vehicle: VehicleBody3D, clean_seconds: float, sim_seconds: float) -> Dictionary:
	var prediction: VehiclePrediction = vehicle.get(&"_prediction")
	var clean: Array[float] = []
	var settling: Array[float] = []
	var settled: Array[float] = []
	var behind: Array[int] = []
	var held_out: Array[int] = []
	var held_back: Array[int] = []
	var worst_shift: float = 0.0
	var started: int = Time.get_ticks_msec()
	var sim_at: int = started + int(clean_seconds * 1000.0)
	var end_at: int = sim_at + int(sim_seconds * 1000.0)
	var simulating: bool = false
	Input.action_press(&"drive_accelerate")
	while Time.get_ticks_msec() < end_at:
		await get_tree().physics_frame
		var now: int = Time.get_ticks_msec()
		_steer(NET_SIM_WEAVE * sin(float(now - started) / 1000.0 * TAU / NET_SIM_WEAVE_PERIOD))
		if not simulating and now >= sim_at:
			vehicle.call(&"configure_net_sim", NetStats.STANDARD_SIM)
			simulating = true
			continue
		var error: float = prediction.reconciler.last_error
		if not simulating:
			clean.append(error)
			continue
		worst_shift = maxf(worst_shift, prediction.last_shift)
		if now < sim_at + 1000:
			settling.append(error)
		else:
			settled.append(error)
			if prediction.host_seq > 0:
				behind.append(prediction.applied_seq - prediction.host_seq)
			held_out.append(prediction.uplink.pending())
			held_back.append(prediction.downlink.pending())
	Input.action_release(&"drive_accelerate")
	_steer(0.0)
	Input.action_press(&"drive_handbrake")
	await _pump(1.0)
	Input.action_release(&"drive_handbrake")
	vehicle.call(&"configure_net_sim", {"lag_ms": 0, "jitter_ms": 0, "loss_pct": 0.0})
	return {
		"clean_error": _mean(clean),
		"settling_error": _mean(settling),
		"settling_worst": settling.max() if not settling.is_empty() else INF,
		"settled_error": _mean(settled),
		"worst_error": settled.max() if not settled.is_empty() else INF,
		"worst_shift": worst_shift,
		"behind": int(_median(behind)),
		"inputs_held": int(_median(held_out)),
		"states_held": int(_median(held_back)),
	}


## The wheel at `value` (-1 left .. 1 right), as a stick would put it.
static func _steer(value: float) -> void:
	Input.action_release(&"drive_left")
	Input.action_release(&"drive_right")
	if value > 0.0:
		Input.action_press(&"drive_right", value)
	elif value < 0.0:
		Input.action_press(&"drive_left", -value)


static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return INF
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / values.size()


static func _median(values: Array) -> float:
	if values.is_empty():
		return -1.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


## N-221: the client comes back from the same running game (same identity in
## its ready reply) under a new peer id. The host gives it its slot back, and
## with it the merit CrewProgression keeps under that slot. The host holds
## `held` all along: the client has to see it in the host's hands (N-908).
func _check_rejoin(old_client: int, old_slot: int, old_merit: int, held: DeliveryPackage,
		dropped: DeliveryPackage, left_at: Vector3) -> void:
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
	_expect(_player(1).carried_package == held, "the host still holds the box it picked up while the client was away")
	var back: Player = _player(_client_peer_id)
	_expect(back.global_position.distance_to(left_at) < 1.0,
		"the rejoined client comes back where it stood (at %s, left at %s)" % [back.global_position, left_at])
	_expect(back.carried_package == dropped and dropped.carrier == back,
		"the rejoined client has the box it dropped by leaving back in its hands")
	rpc_id(_client_peer_id, &"_client_check_rejoin", _client_peer_id, old_slot, held.get_path(), dropped.get_path())
	await _wait_for_report(&"rejoin")
	await _wait_for_report(&"late_carry")
	await _wait_for_report(&"own_box")


## N-221 follow-up: back from a pulled cable before the host noticed. The
## client's link is a ghost the host only drops when the new one says who it
## is; SceneMultiplayer lets go of it then and there (no peer_disconnected
## for it, ever), and its link closes after the level freed its player.
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
	# takes a level load. The host settles the previous rejoin
	# settle_delay_seconds after it (session timeout, 20 s): wait that out
	# first, or it overwrites the long timeout below and a slow load (CI) times
	# the ghost out before the client is back to have it dropped.
	var settled: bool = await _wait_until(func() -> bool:
		return int(_network.call(&"enet_timeout_msec", ghost)) == _session_timeout_msec())
	_expect(settled, "the rejoined client settles before it vanishes")
	var enet := get_tree().root.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	enet.get_peer(ghost).set_timeout(32, 120000, 120000)
	var removed: Array = []
	_network.connect(&"peer_removed", func(id: int) -> void: removed.append(id))
	var disconnected: Array = []
	var on_disconnected: Callable = func(id: int) -> void: disconnected.append(id)
	get_tree().root.multiplayer.peer_disconnected.connect(on_disconnected)
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
	_expect(package.is_held and package.carrier == _player(_client_peer_id),
		"the box the ghost held is back in the hands of the one who came back")
	var window: float = package.care.crisis_left
	_expect(window >= DeliveryPackage.CareModel.CRISIS_SECONDS - 1.0,
		"the box's rescue window was held when the ghost was dropped, and still is (%.1f s left)" % window)
	# SceneMultiplayer lets go of it as it is dropped (disconnect_peer(), its
	# signals blocked), not when its link closes: nothing more is sent to a
	# closing link ("max channels: 0"; run-net-pair.sh greps for it), and the
	# other clients hear it left.
	_expect(not get_tree().root.multiplayer.get_peers().has(ghost),
		"the host's multiplayer lets go of the ghost as it is dropped")
	await _pump(2.5)
	get_tree().root.multiplayer.peer_disconnected.disconnect(on_disconnected)
	_expect(not disconnected.has(ghost),
		"the ghost is let go of by the host itself, not when its link closes (no peer_disconnected for it)")
	_expect(removed == [ghost], "the ghost's link closing removes nothing more (removed %s)" % [removed])
	rpc_id(_client_peer_id, &"_client_check_ghost_rejoin", _client_peer_id, slot, package.get_path())
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


## Sent the frame the host moved a resting box. The new pose has to get here,
## and right behind it the box's full rate: a woken throttle sends every tick
## for its settle window, a stuck one only every rest_interval. Counting the
## syncs, not timing the first one, so a slow frame here can't pass or fail it.
@rpc("authority", "call_remote", "reliable")
func _client_check_rest(package_path: NodePath, moved_to: Vector3, rest_interval: float) -> void:
	var package: Node3D = get_node_or_null(package_path) as Node3D
	var arrived: bool = package != null and await _wait_until(func() -> bool:
		return package.global_position.distance_to(moved_to) < 0.02, 5.0)
	var syncs: Array[int] = [0]
	if arrived:
		var count := func() -> void: syncs[0] += 1
		var sync := package.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
		sync.synchronized.connect(count)
		await _pump(rest_interval * 0.8)
		sync.synchronized.disconnect(count)
	print("NETLOG role=client a moved resting box arrived: %s, then %d syncs in %.2f s" % [
		arrived, syncs[0], rest_interval * 0.8])
	_report(&"rest", arrived and syncs[0] >= 3,
		"client sees a resting box moved and sent at full rate again (arrived %s, %d syncs in %.2f s)"
		% [arrived, syncs[0], rest_interval * 0.8])


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
func _client_check_ghost_rejoin(my_id: int, slot: int, box_path: NodePath) -> void:
	await _pump(0.4)
	var me: int = get_tree().root.multiplayer.get_unique_id()
	var seen: int = int(_network.call(&"color_slot", me))
	var player: Player = _player(me)
	var box: Node = get_node_or_null(box_path)
	var ok: bool = me == my_id and seen == slot and player != null and box != null and player.carried_package == box
	_report(&"ghost_rejoin", ok,
		"the client back after vanishing wears its slot again (slot %d, sees %d) and holds its box again (holds %s)"
		% [slot, seen, player.carried_package if player != null else null])


@rpc("authority", "call_remote", "reliable")
func _client_check_rejoin(my_id: int, slot: int, held_path: NodePath, own_path: NodePath) -> void:
	await _pump(0.4)
	var me: int = get_tree().root.multiplayer.get_unique_id()
	var seen: int = int(_network.call(&"color_slot", me))
	var ok: bool = me == my_id and seen == slot and _player(me) != null
	_report(&"rejoin", ok, "the rejoined client sees its own colour slot again (slot %d, sees %d)" % [slot, seen])
	var held: Node = get_node_or_null(held_path)
	var host_player: Player = _player(1)
	var in_hand: Variant = host_player.carried_package if host_player != null else null
	_report(&"late_carry", held != null and in_hand == held,
		"the rejoined client sees the box the host picked up while it was away in the host's hands (sees %s)"
		% [in_hand])
	var own: Node = get_node_or_null(own_path)
	var mine: Player = _player(me)
	_report(&"own_box", own != null and mine != null and mine.carried_package == own,
		"the rejoined client holds the box it dropped by leaving again (holds %s)"
		% [mine.carried_package if mine != null else null])


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

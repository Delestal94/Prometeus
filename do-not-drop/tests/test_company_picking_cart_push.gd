extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_picking_cart_push.gd
##
## Pushing a picking cart without stopping (expansion D-0610.c2.b: picking_cart_grip.gd, CompanyCarts "step",
## picking_cart_point.gd ACTION_GRIP, picking_cart_view.gd):
## - a cart_push may carry a "step": short and clamped (CART_GRIP_MIN_STEP_M .. CART_PUSH_STEP_M; 0, 0.0 and
##   negatives are the shortest, an int counts), the whole CART_PUSH_STEP_M when it is missing, NaN, INF, a bool
##   or not a number, so every old push moves exactly as before;
## - the lead (PickingCartGrip.lead()): the holder's pace towards the cart times the lead time, never for one
##   standing, walking away or sideways, capped at CART_GRIP_MAX_LEAD_M;
## - the numbers hold together: a holder pressed against the solid deck (towards a corner, the worst) gets room
##   faster than Player.WALK_SPEED even with no lead, a step per interval keeps up with a runner, the cart lets go
##   past where a cart that ran ahead stops and within the reach of who holds it;
## - the cart's handle point is the grip (ACTION_GRIP) with a prompt of its own;
## - gripping the handle: the host's PickingCartGrip keeps the cart CART_GRIP_DISTANCE_M from the holder with
##   cart_push steps of their own peer (no new request or event: the same event the other peer applies, which
##   draws the same cart); never more than one step every CART_GRIP_INTERVAL_S; a holder that stays at the
##   distance (or walks away backwards) pushes nothing, and the cart is never dragged after them;
## - one holder per cart (a second is `taken`) and one cart per holder; the same handle again lets go;
## - it lets go on its own when the holder walks CART_GRIP_RELEASE_M away, when their hands change (they took
##   or stored something), when they have no player any more, when told to (any other use of the cart) and when
##   they leave the session (NetworkManager.peer_removed, multiplayer.peer_disconnected, back under the same id);
## - pushing into a shelf is the host's `blocked`: the cart stays, the holder hears it (a notice, at most one
##   every NOTICE_PAUSE_MSEC) and the grip waits CART_GRIP_BLOCKED_PAUSE_S before asking again, so a held
##   push against a wall is not a flood of requests; the grip stays and the holder can steer around;
## - a holder on a client walks with the cart on open floor for 3 s, the host seeing them late (the pose
##   cushion) and their peer getting the host's steps late (the round trip): walking and running on a LAN and
##   walking over a Steam-like link, towards a corner of the deck, the cart's deck as their own peer has it
##   never stops them, at most one step per interval, and the cart is still ahead and held at the end.
## The single push, the ENet pair and two carts: test_company_picking_cart_world / _net.

const CART: StringName = &"cart_1"
const HEN: StringName = &"hen"
const EPS: float = 0.001
const PLAYER_SCENE: String = "res://scenes/gameplay/player/player.tscn"
const SPRINT := preload("res://scripts/gameplay/player/player_sprint.gd")

var _failures: int = 0
var _net: CompanyNet
var _shed: CompanyShed
var _mirror: CompanyNet
var _mirror_shed: CompanyShed
var _grip: PickingCartGrip
var _refusals: Array = []
var _notices: Array[String] = []
var _events: int = 0
## Where the holder's feet are (world), as the host sees them.
var _feet: Variant = Vector3.ZERO
## The walk's clock (s), the delay of the host's events to the other peer and those still on the way.
var _clock: float = 0.0
var _event_lag: float = 0.0
var _in_flight: Array = []
## The player's capsule radius (player.tscn), what touches the deck.
var _radius: float = 0.35


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_radius = _player_radius()
	_test_step()
	_test_lead()
	_test_numbers()
	await _test_grip()
	if _failures == 0:
		print("PASS: a held handle makes the cart follow its holder ahead of them, in host-decided steps")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


# --- The step of a push ---


func _test_step() -> void:
	var full: float = CompanyTuning.CART_PUSH_STEP_M
	var short: float = CompanyTuning.CART_GRIP_MIN_STEP_M
	var base: Dictionary = {"cart": CART, "dir": Vector3(3.0, 5.0, 0.0)}
	_expect(is_equal_approx(float(CompanyCarts.push_ask(base)["step"]), full), "No step: the whole CART_PUSH_STEP_M")
	var cases: Array = [
		[0.4, 0.4, "A short step is kept"],
		[99.0, full, "A long step is cut to the whole one"],
		[-3.0, short, "A negative step is cut to the shortest"],
		[0.0, short, "A step of 0.0 is cut to the shortest"],
		[1, 1.0, "An int step counts as metres"],
		[0, short, "An int 0 is cut to the shortest"],
		[NAN, full, "NaN: the whole step"],
		[INF, full, "INF: the whole step"],
		[-INF, full, "-INF: the whole step"],
		[true, full, "A bool is not a number: the whole step"],
		["x", full, "Text is not a number: the whole step"],
		[null, full, "null: the whole step"],
	]
	for row: Array in cases:
		var ask: Dictionary = CompanyCarts.push_ask(base.merged({"step": row[0]}))
		_expect(not ask.is_empty() and is_equal_approx(float(ask["step"]), float(row[1])),
			"%s (%s -> %s)" % [row[2], row[0], ask.get("step")])
	_expect(CompanyCarts.push_ask({"cart": CART, "dir": Vector3.ZERO, "step": 0.4}).is_empty(),
		"A step does not make a zero direction valid")
	# check() moves the cart by the step.
	var carts := CompanyCarts.new()
	var station: Dictionary = {"at": Vector3(2.0, 0.0, 2.0), "stand_ok": func(_to: Vector3) -> bool: return true}
	var moved: Dictionary = carts.check(CompanyCarts.push_ask(base.merged({"step": 0.5,
		"dir": Vector3.RIGHT})), station)
	_expect(moved["reason"] == &"" and (moved["data"]["pos"] as Vector3).is_equal_approx(Vector3(2.5, 0.0, 2.0)),
		"A push of step 0.5 moves the cart 0.5 m (%s)" % [moved])
	moved = carts.check(CompanyCarts.push_ask({"cart": CART, "dir": Vector3.RIGHT}), station)
	_expect((moved["data"]["pos"] as Vector3).is_equal_approx(Vector3(2.0 + full, 0.0, 2.0)),
		"Without a step it moves the whole one")


# --- The lead ---


func _test_lead() -> void:
	var interval: float = CompanyTuning.CART_GRIP_INTERVAL_S
	var ahead_s: float = CompanyTuning.CART_GRIP_LEAD_S
	var away := Vector3(2.0, 0.0, 0.0)
	var walk: float = Player.WALK_SPEED
	var walked := Vector3(walk * interval, 0.3, 0.0)
	_expect(PickingCartGrip.lead(null, walked, interval, away) == 0.0, "No earlier look: no lead")
	_expect(is_equal_approx(PickingCartGrip.lead(Vector3.ZERO, walked, interval, away), walk * ahead_s),
		"Walking towards the cart: their pace times CART_GRIP_LEAD_S (%.3f)"
		% PickingCartGrip.lead(Vector3.ZERO, walked, interval, away))
	_expect(is_equal_approx(PickingCartGrip.lead(Vector3.ZERO, walked, interval, away, ahead_s + 0.1),
		walk * (ahead_s + 0.1)), "A longer lead time (the round trip) puts it further")
	_expect(PickingCartGrip.lead(Vector3.ZERO, -walked, interval, away) == 0.0, "Walking away: no lead")
	_expect(PickingCartGrip.lead(Vector3.ZERO, Vector3(0.0, 0.0, 1.0), interval, away) == 0.0, "Sideways: no lead")
	_expect(PickingCartGrip.lead(Vector3.ZERO, Vector3.ZERO, interval, away) == 0.0, "Standing still: no lead")
	_expect(PickingCartGrip.lead(Vector3.ZERO, walked, 0.0, away) == 0.0, "No time between the looks: no lead")
	_expect(is_equal_approx(PickingCartGrip.lead(Vector3.ZERO, Vector3(50.0, 0.0, 0.0), interval, away),
		CompanyTuning.CART_GRIP_MAX_LEAD_M), "A jump (a teleport) is capped at CART_GRIP_MAX_LEAD_M")
	_expect(PickingCartGrip.lead(Vector3.ZERO, walked, interval, away, NAN) == 0.0, "A NaN lead time: no lead")


# --- The numbers ---


func _test_numbers() -> void:
	var distance: float = CompanyTuning.CART_GRIP_DISTANCE_M
	var interval: float = CompanyTuning.CART_GRIP_INTERVAL_S
	_expect(CompanyTuning.CART_GRIP_MIN_STEP_M > 0.0
		and CompanyTuning.CART_GRIP_MIN_STEP_M < CompanyTuning.CART_PUSH_STEP_M and distance > 0.0
		and CompanyTuning.CART_GRIP_RELEASE_M > distance + CompanyTuning.CART_GRIP_MAX_LEAD_M,
		"The grip numbers are ordered: a cart that ran ahead and stopped is still held")
	# The reach origin is about 1.5 m over the feet and the cart's spot 0.5 m over its floor (CompanyShed).
	_expect(Vector2(CompanyTuning.CART_GRIP_RELEASE_M, 1.0).length() < Interactable.REMOTE_REACH,
		"While held the cart stays within the holder's reach, so the host never refuses a step as out_of_reach")
	_expect(_radius > 0.0, "The player's capsule is found in %s (%.2f)" % [PLAYER_SCENE, _radius])
	var touch: float = _corner_touch()
	_expect((distance - touch) / interval >= Player.WALK_SPEED,
		"Pressed against the deck with no lead (%.2f m from its centre) the holder gets room at %.2f m/s, over walking"
		% [touch, (distance - touch) / interval])
	_expect(SPRINT.RUN_SPEED * interval <= CompanyTuning.CART_PUSH_STEP_M,
		"One step per interval keeps up with a runner (%.2f m)" % (SPRINT.RUN_SPEED * interval))
	_expect(interval >= 0.15 - EPS, "At most %.1f steps a second per cart" % (1.0 / interval))


# --- The grip ---


func _test_grip() -> void:
	var state := DefaultShed.ScratchState.new()
	DefaultShed.load_default().apply_to(state)
	_net = CompanyNet.new()
	_net.name = "GripNet"
	_net.company = state
	_net.inventory = state.stock()
	root.add_child(_net)
	_shed = CompanyShed.new()
	_shed.name = "GripShed"
	root.add_child(_shed)
	_shed.follow(_net)
	_shed.rebuild(state, _net.inventory)
	_net.stations = _shed.station_for
	_net.player_origin = func(_peer: int) -> Variant:
		return (_feet as Vector3) + Vector3.UP * 1.5 if _feet is Vector3 else null
	_net.request_rejected.connect(func(rid: int, reason: StringName) -> void: _refusals.append([rid, reason]))
	_mirror = CompanyNet.new()
	_mirror.name = "GripMirror"
	_mirror.company = state
	_mirror.inventory.from_dict(_net.inventory.to_dict())
	root.add_child(_mirror)
	_mirror_shed = CompanyShed.new()
	_mirror_shed.name = "GripMirrorShed"
	root.add_child(_mirror_shed)
	_mirror_shed.follow(_mirror)
	_mirror_shed.rebuild(state, _mirror.inventory)
	_net.event_applied.connect(func(event_seq: int, kind: StringName, data: Dictionary) -> void:
		_events += 1
		if _event_lag > 0.0:
			_in_flight.append([_clock + _event_lag, event_seq, kind, data.duplicate(true)])
		else:
			_mirror._receive(event_seq, kind, data))
	_grip = PickingCartGrip.new()
	_grip.where = func(_peer: int) -> Variant: return _feet
	_grip.lag_of = func(_peer: int) -> float: return 0.0
	root.add_child(_grip)
	_grip.setup(_net, _shed)
	_grip.blocked_noticed.connect(func(text: String) -> void: _notices.append(text))
	await process_frame

	var view: PickingCartView = _shed.cart_views.get(CART) as PickingCartView
	if view == null:
		_expect(false, "The default shed has a cart")
		return
	_expect(view.push_point.action == PickingCartPoint.ACTION_GRIP and view.push_point.get_prompt() != ""
		and view.push_point.get_prompt() != view.load_point.get_prompt(),
			"The handle is the grip, with a prompt of its own")
	var distance: float = CompanyTuning.CART_GRIP_DISTANCE_M
	var interval: float = CompanyTuning.CART_GRIP_INTERVAL_S
	# A look that is due whatever came before (a refused step makes the next wait CART_GRIP_BLOCKED_PAUSE_S).
	var due: float = CompanyTuning.CART_GRIP_BLOCKED_PAUSE_S + 0.01
	var spot: Vector3 = view.global_position

	# Not gripped: time passes and nothing moves.
	_feet = spot + Vector3(-0.5, 0.0, 0.0)
	var seq_idle: int = _net.seq
	_grip.tick(1.0)
	_expect(_net.seq == seq_idle and not _grip.is_gripping(1), "Without a grip the cart does not follow")

	# Grip: the cart keeps its distance from the holder.
	_expect(_grip.toggle(1, CART) == PickingCartGrip.RESULT_GRIPPED and _grip.holder_of(CART) == 1
		and _grip.gripped_cart(1) == CART, "Using the handle grips it")
	_expect(_grip.toggle(2, CART) == PickingCartGrip.REASON_TAKEN and _grip.holder_of(CART) == 1,
		"A second holder is refused (taken)")
	_expect(_grip.toggle(1, &"cart_9") == PickingCartGrip.REASON_NO_CART, "An unknown cart cannot be gripped")
	_grip.tick(0.016)
	_expect(_net.seq == seq_idle + 1, "The first look pushes at once (%d events)" % (_net.seq - seq_idle))
	var gap: float = 0.5
	var expected_x: float = spot.x + (distance - gap)
	_expect(is_equal_approx(view.global_position.x, expected_x) and is_equal_approx(view.global_position.z, spot.z),
		"... with no earlier look (no lead), back to %.2f m from the holder (x %.3f, wanted %.3f)"
		% [distance, view.global_position.x, expected_x])
	_expect(_net.carts.position_of(CART) is Vector3
		and (_net.carts.position_of(CART) as Vector3).is_equal_approx(view.position),
		"CompanyCarts says the same")
	_expect(_refusals.is_empty(), "No refusal")

	# Rate cap: 2 s of 60 Hz frames with the holder always at the same gap make at most 2 / interval pushes.
	var before: int = _net.seq
	for _frame: int in 120:
		_feet = view.global_position + Vector3(-gap, 0.0, 0.0)
		_grip.tick(1.0 / 60.0)
	var pushes: int = _net.seq - before
	_expect(pushes >= 1 and pushes <= int(ceil(2.0 / interval)) + 1,
		"Walking with the cart, at most one step per %.2f s (%d pushes in 2 s)" % [interval, pushes])
	var moved_x: float = view.global_position.x - expected_x
	_expect(moved_x > 0.0 or pushes == 0 or not _refusals.is_empty(),
		"The cart went on ahead of the holder (%.2f m)" % moved_x)

	# At the distance, or backing off: nothing is asked and the cart is not dragged.
	_refusals.clear()
	var calm: Vector3 = view.global_position
	_feet = calm + Vector3(-distance - 0.01, 0.0, 0.0)
	var seq_calm: int = _net.seq
	_grip.tick(due)
	_grip.tick(0.5)
	_expect(_net.seq == seq_calm and view.global_position.is_equal_approx(calm) and _grip.is_gripping(1),
		"At the grip distance nothing is pushed")
	_feet = calm + Vector3(-distance - 1.0, 0.0, 0.0)
	_grip.tick(due)
	_expect(_net.seq == seq_calm and view.global_position.is_equal_approx(calm) and _grip.is_gripping(1),
		"Backing off a step does not drag the cart")

	# Too far: let go.
	var letgo: Array = []
	_grip.released.connect(func(peer: int, cart: StringName, why: StringName) -> void: letgo.append([peer, cart, why]))
	_feet = calm + Vector3(-CompanyTuning.CART_GRIP_RELEASE_M - 0.5, 0.0, 0.0)
	_grip.tick(due)
	_expect(not _grip.is_gripping(1) and letgo == [[1, CART, PickingCartGrip.WHY_AWAY]],
		"Walking away lets go (%s)" % [letgo])

	# Same handle again lets go; grip another cart lets go of the first (only one cart in this shed: use the id check).
	_feet = calm + Vector3(-0.8, 0.0, 0.0)
	_grip.toggle(1, CART)
	letgo.clear()
	_expect(_grip.toggle(1, CART) == PickingCartGrip.RESULT_RELEASED and not _grip.is_gripping(1)
		and letgo == [[1, CART, PickingCartGrip.WHY_TOGGLED]], "The same handle again lets go")

	# Hands change: let go.
	_grip.toggle(1, CART)
	_grip.tick(0.2)
	_net.inventory.receive(HEN, 1, CompanyNet.hands_location(1))
	_mirror.inventory.receive(HEN, 1, CompanyNet.hands_location(1))
	letgo.clear()
	_grip.tick(due)
	_expect(not _grip.is_gripping(1) and letgo == [[1, CART, PickingCartGrip.WHY_HANDS]],
		"Taking something into the hands lets go (%s)" % [letgo])
	_net.inventory.consume(HEN, 1, CompanyNet.hands_location(1))
	_mirror.inventory.consume(HEN, 1, CompanyNet.hands_location(1))

	# No player any more: let go. Told to: let go.
	_grip.toggle(1, CART)
	_feet = null
	letgo.clear()
	_grip.tick(0.2)
	_expect(not _grip.is_gripping(1) and letgo == [[1, CART, PickingCartGrip.WHY_GONE]],
		"Without a player the grip is let go")
	_feet = view.global_position + Vector3(-0.8, 0.0, 0.0)
	_grip.toggle(1, CART)
	_grip.release(1, PickingCartGrip.WHY_OTHER_USE)
	_expect(not _grip.is_gripping(1) and _grip.holder_of(CART) == 0, "release() lets go; releasing twice is harmless")
	_grip.release(1)

	_test_peer_left(view, letgo)

	# Against the shelves: blocked, a notice, a pause, the grip stays.
	await _push_into_wall(view)

	# Walking with it on a client, the host seeing them late and their peer getting the steps late.
	_walk(Player.WALK_SPEED, 0.1, 0.01, 0.02, "LAN, walking")
	_walk(SPRINT.RUN_SPEED, 0.1, 0.01, 0.02, "LAN, running")
	_walk(Player.WALK_SPEED, 0.2, 0.08, 0.16, "Steam-like link, walking")

	_expect(_events == _net.seq and _mirror.seq == _net.seq, "The other peer applied every event in order (%d / %d)"
		% [_mirror.seq, _net.seq])
	await create_timer(PickingCartView.SLIDE_SECONDS + 0.15).timeout
	var here: PickingCartView = _mirror_shed.cart_views.get(CART) as PickingCartView
	_expect(here != null and here.position.is_equal_approx(view.position),
		"The other peer draws the cart where it ended (%s vs %s)"
		% [here.position if here != null else null, view.position])

	for node: Node in [_grip, _mirror_shed, _mirror, _shed, _net]:
		node.free()


## A holder who leaves the session lets go, by whichever signal comes first; nobody else's grip is touched.
func _test_peer_left(view: PickingCartView, letgo: Array) -> void:
	_feet = view.global_position + Vector3(-CompanyTuning.CART_GRIP_DISTANCE_M - 0.1, 0.0, 0.0)
	var network: Node = root.get_node_or_null(^"/root/NetworkManager")
	if network != null and network.has_signal(&"peer_removed"):
		_grip.toggle(2, CART)
		letgo.clear()
		network.emit_signal(&"peer_removed", 7)
		_expect(_grip.holder_of(CART) == 2 and letgo.is_empty(), "Another peer leaving lets go of nothing")
		network.emit_signal(&"peer_removed", 2)
		_expect(not _grip.is_gripping(2) and _grip.holder_of(CART) == 0
			and letgo == [[2, CART, PickingCartGrip.WHY_LEFT]],
			"A holder off the roster (NetworkManager.peer_removed) lets go (%s)" % [letgo])
		_grip.toggle(4, CART)
		letgo.clear()
		network.emit_signal(&"peer_returned", 4, 4)
		_expect(not _grip.is_gripping(4) and letgo == [[4, CART, PickingCartGrip.WHY_LEFT]],
			"A holder back under the same id lets go (%s)" % [letgo])
	else:
		_expect(false, "The NetworkManager autoload is up in the test")
	_grip.toggle(3, CART)
	letgo.clear()
	root.multiplayer.peer_disconnected.emit(3)
	_expect(not _grip.is_gripping(3) and _grip.holder_of(CART) == 0 and letgo == [[3, CART, PickingCartGrip.WHY_LEFT]],
		"A holder whose connection drops (multiplayer.peer_disconnected) lets go (%s)" % [letgo])
	_grip.peer_left(3)
	_expect(letgo.size() == 1, "The second signal of the same leave finds nothing to let go")


## The holder west of the cart pushes it east until the shelves say blocked; then a long frame run asks little.
func _push_into_wall(view: PickingCartView) -> void:
	# The walk before may have used up the notice's pause already.
	var waited_from: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - waited_from < PickingCartGrip.NOTICE_PAUSE_MSEC + 100:
		await process_frame
	_grip.toggle(1, CART)
	_refusals.clear()
	_notices.clear()
	var blocked_at: Vector3 = Vector3.INF
	for _try: int in 40:
		# The holder stands east of the cart: pushing west, into the shelves.
		_feet = view.global_position + Vector3(0.5, 0.0, 0.0)
		_grip.tick(CompanyTuning.CART_GRIP_INTERVAL_S + 0.001)
		if not _refusals.is_empty():
			blocked_at = view.global_position
			break
	_expect(blocked_at != Vector3.INF and _refusals[0] == [0, CompanyCarts.REASON_BLOCKED],
		"Pushed into the shelves the host says blocked, to the holder's own peer (%s)" % [_refusals])
	if blocked_at == Vector3.INF:
		return
	_expect(_notices.size() == 1 and _notices[0] != "", "The holder gets one notice (%s)" % [_notices])
	_expect(_grip.is_gripping(1), "The grip stays after a blocked push, to steer around")
	# Long run at 60 Hz against the wall: the pause keeps the requests few and the notice does not repeat.
	var asked: int = _refusals.size()
	var seq: int = _net.seq
	for _frame: int in 60:
		_feet = view.global_position + Vector3(0.5, 0.0, 0.0)
		_grip.tick(1.0 / 60.0)
	var more: int = _refusals.size() - asked
	_expect(more <= int(ceil(1.0 / CompanyTuning.CART_GRIP_BLOCKED_PAUSE_S)) and _net.seq == seq
		and view.global_position.is_equal_approx(blocked_at),
		"In a second against the wall: %d tries, no event, the cart stays" % more)
	_expect(_notices.size() == 1, "... and no second notice inside the pause (%d)" % _notices.size())
	# Steering around: the holder to the west pushes it back east, the grip still works.
	_feet = view.global_position + Vector3(-0.5, 0.0, 0.0)
	_grip.tick(CompanyTuning.CART_GRIP_BLOCKED_PAUSE_S + 0.01)
	_expect(_net.seq == seq + 1 and view.global_position.x > blocked_at.x,
		"From the other side the same grip pushes it away")
	_grip.release(1)
	await process_frame


## A holder on a client walks at `speed` for 3 s towards a corner of the deck (where it is touched furthest from
## its centre) on open floor. The host sees their feet `view_lag` s late (sending and the pose cushion), their
## peer gets each step `event_lag` s after the host made it and the grip adds `round_trip` to the lead. Their
## player stops when its capsule would overlap the deck where their own peer has it (the cart's node: the look
## only slides behind it). It never should.
func _walk(speed: float, view_lag: float, event_lag: float, round_trip: float, label: String) -> void:
	var view: PickingCartView = _shed.cart_views.get(CART) as PickingCartView
	var seen: PickingCartView = _mirror_shed.cart_views.get(CART) as PickingCartView
	var shed_stations: Callable = _net.stations
	_net.stations = func(location: StringName) -> Dictionary:
		var station: Dictionary = _shed.station_for(location)
		if station.has("stand_ok"):
			station["stand_ok"] = func(_to: Vector3) -> bool: return true
		return station
	_grip.lag_of = func(_peer: int) -> float: return round_trip
	_event_lag = event_lag
	var dt: float = 1.0 / 60.0
	var way: Vector3 = Vector3(PickingCartView.LENGTH, 0.0, PickingCartView.WIDTH).normalized()
	var feet: Vector3 = view.global_position - way * CompanyTuning.CART_GRIP_DISTANCE_M
	var history: Array = [[_clock, feet]]
	_feet = feet
	_grip.toggle(1, CART)
	_grip.tick(dt)
	var seq: int = _net.seq
	var seen_seq: int = _mirror.seq
	var held_start: int = 0
	var held: int = 0
	var closest: float = INF
	var duration: float = 3.0
	for _frame: int in int(round(duration / dt)):
		_clock += dt
		_deliver(_clock)
		var going: bool = _mirror.seq > seen_seq
		var next: Vector3 = feet + way * speed * dt
		if _deck_clearance(seen, next) >= 0.0:
			feet = next
		elif going:
			held += 1
		else:
			held_start += 1
		if going:
			closest = minf(closest, _deck_clearance(seen, feet))
		history.append([_clock, feet])
		_feet = _seen_by_host(history, _clock - view_lag)
		_grip.tick(dt)
	_deliver(INF)
	var steps: int = _net.seq - seq
	_expect(held == 0, "%s: once the first step reached them the deck never stops the holder (%d frames held; "
		% [label, held] + "closest %.2f m from it)" % closest)
	# Setting off from a standstill nothing can move the cart before the host sees them go and the step comes
	# back: the deck may stop them that long at most (none when it is shorter than walking CART_GRIP_DISTANCE_M
	# minus where they touch it).
	var reaction: float = view_lag + event_lag + 2.0 * dt
	var free_start: bool = speed * reaction <= CompanyTuning.CART_GRIP_DISTANCE_M - _corner_touch()
	_expect(held_start * dt <= reaction - (CompanyTuning.CART_GRIP_DISTANCE_M - _corner_touch()) / speed + dt
		and (held_start == 0 or not free_start),
		"%s: setting off, the deck stops them at most until the first step comes (%.2f s held)"
		% [label, held_start * dt])
	_expect(steps >= 1 and steps <= int(ceil(duration / CompanyTuning.CART_GRIP_INTERVAL_S)) + 1,
		"%s: at most one step per interval (%d in %.0f s)" % [label, steps, duration])
	var ahead: float = (seen.global_position - feet).dot(way)
	_expect(_grip.is_gripping(1) and ahead > _corner_touch()
		and seen.global_position.is_equal_approx(view.global_position),
		"%s: the cart is still held and ahead of them, the same on both peers (%.2f m ahead)" % [label, ahead])
	_grip.release(1)
	_event_lag = 0.0
	_grip.lag_of = func(_peer: int) -> float: return 0.0
	_net.stations = shed_stations


## The host's events that reached the other peer by `now`, in order.
func _deliver(now: float) -> void:
	while not _in_flight.is_empty() and float(_in_flight[0][0]) <= now:
		var event: Array = _in_flight.pop_front()
		_mirror._receive(int(event[1]), event[2], event[3])


## Where the holder stood at `when` (the last place at or before it).
func _seen_by_host(history: Array, when: float) -> Vector3:
	var found: Vector3 = history[0][1]
	for entry: Array in history:
		if float(entry[0]) > when + 0.0001:
			break
		found = entry[1]
	return found


## How far a player's capsule standing at `feet` is from the deck of `cart` (negative: overlapping).
func _deck_clearance(cart: PickingCartView, feet: Vector3) -> float:
	var local: Vector3 = cart.global_transform.affine_inverse() * feet
	var outside := Vector2(maxf(absf(local.x) - PickingCartView.LENGTH * 0.5, 0.0),
		maxf(absf(local.z) - PickingCartView.WIDTH * 0.5, 0.0))
	return outside.length() - _radius


## How far from the cart's centre a player touches its deck coming at a corner, the furthest it can be.
func _corner_touch() -> float:
	return Vector2(PickingCartView.LENGTH * 0.5, PickingCartView.WIDTH * 0.5).length() + _radius


## The radius of the player's body capsule, read from its scene; -1 when not found.
func _player_radius() -> float:
	var scene := load(PLAYER_SCENE) as PackedScene
	if scene == null:
		return -1.0
	var state: SceneState = scene.get_state()
	for node: int in state.get_node_count():
		if state.get_node_type(node) != &"CollisionShape3D" or String(state.get_node_path(node, true)) != ".":
			continue
		for property: int in state.get_node_property_count(node):
			var value: Variant = state.get_node_property_value(node, property)
			if state.get_node_property_name(node, property) == &"shape" and value is CapsuleShape3D:
				return (value as CapsuleShape3D).radius
	return -1.0

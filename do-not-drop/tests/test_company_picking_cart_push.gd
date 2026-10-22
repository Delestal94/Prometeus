extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_picking_cart_push.gd
##
## Pushing a picking cart without stopping (expansion D-0610.c2.b: picking_cart_grip.gd, CompanyCarts "step",
## picking_cart_point.gd ACTION_GRIP, picking_cart_view.gd):
## - a cart_push may carry a "step": short and clamped (CART_GRIP_MIN_STEP_M .. CART_PUSH_STEP_M), the whole
##   CART_PUSH_STEP_M when it is missing, NaN or not a number, so every old push moves exactly as before;
## - the cart's handle point is the grip (ACTION_GRIP) with a prompt of its own;
## - gripping the handle: the host's PickingCartGrip keeps the cart CART_GRIP_DISTANCE_M from the holder with
##   short cart_push steps of their own peer (no new request or event: the same event the other peer applies,
##   which draws the same cart); never faster than one step every CART_GRIP_INTERVAL_S; a holder that stays
##   at the distance (or walks away backwards) pushes nothing, and the cart is never dragged after them;
## - one holder per cart (a second is `taken`) and one cart per holder; the same handle again lets go;
## - it lets go on its own when the holder walks CART_GRIP_RELEASE_M away, when their hands change (they took
##   or stored something), when they have no player any more, and when told to (any other use of the cart);
## - pushing into a shelf is the host's `blocked`: the cart stays, the holder hears it (a notice, at most one
##   every NOTICE_PAUSE_MSEC) and the grip waits CART_GRIP_BLOCKED_PAUSE_S before asking again, so a held
##   push against a wall is not a flood of requests; the grip stays and the holder can steer around;
## The single push, the ENet pair and two carts: test_company_picking_cart_world / _net.

const CART: StringName = &"cart_1"
const HEN: StringName = &"hen"
const EPS: float = 0.001

var _failures: int = 0
var _net: CompanyNet
var _shed: CompanyShed
var _mirror: CompanyNet
var _mirror_shed: CompanyShed
var _grip: PickingCartGrip
var _refusals: Array = []
var _notices: Array[String] = []
var _events: int = 0
## Where the holder's feet are (world).
var _feet: Variant = Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_step()
	await _test_grip()
	if _failures == 0:
		print("PASS: a held handle makes the cart follow its holder in short host-decided steps")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


# --- The step of a push ---


func _test_step() -> void:
	var full: float = CompanyTuning.CART_PUSH_STEP_M
	var short: float = CompanyTuning.CART_GRIP_MIN_STEP_M
	_expect(short > 0.0 and short < full and CompanyTuning.CART_GRIP_DISTANCE_M > 0.0
		and CompanyTuning.CART_GRIP_RELEASE_M > CompanyTuning.CART_GRIP_DISTANCE_M, "The grip numbers are ordered")
	var base: Dictionary = {"cart": CART, "dir": Vector3(3.0, 5.0, 0.0)}
	_expect(is_equal_approx(float(CompanyCarts.push_ask(base)["step"]), full), "No step: the whole CART_PUSH_STEP_M")
	_expect(is_equal_approx(float(CompanyCarts.push_ask(base.merged({"step": 0.4}))["step"]), 0.4),
		"A short step is kept")
	_expect(is_equal_approx(float(CompanyCarts.push_ask(base.merged({"step": 99.0}))["step"]), full),
		"A long step is cut to the whole one")
	_expect(is_equal_approx(float(CompanyCarts.push_ask(base.merged({"step": -3.0}))["step"]), short),
		"A negative step is cut to the shortest")
	_expect(is_equal_approx(float(CompanyCarts.push_ask(base.merged({"step": NAN}))["step"]), full),
		"NaN: the whole step")
	_expect(is_equal_approx(float(CompanyCarts.push_ask(base.merged({"step": "x"}))["step"]), full),
		"Not a number: the whole step")
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
		_mirror._receive(event_seq, kind, data))
	_grip = PickingCartGrip.new()
	_grip.where = func(_peer: int) -> Variant: return _feet
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
		"... a short step, back to %.2f m from the holder (x %.3f, wanted %.3f)"
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
		"Walking with the cart, at most one step per %.1f s (%d pushes in 2 s)" % [interval, pushes])
	var moved_x: float = view.global_position.x - expected_x
	_expect(moved_x > 0.0 or pushes == 0 or not _refusals.is_empty(),
		"The cart went on ahead of the holder (%.2f m)" % moved_x)

	# At the distance, or backing off: nothing is asked and the cart is not dragged.
	_refusals.clear()
	var calm: Vector3 = view.global_position
	_feet = calm + Vector3(-distance - 0.01, 0.0, 0.0)
	var seq_calm: int = _net.seq
	_grip.tick(0.5)
	_expect(_net.seq == seq_calm and view.global_position.is_equal_approx(calm) and _grip.is_gripping(1),
		"At the grip distance nothing is pushed")
	_feet = calm + Vector3(-distance - 1.0, 0.0, 0.0)
	_grip.tick(0.5)
	_expect(_net.seq == seq_calm and view.global_position.is_equal_approx(calm) and _grip.is_gripping(1),
		"Backing off a step does not drag the cart")

	# Too far: let go.
	var letgo: Array = []
	_grip.released.connect(func(peer: int, cart: StringName, why: StringName) -> void: letgo.append([peer, cart, why]))
	_feet = calm + Vector3(-CompanyTuning.CART_GRIP_RELEASE_M - 0.5, 0.0, 0.0)
	_grip.tick(0.5)
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
	_grip.tick(0.2)
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

	# Against the shelves: blocked, a notice, a pause, the grip stays.
	await _push_into_wall(view)

	_expect(_events == _net.seq and _mirror.seq == _net.seq, "The other peer applied every event in order (%d / %d)"
		% [_mirror.seq, _net.seq])
	await create_timer(PickingCartView.SLIDE_SECONDS + 0.15).timeout
	var here: PickingCartView = _mirror_shed.cart_views.get(CART) as PickingCartView
	_expect(here != null and here.position.is_equal_approx(view.position),
		"The other peer draws the cart where it ended (%s vs %s)"
		% [here.position if here != null else null, view.position])

	for node: Node in [_grip, _mirror_shed, _mirror, _shed, _net]:
		node.free()


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

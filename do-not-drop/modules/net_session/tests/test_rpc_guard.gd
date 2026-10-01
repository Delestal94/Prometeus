extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/net_session/tests/test_rpc_guard.gd
##
## RpcGuard on its own (net_session module, docs/modulos.md), the checks every
## any_peer RPC runs before trusting what it got:
## - NaN, inf and absurd coordinates are rejected in floats, vectors and poses,
##   and so are flattened or blown-up bases;
## - dictionaries: too many keys, nested values, arrays, objects, non-text keys,
##   long text or non-finite numbers are rejected; the key limit is the caller's;
## - argument arrays: too long or not plain is rejected;
## - long text, a long StringName and an absurdly long NodePath are rejected;
## - the per-peer request budget cuts a burst at REQUEST_BURST, refills at
##   REQUESTS_PER_SECOND, is per peer, starts full again after forget_peer()
##   and reset(); the host's own (local) calls are never limited and count as
##   from the host;
## - a critical request (letting go of a box) still gets through once a flood
##   spent the budget, from a reserve of CRITICAL_RESERVE refilled at
##   CRITICAL_PER_SECOND, and is cut once that is spent too; ordinary requests
##   never touch the reserve;
## - NetEventBus.request() only relays events listed in request_cooldowns, with
##   a few plain arguments.

var _failures: int = 0


class GameBus extends NetEventBus:
	signal ping_sent(peer_id: int, position: Vector3, label: String)
	signal box_ruined(peer_id: int, box: String)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_values()
	_check_containers()
	_check_budget()
	await _check_local_calls()
	await _check_bus_requests()
	if _failures == 0:
		print("PASS: RpcGuard rejects bad values, oversized input and floods; the bus relays only listed requests")
	quit(_failures)


func _check_values() -> void:
	_expect(RpcGuard.finite_float(0.5) and RpcGuard.finite_float(-1.0), "Ordinary floats pass")
	_expect(not RpcGuard.finite_float(NAN) and not RpcGuard.finite_float(INF) and not RpcGuard.finite_float(-INF),
		"NaN and inf floats are rejected")
	_expect(RpcGuard.finite_vec3(Vector3(12.0, 1.5, -300.0)), "A position on the route passes")
	_expect(not RpcGuard.finite_vec3(Vector3(NAN, 0.0, 0.0)), "A NaN position is rejected")
	_expect(not RpcGuard.finite_vec3(Vector3(0.0, INF, 0.0)), "An infinite position is rejected")
	_expect(not RpcGuard.finite_vec3(Vector3(0.0, 0.0, 1.0e9)), "A position a million km away is rejected")
	_expect(not RpcGuard.finite_vec2(Vector2(NAN, 0.0)), "A NaN Vector2 is rejected")
	var pose := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3.0, 1.0, -40.0))
	_expect(RpcGuard.finite_transform(pose), "A rotated pose passes")
	_expect(RpcGuard.finite_transform(Transform3D.IDENTITY), "The identity pose passes")
	var nan_basis := pose
	nan_basis.basis.x = Vector3(NAN, 0.0, 0.0)
	_expect(not RpcGuard.finite_transform(nan_basis), "A pose with NaN in its basis is rejected")
	_expect(not RpcGuard.finite_transform(Transform3D(Basis.IDENTITY, Vector3(INF, 0.0, 0.0))),
		"A pose with an infinite origin is rejected")
	_expect(not RpcGuard.finite_transform(Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)),
		"A flattened (zero-scale) pose is rejected")
	_expect(not RpcGuard.finite_transform(Transform3D(Basis.from_scale(Vector3.ONE * 50.0), Vector3.ZERO)),
		"A pose blown up 50 times is rejected")
	_expect(RpcGuard.text_ok("¡Cuidado!"), "A callout label passes")
	_expect(RpcGuard.text_ok("x".repeat(RpcGuard.MAX_TEXT_LENGTH)), "Text right at the limit passes")
	_expect(not RpcGuard.text_ok("x".repeat(RpcGuard.MAX_TEXT_LENGTH + 1)), "Text past the limit is rejected")
	_expect(RpcGuard.name_ok(&"tow_strap") and RpcGuard.name_ok(&""), "An id passes")
	_expect(not RpcGuard.name_ok(StringName("x".repeat(RpcGuard.MAX_TEXT_LENGTH + 1))),
		"A StringName past the text limit is rejected")
	_expect(RpcGuard.path_ok(^"Level/World/Vehicle/CargoBay/LeftSeat1PackageMount/InteractionArea/Player_1874223901"),
		"A deep path passes")
	_expect(not RpcGuard.path_ok(NodePath("Level/" + "n/".repeat(RpcGuard.MAX_PATH_LENGTH))),
		"A path past MAX_PATH_LENGTH is rejected")


func _check_containers() -> void:
	var input: Dictionary = {"steady": true, "calm": false, "direction_pressed": &"left", "tap": false,
		"lean": 0.4, "lean_fwd": -1.0, "work": false, "tool": &"tape", "balance": Vector2(0.1, 0.2), "x": null}
	_expect(RpcGuard.dict_ok(input), "A real per-frame input passes")
	var big: Dictionary = {}
	for index: int in RpcGuard.MAX_INPUT_KEYS + 1:
		big["k%d" % index] = true
	_expect(not RpcGuard.dict_ok(big), "A dictionary with too many keys is rejected (%d)" % big.size())
	_expect(not RpcGuard.dict_ok({"steady": true}, 0), "The key limit is the caller's")
	_expect(not RpcGuard.dict_ok({"lean": NAN}), "A NaN value is rejected")
	_expect(not RpcGuard.dict_ok({"balance": Vector2(INF, 0.0)}), "An infinite vector value is rejected")
	_expect(not RpcGuard.dict_ok({"nested": {"a": 1}}), "A nested dictionary is rejected")
	_expect(not RpcGuard.dict_ok({"list": [1, 2, 3]}), "An array value is rejected")
	_expect(not RpcGuard.dict_ok({"tool": "t".repeat(RpcGuard.MAX_TEXT_LENGTH + 1)}), "A long text value is rejected")
	_expect(not RpcGuard.dict_ok({7: true}), "A non-text key is rejected")
	_expect(not RpcGuard.dict_ok({"node": root}), "An object value is rejected")

	_expect(RpcGuard.args_ok([Vector3.ONE, "¡Frená!"]) and RpcGuard.args_ok([]), "Plain arguments pass")
	var many: Array = []
	many.resize(RpcGuard.MAX_ARGS + 1)
	_expect(not RpcGuard.args_ok(many), "Too many arguments are rejected")
	_expect(not RpcGuard.args_ok([Vector3(NAN, 0.0, 0.0)]), "A NaN argument is rejected")
	_expect(not RpcGuard.args_ok([[1, 2]]) and not RpcGuard.args_ok([{"a": 1}]), "Nested arguments are rejected")
	_expect(not RpcGuard.args_ok(["x".repeat(RpcGuard.MAX_TEXT_LENGTH + 1)]), "A long text argument is rejected")


func _check_budget() -> void:
	RpcGuard.reset()
	var burst: int = int(RpcGuard.REQUEST_BURST)
	var accepted: int = 0
	for index: int in burst + 25:
		if RpcGuard.take_request(22, 1000):
			accepted += 1
	_expect(accepted == burst, "A burst is cut at the per-peer budget (accepted %d of %d)" % [accepted, burst + 25])
	_expect(RpcGuard.take_request(33, 1000), "Another peer's budget is its own")
	var refilled: int = 0
	for index: int in burst:
		if RpcGuard.take_request(22, 2000):
			refilled += 1
	_expect(refilled == int(RpcGuard.REQUESTS_PER_SECOND),
		"A second later the peer has REQUESTS_PER_SECOND more (got %d)" % refilled)
	_expect(not RpcGuard.take_request(22, 2000), "...and no more")
	RpcGuard.forget_peer(22)
	_expect(RpcGuard.take_request(22, 2000), "A peer that left and came back starts with a full budget")
	RpcGuard.reset()
	var fresh: int = 0
	for index: int in burst:
		if RpcGuard.take_request(33, 2000):
			fresh += 1
	_expect(fresh == burst, "Ending the session resets every budget (got %d)" % fresh)
	RpcGuard.reset()
	_check_critical_reserve()


## A flood of ordinary requests must not cost a peer the one that lets go of
## a box; a flood of critical ones is still cut.
func _check_critical_reserve() -> void:
	var burst: int = int(RpcGuard.REQUEST_BURST)
	var reserve: int = int(RpcGuard.CRITICAL_RESERVE)
	for index: int in burst + 10:
		RpcGuard.take_request(44, 1000)
	_expect(not RpcGuard.take_request(44, 1000), "A flood spends the ordinary budget")
	var critical: int = 0
	for index: int in reserve + 5:
		if RpcGuard.take_critical_request(44, 1000):
			critical += 1
	_expect(critical == reserve, "Critical requests still get through, %d of them (got %d)" % [reserve, critical])
	_expect(not RpcGuard.take_critical_request(44, 1000), "...and are cut once the reserve is spent too")
	var refilled: int = 0
	for index: int in burst + reserve:
		if RpcGuard.take_critical_request(44, 2000):
			refilled += 1
	var expected: int = int(RpcGuard.REQUESTS_PER_SECOND) + int(RpcGuard.CRITICAL_PER_SECOND)
	_expect(refilled == expected, "A second later both refill: %d more (got %d)" % [expected, refilled])
	RpcGuard.reset()
	var ordinary: int = 0
	for index: int in burst + reserve:
		if RpcGuard.take_request(55, 3000):
			ordinary += 1
	_expect(ordinary == burst, "Ordinary requests never touch the reserve (got %d of %d)" % [ordinary, burst])
	_expect(RpcGuard.take_critical_request(55, 3000), "...which is still there for a critical one")
	RpcGuard.reset()


## Offline (a session of one) every call is the host's own: never limited,
## always from the host, attributed to peer 1.
func _check_local_calls() -> void:
	var node := Node.new()
	root.add_child(node)
	await process_frame
	var allowed: int = 0
	for index: int in 200:
		if RpcGuard.allow_request(node):
			allowed += 1
	_expect(allowed == 200, "The host's own requests are never limited (got %d of 200)" % allowed)
	_expect(RpcGuard.sender_ok(node) and RpcGuard.from_host(node) and RpcGuard.is_local_call(node),
		"A plain local call passes the sender checks")
	_expect(RpcGuard.sender_ok(node, 5), "A plain local call passes even an exact-peer check (host code)")
	_expect(RpcGuard.sender(node) == 1, "A local call is attributed to this peer (got %d)" % RpcGuard.sender(node))
	var loose := Node.new()
	_expect(RpcGuard.sender_ok(loose) and RpcGuard.allow_request(loose), "A node outside the tree counts as local")
	loose.free()
	node.queue_free()
	await process_frame


## request() is an any_peer RPC: without a list, any client could make the
## host relay any fact of the game.
func _check_bus_requests() -> void:
	var bus := GameBus.new()
	root.add_child(bus)
	await process_frame
	var pings: Array = []
	var ruined: Array = []
	bus.ping_sent.connect(func(peer: int, at: Vector3, label: String) -> void: pings.append([peer, at, label]))
	bus.box_ruined.connect(func(peer: int, box: String) -> void: ruined.append([peer, box]))
	bus.request(&"ping_sent", [Vector3.ONE, "¡Bache!"])
	_expect(pings.is_empty(), "An event not listed in request_cooldowns is refused (got %s)" % [pings])
	bus.request_cooldowns[&"ping_sent"] = 0.0
	bus.request(&"box_ruined", ["vase"])
	_expect(ruined.is_empty(), "Listing one event doesn't open the others")
	bus.request(&"ping_sent", [Vector3(NAN, 0.0, 0.0), "¡Bache!"])
	bus.request(&"ping_sent", [Vector3.ONE, "x".repeat(RpcGuard.MAX_TEXT_LENGTH + 1)])
	bus.request(&"ping_sent", [Vector3.ONE, {"nested": true}])
	_expect(pings.is_empty(), "A listed event with a NaN, a long text or a nested argument is refused")
	bus.request(&"ping_sent", [Vector3.ONE, "¡Bache!"])
	_expect(pings == [[1, Vector3.ONE, "¡Bache!"]], "A listed event with plain arguments is relayed (got %s)" % [pings])
	bus.queue_free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

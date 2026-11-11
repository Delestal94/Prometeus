extends RefCounted
## The crew of the company-day bot (tests/bot_company_day.gd, D-2016.4) and what its stages share: who plays, how
## each one asks CompanyNet, the shortcuts the bot still takes (BOT_STUB), the clock jumps (BOT_SKIP) and the
## longest stretch each player spent with nothing in the hands. Not a test: preloaded.
##
## Actors. The first is the host's own player (CompanyRoot.player, peer 1): its requests are CompanyNet.request().
## With two players the second is a local actor: one more Player of the crew in the host's world (player.tscn under
## World, named Player_<peer>, CompanyRoot.join_crew(), as the host's spawn makes them), with hands of its own
## (hands:<peer>). There is no session, so its requests go straight into the host's check of a peer's request
## (CompanyNet._take_request: reach from its own node, its own hands, the same events); only the transport is left
## out, and a refusal has no reason (nobody to send it to). D-2017 plays the pair over ENet. A third player and up
## are only a number for the day's orders: the stub `crew_size`.
##
## An actor is moved by teleport (go_to(): next to the spot, well inside the reach the host then measures) and never
## walks: headless the mouse is not captured, so a player's own movement does not run.
##
## Idle (roles-tripulacion.md §1, corte-vertical.md §4 bis): a player is busy with units in the hands (hands:<peer>
## in the stock), carrying a box (Player.carried_package), at a wheel (a fleet vehicle's driver_peer_id) or driving
## the forklift (meta `driving`). IdleWatch, a node under the world, looks every frame and keeps, per player, the
## longest stretch of wall-clock time without any of those, from the first stage to the day's SUMMARY.
##
## Pace: before the van leaves the bot works as fast as the requests go (the clock is jumped anyway). The actor who
## stays in the shed while the van is out works at a person's pace instead (STEP_SECONDS between two things done
## with the hands), or its idle time would say nothing.

## The CompanyNet method that takes a request made by a peer (private: CompanyNet.request_for() refuses a peer that
## is not connected, and a local actor is not).
const TAKE_REQUEST: StringName = &"_take_request"
## Peer id of the second actor (the host is 1).
const SECOND_PEER: int = 2
## Players that really play; the rest only size the orders.
const MAX_ACTORS: int = 2
## The bot stands this far from a station's spot (meters) when it uses it, well inside the reach.
const STAND_OFFSET: Vector3 = Vector3(0.0, 0.5, 1.0)
## Seconds between two things the actor who stays in the shed does with its hands (take, place, carry).
const STEP_SECONDS: float = 6.0
## A player may be this long (seconds) with neither a box in the hands nor a wheel.
const IDLE_LIMIT_SECONDS: float = 120.0
const WATCH_NAME: String = "BotIdleWatch"

## The shortcuts the bot still takes because the game has no way to do it: id -> the stage that takes it, the
## tasks that remove it and what the bot does instead. Each one used in a run prints its BOT_STUB line and blocks
## BOT_OK (corte-vertical.md §4).
const STUBS: Dictionary = {
	&"pallet_unload": {
		"stage": "receive_pallet", "tasks": "D-0607.c",
		"what": "the bot opens each pallet and takes its units by itself (Pallet.open, Pallet.take) and shelves them "
			+ "by hand: the game has no pallet station, no pallet_open request and no point to use",
	},
	&"table_use": {
		"stage": "pack_boxes", "tasks": "D-0701.b",
		"what": "the bot sends the box_* requests itself: the packing table has no interaction in the game "
			+ "(using it does nothing)",
	},
	&"order_claim": {
		"stage": "pack_boxes", "tasks": "order_claim (red-autoridad.md row 8, D-0804 / D-0807)",
		"what": "the bot says which order each table packs (CompanyTableNet.order_of): nothing in the game ties an "
			+ "order to a table",
	},
	&"door_settle": {
		"stage": "deliver", "tasks": "D-0340 + D-0815.b",
		"what": "the bot settles each order (OrderSettlement.settle) and records it on the trip: the company world "
			+ "has no delivery at a house's door, and the shared book fails those orders when the van is back",
	},
	&"crew_size": {
		"stage": "crew", "tasks": "D-2017",
		"what": "only two players play: the rest are a number for the day's orders",
	},
}


## The world's node that times each actor's idle stretches (see the header). The bot adds one per world.
class IdleWatch extends Node:
	var level: CompanyRoot
	## The actors watched: {peer, player}.
	var crew: Array = []
	var running: bool = false
	## peer -> msec of the last frame it was busy, and its longest stretch without (msec).
	var _last_busy: Dictionary = {}
	var _longest: Dictionary = {}

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		if running:
			sample(Time.get_ticks_msec())

	## Starts (again) from now, with every actor counted as just busy.
	func restart(actors: Array, now_msec: int) -> void:
		crew = actors
		_last_busy.clear()
		_longest.clear()
		for actor: Dictionary in crew:
			_last_busy[int(actor["peer"])] = now_msec
			_longest[int(actor["peer"])] = 0
		running = true

	## One look at every actor at `now_msec`.
	func sample(now_msec: int) -> void:
		for actor: Dictionary in crew:
			var peer: int = int(actor["peer"])
			if is_busy(actor):
				_last_busy[peer] = now_msec
			else:
				_longest[peer] = maxi(int(_longest.get(peer, 0)), now_msec - int(_last_busy.get(peer, now_msec)))

	## The day is over: the stretch in course counts up to now and nothing after.
	func stop(now_msec: int) -> void:
		if running:
			sample(now_msec)
		running = false

	## Whether `actor` has a box in the hands or a wheel right now (see the header).
	func is_busy(actor: Dictionary) -> bool:
		var player: Player = actor["player"] as Player
		if player == null or not is_instance_valid(player) or level == null or not is_instance_valid(level):
			return false
		var peer: int = int(actor["peer"])
		if is_instance_valid(player.carried_package) or player.has_meta(&"driving"):
			return true
		if level.net != null and not level.net.inventory.contents_at(CompanyNet.hands_location(peer)).is_empty():
			return true
		if level.fleet != null:
			for body: Node3D in level.fleet.vehicles():
				if int(body.get(&"driver_peer_id")) == peer:
					return true
		return false

	## peer -> the longest idle stretch so far, in seconds.
	func report() -> Dictionary:
		var out: Dictionary = {}
		for peer: int in _longest:
			out[peer] = float(_longest[peer]) / 1000.0
		return out


## The actors of `ctx` on the world `level`, made once per context: the host's player and, with two players or
## more, the local actor; the world's IdleWatch starts timing them. "" when they are ready, else why not.
static func ensure(level: CompanyRoot, ctx: Dictionary) -> String:
	if not (ctx["crew"] as Array).is_empty():
		return ""
	var crew: Array = [{"peer": level.multiplayer.get_unique_id(), "player": level.player}]
	var players: int = int(ctx["players"])
	if players >= 2:
		var second: Player = _second_actor(level)
		if second == null:
			return "no_second_actor"
		if not level.net.has_method(TAKE_REQUEST):
			return "no_actor_requests"
		crew.append({"peer": SECOND_PEER, "player": second})
	if players > MAX_ACTORS:
		stub(ctx, &"crew_size")
	ctx["crew"] = crew
	var watch := level.get_node_or_null(WATCH_NAME) as IdleWatch
	if watch == null:
		watch = IdleWatch.new()
		watch.name = WATCH_NAME
		watch.level = level
		level.add_child(watch)
	watch.restart(crew, Time.get_ticks_msec())
	ctx["idle_watch"] = watch
	return ""


## The second player of the crew in the host's world, as the host's spawn makes one (CompanyRoot._create_crew_member):
## made once, found again afterwards.
static func _second_actor(level: CompanyRoot) -> Player:
	var world: Node = level.get_node_or_null(^"World")
	if world == null:
		return null
	var node_name: String = CompanyRoot.PLAYER_PREFIX + str(SECOND_PEER)
	var found := world.get_node_or_null(NodePath(node_name)) as Player
	if found != null:
		return found
	var member := (load(CompanyRoot.PLAYER_SCENE) as PackedScene).instantiate() as Player
	if member == null:
		return null
	member.name = node_name
	member.position = CompanyRoot.crew_spawn(1)
	member.set_multiplayer_authority(SECOND_PEER)
	CompanyRoot.join_crew(member)
	world.add_child(member)
	return member


## The actor that does job number `index` (they take turns).
static func actor_for(ctx: Dictionary, index: int) -> Dictionary:
	var crew: Array = ctx["crew"]
	return crew[index % crew.size()]


## The host's own actor: the one who loads the van, drives and closes the day.
static func host(ctx: Dictionary) -> Dictionary:
	return (ctx["crew"] as Array)[0]


static func hands_of(actor: Dictionary) -> StringName:
	return CompanyNet.hands_location(int(actor["peer"]))


## The actor stands next to `spot`, as one walking up to it would.
static func go_to(tree: SceneTree, actor: Dictionary, spot: Vector3) -> void:
	(actor["player"] as Node3D).global_position = spot + STAND_OFFSET
	await tree.process_frame


## Whether the actor stands within the reach the host measures to `spot` (Interactable.REMOTE_REACH from its reach
## origin): the bot checks it before it uses anything that is used by hand (a box, a board).
static func in_reach(actor: Dictionary, spot: Vector3) -> bool:
	return CompanyNet.within_reach((actor["player"] as Player).reach_origin(), spot)


## A CompanyNet request as `actor` makes it. &"" when an event came out of it, else why not: the host's reason for
## its own player, &"refused" for the local actor (no session to send the reason through), &"dropped" when nothing
## happened and nobody said so.
static func ask(level: CompanyRoot, actor: Dictionary, kind: StringName, data: Dictionary) -> StringName:
	var net: CompanyNet = level.net
	var before: int = net.seq
	if int(actor["peer"]) != level.multiplayer.get_unique_id():
		net.call(TAKE_REQUEST, int(actor["peer"]), kind, data.merged({"rid": 0}, true))
		return &"" if net.seq > before else &"refused"
	var refusals: Array[StringName] = []
	var on_refused: Callable = func(_rid: int, reason: StringName) -> void: refusals.append(reason)
	net.request_rejected.connect(on_refused)
	var rid: int = net.request(kind, data)
	net.request_rejected.disconnect(on_refused)
	if rid == 0:
		return &"no_request"
	if not refusals.is_empty():
		return refusals[0]
	return &"" if net.seq > before else &"dropped"


## Notes that the run took the shortcut `id` (STUBS): once per run, in the order they were first taken.
static func stub(ctx: Dictionary, id: StringName) -> void:
	var taken: Array = ctx["stubs"]
	if STUBS.has(id) and not taken.has(id):
		taken.append(id)


## The line a shortcut prints: BOT_STUB <stage> <id> [<tasks>] <what the bot does instead>.
static func stub_line(id: StringName) -> String:
	var entry: Dictionary = STUBS.get(id, {})
	return "BOT_STUB %s %s [%s] %s" % [entry.get("stage", "?"), id, entry.get("tasks", "?"), entry.get("what", "")]


## Notes a jump of the day's clock (a time skip, not a shortcut: the bot does not sit through the 18 minutes of a
## day): BOT_SKIP <stage> clock <from> -> <to>, in game minutes.
static func skip(ctx: Dictionary, stage: String, from_min: float, to_min: float) -> void:
	(ctx["skips"] as Array).append("BOT_SKIP %s clock %d -> %d" % [stage, floori(from_min), floori(to_min)])


## The longest stretch each actor spent with nothing in the hands so far: peer -> seconds ({} before any stage).
static func idle_report(ctx: Dictionary) -> Dictionary:
	var watch: Variant = ctx.get("idle_watch")
	if watch == null or not is_instance_valid(watch):
		return ctx.get("idle", {})
	return (watch as IdleWatch).report()


## Stops the idle count of `ctx` (the day is over) and keeps its numbers in ctx.idle.
static func stop_idle(ctx: Dictionary) -> void:
	var watch: Variant = ctx.get("idle_watch")
	if watch != null and is_instance_valid(watch):
		(watch as IdleWatch).stop(Time.get_ticks_msec())
		ctx["idle"] = (watch as IdleWatch).report()

extends Node
## Only current-run state. All numbers here are provisional for the test route.
##
## Tracks every package in the van, not just one: losing a box no longer ends
## the delivery, it just scores less. With four passengers, one person's
## mistake ending everyone's run would be miserable -- the run only collapses
## if every last package is gone.
##
## Split by responsibility (N-225.5). The state, the signals and every RPC stay here; the rest are static
## helpers over that state: RunScoring (door points, the van's cargo tally, the endless score), RunResults
## (rows, route event, stories), RunDeadlines (plan, next one, tally), RunDeliveries (door records and
## photos), RunLeaderboard (the local board) and RunSession (the level side of a late join). The constants
## they define are re-exported below and the methods other files and tests call stay here as wrappers.

const DEADLINE_CUT = preload("res://scripts/core/deadline_cut.gd")
const RUN_SCORING = preload("res://scripts/core/run_scoring.gd")
const RUN_RESULTS = preload("res://scripts/core/run_results.gd")
const RUN_DEADLINES = preload("res://scripts/core/run_deadlines.gd")
const RUN_DELIVERIES = preload("res://scripts/core/run_deliveries.gd")
const RUN_LEADERBOARD = preload("res://scripts/core/run_leaderboard.gd")
const RUN_SESSION = preload("res://scripts/core/run_session.gd")

# What each delivery outcome pays and costs (run_scoring.gd).
const POINTS_INTACT: int = RUN_SCORING.POINTS_INTACT
const POINTS_AT_RISK: int = RUN_SCORING.POINTS_AT_RISK
const CHAOS_MULTIPLIER: float = RUN_SCORING.CHAOS_MULTIPLIER
const DISTANCE_POINTS_PER_METER: float = RUN_SCORING.DISTANCE_POINTS_PER_METER
const POINTS_DELIVERED_INTACT: int = RUN_SCORING.POINTS_DELIVERED_INTACT
const POINTS_DELIVERED_AT_RISK: int = RUN_SCORING.POINTS_DELIVERED_AT_RISK
const POINTS_DELIVERED_RUINED: int = RUN_SCORING.POINTS_DELIVERED_RUINED
const PENALTY_MISSED_HOUSE: int = RUN_SCORING.PENALTY_MISSED_HOUSE
const POINTS_PHOTO_BONUS: int = RUN_SCORING.POINTS_PHOTO_BONUS
const COMPLAINT_PENALTY: int = RUN_SCORING.COMPLAINT_PENALTY
const POINTS_DELIVERED_REPAIRED: int = RUN_SCORING.POINTS_DELIVERED_REPAIRED
const POINTS_DELIVERED_UNCONVINCING: int = RUN_SCORING.POINTS_DELIVERED_UNCONVINCING
const POINTS_DELIVERED_SUBSTITUTED: int = RUN_SCORING.POINTS_DELIVERED_SUBSTITUTED
const CARE_POINTS: Dictionary = RUN_SCORING.CARE_POINTS
# Deadlines (run_deadlines.gd), the results' rescue names (run_results.gd), the board (run_leaderboard.gd) and
# the phone's range (run_deliveries.gd).
const MAX_DEADLINES: int = RUN_DEADLINES.MAX_DEADLINES
const DEADLINE_SPEED: float = RUN_DEADLINES.DEADLINE_SPEED
const DEADLINE_SLACK: float = RUN_DEADLINES.DEADLINE_SLACK
const DEADLINE_STOP_SECONDS: float = RUN_DEADLINES.DEADLINE_STOP_SECONDS
const POINTS_DEADLINE_MET: int = RUN_DEADLINES.POINTS_DEADLINE_MET
const PENALTY_DEADLINE_MISSED: int = RUN_DEADLINES.PENALTY_DEADLINE_MISSED
const DEADLINE_REASONS: Array[String] = RUN_DEADLINES.DEADLINE_REASONS
const RESCUE_NAMES: Dictionary = RUN_RESULTS.RESCUE_NAMES
const MAX_LEADERBOARD_ENTRIES: int = RUN_LEADERBOARD.MAX_LEADERBOARD_ENTRIES
const PHOTO_REACH: float = RUN_DELIVERIES.PHOTO_REACH

## The shared repair kit a crew starts every run with: enough for one simple
## rescue per box, not an endless heal.
const CARE_SUPPLIES_START: Dictionary = {
	&"tape": 3, &"repair": 2, &"filler": 2, &"rag": 2, &"strap": 2, &"substitute": 1,
}
const MODE_DELIVERY: StringName = &"delivery"
const MODE_ENDLESS: StringName = &"endless"

var is_running: bool = false
var elapsed_seconds: float = 0.0
var results: Dictionary = {}
var current_mode: StringName = MODE_DELIVERY
## Meters traveled this run. Only meaningful in MODE_ENDLESS -- the level
## script updates it every physics frame (there's no delivery zone to
## trigger scoring off of instead). Kept here rather than read out of the
## level node so finish_run() has it even when triggered internally (e.g.
## _on_package_ruined below), not just from the three call sites in
## level_endless.gd's own _physics_process.
var current_distance: float = 0.0
## id -> {"integrity": float, "maximum": float, "state": int}
var cargo: Dictionary = {}
## One entry per house that resolved this run, in the order they did:
## {"house": int, "outcome": StringName, "package_id": StringName,
##  "photo": bool}. Photos are attached later by the phone camera, so this
## stays the single record of what happened at each door.
var deliveries: Array[Dictionary] = []
## Presentation data kept alongside the run so the results screen can name
## every order, including a house the crew never reached.
var cargo_names: Dictionary = {}
var house_assignments: Array = []
## Houses whose door was offered somebody else's box (house index -> true); a client remembers it.
var refused_houses: Dictionary = {}
## How many doors this run was supposed to reach, set by the level once the
## route has built itself. Counting missed houses off this instead of off
## the houses that force-resolved themselves keeps the penalty honest no
## matter how the run ends -- rolling the van 300 m short of the last stop
## is still three people left waiting, even though nobody ever drove past
## their door to trigger a "missed" record.
var expected_houses: int = 0
## house index -> Texture2D of the shot actually taken there. Kept beside
## the delivery records rather than inside them: the records are plain data
## that crosses the network, a texture never should.
var delivery_photos: Dictionary = {}
## Host-side attribution for CrewProgression's delivery_photo_taken listener.
## The signal keeps its existing compact signature; these fields describe
## the accepted shot while relay() emits it synchronously on the host.
var last_photo_peer_id: int = 0
var last_photo_package_id: StringName = &""

## The route event drawn for this run, so a late joiner gets it too.
var _event_id: StringName = &""
## Paths of the boxes handed over at a door this run. They're scene nodes, not
## spawned ones, so a joiner's freshly loaded level still has them: the host
## sends this list and the joiner frees them (send_session_state()).
var consumed_packages: Array[String] = []

## True once two or more packages were in trouble at the same moment. The
## score rewards it: surviving a shared scare is the story people retell.
var had_simultaneous_risk: bool = false
## Host-owned kit counts (CARE_SUPPLIES_START), mirrored to clients for the HUD.
var care_supplies: Dictionary = CARE_SUPPLIES_START.duplicate()
## This run's deadlines: [{house, seconds, reason}], same on every peer.
var deadlines: Array = []
## Care notes from the host that reached a client before their delivery did.
var _pending_care: Dictionary = {}

## Overridable so tests don't read/write the real save file on disk --
## user:// is a real per-project directory, not an in-memory sandbox.
var save_path: String = "user://leaderboard.json"
## [{"score": int, "date": String}, ...] sorted best-first, capped at
## MAX_LEADERBOARD_ENTRIES. Local-only for now (no accounts/backend yet).
var leaderboard: Array = []


func _ready() -> void:
	# Under a test script (--script) the main loop has a script of its own:
	# keep tests away from the player's real save, which they used to fill
	# with dozens of scripted runs and unlocks.
	if Engine.get_main_loop().get_script() != null:
		save_path = "user://test_leaderboard.json"
	EventBus.package_integrity_changed.connect(_on_integrity_changed)
	EventBus.package_state_changed.connect(_on_state_changed)
	EventBus.package_ruined.connect(_on_package_ruined)
	# Doors resolve on the host, but every peer scores its own run locally
	# (level_base.gd's _physics_process runs everywhere), so each one needs
	# the same delivery record. Both handlers are idempotent, which is what
	# makes it safe for the host to receive back the fact it just relayed.
	EventBus.house_delivery_recorded.connect(_on_house_delivery_recorded)
	EventBus.delivery_photo_taken.connect(_on_delivery_photo_taken)
	EventBus.delivery_care_noted.connect(_on_delivery_care_noted)
	EventBus.delivery_deadlines_set.connect(func(list: Array) -> void: deadlines = list.duplicate(true))
	EventBus.cargo_registered.connect(_on_cargo_registered)
	EventBus.houses_assigned.connect(_on_houses_assigned)
	EventBus.house_refused_package.connect(func(i: int, _l: String) -> void: refused_houses[i] = true)
	_load_leaderboard()


func _physics_process(delta: float) -> void:
	if is_running:
		elapsed_seconds += delta


func reset_run() -> void:
	is_running = false
	elapsed_seconds = 0.0
	results = {}
	cargo = {}
	had_simultaneous_risk = false
	deliveries = []
	cargo_names = {}
	house_assignments = []
	refused_houses = {}
	expected_houses = 0
	delivery_photos = {}
	last_photo_peer_id = 0
	last_photo_package_id = &""
	current_mode = MODE_DELIVERY
	current_distance = 0.0
	_event_id = &""
	RouteEventManager.reset_route()
	consumed_packages = []
	care_supplies = CARE_SUPPLIES_START.duplicate()
	_pending_care = {}
	deadlines = []


## Deadlines for houses at these distances along the road (metres, in house order); see RunDeadlines.plan().
static func plan_deadlines(distances: Array) -> Array:
	return RUN_DEADLINES.plan(distances)


## Host, as the run starts or when a deadline is shortened: posts the full list to every peer.
func set_deadlines(list: Array) -> void:
	EventBus.relay(&"delivery_deadlines_set", [list])


## Host, "impatient client" failed: the next open deadline after `after_house`
## gets shorter (DEADLINE_CUT) and is relayed. Returns that house, or -1 if none.
func shorten_next_deadline(after_house: int) -> int:
	if not is_running or (NetworkManager.is_online() and not NetworkManager.is_host()):
		return -1
	var cut: Dictionary = DEADLINE_CUT.shorten_next(deadlines, after_house, elapsed_seconds, _delivered_at)
	if not cut.is_empty():
		set_deadlines(cut["list"])
	return int(cut.get("house", -1))


## The closest deadline still open, for the HUD: {} when there is none.
func next_deadline() -> Dictionary:
	return RUN_DEADLINES.next_open(deadlines, deliveries, elapsed_seconds)


func _delivered_at(house_index: int) -> bool:
	return RUN_DELIVERIES.delivered_at(deliveries, house_index)


## Whether the resident actually got a box (not a house driven past, nor an order closed empty): RunDeliveries.
static func handed_over(outcome: StringName) -> bool:
	return RUN_DELIVERIES.handed_over(outcome)


## Met / missed counts over this run's deadlines, from the delivery record.
func deadline_tally() -> Dictionary:
	return RUN_DEADLINES.tally(deadlines, deliveries)


func care_supply_count(tool: StringName) -> int:
	return int(care_supplies.get(tool, 0))


## Host only: spends `amount` units (one by default), or says no if that
## would go below zero (two passengers finishing a repair on the same tick get
## one success). A negative amount puts units back: a service stop tops the
## kit up that way (N-110). Mirrored to every peer.
func consume_care_supply(tool: StringName, amount: int = 1) -> bool:
	if (NetworkManager.is_online() and not NetworkManager.is_host()) or care_supply_count(tool) - amount < 0:
		return false
	care_supplies[tool] = care_supply_count(tool) - amount
	if NetworkManager.is_online():
		_sync_care_supplies.rpc(care_supplies)
	return true


@rpc("authority", "call_remote", "reliable")
func _sync_care_supplies(supplies: Dictionary) -> void:
	care_supplies = supplies.duplicate()


## What DeliveryPackage.delivery_assessment() last said about a box: kept with
## its cargo entry so the door and the results can read it after the box is gone.
func record_care(id: StringName, assessment: Dictionary) -> void:
	_entry(id)["care"] = assessment.duplicate()


func care_category(id: StringName) -> StringName:
	if not cargo.has(id):
		return &""
	return StringName((cargo[id].get("care", {}) as Dictionary).get("category", ""))


## Online, only the host gets here: interactions resolve on the host
## (Interactable.interact() is host-only), so taking the wheel with cargo
## aboard starts the run there. It used to stop there too -- a client never
## heard run_started or run_ended, so it got no results screen and its own
## profile never counted the delivery. The host now hands the start (and the
## route event it drew, which is random) to every client.
func start_run(mode: StringName = MODE_DELIVERY) -> void:
	if is_running or not results.is_empty():
		return
	if NetworkManager.is_online() and not NetworkManager.is_host():
		return
	RouteEventManager.reset_route()
	_begin_run(mode)
	var event_id: StringName = RouteEventManager.begin_random()
	_event_id = event_id
	if NetworkManager.is_online() and NetworkManager.is_host():
		_remote_start_run.rpc(mode, event_id)


func _begin_run(mode: StringName) -> void:
	is_running = true
	current_mode = mode
	current_distance = 0.0
	EventBus.run_started.emit(&"test_route", [1])


@rpc("authority", "call_remote", "reliable")
func _remote_start_run(mode: StringName, event_id: StringName) -> void:
	if is_running or not results.is_empty():
		return
	_begin_run(mode)
	_event_id = event_id
	# The host's route_event_started relay carries the authoritative state.


## Called when a DeliveryHouse resolves (level_base.gd forwards route.gd's
## house_resolved). Records the outcome and takes the package out of the
## van's tally -- it isn't cargo any more, it's a delivery, and counting it
## in both places would pay twice for the same box.
func register_delivery(house_index: int, outcome: StringName, package_id: StringName, opened: bool = false) -> void:
	for entry: Dictionary in deliveries:
		if int(entry["house"]) == house_index:
			return
	var care: StringName = care_category(package_id) if handed_over(outcome) else &""
	if care.is_empty():
		care = StringName(_pending_care.get(house_index, &""))
	deliveries.append({
		"house": house_index,
		"outcome": outcome,
		"package_id": package_id,
		"photo": false,
		"care": care,
		"opened": opened,
		"at": elapsed_seconds,
	})
	if not package_id.is_empty() and cargo.has(package_id):
		cargo[package_id]["delivered"] = true
	# Before the delivery itself, so each door already knows which of its
	# rescue lines to use when house_delivery_recorded reaches it.
	if CARE_POINTS.has(care):
		EventBus.relay(&"delivery_care_noted", [house_index, care])
	EventBus.relay(&"house_delivery_recorded", [house_index, outcome, package_id])


## Files the photo the player just took against a specific door. Returns
## false when there's nothing to file it against (photographing a house
## nobody delivered to), so the caller can say so instead of silently
## pretending it counted.
func attach_delivery_photo(house_index: int) -> bool:
	return _attach_delivery_photo(house_index, NetworkManager.local_id())


func _attach_delivery_photo(house_index: int, peer_id: int) -> bool:
	var accepted: bool = _mark_photo(house_index)
	if accepted:
		last_photo_peer_id = peer_id
		last_photo_package_id = RUN_DELIVERIES.claim_package_at(deliveries, house_index)
		EventBus.relay(&"delivery_photo_taken", [house_index, true])
	return accepted


## What the phone calls, from any peer. The host files it directly; a client
## asks the host, which relays the result back. Answers right away (from this
## peer's copy of the record, which the host keeps in step) so the phone can
## say whether the shot counted without waiting on the round trip.
func submit_delivery_photo(house_index: int) -> bool:
	if not NetworkManager.is_online() or NetworkManager.is_host():
		return attach_delivery_photo(house_index)
	for entry: Dictionary in deliveries:
		if int(entry["house"]) == house_index:
			if bool(entry["photo"]) or not handed_over(StringName(entry["outcome"])):
				return false
			entry["photo"] = true
			_request_delivery_photo.rpc_id(NetworkManager.HOST_ID, house_index)
			return true
	return false


@rpc("any_peer", "call_remote", "reliable")
func _request_delivery_photo(house_index: int) -> void:
	if not NetworkManager.is_host() or not RpcGuard.allow_request(self):
		return
	# The photo has to come from someone standing at that door, not from
	# anywhere on the map.
	var sender_id: int = multiplayer.get_remote_sender_id()
	if not RUN_DELIVERIES.peer_near_house(get_tree(), sender_id, house_index):
		return
	_attach_delivery_photo(house_index, sender_id)


func _mark_photo(house_index: int) -> bool:
	return RUN_DELIVERIES.mark_photo(deliveries, house_index)


func _on_house_delivery_recorded(house_index: int, outcome: StringName, package_id: StringName) -> void:
	register_delivery(house_index, outcome, package_id)


## A client's cargo has no care record of its own: the host's note arrives
## just before the delivery it belongs to.
func _on_delivery_care_noted(house_index: int, category: StringName) -> void:
	_pending_care[house_index] = category
	for entry: Dictionary in deliveries:
		if int(entry["house"]) == house_index:
			entry["care"] = category


func _on_delivery_photo_taken(house_index: int, accepted: bool) -> void:
	if accepted:
		_mark_photo(house_index)


func _on_cargo_registered(package_id: StringName, name_key: String) -> void:
	cargo_names[package_id] = name_key


func _on_houses_assigned(assignments: Array) -> void:
	house_assignments = assignments.duplicate(true)


## Points and complaints from the doors, apart from the van tally in finish_run() (RunScoring.resolve_deliveries()).
func _resolve_deliveries() -> Dictionary:
	var line_seed: int = NetworkManager.world_seed if NetworkManager.world_seed != 0 else randi()  # solo: fresh
	return RUN_SCORING.resolve_deliveries(deliveries, house_assignments, refused_houses, expected_houses,
			deadlines, line_seed)


func finish_run(delivered: bool, reason: String = "") -> void:
	if not is_running:
		return
	# The host decides how the run ended and scores it; a client's copy of
	# the world only sees the replicated result of that (see _remote_finish_run).
	if NetworkManager.is_online() and not NetworkManager.is_host():
		return
	is_running = false
	RouteEventManager.close_for_run_end()
	if current_mode == MODE_ENDLESS:
		_finish_endless_run(reason)
		return
	# Boxes handed over at a door are scored by _resolve_deliveries() instead
	# -- they left the van on purpose, so counting them here too would pay
	# twice for the same package.
	var doors: Dictionary = _resolve_deliveries()
	var settled: Dictionary = RUN_SCORING.settle(cargo, doors, delivered, had_simultaneous_risk)
	var score: int = int(settled["score"])
	var is_new_best: bool = _record_score(score, MODE_DELIVERY)
	results = {
		"delivered": settled["successful"],
		"reason": reason,
		"elapsed_seconds": elapsed_seconds,
		"cargo_total": settled["aboard"],
		"cargo_intact": settled["intact"],
		"cargo_ruined": settled["ruined"],
		"cargo_points": settled["cargo_points"],
		"chaos_multiplier": settled["multiplier"],
		"delivery_points": doors["delivery_points"],
		"breakdown": settled["breakdown"],
		"houses_delivered": doors["houses_delivered"],
		"houses_missed": doors["houses_missed"],
		"houses_lost": doors["houses_lost"],
		"photos": doors["photos"],
		"complaints": doors["complaints"],
		"stories": rescue_stories() + world_stories(),
		"deliveries": RUN_RESULTS.delivery_rows(expected_houses, house_assignments, cargo_names, deliveries),
		"route_event": _result_route_event(),
		"score": score,
		"is_new_best": is_new_best,
		"best_score": best_score(MODE_DELIVERY),
	}
	_publish_results()
	EventBus.run_ended.emit(score, results.duplicate(true))


func _result_route_event() -> Dictionary:
	return RUN_RESULTS.route_event(_event_id, RouteEventManager.EVENTS.get(_event_id, {}),
			bool(RouteEventManager.resolved_events.get(_event_id, false)))


## Endless (docs/tareas-nacho.md #44/#52): no delivery zone, so the score is
## distance weighted by the cargo that lived through it (RunScoring.endless_score()).
## Kept as its own function rather than more branching inside finish_run()
## above, which was already written entirely around "did it arrive intact".
func _finish_endless_run(reason: String) -> void:
	var intact: int = 0
	var ruined: int = 0
	for entry: Dictionary in cargo.values():
		if int(entry.get("state", 0)) == ITrapBehavior.TrapState.RUINED:
			ruined += 1
		else:
			intact += 1
	var score: int = RUN_SCORING.endless_score(cargo, current_distance)
	var is_new_best: bool = _record_score(score, MODE_ENDLESS)
	results = {
		"delivered": false,
		"reason": reason,
		"elapsed_seconds": elapsed_seconds,
		"cargo_total": cargo.size(),
		"cargo_intact": intact,
		"cargo_ruined": ruined,
		"distance_traveled": current_distance,
		"score": score,
		"is_new_best": is_new_best,
		"best_score": best_score(MODE_ENDLESS),
	}
	_publish_results()
	EventBus.run_ended.emit(score, results.duplicate(true))


## Host: how the session stands, for a peer whose level just came up (a late
## joiner, or a client back from a restart). Everything else about a run
## reaches clients as one-off events -- the start, each delivery, the door
## closing, a box handed over -- so someone arriving after them saw a run
## that hadn't started, boxes that were long gone and the depot door open.
## Each box's name key, even delivered or lost ones; the joiner translates it (N-805).
func session_names() -> Dictionary:
	return RUN_SESSION.names(cargo, cargo_names)


func send_session_state(peer_id: int) -> void:
	if not NetworkManager.is_online() or not NetworkManager.is_host() or peer_id == NetworkManager.HOST_ID:
		return
	_receive_session_state.rpc_id(peer_id, {
		"running": is_running,
		"mode": current_mode,
		"event_id": RouteEventManager.active_event_id,
		"route_event": RouteEventManager.active_snapshot() if is_running else {},
		"elapsed": elapsed_seconds,
		"distance": current_distance,
		"expected_houses": expected_houses,
		"deliveries": deliveries.duplicate(true),
		"cargo": cargo.duplicate(true),
		"names": session_names(),
		"consumed": consumed_packages.duplicate(),
		"door_open": RUN_SESSION.depot_door_open(get_tree().current_scene),
		"results": results.duplicate(true),
		"care_supplies": care_supplies.duplicate(),
		"deadlines": deadlines.duplicate(true),
	})


@rpc("authority", "call_remote", "reliable")
func _receive_session_state(state: Dictionary) -> void:
	RUN_SESSION.free_consumed(self, state.get("consumed", []))
	if not bool(state.get("door_open", true)):
		RUN_SESSION.close_depot_door(get_tree().current_scene)
	expected_houses = int(state.get("expected_houses", expected_houses))
	care_supplies = (state.get("care_supplies", care_supplies) as Dictionary).duplicate()
	deadlines = (state.get("deadlines", deadlines) as Array).duplicate(true)
	deliveries.assign(state.get("deliveries", []))
	cargo = (state.get("cargo", {}) as Dictionary).duplicate(true)
	var host_results: Dictionary = state.get("results", {})
	if not host_results.is_empty():
		# Arrived after the run ended: it isn't this player's run to score or
		# count, so no results screen -- they wait for the host's restart,
		# which reloads everyone. Keeping the results still blocks a new start.
		is_running = false
		current_mode = StringName(state.get("mode", MODE_DELIVERY))
		results = host_results.duplicate(true)
		RouteEventManager.load_snapshot({})
		return
	if not bool(state.get("running", false)) or is_running:
		if is_running:
			RouteEventManager.load_snapshot(state.get("route_event", {}))
		return
	_remote_start_run(StringName(state.get("mode", MODE_DELIVERY)), StringName(state.get("event_id", &"")))
	RouteEventManager.load_snapshot(state.get("route_event", {}))
	elapsed_seconds = float(state.get("elapsed", 0.0))
	current_distance = float(state.get("distance", 0.0))
	# The HUD builds its cargo cards from these events as they happen.
	var names: Dictionary = state.get("names", {})
	for id: StringName in cargo:
		var entry: Dictionary = cargo[id]
		EventBus.cargo_registered.emit(id, String(names.get(id, id)))
		EventBus.package_integrity_changed.emit(
				id, float(entry.get("integrity", 100.0)), float(entry.get("maximum", 100.0)))
		EventBus.package_state_changed.emit(id, int(entry.get("state", 0)))


## Results are final: pay out, let the newspaper write itself (run_results_decided), share them.
func _publish_results() -> void:
	print("[Run] ", results)
	CrewProgression.award_delivery(results, NetworkManager.peer_ids)
	EventBus.run_results_decided.emit(results.duplicate(true))
	if NetworkManager.is_online() and NetworkManager.is_host():
		_remote_finish_run.rpc(current_mode, results)


## The host's results, as they are: same score, same breakdown, for every
## client. Only the leaderboard is each player's own (is_new_best/best_score
## are recomputed against it), and the team's money stays with the host
## (CrewProgression is host-authoritative), so it isn't awarded again here.
## run_ended then does the rest locally, like on the host: results screen,
## and UnlockManager counting the run in this player's profile.
@rpc("authority", "call_remote", "reliable")
func _remote_finish_run(mode: StringName, host_results: Dictionary) -> void:
	if not results.is_empty():
		return
	is_running = false
	current_mode = mode
	results = host_results.duplicate(true)
	var score: int = int(results.get("score", 0))
	results["is_new_best"] = _record_score(score, mode)
	results["best_score"] = best_score(mode)
	EventBus.run_ended.emit(score, results.duplicate(true))


## Local top-N high scores (RunLeaderboard), kept across runs and across app restarts.
func best_score(mode: StringName = MODE_DELIVERY) -> int:
	return RUN_LEADERBOARD.best_score(leaderboard, mode)


func _record_score(score: int, mode: StringName = MODE_DELIVERY, crew_size: int = -1) -> bool:
	var is_new_best: bool = score > best_score(mode)
	var players: int = maxi(crew_size if crew_size > 0 else NetworkManager.peer_ids.size(), 1)
	leaderboard = RUN_LEADERBOARD.add(leaderboard, score, mode, players)
	RUN_LEADERBOARD.save_board(save_path, leaderboard)
	return is_new_best


func _load_leaderboard() -> void:
	leaderboard = RUN_LEADERBOARD.load_board(save_path)


## One line per box that needed rescuing, for the results screen (RunResults.rescue_stories()).
func rescue_stories() -> Array[String]:
	return RUN_RESULTS.rescue_stories(cargo)


## Lines other systems add to the run's story (RunResults.world_stories()).
func world_stories() -> Array[String]:
	return RUN_RESULTS.world_stories(get_tree())


## Worst state across the cargo, for readouts that only have room for one.
func worst_state() -> int:
	var worst: int = ITrapBehavior.TrapState.OK
	for entry: Dictionary in cargo.values():
		worst = maxi(worst, int(entry.get("state", 0)))
	return worst


func _entry(id: StringName) -> Dictionary:
	if not cargo.has(id):
		cargo[id] = {"integrity": 100.0, "maximum": 100.0, "state": ITrapBehavior.TrapState.OK}
	return cargo[id]


func _on_integrity_changed(id: StringName, integrity: float, maximum: float) -> void:
	var entry: Dictionary = _entry(id)
	entry["integrity"] = integrity
	entry["maximum"] = maximum


func _on_state_changed(id: StringName, state: int) -> void:
	_entry(id)["state"] = state
	if _count_in_trouble() >= 2:
		had_simultaneous_risk = true


func _on_package_ruined(id: StringName, cause: String) -> void:
	print("[Package] ", id, " ruined: ", cause)
	_entry(id)["state"] = ITrapBehavior.TrapState.RUINED
	# Endless scores the meters each box survived (RunScoring.endless_score()); the last
	# ruin counts, so a box brought back by a substitute and lost again is
	# scored up to its second loss.
	_entry(id)["ruined_at_m"] = current_distance
	# Only what's still in the van can end the run: boxes already handed over
	# at a door are gone on purpose, and a delivered-everything run must not
	# read as "nothing left to deliver".
	var aboard: int = 0
	for entry: Dictionary in cargo.values():
		if not bool(entry.get("delivered", false)):
			aboard += 1
	# A lost hen can still go out as a toy while the kit has one: the run
	# isn't over while there's a playable way out.
	var kind := StringName((_entry(id).get("care", {}) as Dictionary).get("kind", ""))
	if kind == &"noisy" and care_supply_count(&"substitute") > 0:
		return
	if aboard > 0 and _count_ruined() >= aboard:
		# A key, like every run-end reason: each peer's results screen translates it.
		finish_run(false, "HUD_RUN_ALL_CARGO_RUINED")


func _count_in_trouble() -> int:
	var total: int = 0
	for entry: Dictionary in cargo.values():
		if int(entry.get("state", 0)) == ITrapBehavior.TrapState.AT_RISK:
			total += 1
	return total


func _count_ruined() -> int:
	var total: int = 0
	for entry: Dictionary in cargo.values():
		if bool(entry.get("delivered", false)):
			continue
		if int(entry.get("state", 0)) == ITrapBehavior.TrapState.RUINED:
			total += 1
	return total

extends Node
## Only current-run state. All numbers here are provisional for the test route.
##
## Tracks every package in the van, not just one: losing a box no longer ends
## the delivery, it just scores less. With four passengers, one person's
## mistake ending everyone's run would be miserable -- the run only collapses
## if every last package is gone.

const PAR_SECONDS: float = 75.0
const POINTS_INTACT: int = 100
const POINTS_AT_RISK: int = 50
const CHAOS_MULTIPLIER: float = 1.2
const MAX_LEADERBOARD_ENTRIES: int = 10

## docs/tareas-nacho.md #44/#52: endless never "delivers" (no zone to reach),
## so it can't use the cargo/time formula above -- distance is the only
## thing that keeps going up the longer a run survives. Placeholder weight,
## same as PAR_SECONDS above: tune by editing this constant, not the logic.
const DISTANCE_POINTS_PER_METER: float = 1.0

## Handing a box to a resident at their door is worth more than the same
## box merely surviving the trip in the van -- delivering is the goal, not
## hoarding. Showing up with a wrecked box still beats never showing up:
## the resident gets something, and the run gets a story.
const POINTS_DELIVERED_INTACT: int = 150
const POINTS_DELIVERED_AT_RISK: int = 75
const POINTS_DELIVERED_RUINED: int = 20
## Driving past a house nobody ever rang. Deliberately worse than delivering
## a ruined box: the resident waited for nothing.
const PENALTY_MISSED_HOUSE: int = 60
## The delivery photo (see the phone camera): a small reward on its own, and
## the only thing that settles a complaint afterwards.
const POINTS_PHOTO_BONUS: int = 25
## What an unanswered complaint costs. A resident whose box arrived wrecked
## always complains; one whose box arrived dented sometimes does.
const COMPLAINT_PENALTY: int = 40
const COMPLAINT_CHANCE_AT_RISK: float = 0.5

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

## The route event drawn for this run, so a late joiner gets it too.
var _event_id: StringName = &""
var lost_time_bonus: bool = false
## Paths of the boxes handed over at a door this run. They're scene nodes, not
## spawned ones, so a joiner's freshly loaded level still has them: the host
## sends this list and the joiner frees them (send_session_state()).
var consumed_packages: Array[String] = []

## True once two or more packages were in trouble at the same moment. The
## score rewards it: surviving a shared scare is the story people retell.
var had_simultaneous_risk: bool = false

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
	expected_houses = 0
	delivery_photos = {}
	current_mode = MODE_DELIVERY
	current_distance = 0.0
	_event_id = &""
	lost_time_bonus = false
	RouteEventManager.reset_route()
	consumed_packages = []


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
	lost_time_bonus = false
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
func register_delivery(house_index: int, outcome: StringName, package_id: StringName) -> void:
	for entry: Dictionary in deliveries:
		if int(entry["house"]) == house_index:
			return
	deliveries.append({
		"house": house_index,
		"outcome": outcome,
		"package_id": package_id,
		"photo": false,
	})
	if not package_id.is_empty() and cargo.has(package_id):
		cargo[package_id]["delivered"] = true
	EventBus.relay(&"house_delivery_recorded", [house_index, outcome, package_id])


## Files the photo the player just took against a specific door. Returns
## false when there's nothing to file it against (photographing a house
## nobody delivered to), so the caller can say so instead of silently
## pretending it counted.
func attach_delivery_photo(house_index: int) -> bool:
	var accepted: bool = _mark_photo(house_index)
	if accepted:
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
			if bool(entry["photo"]) or StringName(entry["outcome"]) == &"missed":
				return false
			entry["photo"] = true
			_request_delivery_photo.rpc_id(NetworkManager.HOST_ID, house_index)
			return true
	return false


@rpc("any_peer", "call_remote", "reliable")
func _request_delivery_photo(house_index: int) -> void:
	if not NetworkManager.is_host():
		return
	# The photo has to come from someone standing at that door, not from
	# anywhere on the map.
	if not _peer_near_house(multiplayer.get_remote_sender_id(), house_index):
		return
	attach_delivery_photo(house_index)


## The phone's own range plus some slack for the time the request travelled.
const PHOTO_REACH: float = 20.0


func _peer_near_house(peer_id: int, house_index: int) -> bool:
	var house_position: Variant = null
	for house: Node in get_tree().get_nodes_in_group(&"delivery_house"):
		if int(house.get(&"house_index")) == house_index:
			house_position = house.call(&"porch_position")
	if house_position == null:
		return false
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		if player.get_multiplayer_authority() == peer_id:
			return (player.call(&"reach_origin") as Vector3).distance_to(house_position) <= PHOTO_REACH
	return false


func _mark_photo(house_index: int) -> bool:
	for entry: Dictionary in deliveries:
		if int(entry["house"]) == house_index:
			# Nothing was delivered at a house the run drove past: there's
			# nothing for a photo to prove, and it used to earn the bonus.
			if bool(entry["photo"]) or StringName(entry["outcome"]) == &"missed":
				return false
			entry["photo"] = true
			return true
	return false


func _on_house_delivery_recorded(house_index: int, outcome: StringName, package_id: StringName) -> void:
	register_delivery(house_index, outcome, package_id)


func _on_delivery_photo_taken(house_index: int, accepted: bool) -> void:
	if accepted:
		_mark_photo(house_index)


## Points and complaints from the doors, kept apart from the van tally in
## finish_run() so each side stays readable on its own.
func _resolve_deliveries() -> Dictionary:
	var points: int = 0
	var delivered_count: int = 0
	var missed: int = 0
	var photos: int = 0
	var complaints: Array[Dictionary] = []
	for entry: Dictionary in deliveries:
		var outcome: StringName = StringName(entry["outcome"])
		var has_photo: bool = bool(entry["photo"]) and outcome != &"missed"
		if has_photo:
			photos += 1
			points += POINTS_PHOTO_BONUS
		match outcome:
			&"delivered_ok":
				points += POINTS_DELIVERED_INTACT
				delivered_count += 1
			&"delivered_ruined":
				points += POINTS_DELIVERED_RUINED
				delivered_count += 1
				complaints.append(_complaint(entry, has_photo))
			&"missed":
				missed += 1
				points -= PENALTY_MISSED_HOUSE
			&"delivered_at_risk":
				# Handed over dented. Worth less than intact, and the
				# resident might bring it up later -- which is the case the
				# delivery photo exists to answer.
				points += POINTS_DELIVERED_AT_RISK
				delivered_count += 1
				if randf() < COMPLAINT_CHANCE_AT_RISK:
					complaints.append(_complaint(entry, has_photo))
			_:
				push_warning("[Run] Unknown delivery outcome: %s" % outcome)
	# Doors the run never reached at all: no house ever resolved them, so
	# they have no record of their own, but the resident still waited.
	var unreached: int = maxi(expected_houses - deliveries.size(), 0)
	missed += unreached
	points -= unreached * PENALTY_MISSED_HOUSE
	var unanswered: int = 0
	for complaint: Dictionary in complaints:
		if not bool(complaint["dismissed"]):
			points -= COMPLAINT_PENALTY
			unanswered += 1
	# Line by line, for the results screen (tareas de Slatex #89): the same
	# sums as `points`, so the lines always add up to the score shown.
	var counts: Dictionary = {}
	for entry: Dictionary in deliveries:
		counts[StringName(entry["outcome"])] = int(counts.get(StringName(entry["outcome"]), 0)) + 1
	var breakdown: Array = []
	_add_line(breakdown, "Entregas perfectas", int(counts.get(&"delivered_ok", 0)), POINTS_DELIVERED_INTACT)
	_add_line(breakdown, "Entregas abolladas", int(counts.get(&"delivered_at_risk", 0)), POINTS_DELIVERED_AT_RISK)
	_add_line(breakdown, "Entregas arruinadas", int(counts.get(&"delivered_ruined", 0)), POINTS_DELIVERED_RUINED)
	_add_line(breakdown, "Fotos de entrega", photos, POINTS_PHOTO_BONUS)
	_add_line(breakdown, "Vecinos sin su paquete", missed, -PENALTY_MISSED_HOUSE)
	_add_line(breakdown, "Reclamos sin foto", unanswered, -COMPLAINT_PENALTY)
	return {
		"breakdown": breakdown,
		"delivery_points": points,
		"houses_delivered": delivered_count,
		"houses_missed": missed,
		"photos": photos,
		"complaints": complaints,
	}


## A photo of the doorstep is proof of what was handed over, so a complaint
## filed against a delivery that has one is dismissed on the spot.
func _add_line(breakdown: Array, label: String, count: int, each: int) -> void:
	if count > 0:
		breakdown.append({"label": "%s (%d)" % [label, count], "points": count * each})


func _complaint(entry: Dictionary, has_photo: bool) -> Dictionary:
	return {
		"house": int(entry["house"]),
		"dismissed": has_photo,
	}


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
	var cargo_points: int = 0
	var intact: int = 0
	var ruined: int = 0
	var aboard: int = 0
	for entry: Dictionary in cargo.values():
		if bool(entry.get("delivered", false)):
			continue
		aboard += 1
		if not delivered:
			ruined += 1
			continue
		match int(entry.get("state", 0)):
			ITrapBehavior.TrapState.OK:
				cargo_points += POINTS_INTACT
				intact += 1
			ITrapBehavior.TrapState.AT_RISK:
				cargo_points += POINTS_AT_RISK
			_:
				ruined += 1
	var delivery_points: int = int(doors["delivery_points"])
	var houses_delivered: int = int(doors["houses_delivered"])
	var successful: bool = delivered and (cargo_points > 0 or houses_delivered > 0)
	var time_bonus: int = roundi(50.0 * clampf(1.0 - elapsed_seconds / PAR_SECONDS, 0.0, 1.0)) if successful and not lost_time_bonus else 0
	var multiplier: float = CHAOS_MULTIPLIER if (successful and had_simultaneous_risk) else 1.0
	var score: int = maxi(roundi((cargo_points + time_bonus + delivery_points) * multiplier), 0)
	var breakdown: Array = (doors["breakdown"] as Array).duplicate(true)
	if cargo_points > 0:
		breakdown.append({"label": "Carga que volvió sana (%d)" % (aboard - ruined), "points": cargo_points})
	if time_bonus > 0:
		breakdown.append({"label": "Rapidez", "points": time_bonus})
	var is_new_best: bool = _record_score(score, MODE_DELIVERY)
	results = {
		"delivered": successful,
		"reason": reason,
		"elapsed_seconds": elapsed_seconds,
		"cargo_total": aboard,
		"cargo_intact": intact,
		"cargo_ruined": ruined,
		"cargo_points": cargo_points,
		"time_bonus": time_bonus,
		"chaos_multiplier": multiplier,
		"delivery_points": delivery_points,
		"breakdown": breakdown,
		"houses_delivered": houses_delivered,
		"houses_missed": int(doors["houses_missed"]),
		"photos": int(doors["photos"]),
		"complaints": doors["complaints"],
		"score": score,
		"is_new_best": is_new_best,
		"best_score": best_score(MODE_DELIVERY),
	}
	print("[Run] ", results)
	CrewProgression.award_delivery(results, NetworkManager.peer_ids)
	_share_results()
	EventBus.run_ended.emit(score, results.duplicate(true))


## Endless (docs/tareas-nacho.md #44/#52): no delivery zone, so distance
## traveled is the score, full stop -- cargo state is reported for the
## results text but never subtracted from it. Kept as its own function
## rather than more branching inside finish_run() above, which was already
## written entirely around "did it arrive intact", not distance.
func _finish_endless_run(reason: String) -> void:
	var intact: int = 0
	var ruined: int = 0
	for entry: Dictionary in cargo.values():
		if int(entry.get("state", 0)) == ITrapBehavior.TrapState.RUINED:
			ruined += 1
		else:
			intact += 1
	var score: int = roundi(current_distance * DISTANCE_POINTS_PER_METER)
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
	print("[Run] ", results)
	CrewProgression.award_delivery(results, NetworkManager.peer_ids)
	_share_results()
	EventBus.run_ended.emit(score, results.duplicate(true))


## Host: how the session stands, for a peer whose level just came up (a late
## joiner, or a client back from a restart). Everything else about a run
## reaches clients as one-off events -- the start, each delivery, the door
## closing, a box handed over -- so someone arriving after them saw a run
## that hadn't started, boxes that were long gone and the depot door open.
func send_session_state(peer_id: int) -> void:
	if not NetworkManager.is_online() or not NetworkManager.is_host() or peer_id == NetworkManager.HOST_ID:
		return
	var names: Dictionary = {}
	for package: Node in get_tree().get_nodes_in_group(&"cargo"):
		var id: StringName = package.get(&"package_id")
		if cargo.has(id):
			names[id] = String(package.get(&"trap_definition").get(&"display_name"))
	var door_open: bool = true
	var scene: Node = get_tree().current_scene
	var depot: Node = scene.get(&"depot") as Node if scene != null else null
	if depot != null and depot.get(&"door") != null:
		door_open = bool(depot.get(&"door").get(&"is_open"))
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
		"names": names,
		"consumed": consumed_packages.duplicate(),
		"door_open": door_open,
		"results": results.duplicate(true),
	})


@rpc("authority", "call_remote", "reliable")
func _receive_session_state(state: Dictionary) -> void:
	for path: String in state.get("consumed", []):
		var package: Node = get_node_or_null(NodePath(path))
		if package != null:
			package.remove_from_group(&"cargo")
			package.queue_free()
	if not bool(state.get("door_open", true)):
		var scene: Node = get_tree().current_scene
		var depot: Node = scene.get(&"depot") as Node if scene != null else null
		if depot != null and depot.get(&"door") != null:
			depot.get(&"door").call(&"set_open", false, false)
	expected_houses = int(state.get("expected_houses", expected_houses))
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
		EventBus.package_integrity_changed.emit(id, float(entry.get("integrity", 100.0)), float(entry.get("maximum", 100.0)))
		EventBus.package_state_changed.emit(id, int(entry.get("state", 0)))


func _share_results() -> void:
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


## Local top-N high scores, kept across runs and across app restarts. Every
## finished run gets recorded (even a 0-point failure) -- sorting keeps the
## list meaningful on its own, no need to filter before inserting.
## Entries written before endless existed have no "mode" key -- treated as
## MODE_DELIVERY so old saves keep working instead of vanishing from the board.
func best_score(mode: StringName = MODE_DELIVERY) -> int:
	for entry: Dictionary in leaderboard:
		if StringName(entry.get("mode", MODE_DELIVERY)) == mode:
			return int(entry["score"])
	return 0


func _record_score(score: int, mode: StringName = MODE_DELIVERY) -> bool:
	var is_new_best: bool = score > best_score(mode)
	leaderboard.append({"score": score, "date": Time.get_date_string_from_system(), "mode": mode})
	leaderboard.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	_trim_leaderboard()
	_save_leaderboard()
	return is_new_best


## Caps MAX_LEADERBOARD_ENTRIES per mode, not across the whole array -- a
## flat global cap would let endless's distance-based scores (a completely
## different scale from delivery's ~0-360) crowd delivery runs out of the
## saved board entirely, or vice versa. Relies on the array already being
## score-sorted (always true here, called right after sort_custom above),
## so each mode's kept slice is naturally its own top N.
func _trim_leaderboard() -> void:
	var kept: Array = []
	var counts: Dictionary = {}
	for entry: Dictionary in leaderboard:
		var mode: StringName = StringName(entry.get("mode", MODE_DELIVERY))
		var count: int = int(counts.get(mode, 0))
		if count < MAX_LEADERBOARD_ENTRIES:
			kept.append(entry)
			counts[mode] = count + 1
	leaderboard = kept


func _load_leaderboard() -> void:
	LegacyUserData.migrate()
	leaderboard = []
	if not FileAccess.file_exists(save_path):
		return
	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		leaderboard = parsed


func _save_leaderboard() -> void:
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(leaderboard))


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
	# Only what's still in the van can end the run: boxes already handed over
	# at a door are gone on purpose, and a delivered-everything run must not
	# read as "nothing left to deliver".
	var aboard: int = 0
	for entry: Dictionary in cargo.values():
		if not bool(entry.get("delivered", false)):
			aboard += 1
	if aboard > 0 and _count_ruined() >= aboard:
		finish_run(false, "Se arruinó toda la carga. No queda nada que entregar.")


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

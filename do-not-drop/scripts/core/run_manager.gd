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


func start_run(mode: StringName = MODE_DELIVERY) -> void:
	if is_running or not results.is_empty():
		return
	is_running = true
	current_mode = mode
	current_distance = 0.0
	EventBus.run_started.emit(&"test_route", [1])
	RouteEventManager.begin_random()


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


func _mark_photo(house_index: int) -> bool:
	for entry: Dictionary in deliveries:
		if int(entry["house"]) == house_index:
			if bool(entry["photo"]):
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
		var has_photo: bool = bool(entry["photo"])
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
	is_running = false
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
	var time_bonus: int = roundi(50.0 * clampf(1.0 - elapsed_seconds / PAR_SECONDS, 0.0, 1.0)) if successful else 0
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

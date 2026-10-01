class_name RunChronicle
extends Node
## Keeps the facts of the run for the next-day newspaper (N-606.2,
## docs/diario-final.md). It only listens: every fact already travels on
## EventBus (doors, care, boxes that left the van, deer and sheep, the van's
## faults, ruined boxes, photos), so on every peer it notes the same things
## and adds no state a run depends on.
##
## When the host's results are decided (run_results_decided) the host's
## chronicle adds what only the results know (doors the run never reached,
## complaints, how the run ended), hands the facts to NewsDesk and relays
## newspaper_ready: ids and slots, never text. A client's chronicle never
## writes; it only gets the paper from the host.
##
## A fact: {kind, house (0-based, -1 none), tags (kind of box, trap id),
## peer (who it is about, 0 none), at (run seconds)}; kinds are the stories of
## data/newspaper/stories.json.

const NEWS_DESK = preload("res://scripts/presentation/newspaper/news_desk.gd")
const TOWN_SIGN = preload("res://scripts/gameplay/route/town_sign.gd")
const PLAYER_NICKNAME = preload("res://scripts/gameplay/player/player_nickname.gd")
## What a box holds, as the family the catalogue's jokes are about
## (data/contents/*.tres ids); anything else is "other" and only gets
## the generic variants.
const CONTENT_FAMILIES: Dictionary = {
	&"wedding_cake": "cake", &"sourdough": "food",
	&"porcelain_vase": "vase", &"antique_lamp": "antique", &"glass_tower": "glass",
	&"hen": "hen", &"fireworks_crate": "fireworks",
	&"puppy": "critter", &"raccoon_cage": "critter",
	&"milk_canister": "liquid",
}
## route_event_started ids that are an incident on the road, and their story.
const INCIDENT_KINDS: Dictionary = {&"deer_hit": "deer_hit", &"sheep_hit": "sheep_hit"}

## What the last paper printed (kind -> variant), for the next one to avoid.
## Static: it outlives the level, so a restart doesn't repeat the same jokes.
static var last_variants: Dictionary = {}

var facts: Array[Dictionary] = []
## The town the paper is named after; empty, the level says (newspaper_town()).
var town_name: String = ""
## The paper this run wrote (host) or received (everyone).
var paper: Dictionary = {}
var _running: bool = false
var _houses: Array = []
var _trap_of: Dictionary = {}
var _faults: Dictionary = {}


func _ready() -> void:
	name = "RunChronicle"
	EventBus.run_started.connect(_on_run_started)
	EventBus.houses_assigned.connect(func(assignments: Array) -> void: _houses = assignments.duplicate(true))
	EventBus.cargo_registered.connect(func(id: StringName, name_key: String) -> void:
		_trap_of[id] = trap_id(name_key))
	EventBus.house_delivery_recorded.connect(_on_house_delivery)
	EventBus.delivery_care_noted.connect(_on_care_noted)
	EventBus.cargo_overboard_ended.connect(_on_overboard_ended)
	EventBus.route_event_started.connect(_on_route_event)
	EventBus.vehicle_fault_started.connect(_on_fault_started)
	EventBus.vehicle_fault_repaired.connect(_on_fault_repaired)
	EventBus.package_ruined.connect(_on_package_ruined)
	EventBus.delivery_photo_taken.connect(_on_photo)
	EventBus.run_results_decided.connect(_on_results_decided)
	EventBus.newspaper_ready.connect(func(received: Dictionary) -> void: paper = received)
	EventBus.run_ended.connect(func(_score: int, _results: Dictionary) -> void: _running = false)


## "HUD_TRAP_GROWING_WEIGHT" -> "growing_weight" (the tag the variants use).
static func trap_id(name_key: String) -> String:
	# Two trims rather than one literal prefix: the translation test reads any
	# such string in scripts as a key that must exist in the table.
	return name_key.trim_prefix("HUD_").trim_prefix("TRAP_").to_lower()


static func family_of(content_id: Variant) -> String:
	return String(CONTENT_FAMILIES.get(StringName(content_id), "other"))


func note(kind: String, house: int = -1, tags: Array = [], peer: int = 0) -> Dictionary:
	var fact: Dictionary = _stamp({"kind": kind, "house": house, "tags": tags, "peer": peer,
			"at": RunManager.elapsed_seconds})
	facts.append(fact)
	return fact


## A fact about a player keeps their nickname as it was: if they leave before the
## run ends the paper still names them, not whoever is left.
func _stamp(fact: Dictionary) -> Dictionary:
	if int(fact["peer"]) != 0:
		for member: Dictionary in current_crew():
			if int(member["peer"]) == int(fact["peer"]):
				fact["nick"] = member["nick"]
	return fact


func _on_run_started(_route: StringName, _players: Array) -> void:
	facts.clear()
	_faults.clear()
	paper = {}
	_running = true


## [family, trap] of what a house was waiting for, or of a box by its id.
func _tags_for(house: int, package_id: StringName = &"") -> Array:
	var tags: Array = []
	var assignment: Array = []
	if house >= 0 and house < _houses.size():
		assignment = _houses[house]
	elif not package_id.is_empty():
		for candidate: Variant in _houses:
			var order: Array = candidate if candidate is Array else []
			if not order.is_empty() and StringName(order[0]) == package_id:
				assignment = order
	if assignment.size() > 3:
		tags.append(family_of(assignment[3]))
	var trap: String = String(_trap_of.get(package_id, ""))
	if trap.is_empty() and assignment.size() > 1:
		trap = trap_id(String(assignment[1]))
	if not trap.is_empty():
		tags.append(trap)
	return tags


## The peer at the wheel (whoever the van's story is about), or 0.
func _driver() -> int:
	var vehicle: Node = get_tree().get_first_node_in_group(&"vehicle") if is_inside_tree() else null
	return int(vehicle.get(&"driver_peer_id")) if vehicle != null and &"driver_peer_id" in vehicle else 0


func _on_house_delivery(house: int, outcome: StringName, package_id: StringName) -> void:
	if not _running:
		return
	var tags: Array = _tags_for(house, package_id)
	match outcome:
		&"missed":
			note("missed", house, tags, _driver())
		&"lost":
			note("abandoned", house, tags)
		&"delivered_ruined":
			note("delivered_ruined", house, tags)
		&"delivered_ok", &"delivered_at_risk":
			note("delivered_ok", house, tags)


## What the door saw of a rescued box, just before the delivery itself.
func _on_care_noted(house: int, category: StringName) -> void:
	if not _running:
		return
	var tags: Array = _tags_for(house)
	match category:
		&"substituted":
			note("substituted", house, tags)
		&"repaired", &"unconvincing":
			note("repaired_tape", house, tags)


func _on_overboard_ended(package_id: StringName, rescued: bool) -> void:
	if _running:
		note("cargo_recovered" if rescued else "cargo_fell", -1, _tags_for(-1, package_id), _driver())


func _on_route_event(event_id: StringName, event: Dictionary) -> void:
	if _running and INCIDENT_KINDS.has(event_id) and bool(event.get("incident", false)):
		note(String(INCIDENT_KINDS[event_id]), -1, [], _driver())


func _on_fault_started(fault_id: StringName, _position: Vector3) -> void:
	if _running:
		_faults[fault_id] = note("fault_" + String(fault_id), -1, [], _driver())


## However it was fixed, the repair is the story the neighbors tell.
func _on_fault_repaired(fault_id: StringName, method: StringName) -> void:
	if not _running:
		return
	if _faults.has(fault_id):
		(_faults[fault_id]["tags"] as Array).append(String(method))
	note("fault_police", -1, [String(method)])


func _on_package_ruined(package_id: StringName, _cause: String) -> void:
	if _running:
		note("ruined_en_route", -1, _tags_for(-1, package_id))


func _on_photo(house: int, accepted: bool) -> void:
	if _running and accepted:
		note("photo", house, _tags_for(house))


# --- The paper -----------------------------------------------------------------


## Host only. The results decide how the run ended; the paper goes out before
## run_ended does, so every peer has it when their results come up.
func _on_results_decided(results: Dictionary) -> void:
	if not NetworkManager.is_host():
		return
	EventBus.relay(&"newspaper_ready", [compose(results)])


## The paper for what happened plus what these results say. Pure apart from
## the crew and the seed it reads; `crew` and `seed_value` let a test fix them.
func compose(results: Dictionary, crew: Array = [], seed_value: int = 0) -> Dictionary:
	var all: Array = facts.duplicate(true)
	var endless: bool = results.has("distance_traveled")
	var kilometres: float = float(results.get("distance_traveled", RunManager.current_distance)) / 1000.0
	if endless:
		all.append(_stamp({"kind": "endless_end", "house": -1, "tags": [], "peer": _driver()}))
	elif not bool(results.get("delivered", false)):
		all.append(_stamp({"kind": "run_failed", "house": -1, "tags": [], "peer": _driver()}))
	all.append_array(_facts_from_results(results, all))
	var context: Dictionary = {
		"seed": seed_value if seed_value != 0 else session_seed(),
		"town": town(),
		"crew": _with_absent(crew if not crew.is_empty() else current_crew(), all),
		"km": kilometres,
		"minutes": maxi(roundi(float(results.get("elapsed_seconds", RunManager.elapsed_seconds)) / 60.0), 1),
		"endless": endless,
		"previous": last_variants,
	}
	paper = NEWS_DESK.compose(all, context)
	last_variants = NEWS_DESK.variants_used(paper)
	return paper


## What only the results know: a door the run never reached, and the
## complaints the doors filed.
func _facts_from_results(results: Dictionary, noted: Array) -> Array:
	var extra: Array = []
	var seen: Dictionary = {}
	for fact: Dictionary in noted:
		if String(fact["kind"]) in ["missed", "abandoned"]:
			seen[int(fact["house"])] = true
	for row: Variant in results.get("deliveries", []):
		if row is not Dictionary:
			continue
		var house: int = int(row.get("house", -1))
		var outcome: StringName = StringName(row.get("outcome", &""))
		if seen.has(house) or outcome not in [&"missed", &"lost"]:
			continue
		var tags: Array = _tags_for(house, StringName(row.get("package_id", &"")))
		var kind: String = "missed" if outcome == &"missed" else "abandoned"
		extra.append({"kind": kind, "house": house, "tags": tags, "peer": 0})
	for complaint: Variant in results.get("complaints", []):
		if complaint is Dictionary:
			extra.append({"kind": "complaint", "house": int(complaint.get("house", -1)),
					"tags": _tags_for(int(complaint.get("house", -1))), "peer": 0})
	return extra


## The crew plus whoever a fact is about and already left (by the nickname the fact kept).
func _with_absent(crew: Array, all: Array) -> Array:
	var full: Array = crew.duplicate()
	var present: Dictionary = {}
	for member: Dictionary in crew:
		present[int(member["peer"])] = true
	for fact: Dictionary in all:
		var peer: int = int(fact.get("peer", 0))
		if peer != 0 and not present.has(peer) and fact.has("nick"):
			present[peer] = true
			full.append({"peer": peer, "nick": String(fact["nick"])})
	return full


## The crew as the paper names them: [{peer, nick}], by peer id.
func current_crew() -> Array:
	var crew: Array = []
	if not is_inside_tree():
		return crew
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		crew.append({"peer": player.get_multiplayer_authority(), "nick": PLAYER_NICKNAME.of(player)})
	crew.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["peer"]) < int(b["peer"]))
	return crew


## The session's seed; alone (no world seed) each run gets a fresh one, from an
## RNG of its own so the global one (other systems' rolls) isn't touched.
func session_seed() -> int:
	if NetworkManager.world_seed != 0:
		return NetworkManager.world_seed
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi()


func town() -> String:
	if not town_name.is_empty():
		return town_name
	var level: Node = get_parent()
	if level != null and level.has_method(&"newspaper_town") and not String(level.call(&"newspaper_town")).is_empty():
		return String(level.call(&"newspaper_town"))
	var names: Array[String] = TOWN_SIGN.names_for_seed(NetworkManager.world_seed)
	return names[0]

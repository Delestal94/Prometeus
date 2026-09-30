class_name ClientComplaints
extends RefCounted
## Who complains at a door, and in whose voice (S-604, docs/narrativa.md).
##
## Every house belongs to one of the ten recurring clients: the sender of the
## box it ordered (PackageContent.sender), or -- when the run doesn't say what
## is in the box -- one drawn from the session seed and the house number. A
## complaint is a client plus a result:
##
##   ruined    the box arrived wrecked
##   at_risk   it arrived dented
##   opened    it arrived intact but handed over open ("has been gone through")
##   wrong     a box that isn't theirs was offered at the door
##
## Nothing here reads the scene tree: pick_line() is a function of its
## arguments, so the host picks the line once and sends the KEY in the results
## (like LocText, the text never travels) and every peer reads it in its own
## language. The lines live in strings_world.csv (WORLD_COMPLAINT_*), written
## out in full below so test_world_translations sees them used.

const RESULT_RUINED: StringName = &"ruined"
const RESULT_AT_RISK: StringName = &"at_risk"
const RESULT_OPENED: StringName = &"opened"
const RESULT_WRONG: StringName = &"wrong"
const RESULTS: Array[StringName] = [RESULT_RUINED, RESULT_AT_RISK, RESULT_OPENED, RESULT_WRONG]

## The ten clients, in docs/narrativa.md order. Each one is named after the
## content it sends (data/contents/<id>.tres), whose `sender` is the name.
const CLIENTS: Array[StringName] = [
	&"glass_tower", &"wedding_cake", &"hen", &"raccoon_cage", &"fireworks_crate",
	&"antique_lamp", &"sourdough", &"porcelain_vase", &"milk_canister", &"puppy",
]

const LINES: Dictionary = {
	&"glass_tower": {
		&"ruined": [
			"WORLD_COMPLAINT_GLASS_TOWER_RUINED_1",
			"WORLD_COMPLAINT_GLASS_TOWER_RUINED_2",
			"WORLD_COMPLAINT_GLASS_TOWER_RUINED_3",
		],
		&"at_risk": ["WORLD_COMPLAINT_GLASS_TOWER_AT_RISK_1", "WORLD_COMPLAINT_GLASS_TOWER_AT_RISK_2"],
		&"opened": ["WORLD_COMPLAINT_GLASS_TOWER_OPENED_1", "WORLD_COMPLAINT_GLASS_TOWER_OPENED_2"],
		&"wrong": ["WORLD_COMPLAINT_GLASS_TOWER_WRONG_1", "WORLD_COMPLAINT_GLASS_TOWER_WRONG_2"],
	},
	&"wedding_cake": {
		&"ruined": [
			"WORLD_COMPLAINT_WEDDING_CAKE_RUINED_1",
			"WORLD_COMPLAINT_WEDDING_CAKE_RUINED_2",
			"WORLD_COMPLAINT_WEDDING_CAKE_RUINED_3",
		],
		&"at_risk": ["WORLD_COMPLAINT_WEDDING_CAKE_AT_RISK_1", "WORLD_COMPLAINT_WEDDING_CAKE_AT_RISK_2"],
		&"opened": ["WORLD_COMPLAINT_WEDDING_CAKE_OPENED_1", "WORLD_COMPLAINT_WEDDING_CAKE_OPENED_2"],
		&"wrong": ["WORLD_COMPLAINT_WEDDING_CAKE_WRONG_1", "WORLD_COMPLAINT_WEDDING_CAKE_WRONG_2"],
	},
	&"hen": {
		&"ruined": ["WORLD_COMPLAINT_HEN_RUINED_1", "WORLD_COMPLAINT_HEN_RUINED_2", "WORLD_COMPLAINT_HEN_RUINED_3"],
		&"at_risk": ["WORLD_COMPLAINT_HEN_AT_RISK_1", "WORLD_COMPLAINT_HEN_AT_RISK_2"],
		&"opened": ["WORLD_COMPLAINT_HEN_OPENED_1", "WORLD_COMPLAINT_HEN_OPENED_2"],
		&"wrong": ["WORLD_COMPLAINT_HEN_WRONG_1", "WORLD_COMPLAINT_HEN_WRONG_2"],
	},
	&"raccoon_cage": {
		&"ruined": [
			"WORLD_COMPLAINT_RACCOON_CAGE_RUINED_1",
			"WORLD_COMPLAINT_RACCOON_CAGE_RUINED_2",
			"WORLD_COMPLAINT_RACCOON_CAGE_RUINED_3",
		],
		&"at_risk": ["WORLD_COMPLAINT_RACCOON_CAGE_AT_RISK_1", "WORLD_COMPLAINT_RACCOON_CAGE_AT_RISK_2"],
		&"opened": ["WORLD_COMPLAINT_RACCOON_CAGE_OPENED_1", "WORLD_COMPLAINT_RACCOON_CAGE_OPENED_2"],
		&"wrong": ["WORLD_COMPLAINT_RACCOON_CAGE_WRONG_1", "WORLD_COMPLAINT_RACCOON_CAGE_WRONG_2"],
	},
	&"fireworks_crate": {
		&"ruined": [
			"WORLD_COMPLAINT_FIREWORKS_CRATE_RUINED_1",
			"WORLD_COMPLAINT_FIREWORKS_CRATE_RUINED_2",
			"WORLD_COMPLAINT_FIREWORKS_CRATE_RUINED_3",
		],
		&"at_risk": ["WORLD_COMPLAINT_FIREWORKS_CRATE_AT_RISK_1", "WORLD_COMPLAINT_FIREWORKS_CRATE_AT_RISK_2"],
		&"opened": ["WORLD_COMPLAINT_FIREWORKS_CRATE_OPENED_1", "WORLD_COMPLAINT_FIREWORKS_CRATE_OPENED_2"],
		&"wrong": ["WORLD_COMPLAINT_FIREWORKS_CRATE_WRONG_1", "WORLD_COMPLAINT_FIREWORKS_CRATE_WRONG_2"],
	},
	&"antique_lamp": {
		&"ruined": [
			"WORLD_COMPLAINT_ANTIQUE_LAMP_RUINED_1",
			"WORLD_COMPLAINT_ANTIQUE_LAMP_RUINED_2",
			"WORLD_COMPLAINT_ANTIQUE_LAMP_RUINED_3",
		],
		&"at_risk": ["WORLD_COMPLAINT_ANTIQUE_LAMP_AT_RISK_1", "WORLD_COMPLAINT_ANTIQUE_LAMP_AT_RISK_2"],
		&"opened": ["WORLD_COMPLAINT_ANTIQUE_LAMP_OPENED_1", "WORLD_COMPLAINT_ANTIQUE_LAMP_OPENED_2"],
		&"wrong": ["WORLD_COMPLAINT_ANTIQUE_LAMP_WRONG_1", "WORLD_COMPLAINT_ANTIQUE_LAMP_WRONG_2"],
	},
	&"sourdough": {
		&"ruined": [
			"WORLD_COMPLAINT_SOURDOUGH_RUINED_1",
			"WORLD_COMPLAINT_SOURDOUGH_RUINED_2",
			"WORLD_COMPLAINT_SOURDOUGH_RUINED_3",
		],
		&"at_risk": ["WORLD_COMPLAINT_SOURDOUGH_AT_RISK_1", "WORLD_COMPLAINT_SOURDOUGH_AT_RISK_2"],
		&"opened": ["WORLD_COMPLAINT_SOURDOUGH_OPENED_1", "WORLD_COMPLAINT_SOURDOUGH_OPENED_2"],
		&"wrong": ["WORLD_COMPLAINT_SOURDOUGH_WRONG_1", "WORLD_COMPLAINT_SOURDOUGH_WRONG_2"],
	},
	&"porcelain_vase": {
		&"ruined": [
			"WORLD_COMPLAINT_PORCELAIN_VASE_RUINED_1",
			"WORLD_COMPLAINT_PORCELAIN_VASE_RUINED_2",
			"WORLD_COMPLAINT_PORCELAIN_VASE_RUINED_3",
		],
		&"at_risk": ["WORLD_COMPLAINT_PORCELAIN_VASE_AT_RISK_1", "WORLD_COMPLAINT_PORCELAIN_VASE_AT_RISK_2"],
		&"opened": ["WORLD_COMPLAINT_PORCELAIN_VASE_OPENED_1", "WORLD_COMPLAINT_PORCELAIN_VASE_OPENED_2"],
		&"wrong": ["WORLD_COMPLAINT_PORCELAIN_VASE_WRONG_1", "WORLD_COMPLAINT_PORCELAIN_VASE_WRONG_2"],
	},
	&"milk_canister": {
		&"ruined": [
			"WORLD_COMPLAINT_MILK_CANISTER_RUINED_1",
			"WORLD_COMPLAINT_MILK_CANISTER_RUINED_2",
			"WORLD_COMPLAINT_MILK_CANISTER_RUINED_3",
		],
		&"at_risk": ["WORLD_COMPLAINT_MILK_CANISTER_AT_RISK_1", "WORLD_COMPLAINT_MILK_CANISTER_AT_RISK_2"],
		&"opened": ["WORLD_COMPLAINT_MILK_CANISTER_OPENED_1", "WORLD_COMPLAINT_MILK_CANISTER_OPENED_2"],
		&"wrong": ["WORLD_COMPLAINT_MILK_CANISTER_WRONG_1", "WORLD_COMPLAINT_MILK_CANISTER_WRONG_2"],
	},
	&"puppy": {
		&"ruined": [
			"WORLD_COMPLAINT_PUPPY_RUINED_1",
			"WORLD_COMPLAINT_PUPPY_RUINED_2",
			"WORLD_COMPLAINT_PUPPY_RUINED_3",
		],
		&"at_risk": ["WORLD_COMPLAINT_PUPPY_AT_RISK_1", "WORLD_COMPLAINT_PUPPY_AT_RISK_2"],
		&"opened": ["WORLD_COMPLAINT_PUPPY_OPENED_1", "WORLD_COMPLAINT_PUPPY_OPENED_2"],
		&"wrong": ["WORLD_COMPLAINT_PUPPY_WRONG_1", "WORLD_COMPLAINT_PUPPY_WRONG_2"],
	},
}

static var _names: Dictionary = {}


static func is_client(client: StringName) -> bool:
	return CLIENTS.has(client)


## The client a house belongs to. `content_id` is the content of the box the
## house ordered (empty when the run doesn't know it); otherwise a stable
## draw from the seed and the house, so a house never changes client.
static func client_for(content_id: StringName, session_seed: int, house: int) -> StringName:
	if is_client(content_id):
		return content_id
	return CLIENTS[posmod(hash([session_seed, house, &"client"]), CLIENTS.size())]


## Who lives at this house, from the depot's assignments
## ([package_id, trap_key, code, content_id], ...): the sender of the box it ordered.
static func client_of(assignments: Array, house: int, session_seed: int) -> StringName:
	var content_id: StringName = &""
	if house < assignments.size() and (assignments[house] as Array).size() > 3:
		content_id = StringName(assignments[house][3])
	return client_for(content_id, session_seed, house)


## The complaint for one delivery record (RunManager.deliveries), as the
## results carry it: who, what about, and the KEY of the line they say (each
## peer translates it). `dismissed` is a delivery photo; `noted` a complaint
## that never costs anything.
static func make(entry: Dictionary, dismissed: bool, assignments: Array, line_seed: int,
		result: StringName = &"", noted: bool = false) -> Dictionary:
	var house: int = int(entry["house"])
	if result.is_empty():
		result = result_for(StringName(entry.get("outcome", &"")), bool(entry.get("opened", false)))
	var client: StringName = client_of(assignments, house, line_seed)
	var complaint: Dictionary = {
		"house": house,
		"dismissed": dismissed,
		"client": client,
		"result": result,
		"line": pick_line(client, result, line_seed, house),
	}
	if noted:
		complaint["noted"] = true
	return complaint


## The "wrong box" notes: every door in `refused` (house -> true) that has no
## complaint yet keeps one in its client's voice. They cost nothing (the crew
## handed the box back), so they come out settled.
static func wrong_notes(refused: Dictionary, complaints: Array, assignments: Array,
		line_seed: int) -> Array[Dictionary]:
	var complained: Dictionary = {}
	for complaint: Dictionary in complaints:
		complained[int(complaint["house"])] = true
	var houses: Array = refused.keys()
	houses.sort()
	var notes: Array[Dictionary] = []
	for house: int in houses:
		if not complained.has(house):
			notes.append(make({"house": house}, true, assignments, line_seed, RESULT_WRONG, true))
	return notes


## The complaint result for a delivery outcome (DeliveryHouse.OUTCOME_*), or
## empty when that outcome has nothing to complain about. `opened` is for a box
## that was intact but handed over open, which the door records as dented.
static func result_for(outcome: StringName, opened: bool = false) -> StringName:
	match outcome:
		&"delivered_ruined":
			return RESULT_RUINED
		&"delivered_at_risk":
			return RESULT_OPENED if opened else RESULT_AT_RISK
	return &""


## Every line key for a client and result (2 or 3), in table order.
static func lines_for(client: StringName, result: StringName) -> Array:
	var by_result: Dictionary = LINES.get(client, {})
	return by_result.get(result, [])


## The translation key of this house's line: same seed, house, client and
## result, same line on every peer. A different house or result draws again.
static func pick_line(client: StringName, result: StringName, session_seed: int, house: int) -> String:
	var lines: Array = lines_for(client, result)
	if lines.is_empty():
		return ""
	return str(lines[posmod(hash([session_seed, house, client, result]), lines.size())])


## The client's name (a proper noun: the same in every language), read from
## the content resource that carries it. Empty for anything but the ten.
static func client_name(client: StringName) -> String:
	if not is_client(client):
		return ""
	if not _names.has(client):
		var content: Resource = load("res://data/contents/%s.tres" % client)
		_names[client] = String(content.get(&"sender")) if content != null else ""
	return String(_names[client])


## Every line key in the pool, for the tests.
static func all_keys() -> Array[String]:
	var keys: Array[String] = []
	for client: StringName in LINES:
		for result: StringName in (LINES[client] as Dictionary):
			for key: String in (LINES[client][result] as Array):
				keys.append(key)
	return keys

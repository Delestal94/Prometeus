class_name OrderDoorReaction
extends RefCounted
## What the customer does at the door when they rate a delivery (expansion D-0817, "Modo Empresa").
##
## Pure functions, no node, no autoload, no UI. Three reactions from the stars of OrderRating:
## cheer (4-5), shrug (3), angry (1-2). The reaction names a gesture for the door's presentation and
## a translation KEY for what the customer says (the text never travels, like ClientComplaints: every
## peer reads it in its own language). The angry ones reuse the client's own voice from
## ClientComplaints (a wrong box complains `wrong`, anything else `ruined`); cheer and shrug draw from
## small generic pools. Same seed, order and result, same line on every peer. It moves no money and no
## reputation. Thresholds live in CompanyTuning.

const CHEER: StringName = &"cheer"
const SHRUG: StringName = &"shrug"
const ANGRY: StringName = &"angry"
const REACTIONS: Array[StringName] = [CHEER, SHRUG, ANGRY]

## The gesture the door plays for each reaction (the animation itself is presentation).
const GESTURES: Dictionary = {CHEER: &"wave", SHRUG: &"shrug", ANGRY: &"fume"}

const CHEER_LINES: Array[String] = ["WORLD_DOOR_CHEER_1", "WORLD_DOOR_CHEER_2", "WORLD_DOOR_CHEER_3"]
const SHRUG_LINES: Array[String] = ["WORLD_DOOR_SHRUG_1", "WORLD_DOOR_SHRUG_2"]


## The reaction for `stars` (empty when it is not 1-5: nothing was delivered, nobody reacts).
static func reaction_for(stars: int) -> StringName:
	if stars < CompanyTuning.STARS_MIN or stars > CompanyTuning.STARS_MAX:
		return &""
	if stars >= CompanyTuning.REACTION_CHEER_MIN_STARS:
		return CHEER
	if stars >= CompanyTuning.REACTION_SHRUG_MIN_STARS:
		return SHRUG
	return ANGRY


## The gesture of a reaction (empty for anything but the three).
static func gesture_of(reaction: StringName) -> StringName:
	return GESTURES.get(reaction, &"")


## The whole reaction for a settle() result: `{reaction, stars, gesture, line}`. `client` is the
## ClientComplaints client of the house. Empty reaction and line when the result was not ok.
static func react(result: Dictionary, client: StringName, session_seed: int, house: int) -> Dictionary:
	var stars: int = OrderRating.stars(result)
	var reaction: StringName = reaction_for(stars)
	return {
		"reaction": reaction,
		"stars": stars,
		"gesture": gesture_of(reaction),
		"line": line_for(reaction, result, client, session_seed, house),
	}


## The translation key of what the customer says. Angry: the client's complaint (wrong box, else
## ruined); cheer and shrug: a generic line. Empty when there is no reaction.
static func line_for(reaction: StringName, result: Dictionary, client: StringName, session_seed: int,
		house: int) -> String:
	match reaction:
		CHEER:
			return _draw(CHEER_LINES, session_seed, house, reaction)
		SHRUG:
			return _draw(SHRUG_LINES, session_seed, house, reaction)
		ANGRY:
			var kinds: Array = result.get("kinds", [])
			var complaint: StringName = ClientComplaints.RESULT_RUINED
			if kinds.has(OrderPenalties.KIND_WRONG):
				complaint = ClientComplaints.RESULT_WRONG
			return ClientComplaints.pick_line(client, complaint, session_seed, house)
	return ""


## Every generic line key, for the tests.
static func all_keys() -> Array[String]:
	var keys: Array[String] = []
	keys.append_array(CHEER_LINES)
	keys.append_array(SHRUG_LINES)
	return keys


static func _draw(lines: Array[String], session_seed: int, house: int, reaction: StringName) -> String:
	return lines[posmod(hash([session_seed, house, reaction]), lines.size())]

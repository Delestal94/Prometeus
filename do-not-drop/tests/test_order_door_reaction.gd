extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_door_reaction.gd
##
## The customer's reaction at the door (expansion D-0817, order_door_reaction.gd):
## - 4-5 stars cheer, 3 shrugs, 1-2 are angry; 0 or out of range, no reaction and no line;
## - each reaction has its own gesture;
## - angry lines come from the client's voice in ClientComplaints (wrong box -> `wrong`, else `ruined`);
## - cheer and shrug draw a generic line: same seed and house, same line; every key exists in both
##   languages;
## - react() on settle()-shaped results gives the three reactions end to end, and does not change
##   the result passed in.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_thresholds()
	_test_gestures()
	_test_angry_lines()
	_test_generic_lines()
	_test_react()
	_test_translations()
	if _failures == 0:
		print("PASS: the customer reacts at the door from the stars")
	quit(_failures)


func _result(kinds: Array, tip: int = 0, ok: bool = true) -> Dictionary:
	var typed: Array[StringName] = []
	for kind: Variant in kinds:
		typed.append(StringName(kind))
	return {"ok": ok, "paid": 200, "tip": tip, "reputation": 0.0, "kinds": typed, "lost": 0}


func _test_thresholds() -> void:
	var expected: Dictionary = {
		1: OrderDoorReaction.ANGRY, 2: OrderDoorReaction.ANGRY, 3: OrderDoorReaction.SHRUG,
		4: OrderDoorReaction.CHEER, 5: OrderDoorReaction.CHEER,
	}
	for stars: int in expected:
		_expect(OrderDoorReaction.reaction_for(stars) == expected[stars], "%d stars -> %s" % [stars, expected[stars]])
	for bad: int in [-1, 0, 6, 99]:
		_expect(OrderDoorReaction.reaction_for(bad) == &"", "%d stars: nobody reacts" % bad)


func _test_gestures() -> void:
	var gestures: Dictionary = {}
	for reaction: StringName in OrderDoorReaction.REACTIONS:
		var gesture: StringName = OrderDoorReaction.gesture_of(reaction)
		_expect(gesture != &"", "%s has a gesture" % reaction)
		gestures[gesture] = true
	_expect(gestures.size() == 3, "the three gestures differ")
	_expect(OrderDoorReaction.gesture_of(&"") == &"", "no gesture without a reaction")


func _test_angry_lines() -> void:
	for client: StringName in ClientComplaints.CLIENTS:
		var wrong: Dictionary = OrderDoorReaction.react(_result([&"wrong"]), client, 7, 3)
		_expect(wrong["reaction"] == OrderDoorReaction.ANGRY, "wrong box is angry")
		_expect(ClientComplaints.lines_for(client, ClientComplaints.RESULT_WRONG).has(wrong["line"]),
			"%s: a wrong box complains with a wrong-box line" % client)
		var broken: Dictionary = OrderDoorReaction.react(_result([&"broken"]), client, 7, 3)
		_expect(ClientComplaints.lines_for(client, ClientComplaints.RESULT_RUINED).has(broken["line"]),
			"%s: a broken product complains with a ruined line" % client)
		var both: Dictionary = OrderDoorReaction.react(_result([&"broken", &"wrong"]), client, 7, 3)
		_expect(ClientComplaints.lines_for(client, ClientComplaints.RESULT_WRONG).has(both["line"]),
			"%s: wrong box wins over broken" % client)


func _test_generic_lines() -> void:
	var cheer: String = OrderDoorReaction.line_for(&"cheer", _result([], 30), &"hen", 5, 2)
	_expect(OrderDoorReaction.CHEER_LINES.has(cheer), "cheer draws from the cheer pool")
	var again: String = OrderDoorReaction.line_for(&"cheer", _result([], 30), &"hen", 5, 2)
	_expect(again == cheer, "same seed and house, same line")
	var seen: Dictionary = {}
	for house in range(60):
		seen[OrderDoorReaction.line_for(&"cheer", _result([], 30), &"hen", 5, house)] = true
	_expect(seen.size() == OrderDoorReaction.CHEER_LINES.size(), "every cheer line gets drawn across houses")
	var shrug: String = OrderDoorReaction.line_for(&"shrug", _result([&"late"]), &"hen", 5, 2)
	_expect(OrderDoorReaction.SHRUG_LINES.has(shrug), "shrug draws from the shrug pool")
	_expect(OrderDoorReaction.line_for(&"", _result([]), &"hen", 5, 2) == "", "no reaction, no line")


func _test_react() -> void:
	var quick: Dictionary = _result([], 30)
	var before: Dictionary = quick.duplicate(true)
	var cheer: Dictionary = OrderDoorReaction.react(quick, &"puppy", 11, 4)
	_expect(cheer["reaction"] == OrderDoorReaction.CHEER and cheer["stars"] == 5, "quick and clean cheers at 5 stars")
	_expect(cheer["gesture"] == &"wave" and not String(cheer["line"]).is_empty(), "cheer waves and speaks")
	_expect(quick == before, "react() leaves the result as it was")
	var slow: Dictionary = OrderDoorReaction.react(_result([]), &"puppy", 11, 4)
	_expect(slow["reaction"] == OrderDoorReaction.CHEER and slow["stars"] == 4, "clean but slow still cheers at 4")
	var late: Dictionary = OrderDoorReaction.react(_result([&"late"]), &"puppy", 11, 4)
	_expect(late["reaction"] == OrderDoorReaction.SHRUG and late["gesture"] == &"shrug", "late shrugs")
	var none: Dictionary = OrderDoorReaction.react(_result([], 0, false), &"puppy", 11, 4)
	_expect(none["reaction"] == &"" and none["line"] == "" and none["stars"] == 0,
		"a delivery that did not happen: no reaction")


func _test_translations() -> void:
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in OrderDoorReaction.all_keys():
			var text: String = TranslationServer.translate(key)
			_expect(not text.is_empty() and text != key, "%s: %s is translated" % [locale, key])
	TranslationServer.set_locale("es")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_trip_scoring.gd
##
## Score of a closed trip from the delivery run's scoring (expansion D-0520, trip_scoring.gd with
## trip_result.gd). A trip of four orders: one intact box, one dented (packing quality under 90), one
## broken and one that never arrives.
## - each line is worth what RunScoring pays at a door (150 / 75 / 20) and a missed house costs 60,
##   the same numbers (and the same sum) RunScoring.resolve_deliveries gives for the same doors;
## - the score is the sum put together by RunScoring.settle(): never below 0, no chaos multiplier;
## - the breakdown lines add up to the points and use the results screen's HUD_SCORE_* labels;
## - merit goes to the carrier of an intact box (TRIP_MERIT_INTACT) and half of it to a dented one;
##   a broken or undelivered box earns none, and applying twice pays once;
## - the score is not money: applying a trip leaves CrewProgression.team_money as it was, and the
##   pay of the trip is the one OrderSettlement already paid;
## - add_to_day() sums the score of the day's trips.

var _failures: int = 0
var _hen: Resource = load("res://data/products/hen.tres")
var _run_scoring: Script = load("res://scripts/core/run_scoring.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var crew: Node = root.get_node_or_null(^"CrewProgression")
	if crew == null or crew.get_script() == null:
		push_error("CrewProgression autoload missing")
		quit(1)
		return
	crew.reset_campaign(false)
	_test_lines()
	_test_mixed_trip(crew)
	_test_floor_at_zero()
	_test_same_as_a_delivery_run()
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _line(outcome: StringName, box: StringName) -> Dictionary:
	return {"outcome": outcome, "box": box}


func _closed_trip(book: OrderBook, deliver: Dictionary) -> Trip:
	var products: Dictionary = {&"hen": _hen}
	var ids: Array[StringName] = []
	var boxes: Array[StringName] = []
	for i in 4:
		var id := StringName("o%d" % (i + 1))
		var items: Array = [{"product": &"hen", "qty": 2}]
		book.add(Order.make(id, "Ana", &"centro", StringName("h%d" % (i + 1)), items, 0, products))
		book.mark_packed(id, StringName("b%d" % (i + 1)))
		ids.append(id)
		boxes.append(StringName("b%d" % (i + 1)))
	var trip: Trip = Trip.start(&"t1", &"van", ids, boxes, book, 60)
	for id: StringName in deliver:
		var how: Dictionary = deliver[id]
		trip.deliver(id, book, int(how["quality"]), bool(how["intact"]), 100)
	trip.close(book, 150)
	return trip


func _test_lines() -> void:
	var delivered: StringName = TripResult.OUTCOME_DELIVERED
	var failed: StringName = TripResult.OUTCOME_FAILED
	var intact_line: Dictionary = _line(delivered, TripResult.BOX_INTACT)
	_expect(TripScoring.line_points(intact_line) == _run_scoring.POINTS_DELIVERED_INTACT,
		"an intact box is worth a door of an intact one")
	var dented: Dictionary = _line(delivered, TripResult.BOX_AT_RISK)
	_expect(TripScoring.line_points(dented) == _run_scoring.POINTS_DELIVERED_AT_RISK, "a dented box is a dented door")
	var broken: Dictionary = _line(delivered, TripResult.BOX_BROKEN)
	_expect(TripScoring.line_points(broken) == _run_scoring.POINTS_DELIVERED_RUINED, "a broken box is a ruined door")
	var missed: Dictionary = _line(failed, TripResult.BOX_UNDELIVERED)
	_expect(TripScoring.line_points(missed) == -_run_scoring.PENALTY_MISSED_HOUSE, "a lost order costs a missed house")
	_expect(TripScoring.merit_for(_line(delivered, TripResult.BOX_INTACT)) == CompanyTuning.TRIP_MERIT_INTACT,
		"intact box: the whole merit")
	_expect(TripScoring.merit_for(_line(delivered, TripResult.BOX_AT_RISK)) == CompanyTuning.TRIP_MERIT_INTACT / 2,
		"dented box: half the merit (75 points of 150)")
	_expect(TripScoring.merit_for(_line(delivered, TripResult.BOX_BROKEN)) == 0, "a broken box earns no merit")
	_expect(TripScoring.merit_for(_line(failed, TripResult.BOX_UNDELIVERED)) == 0, "an undelivered box earns none")
	_expect(TripScoring.merit_for({}) == 0 and TripScoring.line_points({}) < 0, "an empty line is a missed house")


func _test_mixed_trip(crew: Node) -> void:
	var book := OrderBook.new()
	var trip: Trip = _closed_trip(book, {
		&"o1": {"quality": 100, "intact": true},
		&"o2": {"quality": 70, "intact": true},
		&"o3": {"quality": 100, "intact": false},
	})
	var carriers: Dictionary = {&"o1": 7, &"o2": 8, &"o3": 9, &"o4": 7}
	var result: Dictionary = TripResult.build(trip, book, {}, carriers)
	_expect(result["intact"] == 1 and result["at_risk"] == 1 and result["broken"] == 1 and result["failed"] == 1,
		"one box of each kind")
	_expect(result["score_points"] == 150 + 75 + 20 - 60, "150 + 75 + 20 - 60 (got %s)" % result["score_points"])
	_expect(result["score"] == 185, "the score is the sum (got %s)" % result["score"])
	var sum: int = 0
	var labels: Array = []
	for entry: Dictionary in result["score_breakdown"]:
		sum += int(entry["points"])
		labels.append(entry["label"])
	_expect(sum == result["score_points"], "the breakdown lines add up to the points (got %s)" % sum)
	_expect(labels == ["HUD_SCORE_PERFECT", "HUD_SCORE_DENTED", "HUD_SCORE_RUINED", "HUD_SCORE_MISSED"],
		"one line per kind, the results screen's labels (got %s)" % [labels])
	_expect(result["merit_by_peer"] == {7: 10, 8: 5}, "merit: peer 7 intact, peer 8 dented, peer 9 (broken) none")
	var pay_before: int = int(result["pay_total"])
	var money_before: int = int(crew.team_money)
	var merit_before: int = int(crew.merit.get(8, 0))
	_expect(TripResult.apply(result, crew) == 15, "apply awards 10 + 5")
	_expect(int(crew.merit.get(8, 0)) == merit_before + 5, "the dented box's carrier got 5")
	_expect(int(crew.merit.get(9, 0)) == 0, "the broken box's carrier got none")
	_expect(TripResult.apply(result, crew) == 0, "applying twice pays nothing")
	_expect(int(crew.team_money) == money_before, "the score is not money: team money did not move")
	_expect(int(result["pay_total"]) == pay_before, "the trip's pay is the one settled at the doors")
	var day: Dictionary = TripResult.add_to_day({"day": 1}, [result, result])
	_expect(day["trip_score"] == 370, "the day sums the score of its trips (got %s)" % day.get("trip_score"))


func _test_floor_at_zero() -> void:
	var book := OrderBook.new()
	var trip: Trip = _closed_trip(book, {})
	var result: Dictionary = TripResult.build(trip, book)
	_expect(result["failed"] == 4 and result["score_points"] == -240, "four missed houses: -240 points")
	_expect(result["score"] == 0, "the score never goes below 0 (got %s)" % result["score"])
	_expect(result["merit_by_peer"].is_empty(), "no merit when nothing arrived")
	_expect(TripScoring.score([])["score"] == 0, "no lines, score 0")
	_expect(TripResult.build(null, book)["score"] == 0, "a null trip scores 0")


## The same doors in a delivery run (RunScoring.resolve_deliveries) give the same points, so both modes
## price a house the same way.
func _test_same_as_a_delivery_run() -> void:
	var lines: Array = [_line(TripResult.OUTCOME_DELIVERED, TripResult.BOX_INTACT),
		_line(TripResult.OUTCOME_FAILED, TripResult.BOX_UNDELIVERED)]
	var entries: Array = [{"house": 0, "outcome": "delivered_ok", "photo": false, "package_id": "x"}]
	var doors: Dictionary = _run_scoring.resolve_deliveries(entries, [], {}, 2, [], 0)
	var ours: Dictionary = TripScoring.score(lines)
	_expect(ours["delivery_points"] == doors["delivery_points"],
		"same doors, same points (%s vs %s)" % [ours["delivery_points"], doors["delivery_points"]])
	_expect(ours["delivered"] == doors["houses_delivered"], "same houses delivered")

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_box_seals.gd
##
## Seals on a packed box (expansion D-0708, box_seals.gd and PackingStation.stamp):
## - an order asks for the seals of its requirements (fragile, cold... from data/order_requirements/),
##   without repeats; urgent asks for none; unknown requirement ids are ignored;
## - the door check is_valid() fails while a required seal is missing and missing() names it;
## - stamp() puts a known seal on the box on the table, once, charging STAMP_COST, and refuses
##   (changing nothing) with no box, an unknown kind or a repeat;
## - the seals survive a JSON round trip of the table.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_required()
	_test_stamp_and_door()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _test_required() -> void:
	_expect(BoxSeals.required({}).is_empty(), "no requirements, no seals")
	_expect(
		BoxSeals.required({"requirements": [&"urgent"]}).is_empty(), "urgent asks for no seal"
	)
	_expect(
		BoxSeals.required({"requirements": [&"fragile", &"cold"]}) == [&"fragile", &"cold"],
		"fragile and cold ask for their seals",
	)
	_expect(
		BoxSeals.required({"requirements": [&"gift", &"gift", &"nope"]}) == [&"gift"],
		"repeats and unknown ids are dropped",
	)
	for kind: StringName in BoxSeals.KINDS:
		_expect(BoxSeals.is_kind(kind), "%s is a seal kind" % kind)
	_expect(not BoxSeals.is_kind(&"urgent") and not BoxSeals.is_kind(&""), "urgent is no seal")


func _test_stamp_and_door() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		_expect(false, "CompanyState autoload missing")
		return
	state.new_company("Seal Co")
	var order: Dictionary = {"id": "o1", "requirements": [&"fragile", &"cold"]}
	var table: PackingStation = PackingStation.make(&"t1")
	_expect(not table.stamp(&"fragile", state), "no box: nothing to stamp")
	table.start_box(&"S")
	_expect(not BoxSeals.is_valid(table.box, order), "bare box fails the door")
	_expect(
		BoxSeals.missing(table.box, order) == [&"fragile", &"cold"], "both seals are missing"
	)
	_expect(not table.stamp(&"urgent", state), "unknown kind is refused")
	_expect(table.box.stamps.is_empty(), "a refusal changes nothing")
	var money: int = state.money
	_expect(table.stamp(&"fragile", state), "fragile seal sticks")
	_expect(state.money == money - CompanyTuning.STAMP_COST, "seal charged at its tuning price")
	_expect(not table.stamp(&"fragile", state), "same seal twice is refused")
	_expect(BoxSeals.missing(table.box, order) == [&"cold"], "only cold is missing now")
	_expect(not BoxSeals.is_valid(table.box, order), "still fails the door")
	_expect(table.stamp(&"cold", state), "cold seal sticks")
	_expect(BoxSeals.is_valid(table.box, order), "the door accepts the box")
	_expect(BoxSeals.is_valid(table.box, {"id": "o2"}), "an order with no requirements accepts any box")
	_expect(not BoxSeals.is_valid(null, order), "no box fails the door")
	var copy: PackingStation = PackingStation.from_dict(JSON.parse_string(JSON.stringify(table.to_dict())))
	_expect(BoxSeals.is_valid(copy.box, order), "the seals survive JSON")
	state.reset()

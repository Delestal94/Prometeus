extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_packing_tutorial.gd
##
## Guided first box at the packing table (expansion D-0720, packing_tutorial.gd):
## - the step follows the table: no box -> box; wrong content -> products; then (only if the order
##   asks for seals) seals, label, tape and dispatch; once dispatched, done;
## - an order with no seals skips the seals step, one with a fragile seal has one more step;
## - taking things out (disassemble) sends the player back to the products step;
## - every step has a translation key (es and en) and is done with the `interact` action, which has
##   a keyboard and a gamepad event, so the flow works without a mouse;
## - a null table or an empty order does not crash.

const STEP_KEYS: Array[String] = [
	"WORLD_PACKTUT_BOX", "WORLD_PACKTUT_PRODUCTS", "WORLD_PACKTUT_SEALS", "WORLD_PACKTUT_LABEL",
	"WORLD_PACKTUT_TAPE", "WORLD_PACKTUT_DISPATCH", "WORLD_PACKTUT_DONE",
]

var _failures: int = 0
var _products: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null:
		_expect(false, "CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Tutorial")
	_products = {&"mug": _product(&"mug"), &"book": _product(&"book")}
	_test_flow(state)
	_test_seals(state)
	_test_edges()
	_test_keys_and_input()
	if _failures == 0:
		print("PASS: the packing tutorial follows the table step by step")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _product(id: StringName) -> ProductDefinition:
	var p := ProductDefinition.new()
	p.id = id
	p.cells = Vector3i(1, 1, 1)
	p.buy_price = 20
	return p


func _order(requirements: Array[StringName] = []) -> Dictionary:
	return Order.make(
		&"o1", "Clara", &"centro", &"centro_house_7",
		[{"product": &"mug", "qty": 2}, {"product": &"book", "qty": 1}],
		0, _products, requirements,
	)


func _id(table: PackingStation, order: Dictionary, dispatched: bool = false) -> StringName:
	return PackingTutorial.step(table, order, dispatched)["id"]


func _fill(table: PackingStation, ids: Array) -> void:
	for id: StringName in ids:
		var p: ProductDefinition = _products[id]
		table.stage_product(id)
		_expect(table.put_in_box(p, table.box.first_fit(p)), "put %s" % id)


func _test_flow(state: Node) -> void:
	var order: Dictionary = _order()
	var table: PackingStation = PackingStation.make(&"t1")
	var expected: Array[StringName] = [&"box", &"products", &"label", &"tape", &"dispatch"]
	_expect(PackingTutorial.steps_for(order) == expected, "5 steps, no seals")
	_expect(_id(table, order) == PackingTutorial.BOX, "empty table asks for a box")
	table.start_box(&"M")
	_expect(_id(table, order) == PackingTutorial.PRODUCTS, "empty box asks for products")
	_fill(table, [&"mug", &"mug"])
	_expect(_id(table, order) == PackingTutorial.PRODUCTS, "still missing one product")
	_fill(table, [&"book"])
	var step: Dictionary = PackingTutorial.step(table, order)
	_expect(step["id"] == PackingTutorial.LABEL, "right content asks for the label")
	_expect(step["index"] == 2 and step["total"] == 5 and not step["done"], "third of five steps")
	_expect(table.label_for(order, state), "label")
	_expect(_id(table, order) == PackingTutorial.TAPE, "labeled box asks for tape")
	_expect(table.seal(state), "tape")
	_expect(_id(table, order) == PackingTutorial.DISPATCH, "taped box asks to dispatch")
	_expect(table.dispatch() != null, "dispatch")
	_expect(_id(table, order, false) == PackingTutorial.BOX, "not told dispatched, the empty table starts over")
	var done: Dictionary = PackingTutorial.step(table, order, true)
	_expect(done["id"] == PackingTutorial.DONE and done["done"], "dispatched: done")
	# Taking the box apart sends the player back to the products.
	table.start_box(&"M")
	_fill(table, [&"mug", &"mug", &"book"])
	table.disassemble()
	_expect(_id(table, order) == PackingTutorial.PRODUCTS, "disassembled box asks for products again")


func _test_seals(state: Node) -> void:
	var order: Dictionary = _order([&"fragile"])
	var steps: Array[StringName] = PackingTutorial.steps_for(order)
	_expect(steps.size() == 6 and steps.has(PackingTutorial.SEALS), "a fragile order adds the seals step")
	var table: PackingStation = PackingStation.make(&"t2")
	table.start_box(&"M")
	_fill(table, [&"mug", &"mug", &"book"])
	_expect(_id(table, order) == PackingTutorial.SEALS, "right content, seal missing")
	_expect(table.stamp(&"fragile", state), "stamp")
	_expect(_id(table, order) == PackingTutorial.LABEL, "seal on, label next")


func _test_edges() -> void:
	_expect(PackingTutorial.step(null, {})["id"] == PackingTutorial.BOX, "no table: box step")
	var table: PackingStation = PackingStation.make(&"t3")
	table.start_box(&"S")
	_expect(PackingTutorial.step(table, {}) is Dictionary, "empty order does not crash")


func _test_keys_and_input() -> void:
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in STEP_KEYS:
			_expect(TranslationServer.translate(key) != key, "%s translated in %s" % [key, locale])
	for id: StringName in PackingTutorial.KEYS:
		_expect(STEP_KEYS.has(PackingTutorial.KEYS[id]), "%s has a known key" % id)
	var has_pad: bool = false
	var has_key: bool = false
	for ev: InputEvent in InputMap.action_get_events(PackingTutorial.ACTION):
		has_pad = has_pad or ev is InputEventJoypadButton
		has_key = has_key or ev is InputEventKey
	_expect(has_pad and has_key, "the step action works with keyboard and gamepad")

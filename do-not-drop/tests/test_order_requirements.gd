extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_requirements.gd
##
## The six order requirements (expansion D-0806, order_requirement.gd):
## - data/order_requirements/ holds exactly fragile, cold, gift, urgent, heavy
##   and no_bend, each loading as OrderRequirement with the file name as id and
##   a WORLD_REQ_<ID> display key;
## - every one asks for something (seals, quality or a shorter window) and pays
##   a bonus in (0, 1];
## - urgent halves the delivery window, the others leave it alone;
## - paid() applies the bonus;
## - Order.make() accepts every requirement id and validate() finds no problem.

const DIR := "res://data/order_requirements"
const IDS: Array[StringName] = [&"cold", &"fragile", &"gift", &"heavy", &"no_bend", &"urgent"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var files: Array[String] = []
	for f: String in DirAccess.get_files_at(DIR):
		if f.ends_with(".tres"):
			files.append(f.get_basename())
	files.sort()
	_expect(files.size() == IDS.size(), "six requirement files (got %s)" % [files])
	for id: StringName in IDS:
		_check(id)
	_test_order_accepts_all()
	quit(_failures)


func _check(id: StringName) -> void:
	var req: OrderRequirement = load("%s/%s.tres" % [DIR, id])
	_expect(req != null, "%s loads as OrderRequirement" % id)
	if req == null:
		return
	_expect(req.id == id, "%s: id matches the file name" % id)
	_expect(req.display_key == "WORLD_REQ_" + String(id).to_upper(), "%s: display key" % id)
	var asks: bool = (
		not req.required_seals.is_empty() or req.min_quality > 0 or req.window_factor < 1.0
	)
	_expect(asks, "%s asks for seals, quality or a shorter window" % id)
	_expect(req.pay_bonus > 0.0 and req.pay_bonus <= 1.0, "%s: bonus in (0, 1]" % id)
	if id == &"urgent":
		_expect(req.window_min(Order.WINDOW_MIN) == Order.WINDOW_MIN / 2, "urgent halves the window")
	else:
		_expect(req.window_min(Order.WINDOW_MIN) == Order.WINDOW_MIN, "%s keeps the window" % id)
	_expect(req.paid(100) == roundi(100.0 * (1.0 + req.pay_bonus)), "%s: paid() adds the bonus" % id)


func _test_order_accepts_all() -> void:
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	var reqs: Array[StringName] = IDS.duplicate()
	var order := Order.make(
		&"o1", "Doña Rosa", &"campo", &"campo_3", [{"product": &"hen", "qty": 1}], 0, products, reqs
	)
	_expect(Order.validate(order).is_empty(), "an order with all six requirements validates")
	_expect(order["requirements"].size() == 6, "the order keeps the six requirements")


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)

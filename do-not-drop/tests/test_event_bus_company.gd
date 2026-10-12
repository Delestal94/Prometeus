extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_event_bus_company.gd
##
## Business signals of the company mode on EventBus (expansion D-0215, event_bus.gd;
## docs/arquitectura.md section 10.3):
## - the eleven signals exist with their exact argument names and types, after the 58 the
##   game already had (none reordered);
## - CompanyState.earn/spend/charge emit money_changed with the signed amount and the
##   ledger reason, and a refused spend emits nothing;
## - CompanyState.open_gate emits gate_opened once; opening it again emits nothing;
## - from_dict() (a loaded save or a snapshot) emits no fact.

const EXPECTED: Dictionary = {
	&"company_day_started": [["day", TYPE_INT]],
	&"company_day_closing": [["day", TYPE_INT]],
	&"company_day_summary": [["day", TYPE_INT], ["summary", TYPE_DICTIONARY]],
	&"order_added": [["order_id", TYPE_STRING_NAME]],
	&"order_packed": [["order_id", TYPE_STRING_NAME]],
	&"order_delivered": [["order_id", TYPE_STRING_NAME]],
	&"supply_arrived": [["supplier_id", TYPE_STRING_NAME]],
	&"box_sealed": [["station_id", TYPE_STRING_NAME], ["order_id", TYPE_STRING_NAME]],
	&"gate_opened": [["gate_id", TYPE_STRING_NAME]],
	&"milestone_reached": [["milestone_id", TYPE_STRING_NAME]],
	&"money_changed": [["amount", TYPE_INT], ["reason", TYPE_STRING_NAME]],
}
## Signals event_bus.gd declared before D-0215; the new ones go after them.
const GAME_SIGNALS_BEFORE: int = 58

var _failures: int = 0
var _money: Array = []
var _gates: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bus: Node = root.get_node_or_null(^"EventBus")
	var state: Node = root.get_node_or_null(^"CompanyState")
	if bus == null or state == null:
		push_error("EventBus or CompanyState autoload missing")
		quit(1)
		return
	_test_signatures(bus)
	bus.connect(&"money_changed", func(amount: int, reason: StringName) -> void:
		_money.append([amount, reason]))
	bus.connect(&"gate_opened", func(gate_id: StringName) -> void: _gates.append(gate_id))
	_test_money(state)
	_test_gate(state)
	_test_load_is_silent(state)
	state.reset()
	if _failures == 0:
		print("PASS: EventBus has the company signals; CompanyState emits money and gate facts")
	quit(_failures)


func _test_signatures(bus: Node) -> void:
	var own: Array[StringName] = []
	for info: Dictionary in bus.get_script().get_script_signal_list():
		own.append(StringName(info["name"]))
	for signal_name: StringName in EXPECTED:
		_expect(bus.has_signal(signal_name), "EventBus has %s" % signal_name)
		var index: int = own.find(signal_name)
		_expect(index >= GAME_SIGNALS_BEFORE,
			"%s goes after the %d older signals (at %d)" % [signal_name, GAME_SIGNALS_BEFORE, index])
		var args: Array = _args_of(bus, signal_name)
		var wanted: Array = EXPECTED[signal_name]
		_expect(args.size() == wanted.size(), "%s takes %d arguments" % [signal_name, wanted.size()])
		for i: int in mini(args.size(), wanted.size()):
			_expect(args[i]["name"] == wanted[i][0] and args[i]["type"] == wanted[i][1],
				"%s argument %d is %s of type %d" % [signal_name, i, wanted[i][0], wanted[i][1]])


func _args_of(bus: Node, signal_name: StringName) -> Array:
	for info: Dictionary in bus.get_signal_list():
		if StringName(info["name"]) == signal_name:
			return info["args"]
	return []


func _test_money(state: Node) -> void:
	state.new_company("Signals Co")
	_money.clear()
	state.earn(80, &"order_paid")
	state.spend(30, &"supplier")
	state.spend(1_000_000, &"supplier")
	state.charge(10, &"rent")
	state.earn(0, &"nothing")
	_expect(_money == [[80, &"order_paid"], [-30, &"supplier"], [-10, &"rent"]],
		"money_changed carries signed amount and reason, only for real movements (got %s)" % [_money])


func _test_gate(state: Node) -> void:
	_gates.clear()
	_expect(state.open_gate(&"gate_bridge"), "the gate opens")
	_expect(not state.open_gate(&"gate_bridge"), "an open gate doesn't open again")
	_expect(_gates == [&"gate_bridge"], "gate_opened fires once (got %s)" % [_gates])


func _test_load_is_silent(state: Node) -> void:
	state.earn(5, &"tip")
	state.open_gate(&"gate_river")
	var saved: Dictionary = state.to_dict()
	state.new_company("Other Co")
	_money.clear()
	_gates.clear()
	state.from_dict(saved)
	_expect(state.is_gate_open(&"gate_river"), "from_dict brings the gate back")
	_expect(_money.is_empty() and _gates.is_empty(), "from_dict fires no fact signal")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

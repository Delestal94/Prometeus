extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gate.gd
##
## Gates of the continuous map (expansion D-0306, gate_requirement.gd,
## world_gate.gd, data/gates/*.tres, CompanyState.open_gate):
## - the 7 gates of the map sketch load, are the ones ZoneDefinition.gates names,
##   and water / altitude have no collision while the rest do;
## - a closed gate stops a body that hits it; meeting the milestone opens it,
##   emits gate_opened once and lets the body through;
## - an open gate stays open after to_dict() -> from_dict() (a save and a load);
## - an equipment gate does not open without the gear, nor for a milestone alone;
## - water and altitude let only their vehicle through; a roadblock can be paid.

const GATE_DIR: String = "res://data/gates/"
const ZONE_DIR: String = "res://data/zones/"
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"

var _failures: int = 0
var _opened: Array[StringName] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gates: Dictionary = _load_gates()
	_test_data(gates)
	await _test_blocks_and_opens(gates)
	_test_save_load(gates)
	await _test_equipment(gates)
	_test_vehicle_and_cost(gates)
	if _failures == 0:
		print("PASS: gates block, open once by milestone, equipment, vehicle and cost rules, saved open")
	quit(_failures)


func _load_gates() -> Dictionary:
	var result: Dictionary = {}
	for file: String in DirAccess.get_files_at(GATE_DIR):
		if file.ends_with(".tres"):
			var gate: GateRequirement = load(GATE_DIR + file)
			result[gate.id] = gate
	return result


func _new_state() -> Object:
	var state: Object = (load(STATE_SCRIPT) as GDScript).new()
	state.call("new_company", "Test")
	return state


func _new_gate(gates: Dictionary, id: StringName, state: Object) -> WorldGate:
	var gate := WorldGate.new()
	gate.setup(gates[id], state)
	root.add_child(gate)
	gate.gate_opened.connect(func(gate_id: StringName) -> void: _opened.append(gate_id))
	return gate


func _test_data(gates: Dictionary) -> void:
	_expect(gates.size() == 7, "7 gates in data/gates (got %d)" % gates.size())
	for file: String in DirAccess.get_files_at(ZONE_DIR):
		if file.ends_with(".tres"):
			var zone: ZoneDefinition = load(ZONE_DIR + file)
			for gate_id: StringName in zone.gates:
				_expect(gates.has(gate_id), "%s names %s and the .tres exists" % [zone.id, gate_id])
	for id: StringName in [&"gate_islas_agua", &"gate_montana_altura"]:
		_expect(not (gates[id] as GateRequirement).has_collision(), "%s has no collision" % id)
	var walls: Array[StringName] = [
		&"gate_suburbio", &"gate_campo_obra", &"gate_puerto", &"gate_nieve_equipo", &"gate_volcan_equipo"
	]
	for id: StringName in walls:
		_expect((gates[id] as GateRequirement).has_collision(), "%s has collision" % id)


func _make_body(from: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	body.add_child(shape)
	body.gravity_scale = 0.0
	body.position = from
	root.add_child(body)
	return body


func _push_and_wait(body: RigidBody3D, speed: Vector3) -> void:
	body.linear_velocity = speed
	for i: int in 90:
		await physics_frame


func _test_blocks_and_opens(gates: Dictionary) -> void:
	var state: Object = _new_state()
	var gate: WorldGate = _new_gate(gates, &"gate_suburbio", state)
	await physics_frame
	var gx: float = gate.position.x
	var blocked: RigidBody3D = _make_body(Vector3(gx, 1.5, -6.0))
	await _push_and_wait(blocked, Vector3(0, 0, 4))
	_expect(blocked.position.z < 0.0, "a closed gate stops the body (z=%.2f)" % blocked.position.z)
	_expect(not gate.try_open(), "without the milestone it stays closed")
	_expect(not state.call("is_gate_open", &"gate_suburbio"), "state says closed")
	(state.get("milestones_done") as Array).append(&"deliveries_25")
	_expect(gate.try_open(), "with the milestone it opens")
	_expect(gate.try_open(), "asking again keeps it open")
	_expect(_opened == [&"gate_suburbio"], "gate_opened is emitted exactly once (%s)" % [_opened])
	await physics_frame
	await physics_frame
	await _push_and_wait(blocked, Vector3(0, 0, 4))
	_expect(blocked.position.z > 1.0, "an open gate lets the body through (z=%.2f)" % blocked.position.z)
	blocked.queue_free()
	gate.queue_free()
	state.free()


func _test_save_load(gates: Dictionary) -> void:
	var state: Object = _new_state()
	(state.get("milestones_done") as Array).append(&"deliveries_25")
	var gate: WorldGate = _new_gate(gates, &"gate_suburbio", state)
	gate.try_open()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.call("to_dict")))
	var loaded: Object = _new_state()
	_expect(loaded.call("from_dict", saved), "the saved company loads")
	var again: WorldGate = _new_gate(gates, &"gate_suburbio", loaded)
	_expect(again.is_open(), "an opened gate is still open after save and load")
	_expect((loaded.get("equipment") as Array).is_empty(), "equipment round-trips (empty)")
	gate.queue_free()
	again.queue_free()
	state.free()
	loaded.free()


func _test_equipment(gates: Dictionary) -> void:
	var state: Object = _new_state()
	var gate: WorldGate = _new_gate(gates, &"gate_nieve_equipo", state)
	_expect(not gate.try_open(), "no gear: the snow gate stays closed")
	(state.get("equipment") as Array).append(&"chains")
	_expect(not gate.try_open(), "only chains: still closed")
	_expect(gate.sign_label.text.contains("winter_coat"), "the sign names what is missing (%s)" % gate.sign_label.text)
	(state.get("equipment") as Array).append(&"winter_coat")
	_expect(gate.try_open(), "chains and coat: it opens")
	_expect(not gate.sign_label.text.contains("winter_coat"), "the sign no longer lists what was missing")
	gate.queue_free()
	state.free()
	await physics_frame


func _test_vehicle_and_cost(gates: Dictionary) -> void:
	var state: Object = _new_state()
	var water: WorldGate = _new_gate(gates, &"gate_islas_agua", state)
	_expect(not water.passable_for(&"truck"), "the truck does not cross the water")
	_expect(water.passable_for(&"boat"), "the boat does cross")
	state.set("fleet", [{"vehicle": &"boat"}] as Array[Dictionary])
	_expect(water.try_open(), "owning the boat opens the water gate")
	_expect(water.passable_for(&"truck"), "open: everyone crosses")
	var works: WorldGate = _new_gate(gates, &"gate_campo_obra", state)
	state.set("money", 100)
	_expect(not works.try_open(true), "100 money does not pay a 150 roadblock")
	state.set("money", 400)
	_expect(not works.try_open(false), "without paying the roadblock stays closed")
	_expect(works.try_open(true) and state.get("money") == 250, "paying 150 opens it (money %s)" % state.get("money"))
	water.queue_free()
	works.queue_free()
	state.free()


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + label)

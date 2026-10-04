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
## - water and altitude let only their vehicle through; a roadblock can be paid;
## - every kind shows its GLB (a "Model" node with meshes, not the grey box) and
##   the moving part opens: boom +-90 degrees, barricades +-5.5 m, ranger door
##   90 degrees; refresh() twice leaves the same pose; coast and mountain signs are
##   visible without collision and carry their text on the board.

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
	_test_models(gates)
	if _failures == 0:
		print("PASS: gates block, open once by milestone, equipment, vehicle, cost rules, saved open, models")
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


func _first_mesh(node: Node) -> MeshInstance3D:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
		var nested: MeshInstance3D = _first_mesh(child)
		if nested != null:
			return nested
	return null


func _part(gate: WorldGate, part_name: String) -> Node3D:
	return gate.get_node("Model").find_child(part_name, true, false) as Node3D


func _snapshot(gate: WorldGate, names: Array[String]) -> Array:
	var result: Array = []
	for part_name: String in names:
		var node: Node3D = _part(gate, part_name)
		result.append([node.position, node.rotation])
	return result


func _test_models(gates: Dictionary) -> void:
	var state: Object = _new_state()
	state.set("money", 1000)
	var parts: Dictionary = {
		&"gate_suburbio": ["Boom"],
		&"gate_campo_obra": ["BarricadeLeft", "BarricadeRight"],
		&"gate_nieve_equipo": ["Boom", "Door"],
		&"gate_islas_agua": [],
		&"gate_montana_altura": [],
	}
	for id: StringName in parts:
		var gate: WorldGate = _new_gate(gates, id, state)
		var model: Node = gate.get_node_or_null("Model")
		_expect(model is Node3D and not model is MeshInstance3D,
				"%s instances its model, not the grey box" % id)
		if model == null or _first_mesh(model) == null:
			_expect(false, "%s model has a MeshInstance3D" % id)
			gate.queue_free()
			continue
		_expect(gate.get_node_or_null("Body") != null, "%s keeps its Body" % id)
		var names: Array[String] = []
		names.assign(parts[id])
		for part_name: String in names:
			_expect(_part(gate, part_name) != null, "%s has the %s node" % [id, part_name])
		if names.is_empty():
			_check_sign_gate(gate, id)
		else:
			_check_moving_gate(gate, id, names, state)
		gate.queue_free()
	state.free()


func _check_moving_gate(gate: WorldGate, id: StringName, names: Array[String], state: Object) -> void:
	var closed: Array = _snapshot(gate, names)
	gate.refresh()
	gate.refresh()
	_expect(_snapshot(gate, names) == closed, "%s: refresh() twice keeps the closed pose" % id)
	(state.get("milestones_done") as Array).append(&"deliveries_25")
	if id == &"gate_nieve_equipo":
		(state.get("equipment") as Array).append_array([&"chains", &"winter_coat"])
	_expect(gate.try_open(true), "%s opens" % id)
	var open: Array = _snapshot(gate, names)
	gate.refresh()
	gate.refresh()
	_expect(_snapshot(gate, names) == open, "%s: refresh() twice keeps the open pose" % id)
	match id:
		&"gate_suburbio":
			_expect(is_equal_approx(open[0][1].z - closed[0][1].z, -PI * 0.5), "the barrier boom swings up -90 deg")
		&"gate_campo_obra":
			var left: float = open[0][0].x - closed[0][0].x
			var right: float = open[1][0].x - closed[1][0].x
			_expect(is_equal_approx(left, -5.5), "the left barricade slides -5.5 m (%.2f)" % left)
			_expect(is_equal_approx(right, 5.5), "the right barricade slides +5.5 m (%.2f)" % right)
		&"gate_nieve_equipo":
			_expect(is_equal_approx(open[0][1].z - closed[0][1].z, PI * 0.5), "the checkpoint boom swings up +90 deg")
			_expect(is_equal_approx(open[1][1].y - closed[1][1].y, PI * 0.5), "the ranger door opens +90 deg")


func _check_sign_gate(gate: WorldGate, id: StringName) -> void:
	var model: Node3D = gate.get_node("Model")
	_expect(model.visible, "%s sign is visible even without collision" % id)
	_expect(not gate.requirement.has_collision(), "%s has no collision" % id)
	var board: Node3D = _part(gate, "Board")
	_expect(board != null, "%s has its Board" % id)
	_expect(gate.sign_label.billboard == BaseMaterial3D.BILLBOARD_DISABLED, "%s text is flat on the board" % id)
	if board != null:
		var offset: Vector3 = gate.sign_label.global_position - board.global_position
		_expect(offset.length() < 0.1 and offset.z > 0.0, "%s text sits just in front of the board %s" % [id, offset])


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + label)

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_shed_exterior.gd
##
## Outside of the shed per stage (expansion D-0936, ShedExteriorPlan and ShedExterior):
## - four variants, one per shed stage, each with its own sign text key that exists in both languages;
## - sign, yard and lamps only grow with the stage, and the sign never passes the wall it hangs on;
## - the lamp posts come in pairs inside the floor width and clear of the truck's lane;
## - ShedExterior draws sign, yard and lamps with no collision, and CompanyShed.rebuild() hangs one
##   exterior that follows the stage (a bigger stage gives a wider sign and a deeper yard).

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(ShedExteriorPlan.variant_count() == WarehouseStages.stage_count(), "one variant per stage")
	var last_sign: float = 0.0
	var last_yard: float = 0.0
	var last_lamps: int = -1
	var keys: Dictionary = {}
	for stage: int in ShedExteriorPlan.variant_count():
		var floor_m: Vector2 = WarehouseStages.floor_size_m(stage)
		var size: Vector2 = ShedExteriorPlan.sign_size(stage, floor_m.x)
		_expect(size.x <= floor_m.x and size.x > last_sign, "stage %d: wider sign that fits its wall" % stage)
		_expect(ShedExteriorPlan.yard_depth(stage) > last_yard, "stage %d: deeper yard" % stage)
		var xs: Array[float] = ShedExteriorPlan.lamp_xs(stage, floor_m.x)
		_expect(xs.size() >= last_lamps, "stage %d: no fewer lamps" % stage)
		for x: float in xs:
			_expect(absf(x) < floor_m.x * 0.5 and absf(x) >= ShedExteriorPlan.LAMP_CLEAR,
				"stage %d: lamp inside the width and clear of the dock gate's centre line" % stage)
		var key: StringName = ShedExteriorPlan.variant(stage)["key"]
		_expect(not keys.has(key), "stage %d: its own sign key" % stage)
		keys[key] = true
		_expect(tr(String(key)) != String(key), "stage %d: sign key %s is translated" % [stage, key])
		last_sign = size.x
		last_yard = ShedExteriorPlan.yard_depth(stage)
		last_lamps = xs.size()
	_expect(ShedExteriorPlan.variant(-5) == ShedExteriorPlan.variant(0), "a stage below 0 is the first variant")
	_expect(ShedExteriorPlan.variant(99) == ShedExteriorPlan.variant(3), "a stage above the last is the last variant")

	var widths: Array[float] = []
	var depths: Array[float] = []
	for stage: int in ShedExteriorPlan.variant_count():
		var exterior: ShedExterior = ShedExterior.build(stage, WarehouseStages.floor_size_m(stage), CompanyShed.WALL_HEIGHT)
		var board: MeshInstance3D = exterior.get_node_or_null(^"Sign")
		var yard: MeshInstance3D = exterior.get_node_or_null(^"Yard")
		_expect(board != null and yard != null, "stage %d draws a sign and a yard" % stage)
		_expect(exterior.get_node_or_null(^"SignText") != null, "stage %d: the sign has its text" % stage)
		_expect(_bodies_in(exterior) == 0, "stage %d: the exterior has no collision" % stage)
		if board != null and yard != null:
			widths.append((board.mesh as BoxMesh).size.x)
			depths.append((yard.mesh as BoxMesh).size.z)
			_expect(board.position.y > CompanyShed.WALL_HEIGHT, "stage %d: the sign is above the wall" % stage)
			_expect(yard.position.z - (yard.mesh as BoxMesh).size.z * 0.5 >= WarehouseStages.floor_size_m(stage).y * 0.5,
				"stage %d: the yard starts at the dock wall" % stage)
		exterior.free()
	for i: int in range(1, widths.size()):
		_expect(widths[i] > widths[i - 1] and depths[i] > depths[i - 1], "built exterior %d grows" % i)

	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Exterior Co")
	var shed := CompanyShed.new()
	root.add_child(shed)
	var stock := Inventory.new()
	shed.rebuild(state, stock)
	var first: Node = shed.get_node_or_null(^"Exterior")
	_expect(first != null, "the shed hangs an exterior")
	var first_width: float = ((first.get_node(^"Sign") as MeshInstance3D).mesh as BoxMesh).size.x if first != null else 0.0
	state.warehouse_stage = 2
	shed.rebuild(state, stock)
	await process_frame
	var second: Node = shed.get_node_or_null(^"Exterior")
	_expect(second != null and shed.get_children().filter(func(n: Node) -> bool: return n.name == &"Exterior").size() == 1,
		"a redraw keeps exactly one exterior")
	if second != null:
		_expect(((second.get_node(^"Sign") as MeshInstance3D).mesh as BoxMesh).size.x > first_width,
			"the exterior follows the stage after a redraw")
	shed.free()
	quit(_failures)


func _bodies_in(node: Node) -> int:
	var count: int = 1 if node is CollisionObject3D else 0
	for child: Node in node.get_children():
		count += _bodies_in(child)
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
		print("FAIL: ", message)

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_reference_truck_golden.gd
## Regenerate the expected file: add `-- --write-golden` to that command (only when the truck's
## art is meant to change; a pure refactor must leave the file untouched).
##
## N-225.2: reference_truck.gd was split by responsibility (ReferenceTruckCab, ReferenceTruckCargo,
## ReferenceTruckPanelLines, ...) and must build exactly the same nodes as the single-file version.
## The test instantiates the truck as test_reference_truck.gd does and writes one signature line
## per node the adapter makes or touches (BodyVisuals incl. the model and its cab dressing, cargo
## fittings, ramp and retro chrome; the ReferenceTruck node's door audio; the authored tires hung
## on the physics wheels; the bulkhead collision boxes): relative path (children in order), class,
## transform to 1e-4, visibility, mesh kind/size/AABB/vertices, materials (by content hash, plus
## which are shared between slots), shape, collision layers, metadata. The first state is
## compared line by line against tests/data/reference_truck_golden.txt, which was generated with
## the original file; then each step (rear door shut, cab door open, ramp out and in, paint,
## retro chrome on and off, pedals pressed, a passenger in a fold-down seat) is compared as a
## diff against the previous state. The WindshieldRain and DashboardGps subtrees are live
## animations (drops, map), so only their own node is signed; their tests cover the rest.

const GOLDEN_PATH := "res://tests/data/reference_truck_golden.txt"
## Properties of these value types go into a dump when they differ from a fresh instance.
const DUMP_TYPES: Array[int] = [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR, TYPE_STRING]
const LIVE_SUBTREES: Array[StringName] = [&"WindshieldRain", &"DashboardGps"]
const WHEELS: Array[String] = ["FrontLeftWheel", "FrontRightWheel", "RearLeftWheel", "RearRightWheel"]

var _failures: int = 0
var _van: VehicleBody3D
var _truck: ReferenceTruck
var _material_uses: Dictionary = {}
var _material_dumps: Dictionary = {}
var _auto_names: RegEx


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_auto_names = RegEx.create_from_string("@(\\w+)@\\d+")
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(80.0, 1.0, 80.0)
	ground_shape.shape = ground_box
	ground_shape.position.y = -0.5
	ground.add_child(ground_shape)
	world.add_child(ground)
	_van = (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	_van.position.y = 1.5
	world.add_child(_van)
	await process_frame
	await process_frame
	_truck = _van.get_node_or_null(^"ReferenceTruck") as ReferenceTruck
	_expect(
			_truck != null and _van.get_node_or_null(^"BodyVisuals/ReferenceTruckModel") != null,
			"The authored truck model is installed",
		)
	if _truck == null or _truck.model == null:
		quit(1)
		return

	var states: Array = []  # [title, lines]
	states.append(["initial", _signature()])

	_van.set_door_open(&"rear", false)
	await create_timer(0.8).timeout
	states.append(["rear doors shut (ramp stows with them)", _signature()])

	_van.set_door_open(&"cab_left", not _van.is_door_open(&"cab_left"))
	await create_timer(0.8).timeout
	states.append(["cab_left door toggled", _signature()])

	_truck.set_ramp_deployed(true)
	await create_timer(0.7).timeout
	states.append(["ramp deployed", _signature()])
	_truck.set_ramp_deployed(false)
	await create_timer(0.7).timeout
	states.append(["ramp stowed", _signature()])

	_truck.set_paint(Color("336699"), Color("e61a1a"))
	states.append(["paint set", _signature()])

	_truck.set_retro(true)
	states.append(["retro chrome on", _signature()])
	_truck.set_retro(false)
	states.append(["retro chrome off", _signature()])

	# Pedals dip with what the truck does and fold-down seats drop for a passenger.
	_van.presentation_braking = true
	_van.engine_force = 900.0
	var seated := _passenger(_van.get_node(^"CargoBay/RackSeat2EyePoint").get_path())
	world.add_child(seated)
	_truck._process(1.0)
	states.append(["pedals pressed, RackSeat2 occupied", _signature()])
	seated.free()
	_van.presentation_braking = false
	_van.engine_force = 0.0
	_truck._process(1.0)
	states.append(["pedals released, seats folded", _signature()])

	_check_facts(states)
	var text: String = _render(states)
	if OS.get_cmdline_user_args().has("--write-golden"):
		var out := FileAccess.open(GOLDEN_PATH, FileAccess.WRITE)
		out.store_string(text)
		out.close()
		print("Golden written: %s (%d lines)" % [GOLDEN_PATH, text.count("\n")])
	else:
		_compare(text)

	world.free()
	await process_frame
	if _failures == 0:
		print("PASS: the reference truck builds the very same nodes, materials and collisions as before the split")
	quit(_failures)


## Checks that do not depend on the golden: what other scripts read from the adapter.
func _check_facts(states: Array) -> void:
	_expect(_truck.vehicle == _van and _truck.model != null, "The adapter exposes its vehicle and model")
	_expect(
			_truck.steering_wheel != null and _truck.steering_wheel.name == &"SteeringWheel",
			"The adapter exposes the rebuilt steering wheel",
		)
	_expect(_truck.ramp_visual != null and _truck.ramp_visual.name == &"RampVisual", "The adapter exposes the ramp art")
	_expect(_truck.panel_lines.size() > 20, "The adapter lists its panel lines (got %d)" % _truck.panel_lines.size())
	var paints: Dictionary = _truck.get(&"_paint_materials")
	_expect(
			paints.has("DT_White") and paints.has("DT_Blue"),
			"The adapter keeps its paint copies (got %s)" % str(paints.keys()),
		)
	_expect(
			(paints["DT_White"] as BaseMaterial3D).albedo_color.is_equal_approx(Color("336699")),
			"set_paint recolours the body copy",
		)
	_expect(
			_van.get_node_or_null(^"BodyVisuals/RetroChrome") == null, "set_retro(false) removes the retro chrome again"
		)
	var blades: bool = ReferenceTruck.is_model_wiper("Wiper") and ReferenceTruck.is_model_wiper("Wiper.001")
	_expect(blades and not ReferenceTruck.is_model_wiper("WiperArm"), "is_model_wiper tells the blades from the arms")
	_expect(states.size() == 10, "Every step was signed (got %d)" % states.size())


func _passenger(seat: NodePath) -> Node3D:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar seat_node_path: NodePath\n"
	script.reload()
	var player := Node3D.new()
	player.set_script(script)
	player.set(&"seat_node_path", seat)
	player.add_to_group(&"player")
	return player


# --- signature ---------------------------------------------------------------------------------

func _signature() -> PackedStringArray:
	_material_uses.clear()
	_material_dumps.clear()
	var lines := PackedStringArray()
	_sign_tree(_van.get_node(^"BodyVisuals"), lines)
	_sign_tree(_van.get_node(^"ReferenceTruck"), lines)
	for wheel_name: String in WHEELS:
		for child: Node in _van.get_node(NodePath(wheel_name)).get_children():
			_sign_tree(child, lines)
	for child: Node in _van.get_children():
		if String(child.name).begins_with("Bulkhead"):
			_sign_tree(child, lines)
	var shared: Array[String] = []
	for id: int in _material_uses:
		var use: Dictionary = _material_uses[id]
		if int(use["count"]) > 1:
			shared.append("%s x%d" % [use["hash"], use["count"]])
	shared.sort()
	for entry: String in shared:
		lines.append("shared material " + entry)
	var dumps: Array[String] = []
	for key: String in _material_dumps:
		dumps.append("material %s = %s" % [key, _material_dumps[key]])
	dumps.sort()
	lines.append_array(PackedStringArray(dumps))
	return lines


func _sign_tree(node: Node, lines: PackedStringArray) -> void:
	lines.append(_node_line(node))
	if node.name in LIVE_SUBTREES:
		return
	for child: Node in node.get_children():
		_sign_tree(child, lines)


func _node_line(node: Node) -> String:
	# Engine-made names ("@MeshInstance3D@44") carry a global counter: keep the kind, drop the number.
	var parts: Array[String] = [_auto_names.sub(str(_van.get_path_to(node)), "@$1@", true), node.get_class()]
	if node.get_script() != null:
		parts.append("script=" + String((node.get_script() as Script).resource_path.get_file()))
	if node is Node3D:
		var node3d := node as Node3D
		var basis: Basis = node3d.transform.basis
		parts.append("pos(%s)" % _vec(node3d.position))
		parts.append("basis(%s %s %s)" % [_vec(basis.x), _vec(basis.y), _vec(basis.z)])
		if not node3d.visible:
			parts.append("hidden")
	for meta: StringName in node.get_meta_list():
		parts.append("meta %s=%s" % [meta, str(node.get_meta(meta))])
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		parts.append("shadow=%d" % mesh_node.cast_shadow)
		parts.append("mesh{%s}" % _mesh(mesh_node.mesh))
		parts.append("override=" + _material(mesh_node.material_override))
		if mesh_node.mesh != null:
			for surface: int in range(mesh_node.mesh.get_surface_count()):
				parts.append("surface%d=%s/%s" % [surface, _material(mesh_node.mesh.surface_get_material(surface)),
					_material(mesh_node.get_surface_override_material(surface))])
	if node is CollisionShape3D:
		var collision := node as CollisionShape3D
		parts.append("disabled=%s shape{%s}" % [collision.disabled, _shape(collision.shape)])
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		parts.append("layer=%d mask=%d" % [body.collision_layer, body.collision_mask])
	if node is AudioStreamPlayer3D:
		var audio := node as AudioStreamPlayer3D
		var wav := audio.stream as AudioStreamWAV
		var stream: String = "%d bytes" % wav.data.size() if wav != null else "none"
		parts.append("audio unit=%s max=%s volume=%s pitch=%s stream=%s" % [
			_num(audio.unit_size), _num(audio.max_distance), _num(audio.volume_db), _num(audio.pitch_scale), stream])
	return " | ".join(parts)


func _mesh(mesh: Mesh) -> String:
	if mesh == null:
		return "none"
	var text: String = mesh.get_class() + " name=" + mesh.resource_name
	var aabb: AABB = mesh.get_aabb()
	text += " aabb(%s %s)" % [_vec(aabb.position), _vec(aabb.size)]
	if mesh is PrimitiveMesh:
		text += " " + _dump_changed(mesh) + " material=" + _material((mesh as PrimitiveMesh).material)
	else:
		text += " surfaces=%d" % mesh.get_surface_count()
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var total := Vector3.ZERO
			for vertex: Vector3 in vertices:
				total += vertex
			var indices: int = 0
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
			text += " [verts=%d sum(%s) indices=%d]" % [vertices.size(), _vec(total), indices]
	return text


func _shape(shape: Shape3D) -> String:
	if shape == null:
		return "none"
	return shape.get_class() + " " + _dump_changed(shape)


## A material is named by its content (so a re-ordering of instances is not a diff) and the
## sharing between slots is listed on its own lines (see _signature).
func _material(material: Material) -> String:
	if material == null:
		return "none"
	var dump: String = "%s name='%s' %s" % [material.get_class(), material.resource_name, _dump_changed(material)]
	var short: String = dump.sha1_text().substr(0, 8)
	var use: Dictionary = _material_uses.get(material.get_instance_id(), {"hash": short, "count": 0})
	use["count"] = int(use["count"]) + 1
	_material_uses[material.get_instance_id()] = use
	_material_dumps[short] = dump
	return short


## Every value property that differs from a fresh instance of the same class.
func _dump_changed(object: Object) -> String:
	var fresh: Object = ClassDB.instantiate(object.get_class())
	var entries: Array[String] = []
	for property: Dictionary in object.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE) or not int(property.type) in DUMP_TYPES:
			continue
		var name_: String = property.name
		if name_ == "resource_name" or name_ == "resource_path":
			continue
		var value: Variant = object.get(name_)
		if fresh != null and fresh.get(name_) == value:
			continue
		entries.append("%s=%s" % [name_, _variant(value)])
	if fresh != null and not fresh is RefCounted:
		fresh.free()
	return ",".join(entries)


func _variant(value: Variant) -> String:
	match typeof(value):
		TYPE_FLOAT:
			return _num(value)
		TYPE_VECTOR2:
			return "%s,%s" % [_num((value as Vector2).x), _num((value as Vector2).y)]
		TYPE_VECTOR3:
			return _vec(value)
		TYPE_COLOR:
			var color: Color = value
			return "c(%s,%s,%s,%s)" % [_num(color.r), _num(color.g), _num(color.b), _num(color.a)]
	return str(value)


func _vec(value: Vector3) -> String:
	return "%s %s %s" % [_num(value.x), _num(value.y), _num(value.z)]


func _num(value: float) -> String:
	var text: String = "%.4f" % value
	return "0.0000" if text == "-0.0000" else text


# --- golden file -------------------------------------------------------------------------------

## First state in full, then for each next one only the lines that appear ("+") and vanish ("-").
func _render(states: Array) -> String:
	var out := PackedStringArray()
	var previous := PackedStringArray()
	for index: int in range(states.size()):
		var lines: PackedStringArray = states[index][1]
		out.append("## %s" % states[index][0])
		if index == 0:
			out.append_array(lines)
		else:
			for line: String in lines:
				if not previous.has(line):
					out.append("+ " + line)
			for line: String in previous:
				if not lines.has(line):
					out.append("- " + line)
		previous = lines
	return "\n".join(out) + "\n"


func _compare(text: String) -> void:
	var file := FileAccess.open(GOLDEN_PATH, FileAccess.READ)
	_expect(file != null, "The golden file exists (%s); generate it with -- --write-golden" % GOLDEN_PATH)
	if file == null:
		return
	var expected: PackedStringArray = file.get_as_text().split("\n")
	var actual: PackedStringArray = text.split("\n")
	if expected == actual:
		return
	var shown: int = 0
	for line: String in actual:
		if not expected.has(line) and shown < 15:
			shown += 1
			_expect(false, "Not in the golden: " + line.left(500))
	for line: String in expected:
		if not actual.has(line) and shown < 30:
			shown += 1
			_expect(false, "Missing from the truck: " + line.left(500))
	_expect(false, "The truck differs from the golden (%d lines expected, got %d, %d shown)" % [
		expected.size(), actual.size(), shown])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_golden.gd
## Regenerate the expected file: add `-- --write-golden` to that command (only when the route is
## meant to change; a pure refactor must leave the file untouched). `-- --sync` builds the route
## in one go on this thread (async_build off): it must sign exactly the same world.
##
## N-225.3: route.gd was split by responsibility (houses and yards, path lookups, river reach) and
## must build exactly the same world as the single-file version. The test builds route.tscn with a
## fixed world seed in three setups (1 house, 3 houses with the depot yard and batched dressing,
## 4 houses with the yard and loose dressing) and signs, per setup:
## - the route's own numbers (length, house_count, goal transform and target, _plan, mood, the clear
##   and sight zones, the terrain's rivers / paths / pads / flat zones / crests / platforms);
## - every house in full (transform, variant, index, its yard pieces with transform and meta, the
##   "CASA N" label before and after assign_packages());
## - _path_points, _progress_samples and _house_anchors, point by point;
## - every direct child of the route (type, script, transform) and, for the big subtrees (segments,
##   terrain, dressing, goal lot, sky), the node count and a hash of every node's line (path, class,
##   transform to 1e-4, mesh / multimesh size, label text, collision layers, metadata);
## - the answers to get_progress, road_distance, stop_road_distance, distance_from_path,
##   get_section_name and ground_roughness on a grid of points along and around the road.
## tests/data/route_golden.txt was generated with the original single-file route.gd.
## The file was written on Linux (CI): on Windows ~77 lines differ from it by the last digit of a
## coordinate (a 4-decimal rounding that lands the other way: libm's sin/cos/pow differ in the last
## bit), the same 77 before and after any change. To check a refactor there, write the golden
## (-- --write-golden) before and after, compare the two files and `git checkout` the real one.

const GOLDEN_PATH := "res://tests/data/route_golden.txt"
## Characters per "GOLDEN_GZ" line a CI mismatch prints (_print_for_ci()).
const GOLDEN_CHUNK_SIZE: int = 4000
const NETWORK_MANAGER: NodePath = ^"/root/NetworkManager"
## [seed, houses, start_yard, batch_dressing]
const SETUPS: Array = [
	[4242, 1, Rect2(), false],
	[12345, 3, Rect2(-15.0, 4.0, 30.0, 26.0), true],
	[777001, 4, Rect2(-15.0, 4.0, 30.0, 26.0), false],
]
## Direct children whose whole subtree is summarised by a count and a hash instead of line by line.
const SUMMARISED: Array[String] = ["Segment", "ContinuousTerrain", "GoalLot", "Sky", "Dressing", "Forest"]

var _failures: int = 0
var _auto_names: RegEx
var _counters: RegEx


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_auto_names = RegEx.create_from_string("@(\\w+)@\\d+")
	# Names that end in an instance counter ("Knockable_Node3D_3796") move with any new object.
	_counters = RegEx.create_from_string("_\\d+\\b")
	var network: Node = root.get_node(NETWORK_MANAGER)
	# A headless run builds the route in one go unless told otherwise; this is the sliced build.
	var route_script: GDScript = load("res://scripts/gameplay/route/route.gd") as GDScript
	route_script.set(&"always_slice", not OS.get_cmdline_user_args().has("--sync"))
	var original_seed: Variant = network.get(&"world_seed")
	var original_houses: Variant = network.get(&"world_house_count")
	var out := PackedStringArray()
	for setup: Array in SETUPS:
		network.set(&"world_seed", setup[0])
		network.set(&"world_house_count", 0)
		var route: Node3D = (load("res://scenes/gameplay/route/route.tscn") as PackedScene).instantiate() as Node3D
		route.set(&"house_count", setup[1])
		route.set(&"start_yard", setup[2])
		route.set(&"batch_dressing", setup[3])
		route.set(&"async_build", not OS.get_cmdline_user_args().has("--sync"))  # -- --sync: the blocking build
		# Nothing may tick: animals, windmills and knockable fences move with real time.
		route.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(route)
		# The route builds over several frames (N-408); the world it signs is the finished one.
		if not route.get(&"is_built"):
			await Signal(route, &"built")
		await process_frame
		out.append("#### route seed=%d houses=%d yard=%s batch=%s" % [setup[0], setup[1], _variant(setup[2]), setup[3]])
		out.append_array(_sign_route(route))
		route.free()
		await process_frame
	network.set(&"world_seed", original_seed)
	network.set(&"world_house_count", original_houses)
	var text: String = "\n".join(out) + "\n"
	if OS.get_cmdline_user_args().has("--write-golden"):
		var file := FileAccess.open(GOLDEN_PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		print("Golden written: %s (%d lines)" % [GOLDEN_PATH, text.count("\n")])
	else:
		_compare(text)
	if _failures == 0:
		print("PASS: the route builds the very same world and answers the very same queries as before the split")
	quit(_failures)


# --- signature ---------------------------------------------------------------------------------

func _sign_route(route: Node3D) -> PackedStringArray:
	var lines := PackedStringArray()
	var route_length: float = float(route.get(&"route_length"))
	var house_count: int = int(route.get(&"house_count"))
	var terrain: Node = route.get(&"terrain")
	lines.append("route_length=%s house_count=%d" % [_num(route_length), house_count])
	lines.append("goal_transform=%s" % _xform(route.get(&"goal_transform")))
	lines.append("goal_target=%s bay=%d" % [_vec(route.call(&"goal_target")), int(route.call(&"goal_bay_number"))])
	lines.append("mood=%s" % _variant(_describe_mood(route.get(&"mood"))))
	var plan: Dictionary = route.get(&"_plan")
	for planned: Dictionary in plan.segments:
		lines.append("plan %s" % _variant(_planned(planned)))
	lines.append("clear_zones %s" % _digest(route.get(&"_clear_zones")))
	lines.append("sight_zones %s" % _digest(route.get(&"_sight_zones")))
	for property: String in ["rivers", "paths", "pads", "flat_zones", "crests", "platforms", "tunnels"]:
		var value: Variant = terrain.get(StringName(property))
		lines.append("terrain.%s %s" % [property, _variant(value)])
	lines.append("path_points %s" % _digest(route.get(&"_path_points")))
	for point: Vector3 in route.get(&"_path_points"):
		lines.append("  path %s" % _vec(point))
	for sample: Dictionary in route.get(&"_progress_samples"):
		lines.append("  sample %s" % _variant(sample))
	for anchor: Dictionary in route.get(&"_house_anchors"):
		lines.append("  anchor side=%s cursor=%s" % [_num(anchor.side), _xform(anchor.cursor)])
	lines.append("segments %d" % (route.get(&"_segments") as Array).size())
	for segment: Node3D in route.get(&"_segments"):
		lines.append("  segment %s %s %s %s" % [segment.name, (segment.get_script() as Script).resource_path.get_file(),
			_xform(segment.transform), _meta(segment)])

	lines.append("-- houses")
	_sign_houses(route, lines)
	lines.append("-- assign_packages")
	var assignments: Array = []
	for index: int in range(house_count):
		assignments.append(["pkg_%d" % index, "TRAP_%d" % index, "%d%d" % [index + 1, index * 3]])
	route.call(&"assign_packages", assignments)
	for house: DeliveryHouse in route.get(&"houses"):
		var label: Label3D = route.get_node_or_null(NodePath("HouseNumber%d" % house.house_index)) as Label3D
		var shown: String = label.text.replace("\n", "|") if label != null else "none"
		lines.append("  house%d id=%s label='%s' sign=%s" % [
			house.house_index, house.assigned_package_id, house.assigned_label, shown])

	lines.append("-- children")
	_sign_children(route, lines)

	lines.append("-- queries")
	_sign_queries(route, house_count, lines)
	return lines


func _sign_houses(route: Node3D, lines: PackedStringArray) -> void:
	for house: DeliveryHouse in route.get(&"houses"):
		lines.append("house %s variant=%d index=%d %s" % [
			house.name, house.visual_variant, house.house_index, _xform(house.transform)])
		var label: Node3D = route.get_node_or_null(NodePath("HouseNumber%d" % house.house_index)) as Node3D
		if label != null:
			lines.append("  label %s %s %s" % [label.name, _vec(label.position), _meta(label)])
		var yard: Node = house.get_node_or_null(^"Yard")
		if yard == null:
			lines.append("  no yard")
			continue
		for piece: Node in yard.get_children():
			lines.append("  piece %s" % _node_line(route, piece))
			lines.append("    summary %s" % _subtree_summary(route, piece))


func _sign_children(route: Node3D, lines: PackedStringArray) -> void:
	for child: Node in route.get_children():
		var summarised: bool = false
		for prefix: String in SUMMARISED:
			if String(child.name).begins_with(prefix):
				summarised = true
		if child is DeliveryHouse:
			lines.append(_node_line(route, child) + " | " + _subtree_summary(route, child))
		elif summarised or child.get_child_count() > 6:
			lines.append(_node_line(route, child) + " | " + _subtree_summary(route, child))
		else:
			_sign_tree(route, child, lines)


func _sign_tree(route: Node3D, node: Node, lines: PackedStringArray) -> void:
	lines.append(_node_line(route, node))
	for child: Node in node.get_children():
		_sign_tree(route, child, lines)


func _subtree_summary(route: Node3D, node: Node) -> String:
	var lines := PackedStringArray()
	_sign_tree(route, node, lines)
	if OS.get_cmdline_user_args().has("--dump"):  # to see which node of a subtree changed: diff two dumps
		var dump := FileAccess.open("user://route_golden_dump.txt", FileAccess.READ_WRITE)
		if dump == null:
			dump = FileAccess.open("user://route_golden_dump.txt", FileAccess.WRITE)
		dump.seek_end()
		dump.store_string("\n".join(lines) + "\n")
		dump.close()
	return "nodes=%d hash=%s" % [lines.size(), "\n".join(lines).sha1_text().substr(0, 12)]


func _node_line(route: Node3D, node: Node) -> String:
	var path: String = _counters.sub(_auto_names.sub(str(route.get_path_to(node)), "@$1@", true), "_N", true)
	var parts: Array[String] = [path, node.get_class()]
	if node.get_script() != null:
		parts.append("script=" + String((node.get_script() as Script).resource_path.get_file()))
	if not node.scene_file_path.is_empty():
		parts.append("scene=" + node.scene_file_path.get_file())
	if node is Node3D:
		var node3d := node as Node3D
		parts.append(_xform(node3d.transform))
		if not node3d.visible:
			parts.append("hidden")
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		parts.append("mesh{%s}" % _mesh(mesh_node.mesh))
		parts.append("shadow=%d" % mesh_node.cast_shadow)
	if node is MultiMeshInstance3D:
		var multi := (node as MultiMeshInstance3D).multimesh
		parts.append("multimesh{n=%d %s}" % [multi.instance_count if multi != null else -1,
			_mesh(multi.mesh) if multi != null else "none"])
	if node is Label3D:
		parts.append("text='%s'" % (node as Label3D).text.replace("\n", "|"))
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		parts.append("layer=%d mask=%d" % [body.collision_layer, body.collision_mask])
	if node is CollisionShape3D:
		var shape: Shape3D = (node as CollisionShape3D).shape
		parts.append("shape=%s" % (_shape(shape)))
	parts.append(_meta(node))
	return " | ".join(parts)


func _shape(shape: Shape3D) -> String:
	if shape == null:
		return "none"
	if shape is BoxShape3D:
		return "box %s" % _vec((shape as BoxShape3D).size)
	return shape.get_class()


func _mesh(mesh: Mesh) -> String:
	if mesh == null:
		return "none"
	var aabb: AABB = mesh.get_aabb()
	var text: String = "%s aabb(%s %s) surfaces=%d" % [
		mesh.get_class(), _vec(aabb.position), _vec(aabb.size), mesh.get_surface_count()]
	if mesh is ArrayMesh:
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var total := Vector3.ZERO
			for vertex: Vector3 in vertices:
				total += vertex
			text += " [verts=%d sum(%s)]" % [vertices.size(), _vec(total)]
	return text


func _meta(node: Node) -> String:
	var entries: Array[String] = []
	for key: StringName in node.get_meta_list():
		entries.append("%s=%s" % [key, _variant(node.get_meta(key))])
	entries.sort()
	return "meta{%s}" % ",".join(entries)


func _describe_mood(mood: Object) -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in mood.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and not (property.name as String).begins_with("_"):
			result[property.name] = mood.get(property.name)
	return result


func _planned(planned: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in planned:
		var value: Variant = planned[key]
		result[key] = (value as Script).resource_path.get_file() if value is Script else value
	return result


func _sign_queries(route: Node3D, house_count: int, lines: PackedStringArray) -> void:
	for index: int in range(house_count + 2):
		lines.append("stop_road_distance(%d)=%s" % [index, _num(route.call(&"stop_road_distance", index))])
	var points: Array[Vector3] = route.get(&"_path_points")
	var offsets: Array[Vector3] = [
		Vector3.ZERO, Vector3(8.0, 0.0, 0.0), Vector3(-13.0, 2.0, 5.0), Vector3(0.0, 0.0, 30.0)]
	var checked: int = 0
	for index: int in range(0, points.size(), 7):
		for offset: Vector3 in offsets:
			var world: Vector3 = route.to_global(points[index] + offset)
			lines.append("q %d %s p=%s r=%s d=%s s=%s g=%s" % [
				index, _vec(offset),
				_num(route.call(&"get_progress", world)), _num(route.call(&"road_distance", world)),
				_num(route.call(&"distance_from_path", world)), route.call(&"get_section_name", world),
				_num(route.call(&"ground_roughness", world))])
			checked += 1
	# A grid over the whole route's footprint, far from the road as well, and a few jumps back.
	var low := Vector3(INF, 0.0, INF)
	var high := Vector3(-INF, 0.0, -INF)
	for point: Vector3 in points:
		low = Vector3(minf(low.x, point.x), 0.0, minf(low.z, point.z))
		high = Vector3(maxf(high.x, point.x), 0.0, maxf(high.z, point.z))
	var steps: int = 9
	for ix: int in range(steps + 1):
		for iz: int in range(steps + 1):
			var local := Vector3(lerpf(low.x - 40.0, high.x + 40.0, float(ix) / steps), 0.0,
				lerpf(low.z - 40.0, high.z + 40.0, float(iz) / steps))
			var world: Vector3 = route.to_global(local)
			lines.append("grid %d,%d p=%s r=%s d=%s s=%s g=%s" % [
				ix, iz, _num(route.call(&"get_progress", world)), _num(route.call(&"road_distance", world)),
				_num(route.call(&"distance_from_path", world)), route.call(&"get_section_name", world),
				_num(route.call(&"ground_roughness", world))])
			checked += 1
	lines.append("queries=%d" % checked)


# --- formatting --------------------------------------------------------------------------------

func _digest(values: Array) -> String:
	var parts := PackedStringArray()
	for value: Variant in values:
		parts.append(_variant(value))
	return "n=%d hash=%s" % [values.size(), "\n".join(parts).sha1_text().substr(0, 12)]


func _variant(value: Variant) -> String:
	var text: String = str(value)
	match typeof(value):
		TYPE_FLOAT:
			text = _num(value)
		TYPE_VECTOR2:
			text = "(%s, %s)" % [_num((value as Vector2).x), _num((value as Vector2).y)]
		TYPE_VECTOR3:
			text = "(%s)" % _vec(value)
		TYPE_COLOR:
			var color: Color = value
			text = "c(%s,%s,%s,%s)" % [_num(color.r), _num(color.g), _num(color.b), _num(color.a)]
		TYPE_RECT2:
			var rect: Rect2 = value
			text = "rect(%s, %s)" % [_variant(rect.position), _variant(rect.size)]
		TYPE_TRANSFORM3D:
			text = _xform(value)
		TYPE_DICTIONARY:
			text = _dictionary(value)
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR2_ARRAY:
			var parts: Array[String] = []
			for item: Variant in value:
				parts.append(_variant(item))
			text = "[%s]" % ", ".join(parts)
		TYPE_OBJECT:
			text = "obj"
	return text


func _dictionary(dictionary: Dictionary) -> String:
	var keys: Array = dictionary.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	var parts: Array[String] = []
	for key: Variant in keys:
		parts.append("%s: %s" % [str(key), _variant(dictionary[key])])
	return "{%s}" % ", ".join(parts)


func _xform(value: Transform3D) -> String:
	return "pos(%s) basis(%s %s %s)" % [
		_vec(value.origin), _vec(value.basis.x), _vec(value.basis.y), _vec(value.basis.z)]


func _vec(value: Vector3) -> String:
	return "%s %s %s" % [_num(value.x), _num(value.y), _num(value.z)]


func _num(value: float) -> String:
	var text: String = "%.4f" % value
	return "0.0000" if text == "-0.0000" else text


# --- golden file -------------------------------------------------------------------------------

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
	for index: int in range(mini(expected.size(), actual.size())):
		if expected[index] != actual[index] and shown < 15:
			shown += 1
			_expect(false, "Line %d differs:\n  expected: %s\n  actual:   %s" % [
				index + 1, expected[index].left(400), actual[index].left(400)])
	_expect(false, "The route differs from the golden (%d lines expected, got %d)" % [expected.size(), actual.size()])
	if not OS.get_environment("GITHUB_ACTIONS").is_empty():
		_print_for_ci(text)


## On CI (Linux, the platform the golden is written on) a mismatch prints the
## whole new signature, gzip + base64 in GOLDEN_CHUNK_SIZE pieces that fit in
## the failure's log tail, so a route that is meant to change can be
## regenerated from a Windows PC: join the "GOLDEN_GZ i/n " lines of the run's
## log in order, base64-decode and gunzip them into tests/data/route_golden.txt.
func _print_for_ci(text: String) -> void:
	var packed: String = Marshalls.raw_to_base64(text.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP))
	var count: int = ceili(float(packed.length()) / GOLDEN_CHUNK_SIZE)
	for index: int in range(count):
		print("GOLDEN_GZ %d/%d %s" % [index + 1, count, packed.substr(index * GOLDEN_CHUNK_SIZE, GOLDEN_CHUNK_SIZE)])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

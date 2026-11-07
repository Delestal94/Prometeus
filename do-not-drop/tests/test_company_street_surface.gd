extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_street_surface.gd
##
## The company map's streets are drawn with their surface, not with flat colour boxes (expansion
## D-0304.1b, N-323): StreetSurface (scripts/gameplay/districts/street_surface.gd) and
## shaders/street_surface.gdshader, put on every piece EdgePieces.build_piece() makes.
## - material(): one shared ShaderMaterial per surface (asking twice gives the same one), with the street
##   shader, the shader's `surface` index of each (asphalt 0, gravel 1, dirt 2, cobble 3, verge 4) and the
##   terrain's detail maps; an unknown surface is drawn as asphalt.
## - surface_of(): a GravelSegment is gravel on any street; any other piece takes its street's surface.
## - EdgePieces.plan() carries the street's RoadEdge.surface in every piece.
## - Four real streets built as a cell builds them (avenida_este_1 asphalt, camino_campo_3 gravel with
##   curves and bridges, chacra_1 dirt with mud and gravel patches, calle_v_640_m384 cobble): no mesh is left
##   in RouteSegment.ROAD, SHOULDER or GravelSegment.GRAVEL (every roadway and verge box is dressed, a
##   curve's chords too); every straight piece's roadway is its street's surface, every GravelSegment's is
##   gravel, the verge is the verge; lane lines are visible only on the asphalt street; the roadway's
##   collision is untouched (StraightSegment's `Road` still a 12 x 0.4 m box).
## - A world cell (EdgeCellContent.build_cell) is built out of the tree: its cobble pieces are dressed
##   once the cell enters the tree (the deferred path of StreetSurface.dress()).
## - Crossings: every surface is drawn over the box by its own height (StreetSurface.LIFT, the shader's
##   `lift`), asphalt over cobble over gravel over dirt, by more than the shader's lift_by_heading, and
##   all of it stays under the lowest lane line, so a crossing shows one surface and the lines still show.
##   tests/render_company_edges.gd's `junction` views are how it looks; this is what keeps it so.
## - chacra_8's rail crossing keeps its two CrossingStopLine on gravel: they are not lane lines.
## - The grip follows the drawn surface: every piece of a gravel or dirt street has a GripArea of the
##   surface's slip (gravel's is GravelSegment's) except a GravelSegment and a MudSegment, which bring their
##   own, and a bridge, whose deck is not the street's; asphalt and cobble have none. A vehicle on the last
##   chord of a gravel street's curve (real physics) drops to that slip, on the bridge it does not, and it
##   gets its grip back when the piece is freed. So do the footsteps and the trip: a roadway or verge body
##   tells GelPlayerAudio its surface and PlayerSprint its roughness.

const SHADER_PATH: String = "res://shaders/street_surface.gdshader"
const STREETS: Dictionary = {
	&"avenida_este_1": &"asphalt", &"camino_campo_3": &"gravel", &"chacra_1": &"dirt",
	&"calle_v_640_m384": &"cobble", &"chacra_8": &"gravel",
}
const CELL_SIZE: float = 256.0
## The flat colours RouteSegment draws a roadway and its verge with.
const FLAT: Array[Color] = [RouteSegment.ROAD, RouteSegment.SHOULDER, GravelSegment.GRAVEL]
## The lane lines, by the names the pieces give them. Not StreetSurface's own list: this is what it must catch.
const LANE_LINES: Array[String] = ["EdgeMarking", "CenterMarking", "EdgeLine"]
const SPRINT: GDScript = preload("res://scripts/gameplay/player/player_sprint.gd")
## What each surface sounds like underfoot.
const SOUNDS: Dictionary = {
	&"asphalt": SynthAudioGel.Surface.ROAD, &"cobble": SynthAudioGel.Surface.ROAD,
	&"gravel": SynthAudioGel.Surface.GRAVEL, &"dirt": SynthAudioGel.Surface.SOFT,
}
## A vehicle's wheels before any zone (vehicle.tscn).
const WHEEL_SLIP: float = 3.5

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var graph: RoadGraph = RoadGraph.load_default()
	_check_materials()
	_check_surface_of()
	_check_plan(graph)
	for street: StringName in STREETS:
		await _check_street(graph, street, STREETS[street])
	await _check_cell(graph)
	await _check_lift(graph)
	await _check_stop_lines(graph)
	await _check_grip_zones(graph)
	await _check_grip_physics(graph)
	if _failures == 0:
		print("PASS: the company streets are drawn with their surface (asphalt, gravel, dirt, cobble) and a verge,"
			+ " with lane lines only on asphalt")
	quit(_failures)


func _check_materials() -> void:
	var indices: Dictionary = {&"asphalt": 0, &"gravel": 1, &"dirt": 2, &"cobble": 3, StreetSurface.VERGE: 4}
	for surface: StringName in indices:
		var made: ShaderMaterial = StreetSurface.material(surface)
		_expect(made != null and made.shader != null and made.shader.resource_path == SHADER_PATH,
			"%s is drawn by street_surface.gdshader" % surface)
		var index: Variant = made.get_shader_parameter(&"surface")
		_expect(int(index) == indices[surface],
			"%s is the shader's surface %d (got %s)" % [surface, indices[surface], index])
		_expect(StreetSurface.material(surface) == made, "%s's material is shared, not made again" % surface)
	var asphalt: ShaderMaterial = StreetSurface.material(&"asphalt")
	for detail: String in StreetSurface.DETAILS:
		_expect(asphalt.get_shader_parameter(StringName(detail + "_detail")) is Texture2D,
			"The material reads the terrain's %s detail map" % detail)
	_expect(StreetSurface.material(&"lava") == asphalt, "An unknown surface is drawn as asphalt")


func _check_surface_of() -> void:
	var gravel := GravelSegment.new()
	var straight := StraightSegment.new()
	_expect(StreetSurface.surface_of(gravel, &"dirt") == &"gravel", "A gravel patch on a dirt track is gravel")
	_expect(StreetSurface.surface_of(gravel, &"asphalt") == &"gravel", "...and on any street")
	_expect(StreetSurface.surface_of(straight, &"dirt") == &"dirt", "A straight piece takes its street's surface")
	_expect(StreetSurface.surface_of(straight, &"cobble") == &"cobble", "...cobble too")
	_expect(StreetSurface.surface_of(straight, &"sand") == &"asphalt", "...and asphalt when the surface is unknown")
	gravel.free()
	straight.free()


func _check_plan(graph: RoadGraph) -> void:
	for street: StringName in STREETS:
		var pieces: Array[Dictionary] = EdgePieces.plan(graph, street)
		var all_same: bool = not pieces.is_empty()
		for piece: Dictionary in pieces:
			all_same = all_same and piece.get("surface", &"") == STREETS[street]
		_expect(all_same, "Every piece of %s carries the street's surface %s" % [street, STREETS[street]])


func _check_street(graph: RoadGraph, street: StringName, surface: StringName) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var built: Array[RouteSegment] = EdgePieces.build(graph, street, holder)
	await process_frame
	var road: ShaderMaterial = StreetSurface.material(surface)
	var verge: ShaderMaterial = StreetSurface.material(StreetSurface.VERGE)
	var flat: int = 0
	var lines: int = 0
	var bad_road: PackedStringArray = []
	var curves: int = 0
	var verges: int = 0
	for segment: RouteSegment in built:
		var expected: ShaderMaterial = StreetSurface.material(&"gravel") if segment is GravelSegment else road
		var dressed_road: int = 0
		var dressed_verge: int = 0
		for mesh: MeshInstance3D in _meshes(segment):
			var paint := mesh.material_override as StandardMaterial3D
			if paint != null and paint.albedo_color in FLAT and mesh.is_visible_in_tree():
				flat += 1
			if _is_lane_line(mesh) and mesh.is_visible_in_tree():
				lines += 1
			if mesh.material_override == expected:
				dressed_road += 1
			elif mesh.material_override == verge:
				dressed_verge += 1
		if segment is CurveSegment:
			curves += 1
		verges += dressed_verge
		# A MudSegment's roadway is its own mud (mud_ground.gdshader).
		if not (segment is MudSegment) and dressed_road == 0:
			bad_road.append((segment.get_script() as Script).resource_path.get_file())
	_expect(flat == 0, "%s: no flat colour roadway or verge box is left (got %d)" % [street, flat])
	_expect(bad_road.is_empty(), "%s: every piece's roadway is %s, a gravel patch's gravel (not: %s)"
		% [street, surface, bad_road])
	_expect(verges >= built.size() / 2, "%s: the ground either side is the verge (%d boxes for %d pieces)"
		% [street, verges, built.size()])
	if street == &"camino_campo_3":
		_expect(curves > 0, "camino_campo_3 has curves, whose chords are dressed too (got %d)" % curves)
	if surface == &"asphalt":
		_expect(lines > 0, "%s keeps its lane lines (got %d)" % [street, lines])
		var body := built[0].get_node_or_null(^"Road") as StaticBody3D
		var shape: BoxShape3D = null
		if body != null:
			for child: Node in body.get_children():
				if child is CollisionShape3D:
					shape = (child as CollisionShape3D).shape as BoxShape3D
		_expect(shape != null and shape.size.is_equal_approx(Vector3(12.0, 0.4, built[0].length)),
			"The roadway's collision is untouched: a 12 x 0.4 m box (got %s)" % (shape.size if shape != null else null))
	else:
		_expect(lines == 0, "%s (%s) shows no lane lines (got %d)" % [street, surface, lines])
	holder.queue_free()
	await process_frame


func _check_cell(graph: RoadGraph) -> void:
	var content := EdgeCellContent.new(graph, CELL_SIZE)
	var cell: Vector2i = content.cell_of(Vector3(640.0, 0.0, -200.0))
	var node: Node3D = content.build_cell(cell)
	var cobble: ShaderMaterial = StreetSurface.material(&"cobble")
	var pieces: int = 0
	var dressed: int = 0
	root.add_child(node)
	await process_frame
	for child: Node in node.get_children():
		if not String(child.name).begins_with("calle_v_640_m384_"):
			continue
		pieces += 1
		for mesh: MeshInstance3D in _meshes(child):
			if mesh.material_override == cobble:
				dressed += 1
				break
	_expect(pieces > 0, "Cell %s holds pieces of the cobbled calle_v_640_m384 (got %d)" % [cell, pieces])
	_expect(dressed == pieces, "Built out of the tree, they are cobble once the cell is in it (%d of %d)"
		% [dressed, pieces])
	node.queue_free()
	await process_frame


func _check_lift(graph: RoadGraph) -> void:
	var shader_code: String = (load(SHADER_PATH) as Shader).code
	var matched: RegExMatch = RegEx.create_from_string("lift_by_heading[^=\\n]*= *([0-9.]+)").search(shader_code)
	_expect(matched != null, "The shader says how much the heading adds to the lift")
	var by_heading: float = matched.get_string(1).to_float() if matched != null else 0.0
	var order: Array[StringName] = [&"dirt", &"gravel", &"cobble", &"asphalt"]
	var below: float = 0.0
	for surface: StringName in order:
		var lift: float = StreetSurface.material(surface).get_shader_parameter(&"lift")
		_expect(lift - below > by_heading, "%s is drawn over the one below by more than the heading adds (%.3f, %.3f)"
			% [surface, lift, below])
		below = lift
	_expect(is_zero_approx(float(StreetSurface.material(StreetSurface.VERGE).get_shader_parameter(&"lift"))),
		"The verge is not lifted: it is 30 cm under the roadway already")
	var holder := Node3D.new()
	root.add_child(holder)
	var built: Array[RouteSegment] = EdgePieces.build(graph, &"avenida_este_1", holder)
	await process_frame
	var lowest: float = INF
	for segment: RouteSegment in built:
		for mesh: MeshInstance3D in _meshes(segment):
			var box := mesh.mesh as BoxMesh
			if box != null and _is_lane_line(mesh):
				lowest = minf(lowest, (mesh.get_parent() as Node3D).position.y - box.size.y * 0.5)
	_expect(lowest < INF and below + by_heading < lowest,
		"The top surface (%.3f + %.3f) stays under the lowest lane line (%.3f)" % [below, by_heading, lowest])
	holder.queue_free()
	await process_frame


func _check_stop_lines(graph: RoadGraph) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var built: Array[RouteSegment] = EdgePieces.build(graph, &"chacra_8", holder)
	await process_frame
	var crossings: int = 0
	var shown: int = 0
	for segment: RouteSegment in built:
		if segment is RailCrossingSegment:
			crossings += 1
		for mesh: MeshInstance3D in _meshes(segment):
			if "CrossingStopLine" in String(mesh.get_parent().name) and mesh.is_visible_in_tree():
				shown += 1
	_expect(crossings > 0 and shown == crossings * 2,
		"Each of chacra_8's %d rail crossings shows both its stop lines on gravel (got %d)" % [crossings, shown])
	holder.queue_free()
	await process_frame


func _check_grip_zones(graph: RoadGraph) -> void:
	var patch := GravelSegment.new()
	_expect(is_equal_approx(StreetSurface.GRIP[&"gravel"], patch.reduced_friction_slip),
		"A gravel street holds like a gravel patch")
	patch.free()
	for street: StringName in STREETS:
		var holder := Node3D.new()
		root.add_child(holder)
		var built: Array[RouteSegment] = EdgePieces.build(graph, street, holder)
		await process_frame
		var surface: StringName = STREETS[street]
		var wrong: PackedStringArray = []
		for segment: RouteSegment in built:
			var area := segment.get_node_or_null(NodePath(StreetSurface.GRIP_NODE)) as GripArea
			var own: bool = segment is GravelSegment or segment is MudSegment
			var wanted: bool = StreetSurface.GRIP.has(surface) and not own and not (segment is NarrowBridgeSegment)
			var kind: String = (segment.get_script() as Script).resource_path.get_file()
			var slip_ok: bool = area == null or is_equal_approx(area.slip, StreetSurface.GRIP[surface])
			if wanted != (area != null) or not slip_ok:
				wrong.append(kind)
			_check_underfoot(segment, surface, wrong)
		_expect(wrong.is_empty(), "%s (%s): every piece grips and sounds like what is drawn (not: %s)"
			% [street, surface, wrong])
		holder.queue_free()
		await process_frame


## The roadway and verge bodies of `segment` say what they are to the footsteps and the trip.
func _check_underfoot(segment: RouteSegment, street_surface: StringName, wrong: PackedStringArray) -> void:
	var drawn: StringName = StreetSurface.surface_of(segment, street_surface)
	var road: StaticBody3D = segment.get_node_or_null(^"Road") as StaticBody3D
	if road != null:
		var sound: int = SOUNDS[&"dirt" if segment is MudSegment else drawn]
		if GelPlayerAudio._surface_from_collider(road) != sound:
			wrong.append("sound of %s" % drawn)
		var rough: float = float(SPRINT.roughness_of(road))
		var want_rough: bool = drawn == &"gravel" or drawn == &"dirt" or drawn == &"cobble"
		if want_rough != (rough > 0.0):
			wrong.append("roughness %.2f of %s" % [rough, drawn])
	var ground: StaticBody3D = segment.get_node_or_null(^"Ground") as StaticBody3D
	if ground != null and GelPlayerAudio._surface_from_collider(ground) != SynthAudioGel.Surface.SOFT:
		wrong.append("sound of the verge")


## A vehicle on the far end of a curve (past where a straight box of the piece would reach) and on a bridge.
func _check_grip_physics(graph: RoadGraph) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var built: Array[RouteSegment] = EdgePieces.build(graph, &"camino_campo_3", holder)
	await process_frame
	var curve: RouteSegment = null
	var bridge: RouteSegment = null
	for segment: RouteSegment in built:
		if segment is CurveSegment and curve == null:
			curve = segment
		elif segment is NarrowBridgeSegment and bridge == null:
			bridge = segment
	var vehicle := VehicleBody3D.new()
	vehicle.collision_layer = 2
	vehicle.collision_mask = 0
	vehicle.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	vehicle.freeze = true
	vehicle.add_to_group(&"vehicle")
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	vehicle.add_child(shape)
	var wheel := VehicleWheel3D.new()
	wheel.wheel_friction_slip = WHEEL_SLIP
	vehicle.add_child(wheel)
	root.add_child(vehicle)

	vehicle.global_position = bridge.global_transform * Vector3(0.0, 0.5, -bridge.length * 0.5)
	await _physics(4)
	_expect(is_equal_approx(wheel.wheel_friction_slip, WHEEL_SLIP),
		"On a gravel street's bridge the wheels hold as ever (got %.2f)" % wheel.wheel_friction_slip)
	var far_chord := Vector3.ZERO
	var far_away: float = -1.0
	for mesh: MeshInstance3D in _meshes(curve):
		var box := mesh.mesh as BoxMesh
		if box != null and is_equal_approx(box.size.x, 12.0):
			var at: Vector3 = mesh.global_position
			if at.distance_to(curve.global_position) > far_away:
				far_away = at.distance_to(curve.global_position)
				far_chord = at
	vehicle.global_position = far_chord + Vector3.UP * 0.5
	await _physics(4)
	_expect(is_equal_approx(wheel.wheel_friction_slip, StreetSurface.GRIP[&"gravel"]),
		"On the curve's last chord the wheels hold like gravel (got %.2f)" % wheel.wheel_friction_slip)
	curve.free()
	await _physics(2)
	_expect(is_equal_approx(wheel.wheel_friction_slip, WHEEL_SLIP),
		"A freed piece gives the wheels back (got %.2f)" % wheel.wheel_friction_slip)
	vehicle.queue_free()
	holder.queue_free()
	await process_frame


func _physics(frames: int) -> void:
	for _i: int in frames:
		await physics_frame


## A line a piece paints: a model's own (a bridge deck's edge lines, in its .glb) is part of the model.
func _is_lane_line(mesh: MeshInstance3D) -> bool:
	if mesh.material_override == null:
		return false
	var names: String = String(mesh.name) + "/" + String(mesh.get_parent().name)
	return LANE_LINES.any(func(line: String) -> bool: return line in names)


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var next: Node = pending.pop_back()
		pending.append_array(next.get_children())
		if next is MeshInstance3D:
			found.append(next as MeshInstance3D)
	return found


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

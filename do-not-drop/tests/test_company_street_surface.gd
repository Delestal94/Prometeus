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

const SHADER_PATH: String = "res://shaders/street_surface.gdshader"
const STREETS: Dictionary = {
	&"avenida_este_1": &"asphalt", &"camino_campo_3": &"gravel", &"chacra_1": &"dirt",
	&"calle_v_640_m384": &"cobble",
}
const CELL_SIZE: float = 256.0
## The flat colours RouteSegment draws a roadway and its verge with.
const FLAT: Array[Color] = [RouteSegment.ROAD, RouteSegment.SHOULDER, GravelSegment.GRAVEL]

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
			if StreetSurface.is_line(mesh) and mesh.is_visible_in_tree():
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

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_street_batch.gd
##
## The company map's street pieces drawn as a few meshes per world cell (expansion D-2012.2): StreetBatcher
## (scripts/gameplay/districts/street_batcher.gd, over StaticMerger of modules/render_budget), run by
## CompanyCells as the streamer's second pass (WorldCellStreamer.finish_for).
## - Real cells (EdgeCellContent on data/world/road_graph.tres): (-1, 4) of the Camino del Campo (curves,
##   s-curves, the narrow bridges, gravel; the most nodes of the map) and (2, 0) of Centro (speed bumps, chicanes,
##   straights). Baked, each keeps under a quarter of its nodes (the shed's default view went from 15.2k nodes to
##   about 5k), and every piece is still there, a RouteSegment where it was, with its `Road` body.
## - Nothing to drive, walk or hear changes: a grid of rays down over every piece hits the same height, a body on
##   the same layer, with the same footstep surface and roughness (StreetSurface.UNDERFOOT), before and after; the
##   cell keeps every GripArea (the slip of a gravel or dirt street, D-0304).
## - What is drawn: a `Streets` mesh with a surface per street surface, each with StreetSurface.batched_material()
##   (the street shader with `batched` on); no mesh is left with an unbatched street material; one `Verge` body
##   holds the verge boxes' shapes.
## - In steps (StreetBatcher.start() / step() with a small budget, as the streamer runs it) the cell comes out the
##   same as baked at once, in more than one step.
## - Through CompanyCells: a streamed cell is not drawn until its bake is done, then it is, baked; warm_pieces()
##   builds and bakes one piece of every kind and leaves nothing behind; its pieces run under a MultiplayerAPI of
##   their own with no peers (a client's mud piece would otherwise ask the host for its state from a path no peer
##   has), and the tree's API is back afterwards.
## - The houses' small parts get a draw range (WorldQuality.set_view_range): the doorbell panel's and the waiting
##   marker's mailbox, sign text and porch bulb, the sign's legs and the balloon's string; the sign's boards and the
##   balloon itself have none.

const CELL_SIZE: float = 256.0
const CAMPO: Vector2i = Vector2i(-1, 4)
const CENTRO: Vector2i = Vector2i(2, 0)
## The share of a cell's nodes a bake may leave.
const MAX_LEFT: float = 0.25
## Sideways offsets of the rays over a piece (m): the roadway (12 m wide) and the verge (24 m).
const LATERAL: Array[float] = [-10.5, -7.0, -3.0, 0.0, 3.0, 7.0, 10.5]
const ALONG_STEPS: int = 6

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var graph: RoadGraph = RoadGraph.load_default()
	StreetSurface.warm()
	var content := EdgeCellContent.new(graph, CELL_SIZE, 0, false, null)
	for cell: Vector2i in [CAMPO, CENTRO]:
		await _check_bake(content, cell)
	await _check_steps(content)
	await _check_streamed(graph)
	await _check_house_ranges()
	if _failures == 0:
		print("PASS: a world cell's street pieces are drawn as a few meshes, with the same collision, grip and sound")
	quit(_failures)


func _built(content: EdgeCellContent, cell: Vector2i) -> Node3D:
	var node: Node3D = content.build_cell(cell)
	root.add_child(node)
	return node


func _count(node: Node) -> int:
	return node.find_children("*", "", true, false).size()


## Every piece's name and global transform.
func _pieces(cell: Node3D) -> Dictionary:
	var out: Dictionary = {}
	for child: Node in cell.get_children():
		if child is RouteSegment:
			out[String(child.name)] = (child as Node3D).global_transform
	return out


## What a ray straight down finds over every piece: "height|layer|audio|roughness" per ray, or "miss".
func _ground(cell: Node3D) -> Array[String]:
	var space: PhysicsDirectSpaceState3D = cell.get_world_3d().direct_space_state
	var out: Array[String] = []
	for child: Node in cell.get_children():
		var piece := child as RouteSegment
		if piece == null:
			continue
		for step: int in ALONG_STEPS + 1:
			var along: float = -piece.length * (0.05 + 0.9 * float(step) / ALONG_STEPS)
			for x: float in LATERAL:
				var top: Vector3 = piece.global_transform * Vector3(x, 30.0, along)
				var query := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 60.0)
				query.collide_with_areas = false
				var hit: Dictionary = space.intersect_ray(query)
				if hit.is_empty():
					out.append("miss")
					continue
				var body := hit.collider as CollisionObject3D
				out.append("%.3f|%d|%s|%s" % [(hit.position as Vector3).y, body.collision_layer,
					body.get_meta(StreetSurface.AUDIO_META, &"-"), body.get_meta(StreetSurface.ROUGHNESS_META, -1.0)])
	return out


func _grips(cell: Node3D) -> int:
	return cell.find_children("*", "GripArea", true, false).size()


func _physics() -> void:
	for i in 3:
		await physics_frame


func _check_bake(content: EdgeCellContent, cell: Vector2i) -> void:
	var node: Node3D = _built(content, cell)
	await _physics()
	var before: int = _count(node)
	var pieces: Dictionary = _pieces(node)
	var ground: Array[String] = _ground(node)
	var grips: int = _grips(node)
	_expect(ground.count("miss") * 4 < ground.size(), "Cell %s: the rays find its ground (%d of %d miss)"
		% [cell, ground.count("miss"), ground.size()])
	_expect(pieces.size() > 3 and before > 200, "Cell %s has street pieces to bake (%d pieces, %d nodes)"
		% [cell, pieces.size(), before])
	var result: Dictionary = StreetBatcher.bake(node)
	await _physics()
	var after: int = _count(node)
	_expect(after <= before * MAX_LEFT, "Cell %s keeps under a quarter of its nodes baked (%d -> %d)"
		% [cell, before, after])
	_expect(int(result.get("pieces", 0)) == pieces.size(), "...every piece is baked (%s)" % [result])
	var still: Dictionary = _pieces(node)
	var moved: int = 0
	for name: String in pieces:
		if not still.has(name) or not (still[name] as Transform3D).is_equal_approx(pieces[name]):
			moved += 1
	_expect(moved == 0 and still.size() == pieces.size(), "...every piece is still there, where it was (%d moved)"
		% moved)
	var roads: int = 0
	for child: Node in node.get_children():
		if child is RouteSegment and child.get_node_or_null(^"Road") is StaticBody3D:
			roads += 1
	_expect(roads > 0, "...the pieces keep their `Road` body (%d)" % roads)
	var now: Array[String] = _ground(node)
	var differ: int = 0
	var example: String = ""
	for index: int in mini(ground.size(), now.size()):
		if ground[index] != now[index]:
			differ += 1
			if example.is_empty():
				example = "%s became %s" % [ground[index], now[index]]
	_expect(ground.size() == now.size() and differ == 0,
		"Cell %s: every ray down hits the same ground, body layer, sound and roughness (%d of %d differ: %s)"
		% [cell, differ, ground.size(), example])
	_expect(_grips(node) == grips, "...and keeps its %d GripArea (got %d)" % [grips, _grips(node)])
	var streets := node.get_node_or_null(NodePath(String(StreetBatcher.STREETS_NAME))) as MeshInstance3D
	_expect(streets != null and streets.mesh != null and streets.mesh.get_surface_count() > 0,
		"Cell %s draws its roadways and verges as one `Streets` mesh" % cell)
	if streets != null and streets.mesh != null:
		for surface: int in streets.mesh.get_surface_count():
			var drawn := streets.mesh.surface_get_material(surface) as ShaderMaterial
			_expect(drawn != null and drawn.get_shader_parameter(&"batched") == true,
				"...each surface with the batched street material (surface %d)" % surface)
	var unbatched: int = 0
	for part: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := part as MeshInstance3D
		if mesh.material_override != null and StreetSurface.surface_drawn_by(mesh.material_override) != &"":
			unbatched += 1
	_expect(unbatched == 0, "...and no box is left with its own street material (%d)" % unbatched)
	var verge := node.get_node_or_null(NodePath(String(StreetBatcher.VERGE_NAME))) as StaticBody3D
	_expect(verge != null and verge.get_shape_owners().size() == int(result.get("verges", -1)),
		"...and one `Verge` body with a shape per verge box (%s)" % [result])
	node.free()


func _check_steps(content: EdgeCellContent) -> void:
	var whole: Node3D = _built(content, CAMPO)
	await process_frame
	StreetBatcher.bake(whole)
	var at_once: int = _count(whole)
	whole.free()
	var stepped: Node3D = _built(content, CAMPO)
	await process_frame
	var baker: StreetBatcher = StreetBatcher.start(stepped)
	var steps: int = 0
	while baker != null and not baker.step(0) and steps < 10000:
		steps += 1
	_expect(baker != null and steps > 1, "A bake in steps of no budget takes a branch a step (%d steps)" % steps)
	_expect(_count(stepped) == at_once, "...and leaves the same cell as one bake (%d, at once %d)"
		% [_count(stepped), at_once])
	_expect(StreetBatcher.start(Node3D.new()) == null, "A holder with no piece has nothing to bake")
	stepped.free()


func _check_streamed(graph: RoadGraph) -> void:
	var cells := CompanyCells.new()
	root.add_child(cells)
	cells.set_process(false)
	cells.use_graph(graph)
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var seen := {"pieces": 0, "shared": 0}
	var tree_api: MultiplayerAPI = get_multiplayer()
	var on_added := func(added: Node) -> void:
		if added is RouteSegment and String(added.get_path()).contains("/WarmPieces/"):
			seen.pieces += 1
			if added.multiplayer == tree_api or not added.multiplayer.get_peers().is_empty():
				seen.shared += 1
	node_added.connect(on_added)
	var warmed: int = cells.warm_pieces()
	node_added.disconnect(on_added)
	_expect(warmed >= 5, "warm_pieces builds a piece of every kind (%d)" % warmed)
	_expect(cells.get_node_or_null(^"WarmPieces") == null
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphans,
		"...and leaves nothing behind")
	_expect(seen.pieces == warmed and seen.shared == 0,
		"...its pieces run under an API of their own with no peers, so no RPC leaves (%d of %d shared)"
		% [seen.shared, seen.pieces])
	_expect(get_multiplayer(NodePath(String(cells.get_path()) + "/WarmPieces")) == tree_api,
		"...and the tree's API is back for that path afterwards")
	var anchors: Array[Vector3] = [Vector3(CENTRO.x * CELL_SIZE + 128.0, 0.0, CENTRO.y * CELL_SIZE + 128.0)]
	cells.anchors = anchors
	var now: float = 0.0
	var seen_hidden: bool = false
	var steps: int = 0
	while steps < 4000:
		now += 1.0 / 60.0
		cells.step(now)
		steps += 1
		var node: Node3D = cells.cell_node(CENTRO)
		if node != null and not cells.is_finished(CENTRO):
			seen_hidden = seen_hidden or not node.visible
			_expect(not node.visible, "A streamed cell is not drawn before its bake is done")
		if node != null and cells.is_finished(CENTRO) and not cells.is_busy():
			break
		await process_frame
	var cell: Node3D = cells.cell_node(CENTRO)
	_expect(cell != null and cells.is_finished(CENTRO) and seen_hidden,
		"The streamer bakes the cell (%d steps)" % steps)
	if cell != null:
		_expect(cell.visible and cell.get_node_or_null(NodePath(String(StreetBatcher.STREETS_NAME))) != null,
			"...and draws it, baked, once it is done")
		_expect(cells.longest_finish_usec > 0, "...in the streamer's second pass")
	cells.free()


func _check_house_ranges() -> void:
	var marker := HouseWaitingMarker.new()
	root.add_child(marker)
	var ranged: Array[Node] = []
	var unranged: Array[Node] = []
	for part: Node in marker.find_children("*", "GeometryInstance3D", true, false):
		if part.has_meta(WorldQuality.BASE_RANGE_META):
			ranged.append(part)
		else:
			unranged.append(part)
	var names: Array[String] = []
	for part: Node in unranged:
		names.append("%s/%s" % [part.get_parent().name, part.name])
	_expect(marker.get_node(^"PorchBulb").has_meta(WorldQuality.BASE_RANGE_META)
			and marker.number_label.has_meta(WorldQuality.BASE_RANGE_META)
			and marker.code_label.has_meta(WorldQuality.BASE_RANGE_META),
		"The porch bulb, the mailbox's number and the sign's code have a draw range")
	_expect(not marker.get_node(^"Balloon/BalloonBall").has_meta(WorldQuality.BASE_RANGE_META)
			and not marker.get_node(^"PorchGlow").has_meta(WorldQuality.BASE_RANGE_META),
		"The balloon and the porch glow, what says \"this one\" from afar, have none")
	# Left without a range: the balloon, the glow and the two boards; everything else of the marker has one.
	_expect(unranged.size() == 4, "Only the balloon, the glow and the sign's two boards draw at any distance (%s)"
		% [names])
	for part: Node in ranged:
		var range_end: float = (part as GeometryInstance3D).visibility_range_end
		_expect(range_end > 0.0 and is_equal_approx(range_end,
				float(part.get_meta(WorldQuality.BASE_RANGE_META)) * WorldQuality.setting("range_scale")),
			"%s is drawn up to its base range at this level (%.1f)" % [part.name, range_end])
	marker.free()
	var house := DeliveryHouse.new()
	root.add_child(house)
	var panel: Node = house.get_node_or_null(^"DoorbellPanel")
	var parts: Array[Node] = panel.find_children("*", "GeometryInstance3D", true, false) if panel != null else []
	var bare: int = 0
	for part: Node in parts:
		var base: float = float(part.get_meta(WorldQuality.BASE_RANGE_META, 0.0))
		if not is_equal_approx(base, DeliveryHouse.DOORBELL_VIEW_RANGE):
			bare += 1
	_expect(parts.size() >= 5 and bare == 0,
		"Every part of a house's doorbell panel is drawn up to %.0f m (%d of %d not)"
		% [DeliveryHouse.DOORBELL_VIEW_RANGE, bare, parts.size()])
	house.free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

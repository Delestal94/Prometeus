extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_edge_pieces.gd
##
## The pieces laid along the company map's streets (expansion D-0304.2,
## scripts/gameplay/districts/edge_pieces.gd on data/world/road_graph.tres):
## - the plan is deterministic and lists the street's kinds in order, repeating them;
## - the pieces start at the street's start, follow it with no gap larger than a
##   few meters and stop within MIN_FILL of its end; a piece that does not fit at the
##   end is a straight one cut to size;
## - each piece is set on the street and faces along it (yaw matches the tangent);
## - a `curve` piece takes the turn the street makes over its span;
## - Campo's streets lay their pieces (gravel, mud, curve, chicane...) and Centro's
##   differ from them, with a golden for one Campo street;
## - build() makes a RouteSegment per piece, placed where the plan says.

const MAX_GAP: float = 6.0
const GOLDEN_STREET: StringName = &"camino_campo_3"

var _failures: int = 0
var _graph: RoadGraph


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_graph = RoadGraph.load_default()
	_expect(_graph != null, "data/world/road_graph.tres loads")
	if _graph == null:
		quit(1)
		return
	_test_every_street()
	_test_kinds_and_zones()
	_test_curve_turn()
	_test_build()
	quit(_failures)


func _test_every_street() -> void:
	for edge: RoadEdge in _graph.edges:
		var pieces: Array[Dictionary] = EdgePieces.plan(_graph, edge.id)
		_expect(not pieces.is_empty(), "Street %s has pieces" % edge.id)
		_expect(EdgePieces.signature(pieces) == EdgePieces.signature(EdgePieces.plan(_graph, edge.id)),
				"Street %s plans the same twice" % edge.id)
		var length: float = _graph.edge_length(edge.id)
		var last: Dictionary = pieces[pieces.size() - 1]
		_expect(float(last.start) + float(last.advance) >= length - EdgePieces.MIN_FILL,
				"Street %s is covered to its end" % edge.id)
		_expect(pieces[0].start == 0.0 and (pieces[0].position as Vector2).distance_to(_graph.point_at(edge.id, 0.0)) < 0.01,
				"Street %s starts on its first node" % edge.id)
		for i in pieces.size():
			var piece: Dictionary = pieces[i]
			var facing: Vector2 = _graph.tangent_at(edge.id, piece.start)
			var forward := Vector2(-sin(float(piece.yaw)), -cos(float(piece.yaw)))
			_expect(forward.distance_to(facing) < 0.01, "Piece %d of %s faces along the street" % [i, edge.id])
			_expect(edge.segments.has(piece.kind), "Piece %d of %s is one of its kinds (%s)" % [i, edge.id, piece.kind])
			if i > 0:
				var gap: float = (piece.position as Vector2).distance_to(_graph.point_at(edge.id,
						float(pieces[i - 1].start) + float(pieces[i - 1].advance)))
				_expect(gap < MAX_GAP, "Pieces %d and %d of %s meet (gap %.1f m)" % [i - 1, i, edge.id, gap])
		# Kinds repeat in the order the data gives, except a last cut one.
		for i in pieces.size() - 1:
			_expect(pieces[i].kind == edge.segments[i % edge.segments.size()],
					"Piece %d of %s keeps the data's order" % [i, edge.id])


func _test_kinds_and_zones() -> void:
	var campo_kinds: Dictionary = {}
	var centro_kinds: Dictionary = {}
	for edge: RoadEdge in _graph.edges:
		for piece: Dictionary in EdgePieces.plan(_graph, edge.id):
			if edge.area == &"campo":
				campo_kinds[piece.kind] = true
			elif edge.area == &"centro":
				centro_kinds[piece.kind] = true
	_expect(campo_kinds.has(&"gravel") or campo_kinds.has(&"mud"), "Campo lays gravel or mud: %s" % [campo_kinds.keys()])
	_expect(not centro_kinds.has(&"mud"), "Centro lays no mud")
	_expect(campo_kinds.size() > centro_kinds.size() or campo_kinds.keys() != centro_kinds.keys(),
			"Campo and Centro do not lay the same kinds")
	var golden: String = EdgePieces.signature(EdgePieces.plan(_graph, GOLDEN_STREET))
	_expect(golden.begins_with("gravel:30,curve:"), "Golden street %s starts with gravel and a curve: %s" % [GOLDEN_STREET, golden])


func _test_curve_turn() -> void:
	var seen: int = 0
	for edge: RoadEdge in _graph.edges:
		for piece: Dictionary in EdgePieces.plan(_graph, edge.id):
			if piece.kind != &"curve":
				continue
			seen += 1
			var span_end: float = float(piece.start) + EdgePieces.CURVE_SPAN
			if span_end > _graph.edge_length(edge.id):
				continue
			var a: Vector2 = _graph.tangent_at(edge.id, piece.start)
			var b: Vector2 = _graph.tangent_at(edge.id, span_end - 0.5)
			_expect(absf(absf(float(piece.turn_deg)) - rad_to_deg(absf(a.angle_to(b)))) < 0.5,
					"Curve of %s turns what the street turns" % edge.id)
			_expect(is_equal_approx(float(piece.length), CurveSegment.length_for_turn(piece.turn_deg)),
					"Curve of %s has its own length" % edge.id)
	_expect(seen > 0, "The graph has curve pieces")


func _test_build() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var plan: Array[Dictionary] = EdgePieces.plan(_graph, GOLDEN_STREET)
	var segments: Array[RouteSegment] = EdgePieces.build(_graph, GOLDEN_STREET, root)
	_expect(segments.size() == plan.size() and plan.size() > 0, "build() makes one segment per piece")
	for i in segments.size():
		var ground := Vector2(segments[i].position.x, segments[i].position.z)
		_expect(ground.distance_to(plan[i].position) < 0.01, "Segment %d sits where the plan says" % i)
		_expect(is_equal_approx(segments[i].length, plan[i].length), "Segment %d has the planned length" % i)
	root.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

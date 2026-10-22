class_name EdgePieces
extends RefCounted
## Lays the pieces of a street (RoadEdge.segments, expansion D-0304.2) along its curve.
##
## A piece is a RouteSegment: straight, 30 m or so, built along its own -Z. The
## street bends, so each piece is set at the street's point where it starts and
## turned to face where it ends; the small kink between neighbours is the Bezier's
## own bend, and a piece that bends by itself (`curve`) is given the turn the street
## makes over its span. The list repeats to fill the street's length; a piece that
## no longer fits at the end becomes a straight one cut to what is left.
##
## plan() is pure data (testable with no scene); build() makes the nodes.

## Shortest stretch worth a piece of its own at the end of a street.
const MIN_FILL: float = 2.0
## What a `curve` piece spans along the street, before its own length is known.
const CURVE_SPAN: float = 50.0
## Kinds that bend the road on their own: they take the street's turn over their span.
const BENDING: Array[StringName] = [&"curve"]
## Passes to settle a bend's turn and its built length on each other.
const BEND_PASSES: int = 4
const FILL_KIND: StringName = &"straight"

static var _lengths: Dictionary = {}


## The pieces of one street, in order: { kind, start (m along the street), length,
## position (Vector2 on the ground), yaw (radians, for a Basis(UP, yaw)), turn_deg
## (curves only) }. Empty for a street that is not in the graph or lists no pieces.
static func plan(graph: RoadGraph, edge_id: StringName) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	var edge: RoadEdge = graph.edge_by_id(edge_id)
	if edge == null or edge.segments.is_empty():
		return pieces
	var total: float = graph.edge_length(edge_id)
	var at: float = 0.0
	var index: int = 0
	while total - at >= MIN_FILL:
		var kind: StringName = edge.segments[index % edge.segments.size()]
		index += 1
		var span: float = CURVE_SPAN if BENDING.has(kind) else natural_length(kind)
		var remaining: float = total - at
		if span > remaining:
			kind = FILL_KIND
			span = remaining
		var piece: Dictionary = _piece(graph, edge_id, kind, at, span)
		pieces.append(piece)
		at += float(piece.advance)
	return pieces


## Builds the plan under `parent` (one RouteSegment per piece, already placed).
static func build(graph: RoadGraph, edge_id: StringName, parent: Node3D) -> Array[RouteSegment]:
	var built: Array[RouteSegment] = []
	for piece: Dictionary in plan(graph, edge_id):
		var segment: RouteSegment = build_piece(piece)
		parent.add_child(segment)
		built.append(segment)
	return built


## One piece of a plan() as a RouteSegment, placed in world space, not yet in the tree.
static func build_piece(piece: Dictionary) -> RouteSegment:
	var segment: RouteSegment = (RoadGraph.SEGMENT_SCRIPTS[piece.kind] as GDScript).new() as RouteSegment
	segment.length = piece.length
	if segment is CurveSegment:
		(segment as CurveSegment).turn_deg = piece.turn_deg
	var ground: Vector2 = piece.position
	segment.transform = Transform3D(Basis(Vector3.UP, piece.yaw), Vector3(ground.x, 0.0, ground.y))
	return segment


## "kind:length" for every piece, comma separated: the street's golden, which
## changes only when its data (or this layout) does.
static func signature(pieces: Array[Dictionary]) -> String:
	var parts := PackedStringArray()
	for piece: Dictionary in pieces:
		parts.append("%s:%d" % [piece.kind, roundi(piece.length)])
	return ",".join(parts)


## How long a kind is when nothing has changed it (read once from its script).
static func natural_length(kind: StringName) -> float:
	if not _lengths.has(kind):
		var segment: RouteSegment = (RoadGraph.SEGMENT_SCRIPTS[kind] as GDScript).new() as RouteSegment
		_lengths[kind] = segment.length
		segment.free()
	return _lengths[kind]


static func _piece(graph: RoadGraph, edge_id: StringName, kind: StringName, at: float, span: float) -> Dictionary:
	var start: Vector2 = graph.point_at(edge_id, at)
	var facing: Vector2 = graph.tangent_at(edge_id, at)
	var piece: Dictionary = {
		"kind": kind, "start": at, "length": span, "advance": span,
		"position": start, "yaw": atan2(-facing.x, -facing.y), "turn_deg": 0.0,
	}
	if BENDING.has(kind):
		# The piece advances by the length it is built with, and the turn is the one the street
		# makes over that length: a few passes settle the two on each other (a chord is 10 m).
		var length: float = span
		for _pass in BEND_PASSES:
			var leaving: Vector2 = graph.tangent_at(edge_id, maxf(at, at + length - 0.5))
			# Same sign as CurveSegment.turn_deg: the change of yaw (Basis(UP, yaw)) over the span.
			piece.turn_deg = rad_to_deg(wrapf(atan2(-leaving.x, -leaving.y) - float(piece.yaw), -PI, PI))
			var built: float = CurveSegment.length_for_turn(piece.turn_deg)
			if is_equal_approx(built, length):
				break
			length = built
		piece.length = length
		piece.advance = length
	return piece

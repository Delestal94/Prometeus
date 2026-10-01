extends RefCounted
## What route.gd tells the terrain about the road it builds (route_terrain.gd, a TerrainField): the
## ground under every segment, the hills and the riverbeds under bridges while the segments are
## chained; the rivers' reach and the levelled rail crossings once the whole route exists.

const Houses = preload("res://scripts/gameplay/route/route_houses.gd")

## A river reaches for its own preferred `bank_width` (NarrowBridgeSegment's
## river_reach, up to 60 m out) so it fades into the landscape instead of
## reading as a rectangular pool -- but a winding route can bring another
## stretch of road, a house or the depot yard back within that reach. Run
## once the whole route (every leg, every house) exists, so unlike the
## registration in register_features() this sees what comes both before AND after
## the bridge. Shrinks `bank_width` to stop RIVER_HAZARD_MARGIN short of
## whatever's closest, never below its own `full_width` + a visible margin,
## so the crossing itself is never swallowed. The margin has to clear
## route_terrain.gd's RIVER_MAX_DRIFT (how far the meander can ever swing the
## actual wet edge past the plain `bank_width` this measures against) plus
## some slack, or the meander could still carry the real river into what
## this thought it had already cleared.
const RIVER_HAZARD_MARGIN: float = 4.0 + TerrainField.RIVER_MAX_DRIFT
## The road immediately before and after the bridge is the SAME straight
## lane the river runs under -- at zero sideways distance from its own
## centreline, so without this it would always read as the nearest "hazard"
## and clamp every river down to the floor. Matches test_route_fuzz.gd's
## NEIGHBOUR_ALONG for the same idea: anything within this far along the
## route of the bridge's own span is its approach/exit, not another part of
## the road that happens to have come back close by.
const RIVER_SELF_BUFFER: float = 60.0


## The depot stands behind the start line: its footprint stays level and no
## tree or roadside prop may grow into it. (Ground tiles already reach it:
## the start apron's span makes them for 64 m around.)
static func reserve_start_yard(terrain: TerrainField, start_yard: Rect2, clear_zones: Array[Vector3]) -> void:
	if not start_yard.has_area():
		return
	terrain.flat_zones.append(start_yard)
	var step: float = 8.0
	var x: float = start_yard.position.x + step * 0.5
	while x < start_yard.end.x:
		var z: float = start_yard.position.y + step * 0.5
		while z < start_yard.end.y:
			clear_zones.append(Vector3(x, z, step * 0.75))
			z += step
		x += step


## The road's ground under one segment placed at `cursor`: a span for every ~10 m of it.
static func register_spans(terrain: TerrainField, segment: RouteSegment, cursor: Transform3D) -> void:
	var road_slots: Array[Transform3D] = segment.get_dressing_slots(10.0)
	road_slots.append(Transform3D(Basis(Vector3.UP, segment.exit_turn), segment.exit_offset))
	for i: int in range(road_slots.size() - 1):
		var gravel: bool = segment is GravelSegment or segment is MudSegment
		var width: float = 3.0 if segment is NarrowBridgeSegment else 6.0
		terrain.add_span((cursor * road_slots[i]).origin, (cursor * road_slots[i + 1]).origin, gravel, width)


## The hill's crest and the riverbed under a narrow bridge, for a segment placed at `cursor`.
## `path_start` / `path_end` are where its own stretch of route.gd's path points starts and ends
## (clamp_river_reach() needs it to tell "another part of the road" a river might run into from the
## river's own straight stretch under it); `route_start` is how far along the road it begins.
static func register_features(
	terrain: TerrainField,
	segment: RouteSegment,
	cursor: Transform3D,
	path_start: int,
	path_end: int,
	route_start: float,
) -> void:
	if segment is HillSegment:
		var exit: Vector3 = (cursor * Transform3D(Basis(Vector3.UP, segment.exit_turn), segment.exit_offset)).origin
		terrain.crests.append({
			"a": Vector2(cursor.origin.x, cursor.origin.z), "b": Vector2(exit.x, exit.z),
			"height": (segment as HillSegment).crest_height,
		})
	# The riverbed under a narrow bridge (N-132 follow-up): carves the
	# ground itself so it reads as a real crossing instead of guard
	# rails standing over flat grass. The span exactly matches this
	# straight segment (it never turns), so the deck/rails/water --
	# all flagged &"ignore_river" -- float over the drop. `bank_width`
	# starts at the segment's own preference and clamp_river_reach()
	# (called once the whole route exists) shrinks it if it would
	# otherwise run into another stretch of road, a house or the yard.
	if segment is NarrowBridgeSegment:
		var bridge: NarrowBridgeSegment = segment as NarrowBridgeSegment
		var river_end: Vector3 = (cursor * Transform3D(Basis(Vector3.UP, segment.exit_turn),
				segment.exit_offset)).origin
		terrain.rivers.append({
			"a": Vector2(cursor.origin.x, cursor.origin.z), "b": Vector2(river_end.x, river_end.z),
			"depth": bridge.river_depth, "full_width": bridge.river_width, "bank_width": bridge.river_reach,
			"path_start": path_start, "path_end": path_end, "route_start": route_start,
		})


## Level crossings: the ground along the tracks is levelled to the road, so the train runs flat
## instead of through the roadside hills, with a tunnel at each end and a hill over it; nothing
## grows on the rails, in the cutting or out of the portal (`clear_zones` gets those circles).
static func level_rail_crossings(
	terrain: TerrainField, segments: Array[RouteSegment], clear_zones: Array[Vector3]
) -> void:
	for segment: RouteSegment in segments:
		if segment is RailCrossingSegment:
			var centre: Vector3 = segment.transform * Vector3(0.0, 0.0, (segment as RailCrossingSegment).track_z)
			var level: float = terrain.base_height(Vector2(centre.x, centre.z))
			for pad: Vector3 in (segment as RailCrossingSegment).track_pads():
				terrain.pads.append(Vector3(pad.x, level, pad.z))
				# No tree on the rails.
				clear_zones.append(Vector3(pad.x, pad.z, 4.0))
			# A tunnel at each end, a hill over it; nothing grows in the
			# cutting or out of the portal.
			for mouth: Dictionary in (segment as RailCrossingSegment).tunnel_mouths():
				mouth["level"] = level
				terrain.tunnels.append(mouth)
				var front: Vector2 = (mouth.at as Vector2) + (mouth.dir as Vector2) * 2.0
				clear_zones.append(Vector3(front.x, front.y, 11.0))


## `cumulative` is the metres along the road to each of `path_points`; `start_yard` is the depot's
## ground (an empty Rect2 for none).
static func clamp_river_reach(
	terrain: TerrainField,
	path_points: Array[Vector3],
	cumulative: PackedFloat32Array,
	houses: Array[DeliveryHouse],
	start_yard: Rect2,
) -> void:
	for river: Dictionary in terrain.rivers:
		var a: Vector2 = river.a
		var edge: Vector2 = (river.b as Vector2) - a
		var length: float = maxf(edge.length(), 0.001)
		var dir: Vector2 = edge / length
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var route_start: float = float(river.get("route_start", 0.0))
		var route_end: float = route_start + length
		var hazard: float = INF
		for index: int in range(path_points.size()):
			var travelled: float = cumulative[index] if index < cumulative.size() else 0.0
			if travelled > route_start - RIVER_SELF_BUFFER and travelled < route_end + RIVER_SELF_BUFFER:
				continue  # this bridge's own approach/exit, not a hazard
			var q := Vector2(path_points[index].x, path_points[index].z)
			var s: float = (q - a).dot(dir)
			if s < -RIVER_HAZARD_MARGIN or s > length + RIVER_HAZARD_MARGIN:
				continue
			hazard = minf(hazard, absf((q - a).dot(perp)))
		for house: DeliveryHouse in houses:
			var q := Vector2(house.position.x, house.position.z)
			var s: float = (q - a).dot(dir)
			if s < -RIVER_HAZARD_MARGIN or s > length + RIVER_HAZARD_MARGIN:
				continue
			hazard = minf(hazard, absf((q - a).dot(perp)) - Houses.HOUSE_CLEAR_RADIUS)
		if start_yard.has_area():
			var center: Vector2 = start_yard.position + start_yard.size * 0.5
			var s: float = (center - a).dot(dir)
			if s >= -RIVER_HAZARD_MARGIN and s <= length + RIVER_HAZARD_MARGIN:
				hazard = minf(hazard, absf((center - a).dot(perp)) - maxf(start_yard.size.x, start_yard.size.y) * 0.5)
		var full_width: float = float(river.full_width)
		var desired: float = float(river.bank_width)
		river.bank_width = clampf(hazard - RIVER_HAZARD_MARGIN, full_width + 6.0, desired) if hazard < INF else desired

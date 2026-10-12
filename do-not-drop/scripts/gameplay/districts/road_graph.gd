class_name RoadGraph
extends RoadNetwork
## The company map's streets (expansion D-0304): modules/route_gen's RoadNetwork
## with this game's data (data/world/road_graph.tres), its names and its rules.
##
## From the shed to Centro (a grid of streets, asphalt and cobble) and to the
## Campo (gravel and mud), about 12 km of street, laid out from
## docs/expansion-distritos/diseno/mapa.md. A node of kind gate carries the id of
## the GateRequirement (data/gates/) that closes the way there; the zone each
## node and street lies in is its `area`. An edge's `segments` are the kinds of
## piece (SEGMENT_SCRIPTS) that go along it, in order, repeated to fill its length.
##
## Not done yet (subtasks of D-0304 in detalle/F1-03-distritos.md): the road mesh
## per edge, laying the pieces along the curve and the bot's autopilot.

const DATA_PATH: String = "res://data/world/road_graph.tres"
## Where every trip starts: the shed's gate.
const SHED_NODE: StringName = &"shed"
## RoadEdge.street of the three main streets of mapa.md (the cells under them
## never unload, CompanyCells.pin_streets).
const MAIN_STREETS: Array[StringName] = [&"avenida_este", &"calle_oeste", &"camino_campo"]
## Surfaces a vehicle spreads gravel on (the terrain paints them as a track).
const LOOSE_SURFACES: Array[StringName] = [&"gravel", &"dirt"]
## The kinds of piece an edge can list, by name, as the script that builds each one.
const SEGMENT_SCRIPTS: Dictionary = {
	&"straight": preload("res://modules/route_gen/straight_segment.gd"),
	&"speed_bump": preload("res://modules/route_gen/speed_bump_segment.gd"),
	&"curve": preload("res://modules/route_gen/curve_segment.gd"),
	&"s_curve": preload("res://modules/route_gen/s_curve_segment.gd"),
	&"gravel": preload("res://modules/route_gen/gravel_segment.gd"),
	&"hill": preload("res://modules/route_gen/hill_segment.gd"),
	&"chicane": preload("res://scripts/gameplay/route/segments/chicane_segment.gd"),
	&"narrow_bridge": preload("res://scripts/gameplay/route/segments/narrow_bridge_segment.gd"),
	&"construction_zone": preload("res://scripts/gameplay/route/segments/construction_zone_segment.gd"),
	&"rail_crossing": preload("res://scripts/gameplay/route/segments/rail_crossing_segment.gd"),
	&"tunnel": preload("res://scripts/gameplay/route/segments/tunnel_segment.gd"),
	&"mud": preload("res://scripts/gameplay/route/segments/mud_segment.gd"),
}
## Kinds that only make sense on a loose surface.
const LOOSE_ONLY_SEGMENTS: Array[StringName] = [&"gravel", &"mud"]
## How far a gate node may sit from its GateRequirement.position_xz (mapa.md:
## "can move up to 128 m").
const GATE_TOLERANCE: float = 128.0


static func load_default() -> RoadGraph:
	return load(DATA_PATH) as RoadGraph


## True when the street's surface is loose (gravel, dirt): the terrain draws it as a track.
func is_loose(edge: RoadEdge) -> bool:
	return LOOSE_SURFACES.has(edge.surface)


## The id of the zone whose bounds hold the point, or "" in the gaps between zones.
static func zone_at(zones: Array[ZoneDefinition], p: Vector2) -> StringName:
	for zone: ZoneDefinition in zones:
		if zone.bounds.has_point(p):
			return zone.id
	return &""


## Lays the ground under every street: a terrain span every `spacing` meters
## along its curve, as wide as half the roadway (the same call route_ground.gd
## makes for a segment). Returns how many spans were added.
func register_terrain(terrain: TerrainField, spacing: float = 10.0) -> int:
	var count: int = 0
	for edge: RoadEdge in edges:
		var points: PackedVector2Array = sample_every(edge.id, spacing)
		for i in points.size() - 1:
			terrain.add_span(Vector3(points[i].x, 0.0, points[i].y), Vector3(points[i + 1].x, 0.0, points[i + 1].y),
					is_loose(edge), edge.half_width())
			count += 1
	return count


## What is wrong beyond the module's own validate(): names of pieces and surfaces
## that do not go together, nodes and streets in a zone other than the one they
## say, gates that do not match a data/gates/ file or the zone they close.
func problems(zones: Array[ZoneDefinition], gates: Array[GateRequirement]) -> PackedStringArray:
	var found: PackedStringArray = validate()
	var zone_by_id: Dictionary = {}
	for zone: ZoneDefinition in zones:
		zone_by_id[zone.id] = zone
	var gate_by_id: Dictionary = {}
	for gate: GateRequirement in gates:
		gate_by_id[gate.id] = gate
	for node: RoadNode in nodes:
		found.append_array(_node_problems(node, zones, zone_by_id, gate_by_id))
	for edge: RoadEdge in edges:
		found.append_array(_edge_rules(edge, zones))
	if node_by_id(SHED_NODE) == null:
		found.append("there is no %s node" % SHED_NODE)
	return found


func _node_problems(node: RoadNode, zones: Array[ZoneDefinition], zone_by_id: Dictionary,
		gate_by_id: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	var here: StringName = zone_at(zones, node.position)
	if node.area != here:
		found.append("node %s says zone '%s' but lies in '%s'" % [node.id, node.area, here])
	if node.kind != &"gate":
		return found
	var gate: GateRequirement = gate_by_id.get(node.lock_id) as GateRequirement
	if gate == null:
		found.append("node %s: there is no gate %s in data/gates" % [node.id, node.lock_id])
		return found
	if node.position.distance_to(gate.position_xz) > GATE_TOLERANCE:
		found.append("node %s is more than %d m from its gate" % [node.id, int(GATE_TOLERANCE)])
	var zone: ZoneDefinition = zone_by_id.get(node.area) as ZoneDefinition
	if zone == null or not zone.gates.has(node.lock_id):
		found.append("node %s: zone '%s' is not closed by gate %s" % [node.id, node.area, node.lock_id])
	return found


func _edge_rules(edge: RoadEdge, zones: Array[ZoneDefinition]) -> PackedStringArray:
	var found := PackedStringArray()
	var middle: StringName = zone_at(zones, point_at(edge.id, edge_length(edge.id) * 0.5))
	if edge.area != middle:
		found.append("edge %s says zone '%s' but its middle lies in '%s'" % [edge.id, edge.area, middle])
	if edge.segments.is_empty():
		found.append("edge %s lists no pieces" % edge.id)
	for kind: StringName in edge.segments:
		if not SEGMENT_SCRIPTS.has(kind):
			found.append("edge %s: unknown piece %s" % [edge.id, kind])
		elif LOOSE_ONLY_SEGMENTS.has(kind) and not is_loose(edge):
			found.append("edge %s: piece %s needs a loose surface, not %s" % [edge.id, kind, edge.surface])
	return found

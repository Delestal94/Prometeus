class_name HouseAddresses
extends RefCounted
## The street and number of every delivery house of the company map (expansion D-0312).
##
## Derived, never stored: the street is the `street` tag of the RoadEdge the house stands on
## (data/world/road_graph.tres), its name the translation key WORLD_STREET_<TAG>; the number
## counts the houses of that street in the order of the street's edges and then along each edge,
## one count per side of the way: the right side (HouseSpot.side = 1) takes even numbers
## (2, 4, 6...), the left side odd ones (1, 3, 5...). So two houses never share an address, and
## the number on the label and the number on the house sign come from the same call.
##
## Pure data, no node, no autoload. The label side is OrderLabel.address; the sign side is
## HouseMap.instance (DeliveryHouse.address_number).

const KEY_PREFIX: String = "WORLD_STREET_"

var _by_house: Dictionary = {}

static var _default: HouseAddresses


## The addresses of the default map, built once.
static func load_default() -> HouseAddresses:
	if _default == null:
		var map: HouseMap = HouseMap.load_default()
		var graph: RoadGraph = RoadGraph.load_default()
		if map == null or graph == null:
			return null
		_default = HouseAddresses.build(map, graph)
	return _default


static func build(map: HouseMap, graph: RoadGraph) -> HouseAddresses:
	var built := HouseAddresses.new()
	var edge_order: Dictionary = {}
	for i in graph.edges.size():
		edge_order[graph.edges[i].id] = i
	var streets: Dictionary = {}
	for house: HouseSpot in map.houses:
		var edge: RoadEdge = graph.edge_by_id(house.edge)
		if edge == null:
			continue
		var street: StringName = edge.street if edge.street != &"" else edge.id
		if not streets.has(street):
			streets[street] = []
		(streets[street] as Array).append(house)
	for street: StringName in streets:
		var along_street: Array = streets[street]
		along_street.sort_custom(func(a: HouseSpot, b: HouseSpot) -> bool:
			if a.edge != b.edge:
				return edge_order[a.edge] < edge_order[b.edge]
			return a.along < b.along)
		var counted: Dictionary = {1: 0, -1: 0}
		for house: HouseSpot in along_street:
			var side: int = 1 if house.side >= 0 else -1
			var rank: int = counted[side]
			counted[side] = rank + 1
			built._by_house[house.id] = {
				"street": street,
				"street_key": StringName(KEY_PREFIX + String(street).to_upper()),
				"number": 2 * (rank + 1) if side == 1 else 2 * rank + 1,
			}
	return built


func has_house(house_id: StringName) -> bool:
	return _by_house.has(house_id)


## {street, street_key, number} of a house; empty for an id the map does not have.
func of_house(house_id: StringName) -> Dictionary:
	return (_by_house.get(house_id, {}) as Dictionary).duplicate()


func number_of(house_id: StringName) -> int:
	return int((_by_house.get(house_id, {}) as Dictionary).get("number", 0))


func house_ids() -> Array:
	return _by_house.keys()

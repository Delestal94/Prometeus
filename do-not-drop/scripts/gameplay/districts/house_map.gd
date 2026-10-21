class_name HouseMap
extends Resource
## The delivery houses of the company map (expansion D-0311), data/world/houses.tres:
## 30 in Centro and 20 in Campo. The houses are fixed points of the map; each day
## the seed picks which of them order (pick_for_day). They are the game's own
## DeliveryHouse (door, bell, resident, check at the door), so instance() only sets
## where one stands.

const DATA_PATH: String = "res://data/world/houses.tres"
## A house may stand at most this far from the edge of the roadway of its street
## (the door must be reachable from the road).
const MAX_STREET_GAP: float = 12.0
## Closest two house origins may stand (the widest model is 7 m).
const MIN_SPACING: float = 12.0
## Clearance from the roadway of any street, house origin to roadway edge: the
## walls (2.5 m from the origin) must not touch the asphalt.
const MIN_ROAD_CLEARANCE: float = 4.0

@export var houses: Array[HouseSpot] = []


static func load_default() -> HouseMap:
	return load(DATA_PATH) as HouseMap


func spot(house_id: StringName) -> HouseSpot:
	for house: HouseSpot in houses:
		if house.id == house_id:
			return house
	return null


## Index of a house in `houses`, the number DeliveryHouse.house_index carries.
func index_of(house_id: StringName) -> int:
	for i in houses.size():
		if houses[i].id == house_id:
			return i
	return -1


func in_zone(zone_id: StringName) -> Array[HouseSpot]:
	var found: Array[HouseSpot] = []
	for house: HouseSpot in houses:
		if house.zone == zone_id:
			found.append(house)
	return found


## The houses that ask for a package today: `count` of the zone's houses, picked
## from the seed and the day only, so every peer and every run gets the same ones.
## Fewer come back when the zone has fewer; the order is the map's.
func pick_for_day(zone_id: StringName, world_seed: int, day: int, count: int) -> Array[HouseSpot]:
	var pool: Array[HouseSpot] = in_zone(zone_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, day, String(zone_id)])
	var order: Array[int] = []
	for i in pool.size():
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = order[i]
		order[i] = order[j]
		order[j] = swap
	var chosen: Array[int] = order.slice(0, clampi(count, 0, pool.size()))
	chosen.sort()
	var picked: Array[HouseSpot] = []
	for i: int in chosen:
		picked.append(pool[i])
	return picked


## A DeliveryHouse standing on its spot (not in the tree yet). `height` is the
## ground there, which the terrain answers.
func instance(house: HouseSpot, height: float = 0.0) -> DeliveryHouse:
	var node := DeliveryHouse.new()
	node.name = String(house.id)
	node.visual_variant = house.variant
	node.house_index = maxi(index_of(house.id), 0)
	node.transform = Transform3D(Basis(Vector3.UP, house.yaw), Vector3(house.position.x, height, house.position.y))
	return node


## What is wrong with the list against the street graph and the zones: ids that
## repeat, a house outside the zone it names, with no street near, on the
## roadway, on top of another, or with its door turned away from the street.
func problems(graph: RoadGraph, zones: Array[ZoneDefinition]) -> PackedStringArray:
	var found := PackedStringArray()
	var seen: Dictionary = {}
	var bounds: Dictionary = {}
	for zone: ZoneDefinition in zones:
		bounds[zone.id] = zone.bounds
	for i in houses.size():
		var house: HouseSpot = houses[i]
		if seen.has(house.id):
			found.append("house %s is listed twice" % house.id)
		seen[house.id] = true
		if not bounds.has(house.zone) or not (bounds[house.zone] as Rect2).has_point(house.position):
			found.append("house %s is not inside zone '%s'" % [house.id, house.zone])
		if house.variant < 0 or house.variant >= DeliveryHouse.HOUSE_VISUALS.size():
			found.append("house %s has variant %d, there are %d models" % [house.id, house.variant,
					DeliveryHouse.HOUSE_VISUALS.size()])
		found.append_array(_street_problems(house, graph))
		for k in i:
			if houses[k].position.distance_to(house.position) < MIN_SPACING:
				found.append("houses %s and %s are closer than %d m" % [houses[k].id, house.id, int(MIN_SPACING)])
	return found


func _street_problems(house: HouseSpot, graph: RoadGraph) -> PackedStringArray:
	var found := PackedStringArray()
	var near: Dictionary = graph.nearest_point(house.position)
	if near.is_empty():
		found.append("house %s has no street" % house.id)
		return found
	var edge: RoadEdge = graph.edge_by_id(near.edge)
	var gap: float = float(near.distance) - edge.half_width()
	if gap > MAX_STREET_GAP:
		found.append("house %s is %.1f m from the roadway, more than %d" % [house.id, gap, int(MAX_STREET_GAP)])
	if gap < MIN_ROAD_CLEARANCE:
		found.append("house %s is %.1f m from the roadway, less than %d" % [house.id, gap, int(MIN_ROAD_CLEARANCE)])
	# The entrance (local -Z) has to look at the street it stands on.
	var door: Vector2 = Vector2(-sin(house.yaw), -cos(house.yaw))
	var to_street: Vector2 = ((near.point as Vector2) - house.position).normalized()
	if door.dot(to_street) < 0.9:
		found.append("house %s has its door turned away from the street" % house.id)
	return found

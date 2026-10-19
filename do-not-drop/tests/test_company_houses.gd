extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_houses.gd
##
## The delivery houses of the company map (expansion D-0311, HouseMap in
## scripts/gameplay/districts/house_map.gd, data in data/world/houses.tres):
## - 50 houses, 30 in Centro and 20 in Campo, every zone inside its own bounds, all
##   five DeliveryHouse models used, and HouseMap.problems() finds nothing: each house
##   stands 4 to 12 m off the roadway of a street, no two closer than 12 m, its door
##   turned toward the street;
## - the same checks written out here, so a loosened rule in problems() does not pass:
##   the nearest street (RoadGraph.nearest_point) is at most 12 m from the roadway edge,
##   and no house stands on any roadway;
## - problems() does notice a house moved onto the street, one dropped on another, one
##   outside its zone and one with its back to the street;
## - pick_for_day() gives the same houses for the same seed and day, other houses another
##   day, never more than the zone has, and only houses of that zone;
## - every house instances as a DeliveryHouse (placed, with its variant and its index),
##   enters the tree and builds its door and bell without an error.

const ZONES_DIR: String = "res://data/zones/"

var _failures: int = 0
var _map: HouseMap
var _graph: RoadGraph
var _zones: Array[ZoneDefinition] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_map = HouseMap.load_default()
	_graph = RoadGraph.load_default()
	_expect(_map != null, "data/world/houses.tres loads as a HouseMap")
	_expect(_graph != null, "data/world/road_graph.tres loads as a RoadGraph")
	if _map == null or _graph == null:
		quit(1)
		return
	for file: String in DirAccess.get_files_at(ZONES_DIR):
		if file.ends_with(".tres"):
			_zones.append(load(ZONES_DIR + file) as ZoneDefinition)
	_test_data()
	_test_rules_by_hand()
	_test_problems_notices()
	_test_pick_for_day()
	await _test_instances()
	quit(_failures)


func _test_data() -> void:
	_expect(_map.houses.size() == 50, "The map has 50 houses (got %d)" % _map.houses.size())
	_expect(_map.in_zone(&"centro").size() == 30, "30 houses in Centro")
	_expect(_map.in_zone(&"campo").size() == 20, "20 houses in Campo")
	var variants: Dictionary = {}
	for house: HouseSpot in _map.houses:
		variants[house.variant] = true
	_expect(variants.size() == DeliveryHouse.HOUSE_VISUALS.size(), "Every house model is used")
	var problems: PackedStringArray = _map.problems(_graph, _zones)
	_expect(problems.is_empty(), "No problem with the houses: %s" % ", ".join(problems))
	_expect(_map.spot(&"centro_01") != null and _map.spot(&"nowhere") == null, "spot() finds a house by id")
	_expect(_map.index_of(&"centro_01") == 0 and _map.index_of(&"nowhere") == -1, "index_of() is the list position")


func _test_rules_by_hand() -> void:
	for house: HouseSpot in _map.houses:
		var near: Dictionary = _graph.nearest_point(house.position)
		var edge: RoadEdge = _graph.edge_by_id(near.edge)
		var gap: float = float(near.distance) - edge.half_width()
		_expect(gap <= 12.0, "%s: the street is %.1f m away (at most 12)" % [house.id, gap])
		_expect(gap > 0.0, "%s does not stand on a roadway" % house.id)
		_expect(_graph.edge_by_id(house.edge) != null, "%s names a street that exists" % house.id)
		_expect(absi(house.side) == 1, "%s has side 1 or -1" % house.id)


func _test_problems_notices() -> void:
	var original: HouseMap = _map
	var broken := HouseMap.new()
	for house: HouseSpot in original.houses:
		broken.houses.append(house.duplicate() as HouseSpot)
	var on_street: HouseSpot = broken.houses[0]
	var street_point: Vector2 = _graph.nearest_point(on_street.position).point
	on_street.position = street_point
	_expect(not _problems_about(broken, on_street.id).is_empty(), "A house on the roadway is noticed")
	on_street.position = original.houses[0].position
	var copy: HouseSpot = broken.houses[1]
	copy.position = broken.houses[2].position + Vector2(3.0, 0.0)
	_expect(not _problems_about(broken, copy.id).is_empty(), "A house on top of another is noticed")
	copy.position = original.houses[1].position
	var stray: HouseSpot = broken.houses[3]
	stray.zone = &"campo" if stray.zone == &"centro" else &"centro"
	_expect(not _problems_about(broken, stray.id).is_empty(), "A house outside its zone is noticed")
	stray.zone = original.houses[3].zone
	var turned: HouseSpot = broken.houses[4]
	turned.yaw += PI
	_expect(not _problems_about(broken, turned.id).is_empty(), "A house with its back to the street is noticed")
	turned.yaw = original.houses[4].yaw
	_expect(broken.problems(_graph, _zones).is_empty(), "The copy is clean once every change is undone")
	var twin: HouseSpot = broken.houses[5].duplicate() as HouseSpot
	broken.houses.append(twin)
	_expect(not _problems_about(broken, twin.id).is_empty(), "A repeated id is noticed")


func _problems_about(map: HouseMap, house_id: StringName) -> PackedStringArray:
	var found := PackedStringArray()
	for line: String in map.problems(_graph, _zones):
		if line.contains(String(house_id)):
			found.append(line)
	return found


func _test_pick_for_day() -> void:
	var a: Array[HouseSpot] = _map.pick_for_day(&"centro", 1234, 1, 8)
	var b: Array[HouseSpot] = _map.pick_for_day(&"centro", 1234, 1, 8)
	var other_day: Array[HouseSpot] = _map.pick_for_day(&"centro", 1234, 2, 8)
	var other_seed: Array[HouseSpot] = _map.pick_for_day(&"centro", 99, 1, 8)
	_expect(a.size() == 8, "Eight houses asked, eight picked")
	_expect(_ids(a) == _ids(b), "The same seed and day pick the same houses")
	_expect(_ids(a) != _ids(other_day), "Another day picks other houses")
	_expect(_ids(a) != _ids(other_seed), "Another seed picks other houses")
	var distinct: Dictionary = {}
	for house: HouseSpot in a:
		distinct[house.id] = true
		_expect(house.zone == &"centro", "%s is a house of Centro" % house.id)
	_expect(distinct.size() == a.size(), "No house is picked twice")
	_expect(_map.pick_for_day(&"campo", 1234, 1, 99).size() == 20, "Asking for more than the zone has gives the zone")
	_expect(_map.pick_for_day(&"campo", 1234, 1, 0).is_empty(), "Asking for none gives none")
	_expect(_map.pick_for_day(&"suburbio", 1234, 1, 5).is_empty(), "A zone with no houses gives none")
	var index_before: int = -1
	for house: HouseSpot in a:
		var index: int = _map.index_of(house.id)
		_expect(index > index_before, "The picked houses keep the map's order")
		index_before = index


func _ids(spots: Array[HouseSpot]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for house: HouseSpot in spots:
		ids.append(house.id)
	return ids


func _test_instances() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	for house: HouseSpot in _map.houses:
		var node: DeliveryHouse = _map.instance(house, 2.0)
		_expect(node != null and node.name == String(house.id), "%s instances as a named DeliveryHouse" % house.id)
		_expect(node.visual_variant == house.variant, "%s keeps its model" % house.id)
		_expect(node.house_index == _map.index_of(house.id), "%s keeps its index" % house.id)
		var spot := Vector3(house.position.x, 2.0, house.position.y)
		_expect(node.position.is_equal_approx(spot), "%s stands on its spot" % house.id)
		holder.add_child(node)
	await process_frame
	var built: int = 0
	for node: Node in holder.get_children():
		var body: Node = node.get_node_or_null(^"HouseBody")
		if body != null and node.get_node_or_null(^"HouseVisual") != null:
			built += 1
	var total: int = _map.houses.size()
	_expect(built == total, "Every house built its walls and model (%d of %d)" % [built, total])
	_expect(get_nodes_in_group(&"delivery_house").size() >= total, "The houses joined the delivery_house group")
	holder.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

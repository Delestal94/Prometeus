extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_addresses.gd
##
## The readable addresses of the company map (expansion D-0312, HouseAddresses in
## scripts/gameplay/districts/house_addresses.gd):
## - every one of the 50 houses has a street (the tag of its road edge) and a number, and no two
##   houses of a street share a number: the right side of the way is even, the left side odd;
## - numbers on a side grow along the street (edge order, then distance along the edge);
## - every street of the map has a name in both languages;
## - 10 orders naming map houses: the number on the label (OrderLabel.address) is the one on the
##   house sign (HouseMap.instance -> DeliveryHouse.sign_number), with the same street;
## - houses the map does not know keep the older "<zone>_house_<n>" address of OrderLabel;
## - building from a copy of the map with a house moved to the other side changes its parity.

var _failures: int = 0
var _map: HouseMap
var _graph: RoadGraph
var _addresses: HouseAddresses


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_map = HouseMap.load_default()
	_graph = RoadGraph.load_default()
	_addresses = HouseAddresses.load_default()
	_expect(_map != null and _graph != null and _addresses != null, "map, graph and addresses load")
	if _map == null or _graph == null or _addresses == null:
		quit(1)
		return
	_test_unique_and_parity()
	_test_order_along_street()
	_test_street_names()
	_test_label_and_sign()
	_test_legacy_ids()
	_test_side_change()
	quit(_failures)


func _street_of(house: HouseSpot) -> StringName:
	return _graph.edge_by_id(house.edge).street


func _test_unique_and_parity() -> void:
	var seen: Dictionary = {}
	for house: HouseSpot in _map.houses:
		_expect(_addresses.has_house(house.id), "%s has an address" % house.id)
		var number: int = _addresses.number_of(house.id)
		_expect(number >= 1, "%s has a number (got %d)" % [house.id, number])
		var key: String = "%s %d" % [_street_of(house), number]
		_expect(not seen.has(key), "%s is not repeated (%s)" % [key, house.id])
		seen[key] = true
		_expect(number % 2 == (0 if house.side == 1 else 1),
				"%s: side %d gives parity of %d" % [house.id, house.side, number])
	_expect(_addresses.house_ids().size() == 50, "50 addresses")


func _test_order_along_street() -> void:
	var edge_order: Dictionary = {}
	for i in _graph.edges.size():
		edge_order[_graph.edges[i].id] = i
	for a: HouseSpot in _map.houses:
		for b: HouseSpot in _map.houses:
			if a == b or _street_of(a) != _street_of(b) or a.side != b.side:
				continue
			var a_first: bool = edge_order[a.edge] < edge_order[b.edge] \
					or (a.edge == b.edge and a.along < b.along)
			if a_first:
				_expect(_addresses.number_of(a.id) < _addresses.number_of(b.id),
						"%s comes before %s on %s" % [a.id, b.id, _street_of(a)])


func _test_street_names() -> void:
	var streets: Dictionary = {}
	for house: HouseSpot in _map.houses:
		streets[_addresses.of_house(house.id)["street_key"]] = true
	_expect(streets.size() >= 8, "the houses are spread over several streets (%d)" % streets.size())
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		var names: Dictionary = {}
		for key: StringName in streets:
			var shown: String = TranslationServer.translate(key)
			_expect(shown != String(key), "%s has %s" % [locale, key])
			names[shown] = true
		_expect(names.size() == streets.size(), "%s: every street has its own name" % locale)
	TranslationServer.set_locale("es")


func _test_label_and_sign() -> void:
	var count: int = 0
	for i in range(0, _map.houses.size(), 5):
		var house: HouseSpot = _map.houses[i]
		var order: Dictionary = {"id": "o%d" % i, "customer": "Ana", "zone": house.zone, "house_id": house.id}
		var label: Dictionary = OrderLabel.address(order)
		var node: DeliveryHouse = _map.instance(house, 0.0)
		_expect(label.get("number") == node.sign_number(),
				"%s: label number %s is the sign number %d" % [house.id, label.get("number"), node.sign_number()])
		_expect(label.get("street_key") == _addresses.of_house(house.id)["street_key"],
				"%s: the label names the street of the address" % house.id)
		node.free()
		count += 1
	_expect(count == 10, "10 orders checked (got %d)" % count)
	var plain := DeliveryHouse.new()
	plain.house_index = 4
	_expect(plain.sign_number() == 5, "a house without an address keeps the stop number")
	plain.free()


func _test_legacy_ids() -> void:
	var legacy: Dictionary = OrderLabel.address({"id": "o1", "zone": "centro", "house_id": "centro_house_7"})
	_expect(legacy.get("number") == 7 and legacy.get("street_key") == &"WORLD_STREET_CENTRO",
			"an id the map does not know keeps the zone street and its house number")
	_expect(OrderLabel.address({"id": "o1", "zone": "centro", "house_id": "nowhere"}).is_empty(),
			"an unknown house with no number has no address")


func _test_side_change() -> void:
	var copy: HouseMap = _map.duplicate(true) as HouseMap
	var house: HouseSpot = copy.houses[0]
	var before: int = _addresses.number_of(house.id)
	house.side = -house.side
	var changed: HouseAddresses = HouseAddresses.build(copy, _graph)
	_expect(changed.number_of(house.id) % 2 != before % 2, "moving a house to the other side flips its parity")
	_expect(_addresses.number_of(house.id) == before, "the default addresses were not touched by the copy")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

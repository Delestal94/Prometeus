extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_templates.gd
##
## Order templates per district (expansion D-0820, order_template*.gd, data/order_templates/):
## - every zone that takes deliveries today (shipping_fee > 0) has a set of 40 templates, and every
##   file passes OrderTemplateCheck with no problem (products, requirements, zone, qty, implied
##   requirements, no repeats);
## - the shape mix is the early-days one: single, double and triple orders; a template of 3 products
##   exists, one with an extra whim requirement exists;
## - to_order() gives a valid Order with the pay and window rules of OrderGenerator;
## - the check catches a bad set (unknown product, missing implied requirement, repeats, wrong count).

var _failures: int = 0
var _products: Dictionary = {}
var _reqs: Dictionary = {}
var _zones: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_load_catalogs()
	_test_data()
	_test_mix()
	_test_to_order()
	_test_check_catches_problems()
	quit(_failures)


func _load_catalogs() -> void:
	for file in CompanyCatalog.tres_files("res://data/products"):
		var def: ProductDefinition = load("res://data/products/" + file)
		_products[def.id] = def
	for file in CompanyCatalog.tres_files("res://data/order_requirements"):
		var req: OrderRequirement = load("res://data/order_requirements/" + file)
		_reqs[req.id] = req
	for file in CompanyCatalog.tres_files("res://data/zones"):
		var zone: ZoneDefinition = load("res://data/zones/" + file)
		_zones[zone.id] = zone


func _centro() -> OrderTemplateSet:
	return load("res://data/order_templates/centro.tres")


func _zone_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in _zones:
		ids.append(id)
	return ids


func _test_data() -> void:
	var sets := OrderTemplateCheck.load_sets()
	var problems := OrderTemplateCheck.problems(sets, _products, _reqs, _zone_ids())
	_expect(problems.is_empty(), "data/order_templates has no problems: %s" % [problems])
	var covered: Array[StringName] = []
	for set_res in sets:
		covered.append(set_res.zone)
		_expect(set_res.templates.size() == OrderTemplateSet.PER_ZONE, "%s has 40 templates" % set_res.id)
	for id: StringName in _zones:
		var zone: ZoneDefinition = _zones[id]
		if zone.shipping_fee > 0:
			_expect(id in covered, "zone %s takes deliveries and has templates" % id)
	_expect(not sets.is_empty(), "there are sets")


func _test_mix() -> void:
	var sizes: Dictionary = {}
	var whim := false
	for set_res in OrderTemplateCheck.load_sets():
		for template in set_res.templates:
			sizes[template.items.size()] = int(sizes.get(template.items.size(), 0)) + 1
			for req_id in template.requirements:
				if req_id in OrderGenerator.EXTRA_REQUIREMENTS:
					whim = true
	_expect(int(sizes.get(1, 0)) > 0 and int(sizes.get(2, 0)) > 0 and int(sizes.get(3, 0)) > 0,
		"singles, doubles and triples exist: %s" % [sizes])
	_expect(int(sizes.get(1, 0)) + int(sizes.get(2, 0)) > int(sizes.get(3, 0)), "most templates are small")
	_expect(whim, "some templates carry a whim requirement")


func _test_to_order() -> void:
	var set_res: OrderTemplateSet = _centro()
	var template := set_res.templates[0]
	var order := template.to_order(&"d1_o01", "Marta", &"centro", &"centro_house_3", 30, _products, _reqs)
	_expect(Order.validate(order).is_empty(), "to_order is a valid order: %s" % [Order.validate(order)])
	_expect(order["zone"] == &"centro" and int(order["created_min"]) == 30, "zone and minute kept")
	var plain := Order.make(&"x", "Marta", &"centro", &"centro_house_3", template.items, 30, _products,
		template.requirements)
	_expect(int(order["pay"]) >= int(plain["pay"]), "requirements never lower the pay")
	var urgent: OrderTemplate = null
	for candidate in set_res.templates:
		if &"urgent" in candidate.requirements:
			urgent = candidate
			break
	if urgent != null:
		var rushed := urgent.to_order(&"x", "Marta", &"centro", &"centro_house_3", 0, _products, _reqs)
		_expect(int(rushed["due_min"]) < CompanyTuning.ORDER_WINDOW_MIN, "urgent shrinks the window")
	var by_id := set_res.by_id(template.id)
	_expect(by_id == template and set_res.by_id(&"nope") == null, "by_id finds a template and only that")


func _test_check_catches_problems() -> void:
	var good: OrderTemplateSet = _centro()
	var fewer := OrderTemplateSet.new()
	fewer.id = &"centro"
	fewer.zone = &"centro"
	var bad := OrderTemplate.new()
	bad.id = &"bad"
	bad.items = [{"product": &"ghost", "qty": 1}]
	var glass := OrderTemplate.new()
	glass.id = &"glass"
	glass.items = [{"product": &"glass_tower", "qty": 3}]
	var twin_a := OrderTemplate.new()
	twin_a.id = &"twin"
	twin_a.items = [{"product": &"puppy", "qty": 1}]
	var twin_b := OrderTemplate.new()
	twin_b.id = &"twin"
	twin_b.items = [{"product": &"puppy", "qty": 1}]
	var hen := OrderTemplate.new()
	hen.id = &"hen"
	hen.items = [{"product": &"hen", "qty": 1}]
	hen.requirements = [&"ghost_req"]
	var templates: Array[OrderTemplate] = [bad, glass, twin_a, twin_b, hen]
	fewer.templates = templates
	var text := "\n".join(OrderTemplateCheck.problems([fewer], _products, _reqs, _zone_ids()))
	_expect(text.contains("5 templates, expected 40"), "wrong count is caught")
	_expect(text.contains("product 'ghost' is not in the catalog"), "unknown product is caught")
	_expect(text.contains("qty 3 outside"), "qty out of range is caught")
	_expect(text.contains("its products imply 'fragile'"), "missing implied requirement is caught")
	_expect(text.contains("id empty or repeated"), "repeated template id is caught")
	_expect(text.contains("same products and requirements"), "duplicate shape is caught")
	_expect(text.contains("no product of the zone 'centro'"), "template of other zone products is caught")
	_expect(text.contains("requirement 'ghost_req' is not in the catalog"), "unknown requirement is caught")
	var twice := "\n".join(OrderTemplateCheck.problems([good, good], _products, _reqs, _zone_ids()))
	_expect(twice.contains("already has a set"), "two sets for one zone are caught")
	var off_map := OrderTemplateSet.new()
	off_map.id = &"x"
	off_map.zone = &"mars"
	var no_zone := "\n".join(OrderTemplateCheck.problems([off_map], _products, _reqs, _zone_ids()))
	_expect(no_zone.contains("is not a zone"), "unknown zone is caught")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)
	print("FAIL: ", label)

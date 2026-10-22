extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_district_label.gd
##
## Shipping label colour by district (expansion D-0732, district_label.gd):
## - every district has a colour and a name key, and no two districts share a colour;
## - the colour of an order is the one of its zone, and a zone the table does not know gets the fallback;
## - every zone the shipping fees pay has a colour;
## - every name key is in strings_ui.csv, and district_name() never returns the raw key;
## - same_district() holds for two orders of one zone and never for orders without zone.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(DistrictLabel.COLORS.size() == DistrictLabel.NAME_KEYS.size(), "a colour and a name per district")
	var seen: Array[Color] = []
	for zone: StringName in DistrictLabel.COLORS:
		var color: Color = DistrictLabel.color_for(zone)
		_expect(not (color in seen), "%s has its own colour" % zone)
		seen.append(color)
		_expect(DistrictLabel.name_key(zone) != &"", "%s has a name key" % zone)
		_expect(not (color == DistrictLabel.FALLBACK_COLOR), "%s is not the fallback grey" % zone)
	for zone: StringName in CompanyTuning.SHIPPING_FEE:
		_expect(DistrictLabel.COLORS.has(zone), "paid zone %s has a label colour" % zone)

	var centro: Dictionary = {"id": "o1", "zone": "centro"}
	_expect(DistrictLabel.color_for_order(centro) == DistrictLabel.color_for(&"centro"), "order takes its zone colour")
	_expect(DistrictLabel.color_for_order({}) == DistrictLabel.FALLBACK_COLOR, "an order without zone gets the fallback")
	_expect(DistrictLabel.color_for(&"atlantida") == DistrictLabel.FALLBACK_COLOR, "an unknown zone gets the fallback")
	_expect(DistrictLabel.name_key(&"atlantida") == &"", "an unknown zone has no name key")
	_expect(DistrictLabel.district_name(&"atlantida") == "", "an unknown zone has no name")

	var csv: String = FileAccess.get_file_as_string("res://translations/strings_ui.csv")
	for zone: StringName in DistrictLabel.NAME_KEYS:
		var key: StringName = DistrictLabel.name_key(zone)
		_expect(csv.contains("\n%s," % key), "%s is in strings_ui.csv" % key)

	_expect(DistrictLabel.same_district(centro, {"id": "o2", "zone": "centro"}), "two centro orders share the district")
	_expect(not DistrictLabel.same_district(centro, {"id": "o3", "zone": "campo"}), "centro and campo differ")
	_expect(not DistrictLabel.same_district({}, {}), "orders without zone never match")

	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)

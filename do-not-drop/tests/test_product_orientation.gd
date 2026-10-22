extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_product_orientation.gd
##
## Upright-only products (expansion D-0727, product_orientation.gd and PackedBox.on_side):
## - milk and the wedding cake need the box upright, glass and lamps do not;
## - a standing box is always safe; a laid-down box lists each upright-only product once;
## - the penalty is TIPPED_QUALITY_PENALTY per such product, 0 for a null or empty box;
## - on_side survives a JSON round trip and defaults to false in old snapshots.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(ProductOrientation.needs_upright(&"milk_canister"), "milk needs upright")
	_expect(ProductOrientation.needs_upright(&"wedding_cake"), "cake needs upright")
	_expect(not ProductOrientation.needs_upright(&"glass_tower"), "glass does not")
	for id: StringName in ProductOrientation.UPRIGHT_ONLY:
		_expect(ResourceLoader.exists("res://data/contents/%s.tres" % id), "%s is in the catalog" % id)

	var box := PackedBox.new(&"L")
	_expect(box.place(load("res://data/contents/milk_canister.tres"), Vector3i.ZERO), "milk placed")
	var lamp: ProductDefinition = load("res://data/contents/antique_lamp.tres")
	_expect(box.place(lamp, box.first_fit(lamp)), "lamp placed")
	_expect(ProductOrientation.is_safe(box), "standing box is safe")
	_expect(ProductOrientation.penalty(box) == 0, "standing box has no penalty")
	box.on_side = true
	_expect(ProductOrientation.tipped(box) == [&"milk_canister"], "laid-down box lists the milk once")
	_expect(
		ProductOrientation.penalty(box) == CompanyTuning.TIPPED_QUALITY_PENALTY,
		"one upright product, one penalty"
	)
	var other := PackedBox.new(&"M")
	other.on_side = true
	other.place(load("res://data/contents/glass_tower.tres"), Vector3i.ZERO)
	_expect(ProductOrientation.is_safe(other), "glass lying down is fine")
	_expect(ProductOrientation.tipped(null).is_empty(), "null box lists nothing")
	_expect(ProductOrientation.penalty(null) == 0, "null box has no penalty")

	var back: PackedBox = PackedBox.from_dict(JSON.parse_string(JSON.stringify(box.to_dict())))
	_expect(back.on_side, "on_side survives a JSON round trip")
	_expect(not PackedBox.from_dict({"box_size": "M"}).on_side, "old snapshots stand upright")

	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)

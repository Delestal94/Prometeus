extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_cold_pack.gd
##
## Cooler with ice (expansion D-0721, cold_pack.gd and PackedBox.ice_packs):
## - only a box holding a cold product counts as cold; a null box or unknown ids do not;
## - add_ice() stops at ICE_PACKS_MAX and a null box refuses;
## - cold lasts COLD_BASE_MINUTES without ice and COLD_PER_ICE_MINUTES more per pack, so the same
##   trip spoils a bare box and holds with enough ice; a box with nothing cold always holds;
## - ice_needed() gives 0 for a short trip and caps at ICE_PACKS_MAX;
## - the ice packs survive a JSON round trip of the box and a bad count is clamped.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var milk: ProductDefinition = load("res://data/products/milk_canister.tres")
	var products: Dictionary = {milk.id: milk}
	var box := PackedBox.new(&"L")
	_expect(not ColdPack.has_cold(box, products), "empty box is not cold")
	_expect(not ColdPack.has_cold(null, products), "null box is not cold")
	box.place(milk, box.first_fit(milk))
	_expect(ColdPack.has_cold(box, products), "box with milk is cold")
	_expect(not ColdPack.has_cold(box, {}), "unknown product id is not cold")

	var base: float = CompanyTuning.COLD_BASE_MINUTES
	_expect(is_equal_approx(ColdPack.cold_minutes(box), base), "bare box lasts the base time")
	_expect(not ColdPack.holds(box, base + 1.0, products), "bare box spoils past the base time")
	_expect(ColdPack.holds(box, base, products), "bare box holds exactly the base time")
	_expect(ColdPack.add_ice(box), "first ice pack goes in")
	var one: float = base + CompanyTuning.COLD_PER_ICE_MINUTES
	_expect(is_equal_approx(ColdPack.cold_minutes(box), one), "one pack adds its minutes")
	_expect(ColdPack.holds(box, base + 1.0, products), "ice saves the trip the bare box lost")
	_expect(ColdPack.add_ice(box), "second ice pack goes in")
	_expect(not ColdPack.add_ice(box), "no more than the maximum")
	_expect(box.ice_packs == CompanyTuning.ICE_PACKS_MAX, "packs stay at the maximum")
	_expect(not ColdPack.add_ice(null), "null box refuses ice")

	var dry := PackedBox.new(&"M")
	_expect(ColdPack.holds(dry, 9999.0, products), "box with nothing cold always holds")

	_expect(ColdPack.ice_needed(base) == 0, "short trip needs no ice")
	_expect(ColdPack.ice_needed(base + 1.0) == 1, "slightly longer trip needs one pack")
	_expect(ColdPack.ice_needed(9999.0) == CompanyTuning.ICE_PACKS_MAX, "needed ice is capped")

	var copy: PackedBox = PackedBox.from_dict(JSON.parse_string(JSON.stringify(box.to_dict())))
	_expect(copy.ice_packs == box.ice_packs, "ice packs survive a JSON round trip")
	var data: Dictionary = box.to_dict()
	data["ice_packs"] = 99
	_expect(PackedBox.from_dict(data).ice_packs == CompanyTuning.ICE_PACKS_MAX, "bad count clamped")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)

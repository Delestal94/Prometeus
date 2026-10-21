extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_pallet_jack.gd
##
## Pallet jack (expansion D-0605, pallet_jack.gd):
## - load_bed() puts valid pallets on the truck bed and skips invalid or repeated ones;
## - the jack carries one pallet at a time and has to be within reach of a floor pallet;
## - put_down() on the floor receives the units into the Inventory once and never twice;
## - a drop outside the floor or on top of another pallet is refused and changes nothing;
## - a pallet that never leaves the bed is never counted and stays in left_on_bed();
## - moving a pallet 50 times loses and duplicates no unit; to_dict/from_dict round trip.

const FLOOR := Rect2(-6.0, -6.0, 12.0, 12.0)

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_unload()
	_test_one_at_a_time_and_reach()
	_test_blocked_drops()
	_test_left_on_bed()
	_test_many_moves_and_json()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _yard() -> PalletJack:
	var jack := PalletJack.new()
	var pallets: Array[Dictionary] = [
		Pallet.make(&"a", &"hen", 10), Pallet.make(&"b", &"cake", 5), {"id": &"bad"}
	]
	jack.load_bed(pallets)
	return jack


func _test_unload() -> void:
	var jack := _yard()
	var inv := Inventory.new()
	_expect(jack.ids_at(PalletJack.AT_BED) == [&"a", &"b"], "two valid pallets on the bed")
	var again: Array[Dictionary] = [Pallet.make(&"a", &"hen", 3)]
	_expect(jack.load_bed(again) == 0, "a repeated id is skipped")
	_expect(jack.pick_up(&"a"), "picks the pallet up from the bed")
	_expect(inv.count(&"hen") == 0, "units are not counted while on the bed or the jack")
	_expect(jack.put_down(Vector2(0, 0), FLOOR, inv), "puts it down on the floor")
	_expect(inv.count(&"hen", &"pallet:a") == 10, "the units are received at pallet:a")
	_expect(jack.carrying == &"", "the jack is empty again")
	_expect(jack.pick_up(&"a", Vector2(1, 0)), "picks it up from the floor")
	_expect(jack.put_down(Vector2(3, 0), FLOOR, inv), "moves it on the floor")
	_expect(inv.count(&"hen") == 10, "moving it again does not receive it twice")


func _test_one_at_a_time_and_reach() -> void:
	var jack := _yard()
	var inv := Inventory.new()
	_expect(jack.pick_up(&"a"), "first pallet")
	_expect(not jack.pick_up(&"b"), "a full jack takes no second pallet")
	_expect(jack.put_down(Vector2(0, 0), FLOOR, inv), "drops the first")
	_expect(not jack.pick_up(&"a", Vector2(5, 5)), "out of reach of a floor pallet")
	_expect(jack.pick_up(&"a", Vector2(0.5, 0.5)), "within reach of a floor pallet")
	_expect(not jack.pick_up(&"nope"), "an unknown pallet cannot be picked up")


func _test_blocked_drops() -> void:
	var jack := _yard()
	var inv := Inventory.new()
	jack.pick_up(&"a")
	_expect(not jack.put_down(Vector2(5.9, 0), FLOOR, inv), "outside the floor is refused")
	_expect(inv.count(&"hen") == 0 and jack.carrying == &"a", "the refusal changed nothing")
	_expect(jack.put_down(Vector2(0, 0), FLOOR, inv), "a free spot works")
	jack.pick_up(&"b")
	_expect(not jack.put_down(Vector2(0.5, 0.2), FLOOR, inv), "on top of another pallet is refused")
	_expect(jack.put_down(Vector2(2.0, 0), FLOOR, inv), "next to it works")


func _test_left_on_bed() -> void:
	var jack := _yard()
	var inv := Inventory.new()
	jack.pick_up(&"a")
	jack.put_down(Vector2(0, 0), FLOOR, inv)
	_expect(jack.left_on_bed().size() == 1 and jack.left_on_bed()[0]["id"] == &"b", "b stays on the bed")
	_expect(inv.count(&"cake") == 0, "the pallet left on the bed is never counted")
	_expect(not jack.remove(&"missing"), "removing an unknown pallet fails")
	_expect(jack.remove(&"a") and not jack.places.has(&"a"), "an emptied pallet leaves the yard")


func _test_many_moves_and_json() -> void:
	var jack := _yard()
	var inv := Inventory.new()
	for i in 50:
		var x: float = -4.0 + float(i % 2) * 6.0
		var from := Vector2(2.0 if i % 2 == 0 else -4.0, 0.0)
		_expect(jack.pick_up(&"a", from), "pick %d" % i)
		_expect(jack.put_down(Vector2(x, 0.0), FLOOR, inv), "drop %d" % i)
	_expect(inv.count(&"hen") == 10 and inv.total_units() == 10, "50 moves lose and duplicate nothing")
	var copy := PalletJack.new()
	copy.from_dict(jack.to_dict())
	_expect(copy.ids_at(PalletJack.AT_FLOOR) == [&"a"], "round trip keeps the floor pallet")
	_expect(copy.ids_at(PalletJack.AT_BED) == [&"b"], "round trip keeps the bed pallet")
	_expect(copy.places[&"a"]["pos"] == jack.places[&"a"]["pos"], "round trip keeps the position")

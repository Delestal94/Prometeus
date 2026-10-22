extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_pallet_forklift.gd
##
## Pallet forklift (expansion D-0606, pallet_forklift.gd and the rack slots of pallet_jack.gd):
## - the forks rise and fall at a fixed speed and stay inside 0..FORKLIFT_MAX_LIFT_M;
## - a pallet is taken from the bed or the floor with the forks down, and not with them up;
## - a pallet goes on a rack slot only with the forks at its level, within reach, and on a free slot;
## - the units are received into the Inventory once, whether the pallet goes to the floor or a rack;
## - a pallet on a rack is taken back at that level, and the manual jack and forklift share the ledger;
## - 50 trips between the bed, the floor and a rack lose and duplicate nothing; JSON keeps the slot.

const FLOOR := Rect2(-6.0, -6.0, 12.0, 12.0)
const LEVELS := {&"r1_hi": 1.4, &"r1_top": 2.2}
const SLOT_POS := Vector2(4.0, 0.0)

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_lift()
	_test_rack_drop()
	_test_pick_levels()
	_test_shared_ledger_and_trips()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _yard() -> PalletJack:
	var jack := PalletJack.new()
	var pallets: Array[Dictionary] = [Pallet.make(&"a", &"hen", 10), Pallet.make(&"b", &"cake", 5)]
	jack.load_bed(pallets)
	return jack


func _raise_to(fork: PalletForklift, height: float) -> void:
	fork.set_height(height)


func _test_lift() -> void:
	var fork := PalletForklift.new()
	fork.lift(1.0, 1.0)
	_expect(is_equal_approx(fork.fork_height, CompanyTuning.FORKLIFT_LIFT_SPEED), "one second up is one speed step")
	fork.lift(1.0, 100.0)
	_expect(is_equal_approx(fork.fork_height, CompanyTuning.FORKLIFT_MAX_LIFT_M), "the mast stops the forks")
	fork.lift(-1.0, 100.0)
	_expect(fork.fork_height == 0.0, "the forks do not go below the floor")
	fork.lift(1.0, -5.0)
	_expect(fork.fork_height == 0.0, "a negative delta moves nothing")


func _test_rack_drop() -> void:
	var jack := _yard()
	var inv := Inventory.new()
	var fork := PalletForklift.new()
	_expect(fork.pick_up(jack, &"a", Vector2.ZERO), "takes the pallet off the bed with the forks down")
	_expect(not fork.put_on_rack(jack, &"r1_hi", SLOT_POS, 1.4, SLOT_POS, inv), "forks down: no rack drop")
	_raise_to(fork, 1.4)
	_expect(not fork.put_on_rack(jack, &"r1_hi", SLOT_POS, 1.4, Vector2.ZERO, inv), "out of reach: no rack drop")
	_expect(not fork.put_down(jack, Vector2.ZERO, FLOOR, inv), "forks up: no floor drop")
	_expect(inv.count(&"hen") == 0 and jack.carrying == &"a", "the refusals changed nothing")
	_expect(fork.put_on_rack(jack, &"r1_hi", SLOT_POS, 1.4, Vector2(3.5, 0.0), inv), "leaves it on the rack slot")
	_expect(inv.count(&"hen", &"pallet:a") == 10, "the units are received once, at the rack drop")
	_expect(jack.rack_pallet(&"r1_hi") == &"a" and jack.carrying == &"", "the slot holds it and the forks are empty")
	_expect(fork.pick_up(jack, &"b", Vector2.ZERO) == false, "forks up: the bed pallet is out of level")
	fork.set_height(0.0)
	_expect(fork.pick_up(jack, &"b", Vector2.ZERO), "forks down: takes the next pallet")
	_raise_to(fork, 1.4)
	_expect(not fork.put_on_rack(jack, &"r1_hi", SLOT_POS, 1.4, SLOT_POS, inv), "a taken slot is refused")
	_expect(jack.carrying == &"b", "the refused drop kept the pallet on the forks")


func _test_pick_levels() -> void:
	var jack := _yard()
	var inv := Inventory.new()
	var fork := PalletForklift.new()
	fork.pick_up(jack, &"a", Vector2.ZERO)
	_raise_to(fork, 2.2)
	fork.put_on_rack(jack, &"r1_top", SLOT_POS, 2.2, SLOT_POS, inv)
	fork.set_height(0.0)
	_expect(not fork.pick_up(jack, &"a", SLOT_POS, LEVELS), "forks down cannot reach the top slot")
	_raise_to(fork, 2.2 - CompanyTuning.FORKLIFT_LEVEL_TOLERANCE_M * 0.5)
	_expect(fork.pick_up(jack, &"a", SLOT_POS, LEVELS), "within the tolerance of the level takes it")
	_expect(jack.rack_pallet(&"r1_top") == &"", "the slot is free again")
	_expect(not fork.pick_up(jack, &"nope", SLOT_POS, LEVELS), "an unknown pallet is refused")
	fork.set_height(0.0)
	_expect(fork.put_down(jack, Vector2(0, 0), FLOOR, inv), "puts it on the floor")
	_expect(inv.count(&"hen") == 10, "the floor drop does not receive it twice")


func _test_shared_ledger_and_trips() -> void:
	var jack := _yard()
	var inv := Inventory.new()
	var fork := PalletForklift.new()
	_expect(jack.pick_up(&"a"), "the manual jack takes a pallet off the bed")
	_expect(jack.put_down(Vector2(0, 0), FLOOR, inv), "and leaves it on the floor")
	for i in 50:
		var to_rack: bool = i % 2 == 0
		fork.set_height(0.0 if to_rack else 1.4)
		_expect(fork.pick_up(jack, &"a", Vector2.ZERO if to_rack else SLOT_POS, LEVELS), "pick %d" % i)
		if to_rack:
			fork.set_height(1.4)
			_expect(fork.put_on_rack(jack, &"r1_hi", SLOT_POS, 1.4, SLOT_POS, inv), "rack %d" % i)
		else:
			fork.set_height(0.0)
			_expect(fork.put_down(jack, Vector2.ZERO, FLOOR, inv), "floor %d" % i)
	_expect(inv.count(&"hen") == 10 and inv.total_units() == 10, "50 trips lose and duplicate nothing")
	var copy := PalletJack.new()
	copy.from_dict(jack.to_dict())
	_expect(copy.ids_at(PalletJack.AT_BED) == [&"b"], "round trip keeps the bed pallet")
	var on_floor: bool = copy.ids_at(PalletJack.AT_FLOOR) == [&"a"]
	var on_rack: bool = copy.rack_pallet(&"r1_hi") == &"a"
	_expect(on_floor != on_rack, "round trip keeps exactly one place for the pallet")
	var fork_copy := PalletForklift.new()
	fork_copy.from_dict(fork.to_dict())
	_expect(is_equal_approx(fork_copy.fork_height, fork.fork_height), "the fork height round-trips")

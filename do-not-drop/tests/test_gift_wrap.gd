extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gift_wrap.gd
##
## Gift paper (expansion D-0723, gift_wrap.gd and PackedBox.gift_wrapped):
## - only a taped box can be wrapped, once; a null box refuses;
## - a gift order pays GIFT_WRAP_BONUS of its pay when delivered wrapped, nothing when unwrapped;
## - a wrapped box on an order that is not a gift earns nothing;
## - the wrap survives a JSON round trip of the box and defaults to false.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var box := PackedBox.new(&"M")
	_expect(not GiftWrap.wrap(box), "an open box cannot be wrapped")
	_expect(not GiftWrap.wrap(null), "null box refuses")
	box.taped = true
	_expect(GiftWrap.wrap(box), "taped box is wrapped")
	_expect(box.gift_wrapped, "the box remembers the paper")
	_expect(not GiftWrap.wrap(box), "no second layer of paper")

	var gift: Dictionary = {"requirements": ["gift", "fragile"]}
	var plain: Dictionary = {"requirements": ["fragile"]}
	_expect(GiftWrap.is_gift(gift), "gift order is a gift")
	_expect(not GiftWrap.is_gift(plain), "plain order is not")
	_expect(GiftWrap.bonus(100, box, gift) == roundi(100 * CompanyTuning.GIFT_WRAP_BONUS), "wrapped gift pays extra")
	_expect(GiftWrap.bonus(100, box, plain) == 0, "wrapped box on a plain order earns nothing")
	_expect(GiftWrap.bonus(100, PackedBox.new(&"M"), gift) == 0, "unwrapped gift earns nothing")
	_expect(GiftWrap.bonus(100, null, gift) == 0, "null box earns nothing")

	var back: PackedBox = PackedBox.from_dict(JSON.parse_string(JSON.stringify(box.to_dict())))
	_expect(back.gift_wrapped, "wrap survives a JSON round trip")
	_expect(not PackedBox.from_dict({"box_size": "M"}).gift_wrapped, "old snapshots are unwrapped")

	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)

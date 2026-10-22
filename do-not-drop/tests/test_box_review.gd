extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_box_review.gd
##
## Quality check by a second player (expansion D-0734, box_review.gd, PackedBox.reviewed_by and
## PackingStation.review), for an order of one porcelain vase that asks for the fragile seal:
## - the reviewer must be someone else than the packer, both known; a null or taped box is refused;
## - the report lists every fault (wrong contents, free cells, missing seal, no label or another order's);
## - a faultless box gives an empty report and is marked; faults are reported but do not mark it;
## - a box is reviewed once; touching its content afterwards (product, padding, seal, label) loses the
##   review, taping does not;
## - the delivered box pays BOX_REVIEW_BONUS only with a standing review and no fault;
## - the mark survives a JSON round trip, old boxes have none, and PackingStation.review reaches the table.

const VASE: ProductDefinition = preload("res://data/products/porcelain_vase.tres")
const HEN: ProductDefinition = preload("res://data/products/hen.tres")
const ORDER: Dictionary = {
	"id": &"o1",
	"items": [{"product": &"porcelain_vase", "qty": 1}],
	"requirements": [&"fragile"],
}
const ANA: StringName = &"peer:2"
const BEN: StringName = &"peer:3"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_refusals()
	_test_report()
	_test_review_and_changes()
	_test_bonus()
	_test_persistence_and_table()
	quit(_failures)


func _test_refusals() -> void:
	var box: PackedBox = _good_box()
	var same: Dictionary = BoxReview.review(box, ORDER, ANA, ANA)
	_expect(not same["counted"] and same["reason"] == BoxReview.REASON_SAME_PERSON, "packer cannot review own box")
	_expect(box.reviewed_by == &"" and not BoxReview.is_reviewed(box), "a refused review marks nothing")
	_expect(BoxReview.review(box, ORDER, &"", BEN)["reason"] == BoxReview.REASON_NO_PEOPLE, "unknown packer")
	_expect(BoxReview.review(box, ORDER, ANA, &"")["reason"] == BoxReview.REASON_NO_PEOPLE, "unknown reviewer")
	_expect(BoxReview.review(null, ORDER, ANA, BEN)["reason"] == BoxReview.REASON_NO_BOX, "null box refuses")
	box.taped = true
	var closed: Dictionary = BoxReview.review(box, ORDER, ANA, BEN)
	_expect(closed["reason"] == BoxReview.REASON_TAPED and box.reviewed_by == &"", "a taped box is not opened")


func _test_report() -> void:
	_expect(BoxReview.report(_good_box(), ORDER).is_empty(), "a correct box has an empty report")
	var hen := PackedBox.new(&"M")
	hen.place(HEN, Vector3i.ZERO)
	var kinds: Dictionary = _kinds(BoxReview.report(hen, ORDER))
	_expect(kinds.get(BoxReview.MISSING) == &"porcelain_vase", "report: vase missing")
	_expect(kinds.get(BoxReview.EXTRA) == &"hen", "report: hen is extra")
	_expect(kinds.has(BoxReview.GAPS), "report: free cells")
	_expect(kinds.get(BoxReview.SEAL) == &"fragile", "report: fragile seal missing")
	_expect(kinds.has(BoxReview.LABEL), "report: no label")
	var gaps: Dictionary = {}
	for fault: Dictionary in BoxReview.report(hen, ORDER):
		gaps[fault["kind"]] = fault
	_expect(
		int(gaps[BoxReview.GAPS]["count"]) == hen.total_cells() - hen.grid.size(), "report: counts the free cells"
	)
	var other: PackedBox = _good_box()
	other.label_order_id = &"o9"
	_expect(_kinds(BoxReview.report(other, ORDER)).has(BoxReview.LABEL), "report: label of another order")
	var unlabeled: Dictionary = {"items": [{"product": &"porcelain_vase", "qty": 1}]}
	var no_id: PackedBox = _good_box()
	_expect(BoxReview.report(no_id, unlabeled).is_empty(), "an order without id accepts any label")
	_expect(BoxReview.report(null, ORDER).size() >= 1, "null box has faults")
	# Padding the gaps clears them.
	var loose := PackedBox.new(&"M")
	loose.place(VASE, Vector3i.ZERO)
	loose.label_order_id = &"o1"
	loose.stamps.append(&"fragile")
	_expect(_kinds(BoxReview.report(loose, ORDER)).has(BoxReview.GAPS), "unpadded box reports gaps")
	loose.fill_free_cells(loose.total_cells())
	_expect(BoxReview.report(loose, ORDER).is_empty(), "padded box reports nothing")


func _test_review_and_changes() -> void:
	var bad := PackedBox.new(&"S")
	bad.place(VASE, Vector3i.ZERO)
	var faulty: Dictionary = BoxReview.review(bad, ORDER, ANA, BEN)
	_expect(not faulty["counted"] and faulty["reason"] == BoxReview.REASON_FAULTS, "faulty review does not count")
	_expect((faulty["faults"] as Array).size() == 2, "faulty review lists seal and label")
	_expect(not BoxReview.is_reviewed(bad), "faulty box stays unmarked")
	bad.label_order_id = &"o1"
	bad.stamps.append(&"fragile")
	_expect(BoxReview.review(bad, ORDER, ANA, BEN)["counted"], "after fixing the faults it can be checked again")

	var box: PackedBox = _good_box()
	var result: Dictionary = BoxReview.review(box, ORDER, ANA, BEN)
	_expect(result["counted"] and (result["faults"] as Array).is_empty(), "correct box: empty report, counted")
	_expect(box.reviewed_by == BEN and BoxReview.is_reviewed(box), "the box remembers who checked it")
	var again: Dictionary = BoxReview.review(box, ORDER, ANA, &"peer:4")
	_expect(not again["counted"] and again["reason"] == BoxReview.REASON_ALREADY, "no second review")
	_expect(box.reviewed_by == BEN, "the first reviewer stays")
	box.taped = true
	_expect(BoxReview.is_reviewed(box), "taping after the check keeps it")

	var changed: PackedBox = _reviewed_box()
	changed.stamps.append(&"gift")
	_expect(not BoxReview.is_reviewed(changed), "another seal loses the review")
	changed = _reviewed_box()
	changed.label_order_id = &"o2"
	_expect(not BoxReview.is_reviewed(changed), "another label loses the review")
	changed = _reviewed_box()
	changed.take_out(Vector3i.ZERO)
	_expect(not BoxReview.is_reviewed(changed), "taking the product out loses the review")
	changed.place(VASE, Vector3i.ZERO)
	_expect(BoxReview.is_reviewed(changed), "the very same content is the content that was checked")
	var loose := PackedBox.new(&"M")
	loose.place(VASE, Vector3i.ZERO)
	loose.label_order_id = &"o1"
	loose.stamps.append(&"fragile")
	loose.fill_free_cells(loose.total_cells())
	_expect(BoxReview.review(loose, ORDER, ANA, BEN)["counted"], "padded box is reviewed")
	loose.take_out(Vector3i.ZERO)
	_expect(not BoxReview.is_reviewed(loose), "emptying a reviewed box loses the review")


func _test_bonus() -> void:
	var good: PackedBox = _reviewed_box()
	good.taped = true
	_expect(BoxReview.bonus(100, good, ORDER) == roundi(100 * CompanyTuning.BOX_REVIEW_BONUS), "reviewed box pays")
	_expect(BoxReview.bonus(100, _good_box(), ORDER) == 0, "unreviewed box pays nothing extra")
	_expect(BoxReview.bonus(100, null, ORDER) == 0, "null box pays nothing extra")
	var touched: PackedBox = _reviewed_box()
	touched.stamps.append(&"gift")
	_expect(BoxReview.bonus(100, touched, ORDER) == 0, "a box changed after the check pays nothing extra")
	var other: Dictionary = {"id": &"o1", "items": [{"product": &"hen", "qty": 1}]}
	_expect(BoxReview.bonus(100, good, other) == 0, "reviewed for another order pays nothing extra")
	_expect(CompanyTuning.BOX_REVIEW_BONUS > 0.0 and CompanyTuning.BOX_REVIEW_BONUS < 0.1, "the reward is small")


func _test_persistence_and_table() -> void:
	var box: PackedBox = _reviewed_box()
	var back: PackedBox = PackedBox.from_dict(JSON.parse_string(JSON.stringify(box.to_dict())))
	_expect(back.reviewed_by == BEN, "reviewer survives a JSON round trip")
	_expect(BoxReview.is_reviewed(back), "the review still stands after the round trip")
	back.stamps.append(&"gift")
	_expect(not BoxReview.is_reviewed(back), "and is still lost by a change")
	var old: PackedBox = PackedBox.from_dict({"box_size": "M"})
	_expect(old.reviewed_by == &"" and old.review_seal == 0 and not BoxReview.is_reviewed(old), "old boxes: no review")
	var forged: PackedBox = PackedBox.from_dict(
		{"box_size": "S", "items": [], "reviewed_by": "peer:9", "review_seal": 12345}
	)
	_expect(not BoxReview.is_reviewed(forged), "a review with the wrong seal is not trusted")

	var station: PackingStation = PackingStation.make(&"t1")
	_expect(station.review(ORDER, ANA, BEN)["reason"] == BoxReview.REASON_NO_BOX, "empty table: nothing to check")
	station.start_box(&"S")
	station.stage_product(&"porcelain_vase")
	station.put_in_box(VASE, Vector3i.ZERO)
	var faulty: Dictionary = station.review(ORDER, ANA, BEN)
	_expect(not faulty["counted"], "table box with faults is not marked")
	station.box.label_order_id = &"o1"
	station.box.stamps.append(&"fragile")
	_expect(station.review(ORDER, ANA, BEN)["counted"], "table box without faults is marked")
	var copy: PackingStation = PackingStation.from_dict(JSON.parse_string(JSON.stringify(station.to_dict())))
	_expect(BoxReview.is_reviewed(copy.box), "the table keeps the review through a snapshot")


## A vase filling an S box, labeled and with the fragile seal: no fault for ORDER.
func _good_box() -> PackedBox:
	var box := PackedBox.new(&"S")
	box.place(VASE, Vector3i.ZERO)
	box.label_order_id = &"o1"
	box.stamps.append(&"fragile")
	return box


func _reviewed_box() -> PackedBox:
	var box: PackedBox = _good_box()
	BoxReview.review(box, ORDER, ANA, BEN)
	return box


## kind -> what (the last fault of that kind), to ask "is there a fault of this kind".
func _kinds(faults: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for fault: Dictionary in faults:
		out[fault["kind"]] = fault["what"]
	return out


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)

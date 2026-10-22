class_name BoxReview
extends RefCounted
## Quality check of an open box by a second player (expansion D-0734, "Modo Empresa").
##
## Static and stateless. Before the box is taped, someone other than its packer opens it and checks it
## against its order: the report lists every fault (wrong contents, free cells without padding, missing
## seals, no label or another order's). The report is computed here, from the same rules the door and
## AssemblyQuality use (BoxContentCheck, BoxSeals), so a reviewer can neither invent nor hide a fault.
## Only a faultless box is marked (PackedBox.reviewed_by); the mark is worth something while the box keeps
## the content it had (signature): adding, taking out, padding or stamping afterwards loses it. A box
## delivered with a standing review pays CompanyTuning.BOX_REVIEW_BONUS of its pay on top. Who the packer
## and the reviewer are is up to the caller (the host, from the sender of each request); taping is not
## part of the check, it is what comes next.

## Fault kinds in a report entry {"kind", "what", "count"}.
const MISSING: StringName = &"missing"  ## what = product id, count = units short
const EXTRA: StringName = &"extra"  ## what = product id, count = units left over
const GAPS: StringName = &"gaps"  ## count = free cells without product or padding
const SEAL: StringName = &"seal"  ## what = seal kind the order asks for and the box lacks
const LABEL: StringName = &"label"  ## no label, or the label of another order

## Why a review did not count (review()["reason"]); &"" when it counted.
const REASON_NO_BOX: StringName = &"no_box"
const REASON_TAPED: StringName = &"taped"
const REASON_NO_PEOPLE: StringName = &"no_people"
const REASON_SAME_PERSON: StringName = &"same_person"
const REASON_ALREADY: StringName = &"already_reviewed"
const REASON_FAULTS: StringName = &"faults"


## Every fault of the box for its order, empty when it is fine. A null box misses everything.
static func report(box: PackedBox, order: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var diff: Dictionary = BoxContentCheck.diff(order, box)
	for id: StringName in diff["missing"]:
		out.append({"kind": MISSING, "what": id, "count": int(diff["missing"][id])})
	for id: StringName in diff["extra"]:
		out.append({"kind": EXTRA, "what": id, "count": int(diff["extra"][id])})
	if box == null:
		return out
	var free: int = box.total_cells() - box.grid.size()
	if free > 0:
		out.append({"kind": GAPS, "what": &"", "count": free})
	for kind: StringName in BoxSeals.missing(box, order):
		out.append({"kind": SEAL, "what": kind, "count": 1})
	var wanted: StringName = StringName(str(order.get("id", "")))
	if box.label_order_id == &"" or (wanted != &"" and box.label_order_id != wanted):
		out.append({"kind": LABEL, "what": &"", "count": 1})
	return out


## The reviewer opens the box on the table. {counted, reason, faults}: the faults are always reported;
## the box is marked reviewed (and `counted` is true) only when it has none. Refused, changing nothing,
## for a null or taped box, an empty id, the packer reviewing their own box, or a box already reviewed.
static func review(box: PackedBox, order: Dictionary, packer: StringName, reviewer: StringName) -> Dictionary:
	var out: Dictionary = {"counted": false, "reason": &"", "faults": [] as Array[Dictionary]}
	if box == null:
		out["reason"] = REASON_NO_BOX
	elif box.taped:
		out["reason"] = REASON_TAPED
	elif packer == &"" or reviewer == &"":
		out["reason"] = REASON_NO_PEOPLE
	elif packer == reviewer:
		out["reason"] = REASON_SAME_PERSON
	elif is_reviewed(box):
		out["reason"] = REASON_ALREADY
	if out["reason"] != &"":
		return out
	var faults: Array[Dictionary] = report(box, order)
	out["faults"] = faults
	if not faults.is_empty():
		out["reason"] = REASON_FAULTS
		return out
	box.reviewed_by = reviewer
	box.review_seal = signature(box)
	out["counted"] = true
	return out


## True while the box carries a review made on the content it has now.
static func is_reviewed(box: PackedBox) -> bool:
	return box != null and box.reviewed_by != &"" and box.review_seal == signature(box)


## Extra pay for a box delivered with a standing review and no fault; 0 for anything else.
static func bonus(pay: int, box: PackedBox, order: Dictionary) -> int:
	if not is_reviewed(box) or not report(box, order).is_empty():
		return 0
	return roundi(pay * CompanyTuning.BOX_REVIEW_BONUS)


## Fingerprint of what a review looks at: size, products, padding, seals and label. Tape and the
## extras (ice, paper, note) are left out, so closing the box after the check keeps it.
static func signature(box: PackedBox) -> int:
	if box == null:
		return 0
	var d: Dictionary = box.to_dict()
	return str([d["box_size"], d["items"], d["fill"], d["stamps"], d["label_order_id"]]).hash()

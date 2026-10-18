class_name BoxContentCheck
extends RefCounted
## Is the right stuff in the box? (expansion D-0712, "Modo Empresa").
##
## Static and stateless. Compares what a PackedBox holds with what an Order dictionary asks
## for and says which products are missing and which are extra, with how many units. Two
## moments use it: the table, before taping (PackingStation.content_errors, a warning the
## player can ignore) and the door of the house (door_accepts, the same rule OrderPenalties
## uses to pay 0 for a wrong box).


## {missing, extra}: product id -> units short / units left over. Both empty when the box
## holds exactly the order. A null box is missing everything.
static func diff(order: Dictionary, box: PackedBox) -> Dictionary:
	var wanted: Dictionary = {}
	for item: Dictionary in order.get("items", []):
		var id := StringName(item["product"])
		wanted[id] = int(wanted.get(id, 0)) + int(item["qty"])
	var held: Dictionary = box.contents() if box != null else {}
	var missing: Dictionary = {}
	var extra: Dictionary = {}
	for id: StringName in wanted:
		var short: int = int(wanted[id]) - int(held.get(id, 0))
		if short > 0:
			missing[id] = short
	for id: StringName in held:
		var over: int = int(held[id]) - int(wanted.get(id, 0))
		if over > 0:
			extra[id] = over
	return {"missing": missing, "extra": extra}


## True when nothing is missing and nothing is extra.
static func is_correct(order: Dictionary, box: PackedBox) -> bool:
	if box == null:
		return false
	var d: Dictionary = diff(order, box)
	return (d["missing"] as Dictionary).is_empty() and (d["extra"] as Dictionary).is_empty()


## The door's verdict: same rule as OrderPenalties.matches_order, plus the reason.
## {ok, missing, extra}.
static func door_accepts(order: Dictionary, box: PackedBox) -> Dictionary:
	var d: Dictionary = diff(order, box)
	d["ok"] = is_correct(order, box)
	return d

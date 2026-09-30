extends RefCounted
## The "impatient client" penalty on a run's delivery deadlines (N-227.2), as
## pure data so RunManager only has to relay the result. A failed event cuts
## CUT_FRACTION off the next house's open deadline, never leaving fewer than
## MIN_LEFT seconds from now (and never moving a deadline later): the penalty is
## pressure, not an instant missed deadline.

const CUT_FRACTION: float = 0.15
const MIN_LEFT: float = 10.0


## `deadlines` is RunManager.deadlines ([{house, seconds, reason}]); `delivered`
## says (house -> bool) whether that house's box already arrived. Returns
## {"house": int, "list": Array} with the updated copy, or {} when no house
## after `after_house` has a deadline still open at time `now`.
static func shorten_next(deadlines: Array, after_house: int, now: float, delivered: Callable) -> Dictionary:
	var target: int = -1
	for index: int in deadlines.size():
		var entry: Dictionary = deadlines[index]
		var house: int = int(entry["house"])
		if house <= after_house or delivered.call(house) or float(entry["seconds"]) <= now:
			continue
		if target < 0 or house < int((deadlines[target] as Dictionary)["house"]):
			target = index
	if target < 0:
		return {}
	var updated: Array = deadlines.duplicate(true)
	var chosen: Dictionary = updated[target]
	var seconds: float = float(chosen["seconds"])
	chosen["seconds"] = minf(seconds, maxf(roundf(seconds * (1.0 - CUT_FRACTION)), roundf(now + MIN_LEFT)))
	return {"house": int(chosen["house"]), "list": updated}

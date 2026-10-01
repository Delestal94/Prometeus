extends RefCounted
## Delivery deadlines of a run (N-225.5), split out of run_manager.gd: the plan from the road's distances, which
## one is next for the HUD and the met / missed tally. The list itself (`RunManager.deadlines`), its relay and
## the "impatient client" cut stay on the autoload, which owns the state and the network checks.

const DELIVERIES = preload("res://scripts/core/run_deliveries.gd")

## Delivery deadlines (docs/jugabilidad-paquetes-rescate.md, "Presión para
## conducir rápido"): up to three houses get one, computed from where they
## really are on the generated road. DEADLINE_SPEED sits a little over the
## bench's average cruise (route.gd ROUTE_CRUISE_SPEED, 12.8 m/s), so taking
## every bonus means pushing on several legs; DEADLINE_SLACK leaves room for
## one short rescue stop. Missing one costs a little pay, never the cargo.
const MAX_DEADLINES: int = 3
const DEADLINE_SPEED: float = 13.5
const DEADLINE_SLACK: float = 15.0
const DEADLINE_STOP_SECONDS: float = 25.0
const POINTS_DEADLINE_MET: int = 40
const PENALTY_DEADLINE_MISSED: int = 15
## strings_ui.csv keys: they travel as keys and each peer's HUD translates them.
const DEADLINE_REASONS: Array[String] = ["HUD_DEADLINE_REASON_LEAVING", "HUD_DEADLINE_REASON_BIRTHDAY",
	"HUD_DEADLINE_REASON_SHOP"]


## Deadlines for houses at these distances along the road (metres, in house
## order). Each one budgets the driving at DEADLINE_SPEED plus the stops at
## the houses before it -- a fixed timer would be impossible on a long route
## and free on a short one.
static func plan(distances: Array) -> Array:
	var planned: Array = []
	for index: int in mini(distances.size(), MAX_DEADLINES):
		var seconds: float = DEADLINE_SLACK + float(distances[index]) / DEADLINE_SPEED + index * DEADLINE_STOP_SECONDS
		var reason: String = DEADLINE_REASONS[index % DEADLINE_REASONS.size()]
		planned.append({"house": index, "seconds": roundf(seconds), "reason": reason})
	return planned


## The closest deadline still open, for the HUD: {} when there is none.
static func next_open(deadlines: Array, deliveries: Array, elapsed_seconds: float) -> Dictionary:
	var best: Dictionary = {}
	for deadline: Dictionary in deadlines:
		if DELIVERIES.delivered_at(deliveries, int(deadline["house"])) or elapsed_seconds > float(deadline["seconds"]):
			continue
		if best.is_empty() or float(deadline["seconds"]) < float(best["seconds"]):
			best = deadline
	return best


## Met / missed counts over this run's deadlines, from the delivery record.
static func tally(deadlines: Array, deliveries: Array) -> Dictionary:
	var met: int = 0
	var missed: int = 0
	for deadline: Dictionary in deadlines:
		var on_time: bool = false
		for entry: Dictionary in deliveries:
			if int(entry["house"]) == int(deadline["house"]) and DELIVERIES.handed_over(StringName(entry["outcome"])):
				on_time = float(entry.get("at", INF)) <= float(deadline["seconds"])
		if on_time:
			met += 1
		else:
			missed += 1
	return {"met": met, "missed": missed}

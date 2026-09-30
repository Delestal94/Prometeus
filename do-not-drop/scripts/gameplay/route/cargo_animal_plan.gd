class_name CargoAnimalPlan
extends RefCounted
## What the animals that go for the cargo (N-109) will do this run, worked out
## from the session seed alone: every peer, and the same seed on another day,
## deals the same legs. A "leg" is the stretch up to a door (leg 0 is the
## drive to the first house; the last one is the drive to the goal).
##
## The rhythm is fixed here, not left to luck:
##   - never on the first leg (the crew is still learning the truck);
##   - at most one animal per leg, and never on two legs in a row;
##   - about half of the remaining legs get one.
## What is left to the moment is whether the animal *can* act (a box on the
## rack for the gull, an open one for the dog and the bees): cargo_animals.gd
## checks that, and an animal with nothing to go for simply doesn't come.

const GULL: StringName = &"gull"
const DOG: StringName = &"dog"
const BEES: StringName = &"bees"

const FIRST_EVENT_LEG: int = 1
const EVENT_CHANCE: float = 0.55
## Seconds of driving into the leg before a moving animal (gull, bees) may
## show up: after the crew has had time to settle, well before the door.
const MIN_MOVING_SECONDS: float = 14.0
const MAX_MOVING_SECONDS: float = 42.0
## Relative odds of each kind, in this order.
const KINDS: Array[StringName] = [GULL, DOG, BEES]
const WEIGHTS: Array[float] = [4.0, 3.0, 3.0]


## The animal planned for `leg`, or an empty dictionary for a quiet leg:
## {"kind": StringName, "moving_seconds": float, "leg": int}.
static func for_leg(world_seed: int, leg: int) -> Dictionary:
	if leg < FIRST_EVENT_LEG:
		return {}
	var previous_had_one: bool = false
	var draw: Dictionary = {}
	for index: int in range(FIRST_EVENT_LEG, leg + 1):
		draw = _draw(world_seed, index)
		var has_one: bool = bool(draw["hit"]) and not previous_had_one
		if index == leg:
			return {"kind": draw["kind"], "moving_seconds": draw["seconds"], "leg": leg} if has_one else {}
		previous_had_one = has_one
	return {}


## The plan for legs 0..count-1, for a test or a debug print.
static func for_run(world_seed: int, legs: int) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	for leg: int in range(legs):
		plans.append(for_leg(world_seed, leg))
	return plans


## Its own seeded stream per leg, always read in the same order (roll, kind,
## seconds), so changing one thing never moves the others.
static func _draw(world_seed: int, leg: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, leg, &"cargo_animal"])
	var roll: float = rng.randf()
	var kind_roll: float = rng.randf()
	var seconds: float = rng.randf_range(MIN_MOVING_SECONDS, MAX_MOVING_SECONDS)
	return {"hit": roll < EVENT_CHANCE, "kind": _kind_for(kind_roll), "seconds": seconds}


static func _kind_for(roll: float) -> StringName:
	var total: float = 0.0
	for weight: float in WEIGHTS:
		total += weight
	var cursor: float = roll * total
	for index: int in range(KINDS.size()):
		cursor -= WEIGHTS[index]
		if cursor < 0.0:
			return KINDS[index]
	return KINDS[KINDS.size() - 1]

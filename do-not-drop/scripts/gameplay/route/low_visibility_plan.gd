extends RefCounted
class_name LowVisibilityPlan
## The pure half of the low-visibility event (tareas de Nacho N-113): how long
## it lasts, when it may come, the draw the host makes from the world seed and
## how much of the glass the mud covers as it goes. No autoloads in here, so
## the windshield, the tests and low_visibility_event.gd (the node that runs
## it) all read the same numbers.

const KIND_MUD: StringName = &"mud"
## Kinds a draw may pick. Fog and a box in the way (M-11's other two) would
## join here; the overlay and the HUD are per kind already.
const KINDS: Array[StringName] = [KIND_MUD]
## Mixed into the world seed so these draws share no sequence with other rolls.
const SEED_SALT: int = 113
## A draw every this many seconds of run time.
const SPACING: float = 5.0
## Chance that a draw starts one when the moment is right. Rare: about a third
## of a typical three-minute delivery sees one, and Endless one every eight
## minutes or so (the cooldown plus the wait for a lucky draw).
const CHANCE: float = 0.015
const MIN_DURATION: float = 10.0
const MAX_DURATION: float = 20.0
## Nothing in the run's first seconds: the crew is still settling.
const START_GRACE_SECONDS: float = 45.0
## From the end of one to the start of the next.
const COOLDOWN_SECONDS: float = 120.0
## Deliveries with houses: at most this many per run. Endless: no cap.
const MAX_PER_DELIVERY: int = 1
## Too slow and nobody needs guiding.
const MIN_SPEED: float = 4.0
## The mud lands and clears over these, so the glass is never a hard cut.
const FADE_IN_SECONDS: float = 0.8
const FADE_OUT_SECONDS: float = 1.6


## How much of the glass the mud covers now, 0..1: fades in, holds, fades out.
static func coverage(seconds: float, duration: float) -> float:
	var rising: float = clampf(seconds / FADE_IN_SECONDS, 0.0, 1.0)
	var falling: float = clampf((duration - seconds) / FADE_OUT_SECONDS, 0.0, 1.0)
	return smoothstep(0.0, 1.0, minf(rising, falling))


## Draw number `index` of a run: {"hit", "duration", "kind"}. A pure function
## of its arguments, so every seed always plays out the same.
static func draw(session_seed: int, salt: int, index: int, odds: float = CHANCE) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([session_seed, SEED_SALT, salt, index])
	var roll: float = rng.randf()
	var duration: float = rng.randf_range(MIN_DURATION, MAX_DURATION)
	var kind: StringName = KINDS[rng.randi_range(0, KINDS.size() - 1)]
	return {"hit": roll < odds, "duration": duration, "kind": kind}


## Every start a run of `seconds` would see with nothing in the way (a driver
## always moving, no houses), for tests and tuning: [{"at", "duration", "kind"}].
static func plan(session_seed: int, seconds: float, salt: int = 0, odds: float = CHANCE,
		endless: bool = false) -> Array[Dictionary]:
	var starts: Array[Dictionary] = []
	var free_at: float = 0.0
	var index: int = 0
	var at: float = SPACING
	while at <= seconds:
		index += 1
		if at >= START_GRACE_SECONDS and at >= free_at and (endless or starts.size() < MAX_PER_DELIVERY):
			var result: Dictionary = draw(session_seed, salt, index, odds)
			if bool(result.hit):
				starts.append({"at": at, "duration": float(result.duration), "kind": result.kind})
				free_at = at + float(result.duration) + COOLDOWN_SECONDS
		at += SPACING
	return starts

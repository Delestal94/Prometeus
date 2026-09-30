class_name BossLines
extends RefCounted
## What the Boss says over the depot's radio when the day starts (S-603,
## docs/narrativa.md): Marta Bermudez never shows up, she only talks by radio
## and leaves notes on the board. Dry, practical, always "in something else",
## she treats every disaster as paperwork -- never shouts, never mocks the crew.
##
## A pure module: given the day's context and the session seed it picks the
## same lines every time, and returns them as LocText lines ([key, args...]),
## never built text, so the host decides and each peer translates into its own
## language. Depot (depot.gd) is the one that asks, host-side, and hands the
## result to every peer.
##
## Two lines at most:
##   - the start line, from the order (how many houses, which traps: the hen is
##     "Ruidoso", the fireworks "Explosivo") and the campaign (finished runs,
##     team money). Endless has its own small pool: no houses, no orders;
##   - a reaction to the last run (broken, lost, all clean, the first day), only
##     for delivery days -- endless days get none, the board already keeps the
##     record there.
##
## Every string key is quoted here on purpose: test_world_translations scans the
## scripts for quoted WORLD_* keys, and test_boss_lines checks each in es and en.

## Where in the salt the day is drawn: the same seed, runs and houses always give
## the same lines, a new day (one more finished run) gives another draw.
const SALT: int = 0x603b055
## Chance to draw a line about today's order or campaign over a generic one,
## when at least one such line applies.
const SPECIFIC_CHANCE: float = 0.75
## Money at which the campaign has "a lot" / "hardly any" in the till.
const MONEY_RICH: int = 200
const MONEY_POOR: int = 40
## Finished runs at which the crew stops being new / becomes veteran.
const RUNS_ROOKIE_UNTIL: int = 2
const RUNS_VETERAN_FROM: int = 8
## Houses from which the day counts as a long one.
const HOUSES_MANY: int = 5
## Days without accidents worth mentioning.
const STREAK_MIN: int = 3

## Delivery days. "rule" says when it applies (see _applies), "args" what goes
## into the line (see _args). Rule &"any" is the generic filler.
const START_LINES: Array[Dictionary] = [
	{"key": "WORLD_BOSS_START_ONE", "rule": &"one_house"},
	{"key": "WORLD_BOSS_START_MANY", "rule": &"many_houses", "args": &"houses"},
	{"key": "WORLD_BOSS_START_HEN", "rule": &"noisy_pack", "args": &"houses"},
	{"key": "WORLD_BOSS_START_NOISY", "rule": &"noisy"},
	{"key": "WORLD_BOSS_START_EXPLOSIVE", "rule": &"explosive"},
	{"key": "WORLD_BOSS_START_FRAGILE", "rule": &"fragile"},
	{"key": "WORLD_BOSS_START_LIQUID", "rule": &"liquid"},
	{"key": "WORLD_BOSS_START_GROWING", "rule": &"growing_weight"},
	{"key": "WORLD_BOSS_START_BALANCE", "rule": &"balance"},
	{"key": "WORLD_BOSS_START_HOSTILE", "rule": &"hostile"},
	{"key": "WORLD_BOSS_START_MIXED", "rule": &"mixed"},
	{"key": "WORLD_BOSS_START_ROOKIE", "rule": &"rookie"},
	{"key": "WORLD_BOSS_START_VETERAN", "rule": &"veteran", "args": &"runs"},
	{"key": "WORLD_BOSS_START_RICH", "rule": &"rich", "args": &"money"},
	{"key": "WORLD_BOSS_START_POOR", "rule": &"poor", "args": &"money"},
	{"key": "WORLD_BOSS_START_GENERIC_1", "rule": &"any"},
	{"key": "WORLD_BOSS_START_GENERIC_2", "rule": &"any"},
	{"key": "WORLD_BOSS_START_GENERIC_3", "rule": &"any"},
	{"key": "WORLD_BOSS_START_GENERIC_4", "rule": &"any"},
	{"key": "WORLD_BOSS_START_GENERIC_5", "rule": &"any"},
]

## Endless days: their own lines, or none would fit a road with no houses.
const ENDLESS_LINES: Array[Dictionary] = [
	{"key": "WORLD_BOSS_ENDLESS_1", "rule": &"any"},
	{"key": "WORLD_BOSS_ENDLESS_2", "rule": &"any"},
	{"key": "WORLD_BOSS_ENDLESS_3", "rule": &"any"},
	{"key": "WORLD_BOSS_ENDLESS_BEST", "rule": &"has_best", "args": &"best"},
]

## Reactions to the last delivery run, most specific first: the first whose
## rule applies is the one (see _applies).
const REACTION_LINES: Array[Dictionary] = [
	{"key": "WORLD_BOSS_REACT_FIRST", "rule": &"first_day"},
	{"key": "WORLD_BOSS_REACT_NOTHING", "rule": &"nothing_arrived"},
	{"key": "WORLD_BOSS_REACT_BOTH", "rule": &"ruined_and_lost"},
	{"key": "WORLD_BOSS_REACT_RUINED_MANY", "rule": &"ruined_many", "args": &"ruined"},
	{"key": "WORLD_BOSS_REACT_RUINED_ONE", "rule": &"ruined_one"},
	{"key": "WORLD_BOSS_REACT_LOST", "rule": &"lost", "args": &"lost"},
	{"key": "WORLD_BOSS_REACT_STREAK", "rule": &"streak", "args": &"streak"},
	{"key": "WORLD_BOSS_REACT_PERFECT", "rule": &"perfect"},
]


## The day's context, from what the depot knows: `orders` are the depot's
## (each with "trap_id"), `runs` the finished runs, `money` the team's,
## `log` the campaign log (DepotCampaignBoard.load_log()), `endless_best` the
## endless record.
static func make_context(orders: Array, runs: int, money: int, log: Dictionary, endless_best: int) -> Dictionary:
	var traps: Array[StringName] = []
	for order: Variant in orders:
		traps.append(StringName((order as Dictionary).get("trap_id", &"")))
	var last: Variant = log.get("last", {})
	return {
		"houses": orders.size(),
		"traps": traps,
		"runs": runs,
		"money": money,
		"streak": int(log.get("days", 0)),
		"last": last if last is Dictionary else {},
		"best": endless_best,
	}


## What a finished run leaves behind for tomorrow's reaction, from
## RunManager.results (kept in the campaign log). Delivery and endless runs
## both write one; `mode` tells them apart.
static func summarize_run(results: Dictionary) -> Dictionary:
	var endless: bool = results.has("distance_traveled")
	return {
		"mode": "endless" if endless else "delivery",
		"delivered": bool(results.get("delivered", false)),
		"ruined": int(results.get("cargo_ruined", 0)),
		"lost": int(results.get("houses_lost", 0)),
		"missed": int(results.get("houses_missed", 0)),
		"houses_delivered": int(results.get("houses_delivered", 0)),
	}


## [start, reaction] as LocText lines; the reaction is left out when there is
## none to give. There is always a start line.
static func pick(context: Dictionary, session_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([session_seed, SALT, int(context.get("runs", 0)), int(context.get("houses", 0))])
	var lines: Array = []
	if int(context.get("houses", 0)) == 0:
		lines.append(_draw(ENDLESS_LINES, context, rng))
		return lines
	lines.append(_draw(START_LINES, context, rng))
	var reaction: Array = _reaction(context)
	if not reaction.is_empty():
		lines.append(reaction)
	return lines


## The start line of a pool, drawn with `rng`: from the lines that speak of the
## day (a specific rule) most of the time, a generic one otherwise.
static func _draw(pool: Array[Dictionary], context: Dictionary, rng: RandomNumberGenerator) -> Array:
	var specific: Array[Dictionary] = []
	var generic: Array[Dictionary] = []
	for entry: Dictionary in pool:
		if entry.rule == &"any":
			generic.append(entry)
		elif _applies(entry.rule, context):
			specific.append(entry)
	# Always the same number of draws, so a line appearing or not never shifts
	# the next one.
	var roll: float = rng.randf()
	var index: int = rng.randi()
	var use_specific: bool = generic.is_empty() or (not specific.is_empty() and roll < SPECIFIC_CHANCE)
	var from: Array[Dictionary] = specific if use_specific else generic
	var chosen: Dictionary = from[index % from.size()]
	return LocText.make(chosen.key, _args(chosen.get("args", &""), context))


static func _reaction(context: Dictionary) -> Array:
	for entry: Dictionary in REACTION_LINES:
		if _applies(entry.rule, context):
			return LocText.make(entry.key, _args(entry.get("args", &""), context))
	return []


static func _applies(rule: StringName, context: Dictionary) -> bool:
	var traps: Array = context.get("traps", [])
	var houses: int = int(context.get("houses", 0))
	var runs: int = int(context.get("runs", 0))
	var money: int = int(context.get("money", 0))
	var last: Dictionary = context.get("last", {})
	# Reactions look at the last delivery run only.
	var last_delivery: bool = not last.is_empty() and String(last.get("mode", "delivery")) == "delivery"
	var ruined: int = int(last.get("ruined", 0))
	var lost: int = int(last.get("lost", 0))
	match rule:
		&"any":
			return true
		&"one_house":
			return houses == 1
		&"many_houses":
			return houses >= HOUSES_MANY
		&"noisy_pack":
			return traps.has(&"noisy") and houses >= 2
		&"noisy", &"explosive", &"fragile", &"liquid", &"growing_weight", &"balance", &"hostile":
			return traps.has(rule)
		&"mixed":
			var kinds: Dictionary = {}
			for trap: Variant in traps:
				kinds[trap] = true
			return kinds.size() >= 3
		&"rookie":
			return runs <= RUNS_ROOKIE_UNTIL
		&"veteran":
			return runs >= RUNS_VETERAN_FROM
		&"rich":
			return money >= MONEY_RICH
		&"poor":
			return money <= MONEY_POOR
		&"has_best":
			return int(context.get("best", 0)) > 0
		&"first_day":
			return last.is_empty() and runs == 0
		&"nothing_arrived":
			return last_delivery and not bool(last.get("delivered", false)) \
					and int(last.get("houses_delivered", 0)) == 0
		&"ruined_and_lost":
			return last_delivery and ruined > 0 and lost > 0
		&"ruined_many":
			return last_delivery and ruined >= 2
		&"ruined_one":
			return last_delivery and ruined == 1
		&"lost":
			return last_delivery and lost > 0
		&"streak":
			return last_delivery and ruined == 0 and int(context.get("streak", 0)) >= STREAK_MIN
		&"perfect":
			return last_delivery and bool(last.get("delivered", false)) and ruined == 0 \
					and int(last.get("missed", 0)) == 0
	return false


static func _args(source: StringName, context: Dictionary) -> Array:
	var last: Dictionary = context.get("last", {})
	match source:
		&"houses":
			return [int(context.get("houses", 0))]
		&"runs":
			return [int(context.get("runs", 0))]
		&"money":
			return [int(context.get("money", 0))]
		&"best":
			return [int(context.get("best", 0))]
		&"streak":
			return [int(context.get("streak", 0))]
		&"ruined":
			return [int(last.get("ruined", 0))]
		&"lost":
			return [int(last.get("lost", 0))]
	return []


## Every string key the module can hand out, for tests and tooling.
static func all_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for pool: Array[Dictionary] in [START_LINES, ENDLESS_LINES, REACTION_LINES]:
		for entry: Dictionary in pool:
			keys.append(entry.key)
	return keys


## The lines in this peer's language, one text each.
static func render(lines: Array) -> Array[String]:
	var texts: Array[String] = []
	for line: Variant in lines:
		var text: String = LocText.render(line)
		if not text.is_empty():
			texts.append(text)
	return texts

class_name CargoAnimals
extends Node
## The animals that go for the cargo (tareas de Nacho N-109, extending N-106
## and N-107): until now the wildlife threatened the road; these three
## threaten a box.
##   - the GULL comes in through the open rear doors and lands on a box on
##     the rack. Unless someone holds the box (its passenger with the primary
##     action, or anyone who picks it up) or the horn sounds, it flies out
##     with it a few seconds later and drops it on the road: the box lands in
##     N-213's rescue window, not straight in the bin;
##   - the DOG climbs onto an open box at a stop by a house and wears it down
##     until it is sent off: a honk, the lid shut, the box lifted, or "Tirarle
##     un palo" (dog_distract_point.gd), which anyone with free hands can do;
##   - BEES come for an open cake (Equilibrio) in open country, and agitate
##     it -- damage and little shoves that tilt the box, which is what
##     Equilibrio's passenger is there to lean against -- until the lid is
##     shut, the horn sounds, or the truck leaves the meadow.
## Nothing acts without warning: every animal is announced (its cry, bark or
## buzz, an icon over the box, a banner) WARN seconds before it starts, and
## most of them can be stopped before that (the horn works at any time).
##
## Rarity and rhythm come from CargoAnimalPlan: one animal per leg at most,
## never two legs running, none on the first, all from the run's seed (the world
## seed mixed with the runs finished, or a fresh roll when playing alone). The
## host decides everything here -- what the plan calls for, whether it can
## act (a box on the rack; an open one), the harm to the box, the throw -- and
## relays the alert and the end to everyone (EventBus.cargo_animal_alert /
## cargo_animal_ended); cargo_animal_view.gd draws it on every peer, and the
## host repeats the alert to a peer that joins in the middle of one.
##
## Cost: nothing while idle but a poll twice a second; while an animal is at
## work a few comparisons a frame (no scans: the level's box list is used).

enum Phase { IDLE, ANNOUNCED, ACTING }

## Truck speed that counts as driving, and as stopped at a door (m/s).
const MOVING_SPEED: float = 4.0
const STOPPED_SPEED: float = 1.5
const POLL_SECONDS: float = 0.5
const MAX_PER_RUN: int = 3
## Endless has no doors: a "leg" there is this much driving.
const ENDLESS_LEG_SECONDS: float = 150.0
const HOUSE_STOP_RADIUS: float = 18.0

## Seconds of warning before each animal starts, and how long it then has.
const WARN_SECONDS: Dictionary = {
	CargoAnimalPlan.GULL: 3.0, CargoAnimalPlan.DOG: 3.0, CargoAnimalPlan.BEES: 3.0}
const ACT_SECONDS: Dictionary = {
	CargoAnimalPlan.GULL: 6.0, CargoAnimalPlan.DOG: 30.0, CargoAnimalPlan.BEES: 14.0}

## Gull: a box held this long (in total, it forgives short lapses) scares it.
const GULL_HOLD_TO_REPEL: float = 1.0
## Where the gull's throw puts the box: out past the rear doors, in the truck's
## space, with this much of the truck's own speed (so it lands in the road
## behind instead of being flung at it) plus this push (out and up).
const SNATCH_OUT: Vector3 = Vector3(0.0, 1.1, 5.3)
const SNATCH_PUSH: Vector3 = Vector3(0.0, 2.2, 5.0)
const SNATCH_TRUCK_SPEED_SHARE: float = 0.4

## Dog: it goes for an open box lying within this of the truck; it wears it
## down at this rate (integrity per second, of 100): over its whole time that
## leaves the box at risk, not ruined -- the crew always has a way to save it.
const DOG_REACH: float = 10.0
const DOG_DAMAGE_PER_SECOND: float = 2.5
const BEES_DAMAGE_PER_SECOND: float = 3.0
## Bees: every so often a shove that spins the box a little (rad/s).
const BEES_KICK_GAP: float = 1.4
const BEES_KICK_SPEED: float = 0.9
## Harm is handed to the box in steps this long, not every tick: every damage
## report is relayed to all peers.
const HARM_STEP_SECONDS: float = 0.25
## After an animal ends, none other is announced for this long: the view is
## still drawing its exit (CargoAnimalView.LEAVE_SECONDS, at most 3 s).
const COOLDOWN_SECONDS: float = 3.5

## Texts, by kind (keys written out in full so test_world_translations sees them).
const ALERT_TEXTS: Dictionary = {
	CargoAnimalPlan.GULL: ["WORLD_GULL_ALERT_TITLE", "WORLD_GULL_ALERT_PROMPT"],
	CargoAnimalPlan.DOG: ["WORLD_DOG_ALERT_TITLE", "WORLD_DOG_ALERT_PROMPT"],
	CargoAnimalPlan.BEES: ["WORLD_BEES_ALERT_TITLE", "WORLD_BEES_ALERT_PROMPT"],
}
const GONE_TITLES: Dictionary = {
	CargoAnimalPlan.GULL: "WORLD_GULL_GONE_TITLE",
	CargoAnimalPlan.DOG: "WORLD_DOG_GONE_TITLE",
	CargoAnimalPlan.BEES: "WORLD_BEES_GONE_TITLE",
}
const OUTCOME_PROMPTS: Dictionary = {
	&"scared": "WORLD_ANIMAL_OUTCOME_SCARED",
	&"held": "WORLD_ANIMAL_OUTCOME_HELD",
	&"distracted": "WORLD_ANIMAL_OUTCOME_DISTRACTED",
	&"sealed": "WORLD_ANIMAL_OUTCOME_SEALED",
	&"left": "WORLD_ANIMAL_OUTCOME_LEFT",
}
const RUIN_CAUSES: Dictionary = {
	CargoAnimalPlan.DOG: "WORLD_CARGO_DOG_RUINED",
	CargoAnimalPlan.BEES: "WORLD_CARGO_BEES_RUINED",
}

## Set by the level (level_common.gd / level_base.gd) right after creating it.
var vehicle: Node3D
## The level's boxes (LevelCommon.packages): the same array, not a copy.
var packages: Array = []
## The route's houses (campaign only), for the dog's stops.
var houses: Array = []
## world position -> true if that is open country (campaign only): bees need it.
var zone_probe: Callable = Callable()
## Endless: no doors, so legs are measured in driving time, and no meadows.
var endless: bool = false

var phase: Phase = Phase.IDLE
var kind: StringName = &""
var target: DeliveryPackage
## Kept apart from `target` so the end and the repeated alert can still name
## the box if it has been freed by then.
var target_id: StringName = &""
var leg: int = 0
var events_this_run: int = 0
var view: CargoAnimalView

var _plan: Dictionary = {}
var _leg_moving: float = 0.0
var _fired: bool = false
var _timer: float = 0.0
var _hold: float = 0.0
var _poll: float = 0.0
var _zone_poll: float = 0.0
var _harm: float = 0.0
var _harm_clock: float = 0.0
var _kick_clock: float = 0.0
var _cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()
# What the plan, the pick, the throw and the kicks are dealt from: fixed per
# run so a room repeats it for the same world and run count, never the same
# run after run (_run_seed(), rolled when the run starts).
var _seed: int = 0
var _seeded: bool = false


func _ready() -> void:
	view = CargoAnimalView.new()
	view.name = "View"
	add_child(view)
	view.dog_thrown.connect(_on_dog_thrown)
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"horn_honked", _on_horn_honked)
		bus.connect(&"house_delivery_recorded", _on_house_delivery_recorded)
		bus.connect(&"run_started", _on_run_started)
		bus.connect(&"run_ended", _on_run_ended)
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network != null and network.has_signal(&"peer_level_ready"):
		network.connect(&"peer_level_ready", _on_peer_level_ready)


func _physics_process(delta: float) -> void:
	advance(delta)


## One tick of the director. Public so a test can run it in big steps.
func advance(delta: float) -> void:
	if not _is_host() or not _run_active() or not is_instance_valid(vehicle):
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if _speed() >= MOVING_SPEED:
		_leg_moving += delta
		if endless and _leg_moving >= ENDLESS_LEG_SECONDS:
			_next_leg()
	match phase:
		Phase.IDLE:
			_advance_idle(delta)
		Phase.ANNOUNCED:
			_advance_announced(delta)
		Phase.ACTING:
			_advance_acting(delta)


## What is planned for the leg the truck is on now (empty for a quiet one).
func current_plan() -> Dictionary:
	return _plan


# --- Waiting for the moment --------------------------------------------------

func _advance_idle(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_SECONDS
	if _fired or _plan.is_empty() or events_this_run >= MAX_PER_RUN or _cooldown > 0.0:
		return
	var planned: StringName = StringName(_plan["kind"])
	var speed: float = _speed()
	var chosen: DeliveryPackage = null
	match planned:
		CargoAnimalPlan.GULL:
			if speed >= MOVING_SPEED and _leg_moving >= float(_plan["moving_seconds"]) and _rear_open():
				chosen = _pick(_gull_candidates())
		CargoAnimalPlan.BEES:
			if speed >= MOVING_SPEED and _leg_moving >= float(_plan["moving_seconds"]) and _in_countryside():
				chosen = _pick(_bee_candidates())
		CargoAnimalPlan.DOG:
			if speed <= STOPPED_SPEED and _at_house_stop():
				chosen = _pick(_dog_candidates())
	if chosen != null:
		_announce(planned, chosen)


## A box on the rack that nobody has in their arms.
func _gull_candidates() -> Array:
	var found: Array = []
	for candidate: Variant in packages:
		var box := candidate as DeliveryPackage
		if _alive(box) and box.is_loaded and not box.is_held and vehicle.call(&"carries", box.global_position):
			found.append(box)
	return found


## The open cake, aboard.
func _bee_candidates() -> Array:
	var found: Array = []
	for candidate: Variant in packages:
		var box := candidate as DeliveryPackage
		if _alive(box) and box.is_open and _is_cake(box) and vehicle.call(&"carries", box.global_position):
			found.append(box)
	return found


## An open box within the dog's reach that nobody is carrying.
func _dog_candidates() -> Array:
	var found: Array = []
	for candidate: Variant in packages:
		var box := candidate as DeliveryPackage
		if _alive(box) and box.is_open and not box.is_held and not box.contents_spilled \
				and box.global_position.distance_to(vehicle.global_position) <= DOG_REACH:
			found.append(box)
	return found


func _alive(box: DeliveryPackage) -> bool:
	return is_instance_valid(box) and not box.is_queued_for_deletion() \
			and box.trap_state != ITrapBehavior.TrapState.RUINED


func _is_cake(box: DeliveryPackage) -> bool:
	var content: Resource = box.content_definition()
	return content != null and StringName(content.get(&"id")) == &"wedding_cake"


## Deterministic: the candidates in a fixed order, one drawn from the session
## seed and the leg.
func _pick(candidates: Array) -> DeliveryPackage:
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a: DeliveryPackage, b: DeliveryPackage) -> bool:
		return String(a.package_id) < String(b.package_id))
	_rng.seed = hash([_run_seed(), leg, &"cargo_animal_pick"])
	return candidates[_rng.randi() % candidates.size()] as DeliveryPackage


# --- The warning and the act -------------------------------------------------

func _announce(animal: StringName, box: DeliveryPackage) -> void:
	kind = animal
	target = box
	target_id = box.package_id
	phase = Phase.ANNOUNCED
	_timer = float(WARN_SECONDS[animal])
	_hold = 0.0
	_harm = 0.0
	_harm_clock = 0.0
	_kick_clock = BEES_KICK_GAP
	_zone_poll = POLL_SECONDS
	_fired = true
	events_this_run += 1
	_relay(&"cargo_animal_alert", [kind, box.package_id, _timer, float(ACT_SECONDS[animal])])
	var texts: Array = ALERT_TEXTS[animal]
	# Keys, not text: each peer's HUD translates them (N-805).
	WildlifeCrossing.report_incident(get_tree(), StringName("cargo_%s_alert" % animal), texts[0], texts[1])


func _advance_announced(delta: float) -> void:
	var over: StringName = _lost_interest()
	if not over.is_empty():
		end_event(over)
		return
	_track_hold(delta)
	if _hold >= GULL_HOLD_TO_REPEL and kind == CargoAnimalPlan.GULL:
		end_event(&"held", _holder_peer())
		return
	_timer -= delta
	if _timer <= 0.0:
		phase = Phase.ACTING
		_timer = float(ACT_SECONDS[kind])


func _advance_acting(delta: float) -> void:
	var over: StringName = _lost_interest()
	if not over.is_empty():
		end_event(over)
		return
	_timer -= delta
	match kind:
		CargoAnimalPlan.GULL:
			_track_hold(delta)
			if _hold >= GULL_HOLD_TO_REPEL:
				end_event(&"held", _holder_peer())
			elif _timer <= 0.0:
				# Somebody lifted it in the last moment: it is theirs, not the gull's.
				if target.is_held:
					end_event(&"held", _holder_peer())
				else:
					_snatch()
		CargoAnimalPlan.DOG:
			_do_harm(DOG_DAMAGE_PER_SECOND * delta, delta)
			if _timer <= 0.0:
				end_event(&"left")
		CargoAnimalPlan.BEES:
			_do_harm(BEES_DAMAGE_PER_SECOND * delta, delta)
			_kick_clock -= delta
			if _kick_clock <= 0.0:
				_kick_clock = BEES_KICK_GAP
				_kick_box()
			_zone_poll -= delta
			if _zone_poll <= 0.0:
				_zone_poll = POLL_SECONDS
				if not _in_countryside():
					end_event(&"left")
					return
			if _timer <= 0.0:
				end_event(&"left")


## Why the animal would stop caring about this box right now, or empty.
func _lost_interest() -> StringName:
	if not _alive(target):
		return &"left"
	match kind:
		CargoAnimalPlan.GULL:
			if not _rear_open() or not (target.is_loaded or target.is_held):
				return &"left"
			# A box that has slid out of the bay is no longer on the rack to take.
			if not target.is_held and not vehicle.call(&"carries", target.global_position, 0.6):
				return &"left"
		CargoAnimalPlan.DOG:
			if not target.is_open or target.contents_spilled:
				return &"sealed"
			if target.is_held:
				return &"held"
			# The truck pulling away, or the box out of the dog's reach, ends it.
			if _speed() >= MOVING_SPEED or target.global_position.distance_to(vehicle.global_position) > DOG_REACH:
				return &"left"
		CargoAnimalPlan.BEES:
			if not target.is_open:
				return &"sealed"
	return &""


## Whether somebody is holding the box the gull is after: in their arms, or
## its passenger with the primary action down.
func _track_hold(delta: float) -> void:
	if _is_held_by_crew():
		_hold += delta
	else:
		_hold = maxf(0.0, _hold - delta)


func _is_held_by_crew() -> bool:
	if target.is_held:
		return true
	return float(target.player_input.get("steady_strength", 0.0)) > 0.0


func _holder_peer() -> int:
	if is_instance_valid(target.carrier):
		return int(target.carrier.get_multiplayer_authority())
	return target.tender_peer_id if target.tender_peer_id > 0 else target.assistant_peer_id


## The gull's throw: out through the rear doors and onto the road.
func _snatch() -> void:
	var box: DeliveryPackage = target
	if box.is_held:
		end_event(&"held", _holder_peer())
		return
	_rng.seed = hash([_run_seed(), leg, &"cargo_animal_snatch"])
	var side: float = _rng.randf_range(-0.5, 0.5)
	var out: Vector3 = vehicle.to_global(SNATCH_OUT + Vector3(side, 0.0, 0.0))
	var carried: Vector3 = vehicle.call(&"point_velocity", out)
	box.freeze = false
	box.global_position = out
	var push: Vector3 = SNATCH_PUSH + Vector3(side * 2.0, 0.0, 0.0)
	box.linear_velocity = carried * SNATCH_TRUCK_SPEED_SHARE + vehicle.global_basis * push
	box.angular_velocity = Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.5, 1.5))
	box.reset_physics_interpolation()
	# The throw is not a collision: don't read the jump in speed as a hit.
	box.set(&"_has_previous_velocity", false)
	end_event(&"snatched", 0, true)
	WildlifeCrossing.report_incident(get_tree(), &"cargo_gull_snatch", "WORLD_GULL_SNATCH_TITLE",
			"WORLD_GULL_SNATCH_PROMPT")


func _do_harm(amount: float, delta: float) -> void:
	_harm += amount
	_harm_clock += delta
	if _harm_clock >= HARM_STEP_SECONDS:
		_flush_harm()


func _flush_harm() -> void:
	_harm_clock = 0.0
	if _harm <= 0.0 or not is_instance_valid(target):
		_harm = 0.0
		return
	target.apply_external_damage(_harm, String(RUIN_CAUSES.get(kind, "WORLD_CARGO_DOG_RUINED")))
	_harm = 0.0


## A shove in a direction drawn from the seed and how many there've been.
func _kick_box() -> void:
	if not is_instance_valid(target) or target.freeze:
		return
	_rng.seed = hash([_run_seed(), leg, &"cargo_animal_kick", int(_timer * 10.0)])
	var angle: float = _rng.randf_range(0.0, TAU)
	target.angular_velocity += Vector3(cos(angle), 0.0, sin(angle)) * BEES_KICK_SPEED


# --- Ending ------------------------------------------------------------------

## Closes the animal that is at work. `quiet` skips the banner (the caller
## says its own).
func end_event(outcome: StringName, peer_id: int = 0, quiet: bool = false) -> void:
	if phase == Phase.IDLE:
		return
	_flush_harm()
	var ended: StringName = kind
	var id: StringName = target_id
	phase = Phase.IDLE
	target = null
	target_id = &""
	kind = &""
	_cooldown = COOLDOWN_SECONDS
	_relay(&"cargo_animal_ended", [ended, id, outcome, peer_id])
	if not quiet and OUTCOME_PROMPTS.has(outcome):
		WildlifeCrossing.report_incident(get_tree(), StringName("cargo_%s_gone" % ended),
				GONE_TITLES[ended], OUTCOME_PROMPTS[outcome])


func _on_horn_honked(peer_id: int) -> void:
	if phase == Phase.IDLE or not _is_host():
		return
	# The dog is on the ground by the truck; the gull and the bees are on it.
	if kind == CargoAnimalPlan.DOG and is_instance_valid(vehicle) and is_instance_valid(target) \
			and target.global_position.distance_to(vehicle.global_position) > WildlifeCrossing.HORN_SCARE_DISTANCE:
		return
	end_event(&"scared", peer_id)


func _on_dog_thrown(peer_id: int) -> void:
	if _is_host() and kind == CargoAnimalPlan.DOG and phase != Phase.IDLE:
		end_event(&"distracted", peer_id)


func _on_house_delivery_recorded(_house: int, _outcome: StringName, _package_id: StringName) -> void:
	if _is_host():
		_next_leg()


func _on_run_started(_route: StringName, _players: Array) -> void:
	leg = 0
	events_this_run = 0
	_plan = {}
	_leg_moving = 0.0
	_fired = false
	_poll = 0.0
	_roll_run_seed()
	if phase != Phase.IDLE:
		end_event(&"left", 0, true)


func _on_run_ended(_score: int, _results: Dictionary) -> void:
	if phase != Phase.IDLE and _is_host():
		end_event(&"left", 0, true)


## A peer that arrives in the middle of an animal gets its alert again, with
## what is left of the warning (the view ignores it for a peer that has it).
func _on_peer_level_ready(_peer_id: int) -> void:
	if phase == Phase.IDLE or not _is_host():
		return
	var warn_left: float = _timer if phase == Phase.ANNOUNCED else 0.0
	var act_left: float = float(ACT_SECONDS[kind]) if phase == Phase.ANNOUNCED else _timer
	_relay(&"cargo_animal_alert", [kind, target_id, warn_left, act_left])


func _next_leg() -> void:
	leg += 1
	_leg_moving = 0.0
	_fired = false
	_plan = CargoAnimalPlan.for_leg(_run_seed(), leg)
	if endless and not _plan.is_empty() and StringName(_plan["kind"]) != CargoAnimalPlan.GULL:
		# No doors, no meadows: only the gull comes here.
		_plan = {}


# --- The world ---------------------------------------------------------------

func _speed() -> float:
	return (vehicle as RigidBody3D).linear_velocity.length() if vehicle is RigidBody3D else 0.0


func _rear_open() -> bool:
	return bool(vehicle.get(&"rear_cargo_open"))


func _in_countryside() -> bool:
	return zone_probe.is_valid() and bool(zone_probe.call(vehicle.global_position))


func _at_house_stop() -> bool:
	for house: Variant in houses:
		if not is_instance_valid(house):
			continue
		if vehicle.global_position.distance_to((house as Node3D).global_position) <= HOUSE_STOP_RADIUS:
			return true
	return false


## Dealt once per run. A room (world seed set) mixes in the runs finished, so
## every peer's host deals the same animals for the same world and run but not
## the same ones every run; alone (seed 0) it is a fresh roll each run.
func _roll_run_seed() -> void:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	var world_seed: int = int(network.get(&"world_seed")) if network != null else 0
	if world_seed != 0:
		var runs: int = int(network.get(&"world_completed_runs"))
		_seed = hash([world_seed, runs])
	else:
		var roll := RandomNumberGenerator.new()
		roll.randomize()
		_seed = roll.randi()
	_seeded = true


## The seed of the current run; rolled on first use if a leg is asked for
## before any run_started reached this node.
func _run_seed() -> int:
	if not _seeded:
		_roll_run_seed()
	return _seed


func _is_host() -> bool:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	return network == null or bool(network.call(&"is_host"))


func _run_active() -> bool:
	var run: Node = get_node_or_null(^"/root/RunManager")
	return run != null and bool(run.get(&"is_running"))


## Host: tell everyone (offline it just fires locally).
func _relay(event_name: StringName, args: Array) -> void:
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.call(&"relay", event_name, args)

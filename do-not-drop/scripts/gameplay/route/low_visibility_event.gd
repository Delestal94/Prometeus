extends Node
class_name LowVisibilityEvent
## A short spell in which the driver can't see the road (tareas de Nacho
## N-113, M-11 of the Backseat Drivers analysis): mud thrown over the
## windshield for 10-20 seconds, so somebody at a window has to guide them
## with the phrase wheel (N-505). Only ever a short event: the full "driver
## who can't see" premise is Backseat Drivers'.
##
## The host decides, from the session's world seed: every few seconds of the
## run (LowVisibilityPlan.SPACING) it draws once (LowVisibilityPlan.draw(), a
## pure function of seed and check number, so the same seed always rolls the
## same numbers; the numbers live in low_visibility_plan.gd), and the draw only counts if
## the moment is right (can_start()):
##   - not in the first LowVisibilityPlan.START_GRACE_SECONDS of the run, and only with a driver
##     at the wheel and the truck moving;
##   - at least LowVisibilityPlan.COOLDOWN_SECONDS since the last one ended, and one per
##     delivery (Endless has no houses, so only the cooldown limits it);
##   - the event's whole length ends before the last QUIET_ZONE metres before
##     the next house or the goal (RoutePlanner.QUIET_ZONE, at the current
##     speed): the crew is getting out there, nobody is throwing boxes, and the
##     driver must see. If the truck is in that zone anyway, the event ends.
##   - no route event with a countdown is open (inspection, mimic...).
##
## Everyone else just follows: EventBus.low_visibility_changed carries the
## start and the end (relayed), a peer arriving mid-event gets the rest of it
## (_receive_state), and each peer keeps its own clock (`elapsed`) for the
## fade in and out. What it looks like is windshield_rain.gd's mud overlay,
## shown only to whoever is driving; the HUD says it (hud_notices.gd).
##
## Cost: one comparison per physics tick while nothing happens, a dictionary
## of context twice a second during a run; the rest is the shader, only while it runs.

## The truck's and the route's scripts, as types (N-224.4; neither has a class
## name): driver_peer_id, houses, stop_road_distance and road_distance fail to
## compile here if renamed. level_common.gd preloads this file, never these back.
const VehicleScript = preload("res://scripts/gameplay/vehicle/vehicle.gd")
const RouteScript = preload("res://scripts/gameplay/route/route.gd")
## How often the host re-reads the truck and the road.
const CONTEXT_REFRESH_SECONDS: float = 0.5
## A peer that never hears the end lets go this long after it should have.
const STALE_SECONDS: float = 3.0

## The level whose route and truck this reads (LevelCommon sets it before
## adding the node). Null: the context is empty (the tests feed their own).
var level: Node
## Chance per draw; a var so tests can force or forbid it.
var chance: float = LowVisibilityPlan.CHANCE

## Every peer: {"kind", "duration"} while it lasts, empty otherwise.
var active: Dictionary = {}
## Every peer: seconds since it began.
var elapsed: float = 0.0
## Host-only bookkeeping.
var events_this_run: int = 0
var run_seconds: float = 0.0
var seconds_since_end: float = INF
var draws_made: int = 0
var _spacing_left: float = LowVisibilityPlan.SPACING
var _salt: int = 0
var _context_left: float = 0.0
var _context_cache: Dictionary = {}
## Metres along the road of each house and then the goal, measured once.
var _stops: Array[float] = []


func _ready() -> void:
	add_to_group(&"low_visibility")
	EventBus.low_visibility_changed.connect(_on_changed)
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)
	NetworkManager.peer_level_ready.connect(_on_peer_level_ready)
	reset_for_run()


func _exit_tree() -> void:
	# The level going away must not leave a HUD notice or an overlay behind.
	if not active.is_empty():
		_clear()


## Back to a run with nothing drawn yet. Solo play (seed 0) gets a different
## salt each time, like the route does; a shared seed rolls the same run.
func reset_for_run() -> void:
	if not active.is_empty():
		_clear()
	events_this_run = 0
	run_seconds = 0.0
	seconds_since_end = INF
	draws_made = 0
	_spacing_left = LowVisibilityPlan.SPACING
	_context_left = 0.0
	_context_cache = {}
	# The runs the room has finished move the salt, so the mud does not land at
	# the same second in every delivery of the same room (the host alone reads it).
	_salt = NetworkManager.world_completed_runs
	if NetworkManager.world_seed == 0:
		var fresh := RandomNumberGenerator.new()
		fresh.randomize()
		_salt = fresh.randi()


func is_active() -> bool:
	return not active.is_empty()


## Whether an event of `duration` seconds may start now, given the moment:
## {"running", "driver", "speed", "stop_gap", "route_event"} (see _context()).
func can_start(context: Dictionary, duration: float) -> bool:
	if not bool(context.get("running", false)) or not active.is_empty():
		return false
	if run_seconds < LowVisibilityPlan.START_GRACE_SECONDS or seconds_since_end < LowVisibilityPlan.COOLDOWN_SECONDS:
		return false
	if not bool(context.get("endless", false)) and events_this_run >= LowVisibilityPlan.MAX_PER_DELIVERY:
		return false
	var speed: float = float(context.get("speed", 0.0))
	if not bool(context.get("driver", false)) or speed < LowVisibilityPlan.MIN_SPEED:
		return false
	if bool(context.get("route_event", false)):
		return false
	# It must be over before the truck reaches the quiet zone before a stop.
	var gap: float = float(context.get("stop_gap", INF))
	return gap >= RoutePlanner.QUIET_ZONE + duration * speed


## One step of the event, every physics tick on every peer. `context` is
## _context()'s answer (the tests pass their own). The host draws, starts and
## ends; the others only keep the clock.
func tick(delta: float, context: Dictionary) -> void:
	if not active.is_empty():
		elapsed += delta
		if not NetworkManager.is_host():
			if elapsed > float(active.duration) + STALE_SECONDS:
				_clear()
			return
		var gap: float = float(context.get("stop_gap", INF))
		var over: bool = elapsed >= float(active.duration) or gap < RoutePlanner.QUIET_ZONE
		if over or not bool(context.get("running", false)):
			_finish()
		return
	if not NetworkManager.is_host() or not bool(context.get("running", false)):
		return
	run_seconds += delta
	seconds_since_end += delta
	_spacing_left -= delta
	if _spacing_left > 0.0:
		return
	_spacing_left += LowVisibilityPlan.SPACING
	draws_made += 1
	var result: Dictionary = LowVisibilityPlan.draw(NetworkManager.world_seed, _salt, draws_made, chance)
	if bool(result.hit) and can_start(context, float(result.duration)):
		events_this_run += 1
		EventBus.relay(&"low_visibility_changed", [true, result.kind, float(result.duration), 0.0])


func _physics_process(delta: float) -> void:
	if active.is_empty() and (not NetworkManager.is_host() or not RunManager.is_running):
		return
	if NetworkManager.is_host():
		# The road lookups aren't free: the moment is re-read a couple of times
		# a second, which is plenty for a draw every five.
		_context_left -= delta
		if _context_left <= 0.0:
			_context_left = CONTEXT_REFRESH_SECONDS
			_context_cache = _context()
	tick(delta, _context_cache)


## Host-only: ends it, and starts the cooldown.
func _finish() -> void:
	var kind: StringName = StringName(active.get("kind", LowVisibilityPlan.KIND_MUD))
	seconds_since_end = 0.0
	EventBus.relay(&"low_visibility_changed", [false, kind, 0.0, 0.0])


func _clear() -> void:
	var kind: StringName = StringName(active.get("kind", LowVisibilityPlan.KIND_MUD))
	active = {}
	elapsed = 0.0
	EventBus.low_visibility_changed.emit(false, kind, 0.0, 0.0)


func _on_changed(is_starting: bool, kind: StringName, duration: float, seconds_in: float) -> void:
	if is_starting:
		active = {"kind": kind, "duration": duration}
		elapsed = seconds_in
	else:
		active = {}
		elapsed = 0.0


func _on_run_started(_route_id: StringName, _players: Array) -> void:
	reset_for_run()


## The run's end clears it on every peer at once (the mud is not a thing to
## carry into the results screen).
func _on_run_ended(_score: int, _results: Dictionary) -> void:
	if not active.is_empty():
		_clear()


## Host-only: a peer that joins mid-event gets the rest of it. Deferred so it
## lands after the session state, whose run_started would wipe it; what is
## sent is read when the deferred call runs, not now (_send_state()).
func _on_peer_level_ready(peer_id: int) -> void:
	if not NetworkManager.is_host() or not NetworkManager.is_online() or peer_id == NetworkManager.HOST_ID:
		return
	if active.is_empty():
		return
	_send_state.call_deferred(peer_id)


## What is left of the event, as of now: nothing if it ended in between (the
## run's end clears it in the same frame) or if the peer left meanwhile.
func _send_state(peer_id: int) -> void:
	if active.is_empty() or not NetworkManager.is_online() or peer_id not in multiplayer.get_peers():
		return
	_receive_state.rpc_id(peer_id, active.kind, float(active.duration), elapsed)


@rpc("authority", "call_remote", "reliable")
func _receive_state(kind: StringName, duration: float, seconds_in: float) -> void:
	EventBus.low_visibility_changed.emit(true, kind, duration, seconds_in)


## The moment, from the level: is a run on, is someone driving and how fast,
## how many metres to the next house (or the goal), is a route event open.
func _context() -> Dictionary:
	var context: Dictionary = {"running": RunManager.is_running, "driver": false, "speed": 0.0,
			"stop_gap": INF, "route_event": not RouteEventManager.active_event_id.is_empty(),
			"endless": RunManager.current_mode == RunManager.MODE_ENDLESS}
	var common := level as LevelCommon
	var vehicle := common.vehicle as VehicleScript if common != null else null
	if vehicle == null:
		return context
	context.driver = vehicle.driver_peer_id != 0
	context.speed = vehicle.linear_velocity.length()
	# Only the delivery has stops (the houses, then the goal), and only its
	# route can say how far along the road each one is. Measured a few times a
	# second at most: the nearest-sample lookup is not free.
	# Only level_base.gd has a `route` (by name: preloading the levels here would
	# loop back through level_common.gd, which preloads this file).
	var route := level.get(&"route") as RouteScript
	if route != null:
		context.stop_gap = _gap_to_next_stop(route, vehicle)
	return context


func _gap_to_next_stop(route: RouteScript, vehicle: Node3D) -> float:
	if _stops.is_empty():
		# Every house, then the goal (an index past the last house): fixed once
		# the route is built.
		for index: int in range(route.houses.size() + 1):
			_stops.append(route.stop_road_distance(index))
	var here: float = route.road_distance(vehicle.global_position)
	var gap: float = INF
	for stop: float in _stops:
		var ahead: float = stop - here
		if ahead > -5.0:
			gap = minf(gap, ahead)
	return gap

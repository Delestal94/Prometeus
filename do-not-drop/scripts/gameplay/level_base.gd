extends "res://scripts/gameplay/level_common.gd"
## Composes the phase-1/2 sandbox. Physics, trap logic and HUD remain separate.
## The run starts on its own once a driver is seated with at least one package
## loaded -- no button needed for the real flow.
##
## Everything this level shares with Endless (the depot, spawning players,
## pause, restart, lost cargo...) lives in level_common.gd (N-209); what's
## here is the delivery's own: the route and its houses, and how a delivery
## ends -- at the goal, or tipped, off the road or stuck.

const STOP_SECONDS: float = 1.0
const DELIVERY_MAX_SPEED: float = 1.5
## Wedged: the pedal is down and the truck doesn't move (high-centred on an
## obstacle with its driven wheels hanging, N-803). Same rule as Endless;
## legitimate stops at the depot and houses never count.
const STUCK_SPEED: float = 0.3
const STUCK_SECONDS: float = 6.0
const HOUSE_STOP_RADIUS: float = 18.0
## route.gd and vehicle.gd have no class name: typed through their scripts
## so a rename fails to compile instead of at run time (N-224).
const RouteScript = preload("res://scripts/gameplay/route/route.gd")
const VehicleScript = preload("res://scripts/gameplay/vehicle/vehicle.gd")
@onready var route: RouteScript = $World/Route
## The HUD redraws its progress bar and hint at this rate, not every physics
## tick (N-223); the run's own logic below still runs every tick. Keep it under
## hud_prompts' 0.25 s hint flash or "hold still" flickers.
const HUD_SIGNAL_INTERVAL: float = 0.125
var stopped_seconds: float = 0.0
var stuck_seconds: float = 0.0
var _hud_signal_left: float = 0.0
## What delivery_status_changed last said, to send a change at once.
var _hud_in_zone: bool = false
var _hud_stopped: bool = false
## Orders that came in before the houses were built.
var _pending_assignments: Array = []


func _prepare_mode() -> void:
	# The dog waits at the doors, the bees in the meadows (N-109). The houses
	# list is filled as the route builds, so the same array serves.
	cargo_animals.houses = route.houses
	cargo_animals.zone_probe = _is_open_country
	# The doors are where the run is actually won: route.gd owns the houses,
	# RunManager owns the scoring, and this is the one place that knows both.
	# Without this the houses resolved into nothing and every delivery was
	# worth exactly as much as driving past (docs/colaboracion-equipo.md).
	route.house_resolved.connect(_on_house_resolved)
	RunManager.expected_houses = route.house_count
	EventBus.houses_assigned.connect(_on_houses_assigned)
	# Today's orders: one specific box per house, posted on the depot's
	# board and on each house's sign from the start (every peer draws the
	# same ones from the session seed).
	depot.post_orders(route.house_count)
	# The houses themselves stand once the route has built (it takes several
	# frames: route.gd, N-408); already built, as in a test, it's now.
	if route.is_built:
		_on_route_built()
	else:
		route.built.connect(_on_route_built, CONNECT_ONE_SHOT)


## What needs the houses to exist: their orders and what a refused box says.
func _on_route_built() -> void:
	for house: DeliveryHouse in route.houses:
		var index: int = house.house_index
		house.wrong_package_offered.connect(func(expected: String) -> void:
			EventBus.relay(&"house_refused_package", [index, expected]))
	route.assign_packages(_pending_assignments if not _pending_assignments.is_empty() else depot.assignments())
	_pending_assignments = []


## The orders arrive from the host (EventBus.houses_assigned); the houses may
## still be on their way up, and take them as soon as they are.
func _on_houses_assigned(assignments: Array) -> void:
	if route.is_built:
		route.assign_packages(assignments)
	else:
		_pending_assignments = assignments


## The level's world is complete once the route is (it builds over frames).
func _is_world_built() -> bool:
	return route.is_built


func _wait_for_world() -> void:
	if not route.is_built:
		await route.built


## The village at the end of the road, which the newspaper is named after.
func newspaper_town() -> String:
	var goal: RouteGoalLot = route.goal_lot
	return goal.town_name if goal != null else ""


## Whether the road is running through open country at this point: where the
## bees come for a cake (cargo_animals.gd).
func _is_open_country(world_position: Vector3) -> bool:
	var dresser: RouteDresser = route.dresser
	if dresser == null:
		return false
	var zone: int = dresser.zone_at(route.to_local(world_position), route.road_distance(world_position))
	return zone == RouteDresser.Zone.COUNTRYSIDE


func _on_peer_level_ready(peer_id: int) -> void:
	super(peer_id)
	if not NetworkManager.is_host():
		return
	# The houses were built with the level, for the crew there was then; a
	# restart builds them for everyone here now (NetworkManager.begin_restart()).
	# The host usually builds the level alone, the moment it opens the room:
	# one house, one order on the board. Asking the crew to restart by hand
	# left most sessions delivering a single box, so while nobody has set off
	# the depot rebuilds itself for the crew that's actually here -- after a
	# short wait, so friends joining together cost one reload, not several.
	if _crew_outgrew_route():
		EventBus.depot_notice.emit(tr("HUD_NOTICE_CREW_GREW") % _wanted_houses())
		if not _crew_restart_pending:
			_crew_restart_pending = true
			await get_tree().create_timer(CREW_RESTART_DELAY).timeout
			_crew_restart_pending = false
			if is_inside_tree() and _crew_outgrew_route():
				restart_delivery()


## Seconds the host waits after someone joins before rebuilding the route.
const CREW_RESTART_DELAY: float = 3.0
var _crew_restart_pending: bool = false


func _wanted_houses() -> int:
	return RouteScript.crew_house_count(NetworkManager.peer_ids.size())


## More passengers than houses, and the run not started yet.
func _crew_outgrew_route() -> bool:
	if not NetworkManager.is_host() or RunManager.is_running or not RunManager.results.is_empty():
		return false
	return _wanted_houses() > route.house_count


## Only the host resolves doors (Interactable.interact() is host-only), and
## RunManager relays the record to everyone from there.
func _on_house_resolved(house_index: int, outcome: StringName, package_id: StringName) -> void:
	var houses: Array[DeliveryHouse] = route.houses
	var opened: bool = house_index < houses.size() and houses[house_index].handed_over_open
	RunManager.register_delivery(house_index, outcome, package_id, opened)


func start_delivery() -> void:
	if RunManager.is_running or not RunManager.results.is_empty():
		return
	if not _driver_seated:
		return
	vehicle.freeze = false
	stuck_seconds = 0.0
	_hud_signal_left = 0.0
	var loaded: Array[DeliveryPackage] = _release_loaded_cargo()
	EventBus.relay(&"houses_assigned", [_house_assignments()])
	RunManager.start_run()
	RunManager.set_deadlines(RunManager.plan_deadlines(_house_distances()))
	depot.begin_run(vehicle, loaded)


## How far along the road each house sits, in metres, in house order.
func _house_distances() -> Array:
	var distances: Array = []
	for house: DeliveryHouse in route.houses:
		distances.append(route.get_progress(house.global_position) * route.route_length)
	return distances


## The depot's orders, relayed once more as the run starts so every client's
## houses agree with the host's even if they joined late. A box that isn't
## on the order rides to the goal as plain cargo.
func _house_assignments() -> Array:
	return depot.assignments()


func _physics_process(delta: float) -> void:
	if not RunManager.is_running:
		return
	var progress: float = route.get_progress(vehicle.global_position)
	# Furthest point reached, on every peer: a client left without a host
	# shows it on its disconnect screen (RunTally, N-222).
	RunManager.current_distance = maxf(RunManager.current_distance, progress * route.route_length)
	if route.is_vehicle_in_delivery and vehicle.linear_velocity.length() < DELIVERY_MAX_SPEED:
		stopped_seconds += delta
	else:
		stopped_seconds = 0.0
	_emit_hud_signals(delta, progress)
	# Clients follow the run for the HUD; how it ends is the host's call.
	if not NetworkManager.is_host():
		return
	# The run ends at the goal (stopped in its zone for STOP_SECONDS), not at
	# the last house: every house is one stop on the way, and the last leg to
	# the goal is part of the 2-5 minute delivery (route.gd's time budget).
	# Reaching the goal also settles any house nobody rang (route.gd).
	if stopped_seconds >= STOP_SECONDS:
		RunManager.finish_run(true)
		return
	_check_lost_cargo()
	_update_tipped(delta)
	if _should_count_as_stuck():
		stuck_seconds += delta
	else:
		stuck_seconds = 0.0
	# The reason travels as a key: every peer's results screen translates it.
	if tipped_seconds > 4.0:
		RunManager.finish_run(false, "HUD_RUN_TIPPED")
	elif vehicle.global_position.y < -8.0 or route.distance_from_path(vehicle.global_position) > 42.0:
		RunManager.finish_run(false, "HUD_RUN_OFF_ROAD")
	elif stuck_seconds >= STUCK_SECONDS:
		RunManager.finish_run(false, "HUD_RUN_STUCK")


## The HUD's route and delivery readouts, at HUD_SIGNAL_INTERVAL; the delivery
## status also goes out the moment it changes (in or out of the zone, holding
## still or not), which is what its hint reacts to.
func _emit_hud_signals(delta: float, progress: float) -> void:
	var in_zone: bool = route.is_vehicle_in_delivery
	var holding: bool = stopped_seconds > 0.0
	_hud_signal_left -= delta
	var due: bool = _hud_signal_left <= 0.0
	if due:
		_hud_signal_left += HUD_SIGNAL_INTERVAL
		# A long frame must not queue a burst of catch-up emissions.
		_hud_signal_left = maxf(_hud_signal_left, 0.0)
		EventBus.route_progress_changed.emit(progress, route.route_length * (1.0 - progress),
				route.get_section_name(vehicle.global_position))
	if due or in_zone != _hud_in_zone or holding != _hud_stopped:
		_hud_in_zone = in_zone
		_hud_stopped = holding
		EventBus.delivery_status_changed.emit(in_zone, stopped_seconds)


func _should_count_as_stuck() -> bool:
	# In the mud (MudSegment, N-108) a truck that can't move is not a soft
	# lock: the crew pushes it out or the crane comes.
	if bool(vehicle.get_meta(&"in_mud", false)):
		return false
	if vehicle.linear_velocity.length() >= STUCK_SPEED or absf(vehicle.engine_force) <= 0.0:
		return false
	if (vehicle as VehicleScript).driver_peer_id == 0:
		return false
	var depot_position: Vector3 = depot.to_local(vehicle.global_position)
	if absf(depot_position.x) <= Depot.HALF_WIDTH + 2.0 \
			and depot_position.z > Depot.TRUCK_CLEAR_Z \
			and depot_position.z < Depot.DEPTH + 2.0:
		return false
	for house: DeliveryHouse in route.houses:
		if is_instance_valid(house) and vehicle.global_position.distance_to(house.global_position) <= HOUSE_STOP_RADIUS:
			return false
	return true

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
@onready var route: Node3D = $World/Route
var stopped_seconds: float = 0.0
var stuck_seconds: float = 0.0


func _prepare_mode() -> void:
	# The doors are where the run is actually won: route.gd owns the houses,
	# RunManager owns the scoring, and this is the one place that knows both.
	# Without this the houses resolved into nothing and every delivery was
	# worth exactly as much as driving past (docs/colaboracion-equipo.md).
	if route.has_signal(&"house_resolved"):
		route.connect(&"house_resolved", _on_house_resolved)
		RunManager.expected_houses = (route.get(&"houses") as Array).size()
		EventBus.houses_assigned.connect(func(assignments: Array) -> void: route.call(&"assign_packages", assignments))
		for house: Node in route.get(&"houses"):
			var index: int = int(house.get(&"house_index"))
			house.connect(&"wrong_package_offered", func(expected: String) -> void:
				EventBus.relay(&"house_refused_package", [index, expected]))
		# Today's orders: one specific box per house, posted on the depot's
		# board and on each house's sign from the start (every peer draws the
		# same ones from the session seed).
		depot.post_orders((route.get(&"houses") as Array).size())
		route.call(&"assign_packages", depot.assignments())


func _on_peer_level_ready(peer_id: int) -> void:
	super(peer_id)
	if not NetworkManager.is_host():
		return
	# The houses were built with the level, for the crew there was then; a
	# restart builds them for everyone here now (NetworkManager.begin_restart()).
	var wanted: int = route.call(&"crew_house_count", NetworkManager.peer_ids.size())
	if not RunManager.is_running and RunManager.results.is_empty() and wanted > (route.get(&"houses") as Array).size():
		EventBus.depot_notice.emit("Llegó más gente: reiniciá (mantené R) para que la ruta tenga %d casas." % wanted)


## Only the host resolves doors (Interactable.interact() is host-only), and
## RunManager relays the record to everyone from there.
func _on_house_resolved(house_index: int, outcome: StringName, package_id: StringName) -> void:
	RunManager.register_delivery(house_index, outcome, package_id)


func start_delivery() -> void:
	if RunManager.is_running or not RunManager.results.is_empty():
		return
	if not _driver_seated or not _has_loaded_cargo():
		return
	vehicle.freeze = false
	stuck_seconds = 0.0
	var loaded: Array[DeliveryPackage] = _release_loaded_cargo()
	EventBus.relay(&"houses_assigned", [_house_assignments()])
	RunManager.start_run()
	depot.begin_run(vehicle, loaded)


## The depot's orders, relayed once more as the run starts so every client's
## houses agree with the host's even if they joined late. A box that isn't
## on the order rides to the goal as plain cargo.
func _house_assignments() -> Array:
	return depot.assignments()


func _physics_process(delta: float) -> void:
	if not RunManager.is_running:
		return
	var progress: float = route.get_progress(vehicle.global_position)
	EventBus.route_progress_changed.emit(progress, route.route_length * (1.0 - progress), route.get_section_name(vehicle.global_position))
	if route.is_vehicle_in_delivery and vehicle.linear_velocity.length() < DELIVERY_MAX_SPEED:
		stopped_seconds += delta
	else:
		stopped_seconds = 0.0
	EventBus.delivery_status_changed.emit(route.is_vehicle_in_delivery, stopped_seconds)
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
	if tipped_seconds > 4.0:
		RunManager.finish_run(false, "La camioneta volcó. Tomá las curvas más despacio.")
	elif vehicle.global_position.y < -8.0 or route.distance_from_path(vehicle.global_position) > 42.0:
		RunManager.finish_run(false, "Te saliste de la ruta. Reiniciá para intentarlo de nuevo.")
	elif stuck_seconds >= STUCK_SECONDS:
		RunManager.finish_run(false, "La camioneta quedó atascada. Reiniciá para intentarlo de nuevo.")


func _should_count_as_stuck() -> bool:
	if vehicle.linear_velocity.length() >= STUCK_SPEED or absf(vehicle.engine_force) <= 0.0:
		return false
	if int(vehicle.get(&"driver_peer_id")) == 0:
		return false
	var depot_position: Vector3 = depot.to_local(vehicle.global_position)
	if absf(depot_position.x) <= Depot.HALF_WIDTH + 2.0 \
			and depot_position.z > Depot.TRUCK_CLEAR_Z \
			and depot_position.z < Depot.DEPTH + 2.0:
		return false
	for house: Node in route.get(&"houses"):
		if is_instance_valid(house) and vehicle.global_position.distance_to((house as Node3D).global_position) <= HOUSE_STOP_RADIUS:
			return false
	return true

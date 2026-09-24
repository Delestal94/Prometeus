extends Node3D
## Composes the phase-1/2 sandbox. Physics, trap logic and HUD remain separate.
## The run starts on its own once a driver is seated with at least one package
## loaded -- no button needed for the real flow.

const STOP_SECONDS: float = 1.0
const DELIVERY_MAX_SPEED: float = 1.5
const LOST_CARGO_DISTANCE: float = 8.0
@onready var vehicle: VehicleBody3D = $World/Vehicle
@onready var route: Node3D = $World/Route
@onready var _driver_seat: Area3D = $World/Vehicle/CabinInterior/DriverEyePoint/InteractionArea
@onready var _world: Node3D = $World
## Where every delivery starts: the truck parked inside, the boxes on its
## shelves, the order board (depot.gd). Players spawn here too, handed out
## its spawn spots in order so nobody lands inside anybody else.
@onready var depot: Depot = $World/Depot
var local_player: Node = null
var packages: Array[DeliveryPackage] = []
var stopped_seconds: float = 0.0
var tipped_seconds: float = 0.0
var _driver_seated: bool = false


func _ready() -> void:
	RunManager.reset_run()
	add_child(preload("res://scripts/presentation/ingame_music.gd").new())
	vehicle.freeze = true
	packages.assign(depot.withhold_locked(get_tree().get_nodes_in_group(&"cargo")))
	for package: DeliveryPackage in packages:
		package.freeze = true
	depot.stock_shelves(packages)
	_driver_seat.interacted.connect(_on_driver_seated)
	for mount: Node in get_tree().get_nodes_in_group(&"package_mount"):
		mount.connect(&"interacted", _on_package_loaded)
	EventBus.start_requested.connect(start_debug_delivery)
	EventBus.restart_requested.connect(restart_delivery)
	EventBus.pause_requested.connect(toggle_pause)
	EventBus.run_ended.connect(_on_run_ended)
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
	# The host brings its own truck and paint; replication hands them to
	# every client (vehicle.gd variant_id/paint_id).
	if NetworkManager.is_host():
		vehicle.variant_id = UnlockManager.selected_truck
		vehicle.paint_id = UnlockManager.selected_paint
	NetworkManager.roster_changed.connect(_on_roster_changed)
	# Choices made in the depot (lockers, workshop) show at once.
	UnlockManager.progress_changed.connect(_on_profile_changed)
	# Offline is a session of one, so this same call covers both paths.
	if NetworkManager.is_host():
		_sync_players(NetworkManager.peer_ids)
	# Command line shortcut for smoke checks and development: skips the
	# on-foot loading entirely, same as the HUD's debug button.
	if "--autostart" in OS.get_cmdline_user_args():
		start_debug_delivery.call_deferred()


func _on_roster_changed(peer_ids: Array) -> void:
	if NetworkManager.is_host():
		_sync_players(peer_ids)


func _sync_players(peer_ids: Array) -> void:
	# Only the host spawns: MultiplayerSpawner replicates the result to
	# everyone, so clients never invent players of their own.
	for index: int in range(peer_ids.size()):
		var id: int = int(peer_ids[index])
		if _world.has_node(NodePath(_player_name(id))):
			continue
		var player: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
		player.name = _player_name(id)
		player.set(&"position", _world.to_local(depot.spawn_position(index)))
		player.set_multiplayer_authority(id)
		_world.add_child(player, true)
	for child: Node in _world.get_children():
		if child.name.begins_with("Player_") and not peer_ids.has(_id_from_name(child.name)):
			child.queue_free()
	_refresh_local_player()


## The workshop and the lockers write the profile; the truck is the host's
## (replicated from vehicle.gd), the uniform is each player's own (replicated
## from player.gd). Nothing changes once the truck has left.
func _on_profile_changed() -> void:
	if RunManager.is_running or not RunManager.results.is_empty():
		return
	if NetworkManager.is_host():
		vehicle.variant_id = UnlockManager.selected_truck
		vehicle.paint_id = UnlockManager.selected_paint
	if is_instance_valid(local_player):
		local_player.set(&"cosmetic_id", UnlockManager.selected_cosmetic)


func _refresh_local_player() -> void:
	local_player = _world.get_node_or_null(NodePath(_player_name(NetworkManager.local_id())))


func _player_name(id: int) -> String:
	return "Player_%d" % id


func _id_from_name(value: String) -> int:
	return int(value.trim_prefix("Player_"))


func start_debug_delivery() -> void:
	if RunManager.is_running or not RunManager.results.is_empty():
		return
	var player: Node = local_player
	if player == null:
		return
	if not _has_loaded_cargo() and not packages.is_empty():
		# The debug route needs a deterministic, protected cargo position.
		# Shelf slots remain available in normal play, where loose cargo may
		# genuinely fall after rough driving.
		var mount: Node = vehicle.get_node_or_null(^"CargoBay/LeftSeat1PackageMount/InteractionArea")
		player.call(&"pick_up", packages[0].get_path())
		if mount != null:
			mount.call(&"interact", player)
	if not _driver_seated:
		# The driver's seat is only reachable through its open door.
		vehicle.call(&"set_door_open", &"cab_left", true)
		_driver_seat.interact(player)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Only the host resolves doors (Interactable.interact() is host-only), and
## RunManager relays the record to everyone from there.
func _on_house_resolved(house_index: int, outcome: StringName, package_id: StringName) -> void:
	RunManager.register_delivery(house_index, outcome, package_id)


func _on_driver_seated(_player: Node) -> void:
	_driver_seated = true
	_maybe_start()


func _on_package_loaded(_player: Node) -> void:
	_maybe_start()


func _maybe_start() -> void:
	if _driver_seated and _has_loaded_cargo():
		start_delivery()


## Read from the boxes themselves rather than counting mount events: a box
## can be loaded and taken back out again before anyone takes the wheel.
func _has_loaded_cargo() -> bool:
	for package: DeliveryPackage in packages:
		if is_instance_valid(package) and package.is_loaded:
			return true
	return false


func start_delivery() -> void:
	if RunManager.is_running or not RunManager.results.is_empty():
		return
	if not _driver_seated or not _has_loaded_cargo():
		return
	vehicle.freeze = false
	var loaded: Array[DeliveryPackage] = []
	for package: DeliveryPackage in packages:
		if is_instance_valid(package) and package.is_loaded:
			package.freeze = false
			# Only what's aboard counts: a box left on the rack was never
			# part of this delivery, so it shouldn't drag the score down.
			package.report_to_run()
			loaded.append(package)
	EventBus.relay(&"houses_assigned", [_house_assignments()])
	RunManager.start_run()
	depot.begin_run(vehicle, loaded)


## The depot's orders, relayed once more as the run starts so every client's
## houses agree with the host's even if they joined late. A box that isn't
## on the order rides to the goal as plain cargo.
func _house_assignments() -> Array:
	return depot.assignments()


func restart_delivery() -> void:
	get_tree().paused = false
	# Fade out before reloading instead of the instant hard cut a bare
	# reload_current_scene() would be -- only waits out the fade-to-black
	# half (see prototype_hud.gd's _on_quick_fade_requested), since the
	# fade-back-in half is moot once the whole tree gets torn down anyway.
	EventBus.emit_signal(&"quick_fade_requested", 0.3)
	await get_tree().create_timer(0.15).timeout
	RunManager.reset_run()
	get_tree().reload_current_scene()


func toggle_pause() -> void:
	if RunManager.results.is_empty():
		get_tree().paused = not get_tree().paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED


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
	if stopped_seconds >= STOP_SECONDS:
		RunManager.finish_run(true)
		return
	_check_lost_cargo()
	if vehicle.global_basis.y.dot(Vector3.UP) < 0.25:
		tipped_seconds += delta
	else:
		tipped_seconds = 0.0
	if tipped_seconds > 4.0:
		RunManager.finish_run(false, "La camioneta volcó. Tomá las curvas más despacio.")
	elif vehicle.global_position.y < -8.0 or route.distance_from_path(vehicle.global_position) > 42.0:
		RunManager.finish_run(false, "Te saliste de la ruta. Reiniciá para intentarlo de nuevo.")


func _check_lost_cargo() -> void:
	# A box that falls out is written off on its own. Only losing every last
	# one ends the delivery, and RunManager decides that.
	for package: DeliveryPackage in packages:
		# A box handed over at a door is freed on the spot -- this list
		# outlives it, so skip what's already gone instead of reading a
		# freed node's properties.
		if not is_instance_valid(package):
			continue
		if not package.is_loaded:
			continue
		var distance: float = package.global_position.distance_to(vehicle.global_position)
		if distance > LOST_CARGO_DISTANCE:
			package.mark_lost("Se cayó de la furgoneta.")


func _on_run_ended(_score: int, _results: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Defer rigid-body changes: failure can originate in physics integration.
	vehicle.set_deferred("freeze", true)
	for package: DeliveryPackage in packages:
		if is_instance_valid(package):
			package.set_deferred("freeze", true)

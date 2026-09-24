extends Node3D
## Modo Endless (docs/plan-desarrollo.md Fase 3.5, docs/tareas-nacho.md
## #41-55): same on-foot loading / driver-seat / cargo-loading flow as
## level_base.gd, but RouteStreamer generates road indefinitely instead of
## a fixed curated route.tscn with a delivery zone. Deliberately NOT
## refactored to share a base class with level_base.gd yet -- the two only
## diverge in _physics_process (no delivery zone, no "arrived" success
## state) and start_delivery (has to kick off the streamer); duplicating
## that little is safer than restructuring a file Slatex also depends on
## mid-project. Revisit once both modes are stable.
##
## Ending a run here always calls RunManager.finish_run(false, ...) (cargo
## lost, tipped over, or fell off) -- there's no "arrived" state to award
## the delivery-mode score formula. RunManager scores endless runs by
## distance instead (docs/tareas-nacho.md #52): start_run(MODE_ENDLESS)
## below switches it into that mode, and RunManager.current_distance is
## kept in sync with distance_traveled every physics frame so finish_run()
## has it however the run ends -- including the "all cargo ruined" path,
## which fires from inside RunManager itself, not from this file.

const LOST_CARGO_DISTANCE: float = 8.0
const OUT_OF_BOUNDS_X: float = 42.0
## #97's automated bug bash found a real gap: driving unbraked into repeated
## SpeedBumpSegments at sustained top speed can launch the van hard enough
## that it lands wedged against route geometry -- upright (never trips the
## tip-over check) and inside bounds (never trips the out-of-bounds check),
## just permanently stopped with no way out and the run silently still
## "running" forever. 6s of being effectively stationary is long enough that
## no real player deliberately idles that long mid-drive (there's no reason
## to stop in endless mode at all -- unlike level_base.gd's delivery zone,
## there's no destination to sit still at).
const STUCK_SPEED_THRESHOLD: float = 0.3
const STUCK_SECONDS: float = 6.0
var _stuck_seconds: float = 0.0
@onready var vehicle: VehicleBody3D = $World/Vehicle
@onready var _streamer: RouteStreamer = $World/RouteStreamer
@onready var _driver_seat: Area3D = $World/Vehicle/CabinInterior/DriverEyePoint/InteractionArea
@onready var _world: Node3D = $World
## The same depot as level_base.gd: the run starts there, the truck parked
## inside, players spawning by it (depot.gd). No houses here, so its board
## just says to load anything and go.
@onready var depot: Depot = $World/Depot
var local_player: Node = null
var packages: Array[DeliveryPackage] = []
var tipped_seconds: float = 0.0
var _driver_seated: bool = false
var _streaming_started: bool = false
var _last_vehicle_z: float = 0.0
## Public, meters -- how far the van has actually driven this run. Reset in
## _ready(), only advances while RunManager.is_running.
var distance_traveled: float = 0.0


func _ready() -> void:
	RunManager.reset_run()
	add_child(preload("res://scripts/presentation/ingame_music.gd").new())
	vehicle.freeze = true
	packages.assign(depot.withhold_locked(get_tree().get_nodes_in_group(&"cargo")))
	for package: DeliveryPackage in packages:
		package.freeze = true
	depot.stock_shelves(packages)
	depot.post_orders(0)
	# The road is already out there when you look through the door.
	_streamer.start(vehicle)
	_driver_seat.interacted.connect(_on_driver_seated)
	for mount: Node in get_tree().get_nodes_in_group(&"package_mount"):
		mount.connect(&"interacted", _on_package_loaded)
	EventBus.start_requested.connect(start_debug_delivery)
	EventBus.restart_requested.connect(restart_delivery)
	EventBus.pause_requested.connect(toggle_pause)
	EventBus.run_ended.connect(_on_run_ended)
	# The host brings its own truck and paint; replication hands them to
	# every client (vehicle.gd variant_id/paint_id).
	if NetworkManager.is_host():
		vehicle.variant_id = UnlockManager.selected_truck
		vehicle.paint_id = UnlockManager.selected_paint
	NetworkManager.roster_changed.connect(_on_roster_changed)
	UnlockManager.progress_changed.connect(_on_profile_changed)
	if NetworkManager.is_host():
		_sync_players(NetworkManager.peer_ids)
	if "--autostart" in OS.get_cmdline_user_args():
		start_debug_delivery.call_deferred()


func _on_roster_changed(peer_ids: Array) -> void:
	if NetworkManager.is_host():
		_sync_players(peer_ids)


func _sync_players(peer_ids: Array) -> void:
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


## Same as level_base.gd: the workshop and lockers show at once.
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
		var mount: Node = vehicle.get_node_or_null(^"CargoBay/LeftSeat1PackageMount/InteractionArea")
		player.call(&"pick_up", packages[0].get_path())
		mount.call(&"interact", player)
	if not _driver_seated:
		# The driver's seat is only reachable through its open door.
		vehicle.call(&"set_door_open", &"cab_left", true)
		_driver_seat.interact(player)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_driver_seated(_player: Node) -> void:
	_driver_seated = true
	_maybe_start()


func _on_package_loaded(_player: Node) -> void:
	_maybe_start()


func _maybe_start() -> void:
	if _driver_seated and _has_loaded_cargo():
		start_delivery()


## Same as level_base.gd: read from the boxes, not from counted mount events.
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
			package.report_to_run()
			loaded.append(package)
	RunManager.start_run(RunManager.MODE_ENDLESS)
	depot.begin_run(vehicle, loaded)
	_last_vehicle_z = vehicle.global_position.z
	distance_traveled = 0.0
	_stuck_seconds = 0.0
	_streamer.start(vehicle)
	_streaming_started = true


func restart_delivery() -> void:
	get_tree().paused = false
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
	# Route moves toward -Z, same convention as route.gd's get_progress().
	# Counted from the start line (z = 0): the way out of the depot is free.
	var current_z: float = minf(vehicle.global_position.z, 0.0)
	distance_traveled += maxf(minf(_last_vehicle_z, 0.0) - current_z, 0.0)
	_last_vehicle_z = current_z
	RunManager.current_distance = distance_traveled
	# Clients follow the run for the HUD; how it ends is the host's call.
	if not NetworkManager.is_host():
		return
	_check_lost_cargo()
	if vehicle.global_basis.y.dot(Vector3.UP) < 0.25:
		tipped_seconds += delta
	else:
		tipped_seconds = 0.0
	if vehicle.linear_velocity.length() < STUCK_SPEED_THRESHOLD:
		_stuck_seconds += delta
	else:
		_stuck_seconds = 0.0
	if tipped_seconds > 4.0:
		RunManager.finish_run(false, "La camioneta volcó. Tomá las curvas más despacio.")
	elif vehicle.global_position.y < -8.0 or absf(vehicle.global_position.x) > OUT_OF_BOUNDS_X:
		RunManager.finish_run(false, "Te saliste de la ruta. Reiniciá para intentarlo de nuevo.")
	elif _stuck_seconds > STUCK_SECONDS:
		RunManager.finish_run(false, "La camioneta quedó atascada contra la ruta. Reiniciá para intentarlo de nuevo.")


func _check_lost_cargo() -> void:
	for package: DeliveryPackage in packages:
		if not is_instance_valid(package):
			continue
		if not package.is_loaded:
			continue
		var distance: float = package.global_position.distance_to(vehicle.global_position)
		if distance > LOST_CARGO_DISTANCE:
			package.mark_lost("Se cayó de la furgoneta.")


func _on_run_ended(_score: int, _results: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	vehicle.set_deferred("freeze", true)
	for package: DeliveryPackage in packages:
		# A box handed over at a door is freed on the spot (delivery_house.gd)
		# -- this list outlives it, so skip what's already gone instead of
		# deferring a call onto a freed node.
		if is_instance_valid(package):
			package.set_deferred("freeze", true)

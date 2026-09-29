extends Node3D
class_name LevelCommon
## What the delivery level (level_base.gd) and Endless (level_endless.gd) do
## exactly alike (tareas de Nacho N-209): the depot and its loading, players
## spawned by the host as they join, the run starting once a driver sits with
## cargo aboard, pause, restart for everyone, lost cargo, the view kept when
## the host goes. Each level adds only its own: the road it builds
## (_prepare_mode()), its peers' extras (_on_peer_level_ready()), starting its
## run (start_delivery()) and how a run ends (_physics_process()).
##
## Both scenes lay out the same nodes ($World, $World/Vehicle, $World/Depot,
## $World/PlayerSpawner), which is what makes this possible.

const LOST_CARGO_DISTANCE: float = 8.0
## A box that leaves the van isn't written off on the spot (N-213.1): it lies
## on the road with a marker for this long, so someone can go fetch it and put
## it back on a shelf. Longer than the 8-15 s rescue inside the van, since it
## takes stopping, getting out and walking back. A var so tests can shorten it.
var overboard_rescue_seconds: float = 30.0
## Host-only: package_id -> seconds it has been out of the van so far.
var _overboard_seconds: Dictionary = {}
const OVERBOARD_MARKER: Script = preload("res://scripts/presentation/overboard_marker.gd")
const VEHICLE_FAULTS: Script = preload("res://scripts/gameplay/vehicle/vehicle_faults.gd")
const RESCUE_HOOK: Script = preload("res://scripts/gameplay/vehicle/rescue_hook.gd")
const TRAILER_CAMERA: String = "res://scripts/tools/trailer_camera.gd"
@onready var vehicle: VehicleBody3D = $World/Vehicle
@onready var _driver_seat: Area3D = $World/Vehicle/CabinInterior/DriverEyePoint/InteractionArea
@onready var _world: Node3D = $World
## Where every run starts: the truck parked inside, the boxes on its shelves,
## the order board (depot.gd). Players spawn here too, handed out its spawn
## spots in order so nobody lands inside anybody else.
@onready var depot: Depot = $World/Depot
var local_player: Node = null
var packages: Array[DeliveryPackage] = []
var tipped_seconds: float = 0.0
var _driver_seated: bool = false


func _ready() -> void:
	RunManager.reset_run()
	add_child(preload("res://scripts/presentation/ingame_music.gd").new())
	var play_area: Node = preload("res://scripts/gameplay/play_area.gd").new()
	play_area.name = "PlayArea"
	play_area.set(&"level", self)
	add_child(play_area)
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
	_prepare_mode()
	# The host brings its own truck and paint; replication hands them to
	# every client (vehicle.gd variant_id/paint_id).
	if NetworkManager.is_host():
		vehicle.variant_id = UnlockManager.selected_truck
		vehicle.paint_id = UnlockManager.selected_paint
	$World/PlayerSpawner.spawned.connect(func(_player: Node) -> void: _refresh_local_player())
	NetworkManager.roster_changed.connect(_on_roster_changed)
	NetworkManager.peer_level_ready.connect(_on_peer_level_ready)
	NetworkManager.session_failed.connect(_keep_view)
	# Choices made in the depot (lockers, workshop) show at once.
	UnlockManager.progress_changed.connect(_on_profile_changed)
	# Offline is a session of one, so this same call covers both paths.
	if NetworkManager.is_host():
		_sync_players(NetworkManager.peer_ids)
	# Command line shortcut for smoke checks and development: skips the
	# on-foot loading entirely, same as the HUD's debug button.
	NetworkManager.level_ready.call_deferred()
	# Every peer draws the flag over a box on the road; the host decides (N-213.1).
	var overboard_marker: Node3D = OVERBOARD_MARKER.new()
	overboard_marker.name = "OverboardMarker"
	add_child(overboard_marker)
	# Truck faults (N-214): every peer tracks them, the host rolls them.
	var faults: Node = VEHICLE_FAULTS.new()
	faults.name = "VehicleFaults"
	add_child(faults)
	# The rescue hook (N-213.3) hangs by the rear doors on every peer, stowed
	# until a run takes it from the depot's supplies.
	var hook: Node3D = RESCUE_HOOK.new()
	hook.name = "RescueHook"
	vehicle.add_child(hook)
	if "--autostart" in OS.get_cmdline_user_args():
		start_debug_delivery.call_deferred()
	# The trailer's camera (N-902): F7 free camera, F5/F6/F8 rails. Debug
	# builds only; the tools aren't even exported.
	if OS.is_debug_build() and ResourceLoader.exists(TRAILER_CAMERA):
		var trailer: Camera3D = load(TRAILER_CAMERA).new()
		trailer.name = "TrailerCamera"
		trailer.set(&"target", vehicle)
		add_child(trailer)


## The level's own road and orders, set up once the depot is stocked.
func _prepare_mode() -> void:
	pass


## The level's own start: unfreeze, report the cargo, start the run.
func start_delivery() -> void:
	pass


func _on_roster_changed(peer_ids: Array) -> void:
	if NetworkManager.is_host():
		_sync_players(peer_ids)


## The host is gone. Godot frees everything the host's spawner made -- every
## player, this one's own camera with them -- so the view jumped to some seat
## camera behind the disconnect overlay. A still camera holds the last view.
func _keep_view(_reason: String) -> void:
	var eyes: Camera3D = get_viewport().get_camera_3d()
	if eyes == null or eyes.owner == self:
		return
	var still := Camera3D.new()
	still.name = "DisconnectedView"
	still.fov = eyes.fov
	still.near = eyes.near
	still.far = eyes.far
	still.cull_mask = eyes.cull_mask
	still.environment = eyes.environment
	still.attributes = eyes.attributes
	add_child(still)
	still.owner = self
	still.global_transform = eyes.get_global_transform_interpolated()
	still.current = true


## Host: a peer's level is up (it just joined, or reloaded after a restart).
## Its player can be spawned now, everyone's shown to it, and it's told how
## the run stands -- it may have arrived in the middle of one.
func _on_peer_level_ready(peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	_sync_players(NetworkManager.peer_ids)
	RunManager.send_session_state(peer_id)


func _sync_players(peer_ids: Array) -> void:
	# Only the host spawns: MultiplayerSpawner replicates the result to
	# everyone, so clients never invent players of their own.
	for index: int in range(peer_ids.size()):
		var id: int = int(peer_ids[index])
		if _world.has_node(NodePath(_player_name(id))):
			continue
		# Only into a level that's there: after a host restart each client
		# reloads at its own pace (NetworkManager.is_peer_ready()).
		if not NetworkManager.is_peer_ready(id):
			continue
		$World/PlayerSpawner.spawn({"peer_id": id,
			"position": _world.to_local(depot.spawn_position(index))})
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


func _on_driver_seated(_player: Node) -> void:
	_driver_seated = true
	_maybe_start()


func _on_package_loaded(_player: Node) -> void:
	_maybe_start()


## The driver taking the wheel is the start, cargo or not: forgetting the
## boxes is the crew's problem, paid for at the doors.
func _maybe_start() -> void:
	if _driver_seated:
		start_delivery()


## Read from the boxes themselves rather than counting mount events: a box
## can be loaded and taken back out again before anyone takes the wheel.
## A box on a seated passenger's lap is aboard too (DeliveryPackage.is_aboard).
func _has_loaded_cargo() -> bool:
	for package: DeliveryPackage in packages:
		if is_instance_valid(package) and package.is_aboard():
			return true
	return false


## Unfreezes the boxes aboard and has them count for the run; returns them.
## Only what's aboard counts: a box left on the rack was never part of this
## run, so it shouldn't drag the score down. A lap box stays frozen: it is
## held, and follows its passenger until they shelve it.
func _release_loaded_cargo() -> Array[DeliveryPackage]:
	var loaded: Array[DeliveryPackage] = []
	for package: DeliveryPackage in packages:
		if is_instance_valid(package) and package.is_aboard():
			if package.is_loaded:
				package.freeze = false
			package.report_to_run()
			loaded.append(package)
	return loaded


func restart_delivery() -> void:
	# The host restarts for everyone (NetworkManager.begin_restart()); a
	# client reloading on its own would leave the session's world behind.
	if not NetworkManager.is_host():
		return
	get_tree().paused = false
	# Fade out before reloading instead of the instant hard cut a bare
	# reload_current_scene() would be -- only waits out the fade-to-black
	# half (see HudNotices._on_quick_fade_requested), since the
	# fade-back-in half is moot once the whole tree gets torn down anyway.
	EventBus.emit_signal(&"quick_fade_requested", 0.3)
	await get_tree().create_timer(0.15).timeout
	RunManager.reset_run()
	# Online, every client reloads too, once this level is back up.
	NetworkManager.begin_restart()
	get_tree().reload_current_scene()


func toggle_pause() -> void:
	if RunManager.results.is_empty():
		get_tree().paused = not get_tree().paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED


## Tipped over (upside down or on its side) for this long ends the run; each
## level decides with what message and in which order of checks.
func _update_tipped(delta: float) -> void:
	if vehicle.global_basis.y.dot(Vector3.UP) < 0.25:
		tipped_seconds += delta
	else:
		tipped_seconds = 0.0


func _check_lost_cargo() -> void:
	# A box that falls out gets a rescue window (N-213.1) and is written off
	# on its own once it runs out. Only losing every last one ends the run,
	# and RunManager decides that.
	for package: DeliveryPackage in packages:
		# A box handed over at a door is freed on the spot -- this list
		# outlives it, so skip what's already gone instead of reading a
		# freed node's properties.
		if not is_instance_valid(package):
			continue
		var id: StringName = package.package_id
		# Picked up (or never aboard) is no longer a box lying on the road:
		# carrying it back is the rescue itself.
		var out: bool = (package.is_loaded and package.trap_state != ITrapBehavior.TrapState.RUINED
				and package.global_position.distance_to(vehicle.global_position) > LOST_CARGO_DISTANCE)
		if not out:
			if _overboard_seconds.has(id):
				_overboard_seconds.erase(id)
				EventBus.relay(&"cargo_overboard_ended", [id, package.trap_state != ITrapBehavior.TrapState.RUINED])
			continue
		if not _overboard_seconds.has(id):
			_overboard_seconds[id] = 0.0
			EventBus.relay(&"cargo_overboard", [id, package.global_position, overboard_rescue_seconds])
		_overboard_seconds[id] = float(_overboard_seconds[id]) + get_physics_process_delta_time()
		if float(_overboard_seconds[id]) >= overboard_rescue_seconds:
			_overboard_seconds.erase(id)
			# The order closes empty first (N-213.4), so RunManager no longer
			# counts the box as cargo and writing it off can't end the run.
			var route_node: Node = get_node_or_null(^"World/Route")
			if route_node != null and route_node.has_method(&"close_lost_order"):
				route_node.call(&"close_lost_order", id)
			package.mark_lost("Se cayó del camión.")
			EventBus.relay(&"cargo_overboard_ended", [id, false])


func _on_run_ended(_score: int, _results: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Defer rigid-body changes: failure can originate in physics integration.
	vehicle.set_deferred("freeze", true)
	for package: DeliveryPackage in packages:
		if is_instance_valid(package):
			package.set_deferred("freeze", true)

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
## Wedged: the pedal is down and the truck doesn't move (high-centred on an
## obstacle with its driven wheels hanging, N-803). One rule for both modes
## (N-920): stopping with nobody on the pedal -- the depot, rescuing a fallen
## box, a repair, a driver swap -- never counts, as in the delivery.
const STUCK_SPEED: float = 0.3
const STUCK_SECONDS: float = 6.0
## route.gd and vehicle.gd have no class name: typed through their scripts
## so a rename fails to compile instead of at run time (N-224).
const VehicleScript = preload("res://scripts/gameplay/vehicle/vehicle.gd")
## Seconds the truck has been wedged (see _should_count_as_stuck()).
var stuck_seconds: float = 0.0
## A box that leaves the van isn't written off on the spot (N-213.1): it lies
## on the road with a marker for this long, so someone can go fetch it and put
## it back on a shelf. Longer than the 8-15 s rescue inside the van, since it
## takes stopping, getting out and walking back. A var so tests can shorten it.
var overboard_rescue_seconds: float = 30.0
## Host-only: package_id -> seconds it has been out of the van so far.
var _overboard_seconds: Dictionary = {}
const OVERBOARD_MARKER: Script = preload("res://scripts/presentation/overboard_marker.gd")
const VEHICLE_FAULTS: Script = preload("res://scripts/gameplay/vehicle/vehicle_faults.gd")
const TRUCK_RADIO: Script = preload("res://scripts/gameplay/vehicle/truck_radio.gd")
const RUN_CHRONICLE: Script = preload("res://scripts/presentation/newspaper/run_chronicle.gd")
const NEWS_PHOTOGRAPHER: Script = preload("res://scripts/presentation/newspaper/news_photographer.gd")
const RESCUE_HOOK: Script = preload("res://scripts/gameplay/vehicle/rescue_hook.gd")
const LOW_VISIBILITY: Script = preload("res://scripts/gameplay/route/low_visibility_event.gd")
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
## The gull, the dog and the bees that go for the cargo (N-109): the host
## decides, every peer draws them.
var cargo_animals: CargoAnimals
var tipped_seconds: float = 0.0
var _driver_seated: bool = false
var _depot_stocked: bool = false
var _after_depot_steps: Array[Callable] = []
## Where someone who joins with the truck already on the road goes (N-228.7).
var _late_join: LateJoinSeating
## What someone who dropped out had, for when they come back (N-221).
var _rejoin: RejoinKeepsake
## A returner's spawn waits for its old player to be gone (_sync_players_soon()).
var _resync_queued: bool = false


func _ready() -> void:
	RunManager.reset_run()
	add_child(preload("res://scripts/presentation/ingame_music.gd").new())
	var play_area: Node = preload("res://scripts/gameplay/play_area.gd").new()
	play_area.name = "PlayArea"
	play_area.set(&"level", self)
	add_child(play_area)
	vehicle.freeze = true
	# The depot may still be building (over frames, behind the loading cover:
	# depot.gd, N-408): its floor isn't there yet, so the boxes the level brought
	# wait frozen, and are shelved once it stands. Already built, as in a test, it's now.
	if depot.is_built:
		_stock_depot()
	else:
		for package: Node in get_tree().get_nodes_in_group(&"cargo"):
			package.set(&"freeze", true)
		depot.built.connect(_stock_depot, CONNECT_ONE_SHOT)
	_driver_seat.interacted.connect(_on_driver_seated)
	for mount: Node in get_tree().get_nodes_in_group(&"package_mount"):
		mount.connect(&"interacted", _on_package_loaded)
	EventBus.start_requested.connect(start_debug_delivery)
	EventBus.restart_requested.connect(restart_delivery)
	EventBus.pause_requested.connect(toggle_pause)
	EventBus.run_ended.connect(_on_run_ended)
	# Animals that go for the boxes (N-109): the host rolls them from the session
	# seed, every peer draws them. Before _prepare_mode(), which tells it about
	# the level's houses and meadows.
	cargo_animals = CargoAnimals.new()
	cargo_animals.name = "CargoAnimals"
	cargo_animals.vehicle = vehicle
	cargo_animals.packages = packages
	add_child(cargo_animals)
	_prepare_mode()
	# The host brings its own truck and paint; replication hands them to
	# every client (vehicle.gd variant_id/paint_id).
	if NetworkManager.is_host():
		vehicle.variant_id = UnlockManager.selected_truck
		vehicle.paint_id = UnlockManager.selected_paint
	_late_join = LateJoinSeating.new()
	_late_join.name = "LateJoinSeating"
	_late_join.vehicle = vehicle
	add_child(_late_join)
	_rejoin = RejoinKeepsake.new()
	_rejoin.name = "RejoinKeepsake"
	_rejoin.vehicle = vehicle
	_rejoin.late_join = _late_join
	add_child(_rejoin)
	# Before the roster drops them, while their player still stands (N-221).
	NetworkManager.peer_removed.connect(_on_peer_removed)
	NetworkManager.peer_returned.connect(_rejoin.on_returned)
	$World/PlayerSpawner.spawned.connect(func(_player: Node) -> void: _refresh_local_player())
	NetworkManager.roster_changed.connect(_on_roster_changed)
	NetworkManager.peer_level_ready.connect(_on_peer_level_ready)
	NetworkManager.session_failed.connect(_keep_view)
	NetworkManager.session_failed.connect(_stop_orphaned_run)
	# Choices made in the depot (lockers, workshop) show at once.
	UnlockManager.progress_changed.connect(_on_profile_changed)
	# Offline is a session of one, so this same call covers both paths. A world
	# that is still building (route.gd, N-408) gets its players once it stands:
	# _report_level_ready() below.
	if NetworkManager.is_host():
		_sync_players(NetworkManager.peer_ids)
	# Command line shortcut for smoke checks and development: skips the
	# on-foot loading entirely, same as the HUD's debug button.
	# Reported once the world stands (N-408): a client's "ready" is what makes the
	# host spawn it, and the road it spawns onto builds itself over several frames.
	_report_level_ready.call_deferred()
	# Every peer draws the flag over a box on the road; the host decides (N-213.1).
	var overboard_marker: Node3D = OVERBOARD_MARKER.new()
	overboard_marker.name = "OverboardMarker"
	add_child(overboard_marker)
	# Truck faults (N-214): every peer tracks them, the host rolls them.
	var faults: Node = VEHICLE_FAULTS.new()
	faults.name = "VehicleFaults"
	faults.set(&"vehicle", vehicle)
	add_child(faults)
	# The facts of the run, for the next-day newspaper (N-606): every peer notes
	# them, the host writes the paper when the results are decided.
	var chronicle: Node = RUN_CHRONICLE.new()
	add_child(chronicle)
	# Its photos (N-606.5): every peer takes its own still of the same moments.
	add_child(NEWS_PHOTOGRAPHER.new())
	# Mud over the windshield now and then (N-113): the host draws it from the
	# world seed, every peer follows it; only the driver's view shows it.
	var low_visibility: Node = LOW_VISIBILITY.new()
	low_visibility.name = "LowVisibilityEvent"
	low_visibility.set(&"level", self)
	add_child(low_visibility)
	# The dashboard radio (N-406): the host owns its mode, every peer plays it.
	var radio: Node = TRUCK_RADIO.new()
	radio.name = "TruckRadio"
	radio.set(&"vehicle", vehicle)
	add_child(radio)
	# The rescue hook (N-213.3) hangs by the rear doors on every peer, stowed
	# until a run takes it from the depot's supplies.
	var hook: Node3D = RESCUE_HOOK.new()
	hook.name = "RescueHook"
	vehicle.add_child(hook)
	if "--autostart" in OS.get_cmdline_user_args():
		_autostart.call_deferred()
	# The trailer's camera (N-902): F7 free camera, F5/F6/F8 rails. Debug
	# builds only; the tools aren't even exported.
	if OS.is_debug_build() and ResourceLoader.exists(TRAILER_CAMERA):
		var trailer: Camera3D = load(TRAILER_CAMERA).new()
		trailer.name = "TrailerCamera"
		trailer.set(&"target", vehicle)
		add_child(trailer)


## The town the next-day newspaper is named after (RunChronicle asks when it
## writes); "" lets it pick one from the session seed (Endless has no road).
func newspaper_town() -> String:
	return ""


## The depot stands: sends the locked traps' boxes to the back and puts the rest
## on its shelves, then lets what was waiting for the stock go ahead (_after_depot()).
func _stock_depot() -> void:
	packages.assign(depot.withhold_locked(get_tree().get_nodes_in_group(&"cargo")))
	for package: DeliveryPackage in packages:
		package.freeze = true
	depot.stock_shelves(packages)
	_depot_stocked = true
	var waiting: Array[Callable] = _after_depot_steps
	_after_depot_steps = []
	for step: Callable in waiting:
		step.call()


## Runs `step` once the depot is stocked: at once if it already is, else when its
## build is over (it builds itself over frames behind the loading cover).
func _after_depot(step: Callable) -> void:
	if _depot_stocked:
		step.call()
	else:
		_after_depot_steps.append(step)


## The level's own road and orders, set up once the depot is stocked.
func _prepare_mode() -> void:
	pass


## Waits (a coroutine) until the level's world is complete: the depot, and a road
## that builds itself over several frames (route.gd) overrides it to wait for that
## too. Doesn't suspend when it all stands already.
func _wait_for_world() -> void:
	if not depot.is_built:
		await depot.built


## Whether the level's world stands (the depot and a road that build themselves
## over frames say no until they do). Nobody is spawned into it before that:
## _sync_players().
func _is_world_built() -> bool:
	return depot.is_built


## This peer's level is up: tells the session, once the world stands.
func _report_level_ready() -> void:
	var waited: bool = not _is_world_built()
	await _wait_for_world()
	if not is_inside_tree():
		return
	# The players the host couldn't spawn while the world was still building.
	if waited and NetworkManager.is_host():
		_sync_players(NetworkManager.peer_ids)
	NetworkManager.level_ready()


func _autostart() -> void:
	await _wait_for_world()
	if is_inside_tree():
		start_debug_delivery()


## The level's own start: unfreeze, report the cargo, start the run.
func start_delivery() -> void:
	pass


func _on_roster_changed(peer_ids: Array) -> void:
	if NetworkManager.is_host():
		_sync_players(peer_ids)


## Host: someone left the roster; its player is still here, so what it had is
## noted for when it comes back (RejoinKeepsake).
func _on_peer_removed(peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	_rejoin.remember(peer_id, _world.get_node_or_null(NodePath(_player_name(peer_id))) as Node3D)


## The host is gone mid-run (N-222): stop this peer's copy of the run. With
## the session closed this peer counts as an offline host, and would go on
## to score and end the run itself, covering the disconnect screen (which
## shows RunTally) with results. Not finish_run(): nothing is recorded or won.
## The truck is frozen where it is and no longer predicted: a client at the
## wheel was simulating its copy (N-218), and as the offline host it no longer
## stops on its own -- it would roll on, braking and creeping, behind the
## overlay.
func _stop_orphaned_run(_reason: String) -> void:
	RunManager.is_running = false
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.call(&"stop_prediction")


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
	if not _is_world_built():
		return
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
		# Someone back (N-221) waits for its old player -- a ghost dropped this
		# frame -- to be gone: its seat and box are only free after that.
		var note: Dictionary = _rejoin.note_for(id)
		if not note.is_empty() and _rejoin.lingers(note):
			_sync_players_soon()
			continue
		var back: Dictionary = _rejoin.place(note) if not note.is_empty() else {}
		# The truck already out on the road: the depot is behind the crew, so
		# the newcomer appears aboard (late_join_seating.gd).
		var seat: Node = null
		var data: Dictionary = {"peer_id": id, "position": _world.to_local(depot.spawn_position(index))}
		var placed: Dictionary = back if not back.is_empty() else (_late_join.place() if _late_join.underway() else {})
		if not placed.is_empty():
			seat = placed.seat
			data.position = _world.to_local(placed.position)
			# In the truck's own space too: each peer draws its truck a little
			# behind the host's (player_spawner.gd).
			if placed.has("local"):
				data.vehicle_position = placed.local
		var player: Node = $World/PlayerSpawner.spawn(data)
		# Its box first: a passenger boarding with it keeps it on the lap.
		if not note.is_empty() and player != null:
			_rejoin.give_back(player as Node3D, note)
		if seat != null and player != null:
			if back.is_empty():
				_late_join.seat_player(player, seat)
			else:
				_rejoin.seat_back(player as Node3D, seat as SeatPoint)
	for child: Node in _world.get_children():
		if child.name.begins_with("Player_") and not peer_ids.has(_id_from_name(child.name)):
			child.queue_free()
	_refresh_local_player()


## Host: _sync_players() again next frame, once. A connection, not an await:
## a level freed meanwhile takes it along instead of resuming.
func _sync_players_soon() -> void:
	if _resync_queued:
		return
	_resync_queued = true
	get_tree().process_frame.connect(_sync_players_again, CONNECT_ONE_SHOT)


func _sync_players_again() -> void:
	_resync_queued = false
	if is_inside_tree() and NetworkManager.is_host():
		_sync_players(NetworkManager.peer_ids)


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


## True while the wedge rule applies: counted by each level's _physics_process()
## on the host. Not in the mud (MudSegment, N-108: the crew pushes or the crane
## comes), not without a driver and the pedal down, not around the depot, and
## not where the mode's own stops are (_stuck_exempt_here()).
func _should_count_as_stuck() -> bool:
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
	return not _stuck_exempt_here()


## Hook: where else stopping is part of the mode (level_base.gd: the houses and
## the service lay-by; level_endless.gd: the lay-by).
func _stuck_exempt_here() -> bool:
	return false


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
	# Online, every link goes to the level-load timeout now (N-235): the fade
	# gives ENet time to resend the notice to a client if it's lost, which it
	# couldn't once the reload below blocks this process.
	NetworkManager.announce_restart()
	await get_tree().create_timer(0.15).timeout
	RunManager.reset_run()
	# Online, every client reloads too, once this level is back up.
	NetworkManager.begin_restart()
	# Behind the loading screen (N-408), which also lets the road build over
	# frames: a bare reload_current_scene() froze the window ~4 s.
	var loader: LoadingScreen = LoadingScreen.go(get_tree(), scene_file_path, tr("UI_LOADING_TAG_RESTART"))
	# The music plays on under the loading screen instead of dying with this level.
	loader.carry_audio(get_node_or_null(^"IngameMusic") as AudioStreamPlayer)


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
			package.mark_lost("HUD_CARGO_FELL_OFF")
			EventBus.relay(&"cargo_overboard_ended", [id, false])


func _on_run_ended(_score: int, _results: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Defer rigid-body changes: failure can originate in physics integration.
	vehicle.set_deferred("freeze", true)
	for package: DeliveryPackage in packages:
		if is_instance_valid(package):
			package.set_deferred("freeze", true)

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_root.gd
##
## Root scene of the Modo Empresa (expansion D-0214, company_root.gd,
## scenes/gameplay/company_root.tscn, main_menu.gd --mode=company):
## - it loads and builds with no errors, switching the company on (CompanyState);
## - there is one slab per data/zones/*.tres (nine), the zone names are small enough not to fill the
##   player's view (a blurred stripe in the first capture), and a shed (CompanyShed, D-0911) with its
##   floor and walls with collision, open at the dock and the exit; the furnishing is
##   test_company_default_layout's; the floor is warehouse concrete (D-0911 "Suelo del galpón"): its
##   material carries tx_detail_concrete_512.png in world triplanar, one repetition per
##   CompanyShed.FLOOR_SLAB_M (a whole number of grid cells, so the slab joints land on cell lines);
## - the local player stands inside the shed, on the floor;
## - D-2002.3: it sends its pose CompanyTuning.SHED_POSE_RATE_HZ times a second on foot (the interval
##   rounded down, not up), back to the game's 30 while riding a vehicle (a stand-in in the "vehicle"
##   group that carries everyone) and to the shed's rate off it; a player outside the company's world
##   (Delivery, Endless) keeps player.tscn's 30 while it walks;
## - it has a CompanyNet child (D-2003); solo is the host, so it switches the company on
##   and holds its stock (a client would wait for the host's snapshot instead); it hands
##   CompanyNet the CompanyState node, whose to_dict() the snapshot carries (D-2004);
## - it has a GameClock and a DayCycle child hooked to that CompanyNet (D-0203, D-0219); solo opens the
##   company's day once the world is up: OPENING of its day, the clock running from 08:00, and no
##   shed freeze while no shed area is wired;
## - on a client (a session that isn't the host) it waits for the snapshot without touching
##   CompanyState; the snapshot loads the host's company there, and leaving the root puts back
##   what the client had (switched off when it had none, its own company when it had one);
## - D-0508.3: the day's SUMMARY opens the closing screen (DaySummaryPanel) and its "continue" opens the
##   next day on the host;
## - the main menu knows the scene, the --mode=company flag and has the button;
## - it saves in the folder it is given (save_dir, D-2005): leaving the solo root saves the day
##   as interrupted there, and the real slot (user://saves/company/) is never touched;
## - D-2009: what Steam shows goes to NetworkManager's steam_presence (only kept here, no Steam):
##   solo, the company's lobby data and rich presence (CompanyLobbyMeta) once the world is up; a
##   client, the host's company's presence once the snapshot is in, and no lobby data; leaving the
##   root clears both.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
## The roots save here, never in the game's slot.
const DIR: String = "user://test_company_root"
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
## Nobody listens here: the client stays connecting, which is enough not to be the host.
const CLOSED_PORT: int = 24639
## player.tscn's pose rate, the game's (test_remote_pose_smoothing checks it in the delivery level).
const GAME_POSE_RATE_HZ: int = 30
## Physics ticks for the owner to publish its pose (and pick its rate) again.
const POSE_TICKS: int = 3


## A vehicle that carries everyone, wherever they stand (as test_gel_active_ragdoll's).
class Carrier extends Node3D:
	func carries(_point: Vector3, _margin: float = 0.0) -> bool:
		return true

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clean()
	var real_slot: String = _real_slot()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level: Node = _instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	_expect(bool(state.call(&"is_active")), "Entering the root switches the company on")
	# D-0313: the map's cells stream around the crew, and the root never goes through the loader.
	var cells: CompanyCells = level.get_node_or_null(^"WorldCells") as CompanyCells
	_expect(cells != null and cells == level.get(&"cells"), "The root has its WorldCells child (D-0313)")
	if cells != null:
		var spawned: Node3D = level.get(&"player") as Node3D
		_expect(cells.anchors.size() == 1 and cells.anchors[0].distance_to(spawned.global_position) < 0.01,
			"The only anchor is the local player")
		_expect(cells.is_loaded(Vector2i(0, 0)), "The shed's cell is loaded on entering")
	_expect(root.get_node_or_null(^"SceneLoader") == null, "No loader is left once inside the company")
	var net: CompanyNet = level.get_node_or_null(^"CompanyNet") as CompanyNet
	_expect(net != null and net == level.get(&"net"), "The root has its CompanyNet child (D-2003)")
	if net != null:
		var stock: Inventory = state.call(&"stock")
		_expect(net.inventory.to_dict() == stock.to_dict() and not net.awaiting_snapshot(),
			"Solo counts as host: CompanyNet starts from the company's stock, not waiting for a snapshot")
		_expect(net.company == state, "CompanyNet gets the CompanyState node for the snapshot")
		var cycle: DayCycle = level.get(&"day_cycle")
		var clock: GameClock = level.get(&"clock")
		_expect(cycle != null and clock != null and net.day_cycle == cycle and net.clock == clock
			and net.snapshot().has(DayCycle.SNAPSHOT_KEY) and net.snapshot().has(GameClock.SNAPSHOT_KEY),
			"The root hooks a GameClock and a DayCycle to its CompanyNet (D-0203)")
		if cycle != null and clock != null:
			_expect(cycle.phase() == DayCycle.Phase.OPENING and cycle.current_day() == int(state.get(&"day"))
				and not clock.is_paused() and clock.minute_now() < float(CompanyTuning.DAY_START_MIN) + 5.0,
				"Solo opens the company's day: OPENING of day %s with the clock at 08:00 (got %s, %.1f)"
				% [state.get(&"day"), cycle.phase_name(), clock.minute_now()])
			_expect(not cycle.is_frozen(), "...and the shed isn't frozen (no area is wired yet)")
	_expect_presence(state, true, "Solo, with the day open")

	var zone_files: int = 0
	for file: String in DirAccess.get_files_at("res://data/zones/"):
		if file.ends_with(".tres"):
			zone_files += 1
	var slabs: int = 0
	for child: Node in level.get_node(^"World").get_children():
		if child.name.begins_with("Zone_"):
			slabs += 1
			_expect(child.get_child_count() >= 2, "%s has collision, mesh and name" % child.name)
	_expect(slabs == zone_files and slabs == 9, "One slab per zone .tres (%d slabs, %d files)" % [slabs, zone_files])

	var shed: Node = level.get_node(^"World/Shed")
	_expect(shed is CompanyShed and shed == level.get(&"shed"), "The shed is a CompanyShed (D-0911)")
	_expect(CompanyRoot.SHED_SIZE == WarehouseStages.floor_size_m(0), "The shed is the starting stage's floor")
	# Walls are split around the dock (south) and exit (north) gates; the sides are whole.
	for part: String in ["Floor", "WallBackLeft", "WallBackRight", "WallFrontLeft", "WallFrontRight",
			"WallLeft", "WallRight"]:
		_expect(shed.get_node_or_null(NodePath("Shell/" + part)) is StaticBody3D, "The shed has %s" % part)
	_check_floor_material(shed)

	for child: Node in level.get_node(^"World").get_children():
		if child.name.begins_with("Zone_"):
			var name_label: Label3D = child.get_node_or_null(^"Name") as Label3D
			_expect(name_label != null and name_label.pixel_size * name_label.font_size < 20.0,
				"%s's name is not a giant sign (letters %.0f m)" % [child.name,
				name_label.pixel_size * name_label.font_size if name_label != null else -1.0])
	var player: Node3D = level.get(&"player")
	_expect(player != null and player.is_inside_tree(), "The local player is in the scene")
	if player != null:
		var half: Vector2 = CompanyRoot.SHED_SIZE * 0.5
		_expect(absf(player.global_position.x) < half.x and absf(player.global_position.z) < half.y,
			"The player starts inside the shed (%s)" % player.global_position)
		for _i: int in range(90):
			await physics_frame
		var height: float = player.global_position.y
		_expect(height > -1.0, "The player stands on the floor, not falling (y=%.2f)" % height)
		await _check_pose_rate(player as Player, level.get_node(^"World") as Node3D)

	_check_summary_screen(level, state)

	var menu_source: String = FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_expect(menu_source.contains(SCENE) and menu_source.contains("--mode=company"),
		"The main menu opens this scene with --mode=company")
	_expect(menu_source.contains("pressed.connect(_play_company)"), "The Play page has a Modo Empresa button")

	level.queue_free()
	await process_frame
	_expect(CompanySave.was_interrupted(CompanySave.DEFAULT_SLOT, DIR),
		"Leaving the solo root saves the day as interrupted in its save_dir")
	_expect_presence(null, true, "Leaving the solo root")
	await _check_game_pose_rate()
	await _check_client_restores(state)
	state.call(&"reset")
	_expect(_real_slot() == real_slot, "The game's own save slot is never touched")
	_clean()
	if _failures == 0:
		print("PASS: company root builds the shed and nine zones, company on, player inside, menu flag")
	quit(_failures)


## D-0508.3: the day's SUMMARY opens the closing screen with the host's numbers, its "continue" opens
## the next day and the screen goes away with it.
func _check_summary_screen(level: CompanyRoot, state: Node) -> void:
	var panel: DaySummaryPanel = level.summary_panel
	var cycle: DayCycle = level.day_cycle
	_expect(panel != null and not panel.visible,
		"The root has its closing screen, hidden while the day runs (D-0508.3)")
	if panel == null or cycle == null:
		return
	var day: int = cycle.current_day()
	state.call(&"earn", 120, &"order_paid")
	for next: DayCycle.Phase in [DayCycle.Phase.OPERATING, DayCycle.Phase.CLOSING, DayCycle.Phase.SUMMARY]:
		cycle.call(&"_transition", next)
	_expect(cycle.phase() == DayCycle.Phase.SUMMARY and panel.visible,
		"SUMMARY opens the closing screen (phase %s)" % cycle.phase_name())
	panel.close()
	_expect(cycle.phase() == DayCycle.Phase.OPENING and cycle.current_day() == day + 1 and not panel.visible,
		"Its continue opens the next day (day %d, %s)" % [cycle.current_day(), cycle.phase_name()])


## D-2002.3: the company's `player` sends its pose at the shed's rate on foot, the game's riding a
## vehicle (a Carrier in `world`) and the shed's again once off it.
func _check_pose_rate(player: Player, world: Node3D) -> void:
	var sync := player.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var shed_rate: int = CompanyTuning.SHED_POSE_RATE_HZ
	_expect(_rate(sync) == shed_rate and sync.replication_interval <= 1.0 / shed_rate,
		"The company's player sends its pose %d times a second on foot (every %.4f s)"
		% [shed_rate, sync.replication_interval])
	var truck := Carrier.new()
	truck.add_to_group(&"vehicle")
	world.add_child(truck)
	for _tick: int in range(POSE_TICKS):
		await physics_frame
	_expect(player.net_in_vehicle and _rate(sync) == GAME_POSE_RATE_HZ,
		"Riding a vehicle it sends the game's %d a second again (in vehicle %s, every %.4f s)"
		% [GAME_POSE_RATE_HZ, player.net_in_vehicle, sync.replication_interval])
	truck.free()
	for _tick: int in range(POSE_TICKS):
		await physics_frame
	_expect(not player.net_in_vehicle and _rate(sync) == shed_rate,
		"Off the vehicle, the shed's %d a second (every %.4f s)" % [shed_rate, sync.replication_interval])


## D-2002.3: a player of the game, outside the company's world, sends player.tscn's 30 a second
## while it plays (its owner publishes and picks the rate every tick).
func _check_game_pose_rate() -> void:
	var player := (load(CompanyRoot.PLAYER_SCENE) as PackedScene).instantiate() as Player
	player.name = "Player_1"
	root.add_child(player)
	for _tick: int in range(POSE_TICKS):
		await physics_frame
	var sync := player.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	_expect(player.is_local() and _rate(sync) == GAME_POSE_RATE_HZ,
		"A player outside the company's world sends %d poses a second (every %.4f s)"
		% [GAME_POSE_RATE_HZ, sync.replication_interval])
	player.free()


## Sends a second `sync` makes at its interval, rounded.
static func _rate(sync: MultiplayerSynchronizer) -> int:
	return roundi(1.0 / sync.replication_interval) if sync.replication_interval > 0.0 else 0


## A client loads the host's company from the snapshot; leaving the root puts its own back.
func _check_client_restores(state: Node) -> void:
	var host_state: Node = (load(STATE_SCRIPT) as GDScript).new()
	# In the tree, so its facts reach EventBus instead of erroring on an absolute path.
	root.add_child(host_state)
	host_state.call(&"new_company", "Host SRL")
	host_state.call(&"earn", 900, &"order_paid")
	host_state.call(&"open_gate", &"gate_campo")
	var host := CompanyNet.new()
	host.company = host_state
	host.inventory.receive(&"hen", 5, &"dock")
	host.seq = 7
	var snapshot: Dictionary = host.snapshot()
	for own_name: String in ["", "Mine"]:
		state.call(&"reset")
		if own_name != "":
			state.call(&"new_company", own_name)
			state.call(&"earn", 15, &"order_paid")
		var before: Dictionary = state.call(&"to_dict")
		var was_active: bool = state.call(&"is_active")
		var side := Node.new()
		side.name = "ClientSide"
		root.add_child(side)
		set_multiplayer(SceneMultiplayer.new(), side.get_path())
		var peer := ENetMultiplayerPeer.new()
		_expect(peer.create_client("127.0.0.1", CLOSED_PORT) == OK, "A client session starts")
		side.multiplayer.multiplayer_peer = peer
		var level: Node = _instantiate()
		side.add_child(level)
		await process_frame
		var net: CompanyNet = level.get(&"net")
		var label: String = "with no company" if own_name == "" else "with its own company"
		_expect(net != null and not net.is_host() and net.awaiting_snapshot()
			and state.call(&"to_dict") == before,
			"A client %s waits for the snapshot and leaves CompanyState as it was" % label)
		if net != null:
			_expect(net.apply_snapshot(snapshot) and state.get(&"company_name") == "Host SRL"
				and bool(state.call(&"is_active")),
				"The snapshot loads the host's company into the client's CompanyState (%s)" % label)
			_expect_presence(state, false, "A client %s, after the snapshot" % label)
		level.queue_free()
		await process_frame
		_expect_presence(null, true, "A client %s, after leaving" % label)
		_expect(bool(state.call(&"is_active")) == was_active and state.call(&"to_dict") == before,
			"Leaving the root puts back what the client had %s (active %s, name '%s')"
			% [label, state.call(&"is_active"), state.get(&"company_name")])
		peer.close()
		set_multiplayer(null, side.get_path())
		side.free()
	host.free()
	host_state.free()


## D-2009: NetworkManager's steam_presence (only kept: no Steam here) holds what CompanyLobbyMeta
## builds for `company` (null: none), its keys set to "" left out; the lobby data only when `as_host`.
func _expect_presence(company: Node, as_host: bool, when: String) -> void:
	var session: NetSession = root.get_node_or_null(^"/root/NetworkManager") as NetSession
	if session == null:
		_expect(false, "NetworkManager is a NetSession, with a steam_presence")
		return
	var shown: CompanyLobbyMeta.COMPANY_STATE = company as CompanyLobbyMeta.COMPANY_STATE
	var lobby: Dictionary = _without_blanks(CompanyLobbyMeta.lobby_meta(shown)) if as_host else {}
	var presence: Dictionary = _without_blanks(CompanyLobbyMeta.rich_presence(shown))
	var kept_lobby: Dictionary = session.steam_presence.lobby_meta()
	var kept_presence: Dictionary = session.steam_presence.rich_presence()
	_expect(kept_lobby == lobby and kept_presence == presence and (company == null or not presence.is_empty()),
		"%s: Steam is handed lobby data %s and presence %s (got %s, %s)"
		% [when, lobby, presence, kept_lobby, kept_presence])


static func _without_blanks(values: Dictionary) -> Dictionary:
	var kept: Dictionary = {}
	for key: Variant in values:
		if not String(values[key]).is_empty():
			kept[key] = values[key]
	return kept


## The scene, saving in DIR (set before it enters the tree: the host loads from there on entry).
func _instantiate() -> CompanyRoot:
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	return level


## What the game's slot holds now, its file, .bak and .tmp ("" for each one missing).
static func _real_slot() -> String:
	var path: String = CompanySave.path_for()
	var parts: PackedStringArray = []
	for file: String in [path, path + ".bak", path + ".tmp"]:
		parts.append(FileAccess.get_file_as_string(file) if FileAccess.file_exists(file) else "")
	return "|".join(parts)


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _check_floor_material(shed: Node) -> void:
	var floor_mesh: MeshInstance3D = null
	var floor_body: Node = shed.get_node_or_null(^"Shell/Floor")
	if floor_body != null:
		for child: Node in floor_body.get_children():
			if child is MeshInstance3D:
				floor_mesh = child
	var mesh: PrimitiveMesh = floor_mesh.mesh as PrimitiveMesh if floor_mesh != null else null
	var material := mesh.material as StandardMaterial3D if mesh != null else null
	var texture: Texture2D = material.albedo_texture if material != null else null
	_expect(texture != null and texture.resource_path.ends_with("tx_detail_concrete_512.png"),
		"The shed floor carries the concrete detail map (got %s)"
		% (texture.resource_path if texture != null else "none"))
	if material == null:
		return
	_expect(material.uv1_triplanar and material.uv1_world_triplanar, "The floor's concrete is world triplanar")
	var cells: float = CompanyShed.FLOOR_SLAB_M / CompanyTuning.WAREHOUSE_GRID_M
	var per_slab: bool = is_equal_approx(material.uv1_scale.x, 1.0 / CompanyShed.FLOOR_SLAB_M)
	_expect(per_slab and is_equal_approx(cells, roundf(cells)),
		"One concrete repetition per %.1f m, a whole number of grid cells" % CompanyShed.FLOOR_SLAB_M)
	_expect(material == CompanyShed.floor_material(), "The floor material is shared, not one per redraw")

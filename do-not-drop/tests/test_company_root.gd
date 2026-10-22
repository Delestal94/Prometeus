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
## - D-0316: it has an Interest child (CompanyInterest) reading CompanyRoot.CREW_GROUP, which tracks a
##   node put in the company_vehicle group; solo is the host, so the cells anchor on the player and
##   on that vehicle;
## - D-2002.3: it sends its pose CompanyTuning.SHED_POSE_RATE_HZ times a second on foot (the interval
##   rounded down, not up), back to the game's 30 while riding a vehicle (a stand-in in the "vehicle"
##   group that carries everyone) and to the shed's rate off it; a player outside the company's world
##   (Delivery, Endless) keeps player.tscn's 30 while it walks;
## - it has a CompanyNet child (D-2003); solo is the host, so it switches the company on
##   and holds its stock (a client would wait for the host's snapshot instead); it hands
##   CompanyNet the CompanyState node, whose to_dict() the snapshot carries (D-2004);
## - it has a GameClock and a DayCycle child hooked to that CompanyNet (D-0203, D-0219); solo opens the
##   company's day once the world is up: OPENING of its day, the clock running from 08:00, and the
##   shed not frozen with its player in it;
## - D-0316.1: the shed holds (CompanyShed.holds()) the spawn, at any height, and whoever stands in the
##   dock's or the exit's gate, not a point 20 m out of it; the root wires DayCycle.crew_in_shed: yes
##   with the player where it spawned, no with it 20 m out, yes again back in; no with it seated on a
##   seat 20 m out while its body is still in (Player.reach_origin()); yes with another crew member of
##   the session in and the player out, no with both out; a crew member of another session (its own
##   SceneMultiplayer) standing in the shed doesn't count; with the player out
##   during OPERATING the shed freezes (one event; shed_minute() stands still while the world clock
##   runs) and thaws when it is back (on the test's own ticks, no frame in between);
## - on a client (a session that isn't the host) it waits for the snapshot without touching
##   CompanyState; the snapshot loads the host's company there, and leaving the root puts back
##   what the client had (switched off when it had none, its own company when it had one);
## - the main menu knows the scene, the --mode=company flag and has the button;
## - it saves in the folder it is given (save_dir, D-2005): leaving the solo root saves the day
##   as interrupted there, and the real slot (user://saves/company/) is never touched;
## - D-2009: what Steam shows goes to NetworkManager's steam_presence (only kept here, no Steam):
##   solo, the company's lobby data and rich presence (CompanyLobbyMeta) once the world is up; a
##   client, the host's company's presence once the snapshot is in, and no lobby data; leaving the
##   root clears both;
## - D-0510.2: the root hands its DayCycle the opening notice: the bankruptcy warning with the
##   company in the red, "" in the black.

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
## D-0316.1: how far out of the shed's floor the player stands on the street, and for how many of the
## test's seconds it stays out (past CompanyTuning.SHED_FREEZE_SETTLE_REAL_SECONDS, so it can thaw).
const OUT_M: float = 20.0
const OUT_SECONDS: float = 3.0


## A vehicle that carries everyone, wherever they stand (as test_gel_active_ragdoll's).
class Carrier extends Node3D:
	func carries(_point: Vector3, _margin: float = 0.0) -> bool:
		return true

var _failures: int = 0
## The test's own ticks (_ticks()) for the root's DayCycle and GameClock: real time stopped at
## _base_msec, moved on by hand.
var _base_msec: int = 0
var _skip_msec: int = 0


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
	await _check_interest(level)
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
			_expect(not cycle.is_frozen(), "...and the shed isn't frozen: its player stands in it")
	_expect_presence(state, true, "Solo, with the day open")
	_check_bankrupt_notice(level as CompanyRoot, state)

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
		_check_crew_in_shed(level as CompanyRoot)

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


## D-0510.2: the root's DayCycle.opening_notice is the bankruptcy warning in the red, "" in the black.
func _check_bankrupt_notice(level: CompanyRoot, state: Node) -> void:
	var notice: Callable = level.day_cycle.opening_notice
	_expect(notice.is_valid(), "The root gives its DayCycle the day's opening notice")
	var money: int = int(state.get(&"money"))
	state.set(&"money", 500)
	_expect(str(notice.call()).is_empty(), "A day opening in the black shows no warning")
	state.set(&"money", -1)
	_expect(not str(notice.call()).is_empty(), "A day opening in the red shows the bankruptcy warning")
	state.set(&"money", money)


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


## D-0316.1: the shed holds the spawn and its gates, not the street, and the root's DayCycle reads its
## crew from it. The player is moved without a frame in between, so it never falls on the street.
func _check_crew_in_shed(level: CompanyRoot) -> void:
	var shed: CompanyShed = level.shed
	var half: Vector2 = WarehouseStages.floor_size_m(shed.stage) * 0.5
	_expect(shed.holds(CompanyRoot.SPAWN) and shed.holds(CompanyRoot.SPAWN + Vector3.UP * 10.0),
		"The shed holds the spawn %s, at any height" % CompanyRoot.SPAWN)
	# The middle of each gate, in the walls' line: dock south, exit north.
	var gates: Array[Rect2i] = WarehouseStages.gate_rects(shed.stage)
	var in_wall: float = half.y + CompanyShed.WALL_THICKNESS * 0.5
	var dock: Vector3 = shed.cell_to_local(Vector2(gates[0].position) + Vector2(gates[0].size) * 0.5)
	var door: Vector3 = shed.cell_to_local(Vector2(gates[1].position) + Vector2(gates[1].size) * 0.5)
	dock.z = in_wall
	door.z = -in_wall
	_expect(shed.holds(dock) and shed.holds(door),
		"...and whoever stands in the dock's gate %s or the exit's %s" % [dock, door])
	var south := Vector3(0.0, 1.0, half.y + OUT_M)
	var east := Vector3(half.x + OUT_M, 1.0, 0.0)
	_expect(not shed.holds(south) and not shed.holds(east),
		"...but not a point %.0f m out of its floor (%s, %s)" % [OUT_M, south, east])
	var cycle: DayCycle = level.day_cycle
	var player: Node3D = level.player
	_expect(cycle.crew_in_shed.is_valid(), "The root wires DayCycle.crew_in_shed")
	if not cycle.crew_in_shed.is_valid() or player == null:
		return
	var home: Vector3 = player.global_position
	_expect(bool(cycle.crew_in_shed.call()), "With its player where it spawned (%s) the crew is in the shed" % home)
	var street := Vector3(home.x, home.y, half.y + OUT_M)
	player.global_position = street
	_expect(not bool(cycle.crew_in_shed.call()),
		"With its player %.0f m out (%s) nobody is in the shed" % [OUT_M, street])
	player.global_position = home
	_expect(bool(cycle.crew_in_shed.call()), "...and back in, the crew is in again")
	_check_seated_and_others(level, player as Player, street)
	_check_frozen_shed(level, street)


## A seated player is where its seat is (Player.reach_origin()), not where its body stayed; another
## crew member of the same session keeps the shed in; one of another session (its own multiplayer)
## counts for nothing here. Every node added is freed before returning, with no frame in between.
func _check_seated_and_others(level: CompanyRoot, player: Player, street: Vector3) -> void:
	var inside: Callable = level.day_cycle.crew_in_shed
	var home: Vector3 = player.global_position
	var seat := Node3D.new()
	seat.name = "StreetSeat"
	level.get_node(^"World").add_child(seat)
	seat.global_position = street
	player.seat_node_path = player.get_path_to(seat)
	_expect(not bool(inside.call()) and level.shed.holds(player.global_position),
		"Seated %.0f m out, with its body still in the shed (%s), nobody is in it" % [OUT_M, player.global_position])
	player.seat_node_path = NodePath()
	seat.free()
	_expect(bool(inside.call()), "...and off the seat, its body in the shed, the crew is in again")
	var mate := Node3D.new()
	mate.name = "CrewMate"
	mate.add_to_group(CompanyRoot.CREW_GROUP)
	level.get_node(^"World").add_child(mate)
	mate.global_position = CompanyRoot.SPAWN
	player.global_position = street
	_expect(bool(inside.call()), "With the player out and another of the crew in, the crew is in the shed")
	mate.global_position = street
	_expect(not bool(inside.call()), "...and with both out, nobody is")
	mate.free()
	# Another session in this process: its own SceneMultiplayer, a crew member standing in the shed.
	var side := Node.new()
	side.name = "OtherSession"
	root.add_child(side)
	set_multiplayer(SceneMultiplayer.new(), side.get_path())
	var stranger := Node3D.new()
	stranger.name = "Stranger"
	stranger.add_to_group(CompanyRoot.CREW_GROUP)
	stranger.position = CompanyRoot.SPAWN
	side.add_child(stranger)
	_expect(stranger.multiplayer != level.multiplayer and level.shed.holds(stranger.global_position)
		and not bool(inside.call()),
		"A crew member of another session standing in the shed doesn't count: with the player out nobody is in")
	set_multiplayer(null, side.get_path())
	side.free()
	player.global_position = home
	_expect(bool(inside.call()), "...and the player back in, the crew is in again")


## The shed freezes with the player out during OPERATING and thaws once it is back, as the day's own
## events. The cycle and the clock run on the test's ticks (_ticks()), and no frame passes, so the
## root's BusinessTick polls nothing in between. They keep those ticks until the root is freed (the
## real ones would put the clock back by what was skipped).
func _check_frozen_shed(level: CompanyRoot, street: Vector3) -> void:
	var cycle: DayCycle = level.day_cycle
	var clock: GameClock = level.clock
	var player: Node3D = level.player
	var home: Vector3 = player.global_position
	_base_msec = Time.get_ticks_msec()
	_skip_msec = 0
	cycle.ticks = _ticks
	clock.ticks = _ticks
	# Past the opening's real seconds (the BusinessTick may have got there already).
	_skip_msec += roundi(CompanyTuning.OPENING_REAL_SECONDS * 1000.0)
	cycle.poll()
	_expect(cycle.phase() == DayCycle.Phase.OPERATING and not cycle.is_frozen(),
		"Past the opening the day is OPERATING with the shed running (got %s, frozen %s)"
		% [cycle.phase_name(), cycle.is_frozen()])
	var seq: int = level.net.seq
	player.global_position = street
	cycle.poll()
	var frozen_at: float = cycle.shed_minute()
	_expect(cycle.is_frozen() and level.net.seq == seq + 1 and is_equal_approx(frozen_at, clock.minute_now()),
		"With its player out the shed freezes at the world's minute, as one event (frozen %s, seq +%d, %.2f)"
		% [cycle.is_frozen(), level.net.seq - seq, frozen_at])
	_skip_msec += roundi(OUT_SECONDS * 1000.0)
	cycle.poll()
	_expect(clock.minute_now() > frozen_at + 1.0 and is_equal_approx(cycle.shed_minute(), frozen_at)
		and level.net.seq == seq + 1,
		"%.0f s later the world is at %.2f and the shed still reads %.2f (seq +%d)"
		% [OUT_SECONDS, clock.minute_now(), cycle.shed_minute(), level.net.seq - seq])
	player.global_position = home
	cycle.poll()
	_expect(not cycle.is_frozen() and level.net.seq == seq + 2 and is_equal_approx(cycle.shed_minute(), frozen_at),
		"Back in, the shed thaws from %.2f (frozen %s, seq +%d, shed %.2f)"
		% [frozen_at, cycle.is_frozen(), level.net.seq - seq, cycle.shed_minute()])


## The test's ticks for the root's DayCycle and GameClock: real time stopped, moved on by _skip_msec.
func _ticks() -> int:
	return _base_msec + _skip_msec


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


## D-0316: the Interest child, and the host's cells anchored on every company vehicle too.
func _check_interest(level: Node) -> void:
	var interest: CompanyInterest = level.get_node_or_null(^"Interest") as CompanyInterest
	_expect(interest != null and interest == level.get(&"interest"), "The root has its Interest child (D-0316)")
	if interest == null:
		return
	_expect(interest.crew_group == CompanyRoot.CREW_GROUP, "The interest reads the crew group")
	var van := Node3D.new()
	van.name = "van_test"
	van.position = Vector3(300.0, 0.0, -40.0)
	var sync := MultiplayerSynchronizer.new()
	var config := SceneReplicationConfig.new()
	config.add_property(^".:position")
	sync.replication_config = config
	van.add_child(sync)
	van.add_to_group(CompanyTrips.VEHICLE_GROUP)
	level.add_child(van)
	# The root's _process runs after process_frame is emitted: two frames for it to have run once.
	await process_frame
	await process_frame
	interest.step(Time.get_ticks_msec() / 1000.0 + 1.0)
	_expect(interest.is_tracked(sync), "A company vehicle's synchronizer is tracked by the interest")
	var cells: CompanyCells = level.get(&"cells")
	_expect(cells.anchors.size() == 2 and cells.anchors.has(van.global_position),
		"Solo is the host: the cells anchor on the player and the vehicle (got %s)" % [cells.anchors])
	van.free()
	interest.step(Time.get_ticks_msec() / 1000.0 + 2.0)
	_expect(interest.tracked_count() == 0, "A freed vehicle is forgotten (got %d)" % interest.tracked_count())


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

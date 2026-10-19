class_name CompanyRoot
extends Node3D
## Root scene of the "Modo Empresa" (expansion D-0214, docs/arquitectura.md section 10).
##
## The first thing you can walk around in: the company's shed in the industrial park
## and the nine zones of the continuous map drawn as flat slabs with their name,
## all from data (data/zones/*.tres), nothing placed by hand. The shed (CompanyShed) is
## furnished from the company's layout: a new company starts from DefaultShed (D-0911, D-0620):
## dock and reception with the first pallets, shelves with stock, two packing tables and the
## dispatch zone by the exit. It is a grey-box stand-in until the final models and the district
## scenes exist; what is final here is the entry: --mode=company or the menu opens this scene, the
## company is switched on (CompanyState) and the local player stands in the shed.
##
## No vehicle, no route and no run: Delivery and Endless ignore all of this
## (level_base.gd / level_endless.gd are untouched).
##
## Its "CompanyNet" child carries the business events (D-2003): on the host it
## starts from the company's stock and, until stations exist, refuses every units
## request; on a client it holds the events until the host's snapshot (D-2004), which
## also loads the host's company into this peer's CompanyState.
##
## The host leaving mid-day (D-2005, like N-222): a client keeps what it saw of the
## host's day for the menu (CompanyInterruptedDay), gets its own company back, stops
## the world and loads the main menu. The host (solo too) loads its slot when it comes
## up without a company (CompanySave) and saves the day as it stood at the last applied
## event, marked interrupted, whenever its world closes before the day does: its session
## ended and it went back to the menu, or the game closed. Every day is still saved as in progress,
## also one DayCycle (D-0203) already closed (its SUMMARY phase): saving the closed day is D-0206's
## hook (docs/expansion-distritos/revisar/D-0203.md).
##
## The day (D-0203): the root gives every peer a GameClock and a DayCycle child, both attached to
## CompanyNet before the snapshot goes out. The host opens the company's day once the world is up;
## the phases and the clock then run by themselves (DayCycle). The shed's area is not wired as
## DayCycle.crew_in_shed yet (no remote player nodes exist), so the shed never freezes here.
##
## Steam (D-2009): what the company shows, CompanyLobbyMeta's lobby data (host) and rich presence,
## goes to NetworkManager's steam_presence (NetSteamPresence) when the world comes up, on every
## day_phase event and on a client's snapshot, and is cleared when the world closes. Without Steam
## it is only kept there.

## The CompanyState autoload's script (no class_name: a --script compiles before the autoloads exist).
const COMPANY_STATE := preload("res://scripts/core/company/company_state.gd")
const ZONE_DIR: String = "res://data/zones/"
const PLAYER_SCENE: String = "res://scenes/gameplay/player/player.tscn"
## Where a client goes when its host is gone (as hud_pause.leave_to_menu()). Temporary here in
## gameplay/: once the company HUD exists, the host-gone screen and the way to the menu move
## there, as N-222's live in hud_pause.gd.
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
## Where a save puts the units players held (D-2005): a loaded day opens with empty hands. The
## shed has no fixed spot for them yet (no station gives a location), so they lie in floor
## bundle 0, a floor:<n> location of red-autoridad.md section 2 (row 7). D-2006 / D-0611 will
## refine where they go (where each player stood).
const SAVED_HANDS_LOCATION: StringName = &"floor:0"
## The starting shed (stage 0 of WarehouseStages, 12 x 8 cells of 1 m), in meters: centered on the
## origin, inside the industrial park. A bigger stage draws a bigger floor (CompanyShed).
const SHED_SIZE: Vector2 = Vector2(12.0, 8.0)
## Where the player appears: on the dock floor, facing the shed (north, -Z).
const SPAWN: Vector3 = Vector3(0.0, 1.0, 2.6)
## The group of every player here: this is the company, there is no vehicle to practise for
## (the delivery practice card, player_cargo_care.gd, checks it).
const CREW_GROUP: StringName = &"company_crew"
## Zone names over the map: size of a pixel of their 256 px letters, and height over the ground.
const ZONE_LABEL_PIXEL_SIZE: float = 0.06
const ZONE_LABEL_HEIGHT: float = 30.0
const ZONE_COLORS: Dictionary = {
	&"parque_industrial": Color(0.55, 0.55, 0.58),
	&"centro": Color(0.62, 0.58, 0.50),
	&"suburbio": Color(0.50, 0.62, 0.50),
	&"campo": Color(0.45, 0.62, 0.35),
	&"puerto": Color(0.40, 0.55, 0.65),
	&"islas": Color(0.35, 0.65, 0.70),
	&"montana": Color(0.55, 0.50, 0.45),
	&"nieve": Color(0.85, 0.88, 0.92),
	&"volcan": Color(0.55, 0.25, 0.20),
}

var zones: Array[ZoneDefinition] = []
var player: Node3D
## The shed the players walk in, drawn from the company's layout and stock.
var shed: CompanyShed
## Requests and events of the company's business (D-2003, CompanyNet).
var net: CompanyNet
## The day's clock and phases (D-0219, D-0203), children of this root on every peer.
var clock: GameClock
var day_cycle: DayCycle
## Host: the slot and folder the company is loaded from when the world comes up without one,
## and an interrupted day is saved to (save_interrupted_day()). A test points them at a folder
## of its own before adding the root.
var save_slot: String = CompanySave.DEFAULT_SLOT
var save_dir: String = CompanySave.SAVE_DIR

var _world: Node3D
## Client: the CompanyState node the host's snapshot writes into, and what it held before (its
## to_dict(), or {} when no company was on), put back on leaving (_exit_tree()).
var _mirrored_state: COMPANY_STATE
var _own_company: Dictionary = {}
## Host (solo too): the CompanyState node it runs, saved when the world closes mid-day. Decided
## when the world comes up: a client whose session ended counts as a host to CompanyNet then.
var _hosted_state: COMPANY_STATE
## Client: a snapshot put the host's company in its mirror (there is a day to sum up).
var _saw_host_day: bool = false
## Client: the host is gone and the menu is on its way; nothing here runs any more.
var _host_gone: bool = false
## The session (the NetworkManager autoload, by path: N-919), or null where there is none.
var _session: NetSession
## What was last handed to Steam (_publish_presence()): [lobby data, rich presence].
var _presence_shown: Array = []


func _ready() -> void:
	_start_company(get_node_or_null(^"/root/CompanyState") as COMPANY_STATE)
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_add_environment()
	zones = load_zones()
	for zone: ZoneDefinition in zones:
		_add_zone_slab(zone)
	_add_shed()
	_spawn_player()
	_publish_presence()
	_open_company_day.call_deferred()


## Every zone in data/zones/, in a stable order. A new .tres joins without code.
static func load_zones() -> Array[ZoneDefinition]:
	var found: Array[ZoneDefinition] = []
	var files: PackedStringArray = DirAccess.get_files_at(ZONE_DIR)
	files.sort()
	for file: String in files:
		if file.ends_with(".tres"):
			var zone := load(ZONE_DIR + file) as ZoneDefinition
			if zone != null:
				found.append(zone)
	return found


## Same name on every peer, so its RPCs reach the same node. The host (solo
## counts), with no company on, loads its slot (a new company only when there is
## none to load) and hands CompanyNet its stock (CompanyState.stock(): a copy the
## events keep up to date). A client
## writes nothing (rule 1 of red-autoridad.md): an empty stock, and every event
## held until the host's snapshot puts the real one, and the host's company, in
## place (D-2004); what the client's CompanyState held before comes back when it
## leaves. Both hand CompanyNet the state: the host's goes in the snapshot.
func _add_net(state: COMPANY_STATE) -> void:
	net = CompanyNet.new()
	net.name = "CompanyNet"
	net.company = state
	add_child(net)
	_add_day(state)
	if not net.is_host():
		if state != null:
			_mirrored_state = state
			_own_company = state.to_dict() if state.is_active() else {}
		net.wait_for_snapshot()
		return
	if state == null:
		return
	if not state.is_active():
		# The slot first: a new company here would erase it on the first exit
		# (save_interrupted_day()). CORRUPT already starts a new company (the bad file is kept as
		# .bad); MISSING and TOO_NEW leave it off. A newer build's file is never overwritten
		# (CompanySave.save()), so a new company played over one is not saved.
		CompanySave.load_into(state, save_slot, save_dir)
		if not state.is_active():
			state.new_company()
	# A new company (or a save from before the default existed) starts with the furnished shed:
	# pieces and units, free and the same on every run. It goes in the state before CompanyNet
	# copies the stock, and reaches the clients with the snapshot (D-2004).
	if DefaultShed.needs_default(state):
		var report: Dictionary = DefaultShed.load_default().apply_to(state)
		for refusal: Dictionary in report["refused"]:
			push_warning("CompanyRoot: the default shed left out %s (%s)" % [refusal["uid"], refusal["reason"]])
	net.inventory = state.stock()
	_hosted_state = state


## The day's clock and phases, hooked to CompanyNet on every peer in the frame it is added: the
## snapshot to the peers already up goes out deferred, after this.
func _add_day(state: COMPANY_STATE) -> void:
	clock = GameClock.new()
	clock.name = "GameClock"
	add_child(clock)
	clock.attach(net, state)
	day_cycle = DayCycle.new()
	day_cycle.name = "DayCycle"
	add_child(day_cycle)
	day_cycle.attach(net, clock, state)


## Host (solo too): the company's day opens, after the snapshot to the peers already up. A client
## waits for the host's events.
func _open_company_day() -> void:
	if not is_inside_tree() or _host_gone or not net.is_host() or _hosted_state == null:
		return
	day_cycle.open_day(_hosted_state.day)


## The business side of the world, before the world itself: CompanyNet (_add_net()) and, on a
## client, the watch for its host going away, on two signals: this root's multiplayer
## server_disconnected (the host left or dropped) and NetworkManager's session_failed, by path
## (a handshake that times out or is refused ends the session with no server_disconnected).
## Whichever comes first does it and the other finds _host_gone set; _on_host_lost() only reads
## this peer's mirror and changes scene, so it doesn't matter whether the session already ended.
func _start_company(state: COMPANY_STATE) -> void:
	_session = get_node_or_null(^"/root/NetworkManager") as NetSession
	_add_net(state)
	net.event_applied.connect(_on_event_applied)
	if net.is_host():
		return
	net.company_state_restored.connect(_on_host_day_restored)
	if not multiplayer.server_disconnected.is_connected(_on_host_lost):
		multiplayer.server_disconnected.connect(_on_host_lost)
	if _session != null and not _session.session_failed.is_connected(_on_session_failed):
		_session.session_failed.connect(_on_session_failed)


## Host (solo too): the day as it stands, at the last applied event, saved as interrupted
## (CompanySave): the live stock goes into the company first as a save keeps it (stock_for_save():
## nobody holds anything when it loads). Loading it plays the same day again from the opening.
## False on a client, without a company on, over a newer build's save or when the file could not
## be written.
func save_interrupted_day() -> bool:
	if _hosted_state == null or not is_instance_valid(_hosted_state):
		return false
	if not _hosted_state.is_active():
		return false
	if net != null and is_instance_valid(net) and net.inventory != null:
		_hosted_state.store_stock(stock_for_save(net.inventory))
	var saved: bool = CompanySave.save(_hosted_state, save_slot, save_dir, true)
	if not saved:
		push_warning("CompanyRoot: the interrupted day %d could not be saved to %s"
			% [_hosted_state.day, CompanySave.path_for(save_slot, save_dir)])
	return saved


## A copy of `stock` as a save keeps it (D-2005): what every hands:<peer> held lies in
## SAVED_HANDS_LOCATION, with the total of each product and the reservations unchanged. `stock`
## itself (CompanyNet's live one) is not touched.
static func stock_for_save(stock: Inventory) -> Inventory:
	var copy := Inventory.new()
	copy.from_dict(stock.to_dict())
	var by_product: Dictionary = copy.to_dict().get("stock", {})
	for product: Variant in by_product:
		var locations: Dictionary = by_product[product]
		for location: Variant in locations:
			if String(location).begins_with(CompanyNet.HANDS_PREFIX):
				copy.move(StringName(product), int(locations[location]), StringName(location),
					SAVED_HANDS_LOCATION)
	return copy


## What this client saw of the host's day (CompanyInterruptedDay.summary()): the mirror's day,
## money and wallet history, the live stock and, with a clock, its minute. {} on the host or
## before any snapshot.
func host_day_seen() -> Dictionary:
	if not _saw_host_day or _mirrored_state == null or not is_instance_valid(_mirrored_state):
		return {}
	var minute: int = -1
	if net != null and is_instance_valid(net) and net.clock != null and is_instance_valid(net.clock):
		minute = floori(net.clock.minute_now())
	var stock: Inventory = net.inventory if net != null and is_instance_valid(net) else null
	return CompanyInterruptedDay.summary(_mirrored_state, stock, minute)


## The host's world closing mid-day saves the day as interrupted (D-2005); a client leaves the
## host's company behind: its CompanyState goes back to what it had before the snapshot
## (switched off when it had none), so solo play or a save never takes the host's.
func _exit_tree() -> void:
	if _hosted_state != null:
		save_interrupted_day()
		_hosted_state = null
	_restore_own_company()
	_publish_presence()


func _restore_own_company() -> void:
	if _mirrored_state == null or not is_instance_valid(_mirrored_state):
		return
	if _own_company.is_empty():
		_mirrored_state.reset()
	else:
		_mirrored_state.from_dict(_own_company)
	_mirrored_state = null


## The shed redraws itself from the snapshot (CompanyShed.follow()).
func _on_host_day_restored(_snapshot_seq: int) -> void:
	_saw_host_day = true
	_publish_presence()


## A new day (or phase) of the company: Steam shows the new day (D-2009). The shed follows the
## units and layout events itself (CompanyShed.follow(), D-0910).
func _on_event_applied(_seq: int, kind: StringName, _data: Dictionary) -> void:
	if kind == CompanyNet.DAY_PHASE:
		_publish_presence()


## The company Steam shows for this peer (D-2009): the host's own (solo too) while its world is up; on
## a client the host's, in its mirror, once a snapshot put it there; null otherwise (none yet, the
## host gone, or the world closing).
func _shown_company() -> COMPANY_STATE:
	if not is_inside_tree() or _host_gone:
		return null
	if _hosted_state != null and is_instance_valid(_hosted_state):
		return _hosted_state
	if _saw_host_day and _mirrored_state != null and is_instance_valid(_mirrored_state):
		return _mirrored_state
	return null


## What Steam shows of the company (D-2009, CompanyLobbyMeta): the lobby's company_name and
## company_day on the host, the player's rich presence on every peer. Only a change goes out; with
## no company to show (_shown_company()) both are cleared, the lobby's keys too.
func _publish_presence() -> void:
	if _session == null or not is_instance_valid(_session):
		return
	var company: COMPANY_STATE = _shown_company()
	var shown: Array = [CompanyLobbyMeta.lobby_meta(company), CompanyLobbyMeta.rich_presence(company)]
	if shown == _presence_shown:
		return
	var as_host: bool = company == null or (net != null and is_instance_valid(net) and net.is_host())
	CompanyLobbyMeta.publish(_session.steam_presence, company, as_host)
	_presence_shown = shown


func _on_session_failed(_reason: String) -> void:
	_on_host_lost()


## Client: the host went away mid-day (D-2005). What it saw of the day is kept for the menu
## before its own company comes back; the world stops (a clock or a request here would now act
## as a host on the mirror) and the main menu loads, as hud_pause.leave_to_menu() does. The
## jump to the menu is here only until the company HUD exists (see MAIN_MENU_SCENE).
func _on_host_lost() -> void:
	if _host_gone or _hosted_state != null:
		return
	_host_gone = true
	CompanyInterruptedDay.hold(host_day_seen())
	_restore_own_company()
	process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file.call_deferred(MAIN_MENU_SCENE)


func _add_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	add_child(sun)
	var sky_material := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)


## A flat slab over the zone's rectangle, a hair under the ground line so the
## shed floor, laid on top, hides the part they share.
func _add_zone_slab(zone: ZoneDefinition) -> void:
	var color: Color = ZONE_COLORS.get(zone.id, Color(0.5, 0.5, 0.5))
	var size := Vector3(zone.bounds.size.x, 0.2, zone.bounds.size.y)
	var center := Vector3(zone.bounds.get_center().x, -0.2, zone.bounds.get_center().y)
	var slab: StaticBody3D = CompanyShed.solid_box("Zone_%s" % zone.id, size, center, color)
	_world.add_child(slab)
	var label := Label3D.new()
	label.name = "Name"
	label.text = String(zone.id).to_upper()
	# Letters about 15 m tall, 30 m up: a name to read from afar. At pixel_size 0.5 they were 128 m tall
	# and the industrial park's, right over the shed, filled the player's view with a blurred stripe.
	label.font_size = 256
	label.pixel_size = ZONE_LABEL_PIXEL_SIZE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(center.x, ZONE_LABEL_HEIGHT, center.z)
	slab.add_child(label)


func _add_shed() -> void:
	shed = CompanyShed.new()
	shed.name = "Shed"
	_world.add_child(shed)
	_redraw_shed()
	if net != null:
		shed.follow(net)


## The shed from the company as this peer holds it: on the host what it started with; on a client
## the host's, once the snapshot is in (until then, bare).
func _redraw_shed() -> void:
	if shed != null and net != null and net.company != null:
		shed.rebuild(net.company, net.inventory)


func _spawn_player() -> void:
	var id: int = multiplayer.get_unique_id()
	player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Node3D
	player.name = "Player_%d" % id
	player.position = SPAWN
	player.add_to_group(CREW_GROUP)
	player.set_multiplayer_authority(id)
	_world.add_child(player)

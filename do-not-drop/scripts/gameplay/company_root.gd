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
## scenes exist; what is final here is the entry: --autostart-company (alias --mode=company) or the
## menu's Empresa button opens this scene, the company is switched on (CompanyState) and the local
## player stands in the shed.
##
## Online (the D-0214 follow-up): it is one of NetworkManager.LEVEL_SCENES, so a host here (the
## menu's --host-company) sends every joiner to it. Each peer tells the
## session its world is up (level_ready(), as level_common.gd does), which on a client is what has
## the host send CompanyNet's snapshot and spawn its player. The crew is spawned by the host alone,
## through World/PlayerSpawner (the path LoadingScreen waits on): one player per peer whose world
## is up, at the first spot around SPAWN nobody stands on (free_spawn()), freed when its peer leaves
## the roster, after CompanyNet let go of what it held (D-2006). Solo, and a host alone, is a crew of
## one: the same player at SPAWN it always was.
##
## The company's vehicles (`fleet`) park in the playon outside the shed's exit on every peer and can be driven
## (CompanyFleet, D-0302.2.b); no route and no run: Delivery and Endless ignore all of this.
##
## Its "CompanyNet" child carries the business events (D-2003): on the host it
## starts from the company's stock and, until stations exist, refuses every units
## request; on a client it holds the events until the host's snapshot (D-2004), which
## also loads the host's company into this peer's CompanyState.
##
## The host leaving mid-day (D-2005, like N-222): a client keeps what it saw of the
## host's day for the menu (CompanyInterruptedDay), gets its own company back, stops
## the world and loads the main menu. The host (solo too) loads its slot when it comes
## up without a company (CompanySave), saves a slot with none as that day's opening (D-0251) and,
## whenever its world closes before the day does (session ended, back to the menu, or the game
## closed), writes nothing of that day: it marks the opening interrupted. A day DayCycle (D-0203) closes is saved
## as soon as its SUMMARY applies, and again if the world closes during the summary, as the next
## day's opening (save_closed_day(), D-0236): a game killed mid-day comes back at its last close.
##
## The day (D-0203): the root gives every peer a GameClock and a DayCycle child, both attached to
## CompanyNet before the snapshot goes out. The host opens the company's day once the world is up;
## the phases and the clock then run by themselves (DayCycle, polled by the host's BusinessTick,
## D-0232). DayCycle.crew_in_shed is _crew_in_shed() (D-0316.1): the shed's minute stands still (S4)
## while none of the crew stands in it (CompanyShed.holds(): the floor, the gates in the walls'
## line included), never before anybody is spawned. Only the host's poll reads it; the freeze
## reaches every peer as the day_phase event it already was.
##
## Steam (D-2009): what the company shows, CompanyLobbyMeta's lobby data (host) and rich presence,
## goes to NetworkManager's steam_presence (NetSteamPresence) when the world comes up, on every
## day_phase event and on a client's snapshot, and is cleared when the world closes. Without Steam
## it is only kept there.
##
## Bandwidth (D-2002.3): every player here joins the crew through join_crew(), which has it send
## its pose at CompanyTuning.SHED_POSE_RATE_HZ on foot instead of the game's 30, so a full crew
## fits the shed's 24 KB/s a client (test_company_bandwidth_budget).
##
## The crew split between the shed and the street (D-0316): the "Interest" child (CompanyInterest,
## every peer) sends each company vehicle and loose box only to the players near it (the host still
## simulates all of them), and the cells load around every player and vehicle on the host but only
## around its own player on a client (CompanyInterest.cell_anchors()); a seated player counts at its
## seat, Player.reach_origin() (CompanyInterest.anchor_point()). Every peer's player is a node
## of the crew here (the host's spawns, _add_crew()), so the host has an anchor for each one and
## knows who is in the shed and who is out on the street (_crew_in_shed(), D-0316.1).
##
## Trips (D-0302, D-0302.2.a): the host's "CompanyTrips" child watches the playon's gate (its far edge) and decides
## when a trip starts or closes; the "TripsView" child (CompanyTripsView, every peer) is how every peer, the host
## too, knows which vehicles are out (CompanyNet events and the snapshot). A client has no CompanyTrips; its
## "GateBrake" (D-0316.4) brakes its copy at the gate. The host's "Tow" (CompanyTow, D-0307.1) takes a stuck van home.
##
## A taped box becomes a DeliveryPackage on every peer, under World/Packages (D-0715.b, CompanyNet's
## table.packages); the host's are tracked by the cells, so one left where no cell is loaded freezes
## instead of falling through the missing floor (D-0318.1).

## The CompanyState autoload's script (no class_name: a --script compiles before the autoloads exist).
const COMPANY_STATE := preload("res://scripts/core/company/company_state.gd")
const PLAYER_SCENE: String = "res://scenes/gameplay/player/player.tscn"
const Ride = preload("res://scripts/gameplay/player/player_ride.gd")
## Where a client goes when its host is gone (as hud_pause.leave_to_menu()). Temporary here: once the
## company HUD exists, the host-gone screen and the way to the menu move there, as N-222's in hud_pause.gd.
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
## Where a close's save puts the units players held (D-2005, D-0236): a loaded day opens with empty hands. The
## shed has no fixed spot for them yet (no station gives a location), so they lie in floor
## bundle 0, a floor:<n> location of red-autoridad.md section 2 (row 7). D-2006 / D-0611 will
## refine where they go (where each player stood).
const SAVED_HANDS_LOCATION: StringName = &"floor:0"
## The starting shed (stage 0 of WarehouseStages, 12 x 8 cells of 1 m), in meters: centered on the
## origin, inside the industrial park. A bigger stage draws a bigger floor (CompanyShed).
const SHED_SIZE: Vector2 = Vector2(12.0, 8.0)
## Where the player appears: on the dock floor, facing the shed (north, -Z). The first of the
## roster (the host, solo too) stands right here; the rest side by side (crew_spawn()).
const SPAWN: Vector3 = Vector3(0.0, 1.0, 2.6)
## Meters between two crew members spawned side by side along X: a player's capsule is narrower,
## so nobody lands on anybody, and a crew of 8 spans 6.4 m of the starting shed's 12.
const CREW_SPACING: float = 0.8
## A spawn spot is taken while a crew member stands closer than this share of CREW_SPACING to it.
const SPAWN_CLEARANCE: float = 0.9
## Spawn spots tried before giving up and using the last (8 players fill the first 8).
const MAX_SPAWN_SLOTS: int = 16
## The group of every player here: this is the company, there is no vehicle to practise for
## (the delivery practice card, player_cargo_care.gd, checks it).
const CREW_GROUP: StringName = &"company_crew"
## Every player node is named this and its peer id (player.gd takes its authority from it).
const PLAYER_PREFIX: String = "Player_"
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

## The slot the next company world takes as its save_slot, once (the menu's --slot=<n>, with
## --autostart-company or --host-company); "" leaves save_slot as it is.
static var launch_slot: String = ""

var zones: Array[ZoneDefinition] = []
## This peer's own player: on the host (solo too) from the moment the world is up; on a client once
## the host's spawn of it arrives (null until then).
var player: Node3D
## The shed the players walk in, drawn from the company's layout and stock.
var shed: CompanyShed
## Build mode of the shed (D-0917): keyboard, mouse and gamepad; only asks, the host decides.
var builder: ShedBuilder
## The stock list, the clipboard's Stock sheet (D-0612.b, CompanyClipboard D-1902): every peer, read only.
var stock_board: StockBoard
## The supplier's truck NPC (D-0601): drawn from the calendar and the game clock on every peer.
var supplier_truck: SupplierTruckView
## The supplier calendar the truck follows, on every peer: CompanyNet's (net.supplier.schedule), fed by the
## orders of the supplier board (D-0603.b.2, CompanySupplierLink).
var supplier_schedule: SupplierSchedule = SupplierSchedule.new()
var supplier_board: SupplierBoard
## Requests and events of the company's business (D-2003, CompanyNet).
var net: CompanyNet
## The day's clock and phases (D-0219, D-0203), children of this root on every peer.
var clock: GameClock
var day_cycle: DayCycle
## The closing screen of the day (D-0508.3): every peer shows what the host closed, only the host's
## "continue" moves the day on.
var summary_panel: DaySummaryPanel
## The company's shop over the closing screen (D-0511.2): its Shop button opens it, the host buys.
var shop_screen: CompanyShopScreen
## Host only (null on a client): the host's rules at a fixed rate (D-0232).
var business_tick: BusinessTick
## Host: the playon's gate and the trips out (D-0302.1). Null on a client.
var trips: CompanyTrips
## The company vehicles out as every peer sees them (D-0302.2.a): on the host it publishes what
## `trips` decides, on every peer it follows CompanyNet's trip events and the snapshot.
var trips_view: CompanyTripsView
## Client: brakes the copy it drives at the gate while the host holds it (D-0316.4). Null on the host.
var gate_brake: CompanyGateBrake
var fleet: CompanyFleet
## The map's streamed cells (D-0313): loaded in slices around the crew and the company's vehicles,
## so leaving the shed never loads the world again (the loading screen shows once, on entering).
var cells: CompanyCells
## Who gets each company vehicle's and loose box's updates (D-0316), on every peer.
var interest: CompanyInterest
## World/Packages: where every peer puts the package a sealed box becomes (D-0715.b).
var packages: Node3D
## Host: the slot and folder the company is loaded from when the world comes up without one,
## and whose opening a cut day marks interrupted (save_interrupted_day()). A test points them at a folder
## of its own before adding the root.
var save_slot: String = CompanySave.DEFAULT_SLOT
var save_dir: String = CompanySave.SAVE_DIR
## The arguments CompanyDevFlags reads on the host when the world comes up (--company-day=, --district=,
## --money=, D-0238): the command line's, unless a test hands its own before adding the root.
var dev_args: PackedStringArray = OS.get_cmdline_user_args()
## Host: the crew the day's orders are planned for; 0, the session's (the day bot's --players sets it).
var order_crew: int = 0
## The session and the CompanyState this world plays with. Unset, the NetworkManager and the
## CompanyState autoloads, found by path when the world comes up (N-919). Two peers in one process
## (a test) hand each root its own before adding it, as they do save_dir.
var session: NetSession
var company_state: COMPANY_STATE

var _world: Node3D
## Every peer: where the host's spawns of the crew land (World/PlayerSpawner, as in the delivery).
var _spawner: MultiplayerSpawner
## Decided when the world comes up: this peer is the host (solo too) and spawns the crew. A client
## whose session ended later stays a client here: it spawns nothing while the menu loads.
var _spawns_crew: bool = false
## Client: the CompanyState node the host's snapshot writes into, and what it held before (its
## to_dict(), or {} when no company was on), put back on leaving (_exit_tree()).
var _mirrored_state: COMPANY_STATE
var _own_company: Dictionary = {}
## The slot each crew member last picked from, by "<peer>/<shelf uid>" (ShelfPicking, D-0609).
var _pick_after: Dictionary = {}
## Host (solo too): the CompanyState node it runs, saved when the world closes mid-day. Decided
## when the world comes up: a client whose session ended counts as a host to CompanyNet then.
var _hosted_state: COMPANY_STATE
## Client: a snapshot put the host's company in its mirror (there is a day to sum up).
var _saw_host_day: bool = false
## Client: the host is gone and the menu is on its way; nothing here runs any more.
var _host_gone: bool = false
## What was last handed to Steam (_publish_presence()): [lobby data, rich presence].
var _presence_shown: Array = []
## The supplier's truck, board and pallets (CompanySupplierLink); the host's poll of the pallets runs in _process().
var _supplier: CompanySupplierLink


func _ready() -> void:
	if not launch_slot.is_empty():
		save_slot = launch_slot
		launch_slot = ""
	if company_state == null:
		company_state = get_node_or_null(^"/root/CompanyState") as COMPANY_STATE
	_start_company(company_state)
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_add_environment()
	zones = load_zones()
	for zone: ZoneDefinition in zones:
		_add_zone_slab(zone)
	CompanyGround.add_backup(_world, zones)
	_add_shed()
	ColdChainTick.add_to(self, net, day_cycle, shed, business_tick)
	_add_supplier_truck()
	_add_cells()
	_add_packages()
	_add_interest()
	_add_trips()
	fleet = CompanyFleet.add_to(_world, net, session, shed)
	if trips != null:
		fleet.vehicle_recovered.connect(trips.forget)
		CompanyTow.add_to(self, trips, fleet, net)
	CompanyGpsLink.add_to(_world, fleet, trips_view, net)
	_add_crew()
	_add_builder()
	_add_stock_board()
	CompanyDispatch.add_to(self)
	CompanyOnboardingTracker.add_to(self)
	_add_summary_panel()
	_publish_presence()
	_open_company_day.call_deferred()
	_report_level_ready.call_deferred()


## Every zone in data/zones/, in a stable order. A new .tres joins without code.
static func load_zones() -> Array[ZoneDefinition]:
	return CompanyCatalog.load_all().zones()


## Same name on every peer, so its RPCs reach the same node. The host (solo
## counts), with no company on, loads its slot (a new company only when there is
## none to load) and hands CompanyNet its stock (CompanyState.stock(): a copy the
## events keep up to date), the saved day's return bundle laid on the shed's floor
## (ReturnBundle.place(), D-0252: the snapshot takes it to the clients). A client
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
		# The slot first: a new company here would erase it with its opening save below. CORRUPT
		# already starts a new company (the bad file is kept as
		# .bad); MISSING and TOO_NEW leave it off. A newer build's file is never overwritten
		# (CompanySave.save()), so a new company played over one is not saved.
		CompanySave.load_into(state, save_slot, save_dir)
		if not state.is_active():
			state.new_company()
	# A new company (or a save from before the default existed) starts with the furnished shed:
	# pieces and units, free and the same on every run. It goes in the state before CompanyNet
	# copies the stock, and reaches the clients with the snapshot (D-2004). The development flags
	# (D-0238) go in last, so the snapshot carries them too.
	if DefaultShed.needs_default(state):
		var report: Dictionary = DefaultShed.load_default().apply_to(state)
		for refusal: Dictionary in report["refused"]:
			push_warning("CompanyRoot: the default shed left out %s (%s)" % [refusal["uid"], refusal["reason"]])
	# The slot always holds an opening (D-0251): one without a save gets this day's, before the dev
	# flags (they never reach the disk). A newer build's file counts as a save: never written over.
	if not CompanySave.exists(save_slot, save_dir):
		if not CompanySave.save(state, save_slot, save_dir):
			push_warning("CompanyRoot: opening of day %d not saved to %s" % [state.day, save_dir])
	CompanyDevFlags.apply(state, dev_args, load_zones())
	net.inventory = state.stock()
	ReturnBundle.place(net.floor_bundles, net.inventory, SAVED_HANDS_LOCATION, state.layout, state.warehouse_stage)
	net.pallets.load_save(state.pallets)
	_hosted_state = state


## The day's clock and phases, hooked to CompanyNet on every peer in the frame it is added: the
## snapshot to the peers already up goes out deferred, after this. The cycle asks the world for the
## opening notice and for who is in the shed.
func _add_day(state: COMPANY_STATE) -> void:
	clock = GameClock.new()
	clock.name = "GameClock"
	add_child(clock)
	clock.attach(net, state)
	day_cycle = DayCycle.new()
	day_cycle.name = "DayCycle"
	add_child(day_cycle)
	day_cycle.attach(net, clock, state)
	day_cycle.opening_notice = _opening_notice
	day_cycle.crew_in_shed = _crew_in_shed
	add_child(CompanySoloPause.create(clock, day_cycle))
	_add_business_tick()


## Host (solo too): the business tick (D-0232) runs the host's rules at CompanyTuning.BUSINESS_TICK_HZ,
## DayCycle.poll first, then the day's orders (D-0813.1); the cycle's own poll in _process goes off on
## every peer (a client's poll does nothing anyway).
func _add_business_tick() -> void:
	day_cycle.set_process(false)
	if not net.is_host():
		return
	business_tick = BusinessTick.new()
	business_tick.name = "BusinessTick"
	add_child(business_tick)
	business_tick.add_step(&"day_cycle", day_cycle.poll)
	business_tick.add_step(&"orders", func() -> void: CompanyDayOrders.poll(net, day_cycle))


## Host (solo too): the company's day opens, after the snapshot to the peers already up. A client
## waits for the host's events.
func _open_company_day() -> void:
	if not is_inside_tree() or _host_gone or not net.is_host() or _hosted_state == null:
		return
	day_cycle.open_day(_hosted_state.day)


## The closing screen (D-0508.2), opened by SUMMARY on every peer; EventBus by path (N-919, --script tests).
func _add_summary_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DaySummaryLayer"
	add_child(layer)
	summary_panel = DaySummaryPanel.new()
	summary_panel.name = "DaySummaryPanel"
	layer.add_child(summary_panel)
	summary_panel.continued.connect(_on_summary_continued)
	shop_screen = CompanyShopScreen.attach(self, net, summary_panel)
	var bus: Node = _event_bus()
	if bus != null:
		bus.connect(&"company_day_summary", _on_day_summary)
		bus.connect(&"company_day_started", _on_day_started)


## The EventBus autoload by path (the single lookup of this script; N-919).
func _event_bus() -> Node:
	return get_node_or_null(^"/root/EventBus")


func _on_day_summary(day: int, summary: Dictionary) -> void:
	if summary_panel != null and not _host_gone:
		summary_panel.open(summary, net.pallets.note.discrepancies(day) if net != null else [],
			net.supplier.auto_units(day) if net != null else 0)


## The next day opened (the host pressed continue): every copy of the closing screen goes away.
func _on_day_started(_day: int) -> void:
	if summary_panel != null and summary_panel.visible:
		summary_panel.hide()


## "Continue" on the closing screen: the host opens the next day; a client only closes its copy and
## waits for the host's OPENING event.
func _on_summary_continued() -> void:
	if day_cycle != null and net != null and net.is_host():
		day_cycle.next_day()


## The business side of the world, before the world itself: CompanyNet (_add_net()) and, on a
## client, the watch for its host going away, on two signals: this root's multiplayer
## server_disconnected (the host left or dropped) and NetworkManager's session_failed, by path
## (a handshake that times out or is refused ends the session with no server_disconnected).
## Whichever comes first does it and the other finds _host_gone set; _on_host_lost() only reads
## this peer's mirror and changes scene, so it doesn't matter whether the session already ended.
func _start_company(state: COMPANY_STATE) -> void:
	if session == null:
		session = get_node_or_null(^"/root/NetworkManager") as NetSession
	_add_net(state)
	net.event_applied.connect(_on_event_applied)
	if net.is_host():
		return
	net.company_state_restored.connect(_on_host_day_restored)
	if not multiplayer.server_disconnected.is_connected(_on_host_lost):
		multiplayer.server_disconnected.connect(_on_host_lost)
	if session != null and not session.session_failed.is_connected(_on_session_failed):
		session.session_failed.connect(_on_session_failed)


## Host (solo too): the day cut short (D-0251). Nothing of it is written: the slot's opening is only
## marked interrupted (CompanySave.mark_interrupted()), so loading it plays the day again. False on
## a client, without a company on or a save in the slot, over a newer build's save or on a write error.
func save_interrupted_day() -> bool:
	if _hosted_state == null or not is_instance_valid(_hosted_state):
		return false
	if not _hosted_state.is_active():
		return false
	var marked: bool = CompanySave.mark_interrupted(save_slot, save_dir)
	if not marked:
		push_warning("CompanyRoot: interrupted day %d not marked in %s" % [_hosted_state.day, save_dir])
	return marked


## Host (solo too), with the day closed (DayCycle in SUMMARY): the company saved as the next day's
## opening (D-0236), day + 1 at DAY_START_MIN, not interrupted, with the live stock as a save keeps
## it (stock_for_save()). Loading it opens that day, as next_day() would. The company itself keeps
## its day: only the saved copy moves on. False on a client, without a company on, outside SUMMARY,
## over a newer build's save or when the file could not be written.
func save_closed_day() -> bool:
	if _hosted_state == null or not is_instance_valid(_hosted_state) or not _hosted_state.is_active():
		return false
	if day_cycle == null or not is_instance_valid(day_cycle):
		return false
	if day_cycle.phase() != DayCycle.Phase.SUMMARY:
		return false
	if net != null and is_instance_valid(net) and net.inventory != null:
		_hosted_state.store_stock(stock_for_save(net.inventory))
		_hosted_state.pallets = net.pallets.to_save()
		ColdChainTick.write_clocks(self, _hosted_state)
	var next_opening := COMPANY_STATE.new()
	next_opening.from_dict(_hosted_state.to_dict())
	next_opening.day = _hosted_state.day + 1
	next_opening.clock_minutes = CompanyTuning.DAY_START_MIN
	var saved: bool = CompanySave.save(next_opening, save_slot, save_dir)
	next_opening.free()
	if not saved:
		push_warning("CompanyRoot: the closed day %d could not be saved to %s"
			% [_hosted_state.day, CompanySave.path_for(save_slot, save_dir)])
	return saved


## A copy of `stock` as a save keeps it (D-2005, D-0252: ReturnBundle.for_save()): what lay in hands, on the
## floor, in open boxes and in packages lies in SAVED_HANDS_LOCATION, the total of each product kept and
## nothing reserved. `stock` itself (CompanyNet's live one) is not touched.
static func stock_for_save(stock: Inventory) -> Inventory:
	return ReturnBundle.for_save(stock, SAVED_HANDS_LOCATION)


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


## The host's world closing mid-day marks the day interrupted (D-2005); in the summary it saves the
## next day's opening. Either way its company is then loaded from the slot (D-0251). A client leaves the
## host's company behind: its CompanyState goes back to what it had before the snapshot
## (switched off when it had none), so solo play or a save never takes the host's.
func _exit_tree() -> void:
	var bus: Node = _event_bus()
	if bus != null and bus.is_connected(&"company_day_summary", _on_day_summary):
		bus.disconnect(&"company_day_summary", _on_day_summary)
	if bus != null and bus.is_connected(&"company_day_started", _on_day_started):
		bus.disconnect(&"company_day_started", _on_day_started)
	if _hosted_state != null:
		if save_closed_day() or save_interrupted_day():
			CompanySave.load_into(_hosted_state, save_slot, save_dir)
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


## A new day (or phase): Steam shows it (D-2009); the shed follows units and layout itself (CompanyShed.follow()).
## Host: SUMMARY or a shop_bought saves the closed day (D-0236, N-989); OPENING plans orders (D-0813.1).
func _on_event_applied(_seq: int, kind: StringName, data: Dictionary) -> void:
	var phase: Variant = data.get("phase") if kind == CompanyNet.DAY_PHASE else null
	if net.is_host() and (phase == DayCycle.PHASE_NAMES[DayCycle.Phase.SUMMARY] or kind == CompanyShopNet.BOUGHT):
		save_closed_day()
	if kind == CompanyNet.DAY_PHASE:
		if net.is_host() and data.get("phase") == DayCycle.PHASE_NAMES[DayCycle.Phase.OPENING]:
			CompanyDayOrders.plan(net, _hosted_state, day_cycle.current_day(),
				order_crew if order_crew > 0 else _crew_ids().size())
		_publish_presence()
	elif kind == CompanyOrdersNet.ADDED:
		var bus: Node = _event_bus()
		if bus != null:
			bus.emit_signal(&"order_added", StringName((data["order"] as Dictionary)["id"]))
	elif kind == CompanyColdNet.SPOILED:
		SpoilNotice.announce(_event_bus(), data)


## What the day's opening tells this peer (DayCycle.opening_notice, sent as EventBus.depot_notice):
## a company in the red is told why fewer orders come in (Bankruptcy.opening_text, D-0510.2). The
## money is the host's, replicated, so every peer reads the same.
func _opening_notice() -> String:
	return Bankruptcy.opening_text(_shown_company())


## Host (DayCycle.crew_in_shed, S4): someone of this world's crew is in the shed (CompanyShed.holds()),
## so the shed's minute runs. A player is where its reach starts (Player.reach_origin(), as
## CompanyNet's rule 4): its seat while seated, since the body stays where it sat down and only its
## visual rides along, and on the host a remote one's newest pose. Only the players of this root's
## multiplayer count, as in CompanyInterest; one whose peer left is out of the tree, or on its way
## out, and doesn't. With no shed, or nobody spawned yet (the world just up), it is yes: nothing
## freezes before there is someone to leave. Read when called, so it doesn't matter that the shed and
## the crew are added after the day.
func _crew_in_shed() -> bool:
	if not is_inside_tree() or shed == null or not is_instance_valid(shed) or not shed.is_inside_tree():
		return true
	var anyone: bool = false
	for node: Node in get_tree().get_nodes_in_group(CREW_GROUP):
		var member := node as Node3D
		if member == null or not member.is_inside_tree() or member.is_queued_for_deletion():
			continue
		if member.multiplayer != multiplayer:
			continue
		var at: Vector3 = (member as Player).reach_origin() if member is Player else member.global_position
		if shed.holds(at):
			return true
		anyone = true
	return not anyone


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
	if session == null or not is_instance_valid(session):
		return
	var company: COMPANY_STATE = _shown_company()
	var shown: Array = [CompanyLobbyMeta.lobby_meta(company), CompanyLobbyMeta.rich_presence(company)]
	if shown == _presence_shown:
		return
	var as_host: bool = company == null or (net != null and is_instance_valid(net) and net.is_host())
	CompanyLobbyMeta.publish(session.steam_presence, company, as_host)
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
		net.stations = shed.station_for
		shed.piece_used.connect(_on_piece_used)
		shed.cart_used.connect(PickingCartGrip.attach(self, net, shed).on_cart_used)
		shed.jack_used.connect(_on_jack_used)


## Host: a crew member used a piece of the shed. A shelf puts the units of one of its slots in their
## hands (D-0609): the slot rotates over the filled ones while the hands are empty (_pick_after), and
## the host's own checks (reach, hands, stock) decide in CompanyNet, same as for any units request.
func _on_piece_used(uid: StringName, role: StringName, peer_id: int) -> void:
	if role != &"storage" or net == null or not net.is_host():
		return
	var key: String = "%d/%s" % [peer_id, uid]
	var plan: Dictionary = ShelfPicking.plan(uid, shed.shelves.get(uid) as Shelf, net.inventory,
		CompanyNet.hands_location(peer_id), int(_pick_after.get(key, -1)))
	if plan.has("reason"):
		return
	var hands: StringName = CompanyNet.hands_location(peer_id)
	var before: int = net.inventory.count(plan["product"], hands)
	net.request_for(peer_id, &"units_take",
		{"station": plan["station"], "product": plan["product"], "qty": plan["qty"]})
	if net.inventory.count(plan["product"], hands) > before:
		_pick_after[key] = plan["slot"]


## Host: a crew member worked the pallet jack (D-0605.b): pick a pallet up or put it down, or push the jack.
## PalletJackUse asks the host's own CompanyNet on their behalf, which checks reach, the truck and the floor.
func _on_jack_used(action: StringName, peer_id: int, from: Vector3) -> void:
	if net == null or not net.is_host():
		return
	PalletJackUse.use(net, shed.yard, action, peer_id, from)


## The supplier's side (truck, order board, pallets on the bed) is CompanySupplierLink's (N-985).
func _add_supplier_truck() -> void:
	_supplier = CompanySupplierLink.attach(self, _world, net, supplier_schedule, shed,
		func() -> GameClock: return clock, func() -> Node: return player,
		func() -> bool: return builder != null and builder.is_building(),
		func() -> COMPANY_STATE: return _hosted_state)
	supplier_truck = _supplier.truck
	supplier_board = _supplier.board


## The shed from the company as this peer holds it: on the host what it started with; on a client
## the host's, once the snapshot is in (until then, bare).
func _redraw_shed() -> void:
	if shed != null and net != null and net.company != null:
		shed.rebuild(net.company, net.inventory)


## The streamed cells of the map, on every peer: `anchors` follow, on the host, every player (the crew
## group) and every company vehicle (CompanyTrips' group); on a client only its own player (D-0316).
## Refreshed each frame by `_process`.
func _add_cells() -> void:
	cells = CompanyCells.new()
	cells.name = "WorldCells"
	add_child(cells)
	# Streets (D-0304.1) and Centro's decor (D-0314) load with the cells; events off (D-0315.b).
	cells.use_graph(RoadGraph.load_default(), CompanyCells.seed_of(session), false, CompanyCells.shed_ground(shed))


## The packages the sealed boxes become (D-0715.b), under World/Packages on every peer (CompanyPackages
## builds them), so each synchronizer pairs up with the host's; see _on_package_added().
func _add_packages() -> void:
	if net == null:
		return
	packages = Node3D.new()
	packages.name = "Packages"
	_world.add_child(packages)
	net.table.packages.parent = packages
	net.table.packages.added.connect(_on_package_added)


## Every peer: a loose box of the interest, let go before consume() broadcasts (D-0316.3). Host: frozen
## while its cell isn't loaded (cells.track_body, D-0318.1). No CompanyNet request here (box_sealed).
func _on_package_added(package: DeliveryPackage) -> void:
	if interest != null and is_instance_valid(interest):
		interest.add_loose_box(package, package.consuming)
	if cells == null or not is_instance_valid(cells) or net == null or not net.is_host():
		return
	cells.track_body(package)
	package.tree_exiting.connect(cells.untrack_body.bind(package), CONNECT_ONE_SHOT)


func _add_interest() -> void:
	interest = CompanyInterest.new()
	interest.name = "Interest"
	interest.crew_group = CREW_GROUP
	add_child(interest)


func _process(_delta: float) -> void:
	if _supplier != null:
		_supplier.poll_pallets(clock)
	if cells == null:
		return
	var as_host: bool = net == null or net.is_host()
	cells.anchors = CompanyInterest.cell_anchors(self, CREW_GROUP, CompanyTrips.VEHICLE_GROUP, as_host)


## Every peer: the view of the trips out (CompanyTripsView, attached to CompanyNet in the frame the
## world comes up, like the day's clock, so its snapshot part goes in the first snapshot). Host: the
## gate across the playon's far edge (CompanyFleet.gate_of(): the yard outside the shed's north exit, where the
## vehicles park, so nothing is out until one is driven across it) and the trips that cross it, which the view
## publishes; the day waits for a trip still out (DayCycle.trips_out: CompanyTrips, the authority, on
## the host; the view on a client, where the cycle never polls).
func _add_trips() -> void:
	if net == null:
		return
	trips_view = CompanyTripsView.new()
	trips_view.name = "TripsView"
	add_child(trips_view)
	trips_view.attach(net)
	if not net.is_host():
		day_cycle.trips_out = trips_view.trips_out
		gate_brake = CompanyGateBrake.add_to(self, trips_view, shed, net)
		return
	trips = CompanyTrips.new()
	trips.name = "CompanyTrips"
	add_child(trips)
	trips.use_gate(CompanyFleet.trip_gate(shed, net.company))
	trips.minute_now = func() -> int: return floori(clock.minute_now()) if clock != null else 0
	trips_view.follow(trips)
	day_cycle.trips_out = trips.trips_out


func _add_builder() -> void:
	if net == null or shed == null:
		return
	builder = ShedBuilder.new()
	builder.name = "ShedBuilder"
	add_child(builder)
	builder.setup(shed, net, player)
	builder.busy = func() -> bool: return supplier_board != null and supplier_board.is_open()


## The stock list (D-0612.b, StockBoard.for_company()) as a sheet of the clipboard (D-1902): every peer.
func _add_stock_board() -> void:
	if net == null:
		return
	stock_board = StockBoard.for_company(net, supplier_schedule, func() -> Node: return player,
		func() -> bool: return builder != null and builder.is_building())
	CompanyClipboard.attach(self, stock_board)


## The crew's spawner, on every peer at the same path so the host's spawns land on each client,
## and the session's news of peers coming and going. The host (solo too) spawns its own player
## now and the others' as their worlds come up (_sync_crew()); a client takes its own when it
## arrives (_on_crew_spawned()).
func _add_crew() -> void:
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "PlayerSpawner"
	_spawner.spawn_path = NodePath("..")
	_spawner.spawn_function = _create_crew_member
	_world.add_child(_spawner)
	_spawner.spawned.connect(_on_crew_spawned)
	_spawns_crew = net != null and net.is_host()
	if session != null and not session.peer_level_ready.is_connected(_on_crew_changed):
		session.peer_level_ready.connect(_on_crew_changed)
		session.roster_changed.connect(_on_crew_changed)
	_sync_crew()


## Every peer, from the host's spawn data {peer_id, position}: a player driven by that peer, one
## of the crew before it enters the tree (join_crew()). A position that isn't a finite Vector3
## falls back to SPAWN.
func _create_crew_member(data: Variant) -> Node:
	var spawn: Dictionary = data if data is Dictionary else {}
	var id: int = int(spawn.get("peer_id", 0)) if typeof(spawn.get("peer_id")) == TYPE_INT else 0
	var at: Variant = spawn.get("position")
	var member := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	member.name = _player_name(id)
	member.position = at if at is Vector3 and RpcGuard.finite_vec3(at) else SPAWN
	if id > 0:
		member.set_multiplayer_authority(id)
	join_crew(member)
	return member


## The `slot`-th spawn spot: the first at SPAWN, the rest CREW_SPACING apart to either side in
## turn (+X, -X, then twice as far...).
static func crew_spawn(slot: int) -> Vector3:
	var step: int = (maxi(slot, 0) + 1) / 2
	var side: float = 1.0 if slot % 2 == 1 else -1.0
	return SPAWN + Vector3(CREW_SPACING * float(step) * side, 0.0, 0.0)


## The first spawn spot (crew_spawn(0), 1, 2...) with nobody of `taken` (where the crew stands, in
## the world's space) closer than SPAWN_CLEARANCE across the floor: a newcomer never lands on
## someone, whoever left before it. The last spot tried when every one is taken.
static func free_spawn(taken: Array[Vector3]) -> Vector3:
	var spot: Vector3 = SPAWN
	for slot: int in range(MAX_SPAWN_SLOTS):
		spot = crew_spawn(slot)
		var clear: bool = true
		for at: Vector3 in taken:
			if Vector2(at.x - spot.x, at.z - spot.z).length() < CREW_SPACING * SPAWN_CLEARANCE:
				clear = false
				break
		if clear:
			return spot
	return spot


## Host (solo too): a player for every peer on the roster whose world is up, in roster order, at
## the first spawn spot nobody stands on (free_spawn()); a player whose peer left the roster goes
## first, so its spot is free again. It goes after CompanyNet let go of what it held: the session
## tells peer_removed (CompanyNet drops the units at the player's feet, D-2006) before
## roster_changed, and the node is only freed at the end of the frame.
func _sync_crew() -> void:
	if not _spawns_crew or _host_gone or not is_inside_tree() or _spawner == null:
		return
	var ids: Array[int] = _crew_ids()
	for child: Node in _world.get_children():
		var child_name: String = String(child.name)
		if child_name.begins_with(PLAYER_PREFIX) and not ids.has(int(child_name.trim_prefix(PLAYER_PREFIX))):
			child.queue_free()
	for id: int in ids:
		if _world.has_node(NodePath(_player_name(id))):
			continue
		if session != null and not session.is_peer_ready(id):
			continue
		_spawner.spawn({"peer_id": id, "position": free_spawn(_crew_spots())})
	_refresh_local_player()


## Where each player of this world stands, in the world's space; those on their way out left out.
func _crew_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for child: Node in _world.get_children():
		var member := child as Player
		if member != null and member.is_in_group(CREW_GROUP) and not member.is_queued_for_deletion():
			spots.append(_world.to_local(member.global_position))
	return spots


## The session's roster online, else (solo, a host's room closed) this peer alone.
func _crew_ids() -> Array[int]:
	var ids: Array[int] = []
	if session != null and is_instance_valid(session) and session.is_online():
		ids.assign(session.peer_ids)
	else:
		ids.append(multiplayer.get_unique_id())
	return ids


## A peer's world is up (peer_level_ready: its id) or the roster changed (roster_changed: the ids).
func _on_crew_changed(_why: Variant) -> void:
	_sync_crew()


## A client: a spawn from the host landed; its own player is the one it drives.
func _on_crew_spawned(_member: Node) -> void:
	_refresh_local_player()


## `player` is this peer's own, wherever it came from; the build mode keeps it still while it
## builds (ShedBuilder.player). Both let go of it as it leaves the tree (_on_local_player_leaving()).
func _refresh_local_player() -> void:
	var own: Node3D = _world.get_node_or_null(NodePath(_player_name(multiplayer.get_unique_id()))) as Node3D
	if own != null and own.is_queued_for_deletion():
		own = null
	if own == player:
		return
	player = own
	if player != null:
		player.tree_exiting.connect(_on_local_player_leaving.bind(player), CONNECT_ONE_SHOT)
	if builder != null:
		builder.player = player


## This peer's own player leaves the tree: the host despawned it, the session that spawned it ended
## or the world closes. Neither `player` nor the build mode keeps pointing at a node about to be
## freed. Not the spawner's despawned: that fires while the node is still in place.
func _on_local_player_leaving(leaving: Node3D) -> void:
	if player != leaving:
		return
	player = null
	if builder != null and is_instance_valid(builder):
		builder.player = null


## This peer's world is up (everything here is built in _ready(): the shed's floor, the slabs):
## the session hears it, as level_common.gd's _report_level_ready(). On a client that is what
## has the host spawn its player and send CompanyNet's snapshot; on the host it records the scene.
func _report_level_ready() -> void:
	if not is_inside_tree() or _host_gone or session == null or not is_instance_valid(session):
		return
	session.level_ready()


static func _player_name(id: int) -> String:
	return PLAYER_PREFIX + str(id)


## Every player of the company's world, before it enters the tree: one of the crew (CREW_GROUP),
## sending its pose at the shed's rate while on foot (D-2002.3, CompanyTuning.SHED_POSE_RATE_HZ),
## at SEATED_POSE_RATE_HZ seated (D-2002.4) and at the game's in its bay. Only the owner's copy sends.
static func join_crew(crew_member: Player) -> void:
	crew_member.add_to_group(CREW_GROUP)
	Ride.set_on_foot_pose_rate(crew_member, CompanyTuning.SHED_POSE_RATE_HZ)
	Ride.set_seated_pose_rate(crew_member, CompanyTuning.SEATED_POSE_RATE_HZ)

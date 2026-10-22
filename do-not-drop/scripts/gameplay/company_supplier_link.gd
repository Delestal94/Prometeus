class_name CompanySupplierLink
extends RefCounted
## The supplier side of the company's world, wired out of CompanyRoot (N-985): the supplier's truck beside the
## shed (D-0601), the order board (D-0603.b.2) and the truck's pallets on the bed (D-0605.b, D-0618.b).
##
## attach() builds everything on every peer in the frame the world comes up, as CompanyRoot did before; the
## root keeps `truck`, `board` and `schedule` as its own `supplier_truck`, `supplier_board` and
## `supplier_schedule`. The only state here is the host's pallet bookkeeping (poll_pallets()). Nothing here
## decides on its own: the host's checks live in CompanyNet.

## The CompanyState autoload's script (no class_name: a --script compiles before the autoloads exist).
const COMPANY_STATE := preload("res://scripts/core/company/company_state.gd")

## The supplier's truck NPC, drawn from the calendar and the game clock on every peer.
var truck: SupplierTruckView
## The shed's order screen (null without a CompanyNet).
var board: SupplierBoard

var _net: CompanyNet
var _schedule: SupplierSchedule
## Returns the host's CompanyState (null on a client or once the world closes): looked up when used, as the
## root lets go of it on leaving.
var _hosted_state: Callable
## Host: the day whose truck pallets are on the bed, and the (day, minute) last looked at.
var _pallets_day: int = 0
var _pallets_checked: Vector2i = Vector2i.ZERO


## Builds the board (when there is a CompanyNet) and the truck under `world`, and hooks them to `shed`.
## `schedule` is the calendar the truck follows; `clock_of` returns the root's GameClock (maybe null),
## `player_of` this peer's own player and `building` whether the build mode is on; the three are asked when used.
## `hosted_state` returns the host's CompanyState (see _hosted_state).
static func attach(root: Node, world: Node3D, net: CompanyNet, schedule: SupplierSchedule, shed: CompanyShed,
		clock_of: Callable, player_of: Callable, building: Callable, hosted_state: Callable) -> CompanySupplierLink:
	var link := CompanySupplierLink.new()
	link._net = net
	link._schedule = schedule
	link._hosted_state = hosted_state
	link._add_orders(root, shed, player_of, building)
	link._add_truck(world, shed, clock_of)
	return link


## The supplier orders, on every peer: the truck reads CompanyNet's calendar (the host checks an
## order, every peer applies it) and the shed's board opens the order screen on the peer that used it. The
## host's calendar comes from its save and goes back to it after every order (CompanySupplierNet.load_saved);
## the host also hooks the automatic order of the day's close (SupplierAutoOrderHook, D-0151.3b).
func _add_orders(root: Node, shed: CompanyShed, player_of: Callable, building: Callable) -> void:
	if _net == null:
		return
	_net.supplier.schedule = _schedule
	var defs: Dictionary = _net.supplier.load_catalog(CompanyCatalog.load_all())
	var hosted: COMPANY_STATE = _hosted_state.call()
	if _net.is_host() and hosted != null:
		hosted.supplier_calendar = CompanySupplierNet.load_saved(_schedule, hosted)
		_net.event_applied.connect(_on_ordered)
		SupplierAutoOrderHook.attach(root, _net)
	board = SupplierBoard.new()
	board.name = "SupplierBoard"
	root.add_child(board)
	board.setup(_net, _net.supplier.supplier, defs)
	board.player_of = player_of
	board.busy = building
	shed.supplier_board_opened.connect(func() -> void: board.open())


## Host: an order went into the calendar; the company keeps it for the save (CompanyState.supplier_calendar).
func _on_ordered(_seq: int, kind: StringName, _data: Dictionary) -> void:
	var hosted: COMPANY_STATE = _hosted_state.call()
	if kind == CompanySupplierNet.ORDERED and hosted != null and is_instance_valid(hosted):
		hosted.supplier_calendar = _schedule.to_dict()


## The supplier's truck beside the shed (D-0601). It reads the day and the minute from the same
## GameClock and CompanyState as every other peer, so there is nothing to send.
func _add_truck(world: Node3D, shed: CompanyShed, clock_of: Callable) -> void:
	truck = SupplierTruckView.new()
	truck.schedule = _schedule
	truck.origin = shed.position
	truck.company = _net.company if _net != null else null
	truck.minute_now = func() -> float:
		var clock: GameClock = clock_of.call()
		return clock.minute_now() if clock != null and is_instance_valid(clock) else float(CompanyTuning.DAY_START_MIN)
	world.add_child(truck)
	shed.truck = truck
	if _net != null:
		# The pallets on the bed are the book's (CompanyPallets), the same on every peer (D-0605.b).
		truck.pallets = _net.pallets.book
		_net.event_applied.connect(func(_seq: int, kind: StringName, _data: Dictionary) -> void:
			if CompanyPallets.EVENT_KINDS.has(kind):
				truck.refresh_bed())
		_net.company_state_restored.connect(func(_snapshot_seq: int) -> void: truck.refresh_bed())
		truck.refresh_bed()


## Host, once a game minute: the truck of the day is on its way in (SupplierTruckView draws it from
## SUPPLIER_DRIVE_IN_MIN before it parks) and its pallets are not on the bed yet: one jack_loaded puts them there
## (CompanyPallets.loaded_event), once per day; and when it drove off, jack_departed (D-0618.b, send_truck_off).
func poll_pallets(clock: GameClock) -> void:
	var hosted: COMPANY_STATE = _hosted_state.call()
	if _net == null or not _net.is_host() or hosted == null or clock == null or not is_instance_valid(clock):
		return
	var day: int = hosted.day
	var minute: int = floori(clock.minute_now())
	if _pallets_checked == Vector2i(day, minute):
		return
	_pallets_checked = Vector2i(day, minute)
	CompanyPallets.send_truck_off(_net.pallets, _schedule, day, minute, _net.publish)
	if _pallets_day == day or not CompanyPallets.load_due(_schedule, day, minute):
		return
	var event: Dictionary = _net.pallets.loaded_event(day, _schedule.pallets_for(day), _net.inventory)
	if event.is_empty() or _net.publish(CompanyPallets.LOADED, event):
		_pallets_day = day

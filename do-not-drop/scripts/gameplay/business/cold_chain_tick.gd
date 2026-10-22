class_name ColdChainTick
extends Node
## The cold chain in the company's world (expansion D-0616.b): the host's rule that makes cold products
## rot outside a fridge. Child of CompanyRoot on the host only (solo too); a client never has one: it
## sees the loss as the host's units_spoiled event (CompanyColdNet) and ends with the same stock.
##
## - Time: it runs as a step of the host's BusinessTick (4 Hz) but does its work once per game minute,
##   with the shed's own minute (DayCycle.shed_minute(), the GameClock's held back by the time the shed
##   spent frozen, S4). So milk doesn't rot while the clock is paused, while the shed is frozen (nobody of
##   the crew in it), nor outside the open day (OPENING and OPERATING, as the orders): between days the
##   minute starts again at 08:00 and the gap counts for nothing.
## - What rots: ColdChain.age() counts the minutes of every cold product outside a fridge (a shelf listed
##   by CompanyShed.cold_shelves(), read each time: a fridge bought mid-day counts) where units wait (not
##   in hands, boxes or packages); what reaches COLD_SPOIL_MINUTES is published, one units_spoiled per
##   product and place, and every peer discards it.
## - The clock travels with the units: after each units_moved the host applied (take, store, drop...) the
##   clock goes from the place they left to the one they reached (ColdChain.note_moved()). The moves of
##   the packing tables are not followed yet (D-0616.c): a box has ColdPack, and what comes out of one
##   starts its clock again.
## - The save: the clocks are the company's (CompanyState.cold_clocks, host only). The tick starts from
##   what the company holds and writes them back with write_clocks(), which CompanyRoot calls before it
##   saves.
##
## Cost: a compare per business tick, and once a game minute (about 1.5 real seconds) one pass over the
## cold products in stock. It frees with the root; nothing is created per frame.

## The BusinessTick step this registers.
const STEP: StringName = &"cold_chain"
## The node's name under the root, so write_clocks() finds it.
const NODE_NAME: String = "ColdChainTick"
## Game minutes that must pass before the clocks move: whole minutes keep the work to once a minute.
const MIN_STEP_MINUTES: float = 1.0

## The clocks of the places in this shed.
var chain := ColdChain.new()
var net: CompanyNet = null
## The catalog's products by id (ColdChain.age() looks for the cold ones).
var products: Dictionary = {}
## Callable() -> bool: the day is open (OPENING or OPERATING).
var is_open: Callable = Callable()
## Callable() -> float: the shed's minute, with its fraction.
var shed_minute: Callable = Callable()
## Callable() -> int: the company's day (a new one restarts the minute at 08:00).
var current_day: Callable = Callable()
## Callable() -> Dictionary: the fridges of the shed (shelf uid -> true).
var cold_shelves: Callable = Callable()

var _day: int = -1
var _last_minute: float = -1.0


## Host: a tick for `net`'s world under `parent`, a step of `business_tick`, reading the day from `cycle` and
## the fridges from `shed`, and starting from the clocks `net.company` saved. Null on a client or without a
## business tick.
static func add_to(
	parent: Node, net_in: CompanyNet, cycle: DayCycle, shed: CompanyShed, business_tick: BusinessTick
) -> ColdChainTick:
	if net_in == null or not net_in.is_host() or cycle == null or shed == null or business_tick == null:
		return null
	var tick := ColdChainTick.new()
	tick.name = NODE_NAME
	tick.net = net_in
	var catalog: CompanyCatalog = CompanyCatalog.load_all()
	for id: StringName in catalog.ids(CompanyCatalog.PRODUCTS):
		tick.products[id] = catalog.product(id)
	tick.is_open = func() -> bool:
		return cycle.phase() == DayCycle.Phase.OPENING or cycle.phase() == DayCycle.Phase.OPERATING
	tick.shed_minute = cycle.shed_minute
	tick.current_day = cycle.current_day
	tick.cold_shelves = shed.cold_shelves
	var saved: Variant = net_in.company.get(&"cold_clocks") if net_in.company != null else null
	tick.chain.from_dict(saved)
	parent.add_child(tick)
	business_tick.add_step(STEP, tick.poll)
	return tick


## Host (CompanyRoot, before a save): the live clocks into the company that is saved. Nothing without a tick.
static func write_clocks(parent: Node, company: Object) -> void:
	var tick := parent.get_node_or_null(NODE_NAME) as ColdChainTick
	if tick != null and company != null and is_instance_valid(company):
		company.set(&"cold_clocks", tick.chain.to_dict() if tick.chain.is_ticking() else {})


func _ready() -> void:
	if net != null:
		net.event_applied.connect(_on_event_applied)


## Host, on the business tick: the game minutes since the last time it worked, if at least a minute, age the
## clocks and publish what rotted. A closed day, a new day or a minute that went back only moves the mark
## (_last_minute is -1 while there is no mark).
func poll() -> void:
	if net == null or not is_instance_valid(net) or not net.is_host() or net.is_applying():
		return
	if not bool(is_open.call()):
		_last_minute = -1.0
		return
	var day: int = int(current_day.call())
	var minute: float = float(shed_minute.call())
	if day != _day or _last_minute < 0.0 or minute < _last_minute:
		_day = day
		_last_minute = minute
		return
	var passed: float = minute - _last_minute
	if passed < MIN_STEP_MINUTES:
		return
	_last_minute = minute
	var due: Array[Dictionary] = chain.age(net.inventory, products, cold_shelves.call(), passed)
	for entry: Dictionary in due:
		var event: Dictionary = CompanyColdNet.event_of(entry)
		if event.is_empty() or not net.publish(CompanyColdNet.SPOILED, event):
			push_warning("ColdChainTick: %s at %s could not be thrown out" % [entry["product"], entry["location"]])
	chain.forget_empty(net.inventory)


## Host: the units a move carried bring their clock with them (the event is already applied to the stock).
func _on_event_applied(_seq: int, kind: StringName, data: Dictionary) -> void:
	if kind == &"units_moved":
		chain.note_moved(net.inventory, CompanyAsk.as_id(data.get("product")), CompanyAsk.as_int(data.get("qty")),
			CompanyAsk.as_id(data.get("from")), CompanyAsk.as_id(data.get("to")))

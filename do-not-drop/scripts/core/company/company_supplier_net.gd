class_name CompanySupplierNet
extends RefCounted
## The supplier orders of the shed over the network (expansion D-0603.b.2; the supplier named, D-0621.b):
## ordering from a supplier is a CompanyNet request the host checks and an event every peer applies to its
## calendar the same way (contract docs/expansion-distritos/diseno/red-autoridad.md, rules 1, 5 and 6; D-0619).
##
## CompanyNet hands it the order requests (check(), host only) and the order events (apply(), every
## peer); it lives there as CompanyNet.supplier, and its calendar (`schedule`, the SupplierSchedule the
## suppliers' trucks follow) travels in every snapshot under SNAPSHOT_KEY, so a late joiner sees the same
## deliveries and the same truck. Nothing here sends anything, names an autoload or reads a node.
##
##   supplier_order    {supplier: <supplier id>, <product id>: units, ...}  (one key per line, at most
##                     MAX_LINES; the request's data has to stay flat, RpcGuard.dict_ok())
##   supplier_ordered  {order_day, lines: [{product, qty}], peer, supplier}
##
## `supplier` (SUPPLIER_KEY) names who sells: a supplier of `suppliers`, or DEFAULT_SUPPLIER (the one of
## `supplier`, the definition its truck sells as). A request without it is DEFAULT_SUPPLIER's, the request
## before D-0621.b, and so is an event without it. The host checks what SupplierOrderCart.submit() checks
## (D-0603.a): every product in the catalog (`products`) and sold by that supplier, 1..MAX_LINE_QTY units a
## line, a wallet that covers the order's total at that supplier's prices (its price_factor; nothing is
## charged, the bill comes with each pallet received, D-0503); and also that the day is not closed
## (DayCycle in SUMMARY: the closed day's save is final) and that that supplier's truck of that day stays
## under MAX_DAY_QTY units of a product. The event carries the host's day as `order_day` (the truck comes
## on SupplierSchedule.arrival_day()), `peer`, who asked (the order screen of that peer waits for it), and
## the supplier whose truck brings it. Every peer, the host first, applies it with
## SupplierSchedule.place() after dropping the days before `order_day` (they are past), checking only
## that the data fits (rule 6). Refusals: bad_data (also an unknown supplier, or a product it does not
## sell), no_funds, day_closed, too_much.
##
## The automatic order of the day's close (D-0151.3b, SupplierAutoOrderHook) is the same event with `peer`
## AUTO_PEER (0, nobody's id): every peer notes its units in auto_units() as it applies it, so the day's summary
## tells it; the host checks it with ask() like a request and publishes it itself (HOST_EVENT_KINDS).

const ORDER: StringName = &"supplier_order"
const ORDERED: StringName = &"supplier_ordered"
const REQUEST_KINDS: Array[StringName] = [ORDER]
const EVENT_KINDS: Array[StringName] = [ORDERED]
## Key of the calendar in CompanyNet's snapshot (SupplierSchedule.to_dict()).
const SNAPSHOT_KEY: String = "supplier"
## Key of the supplier in a supplier_order request and in a supplier_ordered event (D-0621.b).
const SUPPLIER_KEY: String = "supplier"
## Whose truck an order that names no supplier goes in.
const DEFAULT_SUPPLIER: StringName = SupplierSchedule.DEFAULT_SUPPLIER
## Products one order may carry: the request's keys, less the request id and the supplier.
const MAX_LINES: int = RpcGuard.MAX_INPUT_KEYS - 2
## Units of one product one day's truck of a supplier may bring, several orders added up.
const MAX_DAY_QTY: int = SupplierOrderCart.MAX_LINE_QTY * 10
## Days with a truck a snapshot may carry, per supplier (the events keep only today on, so a handful).
const MAX_DAYS: int = 32
## Products of one day's truck a snapshot may carry.
const MAX_DAY_PRODUCTS: int = 64
## Suppliers other than DEFAULT_SUPPLIER with a truck in a snapshot.
const MAX_SUPPLIERS: int = 16
const MAX_ID_LENGTH: int = 64
## The `peer` of the order the host sends by itself at the day's close.
const AUTO_PEER: int = 0

const REASON_BAD_DATA: StringName = &"bad_data"
## The wallet does not cover the order's total.
const REASON_NO_FUNDS: StringName = &"no_funds"
## The day is closed (its summary is up): order once the next one opens.
const REASON_DAY_CLOSED: StringName = &"day_closed"
## That day's truck would bring more than MAX_DAY_QTY units of a product.
const REASON_TOO_MUCH: StringName = &"too_much"

## The supplier calendar on this peer: the one the truck follows (CompanyRoot hands its own).
var schedule: SupplierSchedule = SupplierSchedule.new()
## Host: who sells in DEFAULT_SUPPLIER's truck (null: any product of `products`) and the catalog, product
## id -> ProductDefinition.
var supplier: SupplierDefinition
var products: Dictionary = {}
## Every supplier of the catalog, id -> SupplierDefinition, in file name order (load_catalog()).
var suppliers: Dictionary = {}

## Order day -> units of the automatic order of that day's close (AUTO_PEER), on every peer. Not part of
## the snapshot: a peer that joins after the order only misses the summary's line about it.
var _auto_units: Dictionary = {}


## The request data of an order: the lines ([{product, qty}], SupplierOrderCart.to_array()) as one key
## per product, and the supplier when `from` names one (an id: SUPPLIER_KEY). {} when there are no lines,
## more than MAX_LINES or a product named like SUPPLIER_KEY.
static func request_data(lines: Array, from: StringName = &"") -> Dictionary:
	var data: Dictionary = {}
	for line: Variant in lines:
		if not line is Dictionary:
			return {}
		var product: Variant = (line as Dictionary).get("product")
		if not CompanyAsk.is_id(product) or String(product) == SUPPLIER_KEY:
			return {}
		data[String(product)] = (line as Dictionary).get("qty")
	if data.is_empty() or data.size() > MAX_LINES:
		return {}
	if from != &"":
		data[SUPPLIER_KEY] = String(from)
	return data


## The supplier whose truck brings what `seller` sells: DEFAULT_SUPPLIER for `supplier` (or none), else its id.
func truck_of(seller: SupplierDefinition) -> StringName:
	return DEFAULT_SUPPLIER if seller == null or seller == supplier else seller.id


## Who sells in `truck`'s truck: `supplier` for DEFAULT_SUPPLIER, else the one of `suppliers` (null: unknown).
func seller(truck: StringName) -> SupplierDefinition:
	return supplier if truck == DEFAULT_SUPPLIER else suppliers.get(truck) as SupplierDefinition


## Every supplier that can be ordered from, in file name order: `suppliers`, or `supplier` alone when
## there are none.
func sellers() -> Array[SupplierDefinition]:
	var out: Array[SupplierDefinition] = []
	for id: StringName in suppliers:
		out.append(suppliers[id])
	if out.is_empty() and supplier != null:
		out.append(supplier)
	return out


## Host: the supplier_ordered a supplier_order from `peer` asks for, or its refusal: {reason: &"", kind,
## data} or {reason}. `company` is CompanyState-shaped (day, can_afford()); `day` is the DayCycle (or
## null, or a bool in a test): the day is closed while its summary is up.
func check(company: Object, data: Dictionary, peer: int, day: Variant) -> Dictionary:
	var truck: StringName = _truck_asked(data)
	var cart: SupplierOrderCart = _cart_of(data, truck)
	if cart == null or company == null:
		return {"reason": REASON_BAD_DATA}
	if is_closed(day):
		return {"reason": REASON_DAY_CLOSED}
	if not cart.can_submit(company):
		return {"reason": REASON_NO_FUNDS}
	var order_day: int = int(company.get("day"))
	var lines: Array[Dictionary] = _lines_fitting(cart, truck, SupplierSchedule.arrival_day(order_day))
	if lines.is_empty():
		return {"reason": REASON_TOO_MUCH}
	return {"reason": &"", "kind": ORDERED,
		"data": {"order_day": order_day, "lines": lines, "peer": peer, SUPPLIER_KEY: String(truck)}}


## The cart a request's lines make with `truck`'s seller, or null when the truck is none (&"") or a line
## does not fit: not an int, past MAX_LINES, a product not in the catalog or not sold there (check()).
func _cart_of(data: Dictionary, truck: StringName) -> SupplierOrderCart:
	if truck == &"":
		return null
	var cart := SupplierOrderCart.new()
	cart.supplier = seller(truck)
	cart.products = products
	var count: int = 0
	for key: Variant in data:
		if String(key) == "rid" or String(key) == SUPPLIER_KEY:
			continue
		count += 1
		var qty: Variant = data[key]
		if count > MAX_LINES or typeof(qty) != TYPE_INT or String(key).length() > MAX_ID_LENGTH:
			return null
		if not cart.add(StringName(String(key)), int(qty)):
			return null
	return null if cart.is_empty() else cart


## The event's lines of `cart` for `truck`'s truck of `arrival`, or [] when they do not fit in it: a
## product past MAX_DAY_QTY, more than MAX_DAY_PRODUCTS products, or no room for one more supplier.
func _lines_fitting(cart: SupplierOrderCart, truck: StringName, arrival: int) -> Array[Dictionary]:
	var already: Dictionary = schedule.ordered_for(arrival, truck)
	var lines: Array[Dictionary] = []
	for line: Dictionary in cart.to_array():
		if int(already.get(line["product"], 0)) + int(line["qty"]) > MAX_DAY_QTY:
			return []
		lines.append({"product": String(line["product"]), "qty": int(line["qty"])})
	if already.size() + lines.size() > MAX_DAY_PRODUCTS or not _room_for(truck):
		return []
	return lines


## The truck a request asks for: DEFAULT_SUPPLIER when it names none, `supplier` or DEFAULT_SUPPLIER; the
## id of one of `suppliers`; &"" for anything else.
func _truck_asked(data: Dictionary) -> StringName:
	if not data.has(SUPPLIER_KEY):
		return DEFAULT_SUPPLIER
	var named: Variant = data[SUPPLIER_KEY]
	if not SupplierIds.ok(named):
		return &""
	var id := StringName(named)
	if id == DEFAULT_SUPPLIER or (supplier != null and id == supplier.id):
		return DEFAULT_SUPPLIER
	return id if suppliers.has(id) else &""


## Whether a truck of `truck` fits in a snapshot: DEFAULT_SUPPLIER's always, another's while fewer than
## MAX_SUPPLIERS others have one (or it already has one).
func _room_for(truck: StringName) -> bool:
	if truck == DEFAULT_SUPPLIER:
		return true
	var others: Dictionary = schedule.to_dict().get("suppliers", {})
	return others.has(String(truck)) or others.size() < MAX_SUPPLIERS


## True when `day` (a DayCycle, or a bool) says the day is closed: its summary is up and its save is final.
static func is_closed(day: Variant) -> bool:
	if day is bool:
		return day
	return is_instance_valid(day) and day is DayCycle and (day as DayCycle).phase() == DayCycle.Phase.SUMMARY


## Host: check() with what CompanyNet `net` holds: its `company` and its `day_cycle` (closed in SUMMARY).
func ask(net: Object, peer: int, data: Dictionary) -> Dictionary:
	return check(net.get(&"company"), data, peer, net.get(&"day_cycle"))


## Every peer, the host first: applies a supplier_ordered. False, changing nothing, when the data does
## not fit (rule 5: exactly its keys, a day, 1..MAX_LINES lines of an id and 1..MAX_LINE_QTY units, every
## product once, a supplier id the calendar takes or none (DEFAULT_SUPPLIER), that truck of the day under
## MAX_DAY_QTY a product). Whether the supplier sells the products was the host's check.
func apply(data: Dictionary) -> bool:
	var lines: Array = _lines_of(data)
	var truck: StringName = StringName(data.get(SUPPLIER_KEY, DEFAULT_SUPPLIER)) if not lines.is_empty() else &""
	if truck == &"":
		return false
	var order_day: int = data["order_day"]
	var already: Dictionary = schedule.ordered_for(SupplierSchedule.arrival_day(order_day), truck)
	for line: Dictionary in lines:
		if int(already.get(StringName(line["product"]), 0)) + int(line["qty"]) > MAX_DAY_QTY:
			return false
	schedule.forget_before(order_day)
	if not schedule.place(order_day, lines, truck):
		return false
	_note_auto(data, order_day, lines)
	return true


## Units the automatic order of `order_day`'s close put in the calendar (0: none, or a peer that joined later).
func auto_units(order_day: int) -> int:
	return int(_auto_units.get(order_day, 0))


## Keeps the units of an order that came from AUTO_PEER; the days before it are past.
func _note_auto(data: Dictionary, order_day: int, lines: Array) -> void:
	for day: int in _auto_units.keys():
		if day < order_day:
			_auto_units.erase(day)
	if int(data["peer"]) != AUTO_PEER:
		return
	var units: int = 0
	for line: Dictionary in lines:
		units += int(line["qty"])
	_auto_units[order_day] = int(_auto_units.get(order_day, 0)) + units


## The lines of a supplier_ordered as they go into SupplierSchedule.place(), or [] when the event does not fit.
static func _lines_of(data: Dictionary) -> Array:
	var named: bool = data.has(SUPPLIER_KEY)
	if data.size() != (4 if named else 3) or (named and not SupplierIds.ok(data[SUPPLIER_KEY])):
		return []
	if typeof(data.get("order_day")) != TYPE_INT or typeof(data.get("peer")) != TYPE_INT:
		return []
	var raw: Variant = data.get("lines")
	if int(data["order_day"]) < 0 or not raw is Array:
		return []
	var list: Array = raw
	if list.is_empty() or list.size() > MAX_LINES:
		return []
	var out: Array = []
	var seen: Dictionary = {}
	for item: Variant in list:
		if not item is Dictionary or (item as Dictionary).size() != 2:
			return []
		var product: Variant = (item as Dictionary).get("product")
		var qty: Variant = (item as Dictionary).get("qty")
		if not _id_ok(product) or typeof(qty) != TYPE_INT:
			return []
		if int(qty) < 1 or int(qty) > SupplierOrderCart.MAX_LINE_QTY or seen.has(String(product)):
			return []
		seen[String(product)] = true
		out.append({"product": StringName(product), "qty": int(qty)})
	return out


## The snapshot part: the calendar as SupplierSchedule.to_dict() writes it.
func to_dict() -> Dictionary:
	return schedule.to_dict()


## Client: the host's calendar in place of this one, in the same object (the truck keeps reading it).
## False, changing nothing, when it does not fit: `deliveries` (DEFAULT_SUPPLIER's truck) and, optional,
## `suppliers` with at most MAX_SUPPLIERS others (ids the calendar takes); per supplier at most MAX_DAYS
## days, each a day number with up to MAX_DAY_PRODUCTS products of 1..MAX_DAY_QTY units.
func put_snapshot(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var plain: Dictionary = value
	var others: Variant = plain.get("suppliers", {})
	if plain.size() != (2 if plain.has("suppliers") else 1) or not _days_ok(plain.get("deliveries")):
		return false
	if not others is Dictionary or (others as Dictionary).size() > MAX_SUPPLIERS:
		return false
	for id: Variant in others:
		var own: bool = typeof(id) == TYPE_STRING and StringName(id) != DEFAULT_SUPPLIER
		if not (own and SupplierIds.ok(id) and _days_ok((others as Dictionary)[id])):
			return false
	schedule.copy_from(SupplierSchedule.from_dict(plain))
	return true


## Whether `deliveries` is one truck's days as a snapshot carries them (put_snapshot()).
static func _days_ok(deliveries: Variant) -> bool:
	if not deliveries is Dictionary or (deliveries as Dictionary).size() > MAX_DAYS:
		return false
	for day: Variant in deliveries:
		if typeof(day) != TYPE_STRING or not String(day).is_valid_int() or int(String(day)) < 1:
			return false
		var wanted: Variant = (deliveries as Dictionary)[day]
		if not wanted is Dictionary or (wanted as Dictionary).is_empty():
			return false
		if (wanted as Dictionary).size() > MAX_DAY_PRODUCTS:
			return false
		for product: Variant in wanted:
			var qty: Variant = (wanted as Dictionary)[product]
			if not _id_ok(product) or typeof(qty) != TYPE_INT or int(qty) < 1 or int(qty) > MAX_DAY_QTY:
				return false
	return true


## Host: cuts `schedule` down to what a client's put_snapshot() takes (a loaded save may hold more): per
## supplier the first MAX_DAYS days, MAX_DAY_PRODUCTS products a day (in id order) of at most MAX_DAY_QTY
## units, ids that fit; the first MAX_SUPPLIERS other suppliers by id. Returns how many suppliers, days,
## products or quantities were cut (0: it already fit, nothing changed).
static func fit(schedule: SupplierSchedule) -> int:
	var data: Dictionary = schedule.to_dict()
	var fitted: Dictionary = {"deliveries": {}}
	var cut: int = _fit_days(data["deliveries"], fitted["deliveries"])
	var others: Dictionary = data.get("suppliers", {})
	var ids: Array = others.keys()
	ids.sort()
	var kept: Dictionary = {}
	for id: String in ids:
		if kept.size() >= MAX_SUPPLIERS:
			cut += 1
			continue
		var days: Dictionary = {}
		cut += _fit_days(others[id], days)
		if not days.is_empty():
			kept[id] = days
	if not kept.is_empty():
		fitted["suppliers"] = kept
	if cut > 0:
		schedule.copy_from(SupplierSchedule.from_dict(fitted))
	return cut


## Puts in `kept` what of one truck's `deliveries` a snapshot takes; returns how much was cut (fit()).
static func _fit_days(deliveries: Dictionary, kept: Dictionary) -> int:
	var days: Array = deliveries.keys()
	days.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	var cut: int = 0
	for day: String in days:
		var wanted: Dictionary = deliveries[day]
		if kept.size() >= MAX_DAYS:
			cut += 1
			continue
		var day_products: Array = wanted.keys()
		day_products.sort()
		var clean: Dictionary = {}
		for product: String in day_products:
			if not _id_ok(product) or clean.size() >= MAX_DAY_PRODUCTS:
				cut += 1
				continue
			var qty: int = int(wanted[product])
			if qty > MAX_DAY_QTY:
				qty = MAX_DAY_QTY
				cut += 1
			clean[product] = qty
		if not clean.is_empty():
			kept[day] = clean
	return cut


static func _id_ok(value: Variant) -> bool:
	return CompanyAsk.is_id(value) and not String(value).is_empty() and String(value).length() <= MAX_ID_LENGTH


## Fills `products`, `suppliers` (every supplier of `catalog` with an id the calendar takes) and `supplier`
## (DEFAULT_SUPPLIER, or the first by file name when the catalog lacks it), and hands the suppliers' truck
## times to `schedule` (SupplierSchedule.use_suppliers(): set `schedule` first). Returns the product definitions.
func load_catalog(catalog: CompanyCatalog) -> Dictionary:
	var defs: Dictionary = {}
	for id: StringName in catalog.ids(CompanyCatalog.PRODUCTS):
		defs[id] = catalog.product(id)
	products = defs
	suppliers = {}
	for id: StringName in catalog.ids(CompanyCatalog.SUPPLIERS):
		var found: SupplierDefinition = catalog.supplier(id)
		if found != null and SupplierIds.ok(found.id):
			suppliers[found.id] = found
	var first: SupplierDefinition = suppliers.values()[0] if not suppliers.is_empty() else null
	supplier = suppliers.get(DEFAULT_SUPPLIER, first) as SupplierDefinition
	schedule.use_suppliers(suppliers.values())
	return defs


## Host: puts the company's saved calendar in `schedule` (days before today dropped, the rest cut to what a
## client takes, so a broken save cannot keep anyone out); returns the calendar to write back to the save.
static func load_saved(schedule: SupplierSchedule, state: Object) -> Dictionary:
	schedule.copy_from(SupplierSchedule.from_dict(state.supplier_calendar))
	schedule.forget_before(state.day)
	var cut: int = fit(schedule)
	if cut > 0:
		push_warning("CompanyRoot: the saved supplier calendar was cut to what a snapshot carries (%d cut)" % cut)
	return schedule.to_dict()

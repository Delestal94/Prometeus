class_name CompanySupplierNet
extends RefCounted
## The supplier orders of the shed over the network (expansion D-0603.b.2): ordering from the supplier
## is a CompanyNet request the host checks and an event every peer applies to its calendar the same way
## (contract docs/expansion-distritos/diseno/red-autoridad.md, rules 1, 5 and 6; D-0619).
##
## CompanyNet hands it the order requests (check(), host only) and the order events (apply(), every
## peer); it lives there as CompanyNet.supplier, and its calendar (`schedule`, the SupplierSchedule the
## supplier's truck follows) travels in every snapshot under SNAPSHOT_KEY, so a late joiner sees the same
## deliveries and the same truck. Nothing here sends anything, names an autoload or reads a node.
##
##   supplier_order    {<product id>: units, ...}  (one key per line, at most MAX_LINES; the request's
##                     data has to stay flat, RpcGuard.dict_ok())
##   supplier_ordered  {order_day, lines: [{product, qty}], peer}
##
## The host checks what SupplierOrderCart.submit() checks (D-0603.a): every product in the catalog
## (`products`) and sold by `supplier`, 1..SupplierOrderCart.MAX_LINE_QTY units a line, a wallet that
## covers the order's total (`company.can_afford()`; nothing is charged, the bill comes with each pallet
## received, D-0503); and also that the day is not closed (DayCycle in SUMMARY: the closed day's save is
## final) and that the truck of that day stays under MAX_DAY_QTY units of a product. The event carries
## the host's day as `order_day` (the truck comes on SupplierSchedule.arrival_day()) and `peer`, who
## asked (the order screen of that peer waits for it). Every peer, the host first, applies it with
## SupplierSchedule.place() after dropping the days before `order_day` (they are past), checking only
## that the data fits (rule 6). Refusals: bad_data, no_funds, day_closed, too_much.

const ORDER: StringName = &"supplier_order"
const ORDERED: StringName = &"supplier_ordered"
const REQUEST_KINDS: Array[StringName] = [ORDER]
const EVENT_KINDS: Array[StringName] = [ORDERED]
## Key of the calendar in CompanyNet's snapshot (SupplierSchedule.to_dict()).
const SNAPSHOT_KEY: String = "supplier"
## Products one order may carry: the request's keys, less the request id.
const MAX_LINES: int = RpcGuard.MAX_INPUT_KEYS - 1
## Units of one product one day's truck may bring, several orders added up.
const MAX_DAY_QTY: int = SupplierOrderCart.MAX_LINE_QTY * 10
## Days with a truck a snapshot may carry (the events keep only today on, so a handful at most).
const MAX_DAYS: int = 32
## Products of one day's truck a snapshot may carry.
const MAX_DAY_PRODUCTS: int = 64
const MAX_ID_LENGTH: int = 64

const REASON_BAD_DATA: StringName = &"bad_data"
## The wallet does not cover the order's total.
const REASON_NO_FUNDS: StringName = &"no_funds"
## The day is closed (its summary is up): order once the next one opens.
const REASON_DAY_CLOSED: StringName = &"day_closed"
## That day's truck would bring more than MAX_DAY_QTY units of a product.
const REASON_TOO_MUCH: StringName = &"too_much"

## The supplier calendar on this peer: the one the truck follows (CompanyRoot hands its own).
var schedule: SupplierSchedule = SupplierSchedule.new()
## Host: who sells (null: any product of `products`) and the catalog, product id -> ProductDefinition.
var supplier: SupplierDefinition
var products: Dictionary = {}


## The request data of an order: the lines ([{product, qty}], SupplierOrderCart.to_array()) as one key
## per product. {} when there are none or more than MAX_LINES.
static func request_data(lines: Array) -> Dictionary:
	var data: Dictionary = {}
	for line: Variant in lines:
		if not line is Dictionary:
			return {}
		var product: Variant = (line as Dictionary).get("product")
		if not CompanyAsk.is_id(product):
			return {}
		data[String(product)] = (line as Dictionary).get("qty")
	return data if not data.is_empty() and data.size() <= MAX_LINES else {}


## Host: the supplier_ordered a supplier_order from `peer` asks for, or its refusal: {reason: &"", kind,
## data} or {reason}. `company` is CompanyState-shaped (day, can_afford()); `day` is the DayCycle (or
## null, or a bool in a test): the day is closed while its summary is up.
func check(company: Object, data: Dictionary, peer: int, day: Variant) -> Dictionary:
	var cart := SupplierOrderCart.new()
	cart.supplier = supplier
	cart.products = products
	var count: int = 0
	for key: Variant in data:
		if String(key) == "rid":
			continue
		count += 1
		var qty: Variant = data[key]
		if count > MAX_LINES or typeof(qty) != TYPE_INT or String(key).length() > MAX_ID_LENGTH:
			return {"reason": REASON_BAD_DATA}
		if not cart.add(StringName(String(key)), int(qty)):
			return {"reason": REASON_BAD_DATA}
	if cart.is_empty() or company == null:
		return {"reason": REASON_BAD_DATA}
	if is_closed(day):
		return {"reason": REASON_DAY_CLOSED}
	if not cart.can_submit(company):
		return {"reason": REASON_NO_FUNDS}
	var order_day: int = int(company.get("day"))
	var already: Dictionary = schedule.ordered_for(SupplierSchedule.arrival_day(order_day))
	var lines: Array[Dictionary] = []
	for line: Dictionary in cart.to_array():
		if int(already.get(line["product"], 0)) + int(line["qty"]) > MAX_DAY_QTY:
			return {"reason": REASON_TOO_MUCH}
		lines.append({"product": String(line["product"]), "qty": int(line["qty"])})
	if already.size() + lines.size() > MAX_DAY_PRODUCTS:
		return {"reason": REASON_TOO_MUCH}
	return {"reason": &"", "kind": ORDERED, "data": {"order_day": order_day, "lines": lines, "peer": peer}}


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
## product once, the day's truck under MAX_DAY_QTY a product).
func apply(data: Dictionary) -> bool:
	var lines: Array = _lines_of(data)
	if lines.is_empty():
		return false
	var order_day: int = data["order_day"]
	var already: Dictionary = schedule.ordered_for(SupplierSchedule.arrival_day(order_day))
	for line: Dictionary in lines:
		if int(already.get(StringName(line["product"]), 0)) + int(line["qty"]) > MAX_DAY_QTY:
			return false
	schedule.forget_before(order_day)
	return schedule.place(order_day, lines)


## The lines of a supplier_ordered as they go into place(), or [] when the event does not fit.
static func _lines_of(data: Dictionary) -> Array:
	if data.size() != 3 or typeof(data.get("order_day")) != TYPE_INT or typeof(data.get("peer")) != TYPE_INT:
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
## False, changing nothing, when it does not fit: at most MAX_DAYS days, each a day number with up to
## MAX_DAY_PRODUCTS products of 1..MAX_DAY_QTY units.
func put_snapshot(value: Variant) -> bool:
	if not value is Dictionary or (value as Dictionary).size() != 1:
		return false
	var deliveries: Variant = (value as Dictionary).get("deliveries")
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
	schedule.copy_from(SupplierSchedule.from_dict(value))
	return true


## Host: cuts `schedule` down to what a client's put_snapshot() takes (a loaded save may hold more): the
## first MAX_DAYS days, MAX_DAY_PRODUCTS products a day (in id order) of at most MAX_DAY_QTY units, ids
## that fit. Returns how many days, products or quantities were cut (0: it already fit, nothing changed).
static func fit(schedule: SupplierSchedule) -> int:
	var deliveries: Dictionary = schedule.to_dict()["deliveries"]
	var days: Array = deliveries.keys()
	days.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	var kept: Dictionary = {}
	var cut: int = 0
	for day: String in days:
		var wanted: Dictionary = deliveries[day]
		if kept.size() >= MAX_DAYS:
			cut += 1
			continue
		var products: Array = wanted.keys()
		products.sort()
		var clean: Dictionary = {}
		for product: String in products:
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
	if cut > 0:
		schedule.copy_from(SupplierSchedule.from_dict({"deliveries": kept}))
	return cut


static func _id_ok(value: Variant) -> bool:
	return CompanyAsk.is_id(value) and not String(value).is_empty() and String(value).length() <= MAX_ID_LENGTH

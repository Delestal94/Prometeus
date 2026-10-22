class_name CompanyOrdersNet
extends RefCounted
## The day's customer orders over the network (expansion D-0813): one OrderBook on every peer, the
## same everywhere, written only by the host's events (contract
## docs/expansion-distritos/diseno/red-autoridad.md, "Fuera de las 20, sin petición de cliente": a new
## order comes in, an order goes late).
##
## Lives in CompanyNet as `orders`, on every peer; nothing here sends anything or names an autoload.
## Orders are host facts with no client request: the host decides the day's orders (plan_day():
## OrderGenerator with the day's seed, arrival minutes from OrderRhythm) and, as the shed's minute goes
## by, poll() publishes each one that came in as order_added and each one past its due_min as
## order_expired, through CompanyNet.publish() (numbered, reliable, the path of every event). Every
## peer, the host too, applies them in apply() with the same calls on its book and checks only the data
## (rules 5 and 6): a client never writes the book, and no request kind does. The book travels in
## CompanyNet's snapshot under SNAPSHOT_KEY (to_dict() on the host, put_snapshot() on a client), so a
## late joiner, or a peer that skipped a seq, gets the host's; the plan (orders still to come) never
## leaves the host.
##
## Events:
##   order_added    {order: an Order dictionary as Order.normalize() writes it, state open}
##   order_expired  {order: id, minute: the host's minute}: OrderBook.expire_one(), the order goes LATE
##                  (D-0807: still deliverable, the late penalty comes with the payout; nothing is
##                  reserved for an order until order_claim, row 8, so there is no reservation to free)
## In the company world (D-0813.1) the host's CompanyRoot plans each new day at its OPENING and polls on
## its business tick while the day is open (CompanyDayOrders), and every peer's tells EventBus.order_added
## from CompanyNet.event_applied. Each new day's opening drops the closed orders on every peer, inside
## its day_phase event (prune_closed(), from DayCycle.apply_phase()). CompanyTrips and OrderBoxLink keep
## a book of their own until packing, dispatch and delivery are events (rows 15, 17, 19 and 20).

const ADDED: StringName = &"order_added"
const EXPIRED: StringName = &"order_expired"
const EVENT_KINDS: Array[StringName] = [ADDED, EXPIRED]
## Key of the book in CompanyNet's snapshot (CompanyNet adds the part itself).
const SNAPSHOT_KEY: String = "orders"
## Most orders a book holds: an order_added past it is not applied, a snapshot over it is refused; while
## the book is full poll() brings no order in (expiries still go out). Each new day drops the closed orders
## (prune_closed()), but nothing closes an order of this book yet (D-0815.b, D-0302), so for now prune frees
## nothing and the busiest crew (CompanyTuning.ORDERS_MAX_PER_DAY) fills it at about day 16 of one session:
## after that no new orders come in until the session ends (the book isn't saved). About 150 KB of the
## snapshot when full (4096 were 2.4 MB and 230 ms to check on a client; revisar/D-0813.md).
const MAX_ORDERS: int = 256
## Longest id or name an order may carry.
const MAX_TEXT: int = RpcGuard.MAX_TEXT_LENGTH
## Latest minute an order or an expiry may name: GameClock.MAX_MINUTE (a year of game time), as an int.
const MAX_MINUTE: int = 365 * CompanyTuning.MINUTES_PER_DAY
## Highest pay an order may carry.
const MAX_PAY: int = 1_000_000_000
## Where the requirement and zone catalogs live: a requirement or the zone of an order names one of
## their files (the id is the file's name).
const REQUIREMENTS_DIR: String = "res://data/order_requirements/"
const ZONES_DIR: String = "res://data/zones/"
## The generator's houses: "<zone>_house_<n>", n from 1 to OrderGenerator.HOUSES_PER_ZONE.
const HOUSE_INFIX: String = "_house_"
## Keys of an order as Order.normalize() writes it, and those OrderBook adds as it moves on (they only
## travel in a snapshot).
const ORDER_KEYS: Array[String] = [
	"id", "customer", "zone", "house_id", "items", "requirements", "created_min", "due_min", "pay", "state",
]
const BOOK_KEYS: Array[String] = ["box_id", "trip_id", "late_from", "quality", "paid", "intact"]

## The shared book. Read it, never write it or replace it: only events change it (and the snapshot part
## reads this one).
var book: OrderBook = OrderBook.new()

## Host: the day plan_day() planned last (CompanyDayOrders.plan() plans each day once).
var planned_day: int = 0
## Host: the day's orders still to come in, oldest first (plan()).
var _planned: Array[Dictionary] = []
## Host: poll() already warned that the book is full (again once it had room and filled up).
var _full_warned: bool = false
## Ids of each catalog folder, read once ({dir: {StringName: true}}).
static var _catalog_ids: Dictionary = {}


## The book is a Node outside the tree: it goes with this object.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(book):
		book.free()


## Host: the orders of `day` as OrderGenerator.generate_day() draws them from `day_seed` (arrival minutes
## from OrderRhythm, the zones open today that take deliveries, the catalogs; a company in the red gets
## fewer, D-0510; each names a house of the fixed map, HouseMap, where its zone has them), to come in
## through poll(). The same seed, day, crew, zones and money give the same
## orders. Returns how many are planned (plan()).
func plan_day(day_seed: int, day: int, players: int, zones: Array[ZoneDefinition], products: Dictionary,
		requirements: Dictionary, company: Object = null) -> int:
	planned_day = day
	var templates: Dictionary = {}
	for set_res in OrderTemplateCheck.load_sets():
		templates[set_res.zone] = set_res
	return plan(OrderGenerator.generate_day(
		day_seed, day, players, zones, products, requirements, 0, company, templates, HouseMap.load_default()
	))


## Host: `orders` (Order dictionaries, the host's own) are the ones still to come in, in place of what was
## planned before, oldest first (created_min, then id), each open. One whose id is already in the book, or
## repeats an earlier one, is left out. Returns how many are planned.
func plan(orders: Array[Dictionary]) -> int:
	_planned = []
	var seen: Dictionary = {}
	for order: Dictionary in orders:
		var clean: Dictionary = Order.normalize(order)
		clean["state"] = Order.STATE_OPEN
		if book.has(clean["id"]) or seen.has(clean["id"]):
			continue
		seen[clean["id"]] = true
		_planned.append(clean)
	_planned.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["created_min"] != b["created_min"]:
			return int(a["created_min"]) < int(b["created_min"])
		return String(a["id"]) < String(b["id"]))
	return _planned.size()


## Host: the orders still to come in, oldest first (copies).
func planned() -> Array[Dictionary]:
	return _planned.duplicate(true)


## Host, as the shed's minute goes by: through `net` (whose `orders` is this), an order_added for every
## planned order whose created_min is `now_min` or earlier, oldest first, then an order_expired for every
## order of the book past its due_min at `now_min` and not late yet (OrderBook.overdue(), in book order).
## Returns how many events went out. Nothing at all on a client, while `net` applies an event, without
## its inventory or for a minute out of 0..MAX_MINUTE. A planned order leaves the plan only once its event
## went out, or when it can never go (order_ok() refuses it or its id is in the book: dropped with a
## warning). With the book full (MAX_ORDERS, one warning each time it fills) or an order_added refused,
## the orders stop there for the next poll, but the expiries still go out (they don't depend on what
## is still to come in); a refused order_expired stops the poll there.
func poll(net: CompanyNet, now_min: int) -> int:
	if net == null or net.orders != self or not net.is_host() or not _minute_ok(now_min):
		return 0
	if net.is_applying() or net.inventory == null:
		return 0
	var sent: int = 0
	_full_warned = _full_warned and book.size() >= MAX_ORDERS
	while not _planned.is_empty() and int(_planned[0]["created_min"]) <= now_min:
		var next: Dictionary = _planned[0]
		if not order_ok(next, false) or book.has(StringName(next["id"])):
			push_warning("CompanyOrdersNet: planned order %s never fits; dropped" % next.get("id"))
			_planned.pop_front()
			continue
		if book.size() >= MAX_ORDERS:
			if not _full_warned:
				push_warning("CompanyOrdersNet: the order book is full (%d); no order comes in" % MAX_ORDERS)
				_full_warned = true
			break
		if not net.publish(ADDED, {"order": next}):
			break
		_planned.pop_front()
		sent += 1
	for id: StringName in book.overdue(now_min):
		if not net.publish(EXPIRED, {"order": id, "minute": now_min}):
			return sent
		sent += 1
	return sent


## Every peer, the host too (CompanyNet._apply_state()): an order event in the book, checked only as data
## (rule 6). order_added carries exactly one whole open order (order_ok()) whose id the book doesn't have,
## with room for it (MAX_ORDERS); order_expired exactly an id of the book and the host's minute, at which
## that order is due (OrderBook.expire_one()). False, changing nothing, when it doesn't fit.
func apply(kind: StringName, data: Dictionary) -> bool:
	match kind:
		ADDED:
			var order: Variant = data.get("order")
			if data.size() != 1 or not order_ok(order, false) or book.size() >= MAX_ORDERS:
				return false
			return not book.has(StringName(order["id"])) and book.add(order)
		EXPIRED:
			var id: Variant = data.get("order")
			var minute: Variant = data.get("minute")
			if data.size() != 2 or not _text_ok(id) or not _minute_ok(minute):
				return false
			return book.expire_one(StringName(id), int(minute))
	return false


## Every peer, the host too, inside the day_phase event that opens a new day (DayCycle.apply_phase(),
## the same seq everywhere, so every book drops the same orders): the closed orders (delivered, failed,
## cancelled) leave the book, all of them from days gone by; open, packed, out and late ones stay,
## whatever their day (OrderBook.prune_closed(), no signal). Returns how many went.
func prune_closed() -> int:
	return book.prune_closed().size()


## Host: the book as CompanyNet's snapshot carries it (OrderBook.to_dict(): {orders, now_min}).
func to_dict() -> Dictionary:
	return book.to_dict()


## Client: the host's book (to_dict()) in place of this one, without a signal (OrderBook.from_dict() fires
## none), once it passed book_ok(). False when it doesn't fit: then nothing changed.
func put_snapshot(value: Variant) -> bool:
	if not book_ok(value):
		return false
	book.from_dict(value)
	return book.size() == ((value as Dictionary)["orders"] as Array).size()


## A book as to_dict() writes it, from the network (rule 5): exactly {orders, now_min}, now_min a minute
## (0..MAX_MINUTE), at most MAX_ORDERS orders, each order_ok() with what the book adds as it moves on, no
## id twice.
static func book_ok(value: Variant) -> bool:
	if not value is Dictionary or (value as Dictionary).size() != 2:
		return false
	var orders: Variant = (value as Dictionary).get("orders")
	if not _minute_ok((value as Dictionary).get("now_min")) or not orders is Array:
		return false
	if (orders as Array).size() > MAX_ORDERS:
		return false
	var ids: Dictionary = {}
	for order: Variant in orders:
		if not order_ok(order, true) or ids.has(StringName(order["id"])):
			return false
		ids[StringName(order["id"])] = true
	return true


## One order from the network (rule 5): exactly the keys Order.normalize() writes (with `book_keys`, also
## any of BOOK_KEYS, as a snapshot carries them), each of its type and in range: id, customer and state
## short text (a known state; only open without `book_keys`, as an event brings it), a zone of the catalog
## and a house of it (_house_ok()), 1 to Order.MAX_ITEMS products of the catalog, each once, 1 to
## PALLET_MAX_UNITS of each, requirements of the catalog, each once, created_min before due_min (both
## 0..MAX_MINUTE), pay 0..MAX_PAY, and nothing Order.validate() would refuse.
static func order_ok(value: Variant, book_keys: bool) -> bool:
	if not value is Dictionary or not _keys_ok(value, book_keys):
		return false
	var order: Dictionary = value
	var state: Variant = order["state"]
	var zone: Variant = order["zone"]
	var texts: bool = (
		_text_ok(order["id"]) and _text_ok(order["customer"]) and _text_ok(state)
		and _text_ok(zone) and _ids_in(ZONES_DIR).has(StringName(zone))
	)
	if not texts or not Order.STATES.has(StringName(state)) or not _house_ok(order["house_id"], zone):
		return false
	if not book_keys and StringName(state) != Order.STATE_OPEN:
		return false
	var created: Variant = order["created_min"]
	var due: Variant = order["due_min"]
	var pay: Variant = order["pay"]
	var numbers: bool = (
		_minute_ok(created) and _minute_ok(due) and int(due) > int(created)
		and typeof(pay) == TYPE_INT and int(pay) >= 0 and int(pay) <= MAX_PAY
	)
	if not (numbers and _items_ok(order["items"]) and _requirements_ok(order["requirements"])):
		return false
	return _book_fields_ok(order) and Order.validate(Order.normalize(order)).is_empty()


## Every key of ORDER_KEYS, as String, and no other (but BOOK_KEYS, with `book_keys`).
static func _keys_ok(order: Dictionary, book_keys: bool) -> bool:
	for key: String in ORDER_KEYS:
		if not order.has(key):
			return false
	for key: Variant in order:
		if typeof(key) != TYPE_STRING or not (ORDER_KEYS.has(key) or (book_keys and BOOK_KEYS.has(key))):
			return false
	return true


## 1 to Order.MAX_ITEMS lines of exactly {product, qty}: a product of the catalog, each once, and an int
## qty from 1 to CompanyTuning.PALLET_MAX_UNITS.
static func _items_ok(value: Variant) -> bool:
	if not value is Array or (value as Array).is_empty() or (value as Array).size() > Order.MAX_ITEMS:
		return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not item is Dictionary or (item as Dictionary).size() != 2:
			return false
		var product: Variant = (item as Dictionary).get("product")
		var qty: Variant = (item as Dictionary).get("qty")
		if not (_text_ok(product) and CompanyAsk.product_exists(StringName(product))):
			return false
		if seen.has(StringName(product)) or typeof(qty) != TYPE_INT:
			return false
		if int(qty) < 1 or int(qty) > CompanyTuning.PALLET_MAX_UNITS:
			return false
		seen[StringName(product)] = true
	return true


## Ids of the requirement catalog (REQUIREMENTS_DIR), each once.
static func _requirements_ok(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for requirement: Variant in value:
		if not _text_ok(requirement) or seen.has(StringName(requirement)):
			return false
		if not _ids_in(REQUIREMENTS_DIR).has(StringName(requirement)):
			return false
		seen[StringName(requirement)] = true
	return true


## What OrderBook adds to an order as it moves on, when present: box_id and trip_id short text, late_from
## a known state, quality 0..100, paid 0..MAX_PAY, intact a bool.
static func _book_fields_ok(order: Dictionary) -> bool:
	for key: String in ["box_id", "trip_id"]:
		if order.has(key) and not _text_ok(order[key], true):
			return false
	var late_from: Variant = order.get("late_from", Order.STATE_OPEN)
	var quality: Variant = order.get("quality", 0)
	var paid: Variant = order.get("paid", 0)
	if not (_text_ok(late_from) and Order.STATES.has(StringName(late_from))):
		return false
	if typeof(quality) != TYPE_INT or int(quality) < 0 or int(quality) > 100:
		return false
	if typeof(paid) != TYPE_INT or int(paid) < 0 or int(paid) > MAX_PAY:
		return false
	return typeof(order.get("intact", true)) == TYPE_BOOL


## A house the order of `zone` may name: one of the map's delivery houses (HouseAddresses, D-0312) or
## the generator's "<zone>_house_<n>" of that same zone, n from 1 to OrderGenerator.HOUSES_PER_ZONE
## written plainly (no sign, no leading zero).
static func _house_ok(house_id: Variant, zone: Variant) -> bool:
	if not _text_ok(house_id):
		return false
	var text: String = String(house_id)
	var prefix: String = String(zone) + HOUSE_INFIX
	if text.begins_with(prefix):
		var number: String = text.trim_prefix(prefix)
		var n: int = int(number) if number.is_valid_int() else 0
		return str(n) == number and n >= 1 and n <= OrderGenerator.HOUSES_PER_ZONE
	var addresses: HouseAddresses = HouseAddresses.load_default()
	return addresses != null and addresses.has_house(StringName(text))


## Ids of the catalog in `dir`: exactly the names of its files (read once per folder).
static func _ids_in(dir: String) -> Dictionary:
	if not _catalog_ids.has(dir):
		var ids: Dictionary = {}
		for file: String in ResourceLoader.list_directory(dir):
			if file.ends_with(".tres") or file.ends_with(".res"):
				ids[StringName(file.get_basename())] = true
		_catalog_ids[dir] = ids
	return _catalog_ids[dir]


## Text up to MAX_TEXT, empty only if `empty_ok`.
static func _text_ok(value: Variant, empty_ok: bool = false) -> bool:
	if not CompanyAsk.is_id(value) or String(value).length() > MAX_TEXT:
		return false
	return empty_ok or not String(value).is_empty()


## An int minute from 0 to MAX_MINUTE.
static func _minute_ok(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= MAX_MINUTE

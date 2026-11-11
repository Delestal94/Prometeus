class_name CompanyAsk
extends RefCounted
## The data of a company-mode units request, checked before the host acts on it (contract
## docs/expansion-distritos/diseno/red-autoridad.md, rule 5: plain, bounded, ids that exist).
##
## Static only, no state but the product catalog read once. CompanyNet hands each units request
## here (units_take, units_store: at_station(); units_drop: drop()) and refuses with bad_data
## whatever comes back empty; past the station, take() and store() check the stock and the hands.
## Split out of company_net.gd in D-2006 (station_of() in D-0813, take() and store() in D-0517).

## Where the product catalog lives: an id in a request must name one of its files.
const PRODUCTS_DIR: String = "res://data/products/"

## Product ids of the catalog, read once from PRODUCTS_DIR ({StringName: true}).
static var _known_products: Dictionary = {}
static var _catalog_read: bool = false


## A product id that came over the network names a product of the catalog: exactly the
## name of one of its files (case included), never a path.
static func product_exists(product: StringName) -> bool:
	if not _catalog_read:
		_catalog_read = true
		# ResourceLoader lists exported files by their original names (no .remap).
		for file: String in ResourceLoader.list_directory(PRODUCTS_DIR):
			if file.ends_with(".tres") or file.ends_with(".res"):
				_known_products[StringName(file.get_basename())] = true
	return _known_products.has(product)


## Text, as String or StringName.
static func is_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME


## {product, qty} of a units request: a product of the catalog and an int in
## 1..PALLET_MAX_UNITS. {} otherwise.
static func units(data: Dictionary) -> Dictionary:
	var product: Variant = data.get("product")
	var qty: Variant = data.get("qty")
	if not (is_id(product) and typeof(qty) == TYPE_INT):
		return {}
	if int(qty) < 1 or int(qty) > CompanyTuning.PALLET_MAX_UNITS:
		return {}
	if not product_exists(StringName(product)):
		return {}
	return {"product": StringName(product), "qty": int(qty)}


## The station, product and quantity of a units request at a station (units_take,
## units_store), or {} when any is missing, of the wrong type or out of range.
static func at_station(data: Dictionary) -> Dictionary:
	var station: Variant = data.get("station")
	var ask: Dictionary = units(data)
	if ask.is_empty() or not is_id(station) or String(station).is_empty():
		return {}
	ask["station"] = StringName(station)
	return ask


## The station a checked request names (`ask`, from at_station()), as the world describes it (`stations`,
## CompanyNet.stations), or {} when `ask` is empty, the station is unknown or its description unusable (no
## location, a hands: one, a spot that isn't a Vector3). A floor bundle with a position in `bundles` is its own
## station (row 5): its id is its location and its spot is where it lies. Out of company_net.gd in D-0813.
static func station_of(ask: Dictionary, bundles: FloorBundles, stations: Callable) -> Dictionary:
	if ask.is_empty():
		return {}
	var id: StringName = ask["station"]
	var bundle: Variant = bundles.position_of(id)
	if bundle is Vector3:
		return {"location": id, "spot": bundle}
	if not stations.is_valid():
		return {}
	var found: Variant = stations.call(id)
	if not found is Dictionary:
		return {}
	var station: Dictionary = found
	var location: StringName = as_id(station.get("location"))
	if location == &"" or String(location).begins_with(CompanyNet.HANDS_PREFIX):
		return {}
	return station if station.get("spot") is Vector3 else {}


## Host, row 5 past the station's own checks (CompanyNet._take_units()): `ask`'s units from `station` into
## `hands`, free or holding only that product, up to the hand's limit. {reason} when it is refused
## (not_enough, hands_busy, hands_full), else {reason: &"", kind: units_moved, data}. Out of company_net.gd
## in D-0517.
static func take(stock: Inventory, ask: Dictionary, station: Dictionary, hands: StringName) -> Dictionary:
	var product: StringName = ask["product"]
	var qty: int = ask["qty"]
	var from: StringName = as_id(station["location"])
	if stock.count(product, from) < qty:
		return {"reason": CompanyNet.REASON_NOT_ENOUGH}
	var held: Dictionary = stock.contents_at(hands)
	if held.size() > 1 or (held.size() == 1 and not held.has(product)):
		return {"reason": CompanyNet.REASON_HANDS_BUSY}
	if stock.count(product, hands) + qty > CompanyTuning.HAND_MAX_UNITS:
		return {"reason": CompanyNet.REASON_HANDS_FULL}
	return _moved(product, qty, from, hands)


## Host, row 6 past the station's own checks (CompanyNet._store_units()): `ask`'s units from `hands` into a
## `station` that takes them (not a floor bundle: no_station; a slot labeled for that product, `accepts`:
## wrong_product; with room under `capacity`: no_room; units in the hand: not_enough). {reason} or
## {reason: &"", kind: units_moved, data} as take(). Out of company_net.gd in D-0517.
static func store(stock: Inventory, ask: Dictionary, station: Dictionary, hands: StringName) -> Dictionary:
	var product: StringName = ask["product"]
	var qty: int = ask["qty"]
	var to: StringName = as_id(station["location"])
	if FloorBundles.is_floor(to):
		return {"reason": CompanyNet.REASON_NO_STATION}
	if stock.count(product, hands) < qty:
		return {"reason": CompanyNet.REASON_NOT_ENOUGH}
	var accepts: StringName = as_id(station.get("accepts"))
	if accepts != &"" and accepts != product:
		return {"reason": CompanyNet.REASON_WRONG_PRODUCT}
	var capacity: int = as_int(station.get("capacity"))
	if capacity > 0 and units_at(stock, to) + qty > capacity:
		return {"reason": CompanyNet.REASON_NO_ROOM}
	return _moved(product, qty, hands, to)


## The product, quantity and position of a units_drop: units() plus a finite Vector3 `pos`,
## or {} when any doesn't fit.
static func drop(data: Dictionary) -> Dictionary:
	var pos: Variant = data.get("pos")
	var ask: Dictionary = units(data)
	if ask.is_empty() or not (pos is Vector3 and RpcGuard.finite_vec3(pos)):
		return {}
	ask["pos"] = pos
	return ask


## Text as a StringName, &"" for anything else (a value that came over the network).
static func as_id(value: Variant) -> StringName:
	return StringName(value) if is_id(value) else &""


static func as_int(value: Variant) -> int:
	return int(value) if typeof(value) == TYPE_INT else 0


## Units of all products at `location`.
static func units_at(stock: Inventory, location: StringName) -> int:
	var total: int = 0
	for qty: int in stock.contents_at(location).values():
		total += qty
	return total


## The one units_moved a granted take() or store() leads to.
static func _moved(product: StringName, qty: int, from: StringName, to: StringName) -> Dictionary:
	return {"reason": &"", "kind": &"units_moved", "data": {"product": product, "qty": qty, "from": from, "to": to}}

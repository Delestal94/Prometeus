class_name CompanyAsk
extends RefCounted
## The data of a company-mode units request, checked before the host acts on it (contract
## docs/expansion-distritos/diseno/red-autoridad.md, rule 5: plain, bounded, ids that exist).
##
## Static only, no state but the product catalog read once. CompanyNet hands each units request
## here (units_take, units_store: at_station(); units_drop: drop()) and refuses with bad_data
## whatever comes back empty. Split out of company_net.gd in D-2006 (units_at() in D-0813).

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


## Units of every product at `location` in `stock` (the capacity check of units_store).
static func units_at(stock: Inventory, location: StringName) -> int:
	var total: int = 0
	for qty: int in stock.contents_at(location).values():
		total += qty
	return total


## The product, quantity and position of a units_drop: units() plus a finite Vector3 `pos`,
## or {} when any doesn't fit.
static func drop(data: Dictionary) -> Dictionary:
	var pos: Variant = data.get("pos")
	var ask: Dictionary = units(data)
	if ask.is_empty() or not (pos is Vector3 and RpcGuard.finite_vec3(pos)):
		return {}
	ask["pos"] = pos
	return ask

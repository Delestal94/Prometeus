class_name SpoilNotice
extends RefCounted
## The notice that something rotted (expansion D-0616.c): what every peer shows when it applies a
## units_spoiled event (CompanyColdNet.SPOILED, the host's rule, the same on all of them), e.g.
## "Spoiled: 4 Milk canister". Static only; the text is built from the event's data and the catalog, and
## goes out as EventBus.depot_notice (the HUD's toast, which brings its own short sound).
## Nothing here sends anything over the network: the event already reaches everybody.


## The notice for one units_spoiled (`data`: {product, qty, location}), or "" when it is not a well-formed
## one. `catalog` is optional (the real one is loaded when null); an id it doesn't know is shown as is.
static func text(data: Dictionary, catalog: CompanyCatalog = null) -> String:
	var product: StringName = CompanyAsk.as_id(data.get("product"))
	var qty: int = CompanyAsk.as_int(data.get("qty"))
	if product == &"" or qty <= 0:
		return ""
	var shown: String = String(product)
	if catalog == null:
		catalog = CompanyCatalog.load_all()
	var definition: ProductDefinition = catalog.product(product)
	if definition != null and definition.content != null and definition.content.localized_name() != "":
		shown = definition.content.localized_name()
	return TranslationServer.translate(&"WORLD_SPOILED") % [qty, shown]


## Shows the notice for `data` on `bus` (the EventBus node; null does nothing). True when one was sent.
static func announce(bus: Node, data: Dictionary, catalog: CompanyCatalog = null) -> bool:
	if bus == null or not bus.has_signal(&"depot_notice"):
		return false
	var shown: String = text(data, catalog)
	if shown == "":
		return false
	bus.emit_signal(&"depot_notice", shown)
	return true

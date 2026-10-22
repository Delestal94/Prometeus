extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_suppliers.gd
##
## The five suppliers of data/suppliers/ (expansion D-0621, "Varios proveedores"):
## - the catalog loads with no error and has five suppliers, each under its own id;
## - distribuidora_central is still the first by file name (the order screen uses the first one
##   until D-0621.b lets the crew pick) and keeps the single-supplier numbers: everything, list
##   price, 08:30, waits 180 min;
## - every catalog product has at least one seller, and the specialists sell a part of it;
## - they differ in price (factor), punctuality (arrival) and patience (wait), and every truck's
##   stay fits inside the day;
## - the perishable specialist (panaderia_mayorista) is early and short but dearer than list; the
##   cheapest one (importadora_express) is late and short.

const CENTRAL: StringName = &"distribuidora_central"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog: CompanyCatalog = CompanyCatalog.load_all()
	_expect(catalog.errors.is_empty(), "data/ loads with no errors (got %s)" % [catalog.errors])
	var ids: Array[StringName] = catalog.ids(CompanyCatalog.SUPPLIERS)
	_expect(ids.size() == 5, "five suppliers (got %s)" % [ids])
	_expect(not ids.is_empty() and ids[0] == CENTRAL, "distribuidora_central is first by file name (got %s)" % [ids])
	var problems: Array[String] = ExpansionResourceCheck.run()
	_expect(problems.is_empty(), "the resource check is clean (got %s)" % [problems])

	var central: SupplierDefinition = catalog.supplier(CENTRAL)
	_expect(central != null and central.products.size() == 10, "central sells all 10 products")
	_expect(central != null and is_equal_approx(central.price_factor, 1.0), "central sells at list price")
	_expect(central != null and central.arrival_min == CompanyTuning.SUPPLIER_ARRIVAL_MIN, "central arrives at 08:30")
	_expect(central != null and central.wait_minutes == CompanyTuning.SUPPLIER_WAIT_MIN, "central waits 180 min")

	var factors: Dictionary = {}
	var arrivals: Dictionary = {}
	for id: StringName in ids:
		var supplier: SupplierDefinition = catalog.supplier(id)
		_expect(supplier.id == id, "supplier '%s' carries its own id" % id)
		_expect(supplier.arrival_min + supplier.wait_minutes < 24 * 60, "'%s' leaves before midnight" % id)
		factors[supplier.price_factor] = true
		arrivals[supplier.arrival_min] = true
		if id != CENTRAL:
			_expect(supplier.products.size() < 10, "'%s' sells only a part of the catalog" % id)
	_expect(factors.size() == 5, "five different price factors (got %d)" % factors.size())
	_expect(arrivals.size() == 5, "five different arrival minutes (got %d)" % arrivals.size())

	for product_id: StringName in catalog.ids(CompanyCatalog.PRODUCTS):
		var sellers: int = 0
		for id: StringName in ids:
			if catalog.supplier(id).sells(product_id):
				sellers += 1
		_expect(sellers >= 1, "product '%s' has a seller" % product_id)
	_expect(catalog.supplier(&"mercado_del_campo").sells(&"hen"), "the farm market sells hens")
	_expect(not catalog.supplier(&"mercado_del_campo").sells(&"fireworks_crate"), "the farm market does not sell fireworks")

	var bakery: SupplierDefinition = catalog.supplier(&"panaderia_mayorista")
	var express: SupplierDefinition = catalog.supplier(&"importadora_express")
	_expect(bakery.price_factor > 1.0 and bakery.arrival_min < central.arrival_min
		and bakery.wait_minutes < central.wait_minutes, "the bakery is early, short and dearer than list")
	_expect(express.price_factor < 1.0 and express.arrival_min > central.arrival_min
		and express.wait_minutes < central.wait_minutes, "the importer is cheap, late and short")
	var milk: ProductDefinition = catalog.product(&"milk_canister")
	_expect(bakery.unit_price(milk) > central.unit_price(milk), "milk costs more at the bakery than at central")

	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

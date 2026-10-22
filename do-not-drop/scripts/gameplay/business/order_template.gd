class_name OrderTemplate
extends Resource
## One ready-made customer order of a district (expansion D-0820, "Modo Empresa").
##
## Authored data: which products (and how many of each) a customer of the district asks for and which
## requirements go with them. Who, which house and when are not here: those still come from the seed
## (OrderGenerator), so a template is reused day after day with other customers. Pure data, no node.

@export var id: StringName = &""
## [{product: StringName, qty: int}], one entry per distinct product.
@export var items: Array[Dictionary] = []
## Requirement ids (data/order_requirements/), the ones the products imply included.
@export var requirements: Array[StringName] = []


## Builds the order of this template for a customer and a day minute. The pay and the window follow
## the same rules as OrderGenerator (OrderPricing, the tightest requirement).
func to_order(
	order_id: StringName,
	customer: String,
	zone: StringName,
	house_id: StringName,
	created_min: int,
	products: Dictionary,
	catalog: Dictionary,
) -> Dictionary:
	var order: Dictionary = Order.make(order_id, customer, zone, house_id, items, created_min, products, requirements)
	var window: int = CompanyTuning.ORDER_WINDOW_MIN
	for req_id in requirements:
		var req: OrderRequirement = catalog.get(req_id)
		if req != null:
			window = mini(window, req.window_min(CompanyTuning.ORDER_WINDOW_MIN))
	order["due_min"] = created_min + window
	order["pay"] = OrderPricing.with_requirements(int(order["pay"]), requirements, catalog)
	return order

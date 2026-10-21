class_name SupplierDefinition
extends Resource
## One supplier of the company catalog (expansion D-0218, "Modo Empresa").
##
## Data only, like ProductDefinition: which products it sells, how its prices
## compare with each product's buy_price, when its truck pulls into the dock
## and how long it waits there. SupplierSchedule plans the deliveries; the
## truck that drives in is D-0601.

## Same as the file name in data/suppliers/.
@export var id: StringName = &""
## Product ids (data/products/) it sells.
@export var products: Array[StringName] = []
## Multiplies each product's buy_price (1.0 = list price).
@export var price_factor: float = 1.0
## Minute of the day its truck pulls into the dock.
@export var arrival_min: int = 0
## Game minutes the truck waits at the dock before leaving.
@export var wait_minutes: int = 0
## Truck model; null until D-0601 brings one (the delivery uses the default).
@export var truck_scene: PackedScene


func sells(product_id: StringName) -> bool:
	return products.has(product_id)


## What one unit of `product` costs from this supplier.
func unit_price(product: ProductDefinition) -> int:
	return roundi(product.buy_price * price_factor)

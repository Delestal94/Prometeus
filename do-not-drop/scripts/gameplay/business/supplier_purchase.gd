class_name SupplierPurchase
extends RefCounted
## What buying stock from the supplier costs (expansion D-0503, "Modo Empresa").
##
## Pure functions over a company wallet (CompanyState or anything with the same
## can_afford / charge API), a Pallet dictionary and a products catalog. Placing
## an order only checks that the wallet could pay it; the bill is charged when
## the pallet is received (the truck unloads it), so a pallet that never
## arrives costs nothing. Unit price is ProductDefinition.buy_price.

const REASON: StringName = &"supplier"


## What a supplier order of qty units of one product costs. 0 for unknown
## products or non-positive quantities. products maps id -> ProductDefinition.
static func cost(product: StringName, qty: int, products: Dictionary) -> int:
	var def: ProductDefinition = products.get(product)
	if def == null or qty <= 0:
		return 0
	return def.buy_price * qty


## What a pallet costs (its units at the product's buy price).
static func pallet_cost(pallet: Dictionary, products: Dictionary) -> int:
	return cost(StringName(pallet.get("product", &"")), int(pallet.get("qty", 0)), products)


## True when the wallet covers the whole order. Used when the order is placed.
static func can_order(wallet: Object, pallets: Array, products: Dictionary) -> bool:
	var total: int = 0
	for pallet: Dictionary in pallets:
		total += pallet_cost(pallet, products)
	return wallet.can_afford(total)


## Receives a sealed pallet into the inventory and charges its cost. False,
## changing nothing, if the pallet is invalid, already received or the product
## is unknown. The charge goes through even into the red (the goods are
## already unloaded; what a negative balance means is D-0510).
static func receive(
	wallet: Object, inventory: Inventory, pallet: Dictionary, products: Dictionary
) -> bool:
	var price: int = pallet_cost(pallet, products)
	if price <= 0 or not Pallet.receive(inventory, pallet):
		return false
	wallet.charge(price, REASON)
	return true

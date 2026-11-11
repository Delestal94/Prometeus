class_name SupplierPurchase
extends RefCounted
## What buying stock from the supplier costs (expansion D-0503, "Modo Empresa").
##
## Pure functions over a company wallet (CompanyState or anything with the same
## can_afford / charge API), a Pallet dictionary and a products catalog. Placing
## an order only checks that the wallet could pay it; the bill is charged when
## the pallet is received (the truck unloads it), so a pallet that never
## arrives costs nothing. Unit price is ProductDefinition.buy_price, times the
## price_factor of the supplier that sells it when one is named (D-0621).
##
## In the game the units enter the stock through the pallet book (PalletJack, the
## first put-down of a pallet of the truck's bed) and the host's SupplierBillHook
## calls bill() for that pallet (D-0503.b); receive() is both steps in one, for a
## caller that holds the pallet and the Inventory itself.

const REASON: StringName = &"supplier"


## What a supplier order of qty units of one product costs from `seller` (list
## price without one). 0 for unknown products or non-positive quantities.
## products maps id -> ProductDefinition.
static func cost(product: StringName, qty: int, products: Dictionary, seller: SupplierDefinition = null) -> int:
	if qty <= 0:
		return 0
	return SupplierOrderCart.unit_cost(product, products, seller) * qty


## What a pallet costs (its units at the product's buy price, or at `seller`'s).
static func pallet_cost(pallet: Dictionary, products: Dictionary, seller: SupplierDefinition = null) -> int:
	return cost(StringName(pallet.get("product", &"")), int(pallet.get("qty", 0)), products, seller)


## True when the wallet covers the whole order. Used when the order is placed.
static func can_order(wallet: Object, pallets: Array, products: Dictionary) -> bool:
	var total: int = 0
	for pallet: Dictionary in pallets:
		total += pallet_cost(pallet, products)
	return wallet.can_afford(total)


## Charges `wallet` what `pallet` costs from `seller` (pallet_cost()), with REASON.
## Returns what was charged: 0, charging nothing, for a pallet that costs nothing
## (invalid, unknown product) or when the wallet refuses. The charge goes through
## even into the red (the goods are already unloaded; what a negative balance
## means is D-0510). Whether the pallet was received, and only once, is the
## caller's to know (PalletJack.take_received()).
static func bill(
	wallet: Object, pallet: Dictionary, products: Dictionary, seller: SupplierDefinition = null
) -> int:
	var price: int = pallet_cost(pallet, products, seller)
	if price <= 0 or wallet == null or not wallet.charge(price, REASON):
		return 0
	return price


## Receives a sealed pallet into the inventory and charges its cost (bill()).
## False, changing nothing, if the pallet is invalid, already received or the
## product is unknown.
static func receive(
	wallet: Object, inventory: Inventory, pallet: Dictionary, products: Dictionary
) -> bool:
	var price: int = pallet_cost(pallet, products)
	if price <= 0 or not Pallet.receive(inventory, pallet):
		return false
	bill(wallet, pallet, products)
	return true

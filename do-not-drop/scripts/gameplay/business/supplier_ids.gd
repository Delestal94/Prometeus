class_name SupplierIds
extends RefCounted
## The ids of the suppliers' trucks and of the pallets they bring (expansion D-0621.b, "Modo Empresa").
##
## A supplier id names a truck of the SupplierSchedule and goes into the ids of its pallets, which the
## pallet book (CompanyPallets) and the Inventory ("pallet:<id>") take: so it is short, plain and has no
## SEPARATOR. DEFAULT's pallets keep the ids they had before there were several suppliers. Static only.

## The supplier of the calls that name none: the only one before D-0621.b (SupplierSchedule.DEFAULT_SUPPLIER).
const DEFAULT: StringName = &"distribuidora_central"
## Longest supplier id: it goes into the pallet ids (CompanyPallets.MAX_ID_LENGTH).
const MAX_LENGTH: int = 24
## Between the day, the supplier and the product in the pallet ids of a truck that is not DEFAULT's
## ("d<day>-<supplier>-<product>_<n>"); no supplier or product id has one.
const SEPARATOR: String = "-"


## A supplier id a calendar takes: lowercase letters, digits and '_', 1..MAX_LENGTH long.
static func ok(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return false
	var text: String = String(value)
	if text.is_empty() or text.length() > MAX_LENGTH:
		return false
	for index: int in text.length():
		var code: int = text.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


## What the ids of the pallets of `product` in `supplier`'s truck of `day` start with (Pallet.plan's
## prefix): "d<day>_<product>" for DEFAULT's, "d<day>-<supplier>-<product>" for the others'.
static func pallet_prefix(supplier: StringName, day: int, product: StringName) -> StringName:
	if supplier == DEFAULT:
		return StringName("d%d_%s" % [day, product])
	return StringName("d%d%s%s%s%s" % [day, SEPARATOR, supplier, SEPARATOR, product])


## The supplier whose truck brings the pallet `id`: the one between the separators, DEFAULT for an id
## with none (its pallets, and the shed's first ones).
static func pallet_supplier(id: StringName) -> StringName:
	var parts: PackedStringArray = String(id).split(SEPARATOR)
	return StringName(parts[1]) if parts.size() == 3 and ok(parts[1]) else DEFAULT

class_name OrderLabel
extends RefCounted
## The shipping label of a packed box (expansion D-0707, "Modo Empresa"): which order the box is
## for and the street and number the courier reads off it.
##
## Pure data, no node, no autoload. The address is derived from the order's house_id
## ("<zone>_house_<n>", see OrderGenerator). Street names are translation keys (the screen calls
## tr()); until D-0312 gives every street its own name there is one street per zone and the
## number is the house number, so the same house always shows the same address on the label and
## on the house sign. The look of the paper is package_shipping_label.gd (presentation).

## zone id -> translation key of its street. Placeholder until D-0312 (one street per zone).
const STREET_KEYS: Dictionary = {
	&"centro": &"WORLD_STREET_CENTRO",
	&"campo": &"WORLD_STREET_CAMPO",
}
const FALLBACK_STREET_KEY: StringName = &"WORLD_STREET_MAIN"


## {order, customer, street_key, number} for an order dictionary; empty if it names no house.
static func address(order: Dictionary) -> Dictionary:
	var order_id: String = str(order.get("id", ""))
	var number: int = house_number(StringName(str(order.get("house_id", ""))))
	if order_id == "" or number < 1:
		return {}
	var zone: StringName = StringName(str(order.get("zone", "")))
	return {
		"order": StringName(order_id),
		"customer": str(order.get("customer", "")),
		"street_key": STREET_KEYS.get(zone, FALLBACK_STREET_KEY),
		"number": number,
	}


## 12 from "centro_house_12"; 0 if the id has no house number.
static func house_number(house_id: StringName) -> int:
	var parts: PackedStringArray = String(house_id).split("_house_")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return 0
	return maxi(int(parts[1]), 0)


## True when the label on the box is the one for this order.
static func matches(box: PackedBox, order: Dictionary) -> bool:
	return box != null and box.label_order_id != &"" and str(box.label_order_id) == str(order.get("id", ""))

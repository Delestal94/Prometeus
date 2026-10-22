class_name OrderLabel
extends RefCounted
## The shipping label of a packed box (expansion D-0707, "Modo Empresa"): which order the box is
## for and the street and number the courier reads off it.
##
## Pure data, no node, no autoload. The address is derived from the order's house_id
## naming a house of the map (HouseAddresses, D-0312: its street and number, the same ones the
## house sign shows) or the generator's older "<zone>_house_<n>". Street names are translation
## keys (the screen calls tr()). The look of the paper is package_shipping_label.gd (presentation).

## Houses the map does not know (the generator's "<zone>_house_<n>"): zone id -> translation key
## of its one street, and the number is the house number.
const STREET_KEYS: Dictionary = {
	&"centro": &"WORLD_STREET_CENTRO",
	&"campo": &"WORLD_STREET_CAMPO",
}
const FALLBACK_STREET_KEY: StringName = &"WORLD_STREET_MAIN"


## {order, customer, street_key, number} for an order dictionary; empty if it names no house.
static func address(order: Dictionary) -> Dictionary:
	var order_id: String = str(order.get("id", ""))
	var house_id := StringName(str(order.get("house_id", "")))
	var addresses: HouseAddresses = HouseAddresses.load_default()
	if order_id != "" and addresses != null and addresses.has_house(house_id):
		var known: Dictionary = addresses.of_house(house_id)
		return {
			"order": StringName(order_id),
			"customer": str(order.get("customer", "")),
			"street_key": known["street_key"],
			"number": known["number"],
		}
	var number: int = house_number(house_id)
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

class_name CompanyTooltips
extends RefCounted
## What a product or an order requirement says when the player points at it (expansion D-1908,
## "Modo Empresa"): the tooltip with the mouse and the detail line under a list with the gamepad.
##
## Static and stateless, from the data alone (ProductDefinition, OrderRequirement), so every peer
## writes it in its own language. A product: size in cells and weight, fragile, cold or hot, the trap
## its content carries and what it costs and earns. A requirement: the stamp it asks for, the minimum
## packing quality, a shorter deadline and the extra pay. Nothing that is not set is said (no "Trampa"
## for a product without one). No autoload is named (N-919): a --script test compiles it.

const REQUIREMENTS_DIR: String = "res://data/order_requirements"
const TRAPS_DIR: String = "res://data/traps"
## Stamp id -> translation key of its name, the same names the order sheet uses.
const SEAL_KEYS: Dictionary = OrderSheet.REQUIREMENT_KEYS
const TEMPERATURE_KEYS: Dictionary = {
	&"cold": "UI_TIP_PRODUCT_COLD",
	&"heat": "UI_TIP_PRODUCT_HEAT",
}


## One line per fact of `product` (none for null).
static func product_lines(product: ProductDefinition) -> PackedStringArray:
	var lines: PackedStringArray = []
	if product == null:
		return lines
	lines.append(TranslationServer.translate("UI_TIP_PRODUCT_SIZE") % [
		product.cells.x, product.cells.y, product.cells.z, weight_text(product.weight_kg)])
	if product.fragile:
		lines.append(TranslationServer.translate("UI_TIP_PRODUCT_FRAGILE"))
	if TEMPERATURE_KEYS.has(product.temperature):
		lines.append(TranslationServer.translate(TEMPERATURE_KEYS[product.temperature]))
	var trap: String = trap_name(product.trap_id)
	if not trap.is_empty():
		lines.append(TranslationServer.translate("UI_TIP_PRODUCT_TRAP") % trap)
	lines.append(TranslationServer.translate("UI_TIP_PRODUCT_PRICES") % [product.buy_price, product.get_sell_price()])
	return lines


## "3" for 3.0 kg, "0.5" for half a kilo: one decimal only when there is one.
static func weight_text(kg: float) -> String:
	var tenths: int = roundi(kg * 10.0)
	return str(roundi(tenths / 10.0)) if tenths % 10 == 0 else String.num(tenths / 10.0, 1)


## The tooltip of `product`: its lines one under the other ("" for null).
static func product_text(product: ProductDefinition) -> String:
	return "\n".join(product_lines(product))


## One line per rule of `requirement`: its name, then what it asks and pays (none for null).
static func requirement_lines(requirement: OrderRequirement) -> PackedStringArray:
	var lines: PackedStringArray = []
	if requirement == null:
		return lines
	if not requirement.display_key.is_empty():
		lines.append(TranslationServer.translate(requirement.display_key))
	for seal: StringName in requirement.required_seals:
		var key: String = String(SEAL_KEYS.get(seal, ""))
		var seal_name: String = TranslationServer.translate(key) if not key.is_empty() else String(seal)
		lines.append(TranslationServer.translate("UI_TIP_REQ_SEAL") % seal_name)
	if requirement.min_quality > 0:
		lines.append(TranslationServer.translate("UI_TIP_REQ_QUALITY") % requirement.min_quality)
	if requirement.window_factor < 1.0:
		lines.append(TranslationServer.translate("UI_TIP_REQ_WINDOW") % roundi(requirement.window_factor * 100.0))
	if requirement.pay_bonus > 0.0:
		lines.append(TranslationServer.translate("UI_TIP_REQ_BONUS") % roundi(requirement.pay_bonus * 100.0))
	return lines


static func requirement_text(requirement: OrderRequirement) -> String:
	return "\n".join(requirement_lines(requirement))


## The requirement `id` from data/order_requirements/ (null when there is none).
static func load_requirement(id: StringName) -> OrderRequirement:
	var path: String = "%s/%s.tres" % [REQUIREMENTS_DIR, id]
	if String(id).is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as OrderRequirement


## The translated name of the trap `trap_id` ("" without one or for an id with no .tres).
static func trap_name(trap_id: StringName) -> String:
	var path: String = "%s/%s.tres" % [TRAPS_DIR, trap_id]
	if String(trap_id).is_empty() or not ResourceLoader.exists(path):
		return ""
	var trap: Resource = load(path)
	if trap == null or not trap.has_method(&"name_key"):
		return ""
	return TranslationServer.translate(String(trap.call(&"name_key")))

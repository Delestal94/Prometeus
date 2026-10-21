class_name PackingTutorial
extends RefCounted
## Guided first box at the packing table (expansion D-0720, "Modo Empresa").
##
## Static and stateless: the step is read from the table and the order, so it cannot get out of
## step with what the player did (undo, disassemble, doing things out of order). The screen that
## shows it (hint panel) only draws `key` with the control hint of `action`. Every step is done
## with the `interact` action, which has a keyboard and a gamepad binding, so the flow needs no
## mouse. No node, no autoload, no tr(): texts are translation keys.
##
## Steps in order: BOX (take a box), PRODUCTS (put the order's products in), SEALS (only if the
## order asks for some), LABEL, TAPE, DISPATCH (leave it in the dispatch zone), then DONE.

const BOX: StringName = &"box"
const PRODUCTS: StringName = &"products"
const SEALS: StringName = &"seals"
const LABEL: StringName = &"label"
const TAPE: StringName = &"tape"
const DISPATCH: StringName = &"dispatch"
const DONE: StringName = &"done"

## Step id -> translation key of its text. Literal keys, so the translation test sees them.
const KEYS: Dictionary = {
	&"box": "WORLD_PACKTUT_BOX",
	&"products": "WORLD_PACKTUT_PRODUCTS",
	&"seals": "WORLD_PACKTUT_SEALS",
	&"label": "WORLD_PACKTUT_LABEL",
	&"tape": "WORLD_PACKTUT_TAPE",
	&"dispatch": "WORLD_PACKTUT_DISPATCH",
	&"done": "WORLD_PACKTUT_DONE",
}

## Input action every step is done with (keyboard and gamepad).
const ACTION: StringName = &"interact"


## The step the player is on for `station` and `order` (an Order dictionary, {} for none):
## {id, key, action, index, total, done}. `index` counts from 0 over the steps this order needs;
## `dispatched` is true once the box left the table sealed (the table is empty again).
static func step(station: PackingStation, order: Dictionary, dispatched: bool = false) -> Dictionary:
	var ids: Array[StringName] = steps_for(order)
	var id: StringName = _current(station, order, dispatched)
	var at: int = ids.find(id)
	return {
		"id": id,
		"key": KEYS[id],
		"action": ACTION,
		"index": at if at >= 0 else ids.size(),
		"total": ids.size(),
		"done": id == DONE,
	}


## The steps this order needs, in order (SEALS only with required seals; DONE not included).
static func steps_for(order: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = [BOX, PRODUCTS]
	if not BoxSeals.required(order).is_empty():
		out.append(SEALS)
	out.append_array([LABEL, TAPE, DISPATCH] as Array[StringName])
	return out


static func _current(station: PackingStation, order: Dictionary, dispatched: bool) -> StringName:
	if station == null:
		return BOX
	if dispatched and not station.has_box():
		return DONE
	var box: PackedBox = station.box
	if box == null:
		return BOX
	var errors: Dictionary = station.content_errors(order)
	if not errors.get("missing", []).is_empty() or not errors.get("extra", []).is_empty():
		return PRODUCTS
	if not BoxSeals.missing(box, order).is_empty():
		return SEALS
	if box.label_order_id != StringName(str(order.get("id", ""))):
		return LABEL
	if not box.taped:
		return TAPE
	return DISPATCH

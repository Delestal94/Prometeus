class_name Shelf
extends RefCounted
## A storage placeable with labeled product slots (expansion D-0608, "Modo Empresa").
##
## Pure data over the Inventory (D-0211): the shelf only remembers which product each slot is
## labeled for; the units live in the Inventory at `shelf:<shelf_id>_<slot>`. A slot holds one
## product (its label) up to CompanyTuning.SHELF_SLOT_CAPACITY units. Putting units in moves
## them from where they were (hands, cart, pallet), so nothing is created or lost; the node that
## draws the shelf and the player interaction (D-0609, D-0611) call this.

var id: StringName = &""
## Product label of each slot; &"" is an unlabeled, empty slot.
var labels: Array[StringName] = []
## A fridge (PlaceableDefinition.cold, D-0617): it keeps only cold products and no other shelf does.
var cold: bool = false


## A shelf of `slot_count` slots (use PlaceableDefinition.slots and .cold); null if id or count is invalid.
static func make(shelf_id: StringName, slot_count: int, is_cold: bool = false) -> Shelf:
	if shelf_id == &"" or slot_count <= 0:
		return null
	var shelf := Shelf.new()
	shelf.id = shelf_id
	shelf.cold = is_cold
	shelf.labels.resize(slot_count)
	shelf.labels.fill(&"")
	return shelf


func slot_count() -> int:
	return labels.size()


## Where the Inventory counts the units of a slot.
func location(slot: int) -> StringName:
	return StringName("shelf:%s_%d" % [id, slot])


func label_of(slot: int) -> StringName:
	return labels[slot] if _valid(slot) else &""


## First slot labeled for the product, or -1.
func find_slot(product: StringName) -> int:
	return labels.find(product) if product != &"" else -1


## True when a product of this temperature (ProductDefinition.temperature) may be kept here: a fridge
## takes only cold ones, any other shelf only the rest.
func accepts_temperature(temperature: StringName) -> bool:
	return (temperature == ColdPack.COLD) == cold


## Labels an empty slot (or relabels the same product). Fails if the slot holds units of
## another product, or if the product already has another slot on this shelf. `temperature` is the
## product's (ProductDefinition.temperature); a fridge refuses ambient products and the other shelves
## refuse cold ones (D-0617). &"" skips that check.
func set_label(
	inventory: Inventory, slot: int, product: StringName, temperature: StringName = &""
) -> bool:
	if not _valid(slot) or product == &"":
		return false
	if temperature != &"" and not accepts_temperature(temperature):
		return false
	if labels[slot] == product:
		return true
	if count(inventory, slot) > 0:
		return false
	if find_slot(product) != -1:
		return false
	labels[slot] = product
	return true


## Clears the label of an empty slot.
func clear_label(inventory: Inventory, slot: int) -> bool:
	if not _valid(slot) or count(inventory, slot) > 0:
		return false
	labels[slot] = &""
	return true


func count(inventory: Inventory, slot: int) -> int:
	if not _valid(slot):
		return 0
	return inventory.count(labels[slot], location(slot)) if labels[slot] != &"" else 0


## Units that still fit in the slot.
func free_space(inventory: Inventory, slot: int) -> int:
	if not _valid(slot) or labels[slot] == &"":
		return 0
	return CompanyTuning.SHELF_SLOT_CAPACITY - count(inventory, slot)


## Puts `qty` units of the slot's product in the slot, taking them from `from`. All or nothing:
## fails if the slot is unlabeled for that product, it would overflow, or `from` holds fewer.
func deposit(
	inventory: Inventory, slot: int, product: StringName, qty: int, from: StringName
) -> bool:
	if not _valid(slot) or labels[slot] != product or qty <= 0:
		return false
	if qty > free_space(inventory, slot):
		return false
	return inventory.move(product, qty, from, location(slot))


## Takes `qty` units out of the slot into `to` (hands, cart: D-0609). All or nothing.
func withdraw(inventory: Inventory, slot: int, qty: int, to: StringName) -> bool:
	if not _valid(slot) or labels[slot] == &"" or qty <= 0:
		return false
	return inventory.move(labels[slot], qty, location(slot), to)


## Units of a product on this shelf, across slots.
func total_of(inventory: Inventory, product: StringName) -> int:
	var slot: int = find_slot(product)
	return count(inventory, slot) if slot != -1 else 0


func to_dict() -> Dictionary:
	return {"id": id, "labels": labels.duplicate(), "cold": cold}


## Rebuilds a shelf from to_dict() (also after a JSON round trip); null if it is invalid.
static func from_dict(data: Dictionary) -> Shelf:
	var raw: Array = data.get("labels", [])
	var shelf: Shelf = make(StringName(str(data.get("id", ""))), raw.size(), bool(data.get("cold", false)))
	if shelf == null:
		return null
	for i: int in raw.size():
		shelf.labels[i] = StringName(str(raw[i]))
	return shelf


func _valid(slot: int) -> bool:
	return slot >= 0 and slot < labels.size()

class_name CompanyColdNet
extends RefCounted
## Cold products that rot, over the network (expansion D-0616.b): what the host's ColdChainTick decides
## reaches every peer as one host event, units_spoiled, so the stock (and the orders that counted on it)
## ends the same on all of them. Static only; nothing here sends anything or names an autoload.
##
## The clocks (ColdChain) live on the host alone: a client has no use for them, it only sees the loss
## as stock. Nobody asks for this event (the host's own rule, like wallet_moved): CompanyNet.publish()
## takes it, CompanyNet._apply_state() applies it with apply() on every peer, the host too.
##
## Event (CompanyNet.HOST_EVENT_KINDS):
##   units_spoiled  {product: id, qty: int > 0, location: id}   all the units of `product` at `location`
## Applying it is Inventory.discard(): the units leave the stock even if reserved and, if the orders now
## promise more than is left, the newest reservations shrink until they fit. Every peer holds the same
## reservations (they travel in the snapshot), so every peer cuts the same ones: the event doesn't name
## the orders that lost units. A copy that doesn't hold those units (apply() is false) is off the host's
## and CompanyNet asks for a snapshot.

## Cold units rotted in a place (CompanyNet.HOST_EVENT_KINDS).
const SPOILED: StringName = &"units_spoiled"


## Host: the event for one entry of ColdChain.age() ({product, location, qty}), or {} when it is not a
## well-formed one.
static func event_of(due: Dictionary) -> Dictionary:
	var product: StringName = CompanyAsk.as_id(due.get("product"))
	var location: StringName = CompanyAsk.as_id(due.get("location"))
	var qty: int = CompanyAsk.as_int(due.get("qty"))
	if product == &"" or location == &"" or qty <= 0:
		return {}
	return {"product": product, "qty": qty, "location": location}


## Every peer, the host too: `data` (a units_spoiled) applied to `inventory`. Checked only as data
## (rule 6): ids no longer than a snapshot's and a positive int; the place must hold the units. False,
## changing nothing, otherwise.
static func apply(inventory: Inventory, data: Dictionary) -> bool:
	var product: StringName = CompanyAsk.as_id(data.get("product"))
	var location: StringName = CompanyAsk.as_id(data.get("location"))
	var qty: int = CompanyAsk.as_int(data.get("qty"))
	if inventory == null or product == &"" or location == &"" or qty <= 0:
		return false
	if not (CompanySnapshot.name_ok(product) and CompanySnapshot.name_ok(location)):
		return false
	return inventory.discard(product, qty, location) is Dictionary

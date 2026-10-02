class_name AccessoryOffers
extends RefCounted
## The accessory shop's offers and what they cost (N-923.3 / N-923.4), pure: no
## scene, no network, no wallet. The depot's counter and a service stop's both
## build their rows from here, so there is one catalogue and one price formula;
## the host's CrewProgression.buy_accessory() is the only thing that charges.
##
## An offer is one accessory for one buyer: id "accessory:<peer>:<accessory>",
## {title, detail, cost, accessory, buyer (peer id), multiplier}, plus whatever
## `extra` the venue stamps (a service stop adds venue and stop). The buyer is
## the player who asked for it, never the winner of a vote on something else.

const PREFIX: String = "accessory:"


static func offer_id(buyer_peer: int, accessory: StringName) -> StringName:
	return StringName("%s%d:%s" % [PREFIX, buyer_peer, accessory])


## Whether `offer` is an accessory offer (it names a catalogue accessory).
static func is_offer(offer: Variant) -> bool:
	return offer is Dictionary and AccessoryCatalog.has(StringName((offer as Dictionary).get("accessory", &"")))


## What `accessory` costs the team: the catalogue price times `multiplier` (a
## surcharge, never a discount: it is clamped to 1), halved by a Discount card.
## -1 for an id that is not sold, so it can never be bought as free.
static func cost(accessory: StringName, multiplier: float = 1.0, discounted: bool = false) -> int:
	var base: int = AccessoryCatalog.price_of(accessory)
	if base < 0:
		return -1
	var price: int = roundi(base * maxf(multiplier, 1.0))
	return maxi(0, roundi(price * 0.5)) if discounted else price


## The whole catalogue, once per buyer in `buyer_peers`, in shelf order.
static func build(buyer_peers: Array, multiplier: float = 1.0, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	for peer: Variant in buyer_peers:
		for accessory: StringName in AccessoryCatalog.ids():
			var offer: Dictionary = {
				"title": AccessoryCatalog.title_key(accessory),
				"detail": AccessoryCatalog.slot_title_key(AccessoryCatalog.slot_of(accessory)),
				"cost": cost(accessory, multiplier), "accessory": accessory, "buyer": int(peer),
				"multiplier": maxf(multiplier, 1.0),
			}
			offer.merge(extra, true)
			result[offer_id(int(peer), accessory)] = offer
	return result


## Why `buyer` (a colour key) can't have `accessory` right now: &"" if it can,
## &"unknown" (not in the catalogue), &"owned" (the buyer has it) or &"taken"
## (another player has it: there is one copy of each).
static func block_reason(inventory: AccessoryInventory, buyer: String, accessory: StringName) -> StringName:
	if not AccessoryCatalog.has(accessory) or buyer.is_empty():
		return &"unknown"
	var holder: String = inventory.owner_of(accessory)
	if holder.is_empty():
		return &""
	return &"owned" if holder == buyer else &"taken"


## The offer ids in `offers` that can't be bought because somebody has the
## accessory already (whoever the buyer is).
static func blocked_ids(offers: Dictionary, inventory: AccessoryInventory) -> Array:
	var blocked: Array = []
	for id: Variant in offers:
		var offer: Variant = offers[id]
		if is_offer(offer) and not inventory.owner_of(StringName((offer as Dictionary)["accessory"])).is_empty():
			blocked.append(id)
	return blocked

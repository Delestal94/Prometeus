extends RefCounted
## The service station's accessory shelf talking to the crew's wallet (N-923.4).
## ServiceStopShop keeps its by-name calls on CrewProgression under the dynamic
## dispatch budget (test_dynamic_dispatch_budget); the accessory part lives here
## and takes the CrewProgression node as an argument (its script names autoloads,
## so it can't be typed here). The rules themselves are CrewProgression's
## buy_accessory() and AccessoryOffers: this only asks.


## The accessory offer ids nobody can buy now: somebody has the accessory (one
## copy of each).
static func blocked(crew: Node, offers: Dictionary) -> Array:
	if crew == null:
		return []
	return AccessoryOffers.blocked_ids(offers, crew.get(&"accessories") as AccessoryInventory)


## Host: buys `offer` (an accessory offer) for its buyer. {ok, reason, cost, who}:
## CrewProgression.buy_accessory()'s answer plus the colour name of the buyer for
## the notice. Nothing is charged unless the grant works.
static func buy(crew: Node, offer: Dictionary, discount_peer: int, default_multiplier: float) -> Dictionary:
	var peer: int = int(offer.get("buyer", 0))
	var result: Dictionary = crew.call(&"buy_accessory", crew.call(&"player_color_key", peer),
			StringName(offer["accessory"]), float(offer.get("multiplier", default_multiplier)), discount_peer)
	result["who"] = String(crew.call(&"player_color_name", peer))
	return result

extends Node
## Host-owned shop vote. The UI only needs to display offers, submit a vote,
## and react to the resolved purchase.

var offers: Dictionary = {} # id -> {cost, label}
var votes: Dictionary = {} # peer -> offer id
var active: bool = false
var crew_progression: Node
var event_bus: Node

func open_shop(new_offers: Dictionary) -> void:
	offers = new_offers.duplicate(true)
	votes.clear()
	active = true
	_emit_event(&"shop_opened", [offers.duplicate(true)])

func vote(peer_id: int, offer_id: StringName) -> bool:
	if not active or not offers.has(offer_id):
		return false
	votes[peer_id] = offer_id
	_emit_event(&"shop_vote_changed", [peer_id, offer_id])
	return true

func resolve(peers: Array) -> StringName:
	if not active:
		return &""
	var counts: Dictionary = {}
	for peer: Variant in peers:
		var offer: StringName = votes.get(int(peer), &"")
		if not offer.is_empty():
			counts[offer] = int(counts.get(offer, 0)) + 1
	var winner: StringName = &""
	var best: int = -1
	for offer: StringName in counts:
		if int(counts[offer]) > best:
			winner = offer
			best = int(counts[offer])
	return _buy(winner)

func use_priority(peer_id: int, offer_id: StringName) -> StringName:
	if not active or not offers.has(offer_id):
		return &""
	var crew: Node = _crew()
	if crew == null or not crew.consume_card(peer_id, crew.Card.PRIORITY):
		return &""
	return _buy(offer_id)


func use_revote(peer_id: int) -> bool:
	var crew: Node = _crew()
	if not active or crew == null or not crew.consume_card(peer_id, crew.Card.REVOTE):
		return false
	votes.clear()
	_emit_event(&"shop_vote_changed", [peer_id, &""])
	return true


func use_discount(peer_id: int, offer_id: StringName) -> StringName:
	var crew: Node = _crew()
	if not active or not offers.has(offer_id) or crew == null:
		return &""
	if not crew.consume_card(peer_id, crew.Card.DISCOUNT):
		return &""
	var offer: Dictionary = offers[offer_id].duplicate(true)
	offer["cost"] = maxi(0, roundi(int(offer.get("cost", 0)) * 0.5))
	offers[offer_id] = offer
	return _buy(offer_id)


func reveal_offers(peer_id: int) -> Dictionary:
	var crew: Node = _crew()
	if crew == null or not crew.consume_card(peer_id, crew.Card.INFORMATION):
		return {}
	return offers.duplicate(true)

func _buy(offer_id: StringName) -> StringName:
	if offer_id.is_empty() or not offers.has(offer_id):
		return &""
	var offer: Dictionary = offers[offer_id]
	var crew: Node = _crew()
	if crew == null or not crew.spend(int(offer.get("cost", 0))):
		return &""
	active = false
	_emit_event(&"shop_resolved", [offer_id, offer.duplicate(true)])
	return offer_id


func _crew() -> Node:
	if crew_progression != null:
		return crew_progression
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/CrewProgression")


func _emit_event(signal_name: StringName, arguments: Array) -> void:
	var bus: Node = event_bus
	if bus == null and is_inside_tree():
		bus = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(signal_name):
		var payload: Array = [signal_name]
		payload.append_array(arguments)
		bus.callv(&"emit_signal", payload)

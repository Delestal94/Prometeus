extends CoopVote
## Take My Package's shop vote on the coop_vote module's CoopVote
## (docs/modulos.md): the module runs the vote and mirrors it to every
## peer; this file is the depot's supplies as the offers, the shared wallet
## (CrewProgression) as the purse, the crew's cards (priority, revote,
## discount, information) and the EventBus signals the UI listens to.
## Purchasing remains the depot's responsibility.

var crew_progression: Node
var event_bus: Node


func _ready() -> void:
	session = get_node_or_null(^"/root/NetworkManager") as NetSession
	opened.connect(func(new_offers: Dictionary) -> void: _emit_event(&"shop_opened", [new_offers]))
	vote_changed.connect(
		func(peer_id: int, offer_id: StringName) -> void: _emit_event(&"shop_vote_changed", [peer_id, offer_id]))
	resolved.connect(
		func(offer_id: StringName, offer: Dictionary) -> void: _emit_event(&"shop_resolved", [offer_id, offer]))
	var bus: Node = event_bus if event_bus != null else get_node_or_null(^"/root/EventBus")
	if bus != null and bus.has_signal(&"run_started") and not bus.is_connected(&"run_started", _on_run_started):
		bus.connect(&"run_started", _on_run_started)
	if bus != null and bus.has_signal(&"run_ended") and not bus.is_connected(&"run_ended", _on_run_ended):
		bus.connect(&"run_ended", _on_run_ended)


func open_shop(new_offers: Dictionary) -> void:
	open(new_offers)


@rpc("any_peer", "call_local", "reliable")
func request_open_shop() -> void:
	request_open()


func use_priority(peer_id: int, offer_id: StringName) -> StringName:
	if not active or not offers.has(offer_id):
		return &""
	var crew: Node = _crew()
	if crew == null or not crew.consume_card(peer_id, crew.Card.PRIORITY):
		return &""
	return buy(offer_id)


func use_revote(peer_id: int) -> bool:
	var crew: Node = _crew()
	if not active or crew == null or not crew.consume_card(peer_id, crew.Card.REVOTE):
		return false
	restart_votes(peer_id)
	return true


@rpc("any_peer", "call_local", "reliable")
func request_revote() -> bool:
	if not is_host() or not RpcGuard.allow_request(self):
		return false
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender_id if sender_id != 0 else local_peer_id()
	if not use_revote(peer_id):
		return false
	_broadcast_state()
	return true


## Discount closes the vote on its current leader. The depot receives the
## marker in shop_resolved and performs the already-authoritative discounted
## purchase; the card is only consumed if that purchase succeeds.
@rpc("any_peer", "call_local", "reliable")
func request_discount(offer_id: StringName) -> bool:
	if not is_host() or not active or not RpcGuard.allow_request(self):
		return false
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender_id if sender_id != 0 else local_peer_id()
	var crew: Node = _crew()
	if crew == null or not crew.has_card(peer_id, crew.Card.DISCOUNT):
		return false
	if offer_id != resolve_winner(connected_peers()):
		return false
	var offer: Dictionary = (offers[offer_id] as Dictionary).duplicate(true)
	offer["discounted"] = true
	offer["discount_peer"] = peer_id
	close_on(offer_id, offer)
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
	return buy(offer_id)


func reveal_offers(peer_id: int) -> Dictionary:
	var crew: Node = _crew()
	if crew == null or not crew.consume_card(peer_id, crew.Card.INFORMATION):
		return {}
	return offers.duplicate(true)


func _default_offers() -> Dictionary:
	var crew: Node = _crew()
	return crew.SUPPLIES if crew != null else {}


func _spend(cost: int) -> bool:
	var crew: Node = _crew()
	return crew != null and bool(crew.spend(cost))


func _on_run_started(_route_id: StringName, _players: Array) -> void:
	reset()


func _on_run_ended(_score: int, _results: Dictionary) -> void:
	reset()


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

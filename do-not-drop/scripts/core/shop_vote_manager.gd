extends Node
## Host-owned shop vote. The UI only needs to display offers, submit a vote,
## and react to the resolved purchase.

const VOTE_DURATION: float = 20.0

var offers: Dictionary = {} # id -> {cost, label}
var votes: Dictionary = {} # peer -> offer id
var active: bool = false
var timer_started: bool = false
var seconds_left: float = VOTE_DURATION
var crew_progression: Node
var event_bus: Node


func _ready() -> void:
	var bus: Node = event_bus if event_bus != null else get_node_or_null(^"/root/EventBus")
	if bus != null and bus.has_signal(&"run_started") and not bus.is_connected(&"run_started", _on_run_started):
		bus.connect(&"run_started", _on_run_started)
	if bus != null and bus.has_signal(&"run_ended") and not bus.is_connected(&"run_ended", _on_run_ended):
		bus.connect(&"run_ended", _on_run_ended)


func _process(delta: float) -> void:
	if not active or not timer_started:
		return
	if _is_host() and _everyone_voted(_connected_peers()):
		finish_vote(_connected_peers())
		return
	seconds_left = maxf(0.0, seconds_left - delta)
	if _is_host() and is_zero_approx(seconds_left):
		finish_vote(_connected_peers())


func open_shop(new_offers: Dictionary) -> void:
	offers = new_offers.duplicate(true)
	votes.clear()
	active = true
	timer_started = false
	seconds_left = VOTE_DURATION
	_emit_event(&"shop_opened", [offers.duplicate(true)])
	_broadcast_state()

func vote(peer_id: int, offer_id: StringName) -> bool:
	if not active or not offers.has(offer_id):
		return false
	votes[peer_id] = offer_id
	_emit_event(&"shop_vote_changed", [peer_id, offer_id])
	return true


@rpc("any_peer", "call_local", "reliable")
func request_open_shop() -> void:
	if not _is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if not active:
		var crew: Node = _crew()
		if crew != null:
			open_shop(crew.SUPPLIES)
	elif sender_id > 0:
		_send_state(sender_id)


@rpc("any_peer", "call_local", "reliable")
func request_vote(offer_id: StringName) -> bool:
	if not _is_host():
		return false
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender_id if sender_id != 0 else _local_peer_id()
	if peer_id <= 0 or (_is_online() and not _connected_peers().has(peer_id)):
		return false
	if not vote(peer_id, offer_id):
		return false
	if not timer_started:
		timer_started = true
		seconds_left = VOTE_DURATION
	_broadcast_state()
	if _everyone_voted(_connected_peers()):
		finish_vote(_connected_peers())
	return true


## Pure selection: purchasing remains the depot's responsibility, so asking
## for the winner can never charge the shared wallet a second time.
func resolve_winner(peers: Array) -> StringName:
	if not active:
		return &""
	var counts: Dictionary = {}
	for peer: Variant in peers:
		var offer: StringName = votes.get(int(peer), &"")
		if offers.has(offer):
			counts[offer] = int(counts.get(offer, 0)) + 1
	var winner: StringName = &""
	var best_votes: int = 0
	var best_cost: int = 0
	for offer: StringName in counts:
		var count: int = int(counts[offer])
		var cost: int = int((offers[offer] as Dictionary).get("cost", 0))
		if count > best_votes or (count == best_votes and (winner.is_empty() or cost < best_cost)):
			winner = offer
			best_votes = count
			best_cost = cost
	return winner


func finish_vote(peers: Array) -> StringName:
	if not active:
		return &""
	var winner: StringName = resolve_winner(peers)
	var offer: Dictionary = (offers.get(winner, {}) as Dictionary).duplicate(true)
	active = false
	timer_started = false
	_emit_event(&"shop_resolved", [winner, offer])
	_broadcast_resolution(winner, offer)
	return winner


func resolve(peers: Array) -> StringName:
	return _buy(resolve_winner(peers))

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
	timer_started = false
	seconds_left = VOTE_DURATION
	_emit_event(&"shop_vote_changed", [peer_id, &""])
	return true


@rpc("any_peer", "call_local", "reliable")
func request_revote() -> bool:
	if not _is_host():
		return false
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender_id if sender_id != 0 else _local_peer_id()
	if not use_revote(peer_id):
		return false
	_broadcast_state()
	return true


## Discount closes the vote on its current leader. The depot receives the
## marker in shop_resolved and performs the already-authoritative discounted
## purchase; the card is only consumed if that purchase succeeds.
@rpc("any_peer", "call_local", "reliable")
func request_discount(offer_id: StringName) -> bool:
	if not _is_host() or not active:
		return false
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender_id if sender_id != 0 else _local_peer_id()
	var crew: Node = _crew()
	if crew == null or not crew.has_card(peer_id, crew.Card.DISCOUNT):
		return false
	if offer_id != resolve_winner(_connected_peers()):
		return false
	var offer: Dictionary = (offers[offer_id] as Dictionary).duplicate(true)
	offer["discounted"] = true
	offer["discount_peer"] = peer_id
	active = false
	timer_started = false
	_emit_event(&"shop_resolved", [offer_id, offer])
	_broadcast_resolution(offer_id, offer)
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


func _everyone_voted(peers: Array) -> bool:
	if peers.is_empty():
		return false
	for peer: Variant in peers:
		if not votes.has(int(peer)):
			return false
	return true


func _connected_peers() -> Array:
	var network: Node = _network()
	return (network.get(&"peer_ids") as Array).duplicate() if network != null else [1]


func _local_peer_id() -> int:
	var network: Node = _network()
	return int(network.call(&"local_id")) if network != null else 1


func _is_online() -> bool:
	var network: Node = _network()
	return network != null and bool(network.call(&"is_online"))


func _is_host() -> bool:
	var network: Node = _network()
	return network == null or bool(network.call(&"is_host"))


func _network() -> Node:
	return get_node_or_null(^"/root/NetworkManager") if is_inside_tree() else null


func _broadcast_state() -> void:
	if _is_online() and _is_host():
		_sync_state.rpc(offers, votes, active, timer_started, seconds_left)


func _send_state(peer_id: int) -> void:
	if _is_online() and _is_host():
		_sync_state.rpc_id(peer_id, offers, votes, active, timer_started, seconds_left)


@rpc("authority", "call_remote", "reliable")
func _sync_state(new_offers: Dictionary, new_votes: Dictionary, is_active: bool, has_timer: bool, remaining: float) -> void:
	offers = new_offers.duplicate(true)
	votes = new_votes.duplicate(true)
	active = is_active
	timer_started = has_timer
	seconds_left = remaining
	_emit_event(&"shop_opened", [offers.duplicate(true)])


func _broadcast_resolution(offer_id: StringName, offer: Dictionary) -> void:
	if _is_online() and _is_host():
		_sync_resolution.rpc(offer_id, offer)


@rpc("authority", "call_remote", "reliable")
func _sync_resolution(offer_id: StringName, offer: Dictionary) -> void:
	active = false
	timer_started = false
	_emit_event(&"shop_resolved", [offer_id, offer.duplicate(true)])


func _on_run_started(_route_id: StringName, _players: Array) -> void:
	_reset_vote()


func _on_run_ended(_score: int, _results: Dictionary) -> void:
	_reset_vote()


func _reset_vote() -> void:
	active = false
	timer_started = false
	seconds_left = VOTE_DURATION
	votes.clear()
	offers.clear()


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

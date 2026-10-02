extends CoopVote
## Take My Package's shop vote on the coop_vote module's CoopVote
## (docs/modulos.md): the module runs the vote and mirrors it to every
## peer; this file is the depot's supplies as the offers, the shared wallet
## (CrewProgression) as the purse, the crew's cards (priority, revote,
## discount, information) and the EventBus signals the UI listens to.
## Purchasing remains the depot's responsibility, except for the accessory
## shelf (N-923.3): its offers (AccessoryOffers, one per accessory and buyer) are
## settled here, on the host, when the vote closes on one: a single
## CrewProgression.buy_accessory() charges the team and grants the accessory to
## the offer's buyer, or charges nothing. A service stop's accessory offers
## (venue) are settled by that stop.

var crew_progression: Node
var event_bus: Node


func _ready() -> void:
	session = get_node_or_null(^"/root/NetworkManager") as NetSession
	opened.connect(func(new_offers: Dictionary) -> void: _emit_event(&"shop_opened", [new_offers]))
	vote_changed.connect(
		func(peer_id: int, offer_id: StringName) -> void: _emit_event(&"shop_vote_changed", [peer_id, offer_id]))
	resolved.connect(
		func(offer_id: StringName, offer: Dictionary) -> void: _emit_event(&"shop_resolved", [offer_id, offer]))
	resolved.connect(_settle_accessory_on_close)
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
	# An accessory nobody can have (or the team can't pay) must not eat the card.
	if _is_accessory_offer(offer_id) and not accessory_block(offers[offer_id]).is_empty():
		return &""
	if crew == null or not crew.consume_card(peer_id, crew.Card.PRIORITY):
		return &""
	# A venue's offer (a service stop, N-110) is paid by that venue when it
	# hears shop_resolved: closing on it, not buying here, charges it once.
	if _has_venue(offer_id):
		close_on(offer_id, offers[offer_id])
		return offer_id
	return buy(offer_id)


## An accessory offer is settled when the vote closes on it (never here, so the
## wallet is touched once and only if the grant works): a priority card, a
## discount or the vote itself all end in close_on(). `&""` if it can't be bought.
func buy(offer_id: StringName) -> StringName:
	if not _is_accessory_offer(offer_id):
		return super.buy(offer_id)
	var offer: Dictionary = offers[offer_id]
	if not accessory_block(offer).is_empty():
		return &""
	close_on(offer_id, offer)
	return offer_id


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
	if not is_host() or not active or not RpcGuard.allow_request(self) or not RpcGuard.name_ok(offer_id):
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
	# A venue charges its own offers, and spends the card itself (half price);
	# so does the accessory shelf, which only uses the card if the grant works.
	if _has_venue(offer_id) or _is_accessory_offer(offer_id):
		if not crew.has_card(peer_id, crew.Card.DISCOUNT):
			return &""
		var marked: Dictionary = (offers[offer_id] as Dictionary).duplicate(true)
		marked["discounted"] = true
		marked["discount_peer"] = peer_id
		close_on(offer_id, marked)
		return offer_id
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


## Whether an offer belongs to a venue that buys it itself (its "venue" key).
func _has_venue(offer_id: StringName) -> bool:
	return not String((offers.get(offer_id, {}) as Dictionary).get("venue", "")).is_empty()


## The depot's counter: the supplies and the accessory shelf (one row per
## connected player as buyer).
func _default_offers() -> Dictionary:
	var crew: Node = _crew()
	var result: Dictionary = (crew.SUPPLIES as Dictionary).duplicate(true) if crew != null else {}
	result.merge(AccessoryOffers.build(connected_peers()), true)
	return result


func _is_accessory_offer(offer_id: StringName) -> bool:
	return AccessoryOffers.is_offer(offers.get(offer_id))


## Why `offer` (an accessory offer) can't be bought now: "" when it can, else
## the reason (see CrewProgression.buy_accessory; "no_money" included). Reads
## only: nothing is charged.
func accessory_block(offer: Dictionary) -> String:
	var crew: Node = _crew()
	if crew == null or not AccessoryOffers.is_offer(offer):
		return "unknown"
	var color: String = crew.player_color_key(int(offer.get("buyer", 0)))
	var reason: StringName = AccessoryOffers.block_reason(
			crew.accessories, color, StringName(offer["accessory"]))
	if reason != &"":
		return String(reason)
	if int(offer.get("cost", 0)) > int(crew.team_money):
		return "no_money"
	return ""


## Host-callable, no RPC (the network layer wraps it later): buys the accessory
## `offer` names for the offer's buyer and says what happened to the crew.
## `offer` may carry "discounted"/"discount_peer" (a Discount card closed the
## vote). Returns CrewProgression.buy_accessory()'s {ok, reason, cost}; a depot
## offer is refused while a run is on or its results are up, like the supplies.
func settle_accessory_offer(offer: Dictionary) -> Dictionary:
	var crew: Node = _crew()
	if crew == null or not is_host() or not AccessoryOffers.is_offer(offer):
		return {"ok": false, "reason": &"unknown", "cost": 0}
	var accessory: StringName = StringName(offer["accessory"])
	var peer: int = int(offer.get("buyer", 0))
	if String(offer.get("venue", "")).is_empty() and _run_blocks_depot():
		return {"ok": false, "reason": &"closed", "cost": AccessoryOffers.cost(accessory)}
	var discount_peer: int = int(offer.get("discount_peer", 0)) if bool(offer.get("discounted", false)) else 0
	var result: Dictionary = crew.buy_accessory(
			crew.player_color_key(peer), accessory, float(offer.get("multiplier", 1.0)), discount_peer)
	_announce_accessory(result, accessory, peer, crew)
	return result


func _settle_accessory_on_close(offer_id: StringName, offer: Dictionary) -> void:
	if offer_id.is_empty() or not is_host() or not AccessoryOffers.is_offer(offer):
		return
	if not String(offer.get("venue", "")).is_empty():
		return # the service stop settles its own
	settle_accessory_offer(offer)


## The line the crew reads about the money: what was bought for whom, or why not.
func _announce_accessory(result: Dictionary, accessory: StringName, peer: int, crew: Node) -> void:
	var item_name: String = tr(AccessoryCatalog.title_key(accessory)).to_lower()
	var cost: int = int(result.get("cost", 0))
	var text: String
	match StringName(result.get("reason", &"")):
		&"":
			text = tr("UI_ACCESSORY_NOTICE_BOUGHT") % [item_name, crew.player_color_name(peer), cost]
		&"no_money":
			text = tr("UI_ACCESSORY_NOTICE_NO_MONEY") % [item_name, cost]
		&"owned", &"taken":
			text = tr("UI_ACCESSORY_NOTICE_TAKEN") % item_name
		&"no_card":
			text = tr("UI_ACCESSORY_NOTICE_NO_CARD")
		_:
			return
	var bus: Node = event_bus
	if bus == null and is_inside_tree():
		bus = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_method(&"relay"):
		bus.call(&"relay", &"depot_notice", [text])


## The depot's counter shuts while a run is on or its results are showing
## (Depot.request_supply does the same for supplies).
func _run_blocks_depot() -> bool:
	var manager: Node = get_node_or_null(^"/root/RunManager") if is_inside_tree() else null
	if manager == null:
		return false
	return bool(manager.get(&"is_running")) or not (manager.get(&"results") as Dictionary).is_empty()


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

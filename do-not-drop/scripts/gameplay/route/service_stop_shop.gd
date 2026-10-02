extends Node
class_name ServiceStopShop
## What a service station's counter sells (tareas de Nacho N-110): the shared
## repair kit topped up (RunManager.care_supplies: tape, repair, filler, rag,
## strap, the toy hen) and the truck's spare part, which fixes an active fault
## on the spot (VehicleFaults). Paid with the team's money, a bit dearer than
## the depot's counter (PRICE_MARKUP).
##
## It reuses the depot's purchase flow instead of a new one: the offers go to
## ShopVoteManager, the crew votes there exactly as at the depot (one player
## buys straight away), and the depot panel (DepotPanel, station &"service")
## shows them. What differs is where the winning offer is bought: ShopVoteManager
## only selects, and this node -- on the host -- charges CrewProgression and
## applies the item, for offers stamped with its own VENUE and stop key. The
## depot's panel leaves those offers alone.
##
## Stopping is a decision, not a free breather: nothing here pauses the run.
## RunManager.elapsed_seconds and the deadlines (plan_deadlines) keep running
## while the crew shops, so the time the vote and the walk take is spent.
##
## Autoloads are looked up by path, not by name: this script is loaded through
## a chain that a test may compile before the autoloads exist.

## Stamped on every offer, so the depot panel and other stops leave them alone.
const VENUE: StringName = &"service_stop"
## Road prices over the depot's: the depot's spare part is $100, here $140.
const PRICE_MARKUP: float = 1.4
const SPARE: StringName = &"spare_part"
## What one unit of each kit item would be worth at the depot's prices (on the
## scale N-227.2 set: a delivery pays 300-450); a refill is what's missing (up
## to the kit a run starts with) times this times the markup. A full tape
## refill, the commonest, is ~$100: one house's pay buys the crew one or two.
const KIT_UNIT_COST: Dictionary = {
	&"tape": 24, &"repair": 48, &"filler": 32, &"rag": 24, &"strap": 32, &"substitute": 80,
}
## In the order the panel lists them (all in strings_ui.csv).
const ITEMS: Array[StringName] = [&"tape", &"repair", &"filler", &"rag", &"strap", &"substitute", SPARE]
const TEXTS: Dictionary = {
	&"tape": {"title": "UI_SERVICE_TAPE", "detail": "UI_SERVICE_TAPE_DETAIL"},
	&"repair": {"title": "UI_SERVICE_REPAIR", "detail": "UI_SERVICE_REPAIR_DETAIL"},
	&"filler": {"title": "UI_SERVICE_FILLER", "detail": "UI_SERVICE_FILLER_DETAIL"},
	&"rag": {"title": "UI_SERVICE_RAG", "detail": "UI_SERVICE_RAG_DETAIL"},
	&"strap": {"title": "UI_SERVICE_STRAP", "detail": "UI_SERVICE_STRAP_DETAIL"},
	&"substitute": {"title": "UI_SERVICE_SUBSTITUTE", "detail": "UI_SERVICE_SUBSTITUTE_DETAIL"},
	SPARE: {"title": "UI_SUPPLY_SPARE_PART", "detail": "UI_SERVICE_SPARE_DETAIL"},
}
## Faults a spare part can fix, in the order it fixes them.
const FAULT_ORDER: Array[StringName] = [&"rear_door", &"mirror"]

## For the depot panel (it treats this node as its "depot"): the team's money
## and the offers that can't be bought right now (kit already full, a spare
## already aboard), as the host last reported them.
var team_money: int = 0
var supplies: Array = []
## The stop's own name (its segment's), stamped on the offers it opens.
var stop_key: String = ""
## How near the counter a player has to be (or the truck in the lay-by) for
## the crew to count as shopping here: the vote opens again after a purchase
## only then, and the host closes it once nobody is.
const CREW_REACH: float = 12.0
## How often the host looks whether the crew is still at the station.
const WATCH_SECONDS: float = 0.5
var _watch: float = 0.0


func _ready() -> void:
	stop_key = String(get_parent().get_parent().name) if get_parent() != null and get_parent().get_parent() != null \
			else String(name)
	add_to_group(&"service_shop")
	var bus: Node = _autoload(&"EventBus")
	if bus != null:
		bus.connect(&"shop_resolved", _on_shop_resolved)
	refresh_state()


## Host, online: a vote on this stop's offers closes on nothing once the crew
## has left (the truck out of the lay-by and nobody near the counter), so the
## kit can't be bought from kilometres down the road.
func _process(delta: float) -> void:
	_watch += delta
	if _watch < WATCH_SECONDS:
		return
	_watch = 0.0
	if _is_host() and _is_online() and vote_is_mine() and not crew_at_station():
		_autoload(&"ShopVoteManager").call(&"close_on", &"", {})


## Whether the crew's vote is open on this stop's offers.
func vote_is_mine() -> bool:
	var votes: Node = _autoload(&"ShopVoteManager")
	if votes == null or not bool(votes.get(&"active")):
		return false
	for offer: Variant in (votes.get(&"offers") as Dictionary).values():
		if offer is Dictionary and offer.get("venue") == VENUE and offer.get("stop") == stop_key:
			return true
	return false


## Whether the crew is shopping here: the truck in the lay-by or a player
## within CREW_REACH of the counter.
func crew_at_station() -> bool:
	var stop: Node = get_parent()
	var truck: Node3D = get_tree().get_first_node_in_group(&"vehicle") as Node3D
	if stop != null and truck != null and bool(stop.call(&"in_bay", truck.global_position)):
		return true
	var counter: Node3D = _counter()
	if counter == null:
		return false
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		if player is Node3D and (player as Node3D).global_position.distance_to(counter.global_position) <= CREW_REACH:
			return true
	return false


## Whether this peer's own player has walked away from the counter (further
## than `reach`): its open panel closes then.
func local_player_away(reach: float) -> bool:
	var counter: Node3D = _counter()
	if counter == null or not counter.has_method(&"local_player"):
		return false
	var player: Node3D = counter.call(&"local_player") as Node3D
	return player != null and player.global_position.distance_to(counter.global_position) > reach


## Every offer, id -> {title, detail, cost, venue, stop, amount}: the cost is
## what buying it now would charge (a refill of what's missing), or one unit's
## price for something that can't be bought now. Same on every peer, from the
## synced kit and spares.
func offers() -> Dictionary:
	var result: Dictionary = {}
	var start: Dictionary = _kit_start()
	for id: StringName in ITEMS:
		var amount: int = 1
		var unit: float = float(_spare_cost())
		if id != SPARE:
			amount = maxi(int(start.get(id, 0)) - _kit_count(id), 0)
			unit = float(KIT_UNIT_COST[id]) * PRICE_MARKUP
		result[id] = {
			"title": TEXTS[id]["title"], "detail": TEXTS[id]["detail"], "venue": VENUE, "stop": stop_key,
			"amount": amount, "cost": roundi(unit * maxi(amount, 1)),
		}
	return result


## What the depot charges for the spare part, with the road's markup.
func _spare_cost() -> int:
	var crew: Node = _autoload(&"CrewProgression")
	var base: int = int((crew.get(&"SUPPLIES") as Dictionary)[SPARE]["cost"]) if crew != null else 100
	return roundi(base * PRICE_MARKUP)


## Ids that can't be bought: a kit item at its starting stock, a spare part
## when one is already aboard.
func unavailable() -> Array:
	var blocked: Array = []
	var start: Dictionary = _kit_start()
	for id: StringName in ITEMS:
		if id == SPARE:
			if _spares() >= 1:
				blocked.append(id)
		elif _kit_count(id) >= int(start.get(id, 0)):
			blocked.append(id)
	return blocked


# --- The depot panel's interface (the same calls it makes on the Depot) --------------


## Any peer's panel asks for a purchase; only the host's answer counts.
func buy_supply(supply_id: StringName) -> bool:
	return _purchase(supply_id, 0)


## The panel's discount button, solo: half price with the local player's card.
func buy_supply_discounted(supply_id: StringName) -> bool:
	var network: Node = _autoload(&"NetworkManager")
	return _purchase(supply_id, int(network.call(&"local_id")) if network != null else 1)


## Host, as player `peer` uses the counter: everyone gets the fresh money and
## availability (the panel opens on the next message), and online the crew's
## vote opens on these offers -- unless it is already open on them: then only
## `peer` is sent its state, so a second player at the counter (or a late
## joiner) never wipes the votes cast or restarts the clock.
func open_for_crew(peer: int = 0) -> void:
	if not _is_host():
		return
	refresh_state()
	_broadcast()
	if not _is_online():
		return
	var votes: Node = _autoload(&"ShopVoteManager")
	if votes == null:
		return
	if not vote_is_mine():
		votes.call(&"open_shop", offers())
	elif peer > 0:
		votes.call(&"send_state_to", peer)


## The panel's hint under the title.
func hint_key() -> String:
	return "UI_SERVICE_HINT"


# --- Buying (host) ----------------------------------------------------------------------


## Charges the team and hands over the item. `discount_peer` is the player whose
## Discount card pays half (0 for none). False, and nothing charged, when the
## run isn't on, the offer is unknown or can't be bought, or the money or the
## card isn't there.
func _purchase(id: StringName, discount_peer: int) -> bool:
	var crew: Node = _autoload(&"CrewProgression")
	if not _is_host() or crew == null or not _run_going() or unavailable().has(id):
		return false
	var offer: Dictionary = offers().get(id, {})
	if offer.is_empty():
		return false
	var cost: int = int(offer["cost"])
	var card: int = int((crew.get(&"Card") as Dictionary)["DISCOUNT"])
	if discount_peer > 0:
		if not bool(crew.call(&"has_card", discount_peer, card)):
			return false
		cost = maxi(0, roundi(cost * 0.5))
	if not bool(crew.call(&"spend", cost)):
		_notice(tr("WORLD_SERVICE_NOTICE_NO_MONEY") % [tr(String(offer["title"])).to_lower(), cost])
		return false
	if discount_peer > 0:
		crew.call(&"consume_card", discount_peer, card)
	var fixed: bool = _hand_over(id, int(offer["amount"]))
	_notice(tr("WORLD_SERVICE_NOTICE_BOUGHT") % [tr(String(offer["title"])).to_lower(), cost])
	if fixed:
		_notice(tr("WORLD_SERVICE_NOTICE_FIXED"))
	refresh_state()
	_broadcast()
	return true


## The item itself: a kit refill, or a spare part (which fixes an active fault
## right away). Returns whether it fixed one.
func _hand_over(id: StringName, amount: int) -> bool:
	if id != SPARE:
		var manager: Node = _autoload(&"RunManager")
		if manager != null:
			manager.call(&"consume_care_supply", id, -amount)
		return false
	var faults: Node = get_tree().get_first_node_in_group(&"vehicle_faults")
	if faults == null:
		return false
	faults.call(&"stock_spares", _spares() + 1)
	for fault_id: StringName in FAULT_ORDER:
		if bool(faults.call(&"is_broken", fault_id)):
			return bool(faults.call(&"repair", fault_id, &"spare"))
	return false


## The crew's vote closed on one of this stop's offers: the host buys it (with
## the winner's card if one was used to close it). Then the vote opens again on
## the new state, so the crew can go on shopping.
func _on_shop_resolved(offer_id: StringName, offer: Dictionary) -> void:
	if not _is_host() or offer_id.is_empty() or offer.get("venue") != VENUE or offer.get("stop") != stop_key:
		return
	_purchase(offer_id, int(offer.get("discount_peer", 0)) if bool(offer.get("discounted", false)) else 0)
	if _is_online():
		_reopen_vote.call_deferred()


func _reopen_vote() -> void:
	var votes: Node = _autoload(&"ShopVoteManager")
	if votes != null and not bool(votes.get(&"active")) and _run_going() and crew_at_station():
		votes.call(&"open_shop", offers())


## The station goes (Endless culls it behind the truck): a vote still open on
## its offers closes on nothing, on every peer, so nobody votes on a shop that
## is no longer there. Only when its segment is culled: when the whole level
## goes, the vote goes with the run and nothing is sent.
func _exit_tree() -> void:
	var segment: Node = get_parent().get_parent() if get_parent() != null else null
	if segment == null or not segment.is_queued_for_deletion():
		return
	if _is_host() and _run_going() and vote_is_mine():
		_autoload(&"ShopVoteManager").call(&"close_on", &"", {})


# --- State everyone shows --------------------------------------------------------------------


## Host: recomputes what the panel shows.
func refresh_state() -> void:
	var crew: Node = _autoload(&"CrewProgression")
	team_money = int(crew.get(&"team_money")) if crew != null else 0
	supplies = unavailable()


## To every peer whose level is up: one still loading the route has no such
## node yet, and gets the state when it next opens the counter.
func _broadcast() -> void:
	_apply_state(supplies, team_money)
	if not _is_online():
		return
	var network: Node = _autoload(&"NetworkManager")
	for peer: Variant in network.get(&"peer_ids"):
		var id: int = int(peer)
		if id != multiplayer.get_unique_id() and bool(network.call(&"is_peer_ready", id)):
			_receive_state.rpc_id(id, supplies, team_money)


@rpc("authority", "call_remote", "reliable")
func _receive_state(blocked: Array, money: int) -> void:
	_apply_state(blocked, money)


func _apply_state(blocked: Array, money: int) -> void:
	supplies = blocked
	team_money = money
	var bus: Node = _autoload(&"EventBus")
	if bus == null:
		return
	if not _is_host():
		bus.emit_signal(&"team_money_changed", money)
	bus.emit_signal(&"depot_supplies_changed", blocked.duplicate(), money)


# --- Helpers ---------------------------------------------------------------------------------------


func _kit_count(id: StringName) -> int:
	var manager: Node = _autoload(&"RunManager")
	return int(manager.call(&"care_supply_count", id)) if manager != null else 0


## The kit a run starts with: a refill never goes past it.
func _kit_start() -> Dictionary:
	var manager: Node = _autoload(&"RunManager")
	return manager.get(&"CARE_SUPPLIES_START") if manager != null else {}


func _spares() -> int:
	var faults: Node = get_tree().get_first_node_in_group(&"vehicle_faults") if is_inside_tree() else null
	return int(faults.get(&"spares")) if faults != null else 0


func _run_going() -> bool:
	var manager: Node = _autoload(&"RunManager")
	return manager != null and bool(manager.get(&"is_running"))


func _notice(text: String) -> void:
	var bus: Node = _autoload(&"EventBus")
	if bus != null:
		bus.call(&"relay", &"depot_notice", [text])


func _is_online() -> bool:
	var network: Node = _autoload(&"NetworkManager")
	return network != null and bool(network.call(&"is_online"))


func _is_host() -> bool:
	var network: Node = _autoload(&"NetworkManager")
	return network == null or bool(network.call(&"is_host"))


func _counter() -> Node3D:
	var stop: Node = get_parent()
	return stop.get(&"counter") as Node3D if stop != null else null


func _autoload(autoload_name: StringName) -> Node:
	return get_node_or_null(NodePath("/root/%s" % autoload_name)) if is_inside_tree() else null

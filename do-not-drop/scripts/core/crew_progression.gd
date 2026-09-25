extends Node
## Shared money and individual merit/cards. Host owns the mutable state; the
## UI can treat the signals as a compact shop/vote model.

const STARTING_MONEY: int = 100
const MAX_CARD_PER_PLAYER: int = 1
const BASE_CARD_CHANCE: float = 0.20
const MERIT_CARD_BONUS: float = 0.01
const PITY_DELIVERIES: int = 3
const MERIT_POINTS := {
	&"defused": 25,
	&"rescued": 20,
	&"calmed": 10,
	&"dried": 10,
	&"leveled": 8,
	&"sequence": 8,
	&"handover": 5,
	&"photo_saved": 15,
}

enum Card { PRIORITY, REVOTE, DISCOUNT, RESCUE, INFORMATION }

## What the depot's supplies counter sells (depot.gd): bought with team money
## before a run and used up by the next delivery that leaves the depot.
## "cost" in team money; the effect lives where it applies (see depot.gd).
const SUPPLIES := {
	&"padding": {"title": "Acolchado de estantes", "detail": "Espuma en el rack: la carga sufre un 25 % menos por golpes en el próximo reparto.", "cost": 40},
	&"insurance": {"title": "Seguro de envío", "detail": "Cada paquete que se entregue roto en el próximo reparto le devuelve $30 al equipo.", "cost": 35},
}

var team_money: int = STARTING_MONEY
var merit: Dictionary = {} # peer id -> points
var cards: Dictionary = {} # peer id -> Card
var dry_deliveries: Dictionary = {}
var _credited_actions: Dictionary = {}
var event_bus: Node
var priority_issued: bool = false
## Supplies bought and waiting in the depot for the next run: id -> true.
var supplies: Dictionary = {}


func _ready() -> void:
	var bus: Node = event_bus if event_bus != null else get_node_or_null(^"/root/EventBus")
	if bus != null and bus.has_signal(&"delivery_photo_taken") \
			and not bus.is_connected(&"delivery_photo_taken", _on_delivery_photo_taken):
		bus.connect(&"delivery_photo_taken", _on_delivery_photo_taken)


func reset_campaign() -> void:
	team_money = STARTING_MONEY
	merit.clear()
	cards.clear()
	dry_deliveries.clear()
	_credited_actions.clear()
	priority_issued = false
	supplies.clear()
	_emit_event(&"team_money_changed", [team_money])


func award_action(peer_id: int, action_id: StringName, points: int) -> bool:
	if peer_id <= 0 or points <= 0 or _credited_actions.has(action_id):
		return false
	_credited_actions[action_id] = peer_id
	merit[peer_id] = int(merit.get(peer_id, 0)) + points
	_emit_event(&"merit_changed", [peer_id, int(merit[peer_id])])
	return true


## Turns a package fact into the stable action id used for deduplication.
## occurrence belongs to that package and milestone, so separate real saves
## can score while a repeated report of the same one cannot.
func award_milestone(peer_id: int, package_id: StringName, milestone: StringName, occurrence: int) -> bool:
	if package_id.is_empty() or not MERIT_POINTS.has(milestone) or occurrence <= 0:
		return false
	var action_id := StringName("%s:%s:%d" % [package_id, milestone, occurrence])
	return award_action(peer_id, action_id, int(MERIT_POINTS[milestone]))


func award_delivery(results: Dictionary, peers: Array) -> void:
	var payout: int = int(results.get("cargo_points", 0)) + int(results.get("time_bonus", 0))
	team_money += maxi(payout, 0)
	_credited_actions.clear()
	_emit_event(&"team_money_changed", [team_money])
	for peer: Variant in peers:
		_grant_card_chance(int(peer))


func spend(cost: int) -> bool:
	if cost < 0 or cost > team_money:
		return false
	team_money -= cost
	_emit_event(&"team_money_changed", [team_money])
	return true


## Host-only. One of each supply at a time: it's a kit for the next run,
## not a stockpile.
func buy_supply(supply_id: StringName) -> bool:
	if not SUPPLIES.has(supply_id) or supplies.has(supply_id):
		return false
	if not spend(int(SUPPLIES[supply_id]["cost"])):
		return false
	supplies[supply_id] = true
	return true


## Hands the waiting supplies to the run that's leaving, and clears them.
func take_supplies() -> Array[StringName]:
	var taken: Array[StringName] = []
	for supply_id: StringName in supplies:
		taken.append(supply_id)
	supplies.clear()
	return taken


func add_team_money(amount: int) -> void:
	if amount <= 0:
		return
	team_money += amount
	_emit_event(&"team_money_changed", [team_money])


func has_card(peer_id: int, card: Card) -> bool:
	return int(cards.get(peer_id, -1)) == card


func consume_card(peer_id: int, card: Card) -> bool:
	if not has_card(peer_id, card):
		return false
	cards.erase(peer_id)
	_emit_event(&"card_changed", [peer_id, -1])
	return true


func _grant_card_chance(peer_id: int) -> void:
	if peer_id <= 0 or cards.has(peer_id):
		return
	var chance: float = BASE_CARD_CHANCE + float(merit.get(peer_id, 0)) * MERIT_CARD_BONUS + float(dry_deliveries.get(peer_id, 0)) * 0.20
	if int(dry_deliveries.get(peer_id, 0)) >= PITY_DELIVERIES or randf() < minf(chance, 1.0):
		var possible_cards: Array = Card.values()
		if priority_issued:
			possible_cards.erase(Card.PRIORITY)
		cards[peer_id] = possible_cards.pick_random()
		if int(cards[peer_id]) == Card.PRIORITY:
			priority_issued = true
		dry_deliveries[peer_id] = 0
		_emit_event(&"card_changed", [peer_id, int(cards[peer_id])])
	else:
		dry_deliveries[peer_id] = int(dry_deliveries.get(peer_id, 0)) + 1


func _emit_event(signal_name: StringName, arguments: Array) -> void:
	var bus: Node = event_bus
	if bus == null and is_inside_tree():
		bus = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(signal_name):
		if signal_name in [&"merit_changed", &"card_changed"] and bus.has_method(&"relay"):
			bus.call(&"relay", signal_name, arguments)
		else:
			var payload: Array = [signal_name]
			payload.append_array(arguments)
			bus.callv(&"emit_signal", payload)


func _on_delivery_photo_taken(_house_index: int, accepted: bool) -> void:
	if not accepted:
		return
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network != null and not bool(network.call(&"is_host")):
		return
	var run: Node = get_node_or_null(^"/root/RunManager")
	if run == null:
		return
	var peer_id: int = int(run.get(&"last_photo_peer_id"))
	var package_id := StringName(run.get(&"last_photo_package_id"))
	award_milestone(peer_id, package_id, &"photo_saved", 1)

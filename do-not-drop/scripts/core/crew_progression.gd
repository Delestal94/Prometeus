extends Node
## Shared money and individual merit/cards. Host owns the mutable state; the
## UI can treat the signals as a compact shop/vote model.

const STARTING_MONEY: int = 100
const CAMPAIGN_PATH: String = "user://crew_campaign.json"
const CAMPAIGN_VERSION: int = 1
const SAFE_JSON = preload("res://scripts/core/safe_json.gd")
## Player.PLAYER_COLORS uses peer_id modulo five in this same order.
const PLAYER_COLOR_KEYS: Array[String] = ["mint", "yellow", "coral", "sky", "violet"]
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

## Only these cards belong to the current playable loop. The other enum
## values stay reserved so old saves and the documented design keep stable
## ids, but a delivery can never draw them.
const DRAWABLE_CARDS := [Card.RESCUE, Card.DISCOUNT, Card.REVOTE]
const CARD_NAMES := {
	Card.RESCUE: "Rescate",
	Card.DISCOUNT: "Descuento",
	Card.REVOTE: "Re-voto",
	Card.PRIORITY: "Prioridad",
	Card.INFORMATION: "Información",
}

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
## Supplies bought and waiting in the depot for the next run: id -> true.
var supplies: Dictionary = {}
var campaign_path: String = CAMPAIGN_PATH
var _saved_players_by_color: Dictionary = {}
var _known_peers: Array[int] = []
var _using_host_campaign: bool = false


func _ready() -> void:
	if Engine.get_main_loop().get_script() != null:
		campaign_path = "user://test_crew_campaign.json"
	load_campaign()
	var bus: Node = event_bus if event_bus != null else get_node_or_null(^"/root/EventBus")
	if bus != null and bus.has_signal(&"delivery_photo_taken") \
			and not bus.is_connected(&"delivery_photo_taken", _on_delivery_photo_taken):
		bus.connect(&"delivery_photo_taken", _on_delivery_photo_taken)
	if bus != null and bus.has_signal(&"card_changed") \
			and not bus.is_connected(&"card_changed", _on_card_changed):
		bus.connect(&"card_changed", _on_card_changed)
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network != null and network.has_signal(&"roster_changed") \
			and not network.is_connected(&"roster_changed", _on_roster_changed):
		network.connect(&"roster_changed", _on_roster_changed)


func reset_campaign(persist: bool = false) -> bool:
	team_money = STARTING_MONEY
	merit.clear()
	cards.clear()
	dry_deliveries.clear()
	_credited_actions.clear()
	supplies.clear()
	_saved_players_by_color.clear()
	_known_peers.assign(_current_peers())
	_emit_event(&"team_money_changed", [team_money])
	if persist:
		return save_campaign()
	return true


func save_campaign() -> bool:
	if not _can_write_campaign():
		return false
	_capture_current_players()
	var saved: bool = SAFE_JSON.write(campaign_path, _campaign_data())
	if not saved:
		push_warning("No se pudo guardar la campaña: " + campaign_path)
		return false
	_broadcast_campaign()
	return true


func load_campaign() -> void:
	var data: Dictionary = SAFE_JSON.read(campaign_path, _default_campaign())
	_apply_campaign_data(data, true)


func player_color_key(peer_id: int) -> String:
	return PLAYER_COLOR_KEYS[posmod(peer_id, PLAYER_COLOR_KEYS.size())]


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
	save_campaign()


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
	save_campaign()
	return true


## Host-only discounted purchase. Validation happens before the card is
## consumed, so a sold-out or unaffordable item never wastes it.
func buy_supply_discounted(peer_id: int, supply_id: StringName) -> bool:
	if not SUPPLIES.has(supply_id) or supplies.has(supply_id) or not has_card(peer_id, Card.DISCOUNT):
		return false
	var cost: int = maxi(0, roundi(int(SUPPLIES[supply_id]["cost"]) * 0.5))
	if not spend(cost):
		return false
	supplies[supply_id] = true
	consume_card(peer_id, Card.DISCOUNT)
	return true


## Hands the waiting supplies to the run that's leaving, and clears them.
func take_supplies() -> Array[StringName]:
	var taken: Array[StringName] = []
	for supply_id: StringName in supplies:
		taken.append(supply_id)
	supplies.clear()
	save_campaign()
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
	save_campaign()
	return true


func card_name(card_id: int) -> String:
	return String(CARD_NAMES.get(card_id, "Carta"))


## Usable from anywhere during a run. Clients ask the host, which derives
## the peer from the RPC sender and lets RouteEventManager resolve the event.
@rpc("any_peer", "call_local", "reliable")
func request_use_card() -> bool:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network != null and bool(network.call(&"is_online")) and not bool(network.call(&"is_host")):
		return false
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender_id if sender_id != 0 else int(network.call(&"local_id")) if network != null else 1
	var held_card: int = int(cards.get(peer_id, -1))
	if held_card != Card.RESCUE:
		_send_card_notice(peer_id, "Esta carta se usa en el depósito" if held_card in [Card.DISCOUNT, Card.REVOTE] else "No tenés ninguna carta")
		return false
	var route_events: Node = get_node_or_null(^"/root/RouteEventManager")
	if route_events == null or StringName(route_events.get(&"active_event_id")).is_empty():
		_send_card_notice(peer_id, "No hay nada que rescatar")
		return false
	return bool(route_events.call(&"use_rescue", peer_id))


func _send_card_notice(peer_id: int, text: String) -> void:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network != null and bool(network.call(&"is_online")) and peer_id != int(network.call(&"local_id")):
		_receive_card_notice.rpc_id(peer_id, text)
	else:
		_receive_card_notice(text)


@rpc("authority", "call_remote", "reliable")
func _receive_card_notice(text: String) -> void:
	var bus: Node = event_bus if event_bus != null else get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.emit_signal(&"depot_notice", text)


func _grant_card_chance(peer_id: int) -> void:
	if peer_id <= 0 or cards.has(peer_id):
		return
	var chance: float = BASE_CARD_CHANCE + float(merit.get(peer_id, 0)) * MERIT_CARD_BONUS + float(dry_deliveries.get(peer_id, 0)) * 0.20
	if int(dry_deliveries.get(peer_id, 0)) >= PITY_DELIVERIES or randf() < minf(chance, 1.0):
		cards[peer_id] = DRAWABLE_CARDS.pick_random()
		dry_deliveries[peer_id] = 0
		_emit_event(&"card_changed", [peer_id, int(cards[peer_id])])
	else:
		dry_deliveries[peer_id] = int(dry_deliveries.get(peer_id, 0)) + 1


func _default_campaign() -> Dictionary:
	return {
		"version": CAMPAIGN_VERSION,
		"team_money": STARTING_MONEY,
		"supplies": [],
		"players": {},
	}


func _campaign_data() -> Dictionary:
	var supply_ids: Array[String] = []
	for supply_id: StringName in supplies:
		supply_ids.append(String(supply_id))
	return {
		"version": CAMPAIGN_VERSION,
		"team_money": team_money,
		"supplies": supply_ids,
		"players": _saved_players_by_color.duplicate(true),
	}


func _apply_campaign_data(data: Dictionary, remember_players: bool) -> void:
	team_money = maxi(int(data.get("team_money", STARTING_MONEY)), 0)
	supplies.clear()
	for raw_id: Variant in data.get("supplies", []):
		var supply_id := StringName(raw_id)
		if SUPPLIES.has(supply_id):
			supplies[supply_id] = true
	var normalized_players := _normalized_players(Dictionary(data.get("players", {})))
	if remember_players:
		_saved_players_by_color = normalized_players.duplicate(true)
	var old_peers: Array = merit.keys()
	for peer: Variant in cards:
		if not old_peers.has(peer):
			old_peers.append(peer)
	merit.clear()
	cards.clear()
	dry_deliveries.clear()
	var peers: Array[int] = _current_peers()
	for peer_id: int in peers:
		_apply_player_entry(peer_id, normalized_players)
	_known_peers.assign(peers)
	_emit_event(&"team_money_changed", [team_money])
	for old_peer: Variant in old_peers:
		if not peers.has(int(old_peer)):
			_emit_event(&"merit_changed", [int(old_peer), 0])
			_emit_event(&"card_changed", [int(old_peer), -1])
	for peer_id: int in peers:
		_emit_event(&"merit_changed", [peer_id, int(merit.get(peer_id, 0))])
		_emit_event(&"card_changed", [peer_id, int(cards.get(peer_id, -1))])


func _normalized_players(raw_players: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for color: String in PLAYER_COLOR_KEYS:
		var raw: Variant = raw_players.get(color, {})
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var card_id: int = int(entry.get("card", -1))
		normalized[color] = {
			"merit": maxi(int(entry.get("merit", 0)), 0),
			"card": card_id if card_id >= 0 and card_id < Card.size() else -1,
			"dry_deliveries": maxi(int(entry.get("dry_deliveries", 0)), 0),
		}
	return normalized


func _apply_player_entry(peer_id: int, players_by_color: Dictionary) -> void:
	var entry: Dictionary = players_by_color.get(player_color_key(peer_id), {})
	merit[peer_id] = maxi(int(entry.get("merit", 0)), 0)
	dry_deliveries[peer_id] = maxi(int(entry.get("dry_deliveries", 0)), 0)
	var card_id: int = int(entry.get("card", -1))
	if card_id >= 0 and card_id < Card.size():
		cards[peer_id] = card_id


func _apply_saved_player(peer_id: int) -> void:
	_apply_player_entry(peer_id, _saved_players_by_color)


func _capture_current_players() -> void:
	var peer_ids: Array = _current_peers()
	for source: Dictionary in [merit, cards, dry_deliveries]:
		for raw_peer: Variant in source:
			if not peer_ids.has(int(raw_peer)):
				peer_ids.append(int(raw_peer))
	for peer: Variant in peer_ids:
		_capture_player(int(peer))


func _capture_player(peer_id: int) -> void:
	_saved_players_by_color[player_color_key(peer_id)] = {
		"merit": maxi(int(merit.get(peer_id, 0)), 0),
		"card": int(cards.get(peer_id, -1)),
		"dry_deliveries": maxi(int(dry_deliveries.get(peer_id, 0)), 0),
	}


func _current_peers() -> Array[int]:
	var network: Node = get_node_or_null(^"/root/NetworkManager") if is_inside_tree() else null
	if network != null:
		var peers: Array[int] = []
		peers.assign(network.get(&"peer_ids"))
		return peers
	var peers: Array[int] = []
	for source: Dictionary in [merit, cards, dry_deliveries]:
		for raw_peer: Variant in source:
			var peer_id: int = int(raw_peer)
			if peer_id > 0 and not peers.has(peer_id):
				peers.append(peer_id)
	if peers.is_empty():
		peers.append(1)
	return peers


func _can_write_campaign() -> bool:
	var network: Node = get_node_or_null(^"/root/NetworkManager") if is_inside_tree() else null
	return network == null or not bool(network.call(&"is_online")) or bool(network.call(&"is_host"))


func _on_roster_changed(raw_peers: Array) -> void:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network == null:
		return
	if not bool(network.call(&"is_online")):
		if _using_host_campaign:
			_using_host_campaign = false
			load_campaign()
		return
	var peers: Array[int] = []
	peers.assign(raw_peers)
	if not bool(network.call(&"is_host")):
		_known_peers.assign(peers)
		return
	for old_peer: int in _known_peers:
		if not peers.has(old_peer):
			_capture_player(old_peer)
			merit.erase(old_peer)
			cards.erase(old_peer)
			dry_deliveries.erase(old_peer)
	for peer_id: int in peers:
		if not _known_peers.has(peer_id):
			_apply_saved_player(peer_id)
	_known_peers.assign(peers)
	_broadcast_campaign()


func _broadcast_campaign() -> void:
	var network: Node = get_node_or_null(^"/root/NetworkManager") if is_inside_tree() else null
	if network == null or not bool(network.call(&"is_online")) or not bool(network.call(&"is_host")):
		return
	_capture_current_players()
	_receive_campaign.rpc(_campaign_data())


@rpc("authority", "call_remote", "reliable")
func _receive_campaign(data: Dictionary) -> void:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network == null or bool(network.call(&"is_host")):
		return
	_using_host_campaign = true
	_apply_campaign_data(data, false)


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


func _on_card_changed(peer_id: int, card_id: int) -> void:
	if card_id < 0:
		cards.erase(peer_id)
	else:
		cards[peer_id] = card_id

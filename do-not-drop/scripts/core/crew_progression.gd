extends Node
## Shared money and individual merit/cards. Host owns the mutable state; the
## UI can treat the signals as a compact shop/vote model.

const STARTING_MONEY: int = 100
const CAMPAIGN_PATH: String = "user://crew_campaign.json"
## 2 (N-226.2): "players" is keyed by colour slot ("0".."7", PlayerColorSlot),
## not by colour name. A version-1 file (names, from peer_id modulo five) is
## migrated on load: LEGACY_COLOR_FOR_SLOT says which old name each slot takes.
const CAMPAIGN_VERSION: int = 2
const SAFE_JSON = preload("res://modules/persistence/safe_json.gd")
## Typed handles on the autoloads this file talks to (N-224): a renamed
## method or property fails when the script compiles, not mid-run.
const NETWORK_MANAGER := preload("res://scripts/core/network_manager.gd")
const RUN_MANAGER := preload("res://scripts/core/run_manager.gd")
const ROUTE_EVENT_MANAGER := preload("res://scripts/core/route_event_manager.gd")
## Player.PLAYER_COLORS has the same order: the colour of slot i is entry i.
## The slot comes from PlayerColorSlot (host 0, then arrival order), not from
## the peer id.
## Eight of them, one per seat of a full room (N-228.3).
const PLAYER_COLOR_KEYS: Array[String] = [
	"mint", "yellow", "coral", "sky", "violet", "white", "cobalt", "teal",
]
const PLAYER_COLOR_NAMES: Array[String] = [
	"UI_COLOR_MINT", "UI_COLOR_YELLOW", "UI_COLOR_CORAL", "UI_COLOR_SKY", "UI_COLOR_VIOLET",
	"UI_COLOR_WHITE", "UI_COLOR_COBALT", "UI_COLOR_TEAL",
]
## Version-1 saves named players by colour, and the host was always peer 1 =
## "yellow": it becomes slot 0, the host's slot, and "mint" (old 0) takes the
## old yellow's place, so every old entry lands on a different slot. Version 1
## only ever had five colours: slots 5..7 have no legacy entry and start clean.
const LEGACY_COLOR_FOR_SLOT: Array[String] = ["yellow", "mint", "coral", "sky", "violet"]
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
	&"assist": 5,
}

enum Card { PRIORITY, REVOTE, DISCOUNT, RESCUE, INFORMATION }

## Only these cards belong to the current playable loop. The other enum
## values stay reserved so old saves and the documented design keep stable
## ids, but a delivery can never draw them.
const DRAWABLE_CARDS := [Card.RESCUE, Card.DISCOUNT, Card.REVOTE]
const CARD_NAMES := {
	Card.RESCUE: "UI_CARD_RESCUE",
	Card.DISCOUNT: "UI_CARD_DISCOUNT",
	Card.REVOTE: "UI_CARD_REVOTE",
	Card.PRIORITY: "UI_CARD_PRIORITY",
	Card.INFORMATION: "UI_CARD_INFORMATION",
}

## What the depot's supplies counter sells (depot.gd): bought with team money
## before a run and used up by the next delivery that leaves the depot.
## "cost" in team money; the effect lives where it applies (see depot.gd).
## Prices (N-227.2): a typical delivery pays RunManager.POINTS_DELIVERED_INTACT
## x 2-3 houses = 300-450, plus deadlines (+40) and photos (+25). Mean price is
## 130 (100..160), so one delivery buys a mid-price item plus a cheap one, and
## the whole shelf (520) takes about two. Before, prices were 25..40 against a
## payout that never really reached the wallet; the old ratio was kept (x4).
const SUPPLIES := {
	&"padding": {"title": "UI_SUPPLY_PADDING", "detail": "UI_SUPPLY_PADDING_DETAIL", "cost": 160},
	&"insurance": {"title": "UI_SUPPLY_INSURANCE", "detail": "UI_SUPPLY_INSURANCE_DETAIL", "cost": 140},
	&"rescue_hook": {
		"title": "UI_SUPPLY_RESCUE_HOOK",
		"detail": "UI_SUPPLY_RESCUE_HOOK_DETAIL",
		"cost": 120,
	},
	&"spare_part": {
		"title": "UI_SUPPLY_SPARE_PART",
		"detail": "UI_SUPPLY_SPARE_PART_DETAIL",
		"cost": 100,
	},
	&"tow_strap": {
		"title": "UI_SUPPLY_TOW_STRAP",
		"detail": "UI_SUPPLY_TOW_STRAP_DETAIL",
		"cost": 30,
	},
}

var team_money: int = STARTING_MONEY
var merit: Dictionary = {} # peer id -> points
var cards: Dictionary = {} # peer id -> Card
var dry_deliveries: Dictionary = {}
var _credited_actions: Dictionary = {}
## Current-run merit is separate from the campaign total: it drives the
## results awards without changing how persistent merit or cards work.
var _run_merit: Dictionary = {}
var _run_milestones: Dictionary = {}
var event_bus: Node
## Supplies bought and waiting in the depot for the next run: id -> true.
var supplies: Dictionary = {}
var campaign_path: String = CAMPAIGN_PATH
## Saved progress by colour slot: slot (int) -> {merit, card, dry_deliveries}.
var _saved_players_by_slot: Dictionary = {}
var _known_peers: Array[int] = []
## The slot each known peer wore when the roster last changed. The network
## frees a leaver's slot before the roster says so, so its progress is saved
## under this, not under whatever the peer would read as by then.
var _known_slots: Dictionary = {}
## The last campaign the host sent, kept to read it again if this client's
## slot map changes after it (the map and the campaign travel separately).
var _last_host_data: Dictionary = {}
## Host: campaign entries a newcomer pushed out (N-221). It took the slot kept
## for someone who left, with the room otherwise full: the entry under that slot
## is theirs, and the newcomer's own would overwrite it at the next capture.
## {old peer id: entry}, moved along by peer_rejoined and given back when they
## are on the roster again. Session only; the DISPLACED_MEMORY most recent.
var _displaced_players: Dictionary = {}
const DISPLACED_MEMORY: int = 16
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
	if bus != null and bus.has_signal(&"run_started") \
			and not bus.is_connected(&"run_started", _on_run_started):
		bus.connect(&"run_started", _on_run_started)
	var network := _network()
	if network != null and not network.roster_changed.is_connected(_on_roster_changed):
		network.roster_changed.connect(_on_roster_changed)
	if network != null and not network.color_slots_changed.is_connected(_on_color_slots_changed):
		network.color_slots_changed.connect(_on_color_slots_changed)
	if network != null and not network.peer_rejoined.is_connected(_on_peer_rejoined):
		network.peer_rejoined.connect(_on_peer_rejoined)


func reset_campaign(persist: bool = false) -> bool:
	team_money = STARTING_MONEY
	merit.clear()
	cards.clear()
	dry_deliveries.clear()
	_credited_actions.clear()
	_run_merit.clear()
	_run_milestones.clear()
	supplies.clear()
	_saved_players_by_slot.clear()
	_displaced_players.clear()
	_last_host_data.clear()
	_known_peers.assign(_current_peers())
	_refresh_known_slots(_known_peers)
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


## The colour slot of a peer (0..7): what merit, cards and the save are keyed
## by. It is the host's index, not the peer id (N-226.2).
func player_slot(peer_id: int) -> int:
	return PlayerColorSlot.slot(peer_id, PLAYER_COLOR_KEYS.size())


func player_color_key(peer_id: int) -> String:
	return PLAYER_COLOR_KEYS[player_slot(peer_id)]


func player_color_name(peer_id: int) -> String:
	return tr(PLAYER_COLOR_NAMES[player_slot(peer_id)])


func award_action(peer_id: int, action_id: StringName, points: int) -> bool:
	if peer_id <= 0 or points <= 0 or _credited_actions.has(action_id):
		return false
	_credited_actions[action_id] = peer_id
	merit[peer_id] = int(merit.get(peer_id, 0)) + points
	_run_merit[peer_id] = int(_run_merit.get(peer_id, 0)) + points
	_emit_event(&"merit_changed", [peer_id, int(merit[peer_id])])
	return true


## Turns a package fact into the stable action id used for deduplication.
## occurrence belongs to that package and milestone, so separate real saves
## can score while a repeated report of the same one cannot.
func award_milestone(peer_id: int, package_id: StringName, milestone: StringName, occurrence: int) -> bool:
	if package_id.is_empty() or not MERIT_POINTS.has(milestone) or occurrence <= 0:
		return false
	var action_id := StringName("%s:%s:%d" % [package_id, milestone, occurrence])
	if not award_action(peer_id, action_id, int(MERIT_POINTS[milestone])):
		return false
	var peer_milestones: Dictionary = _run_milestones.get(peer_id, {})
	peer_milestones[milestone] = int(peer_milestones.get(milestone, 0)) + 1
	_run_milestones[peer_id] = peer_milestones
	return true


func award_delivery(results: Dictionary, peers: Array) -> void:
	results["merit_by_peer"] = _run_merit.duplicate(true)
	results["awards"] = _delivery_awards()
	# Door points + cargo that came back, with no chaos multiplier (that one is
	# only in the score). Endless results carry neither, so it pays nothing.
	# Shown on the results screen as "Pago del equipo" (results["payout"]).
	var base_payout: int = maxi(int(results.get("delivery_points", 0)) + int(results.get("cargo_points", 0)), 0)
	# The manual van pays more (N-114): the multiplier is the truck's own
	# (vehicle.gd VARIANTS, the one source), read from the truck on the road.
	# 1.0 (no truck, an ordinary one) changes nothing.
	var multiplier: float = _truck_pay_multiplier()
	results["pay_multiplier"] = multiplier
	var payout: int = roundi(base_payout * multiplier)
	results["payout"] = payout
	results["pay_bonus"] = payout - base_payout
	team_money += payout
	_credited_actions.clear()
	_emit_event(&"team_money_changed", [team_money])
	for peer: Variant in peers:
		_grant_card_chance(int(peer))
	save_campaign()
	_reset_run_merit()


## What the truck the crew is driving multiplies the payout by (Vehicle.pay_multiplier()).
func _truck_pay_multiplier() -> float:
	var truck: Node = get_tree().get_first_node_in_group(&"vehicle") if is_inside_tree() else null
	if truck == null or not truck.has_method(&"pay_multiplier"):
		return 1.0
	return maxf(float(truck.call(&"pay_multiplier")), 1.0)


func _on_run_started(_route_id: StringName, _peers: Array) -> void:
	_reset_run_merit()


func _reset_run_merit() -> void:
	_run_merit.clear()
	_run_milestones.clear()


func _delivery_awards() -> Array[Dictionary]:
	var awards: Array[Dictionary] = []
	var mvp: int = _best_peer(_run_merit)
	if mvp > 0:
		awards.append({"title": "HUD_AWARD_MVP", "peer": mvp})
	_append_milestone_award(awards, "HUD_AWARD_RESCUER", [&"rescued"])
	_append_milestone_award(awards, "HUD_AWARD_DEFUSER", [&"defused"])
	_append_milestone_award(awards, "HUD_AWARD_STEADY_HAND", [&"leveled", &"calmed", &"dried", &"sequence"])
	return awards


func _append_milestone_award(awards: Array[Dictionary], title: String, milestones: Array[StringName]) -> void:
	var scores: Dictionary = {}
	for peer: Variant in _run_milestones:
		var counts: Dictionary = _run_milestones[peer]
		for milestone: StringName in milestones:
			scores[int(peer)] = int(scores.get(int(peer), 0)) + int(counts.get(milestone, 0))
	var winner: int = _best_peer(scores)
	if winner > 0:
		awards.append({"title": title, "peer": winner})


func _best_peer(scores: Dictionary) -> int:
	var winner: int = 0
	var best: int = 0
	for raw_peer: Variant in scores:
		var peer: int = int(raw_peer)
		var score: int = int(scores[raw_peer])
		if score > best or (score == best and score > 0 and (winner == 0 or peer < winner)):
			winner = peer
			best = score
	return winner


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
	return tr(String(CARD_NAMES.get(card_id, "UI_CARD_GENERIC")))


## Usable from anywhere during a run. Clients ask the host, which derives
## the peer from the RPC sender and lets RouteEventManager resolve the event.
@rpc("any_peer", "call_local", "reliable")
func request_use_card() -> bool:
	var network := _network()
	if network != null and network.is_online() and not network.is_host():
		return false
	if not RpcGuard.allow_request(self):
		return false
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender_id if sender_id != 0 else network.local_id() if network != null else 1
	var held_card: int = int(cards.get(peer_id, -1))
	if held_card != Card.RESCUE:
		_send_card_notice(peer_id, "HUD_CARD_DEPOT_ONLY" if held_card in [Card.DISCOUNT, Card.REVOTE]
			else "HUD_CARD_NONE")
		return false
	var route_events := get_node_or_null(^"/root/RouteEventManager") as ROUTE_EVENT_MANAGER
	if route_events == null or route_events.active_event_id.is_empty():
		_send_card_notice(peer_id, "HUD_CARD_NOTHING_TO_RESCUE")
		return false
	return route_events.use_rescue(peer_id)


func _send_card_notice(peer_id: int, text: String) -> void:
	var network := _network()
	if network != null and network.is_online() and peer_id != network.local_id():
		_receive_card_notice.rpc_id(peer_id, text)
	else:
		_receive_card_notice(text)


@rpc("authority", "call_remote", "reliable")
func _receive_card_notice(text: String) -> void:
	var bus: Node = event_bus if event_bus != null else get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.emit_signal(&"depot_notice", tr(text))


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
		"players": _players_for_file(),
	}


## The saved players with string keys ("0".."4"), the way JSON stores them.
func _players_for_file() -> Dictionary:
	var players: Dictionary = {}
	for slot: int in _saved_players_by_slot:
		players[str(slot)] = (_saved_players_by_slot[slot] as Dictionary).duplicate(true)
	return players


func _apply_campaign_data(data: Dictionary, remember_players: bool) -> void:
	var raw_version: Variant = data.get("version", 1)
	var version: int = int(raw_version) if raw_version is int or raw_version is float else 1
	if version > CAMPAIGN_VERSION or version < 1:
		# Written by a newer game (or not by this one): its layout is unknown,
		# so it is not guessed at. The next save replaces it.
		push_warning("Campaña guardada con el formato %d (este juego sabe hasta el %d): se empieza de cero."
				% [version, CAMPAIGN_VERSION])
		data = _default_campaign()
		version = CAMPAIGN_VERSION
	if not remember_players:
		_last_host_data = data.duplicate(true)
	team_money = maxi(int(data.get("team_money", STARTING_MONEY)), 0)
	supplies.clear()
	var raw_supplies: Variant = data.get("supplies", [])
	for raw_id: Variant in raw_supplies if raw_supplies is Array else []:
		var supply_id := StringName(raw_id)
		if SUPPLIES.has(supply_id):
			supplies[supply_id] = true
	var raw_players: Variant = data.get("players", {})
	var normalized_players := _normalized_players(raw_players if raw_players is Dictionary else {}, version)
	if remember_players:
		_saved_players_by_slot = normalized_players.duplicate(true)
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
	_refresh_known_slots(peers)
	_emit_event(&"team_money_changed", [team_money])
	for old_peer: Variant in old_peers:
		if not peers.has(int(old_peer)):
			_emit_event(&"merit_changed", [int(old_peer), 0])
			_emit_event(&"card_changed", [int(old_peer), -1])
	for peer_id: int in peers:
		_emit_event(&"merit_changed", [peer_id, int(merit.get(peer_id, 0))])
		_emit_event(&"card_changed", [peer_id, int(cards.get(peer_id, -1))])


## {slot: entry} for the palette's slots, from a file's "players" of `version`
## (1 = colour names, migrated; 2 = slot numbers). Anything malformed is left out.
func _normalized_players(raw_players: Dictionary, version: int = CAMPAIGN_VERSION) -> Dictionary:
	var normalized: Dictionary = {}
	for slot: int in PLAYER_COLOR_KEYS.size():
		if version < 2 and slot >= LEGACY_COLOR_FOR_SLOT.size():
			break
		var key: String = LEGACY_COLOR_FOR_SLOT[slot] if version < 2 else str(slot)
		var raw: Variant = raw_players.get(key, {})
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var card_id: int = int(entry.get("card", -1))
		normalized[slot] = {
			"merit": maxi(int(entry.get("merit", 0)), 0),
			"card": card_id if card_id >= 0 and card_id < Card.size() else -1,
			"dry_deliveries": maxi(int(entry.get("dry_deliveries", 0)), 0),
		}
	return normalized


func _apply_player_entry(peer_id: int, players_by_slot: Dictionary) -> void:
	_apply_entry(peer_id, players_by_slot.get(player_slot(peer_id), {}))


func _apply_entry(peer_id: int, entry: Dictionary) -> void:
	merit[peer_id] = maxi(int(entry.get("merit", 0)), 0)
	dry_deliveries[peer_id] = maxi(int(entry.get("dry_deliveries", 0)), 0)
	var card_id: int = int(entry.get("card", -1))
	if card_id >= 0 and card_id < Card.size():
		cards[peer_id] = card_id


func _apply_saved_player(peer_id: int) -> void:
	var network := _network() if is_inside_tree() else null
	var displaced: Dictionary = _displaced_players.get(peer_id, {})
	_displaced_players.erase(peer_id)
	if network != null and not network.inherits_color_slot(peer_id):
		# Took the slot kept for someone who left while the room was full
		# (N-221): what's saved under it is theirs -- kept for them, before this
		# player's own is captured over it -- so this player starts clean.
		var owner: int = network.slot_kept_for(peer_id)
		var slot: int = player_slot(peer_id)
		if owner > 0 and _saved_players_by_slot.has(slot):
			_keep_displaced(owner, _saved_players_by_slot[slot])
		_apply_entry(peer_id, displaced)
		return
	if not displaced.is_empty():
		# Back after a newcomer took its slot: its own entry, not the slot's.
		_apply_entry(peer_id, displaced)
		return
	_apply_player_entry(peer_id, _saved_players_by_slot)


func _keep_displaced(owner: int, entry: Dictionary) -> void:
	_displaced_players.erase(owner)
	_displaced_players[owner] = entry.duplicate(true)
	while _displaced_players.size() > DISPLACED_MEMORY:
		_displaced_players.erase(_displaced_players.keys()[0])


func _capture_current_players() -> void:
	var peer_ids: Array = _current_peers()
	_refresh_known_slots(peer_ids)
	for source: Dictionary in [merit, cards, dry_deliveries]:
		for raw_peer: Variant in source:
			if not peer_ids.has(int(raw_peer)):
				peer_ids.append(int(raw_peer))
	for peer: Variant in peer_ids:
		_capture_player(int(peer))


func _capture_player(peer_id: int) -> void:
	var slot: int = int(_known_slots.get(peer_id, player_slot(peer_id)))
	_saved_players_by_slot[slot] = {
		"merit": maxi(int(merit.get(peer_id, 0)), 0),
		"card": int(cards.get(peer_id, -1)),
		"dry_deliveries": maxi(int(dry_deliveries.get(peer_id, 0)), 0),
	}


## Remembers the slot each of `peers` wears now (and forgets everyone else's).
func _refresh_known_slots(peers: Array) -> void:
	_known_slots.clear()
	for peer: Variant in peers:
		_known_slots[int(peer)] = player_slot(int(peer))


func _current_peers() -> Array[int]:
	var network := _network() if is_inside_tree() else null
	if network != null:
		return network.peer_ids.duplicate()
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
	var network := _network() if is_inside_tree() else null
	return network == null or not network.is_online() or network.is_host()


func _on_roster_changed(raw_peers: Array) -> void:
	var network := _network()
	if network == null:
		return
	if not network.is_online():
		if raw_peers.size() <= 1:
			# The session is over: the peer ids those were kept under mean nothing now.
			_displaced_players.clear()
		if _using_host_campaign:
			_using_host_campaign = false
			load_campaign()
		return
	var peers: Array[int] = []
	peers.assign(raw_peers)
	if not network.is_host():
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
	_refresh_known_slots(peers)
	_broadcast_campaign()


## A client's slot map arrived or changed: the campaign it was given is keyed
## by slot, so it is read again with the map it should have been read with.
func _on_color_slots_changed(_slots: Dictionary) -> void:
	var network := _network()
	if network == null or not network.is_online() or network.is_host() or _last_host_data.is_empty():
		return
	_apply_campaign_data(_last_host_data, false)


## Host: someone who dropped is back under a new peer id (N-221). Their
## campaign merit and card come back with their slot (_apply_saved_player,
## when they reach the roster); what they earned this run so far, kept by peer
## id, moves over here now.
func _on_peer_rejoined(old_id: int, new_id: int) -> void:
	for source: Dictionary in [_run_merit, _run_milestones, _displaced_players]:
		if source.has(old_id):
			source[new_id] = source[old_id]
			source.erase(old_id)


func _broadcast_campaign() -> void:
	var network := _network() if is_inside_tree() else null
	if network == null or not network.is_online() or not network.is_host():
		return
	_capture_current_players()
	_receive_campaign.rpc(_campaign_data())


## Same channel as NetworkManager._sync_color_slots(), which the host sends
## first when someone joins: the campaign is applied by slot, so the slots
## must already be here (test_rpc_guard checks the channel).
@rpc("authority", "call_remote", "reliable")
func _receive_campaign(data: Dictionary) -> void:
	var network := _network()
	if network == null or network.is_host():
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
	var network := _network()
	if network != null and not network.is_host():
		return
	var run := get_node_or_null(^"/root/RunManager") as RUN_MANAGER
	if run == null:
		return
	award_milestone(run.last_photo_peer_id, run.last_photo_package_id, &"photo_saved", 1)


func _on_card_changed(peer_id: int, card_id: int) -> void:
	if card_id < 0:
		cards.erase(peer_id)
	else:
		cards[peer_id] = card_id


## The NetworkManager autoload, or null outside a running game (a bare
## CrewProgression in a test, or one not added to the tree yet).
func _network() -> NETWORK_MANAGER:
	return get_node_or_null(^"/root/NetworkManager") as NETWORK_MANAGER

class_name CoopVote
extends Node
## A host-owned vote among the peers of a session over a set of offers
## (id -> {cost, label, ...}): whoever asks opens it, every vote restarts
## nothing, the first vote starts the clock, and it resolves when everyone
## voted or the clock ran out -- the most voted offer wins, the cheapest on
## a tie. Portable module (docs/modulos.md): the game extends it as an
## autoload, says what the offers are and how a purchase is paid
## (_default_offers, _spend), and listens to the signals.
##
## Host-authoritative: clients ask through the request_* RPCs, the host
## keeps the state and mirrors it to everyone (_sync_state, _sync_resolution).
## resolve_winner() is pure selection: asking for the winner never charges
## anyone, finish_vote() announces it, resolve() pays for it.

signal opened(offers: Dictionary)
signal vote_changed(peer_id: int, offer_id: StringName)
signal resolved(offer_id: StringName, offer: Dictionary)

var vote_duration: float = 20.0
var offers: Dictionary = {}  # id -> {cost, label, ...}
var votes: Dictionary = {}  # peer -> offer id
var active: bool = false
var timer_started: bool = false
var seconds_left: float = 20.0
## The session (a NetSession) whose roster counts as the voters; without
## one, the MultiplayerAPI's peers.
var session: NetSession = null


func _process(delta: float) -> void:
	if not active or not timer_started:
		return
	if is_host() and _everyone_voted(connected_peers()):
		finish_vote(connected_peers())
		return
	seconds_left = maxf(0.0, seconds_left - delta)
	if is_host() and is_zero_approx(seconds_left):
		finish_vote(connected_peers())


func open(new_offers: Dictionary) -> void:
	offers = new_offers.duplicate(true)
	votes.clear()
	active = true
	timer_started = false
	seconds_left = vote_duration
	opened.emit(offers.duplicate(true))
	_broadcast_state()


func vote(peer_id: int, offer_id: StringName) -> bool:
	if not active or not offers.has(offer_id):
		return false
	votes[peer_id] = offer_id
	vote_changed.emit(peer_id, offer_id)
	return true


## Any peer asks for the vote: the host opens it with the game's offers,
## or hands the asker the state of the one already running.
@rpc("any_peer", "call_local", "reliable")
func request_open() -> void:
	if not is_host() or not RpcGuard.allow_request(self):
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if not active:
		open(_default_offers())
	elif sender_id > 0:
		_send_state(sender_id)


@rpc("any_peer", "call_local", "reliable")
func request_vote(offer_id: StringName) -> bool:
	if not is_host() or not RpcGuard.allow_request(self):
		return false
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender_id if sender_id != 0 else local_peer_id()
	if peer_id <= 0 or (is_online() and not connected_peers().has(peer_id)):
		return false
	if not vote(peer_id, offer_id):
		return false
	if not timer_started:
		timer_started = true
		seconds_left = vote_duration
	_broadcast_state()
	if _everyone_voted(connected_peers()):
		finish_vote(connected_peers())
	return true


## Pure selection: purchasing is the caller's business, so asking for the
## winner can never charge anyone a second time.
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


## Closes the vote on its winner and tells everyone; nothing is paid.
func finish_vote(peers: Array) -> StringName:
	if not active:
		return &""
	var winner: StringName = resolve_winner(peers)
	var offer: Dictionary = (offers.get(winner, {}) as Dictionary).duplicate(true)
	active = false
	timer_started = false
	resolved.emit(winner, offer)
	_broadcast_resolution(winner, offer)
	return winner


## Closes the vote on its winner and pays for it (_spend).
func resolve(peers: Array) -> StringName:
	return buy(resolve_winner(peers))


## Pays for `offer_id` and closes the vote on it; "" when it can't be paid.
func buy(offer_id: StringName) -> StringName:
	if offer_id.is_empty() or not offers.has(offer_id):
		return &""
	var offer: Dictionary = offers[offer_id]
	if not _spend(int(offer.get("cost", 0))):
		return &""
	active = false
	resolved.emit(offer_id, offer.duplicate(true))
	return offer_id


## Closes the vote on `offer_id` as it is (a card or a rule decided it),
## without paying here.
func close_on(offer_id: StringName, offer: Dictionary) -> void:
	active = false
	timer_started = false
	resolved.emit(offer_id, offer.duplicate(true))
	_broadcast_resolution(offer_id, offer)


## Everyone votes again from scratch; the clock waits for the first vote.
func restart_votes(by_peer: int) -> void:
	votes.clear()
	timer_started = false
	seconds_left = vote_duration
	vote_changed.emit(by_peer, &"")


func reset() -> void:
	active = false
	timer_started = false
	seconds_left = vote_duration
	votes.clear()
	offers.clear()


func _everyone_voted(peers: Array) -> bool:
	if peers.is_empty():
		return false
	for peer: Variant in peers:
		if not votes.has(int(peer)):
			return false
	return true


func connected_peers() -> Array:
	if session != null:
		return session.peer_ids.duplicate()
	if not is_online():
		return [1]
	var peers: Array = [multiplayer.get_unique_id()]
	peers.append_array(Array(multiplayer.get_peers()))
	return peers


func local_peer_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func is_online() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer if is_inside_tree() else null
	return peer != null and peer is not OfflineMultiplayerPeer


func is_host() -> bool:
	return not is_online() or multiplayer.is_server()


func _broadcast_state() -> void:
	if is_online() and is_host():
		_sync_state.rpc(offers, votes, active, timer_started, seconds_left)


func _send_state(peer_id: int) -> void:
	if is_online() and is_host():
		_sync_state.rpc_id(peer_id, offers, votes, active, timer_started, seconds_left)


@rpc("authority", "call_remote", "reliable")
func _sync_state(new_offers: Dictionary, new_votes: Dictionary, is_active: bool, has_timer: bool,
		remaining: float) -> void:
	offers = new_offers.duplicate(true)
	votes = new_votes.duplicate(true)
	active = is_active
	timer_started = has_timer
	seconds_left = remaining
	opened.emit(offers.duplicate(true))


func _broadcast_resolution(offer_id: StringName, offer: Dictionary) -> void:
	if is_online() and is_host():
		_sync_resolution.rpc(offer_id, offer)


@rpc("authority", "call_remote", "reliable")
func _sync_resolution(offer_id: StringName, offer: Dictionary) -> void:
	active = false
	timer_started = false
	resolved.emit(offer_id, offer.duplicate(true))


# --- Hooks the game fills in ---------------------------------------------------

## The offers a request_open() puts up when none is running.
func _default_offers() -> Dictionary:
	return {}


## Pays `cost` from wherever the game keeps its money; false leaves the
## vote open.
func _spend(_cost: int) -> bool:
	return true

class_name AccessoryNet
extends Node
## The accessories over the network (N-923.5), host-authoritative: a player
## asks to wear, drop or pick up an accessory, the host checks the request
## against its own inventory and the world and applies it, and every peer gets
## the result (_receive_accessories). Nobody but the host changes who owns or
## wears what: a client's copy is only ever what the host last sent.
##
## CrewProgression adds it as its child "AccessoryNet" (the same path on every
## peer, for the RPCs) and hands it its inventory, the colour of a peer and its
## save. Buying is not an RPC here: it is the shop's vote (a player votes for
## its own offer, ShopVoteManager settles it with CrewProgression.buy_accessory()
## on the host) and its result reaches the clients with the campaign and with
## the sync below, like every other change.
##
## On the ground (AccessoryGround): a dropped accessory stays its owner's until
## somebody else picks it up, so it is never lost and never sold twice; it can't
## be worn while it lies there. It goes back to its owner (the pickup goes away)
## when the owner leaves, when the delivery ends, after PICKUP_LIFETIME_MSEC,
## or if the owner no longer has it (a reset campaign). Each player has at most
## MAX_PICKUPS_PER_PLAYER lying at once.
##
## For the pickup in the world (N-923.6): `ground` is the same on every peer
## (pickup_added / pickup_removed, ids from the host), a node shows each one at
## its position and asks with pick_up(pickup_id) -- or, run on the host as an
## Interactable, calls pick_up_as(peer, pickup_id). Rules that need the world
## around the player (not dropping from a fast truck) go in _drop_block().

## How long a dropped accessory waits for somebody before it goes back (N-923).
const PICKUP_LIFETIME_MSEC: int = 120000
## Accessories one player may have lying on the ground at once (N-923).
const MAX_PICKUPS_PER_PLAYER: int = 1
## Metres in front of a player where what they drop lands.
const DROP_DISTANCE: float = 0.9
## A burst of changes writes the campaign once, this long after the first.
const SAVE_DELAY_SEC: float = 0.5
const PLAYER_GROUP: StringName = &"player"

## The crew's inventory (CrewProgression.accessories): the host's own, a
## client's mirror of it.
var inventory: AccessoryInventory
## What lies on the ground, the same on every peer.
var ground := AccessoryGround.new()
## The colour keys an owner may be (CrewProgression.PLAYER_COLOR_KEYS).
var owners: Array = []
var _color_of: Callable
var _save: Callable
var _session: NetSession
var _sync_queued: bool = false
var _save_queued: bool = false


## Wires it to the crew: `color_of(peer_id) -> String` names the owner of a
## peer's things, `save` writes the campaign (host). `session` (NetworkManager)
## says who leaves and when the session ends; `bus` (EventBus) when a delivery
## ends. Both may be null (a test, playing without them).
func setup(owned: AccessoryInventory, colour_keys: Array, color_of: Callable, save: Callable,
		session: NetSession = null, bus: Node = null) -> void:
	inventory = owned
	owners = colour_keys.duplicate()
	_color_of = color_of
	_save = save
	_session = session
	inventory.changed.connect(_on_inventory_changed)
	ground.pickup_added.connect(func(_id: int, _pickup: Dictionary) -> void: _queue_sync())
	ground.pickup_removed.connect(func(_id: int) -> void: _queue_sync())
	if session != null:
		session.peer_removed.connect(_on_peer_removed)
		session.roster_changed.connect(_on_roster_changed)
	if bus != null and bus.has_signal(&"run_ended"):
		bus.connect(&"run_ended", _on_run_ended)


func _process(_delta: float) -> void:
	if not ground.is_empty() and _is_host():
		expire_pickups(Time.get_ticks_msec())


# --- What the local player asks for -------------------------------------------

## The local player wears `accessory` in `slot`; &"" takes off what is there.
func equip(slot: StringName, accessory: StringName = &"") -> void:
	if _is_client():
		request_equip_accessory.rpc_id(NetSession.HOST_ID, slot, accessory)
	else:
		equip_as(_local_id(), slot, accessory)


## The local player drops `accessory` in front of them.
func drop(accessory: StringName) -> void:
	if _is_client():
		request_drop_accessory.rpc_id(NetSession.HOST_ID, accessory)
	else:
		drop_as(_local_id(), accessory)


## The local player picks up pickup `pickup_id` (an id from `ground`).
func pick_up(pickup_id: int) -> void:
	if _is_client():
		request_pickup_accessory.rpc_id(NetSession.HOST_ID, pickup_id)
	else:
		pick_up_as(_local_id(), pickup_id)


# --- Requests, on the host --------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func request_equip_accessory(slot: StringName, accessory: StringName) -> void:
	if not _is_host() or not RpcGuard.allow_request(self) or not RpcGuard.name_ok(slot) \
			or not RpcGuard.name_ok(accessory):
		return
	var peer_id: int = RpcGuard.sender(self)
	if _on_roster(peer_id):
		equip_as(peer_id, slot, accessory)


@rpc("any_peer", "call_remote", "reliable")
func request_drop_accessory(accessory: StringName) -> void:
	if not _is_host() or not RpcGuard.allow_request(self) or not RpcGuard.name_ok(accessory):
		return
	var peer_id: int = RpcGuard.sender(self)
	if _on_roster(peer_id):
		drop_as(peer_id, accessory)


@rpc("any_peer", "call_remote", "reliable")
func request_pickup_accessory(pickup_id: int) -> void:
	if not _is_host() or not RpcGuard.allow_request(self) or pickup_id <= 0:
		return
	var peer_id: int = RpcGuard.sender(self)
	if _on_roster(peer_id):
		pick_up_as(peer_id, pickup_id)


## Host: `peer_id` wears `accessory` in `slot` (&"" takes it off). Returns &""
## or why not: &"not_host", &"unknown" (no such slot or accessory, or not that
## slot's), &"not_owner", &"on_ground".
func equip_as(peer_id: int, slot: StringName, accessory: StringName) -> StringName:
	if not _is_host():
		return &"not_host"
	var owner: String = _color(peer_id)
	if owner.is_empty() or not AccessoryCatalog.valid_slot(slot):
		return &"unknown"
	if accessory.is_empty():
		inventory.unequip(owner, slot)
		_save_soon()
		return &""
	if AccessoryCatalog.slot_of(accessory) != slot:
		return &"unknown"
	if not inventory.owns(owner, accessory):
		return &"not_owner"
	if ground.pickup_of(accessory) != 0:
		return &"on_ground"
	inventory.equip(owner, accessory)
	_save_soon()
	return &""


## Host: `peer_id` drops `accessory` in front of their player (taking it off
## first). Returns &"" or why not: &"not_host", &"unknown", &"not_owner",
## &"on_ground" (already lying), &"too_many" (MAX_PICKUPS_PER_PLAYER),
## &"no_player" (no body in this level to drop it from), or _drop_block()'s.
func drop_as(peer_id: int, accessory: StringName) -> StringName:
	if not _is_host():
		return &"not_host"
	var owner: String = _color(peer_id)
	if owner.is_empty() or not inventory.owns(owner, accessory):
		return &"not_owner" if not owner.is_empty() and AccessoryCatalog.has(accessory) else &"unknown"
	if ground.pickup_of(accessory) != 0:
		return &"on_ground"
	if ground.owned_by(owner).size() >= MAX_PICKUPS_PER_PLAYER:
		return &"too_many"
	var player: Node3D = _player(peer_id)
	var blocked: StringName = &"no_player" if player == null else _drop_block(peer_id, player)
	if not blocked.is_empty():
		return blocked
	var at: Vector3 = drop_point(player)
	if not RpcGuard.finite_vec3(at):
		return &"no_player" # a body with no sane pose: nowhere to put it
	var slot: StringName = AccessoryCatalog.slot_of(accessory)
	if inventory.equipped_in(owner, slot) == accessory:
		inventory.unequip(owner, slot)
	ground.add(accessory, owner, peer_id, at, Time.get_ticks_msec())
	_save_soon()
	return &""


## Host: `peer_id` takes pickup `pickup_id`: theirs again if it was, else it
## moves to them (one copy, never duplicated). Returns &"" or why not:
## &"not_host", &"gone" (no such pickup), &"unknown", &"no_player", &"far"
## (out of reach: an interactable's, plus that peer's round trip).
func pick_up_as(peer_id: int, pickup_id: int) -> StringName:
	if not _is_host():
		return &"not_host"
	var pickup: Dictionary = ground.get_pickup(pickup_id)
	var taker: String = _color(peer_id)
	if pickup.is_empty() or taker.is_empty():
		return &"gone" if pickup.is_empty() else &"unknown"
	var player: Node3D = _player(peer_id)
	if player == null:
		return &"no_player"
	var reach: float = Interactable.REMOTE_REACH + NetStats.reach_slack(multiplayer.multiplayer_peer, peer_id)
	if reach_origin(player).distance_to(pickup["position"]) > reach:
		return &"far"
	ground.remove(pickup_id)
	var owner: String = pickup["owner"]
	if owner != taker and not inventory.give(owner, taker, StringName(pickup["accessory"])):
		return &"gone" # its owner had lost it meanwhile (pruned): nothing to hand over
	_save_soon()
	return &""


## Host: every pickup lying PICKUP_LIFETIME_MSEC or more at `now_msec` goes back
## to its owner. Returns how many did.
func expire_pickups(now_msec: int) -> int:
	if not _is_host():
		return 0
	var gone: Array[int] = ground.expired(now_msec, PICKUP_LIFETIME_MSEC)
	for pickup_id: int in gone:
		ground.remove(pickup_id)
	return gone.size()


## Host: every accessory on the ground goes back to its owner.
func return_all() -> void:
	if _is_host():
		ground.clear()


## Client: the host's word on the inventory (CrewProgression.accessories, as
## AccessoryInventory.to_dict()) and the ground (AccessoryGround.to_array()).
## Anything that doesn't check out is dropped there.
func apply_host_state(owned: Dictionary, pickups: Array) -> void:
	inventory.load_dict(owned, owners)
	ground.load_array(pickups, owners)


## Where something `player` drops lands: DROP_DISTANCE in front of where they are.
static func drop_point(player: Node3D) -> Vector3:
	var forward: Vector3 = -player.global_basis.z
	forward.y = 0.0
	var origin: Vector3 = reach_origin(player)
	return origin + forward.normalized() * DROP_DISTANCE if forward.length() > 0.01 else origin


## Where a player is for anything within reach: its seat while seated
## (Player.reach_origin()), else where it stands.
static func reach_origin(player: Node3D) -> Vector3:
	if player.has_method(&"reach_origin"):
		var origin: Variant = player.call(&"reach_origin")
		if origin is Vector3:
			return origin
	return player.global_position


# --- To every peer --------------------------------------------------------------

## Host -> clients: the whole inventory and the ground, after any change, and
## to everyone again when the roster changes (a newcomer gets it this way).
## Whole rather than a change: four accessories at most, and a copy that went
## stale can't drift further. Same channel as CrewProgression._receive_campaign,
## which carries the inventory too: they arrive in the order the host sent them.
@rpc("authority", "call_remote", "reliable")
func _receive_accessories(owned: Dictionary, pickups: Array) -> void:
	if _is_host() or not RpcGuard.from_host(self):
		return
	apply_host_state(owned, pickups)


func _queue_sync() -> void:
	if _sync_queued or not _is_host() or not _online():
		return
	_sync_queued = true
	_flush_sync.call_deferred()


func _flush_sync() -> void:
	_sync_queued = false
	if _is_host() and _online() and is_inside_tree():
		_receive_accessories.rpc(inventory.to_dict(), ground.to_array())


func _save_soon() -> void:
	if _save_queued or not _save.is_valid():
		return
	_save_queued = true
	if is_inside_tree():
		get_tree().create_timer(SAVE_DELAY_SEC).timeout.connect(_save_now)
	else:
		_save_now()


func _save_now() -> void:
	_save_queued = false
	if _save.is_valid() and _is_host():
		_save.call()


# --- What happens around it --------------------------------------------------------

## Host: a pickup only stands for something its owner still owns.
func _on_inventory_changed(_owner: String) -> void:
	if _is_host():
		ground.prune(inventory)
		_queue_sync()


## Host: what a leaver dropped goes back to it (by colour: its things stay
## there while it is away, CrewProgression).
func _on_peer_removed(peer_id: int) -> void:
	if not _is_host():
		return
	var owner: String = _color(peer_id)
	for pickup_id: int in ground.ids():
		var pickup: Dictionary = ground.get_pickup(pickup_id)
		if int(pickup["dropper"]) == peer_id or (not owner.is_empty() and pickup["owner"] == owner):
			ground.remove(pickup_id)


func _on_roster_changed(_peers: Array) -> void:
	if not _online():
		# The session is over: what lay in its world is back with its owners.
		ground.clear()
		_sync_queued = false
	elif _is_host():
		_queue_sync()


func _on_run_ended(_score: int, _results: Dictionary) -> void:
	return_all()


## A rule about the world around `player` that stops a drop (N-923.6: not from
## a truck going faster than 5 m/s), &"" if none.
func _drop_block(_peer_id: int, _player: Node3D) -> StringName:
	return &""


## The body `peer_id` plays with in the current level, or null.
func _player(peer_id: int) -> Node3D:
	if not is_inside_tree():
		return null
	for node: Node in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if node is Node3D and node.get_multiplayer_authority() == peer_id:
			return node
	return null


func _color(peer_id: int) -> String:
	if peer_id <= 0 or not _color_of.is_valid():
		return ""
	var key: String = String(_color_of.call(peer_id))
	return key if owners.is_empty() or owners.has(key) else ""


func _on_roster(peer_id: int) -> bool:
	return _session == null or _session.peer_ids.has(peer_id)


func _online() -> bool:
	if not is_inside_tree():
		return false
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and peer is not OfflineMultiplayerPeer \
			and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func _is_host() -> bool:
	return not _online() or multiplayer.is_server()


func _is_client() -> bool:
	return _online() and not multiplayer.is_server()


func _local_id() -> int:
	return multiplayer.get_unique_id() if _online() else NetSession.HOST_ID

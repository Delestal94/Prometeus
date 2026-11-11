class_name PickingCartGrip
extends Node
## Holding a picking cart's handle (expansion D-0610.c2.b): the cart goes along with who pushes it.
##
## Using the handle (PickingCartPoint.ACTION_GRIP) grips it; using it again lets go. While gripped, the HOST
## looks every physics frame at where the holder stands and, if they came closer to the cart than
## CompanyTuning.CART_GRIP_DISTANCE_M plus a lead, asks its own CompanyNet for a cart_push on their behalf
## (request_for, the same request and event as a single push, CompanyCarts "step"), at most one every
## CART_GRIP_INTERVAL_S. The lead (lead()) is how far the holder walks towards the cart, at the pace seen since
## the last look, in CART_GRIP_LEAD_S plus their round trip (at most CART_GRIP_MAX_LEAD_M): their peer gets the
## step a while after the host saw them, so it goes where they will be by then and the next one comes before
## they reach the cart's solid deck (CompanyTuning says why the numbers hold; test_company_picking_cart_push
## walks it with a LAN's and a Steam link's delays). Only setting off from a standstill can the deck stop
## them, until the host sees them go and the first step comes back (a frame or two walking on a LAN).
## Nothing here is a new request or a new event, so every peer sees the cart roll through cart_moved and the
## host's checks (reach, floor, other carts) still decide every step. A cart pulled away is never followed:
## walking back does not drag it, and past CART_GRIP_RELEASE_M the holder lets go.
##
## Let go on its own when: the holder uses the handle again, uses anything else of the cart (loads, takes...),
## their hands change (they took or put something), they walk off, have no player any more, or leave the
## session (peer_left(): NetworkManager.peer_removed, multiplayer.peer_disconnected, or back under the same id).
## One holder per cart (a second one is `taken`) and one cart per holder (gripping another lets go of the first).
##
## A step the host refuses with `blocked` tells who pushes: the refusal reaches their own peer with
## request_rejected (rid 0, as for any request the host makes for them) and this node shows a notice there
## (EventBus.depot_notice), at most one every NOTICE_PAUSE_MSEC. The grip stays, so they can steer around.
##
## Host-side state (who holds what): the clients only see the cart move. Presentation never decides anything.

signal gripped(peer: int, cart_id: StringName)
signal released(peer: int, cart_id: StringName, why: StringName)
## This peer's own push was refused with `blocked` (the notice text, already translated).
signal blocked_noticed(text: String)

const RESULT_GRIPPED: StringName = &"gripped"
const RESULT_RELEASED: StringName = &"released"
const REASON_TAKEN: StringName = &"taken"
const REASON_NO_CART: StringName = &"no_cart"
const WHY_TOGGLED: StringName = &"toggled"
const WHY_OTHER_USE: StringName = &"other_use"
const WHY_HANDS: StringName = &"hands"
const WHY_AWAY: StringName = &"away"
const WHY_GONE: StringName = &"gone"
const WHY_LEFT: StringName = &"left"
const NOTICE_PAUSE_MSEC: int = 1500
## The holder's round trip is read again this often (s), not on every look (on Steam it asks the client).
const LAG_REFRESH_S: float = 1.0
const NOTICE_KEY: String = "WORLD_SHED_PUSH_BLOCKED"

var net: CompanyNet
var shed: CompanyShed
## Callable(peer: int) -> Variant: where that peer's feet are (world), null if they have no player. Empty: the
## player of that peer in Interactable.player_group (what CompanyRoot uses); tests answer it themselves.
var where: Callable = Callable()
## Callable(peer: int) -> float: the round trip to that peer, in seconds, added to the lead's CART_GRIP_LEAD_S.
## Empty: NetStats.round_trip_seconds (ENet's, Steam's ping; 0 offline); tests answer it themselves.
var lag_of: Callable = Callable()

## peer -> {cart: StringName, hands: int (hash of what they held), wait: float seconds to the next look,
## last: Variant (their feet at the last look, null before the first), since: float seconds since it,
## lag: float their round trip (_lag()), lag_age: float seconds since it was read}
var _grips: Dictionary = {}
var _last_notice_msec: int = -NOTICE_PAUSE_MSEC


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# A holder who leaves lets go: peer_removed comes first (and for a ghost), peer_disconnected also without a
	# session autoload (tests, a bare scene); the second finds nothing to let go.
	if not multiplayer.peer_disconnected.is_connected(peer_left):
		multiplayer.peer_disconnected.connect(peer_left)
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network == null:
		return
	if network.has_signal(&"peer_removed") and not network.is_connected(&"peer_removed", peer_left):
		network.connect(&"peer_removed", peer_left)
	if network.has_signal(&"peer_returned") and not network.is_connected(&"peer_returned", _on_peer_returned):
		network.connect(&"peer_returned", _on_peer_returned)


## A grip child of `parent`, set up for `company_net` and `company_shed`.
static func attach(parent: Node, company_net: CompanyNet, company_shed: CompanyShed) -> PickingCartGrip:
	var grip := PickingCartGrip.new()
	grip.name = "CartGrip"
	parent.add_child(grip)
	grip.setup(company_net, company_shed)
	return grip


## Host: a crew member worked a picking cart (D-0610.b, take D-0610.c2). The handle is ours; the rest goes to
## PickingCartUse, which asks the host's own CompanyNet on their behalf (reach, hands and room).
func on_cart_used(cart_id: StringName, action: StringName, peer: int, from: Vector3, what: StringName) -> void:
	if net == null or not net.is_host() or handled(cart_id, action, peer):
		return
	PickingCartUse.use(net, shed.cart_views.get(cart_id) as PickingCartView, action, peer, from, what)


## Host: `peer` used a point of cart `cart_id`. The handle grips or lets go and that is all (true); any other
## use of the cart lets go of it and goes on (false: the caller does what it asked).
func handled(cart_id: StringName, action: StringName, peer: int) -> bool:
	if action == PickingCartPoint.ACTION_GRIP:
		toggle(peer, cart_id)
		return true
	release(peer, WHY_OTHER_USE)
	return false


## The net to ask on the holders' behalf and the shed whose carts they push. Every peer calls it (the host
## drives the grips, each peer shows its own notices).
func setup(company_net: CompanyNet, company_shed: CompanyShed) -> void:
	net = company_net
	shed = company_shed
	if net != null and not net.request_rejected.is_connected(_on_request_rejected):
		net.request_rejected.connect(_on_request_rejected)


## Who holds `cart_id` now, 0 if nobody.
func holder_of(cart_id: StringName) -> int:
	for peer: int in _grips:
		if _grips[peer]["cart"] == cart_id:
			return peer
	return 0


func is_gripping(peer: int) -> bool:
	return _grips.has(peer)


func gripped_cart(peer: int) -> StringName:
	return _grips[peer]["cart"] if _grips.has(peer) else &""


## Host: `peer` used the handle of `cart_id`: grips it, or lets go if that is the cart they hold. RESULT_*
## or the reason (taken, no_cart).
func toggle(peer: int, cart_id: StringName) -> StringName:
	if net == null or not net.is_host() or _view(cart_id) == null:
		return REASON_NO_CART
	if _grips.has(peer) and _grips[peer]["cart"] == cart_id:
		release(peer, WHY_TOGGLED)
		return RESULT_RELEASED
	var holder: int = holder_of(cart_id)
	if holder != 0 and holder != peer:
		return REASON_TAKEN
	if _grips.has(peer):
		release(peer, WHY_OTHER_USE)
	_grips[peer] = {"cart": cart_id, "hands": _hands_hash(peer), "wait": 0.0, "last": null, "since": 0.0,
		"lag": 0.0, "lag_age": LAG_REFRESH_S}
	gripped.emit(peer, cart_id)
	return RESULT_GRIPPED


## Host: lets go of whatever `peer` holds (nothing happens if nothing).
func release(peer: int, why: StringName = WHY_OTHER_USE) -> void:
	if not _grips.has(peer):
		return
	var cart_id: StringName = _grips[peer]["cart"]
	_grips.erase(peer)
	released.emit(peer, cart_id, why)


## Host: `peer` left the session (or came back under the same id): lets go of what it held (WHY_LEFT).
func peer_left(peer: int) -> void:
	release(peer, WHY_LEFT)


func _on_peer_returned(id: int, previous_id: int) -> void:
	if id == previous_id:
		peer_left(id)


func _physics_process(delta: float) -> void:
	tick(delta)


## Host: lets `delta` seconds go by. Public so a test can step it without frames.
func tick(delta: float) -> void:
	if _grips.is_empty() or net == null or not net.is_host():
		return
	for peer: int in _grips.keys():
		if not _grips.has(peer):
			continue
		var grip: Dictionary = _grips[peer]
		grip["wait"] = float(grip["wait"]) - delta
		grip["since"] = float(grip["since"]) + delta
		grip["lag_age"] = float(grip["lag_age"]) + delta
		if float(grip["wait"]) <= 0.0:
			_follow(peer, grip)


## One look at a holder: let go if it is time, else push if they came too close (with the lead, lead()).
func _follow(peer: int, grip: Dictionary) -> void:
	var view: PickingCartView = _view(grip["cart"])
	var feet: Variant = _feet(peer)
	if view == null or not (feet is Vector3) or not RpcGuard.finite_vec3(feet):
		release(peer, WHY_GONE)
		return
	if int(grip["hands"]) != _hands_hash(peer):
		release(peer, WHY_HANDS)
		return
	var away: Vector3 = view.global_position - (feet as Vector3)
	away.y = 0.0
	var gap: float = away.length()
	if gap > CompanyTuning.CART_GRIP_RELEASE_M:
		release(peer, WHY_AWAY)
		return
	if float(grip["lag_age"]) >= LAG_REFRESH_S:
		grip["lag"] = _lag(peer)
		grip["lag_age"] = 0.0
	var ahead_s: float = CompanyTuning.CART_GRIP_LEAD_S + float(grip["lag"])
	var ahead: float = lead(grip["last"], feet, float(grip["since"]), away, ahead_s)
	grip["last"] = feet
	grip["since"] = 0.0
	var step: float = CompanyTuning.CART_GRIP_DISTANCE_M + ahead - gap
	if step < CompanyTuning.CART_GRIP_MIN_STEP_M:
		# Nothing to ask: look again next frame (only the requests wait CART_GRIP_INTERVAL_S), so a holder who
		# sets off from a standstill gets the cart moving the frame the host sees them go.
		return
	grip["wait"] = CompanyTuning.CART_GRIP_INTERVAL_S
	# The direction in the shed's frame (the cart's position is), the way PickingCartUse measures a push.
	var local_away: Vector3 = shed.global_transform.basis.inverse() * away
	var before: int = net.seq
	net.request_for(peer, CompanyCarts.PUSH, {"cart": view.cart.id,
		"dir": Vector3(local_away.x, 0.0, local_away.z), "step": step})
	if net.seq == before:
		grip["wait"] = CompanyTuning.CART_GRIP_BLOCKED_PAUSE_S


## How much further than CART_GRIP_DISTANCE_M the cart goes (m): the holder's pace towards it (from `last`, their
## feet `seconds` ago, to `feet`, along `away`, holder to cart) for `ahead_s` seconds, at most
## CART_GRIP_MAX_LEAD_M; 0 with no earlier look, no time between them or walking away.
static func lead(last: Variant, feet: Vector3, seconds: float, away: Vector3,
		ahead_s: float = CompanyTuning.CART_GRIP_LEAD_S) -> float:
	if not (last is Vector3) or seconds <= 0.001 or away.length() < 0.001:
		return 0.0
	var walked: Vector3 = feet - (last as Vector3)
	walked.y = 0.0
	var pace: float = walked.dot(away.normalized()) / seconds
	if not is_finite(pace) or not is_finite(ahead_s):
		return 0.0
	return clampf(pace * maxf(ahead_s, 0.0), 0.0, CompanyTuning.CART_GRIP_MAX_LEAD_M)


## The round trip to `peer` (s): their step reaches them that much later than the host saw them (0 for the
## host's own player and without a connection). lag_of answers it when set.
func _lag(peer: int) -> float:
	var seconds: float = 0.0
	if lag_of.is_valid():
		seconds = float(lag_of.call(peer))
	elif is_inside_tree():
		seconds = NetStats.round_trip_seconds(multiplayer.multiplayer_peer, peer)
	return clampf(seconds, 0.0, 1.0) if is_finite(seconds) else 0.0


func _view(cart_id: StringName) -> PickingCartView:
	if shed == null or not is_instance_valid(shed):
		return null
	var view: Variant = shed.cart_views.get(cart_id)
	if view is PickingCartView and is_instance_valid(view) and (view as PickingCartView).is_inside_tree():
		return view as PickingCartView
	return null


func _hands_hash(peer: int) -> int:
	return net.inventory.contents_at(CompanyNet.hands_location(peer)).hash() if net != null else 0


func _feet(peer: int) -> Variant:
	if where.is_valid():
		return where.call(peer)
	if not is_inside_tree():
		return null
	for player: Node in get_tree().get_nodes_in_group(Interactable.player_group):
		if player.get_multiplayer_authority() == peer and player is Node3D:
			return (player as Node3D).global_position
	return null


## This peer's own refusal (rid 0: the host's, made for us) of a push: tell them, now and then.
func _on_request_rejected(rid: int, reason: StringName) -> void:
	if rid != 0 or reason != CompanyCarts.REASON_BLOCKED:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_notice_msec < NOTICE_PAUSE_MSEC:
		return
	_last_notice_msec = now
	var text: String = tr(NOTICE_KEY)
	blocked_noticed.emit(text)
	var bus: Node = get_node_or_null(^"/root/EventBus") if is_inside_tree() else null
	if bus != null:
		bus.emit_signal(&"depot_notice", text)

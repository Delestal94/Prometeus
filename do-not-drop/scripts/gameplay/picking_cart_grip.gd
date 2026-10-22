class_name PickingCartGrip
extends Node
## Holding a picking cart's handle (expansion D-0610.c2.b): the cart goes along with who pushes it.
##
## Using the handle (PickingCartPoint.ACTION_GRIP) grips it; using it again lets go. While gripped, every
## CompanyTuning.CART_GRIP_INTERVAL_S the HOST looks at where the holder stands and, if they came closer to the
## cart than CART_GRIP_DISTANCE_M, asks its own CompanyNet for a short cart_push on their behalf (request_for,
## the same request and event as a single push, CompanyCarts "step"): the cart stays that far ahead of them.
## Nothing here is a new request or a new event, so every peer sees the cart roll through cart_moved and the
## host's checks (reach, floor, other carts) still decide every step. A cart pulled away is never followed:
## walking back does not drag it, and past CART_GRIP_RELEASE_M the holder lets go.
##
## Let go on its own when: the holder uses the handle again, uses anything else of the cart (loads, takes...),
## their hands change (they took or put something), they walk off or have no player any more (left).
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
const NOTICE_PAUSE_MSEC: int = 1500
const NOTICE_KEY: String = "WORLD_SHED_PUSH_BLOCKED"

var net: CompanyNet
var shed: CompanyShed
## Callable(peer: int) -> Variant: where that peer's feet are (world), null if they have no player. Empty: the
## player of that peer in Interactable.player_group (what CompanyRoot uses); tests answer it themselves.
var where: Callable = Callable()

## peer -> {cart: StringName, hands: int (hash of what they held), wait: float seconds to the next step}
var _grips: Dictionary = {}
var _last_notice_msec: int = -NOTICE_PAUSE_MSEC


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## A grip child of `parent`, set up for `company_net` and `company_shed`.
static func attach(parent: Node, company_net: CompanyNet, company_shed: CompanyShed) -> PickingCartGrip:
	var grip := PickingCartGrip.new()
	grip.name = "CartGrip"
	parent.add_child(grip)
	grip.setup(company_net, company_shed)
	return grip


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
	_grips[peer] = {"cart": cart_id, "hands": _hands_hash(peer), "wait": 0.0}
	gripped.emit(peer, cart_id)
	return RESULT_GRIPPED


## Host: lets go of whatever `peer` holds (nothing happens if nothing).
func release(peer: int, why: StringName = WHY_OTHER_USE) -> void:
	if not _grips.has(peer):
		return
	var cart_id: StringName = _grips[peer]["cart"]
	_grips.erase(peer)
	released.emit(peer, cart_id, why)


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
		if float(grip["wait"]) <= 0.0:
			_follow(peer, grip)


## One look at a holder: let go if it is time, else push if they came too close.
func _follow(peer: int, grip: Dictionary) -> void:
	var view: PickingCartView = _view(grip["cart"])
	var feet: Variant = _feet(peer)
	if view == null or not (feet is Vector3) or not RpcGuard.finite_vec3(feet):
		release(peer, WHY_GONE)
		return
	if int(grip["hands"]) != _hands_hash(peer):
		release(peer, WHY_HANDS)
		return
	grip["wait"] = CompanyTuning.CART_GRIP_INTERVAL_S
	var away: Vector3 = view.global_position - (feet as Vector3)
	away.y = 0.0
	var gap: float = away.length()
	if gap > CompanyTuning.CART_GRIP_RELEASE_M:
		release(peer, WHY_AWAY)
		return
	var step: float = CompanyTuning.CART_GRIP_DISTANCE_M - gap
	if step < CompanyTuning.CART_GRIP_MIN_STEP_M:
		return
	# The direction in the shed's frame (the cart's position is), the way PickingCartUse measures a push.
	var local_away: Vector3 = shed.global_transform.basis.inverse() * away
	var before: int = net.seq
	net.request_for(peer, CompanyCarts.PUSH, {"cart": view.cart.id,
		"dir": Vector3(local_away.x, 0.0, local_away.z), "step": step})
	if net.seq == before:
		grip["wait"] = CompanyTuning.CART_GRIP_BLOCKED_PAUSE_S


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

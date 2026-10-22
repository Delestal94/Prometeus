class_name CompanyCarts
extends RefCounted
## Where the picking carts stand, as the host decides it and every peer keeps it (expansion D-0610.b).
##
## The units on a cart are the Inventory's (cart:<id>, PickingCart) and move with units_take /
## units_store like any others; this holds the only thing the Inventory cannot: the spot of the cart on
## the shed floor. A push is a request, cart_push {cart, dir}, that CompanyNet checks at the cart's
## station (reach, as for any units request): the host moves the cart CompanyTuning.CART_PUSH_STEP_M
## along `dir` (flattened, any length) and publishes one cart_moved {cart, pos}, which every peer
## applies the same (rule 6: nothing is checked again, only that the data fits). `pos` is in the shed's
## own frame, ground height. A cart that was never pushed has no entry: the shed stands it at its
## default spot (DefaultShed.cart_spots). The spots travel in every snapshot under SNAPSHOT_KEY.
##
## What only the shed knows, the station gives: "at" (the cart's spot now, shed frame) and "stand_ok"
## (Callable(pos: Vector3) -> bool: the floor there is free). No node and no autoload here.

const PUSH: StringName = &"cart_push"
const MOVED: StringName = &"cart_moved"
const REQUEST_KINDS: Array[StringName] = [PUSH]
const EVENT_KINDS: Array[StringName] = [MOVED]
const SNAPSHOT_KEY: String = "carts"
## Carts a company can have (a snapshot or an event past this is refused).
const MAX_CARTS: int = 16
const MAX_ID_LENGTH: int = 32

const REASON_BAD_DATA: StringName = &"bad_data"
const REASON_NO_STATION: StringName = &"no_station"
const REASON_BLOCKED: StringName = &"blocked"

## cart id -> Vector3 (shed frame, y 0), only the carts that were pushed.
var _at: Dictionary = {}


## A cart id that came over the network: an identifier of at most MAX_ID_LENGTH characters.
static func id_ok(value: Variant) -> bool:
	if not CompanyAsk.is_id(value):
		return false
	var text: String = String(value)
	if text.is_empty() or text.length() > MAX_ID_LENGTH:
		return false
	for index: int in text.length():
		var code: int = text.unicode_at(index)
		var plain: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95
		if not plain:
			return false
	return true


## Where a pushed cart stands, null while it was never pushed.
func position_of(cart: StringName) -> Variant:
	return _at.get(cart)


func count() -> int:
	return _at.size()


## {cart, dir, step} of a cart_push request, `dir` a finite Vector3 whose x and z are not both zero; {} otherwise.
## `step` (metres) is the optional "step" of the data, a short one while somebody holds the handle
## (D-0610.c2.b, PickingCartGrip): clamped to CART_GRIP_MIN_STEP_M .. CART_PUSH_STEP_M, and the whole
## CART_PUSH_STEP_M when absent or not a finite number, as every push was before it existed.
static func push_ask(data: Dictionary) -> Dictionary:
	var cart: Variant = data.get("cart")
	var dir: Variant = data.get("dir")
	if not (id_ok(cart) and dir is Vector3 and RpcGuard.finite_vec3(dir)):
		return {}
	var flat := Vector3((dir as Vector3).x, 0.0, (dir as Vector3).z)
	if flat.length() < 0.001:
		return {}
	var step: float = CompanyTuning.CART_PUSH_STEP_M
	var wanted: Variant = data.get("step")
	if (wanted is float or wanted is int) and is_finite(float(wanted)):
		step = clampf(float(wanted), CompanyTuning.CART_GRIP_MIN_STEP_M, CompanyTuning.CART_PUSH_STEP_M)
	return {"cart": StringName(cart), "dir": flat, "step": step}


## Host: the cart_moved a cart_push asks for at `station` (what CompanyNet's `stations` knows of the cart
## plus "at" and "stand_ok", see above), or its refusal: {reason: &"", kind, data} or {reason}.
func check(ask: Dictionary, station: Dictionary) -> Dictionary:
	var at: Variant = station.get("at")
	var stand: Variant = station.get("stand_ok")
	if ask.is_empty():
		return {"reason": REASON_BAD_DATA}
	if not (at is Vector3 and stand is Callable and (stand as Callable).is_valid()):
		return {"reason": REASON_NO_STATION}
	var from: Vector3 = at
	var step: Vector3 = (ask["dir"] as Vector3).normalized() * float(ask.get("step", CompanyTuning.CART_PUSH_STEP_M))
	var to := Vector3(from.x + step.x, 0.0, from.z + step.z)
	if not bool((stand as Callable).call(to)):
		return {"reason": REASON_BLOCKED}
	if not _at.has(ask["cart"]) and _at.size() >= MAX_CARTS:
		return {"reason": REASON_BAD_DATA}
	return {"reason": &"", "kind": MOVED, "data": {"cart": ask["cart"], "pos": to}}


## Every peer: applies a cart_moved. False, changing nothing, when the data does not fit.
func apply(data: Dictionary) -> bool:
	var cart: Variant = data.get("cart")
	var pos: Variant = data.get("pos")
	if not (id_ok(cart) and pos is Vector3 and RpcGuard.finite_vec3(pos)):
		return false
	if not _at.has(StringName(cart)) and _at.size() >= MAX_CARTS:
		return false
	_at[StringName(cart)] = pos
	return true


## The snapshot part: {cart id (text): Vector3}.
func to_dict() -> Dictionary:
	var plain: Dictionary = {}
	for cart: StringName in _at:
		plain[String(cart)] = _at[cart]
	return plain


## Client: the host's part in place of what is here. False, changing nothing, when it does not fit.
func put_snapshot(value: Variant) -> bool:
	if not value is Dictionary or (value as Dictionary).size() > MAX_CARTS:
		return false
	var found: Dictionary = {}
	for cart: Variant in value:
		var pos: Variant = (value as Dictionary)[cart]
		if not (id_ok(cart) and pos is Vector3 and RpcGuard.finite_vec3(pos)):
			return false
		found[StringName(cart)] = pos
	_at = found
	return true

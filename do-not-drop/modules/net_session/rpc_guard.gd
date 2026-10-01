class_name RpcGuard
extends RefCounted
## The checks every `@rpc("any_peer")` runs before trusting what it got.
## Portable module (docs/modulos.md): static, no session needed. Any peer may
## call those RPCs: a client with a bug sends garbage just like a troll in a
## public lobby, so each one checks who sent it and what came with it before
## the host acts on it. Pass the node the RPC runs on:
##
##   sender_ok(node[, peer])  a local call, or a connected peer (exactly `peer`, if given)
##   from_host(node)          the host is telling this peer something
##   allow_request(node)      sender_ok() plus the sender's request budget (reliable requests)
##   allow_critical_request(node)  the same, with a reserve of its own once the budget
##                            is spent: for a request whose loss leaves the host and
##                            the peer disagreeing for good (letting go of something)
##   finite_float/vec2/vec3/transform   no NaN, no inf, no absurd coordinates: one NaN
##                            in a pose breaks the physics engine for every peer
##   dict_ok(d, max_keys)     a small, flat dictionary of plain values
##   args_ok(a, max_size)     a short array of plain values
##   text_ok(s)               a short string
##   name_ok(n)               a short StringName (an id, an event name)
##   path_ok(p)               a NodePath of a sane length
##
## Whatever fails a check is dropped silently; the budget warns once per peer.
## A NetSession forgets a peer's budget when it leaves (forget_peer) and every
## budget when the session ends (reset).

## Each remote peer's budget of reliable requests, as a token bucket: up to
## REQUEST_BURST at once, refilled at REQUESTS_PER_SECOND. Mashing a key is
## about 10 a second and a joiner asks for a few things at once; a client
## looping a request can't fill the host's queue. The host's own calls never
## spend it.
const REQUESTS_PER_SECOND: float = 20.0
const REQUEST_BURST: float = 40.0
## Requests a peer must not lose to its own flood (allow_critical_request()):
## dropped, the host and that peer disagree for good -- a box still in hands on
## one side and on the floor on the other. They spend the ordinary budget while
## there is some, then a reserve of their own: CRITICAL_RESERVE at once,
## refilled at CRITICAL_PER_SECOND. A client looping one is still cut.
const CRITICAL_RESERVE: float = 10.0
const CRITICAL_PER_SECOND: float = 5.0
## Metres. Past this a coordinate is garbage (float precision was gone long
## before).
const MAX_COORDINATE: float = 1.0e6
const MAX_TEXT_LENGTH: int = 64
## Characters. A node path from one peer's tree to another's: the deepest in a
## level is under a hundred.
const MAX_PATH_LENGTH: int = 256
## Per-frame input dictionaries carry a handful of keys.
const MAX_INPUT_KEYS: int = 16
## Arguments of a relayed request (NetEventBus.request()).
const MAX_ARGS: int = 8

## Remote peer id -> {"tokens": float, "reserve": float, "at": msec, "warned": bool}.
static var _buckets: Dictionary = {}


static func _api(node: Node) -> MultiplayerAPI:
	return node.multiplayer if node != null and node.is_inside_tree() else null


## The peer an RPC is attributed to: whoever sent it, or this peer itself for
## a plain local call.
static func sender(node: Node) -> int:
	var api: MultiplayerAPI = _api(node)
	if api == null:
		return 1
	var id: int = api.get_remote_sender_id()
	return id if id != 0 else api.get_unique_id()


## A plain call, or a call_local RPC this peer sent itself.
static func is_local_call(node: Node) -> bool:
	var api: MultiplayerAPI = _api(node)
	if api == null:
		return true
	var id: int = api.get_remote_sender_id()
	return id == 0 or id == api.get_unique_id()


## The sender is someone real: a plain local call, this peer itself, or a peer
## connected right now. With `expected_peer`, it has to be exactly that peer
## (a plain local call still passes: that's the host's own code).
static func sender_ok(node: Node, expected_peer: int = 0) -> bool:
	var api: MultiplayerAPI = _api(node)
	if api == null:
		return true
	var id: int = api.get_remote_sender_id()
	if id == 0:
		return true
	if expected_peer > 0:
		return id == expected_peer
	return id == api.get_unique_id() or api.get_peers().has(id)


## The host announcing something to the peer that owns this node (an RPC
## that is any_peer only so the host can reach a node it doesn't own).
static func from_host(node: Node) -> bool:
	var api: MultiplayerAPI = _api(node)
	if api == null:
		return true
	var id: int = api.get_remote_sender_id()
	return id == 0 or id == MultiplayerPeer.TARGET_PEER_SERVER


## For every reliable request the host handles: a real sender with budget left.
static func allow_request(node: Node) -> bool:
	if not sender_ok(node):
		return false
	if is_local_call(node):
		return true
	return take_request(sender(node), Time.get_ticks_msec())


## allow_request() for a request that must not be lost to the sender's own
## flood: once its budget is spent it still has CRITICAL_RESERVE.
static func allow_critical_request(node: Node) -> bool:
	if not sender_ok(node):
		return false
	if is_local_call(node):
		return true
	return take_critical_request(sender(node), Time.get_ticks_msec())


## Spends one request from `peer_id`'s bucket at time `now_msec`. Public so
## tests can drive the clock.
static func take_request(peer_id: int, now_msec: int) -> bool:
	return _spend(peer_id, now_msec, false)


## take_request() for a critical request: the reserve once the bucket is empty.
static func take_critical_request(peer_id: int, now_msec: int) -> bool:
	return _spend(peer_id, now_msec, true)


static func _spend(peer_id: int, now_msec: int, critical: bool) -> bool:
	var bucket: Dictionary = _buckets.get(peer_id, {})
	if bucket.is_empty():
		bucket = {"tokens": REQUEST_BURST, "reserve": CRITICAL_RESERVE, "at": now_msec, "warned": false}
		_buckets[peer_id] = bucket
	var elapsed: float = maxf(0.0, float(now_msec - int(bucket["at"])) / 1000.0)
	bucket["tokens"] = minf(REQUEST_BURST, float(bucket["tokens"]) + elapsed * REQUESTS_PER_SECOND)
	bucket["reserve"] = minf(CRITICAL_RESERVE, float(bucket["reserve"]) + elapsed * CRITICAL_PER_SECOND)
	bucket["at"] = now_msec
	if float(bucket["tokens"]) >= 1.0:
		bucket["tokens"] = float(bucket["tokens"]) - 1.0
		return true
	if critical and float(bucket["reserve"]) >= 1.0:
		bucket["reserve"] = float(bucket["reserve"]) - 1.0
		return true
	# Once per peer: a flood would otherwise flood the log too.
	if not bool(bucket["warned"]):
		bucket["warned"] = true
		push_warning("RpcGuard: peer %d is over %d requests a second; dropping the rest"
			% [peer_id, roundi(REQUESTS_PER_SECOND)])
	return false


## A peer left: its budget goes with it.
static func forget_peer(peer_id: int) -> void:
	_buckets.erase(peer_id)


## The session ended: nobody's budget carries over.
static func reset() -> void:
	_buckets.clear()


static func finite_float(value: float, limit: float = MAX_COORDINATE) -> bool:
	return is_finite(value) and absf(value) <= limit


static func finite_vec2(value: Vector2) -> bool:
	return value.is_finite() and absf(value.x) <= MAX_COORDINATE and absf(value.y) <= MAX_COORDINATE


static func finite_vec3(value: Vector3) -> bool:
	return value.is_finite() and absf(value.x) <= MAX_COORDINATE and absf(value.y) <= MAX_COORDINATE \
		and absf(value.z) <= MAX_COORDINATE


## A pose a body can take: finite, within the world, and a basis that isn't
## flattened or blown up (a physics engine rejects those as surely as a NaN).
static func finite_transform(value: Transform3D) -> bool:
	if not finite_vec3(value.origin):
		return false
	var basis: Basis = value.basis
	if not (basis.x.is_finite() and basis.y.is_finite() and basis.z.is_finite()):
		return false
	var volume: float = absf(basis.determinant())
	return volume > 0.001 and volume < 1000.0


static func text_ok(value: String, max_length: int = MAX_TEXT_LENGTH) -> bool:
	return value.length() <= max_length


## An id or an event name that came over the network: short, like text_ok().
static func name_ok(value: StringName, max_length: int = MAX_TEXT_LENGTH) -> bool:
	return String(value).length() <= max_length


## A node path that came over the network, before get_node() walks it.
static func path_ok(value: NodePath, max_length: int = MAX_PATH_LENGTH) -> bool:
	return String(value).length() <= max_length


## At most `max_keys` entries, string keys, and only plain values: null, bool,
## int, finite float, short text, finite Vector2/Vector3. Nothing nested.
static func dict_ok(value: Dictionary, max_keys: int = MAX_INPUT_KEYS) -> bool:
	if value.size() > max_keys:
		return false
	for key: Variant in value:
		if not (key is String or key is StringName) or not text_ok(String(key)):
			return false
		if not plain_value(value[key]):
			return false
	return true


## At most `max_size` plain values (plain_value()), nothing nested.
static func args_ok(value: Array, max_size: int = MAX_ARGS) -> bool:
	if value.size() > max_size:
		return false
	for item: Variant in value:
		if not plain_value(item):
			return false
	return true


## null, bool, int, finite float, short text or a finite Vector2/Vector3.
static func plain_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return finite_float(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return text_ok(String(value))
		TYPE_VECTOR2:
			return finite_vec2(value)
		TYPE_VECTOR3:
			return finite_vec3(value)
	return false

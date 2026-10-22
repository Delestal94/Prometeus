extends Node
class_name NetRestThrottle
## The sending side of a replicated pose: while what a MultiplayerSynchronizer
## sends stays put, it goes out every `rest_interval` instead of every tick --
## a box on a shelf, one riding still in the truck, one asleep on the floor.
##
## A child of the synchronized body. It watches the properties in `watched` on
## the synchronizer's root (a Transform3D within `max_distance` and
## `max_angle`, a Vector3 within `max_distance`, anything else for equality).
## After `settle_seconds` without a change it sets the synchronizer's
## replication_interval to `rest_interval`; the first change puts the
## original interval back in the same tick, before the next send.
##
## Why it never goes fully quiet: the poses travel unreliable, so the settle
## window keeps sending the final one at full rate for a while (one lost as it
## stopped doesn't leave a peer with an old pose), and the slow trickle after
## it is what a late joiner gets. SceneMultiplayer also drops a sync whose
## 16-bit clock looks older than the last one, and that clock wraps after
## 65536 network frames.
##
## A peer the synchronizer was just made visible to (update_visibility(peer),
## how a game lets a late joiner in) wakes it, so that peer gets the pose at
## full rate at once. Hiding it from a peer (its visibility flag off, the
## synchronizer not public) doesn't: nobody new gets anything. Nor does a
## change made while the synchronizer has the meta QUIET_META set to true (a
## keepalive pulse: it lasts two of its intervals at whatever rate it is on,
## and waking it would send every peer that sees it the full rate for nothing).
## Only the multiplayer authority throttles; on the others the node does nothing.
##
## Muted (set_muted()), it sends every `muted_interval` whatever the body does:
## for a pose the other peers draw some other way meanwhile (a box in someone's
## hands, drawn on them). Unmuted it's back to every tick at once, for a whole
## settle window, as if it had just moved. A visibility change doesn't unmute
## it, but showing it to a peer, a quiet keepalive pulse included, sends a pose
## at once (every tick for MUTED_SHOW_FRAMES rendered frames, then muted again):
## a late joiner gets one before a far-copy rule calls its copy stale, and a
## pulse still moves that peer's sync clock.

## A synchronizer whose visibility changes while it has this meta set to true doesn't wake its throttle.
const QUIET_META: StringName = &"net_rest_quiet"
## Rendered frames a muted synchronizer goes every tick after it's shown to a peer: SceneMultiplayer sends once a
## frame, so two make sure one send falls after the change.
const MUTED_SHOW_FRAMES: int = 2

@export var synchronizer_path: NodePath = ^"../MultiplayerSynchronizer"
## Properties of the synchronizer's root that make up the pose.
@export var watched: Array[StringName] = [&"transform"]
@export var rest_interval: float = 0.5
@export var settle_seconds: float = 0.5
## Metres a position may drift from where it last moved and still count as at
## rest: a peer's copy of a resting body is never off by more than twice this,
## and each slow send corrects it.
@export var max_distance: float = 0.005
## Radians, the same for a rotation.
@export var max_angle: float = 0.01
## Seconds between sends while muted: seldom enough to cost next to nothing,
## often enough that SceneMultiplayer's 16-bit sync clock (above) can't wrap on
## a body muted for minutes, and a late joiner still gets a pose.
@export var muted_interval: float = 5.0

var _sync: MultiplayerSynchronizer
var _root: Node
var _active_interval: float = 0.0
var _reference: Array = []
var _still_seconds: float = 0.0
var _resting: bool = false
var _muted: bool = false
var _show_frames: int = 0


func _ready() -> void:
	_sync = get_node_or_null(synchronizer_path) as MultiplayerSynchronizer
	_root = _sync.get_node_or_null(_sync.root_path) if _sync != null else null
	if _root == null:
		push_error("NetRestThrottle %s: no synchronizer with a root at %s" % [get_path(), synchronizer_path])
		set_physics_process(false)
		return
	for property: StringName in watched:
		if not property in _root:
			push_error("NetRestThrottle %s: %s has no property %s" % [get_path(), _root.name, property])
			set_physics_process(false)
			return
	_active_interval = _sync.replication_interval
	_sync.visibility_changed.connect(_on_visibility_changed)
	_capture()
	set_process(false)
	if _muted and _sync.is_multiplayer_authority():
		_sync.replication_interval = _interval()


func _physics_process(delta: float) -> void:
	if not _sync.is_multiplayer_authority():
		return
	if _moved():
		_capture()
		_still_seconds = 0.0
	else:
		_still_seconds += delta
	_apply()


## Whether the synchronizer is on its slow rest interval right now.
func is_resting() -> bool:
	return _resting


## Back to every tick for a full settle window, as if it had just moved (still muted if it is).
func wake() -> void:
	_still_seconds = 0.0
	_apply()


## Muted: every `muted_interval`, moving or not (see the header). Unmuting puts every tick back in the same
## tick, before the next send, for a whole settle window. Only the authority's rate changes.
func set_muted(muted: bool) -> void:
	if muted == _muted:
		return
	_muted = muted
	_still_seconds = 0.0
	_resting = false
	if _sync != null and _root != null and _sync.is_multiplayer_authority():
		_sync.replication_interval = _interval()


## Whether set_muted() holds it at muted_interval.
func is_muted() -> bool:
	return _muted


func _apply() -> void:
	var resting: bool = _still_seconds >= settle_seconds
	if resting == _resting:
		return
	_resting = resting
	_sync.replication_interval = _interval()


func _interval() -> float:
	if _muted:
		return _active_interval if _show_frames > 0 else muted_interval
	return rest_interval if _resting else _active_interval


## Muted and just shown to a peer: every tick for MUTED_SHOW_FRAMES frames, then muted again.
func _process(_delta: float) -> void:
	_show_frames -= 1
	if _show_frames > 0:
		return
	_show_frames = 0
	set_process(false)
	if _sync.is_multiplayer_authority():
		_sync.replication_interval = _interval()


func _capture() -> void:
	_reference.clear()
	for property: StringName in watched:
		_reference.append(_root.get(property))


func _moved() -> bool:
	for index: int in range(watched.size()):
		var now: Variant = _root.get(watched[index])
		var then: Variant = _reference[index]
		if typeof(now) != typeof(then):
			return true
		match typeof(now):
			TYPE_TRANSFORM3D:
				var a: Transform3D = now
				var b: Transform3D = then
				if a.origin.distance_to(b.origin) > max_distance:
					return true
				if a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()) > max_angle:
					return true
			TYPE_VECTOR3:
				if (now as Vector3).distance_to(then as Vector3) > max_distance:
					return true
			_:
				if now != then:
					return true
	return false


## The game calls update_visibility(peer) when that peer can start receiving
## (0 is the synchronizer's own per-frame refresh, not someone new).
func _on_visibility_changed(for_peer: int) -> void:
	if for_peer == 0:
		return
	if not _sync.public_visibility and not _sync.get_visibility_for(for_peer):
		return
	if _muted:
		_show_frames = MUTED_SHOW_FRAMES
		set_process(true)
		if _sync.is_multiplayer_authority():
			_sync.replication_interval = _interval()
		return
	if bool(_sync.get_meta(QUIET_META, false)):
		return
	wake()

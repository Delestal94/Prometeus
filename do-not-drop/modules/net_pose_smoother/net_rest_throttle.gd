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
## full rate at once. Only the multiplayer authority throttles; on the others
## the node does nothing.

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

var _sync: MultiplayerSynchronizer
var _root: Node
var _active_interval: float = 0.0
var _reference: Array = []
var _still_seconds: float = 0.0
var _resting: bool = false


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


## Back to every tick for a full settle window, as if it had just moved.
func wake() -> void:
	_still_seconds = 0.0
	_apply()


func _apply() -> void:
	var resting: bool = _still_seconds >= settle_seconds
	if resting == _resting:
		return
	_resting = resting
	_sync.replication_interval = rest_interval if resting else _active_interval


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
	if for_peer != 0:
		wake()

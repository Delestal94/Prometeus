extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/net_pose_smoother/tests/test_net_rest_throttle.gd
##
## NetRestThrottle on its own (net_rest_throttle.gd, N-228.5): a synchronized
## body that keeps moving sends every tick; left still for settle_seconds it
## drops to rest_interval; any move past max_distance or max_angle -- also a
## slow creep that adds up -- or a change in another watched property brings
## the full rate back in the same tick; a peer the synchronizer is made
## visible to wakes it, the per-frame refresh (peer 0) doesn't; a watched
## property the body doesn't have leaves the rate alone.

const TICK: float = 1.0 / 60.0
const ACTIVE: float = 1.0 / 60.0

var _failures: int = 0


class Body:
	extends Node3D
	var riding: bool = false


func _initialize() -> void:
	var body := Body.new()
	body.name = "Body"
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSynchronizer"
	sync.root_path = ^".."
	sync.replication_interval = ACTIVE
	body.add_child(sync)
	var throttle := NetRestThrottle.new()
	throttle.watched = [&"transform", &"riding"]
	body.add_child(throttle)
	root.add_child(body)
	await process_frame
	throttle.set_physics_process(false)  # Stepped by hand below.

	for tick: int in range(60):
		body.position.x += 0.05
		throttle._physics_process(TICK)
	_expect(not throttle.is_resting() and is_equal_approx(sync.replication_interval, ACTIVE),
		"A moving body sends every tick (interval %.4f)" % sync.replication_interval)
	_settle(throttle)
	_expect(throttle.is_resting() and is_equal_approx(sync.replication_interval, throttle.rest_interval),
		"Still for settle_seconds, it sends every rest_interval (interval %.4f)" % sync.replication_interval)

	body.position.x += 0.05
	throttle._physics_process(TICK)
	_expect(is_equal_approx(sync.replication_interval, ACTIVE), "A move brings every tick back at once")
	_settle(throttle)
	body.position.x += throttle.max_distance * 0.5
	throttle._physics_process(TICK)
	_expect(throttle.is_resting(), "A nudge under max_distance keeps it resting")
	for tick: int in range(4):
		body.position.x += throttle.max_distance * 0.5
		throttle._physics_process(TICK)
	_expect(not throttle.is_resting(), "Nudges that add up past max_distance wake it (a slow creep)")

	_settle(throttle)
	body.rotate_y(throttle.max_angle * 2.0)
	throttle._physics_process(TICK)
	_expect(not throttle.is_resting(), "Turning past max_angle wakes it")
	_settle(throttle)
	body.riding = true
	throttle._physics_process(TICK)
	_expect(not throttle.is_resting(), "Any other watched property changing wakes it")

	_settle(throttle)
	sync.update_visibility(0)
	_expect(throttle.is_resting(), "The synchronizer's own visibility refresh (peer 0) doesn't wake it")
	# What update_visibility(peer) emits for a connected peer. This test has no
	# peer 5, so the replication interface logs that it doesn't know it.
	sync.visibility_changed.emit(5)
	_expect(not throttle.is_resting() and is_equal_approx(sync.replication_interval, ACTIVE),
		"A peer it was just made visible to wakes it, to get the pose at full rate")

	var typo := NetRestThrottle.new()
	typo.watched = [&"net_transfrom"]
	body.add_child(typo)
	await process_frame
	_expect(not typo.is_physics_processing(), "A watched property the body lacks turns the throttle off")

	body.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: NetRestThrottle sends a resting pose slowly and wakes on any change")
	quit(_failures)


func _settle(throttle: NetRestThrottle) -> void:
	for tick: int in range(ceili(throttle.settle_seconds / TICK) + 1):
		throttle._physics_process(TICK)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/net_pose_smoother/tests/test_net_rest_throttle.gd
##
## NetRestThrottle on its own (net_rest_throttle.gd, N-228.5): a synchronized
## body that keeps moving sends every tick; left still for settle_seconds it
## drops to rest_interval; any move past max_distance or max_angle -- also a
## slow creep that adds up -- or a change in another watched property brings
## the full rate back in the same tick; a peer the synchronizer is made
## visible to wakes it (public, or by its flag), the per-frame refresh (peer 0) doesn't, nor hiding it
## from a peer, nor a change made with QUIET_META set (a keepalive pulse); a
## watched property the body doesn't have leaves the rate alone.
## Muted (set_muted(), D-2002.5: a box in someone's hands), it sends every
## muted_interval moving or still, a peer it's shown to doesn't change that;
## unmuted, every tick comes back at once and stays for a settle window.

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
	_settle(throttle)
	sync.public_visibility = false
	sync.visibility_changed.emit(6)
	_expect(throttle.is_resting(), "Hiding it from a peer (flag off, not public) doesn't wake it")
	# Not public, but this peer's flag on: shown to it for real (a late joiner, someone walking up).
	sync.set_visibility_for(7, true)
	_settle(throttle)
	sync.visibility_changed.emit(7)
	_expect(not throttle.is_resting(), "Shown to a peer through its flag (not public) wakes it")
	sync.set_visibility_for(7, false)
	_settle(throttle)
	# Visible again, so only the meta can keep this change from waking it.
	sync.public_visibility = true
	sync.set_meta(NetRestThrottle.QUIET_META, true)
	sync.visibility_changed.emit(5)
	sync.remove_meta(NetRestThrottle.QUIET_META)
	_expect(throttle.is_resting(), "A change made with QUIET_META set (a keepalive pulse) doesn't wake it")

	_check_muted(body, sync, throttle)

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


## set_muted(): the muted interval whatever the body does, until unmuted (then every tick for a settle window).
func _check_muted(body: Body, sync: MultiplayerSynchronizer, throttle: NetRestThrottle) -> void:
	_settle(throttle)
	throttle.set_muted(true)
	_expect(throttle.is_muted() and is_equal_approx(sync.replication_interval, throttle.muted_interval),
		"Muted, it sends every muted_interval at once (interval %.4f)" % sync.replication_interval)
	for tick: int in range(30):
		body.position.x += 0.05
		throttle._physics_process(TICK)
	_expect(is_equal_approx(sync.replication_interval, throttle.muted_interval),
		"Muted, moving doesn't bring every tick back (interval %.4f)" % sync.replication_interval)
	_settle(throttle)
	_expect(is_equal_approx(sync.replication_interval, throttle.muted_interval),
		"Muted, coming to rest doesn't put rest_interval on it (interval %.4f)" % sync.replication_interval)
	sync.visibility_changed.emit(5)
	_expect(is_equal_approx(sync.replication_interval, throttle.muted_interval),
		"Muted, a peer it's shown to doesn't unmute it (interval %.4f)" % sync.replication_interval)
	throttle.set_muted(false)
	_expect(not throttle.is_muted() and not throttle.is_resting()
		and is_equal_approx(sync.replication_interval, ACTIVE),
		"Unmuted, every tick is back at once (interval %.4f)" % sync.replication_interval)
	for tick: int in range(ceili(throttle.settle_seconds / TICK) - 1):
		throttle._physics_process(TICK)
	_expect(is_equal_approx(sync.replication_interval, ACTIVE),
		"...and stays for the settle window even if it doesn't move (interval %.4f)" % sync.replication_interval)
	_settle(throttle)
	_expect(throttle.is_resting() and is_equal_approx(sync.replication_interval, throttle.rest_interval),
		"Then still, it rests as before (interval %.4f)" % sync.replication_interval)


func _settle(throttle: NetRestThrottle) -> void:
	for tick: int in range(ceili(throttle.settle_seconds / TICK) + 1):
		throttle._physics_process(TICK)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

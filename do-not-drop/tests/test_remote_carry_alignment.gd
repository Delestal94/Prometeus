extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_remote_carry_alignment.gd
##
## A box in a remote player's hands stays in those hands (N-217, PackageNetPose). The carrier's body is drawn
## from its pose buffer, 50-200 ms in the past; the box used to be drawn at the newest carry pose (on the host)
## or from its own buffer (on a third peer), so at a walk it floated well ahead of the hands. Now the carrier
## sends the pose in its body's space too (submit_carry_transform's `in_hands`), the host replicates who holds it
## and where (carrier_peer_id, hold_offset), and every peer but the carrier's draws it on the body it draws.
##
## Measured with a carrier walking at 3.6 m/s, its poses 40 ms late plus up to 10 ms of jitter, the carry
## poses 40 ms late:
## - on the host: the newest carry pose is well off the drawn hands, the box drawn within 5 cm of them, and
##   the host still simulates the box at the newest carry pose (what its physics and traps see);
## - on a third peer (a client copy of the box, not the carrier's): within 5 cm too;
## - the carrier's body space round-trips: hold_offset is what it sent; dropping clears it.

const SPEED: float = 3.6
const RATE: float = 30.0
const ONE_WAY: float = 0.04
const LIMIT: float = 0.05

var _failures: int = 0
var _in_hands := Transform3D(Basis(Vector3.UP, 0.2), Vector3(0.05, 1.05, -0.55))


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var world: Node3D = level.get_node(^"World")
	var box: Node3D = get_nodes_in_group(&"cargo")[0]
	var remote: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	remote.name = "Player_2"
	world.add_child(remote)
	await process_frame
	_expect(not remote.call(&"is_local"), "Player_2 is another peer's player here")
	box.call(&"take_by", remote)
	_expect(bool(box.get(&"is_held")) and remote.get(&"carried_package") == box, "The remote player holds the box")

	# A probe after every _process: what's on screen this frame.
	var probe_script := GDScript.new()
	probe_script.source_code = ("extends Node\nvar sample: Callable\n"
			+ "func _process(_d: float) -> void:\n\tif sample.is_valid(): sample.call()\n")
	probe_script.reload()
	var probe := Node.new()
	probe.set_script(probe_script)
	probe.process_priority = 1000
	root.add_child(probe)

	# --- on the host ---
	var host: Array[float] = await _walk(box, remote, probe, false)
	_expect(host[1] > 0.15, "On the host the newest carry pose is well off the hands as drawn (%.2f m)" % host[1])
	_expect(host[0] < LIMIT,
		"...but the box is drawn within %.0f cm of them (%.1f cm)" % [LIMIT * 100.0, host[0] * 100.0])
	var offset: Transform3D = box.get(&"hold_offset")
	_expect(int(box.get(&"carrier_peer_id")) == 2 and offset.is_equal_approx(_in_hands),
		"The host replicates who holds it and where in their hands")
	await physics_frame
	var newest: Transform3D = box.get(&"_carry_pose")
	box.call(&"_physics_process", 0.0)
	_expect(box.global_position.distance_to(newest.origin) < 0.001,
		"The host still simulates the box at the newest carry pose")

	# --- on a third peer: a client's copy of the box ---
	box.set_multiplayer_authority(5)
	var third: Array[float] = await _walk(box, remote, probe, true)
	_expect(third[0] < LIMIT, "On a third peer the box is drawn within %.0f cm of the carrier's hands (%.1f cm)"
			% [LIMIT * 100.0, third[0] * 100.0])
	box.set_multiplayer_authority(1)
	print("remote carry: host box %.1f cm off the hands (newest carry pose %.1f cm), third peer %.1f cm" % [
		host[0] * 100.0, host[1] * 100.0, third[0] * 100.0])

	box.call(&"set_held", false)
	_expect(int(box.get(&"carrier_peer_id")) == 0 and box.get(&"hold_offset") == Transform3D.IDENTITY,
		"Let go, nobody holds it any more")
	probe.free()
	level.free()
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: a box in a remote player's hands is drawn in them on the host and on every other peer")
	quit(_failures)


## The carrier walks for 1.5 s; returns [worst box-to-hands distance, worst newest-carry-to-hands distance]
## after the first half second. `as_client`: the box is a client's copy, fed what the host replicates.
func _walk(box: Node3D, remote: Node3D, probe: Node, as_client: bool) -> Array[float]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2171
	var start := Vector3(15.0, 0.3, -15.0) + (Vector3(0.0, 0.0, 6.0) if as_client else Vector3.ZERO)
	var body := func(t: float) -> Transform3D: return Transform3D(Basis(), start + Vector3(SPEED * t, 0.0, 0.0))
	var packets: Array = []
	for k: int in range(int(2.0 * RATE)):
		packets.append([k / RATE + ONE_WAY + rng.randf_range(0.0, 0.01), k / RATE])
	packets.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var worst: Array[float] = [0.0, 0.0]
	var elapsed: Array[float] = [0.0]
	var base_ms: int = 700000 if as_client else 600000
	probe.set(&"sample", func() -> void:
		if elapsed[0] < 0.5:
			return
		var hands: Vector3 = (remote.global_transform * _in_hands).origin
		worst[0] = maxf(worst[0], box.global_position.distance_to(hands))
		var newest: Vector3 = (body.call(elapsed[0] - ONE_WAY) * _in_hands).origin
		worst[1] = maxf(worst[1], newest.distance_to(hands)))
	var began: int = Time.get_ticks_usec()
	var next: int = 0
	while true:
		var t: float = (Time.get_ticks_usec() - began) / 1000000.0
		if t > 1.5:
			break
		elapsed[0] = t
		while next < packets.size() and float(packets[next][0]) <= t:
			var sent: float = packets[next][1]
			remote.set(&"net_time", base_ms + roundi(sent * 1000.0))
			remote.set(&"net_in_vehicle", false)
			remote.set(&"net_position", (body.call(sent) as Transform3D).origin)
			remote.set(&"net_yaw", 0.0)
			(remote.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer).synchronized.emit()
			next += 1
		var carry: Transform3D = body.call(maxf(t - ONE_WAY, 0.0)) * _in_hands
		if as_client:
			# What the host replicates with the box's pose.
			box.set(&"carrier_peer_id", 2)
			box.set(&"hold_offset", _in_hands)
			box.set(&"net_transform", carry)
		else:
			box.call(&"submit_carry_transform", carry, false, _in_hands)
		await process_frame
	probe.set(&"sample", Callable())
	return worst


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

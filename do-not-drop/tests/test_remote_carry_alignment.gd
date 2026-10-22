extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_remote_carry_alignment.gd
##
## A box in a remote player's hands stays in those hands (N-217, PackageNetPose), and while it's there the host
## doesn't send its pose (D-2002.5). The carrier's body is drawn from its pose buffer, 50-200 ms in the past; the
## box used to be drawn at the newest carry pose (on the host) or from its own buffer (on a third peer), so at a walk
## it floated well ahead of the hands. The host replicates who holds it (carrier_peer_id) and every peer but the
## carrier's draws it where that player's own code holds it (PlayerCarry.hands_pose()) on the body it draws: no
## box pose is needed for that, so the host mutes it (NetRestThrottle.set_muted(): a pose every muted_interval).
##
## Measured with a carrier walking at 3.6 m/s, its poses 40 ms late plus up to 10 ms of jitter, the carry
## poses 40 ms late:
## - on the host: held on foot, the box's synchronizer goes to the muted interval (what SceneMultiplayer reads to
##   send it); the newest carry pose is well off the drawn hands, the box drawn within 5 cm of them (it rides the
##   drawn body), and the host still simulates the box at the newest carry pose (what its physics and traps see);
## - on a third peer, with no pose of the box at all (a trickle pose that lands is ignored): within 5 cm too;
## - let go on that peer (the reliable is_held/carrier_peer_id delta lands first): the box stays where it was drawn
##   (not back where the host had it before the hold, the buffer's stale poses) until the host's first fresh pose,
##   then eases to it (never more than 5 cm a frame at 144 fps) and ends there; the carrier's own client, which
##   predicted it, does the same;
## - in the bay of a truck moving at 20 m/s, drawn by hand at 60 fps: a third peer whose copy of the carrier sits
##   down before the host's carrier_peer_id 0 lands, and the carrier's own client with a menu open (no prediction,
##   still muted) and then letting go, keep the box within 5 cm of where the hands held it in the truck's space
##   until the host's first fresh pose, and it stays there once that pose (in the truck's space) lands;
## - a late joiner's copy, which never got a pose, is drawn in the carrier's hands;
## - dropped on the host, the full rate is back on the next tick (not muted, every tick, not resting) and nobody
##   holds it any more.

const SPEED: float = 3.6
const RATE: float = 30.0
const ONE_WAY: float = 0.04
const LIMIT: float = 0.05
const FPS: float = 144.0

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var world: Node3D = level.get_node(^"World")
	var box: DeliveryPackage = get_nodes_in_group(&"cargo")[0]
	var remote: Player = load("res://scenes/gameplay/player/player.tscn").instantiate()
	remote.name = "Player_2"
	world.add_child(remote)
	await process_frame
	_expect(not remote.is_local(), "Player_2 is another peer's player here")
	box.take_by(remote)
	_expect(box.is_held and remote.carried_package == box, "The remote player holds the box")
	# Past the lift (PlayerCarry.hands_pose() eases the box up from where it lay for 1.3 s).
	remote._pickup_elapsed = 2.0
	var sync := box.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var throttle := box.get_node(^"NetRestThrottle") as NetRestThrottle
	var active: float = sync.replication_interval

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
	box.submit_carry_transform(remote._carry_component.hands_pose(box), false)
	await _tick()
	_expect(box.carrier_peer_id == 2 and throttle.is_muted()
		and is_equal_approx(sync.replication_interval, throttle.muted_interval),
		"Held on foot, the host replicates who holds it and sends its pose every %.1f s (interval %.4f)"
		% [throttle.muted_interval, sync.replication_interval])
	var host: Array[float] = await _walk(box, remote, probe, false)
	_expect(host[1] > 0.15, "On the host the newest carry pose is well off the hands as drawn (%.2f m)" % host[1])
	_expect(host[0] < LIMIT,
		"...but the box is drawn within %.0f cm of them (%.1f cm)" % [LIMIT * 100.0, host[0] * 100.0])
	await physics_frame
	var newest: Transform3D = box._carry_pose
	box._physics_process(0.0)
	_expect(box.global_position.distance_to(newest.origin) < 0.001,
		"The host still simulates the box at the newest carry pose")
	_expect(is_equal_approx(sync.replication_interval, throttle.muted_interval),
		"...and still sends its pose only every %.1f s while held" % throttle.muted_interval)

	# --- on a third peer: a client's copy of the box, which gets no pose of it while held ---
	box.set_multiplayer_authority(5)
	var third: Array[float] = await _walk(box, remote, probe, true)
	_expect(third[0] < LIMIT, "On a third peer the box is drawn within %.0f cm of the carrier's hands (%.1f cm)"
			% [LIMIT * 100.0, third[0] * 100.0])
	print("remote carry: host box %.1f cm off the hands (newest carry pose %.1f cm), third peer %.1f cm" % [
		host[0] * 100.0, host[1] * 100.0, third[0] * 100.0])
	_check_let_go(box, remote, false)
	_check_let_go(box, level.local_player, true)
	_check_truck_let_go(box, remote, level.vehicle, false)
	_check_truck_let_go(box, level.local_player, level.vehicle, true)
	await _check_late_joiner(world, remote)

	# --- dropped on the host: the full rate is back ---
	box.set_multiplayer_authority(1)
	box.take_by(remote)
	box.submit_carry_transform(remote.global_transform, false)
	await _tick()
	_expect(throttle.is_muted(), "Taken again on foot, muted again")
	box.request_drop(Transform3D(Basis(), remote.global_position + Vector3(0.0, 0.4, -0.8)), false)
	_expect(not box.is_held and box.carrier_peer_id == 0, "Let go, nobody holds it any more")
	await _tick()
	_expect(not throttle.is_muted() and not throttle.is_resting()
		and is_equal_approx(sync.replication_interval, active),
		"Dropped, its pose goes every tick again from the next tick (interval %.4f)" % sync.replication_interval)
	probe.free()
	level.free()
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: a box in a remote player's hands is drawn in them on every peer, its pose muted until let go")
	quit(_failures)


## The carrier walks for 1.5 s; returns [worst box-to-hands distance, worst newest-carry-to-hands distance]
## after the first half second: the hands as drawn are where the drawn body's PlayerCarry holds the box this frame
## (a wall it walks past pulls them back, as on the carrier's own screen), the newest carry pose the same hold on
## the body where the carrier last said it was. `as_client`: the box is a client's copy, told only who holds it,
## as the host replicates it (no pose: muted; one trickle pose that lands mid-walk is ignored).
func _walk(box: DeliveryPackage, remote: Player, probe: Node, as_client: bool) -> Array[float]:
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
	var in_body: Array = [null]
	var base_ms: int = 700000 if as_client else 600000
	if as_client:
		box.is_held = true
		box.carrier_peer_id = 2
	probe.set(&"sample", func() -> void:
		var held: Transform3D = remote._carry_component.hands_pose(box)
		in_body[0] = remote.global_transform.affine_inverse() * held
		if elapsed[0] < 0.5:
			return
		worst[0] = maxf(worst[0], box.global_position.distance_to(held.origin))
		var newest: Vector3 = (body.call(elapsed[0] - ONE_WAY) * (in_body[0] as Transform3D)).origin
		worst[1] = maxf(worst[1], newest.distance_to(held.origin)))
	var began: int = Time.get_ticks_usec()
	var next: int = 0
	var trickled: bool = false
	while true:
		var t: float = (Time.get_ticks_usec() - began) / 1000000.0
		if t > 1.5:
			break
		elapsed[0] = t
		while next < packets.size() and float(packets[next][0]) <= t:
			var sent: float = packets[next][1]
			remote.net_time = base_ms + roundi(sent * 1000.0)
			remote.net_in_vehicle = false
			remote.net_position = (body.call(sent) as Transform3D).origin
			remote.net_yaw = 0.0
			(remote.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer).synchronized.emit()
			next += 1
		var carry: Transform3D = body.call(maxf(t - ONE_WAY, 0.0)) * (in_body[0] as Transform3D
				if in_body[0] != null else Transform3D(Basis(), Vector3(0.0, 1.05, -0.55)))
		if not as_client:
			box.submit_carry_transform(carry, false)
		elif t > 1.0 and not trickled:
			# The muted interval's trickle: where the host had it, which a held copy doesn't buffer.
			trickled = true
			box.net_transform = carry
			box.net_time = base_ms + roundi(t * 1000.0)
			box._net_view.push(box)
		await process_frame
	probe.set(&"sample", Callable())
	return worst


## A client's copy let go of after a muted hold (`own`: on the carrier's own client, which predicted it in its
## hands; else drawn on the remote carrier): its buffer holds the poses from before the hold, 3 m away. Drawn by
## hand at FPS: it stays where it was drawn until a fresh pose lands, eases to it, ends there.
func _check_let_go(box: DeliveryPackage, carrier: Player, own: bool) -> void:
	var view: PackageNetPose = box._net_view
	var what: String = "the carrier's own client" if own else "a third peer"
	var now: float = 50.0 + (10.0 if own else 0.0)
	var before := Transform3D(Basis(), carrier.global_position + Vector3(3.0, 0.4, 0.0))
	box.is_held = false
	box.carrier_peer_id = 0
	for k: int in range(6):
		box.net_in_vehicle = false
		box.net_transform = before
		box.net_time = 900000 + (100000 if own else 0) + k * 33
		view.push(box, now + k / RATE)
	now += 0.5
	box.is_held = true
	box.carrier_peer_id = carrier.get_multiplayer_authority()
	var hands: Transform3D = carrier._carry_component.hands_pose(box)
	for frame: int in range(30):
		if own:
			box.predict_carry(hands, false)
		view.draw(box, 1.0 / FPS, now)
		now += 1.0 / FPS
	_expect(box.global_position.distance_to(hands.origin) < 0.01, "Held, %s draws the box in the hands" % what)
	# The hold ends: the delta first, the first fresh pose a round trip later.
	box.is_held = false
	box.carrier_peer_id = 0
	box._predicted_frame = -100
	var drawn: Vector3 = box.global_position
	for frame: int in range(12):
		view.draw(box, 1.0 / FPS, now)
		now += 1.0 / FPS
	_expect(box.global_position.distance_to(drawn) < 0.001,
		"Let go, %s keeps it where it was drawn until a fresh pose (not at the stale one, %.2f m off)"
		% [what, box.global_position.distance_to(before.origin)])
	var dropped := Transform3D(Basis(), drawn + Vector3(0.0, -0.6, -0.3))
	var worst_jump: float = 0.0
	var previous: Vector3 = drawn
	for frame: int in range(int(FPS * 0.6)):
		if frame % 5 == 0:
			box.net_transform = dropped
			box.net_time = 2000000 + (100000 if own else 0) + frame * 7
			view.push(box, now)
		view.draw(box, 1.0 / FPS, now)
		worst_jump = maxf(worst_jump, box.global_position.distance_to(previous))
		previous = box.global_position
		now += 1.0 / FPS
	_expect(worst_jump < 0.05, "...then %s eases it to the host's pose, at most 5 cm a frame (%.1f cm)"
		% [what, worst_jump * 100.0])
	_expect(box.global_position.distance_to(dropped.origin) < 0.01,
		"...and %s ends where the host has it (%.2f m off)" % [what, box.global_position.distance_to(dropped.origin)])


## A client's copy in the bay of a truck moving at 20 m/s (this process's truck put by hand each frame at FPS, not
## interpolated, as a client's is). `own`: the carrier is this peer's player, holding it with a menu open (no
## prediction) and then letting go; else another's, whose copy sits down before the host's carrier_peer_id 0. The
## box stays where the hands held it in the truck's space, within LIMIT, until the host's fresh pose there.
func _check_truck_let_go(box: DeliveryPackage, carrier: Player, van: Node3D, own: bool) -> void:
	var what: String = "the carrier's own client" if own else "a third peer"
	var view: PackageNetPose = box._net_view
	var parked: Transform3D = van.global_transform
	var interpolation: Node.PhysicsInterpolationMode = van.physics_interpolation_mode
	van.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	carrier.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var body := Transform3D(Basis(), Vector3(0.0, 0.3, 3.0))
	var held: DeliveryPackage = carrier.carried_package
	box.is_held = true
	box.carrier_peer_id = carrier.get_multiplayer_authority()
	box._predicted_frame = -100
	if own:
		carrier.carried_package = box
	var dt: float = 1.0 / 60.0
	var now: float = 80.0 + (10.0 if own else 0.0)
	var in_truck: Variant = null
	var worst: float = 0.0
	var off_hands: float = 0.0
	for frame: int in range(90):
		van.global_transform = parked.translated(-parked.basis.z * 20.0 * frame * dt)
		carrier.global_transform = van.global_transform * body
		if frame == 30:
			# Let go here: the seat lands before carrier_peer_id 0 (another's), or the hands let go (own).
			if own:
				carrier.carried_package = null
			else:
				carrier.seat_node_path = ^"Seat"
		if frame == 45:
			box.is_held = false
			box.carrier_peer_id = 0
		if frame >= 60 and frame % 2 == 0:
			box.net_in_vehicle = true
			box.net_transform = in_truck
			box.net_time = 3000000 + (100000 if own else 0) + frame * 17
			view.push(box, now)
		view.draw(box, dt, now)
		var here: Transform3D = van.global_transform.affine_inverse() * box.global_transform
		if frame < 30:
			var hands: Vector3 = carrier._carry_component.hands_pose(box).origin
			off_hands = maxf(off_hands, box.global_position.distance_to(hands))
		if frame == 29:
			in_truck = here
		elif frame > 29:
			worst = maxf(worst, here.origin.distance_to((in_truck as Transform3D).origin))
		now += dt
	var bay: Vector3 = (van.global_transform * (in_truck as Transform3D)).origin if in_truck != null else Vector3.INF
	_expect(in_truck != null and bool(van.call(&"carries", bay, 0.4)),
		"%s: the hands hold the box in the truck's bay" % what)
	_expect(off_hands < LIMIT, "Held in a truck at 20 m/s, %s draws the box in the hands (%.1f cm off at worst)%s"
		% [what, off_hands * 100.0, ", a menu open: no prediction" if own else ""])
	_expect(worst < LIMIT, ("In a truck at 20 m/s, %s keeps the box let go of where the hands held it in the"
		+ " truck's space until the host's pose (%.1f cm off at worst)") % [what, worst * 100.0])
	carrier.seat_node_path = NodePath()
	carrier.carried_package = held
	van.global_transform = parked
	van.physics_interpolation_mode = interpolation
	van.reset_physics_interpolation()
	carrier.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT


## A late joiner's copy of a held box: no pose ever came (the host sends one every muted_interval), only who holds
## it (the delta of every ON_CHANGE property it gets on joining) and the carrier's pick_up again (N-908), which
## starts a lift from wherever this copy happens to be. Drawn in the carrier's hands, without that lift.
func _check_late_joiner(world: Node3D, remote: Player) -> void:
	var late: DeliveryPackage = load("res://scenes/gameplay/package/package.tscn").instantiate()
	late.package_id = &"late_joiner_box"
	late.set_multiplayer_authority(5)
	world.add_child(late)
	late.position = remote.global_position + Vector3(6.0, 0.0, 6.0)
	late.is_held = true
	late.carrier_peer_id = 2
	remote._pickup_elapsed = 0.0
	remote._pickup_from = late.global_transform
	await process_frame
	await process_frame
	# Where the hands hold it past the lift, this frame.
	remote._pickup_elapsed = 2.0
	var hands: Transform3D = remote._carry_component.hands_pose(late)
	_expect(not late._has_net_state and late.global_position.distance_to(hands.origin) < 0.01,
		"A late joiner's copy that never got a pose is drawn in the carrier's hands at once (%.2f m off)"
		% late.global_position.distance_to(hands.origin))
	late.free()


## A whole physics tick: physics_frame comes before the nodes' _physics_process.
func _tick() -> void:
	await physics_frame
	await physics_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

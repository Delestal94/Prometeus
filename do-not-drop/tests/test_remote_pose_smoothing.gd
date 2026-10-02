extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_remote_pose_smoothing.gd
##
## Remote players and boxes drawn smoothly (N-217, docs/investigacion-red.md fase 2):
## - what goes over the wire: players and boxes sync at 30 Hz, each pose
##   carries its owner's clock (net_time) as the last property of the
##   packet, so its setter sees the whole pose; a player sends net_yaw (in
##   the truck's space while riding) instead of `rotation`;
## - a remote player's poses, sent at 30 Hz, go into a NetPoseSmoother and
##   it's drawn a cushion behind the newest one, moving evenly between them,
##   turning with them; riding, inside this peer's truck;
## - on the host a request is judged from the remote player's newest pose,
##   not the one drawn in the past (reach_origin), with extra reach for its
##   round trip (NetStats.reach_slack: none offline, 5 m/s of it, capped);
## - a client's box is drawn the same way.
##
## Offline, a node whose authority is another peer behaves like a client's
## copy, so the puppet side is tested that way, against the real clock.

const SPEED: float = 3.6
const RATE: float = 30.0

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var van = level.vehicle
	var world: Node3D = level.get_node(^"World")
	var player: Node3D = level.local_player

	# --- what goes over the wire ---
	var player_sync := player.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	_expect_wire(player_sync, "players")
	_expect(player_sync.replication_config.has_property(NodePath(".:net_yaw"))
		and not player_sync.replication_config.has_property(NodePath(".:rotation")),
		"Players send net_yaw, not their rotation")
	var box: Node3D = get_nodes_in_group(&"cargo")[0]
	_expect_wire(box.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer, "boxes")
	await physics_frame
	_expect(absi(int(box.get(&"net_time")) - NetPoseSmoother.clock_ms()) <= 50,
		"The host stamps a box's pose with its clock")
	_expect(absi(int(player.get(&"net_time")) - NetPoseSmoother.clock_ms()) <= 50,
		"The owner stamps its pose with its clock")

	# --- a remote player walking: drawn behind its newest pose, evenly ---
	var remote: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	remote.name = "Player_2"
	world.add_child(remote)
	await process_frame
	var start := Vector3(20.0, 0.3, 20.0)
	var yaw_from: float = 0.0
	var yaw_to: float = 0.6
	var packets: int = 18
	var drawn: Array[Vector3] = []
	var first_ms: int = Time.get_ticks_msec()
	for index: int in range(packets):
		var along: float = float(index) / RATE
		remote.set(&"net_in_vehicle", false)
		remote.set(&"net_position", start + Vector3(SPEED * along, 0.0, 0.0))
		remote.set(&"net_yaw", lerpf(yaw_from, yaw_to, float(index) / float(packets - 1)))
		remote.set(&"net_time", 100000 + roundi(along * 1000.0))
		var until: int = first_ms + roundi((index + 1) * 1000.0 / RATE)
		while Time.get_ticks_msec() < until:
			await process_frame
			drawn.append(remote.global_position)
	var smoother: NetPoseSmoother = remote.get(&"_net_smoother")
	_expect(smoother != null and not smoother.is_empty(), "A remote player's poses go into its buffer")
	var newest: Vector3 = start + Vector3(SPEED * (packets - 1) / RATE, 0.0, 0.0)
	var now_drawn: Vector3 = remote.global_position
	var trail: float = (newest.x - now_drawn.x) / SPEED
	_expect(trail > NetPoseSmoother.MIN_DELAY - 0.035 and trail < NetPoseSmoother.MAX_DELAY + 0.05,
		"It's drawn a cushion behind the newest pose (%.0f ms)" % (trail * 1000.0))
	_expect(absf(now_drawn.z - start.z) < 0.001, "...on the path the owner walked")
	var worst_step: float = 0.0
	for index: int in range(1, drawn.size()):
		if drawn[index - 1].x > start.x + 0.01:
			worst_step = maxf(worst_step, drawn[index].x - drawn[index - 1].x)
	_expect(worst_step < SPEED / RATE * 0.75,
		"Between packets it moves on instead of jumping a whole packet at once (worst step %.3f m)" % worst_step)
	var yaw: float = remote.rotation.y
	_expect(yaw > yaw_from + 0.05 and yaw < yaw_to, "It turns along with its poses (yaw %.2f)" % yaw)

	# --- the host judges it by its newest pose ---
	_expect((remote.call(&"reach_origin") as Vector3).distance_to(newest) < 0.001,
		"On the host a remote player reaches from its newest pose, not the drawn one")
	_expect(is_zero_approx(NetStats.reach_slack(root.multiplayer.multiplayer_peer, 2)),
		"Offline nobody gets extra reach")
	_expect(is_equal_approx(NetStats.slack_for_round_trip(0.1), 0.5),
		"A 100 ms round trip gives half a metre more reach")
	_expect(is_equal_approx(NetStats.slack_for_round_trip(2.0), 1.5), "...and a terrible link no more than 1.5 m")

	# --- riding: its poses are in the truck's space, drawn on this peer's truck ---
	var seat := Vector3(-0.3, 0.26, 3.1)
	var base_ms: int = 200000
	for index: int in range(6):
		remote.set(&"net_in_vehicle", true)
		remote.set(&"net_position", seat)
		remote.set(&"net_yaw", 0.0)
		remote.set(&"net_time", base_ms + index * 33)
		await create_timer(1.0 / RATE).timeout
	await create_timer(NetPoseSmoother.MAX_DELAY + 0.05).timeout
	await process_frame
	var on_truck: Vector3 = (van as Node3D).global_transform * seat
	_expect(remote.global_position.distance_to(on_truck) < 0.02,
		"A riding remote player is drawn in this peer's truck (off by %.3f)" % [
			remote.global_position.distance_to(on_truck)])
	var facing: float = (-(remote.global_basis.z)).signed_angle_to(-(van as Node3D).global_basis.z, Vector3.UP)
	_expect(absf(facing) < 0.02,
		"...facing the way the truck does when its yaw in the truck is 0 (off %.3f rad)" % facing)

	# --- a client's box ---
	var puppet: Node3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	puppet.set(&"package_id", &"test_smoothed_box")
	puppet.set_multiplayer_authority(2)
	world.add_child(puppet)
	await process_frame
	var box_from := Vector3(-10.0, 1.0, 5.0)
	for index: int in range(10):
		puppet.set(&"net_in_vehicle", false)
		puppet.set(&"net_transform", Transform3D(Basis(), box_from + Vector3(0.0, 0.0, -2.0 * index / RATE)))
		puppet.set(&"net_time", 300000 + index * 33)
		if index == 9:
			break
		await create_timer(1.0 / RATE).timeout
	await process_frame
	var box_smoother: NetPoseSmoother = puppet.get(&"_net_smoother")
	_expect(box_smoother != null and not box_smoother.is_empty(),
		"A client's box files the host's poses into its buffer")
	var box_newest_z: float = box_from.z - 2.0 * 9.0 / RATE
	_expect(puppet.global_position.z > box_newest_z + 0.03 and puppet.global_position.z < box_from.z,
		"It's drawn behind the newest pose, between the ones it got (z %.3f, newest %.3f)" % [
			puppet.global_position.z, box_newest_z])
	await create_timer(NetPoseSmoother.MAX_DELAY + NetPoseSmoother.MAX_EXTRAPOLATION + 0.05).timeout
	await process_frame
	_expect(absf(puppet.global_position.z - box_newest_z) < 2.0 * NetPoseSmoother.MAX_EXTRAPOLATION + 0.01,
		"With no more poses it settles at the last one, at most a short glide past (z %.3f)" % puppet.global_position.z)

	level.free()
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: remote players and boxes go through the pose buffer at 30 Hz,",
			" and the host judges reach by the newest pose")
	quit(_failures)


func _expect_wire(sync: MultiplayerSynchronizer, what: String) -> void:
	_expect(is_equal_approx(sync.replication_interval, 0.0333),
		"%s sync at 30 Hz (interval %.4f)" % [what.capitalize(), sync.replication_interval])
	var paths: Array[NodePath] = sync.replication_config.get_properties()
	var last: NodePath = paths[-1]
	_expect(last == NodePath(".:net_time"),
		"The clock is the last property %s send, after the pose (last: %s)" % [what, last])
	var mode: int = sync.replication_config.property_get_replication_mode(last)
	_expect(mode == SceneReplicationConfig.REPLICATION_MODE_ALWAYS
		and sync.replication_config.property_get_spawn(last), "...sent with every pose and on spawn")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

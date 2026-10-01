extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_remote_smoothing.gd
##
## Other peers' players and the host's boxes, drawn smoothly (N-217). They
## were put on whichever pose came last, so with internet jitter they jumped;
## now each pose carries its sender's clock and goes through a
## NetSnapshotBuffer (modules/net_pose_smoother), and they go out at 30 Hz.
## - What goes over the wire: players send PlayerNetPose:net_time and
##   PlayerNetPose:net_yaw instead of rotation, boxes net_time; both every 1/30 s.
## - The owner stamps its pose (clock_ms()) and its heading, in the truck's
##   space while riding in the bay.
## - A remote player walking at running speed, its poses arriving with
##   jitter, is drawn without going backwards or jumping, and turns to the
##   heading sent, inside this peer's truck when riding.
## - A client's box: an unstamped pose is placed at once (spawn state, the
##   other tests); stamped ones are drawn in the past, between two poses.
## - Reach (the host): a remote player's requests reach further by a running
##   speed over its ping plus cushion (Interactable._within_reach and the box's
##   own checks); the host's own player gets nothing extra, and the slack is capped.
## Offline, a node whose authority is another peer behaves like a client's copy.

const RUN_SPEED: float = 6.0

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	await physics_frame
	var van = level.vehicle
	var world: Node3D = level.get_node(^"World")
	var player: Node3D = level.local_player
	_check_wire(player)
	await _check_publish(player, van)
	var remote: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	remote.name = "Player_2"
	world.add_child(remote)
	await process_frame
	await _check_remote_player(remote, van)
	await _check_box(world)
	_check_reach(player, remote)
	level.free()
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: remote players and boxes are drawn from a snapshot buffer at 30 Hz, and reach allows for the lag")
	quit(_failures)


func _check_wire(player: Node) -> void:
	var player_sync := player.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var config: SceneReplicationConfig = player_sync.replication_config
	_expect(config.has_property(NodePath("PlayerNetPose:net_time"))
			and config.has_property(NodePath("PlayerNetPose:net_yaw"))
			and not config.has_property(NodePath(".:rotation")),
		"Players send their clock and heading, not a raw rotation")
	var box: Node = get_nodes_in_group(&"cargo")[0]
	var box_sync := box.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	_expect(box_sync.replication_config.has_property(NodePath(".:net_time")),
		"Boxes send the host's clock with each pose")
	for sync: MultiplayerSynchronizer in [player_sync, box_sync]:
		_expect(absf(sync.replication_interval - 1.0 / 30.0) < 0.001,
			"%s sends at 30 Hz (every %.4f s)" % [sync.get_parent().name, sync.replication_interval])


func _check_publish(player: Node3D, van: Node3D) -> void:
	var pose_node: Node = player.get_node(^"PlayerNetPose")
	player.global_position = van.to_global(Vector3(0.0, 0.3, 8.0))
	player.global_rotation = Vector3(0.0, 0.8, 0.0)
	await physics_frame
	await physics_frame
	_expect(not bool(player.get(&"net_in_vehicle")) and absf(float(pose_node.get(&"net_yaw")) - 0.8) < 0.01,
		"On foot the heading goes out in the world (%.3f)" % float(pose_node.get(&"net_yaw")))
	_expect(absi(int(pose_node.get(&"net_time")) - NetSnapshotBuffer.clock_ms()) <= 40,
		"...stamped with the owner's clock (%d, now %d)" % [
			int(pose_node.get(&"net_time")), NetSnapshotBuffer.clock_ms()])
	var van_yaw: float = van.global_rotation.y
	player.global_position = van.to_global(Vector3(0.3, 0.27, 2.4))
	player.global_rotation = Vector3(0.0, van_yaw + 0.5, 0.0)
	await physics_frame
	await physics_frame
	_expect(bool(player.get(&"net_in_vehicle")) and absf(wrapf(float(pose_node.get(&"net_yaw")) - 0.5, -PI, PI)) < 0.02,
		"Riding in the bay, the heading goes out in the truck's space (%.3f)" % float(pose_node.get(&"net_yaw")))
	player.global_position = van.to_global(Vector3(0.0, 0.3, 8.0))
	await physics_frame


func _check_remote_player(remote: Node3D, van: Node3D) -> void:
	var pose_node: Node = remote.get_node(^"PlayerNetPose")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var start: Vector3 = van.to_global(Vector3(6.0, 0.3, 0.0))
	# A second of the owner running along +X at 30 Hz, each pose landing
	# 0..25 ms late, sampled every rendered frame.
	var began: int = Time.get_ticks_usec()
	var pending: Array = []
	var sent: int = 0
	var previous: float = INF
	var backward: float = 0.0
	var worst_speed: float = 0.0
	var last_usec: int = began
	while Time.get_ticks_usec() - began < 1_000_000:
		var elapsed: float = (Time.get_ticks_usec() - began) / 1000000.0
		while sent / 30.0 <= elapsed:
			pending.append([sent / 30.0 + rng.randf_range(0.0, 0.025), sent])
			sent += 1
		pending.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		while not pending.is_empty() and float(pending[0][0]) <= elapsed:
			var index: int = int(pending.pop_front()[1])
			pose_node.set(&"net_time", 100_000 + index * 1000 / 30)
			pose_node.set(&"net_yaw", 1.0)
			remote.set(&"net_in_vehicle", false)
			remote.set(&"net_position", start + Vector3(RUN_SPEED * index / 30.0, 0.0, 0.0))
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		if elapsed > 0.3 and previous != INF:
			var x: float = remote.global_position.x
			backward = maxf(backward, previous - x)
			var frame: float = maxf((now_usec - last_usec) / 1000000.0, 0.001)
			worst_speed = maxf(worst_speed, absf(x - previous) / frame)
		previous = remote.global_position.x
		last_usec = now_usec
	_expect(backward < 0.002, "A remote player is never drawn going backwards (%.3f m)" % backward)
	_expect(worst_speed < RUN_SPEED * 2.5,
		"...nor jumping: at most %.1f m/s between frames (%.1f)" % [RUN_SPEED * 2.5, worst_speed])
	_expect(absf(wrapf(remote.global_rotation.y - 1.0, -PI, PI)) < 0.01,
		"It turns to the heading sent (%.3f)" % remote.global_rotation.y)

	# Riding: in this peer's truck, turned with it.
	pose_node.set(&"net_time", 0)
	remote.set(&"net_in_vehicle", true)
	pose_node.set(&"net_yaw", 0.3)
	remote.set(&"net_position", Vector3(-0.3, 0.26, 3.1))
	await process_frame
	var truck: Transform3D = van.get_global_transform_interpolated()
	_expect(remote.global_position.distance_to(truck * Vector3(-0.3, 0.26, 3.1)) < 0.01,
		"A remote rider is drawn in this peer's truck")
	_expect(absf(wrapf(remote.global_rotation.y - (van.global_rotation.y + 0.3), -PI, PI)) < 0.02,
		"...facing the truck's heading plus its own (%.3f)" % remote.global_rotation.y)
	remote.set(&"net_in_vehicle", false)
	remote.set(&"net_position", van.to_global(Vector3(0.0, 0.3, 9.0)))
	await process_frame


func _check_box(world: Node3D) -> void:
	var puppet: Node3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	puppet.set(&"package_id", &"test_smoothed_box")
	puppet.set_multiplayer_authority(2)
	world.add_child(puppet)
	await process_frame
	var here := Vector3(30.0, 2.0, 30.0)
	puppet.set(&"net_transform", Transform3D(Basis.IDENTITY, here))
	await process_frame
	_expect(puppet.global_position.distance_to(here) < 0.001, "An unstamped box pose is placed at once")
	# Stamped poses 1 m apart, arriving 1/30 s apart: drawn in between, in the past.
	for index: int in range(3):
		puppet.set(&"net_time", 200_000 + index * 33)
		puppet.set(&"net_transform", Transform3D(Basis.IDENTITY, here + Vector3(index, 0.0, 0.0)))
		var until: int = Time.get_ticks_usec() + 33_000
		while Time.get_ticks_usec() < until:
			await process_frame
	var x: float = puppet.global_position.x - here.x
	_expect(x > 0.0 and x < 2.0, "Stamped box poses are drawn in the past, between two of them (x %.2f)" % x)
	puppet.free()


func _check_reach(player: Node3D, remote: Node3D) -> void:
	_expect(is_zero_approx(float(player.call(&"reach_slack"))), "The host's own player reaches no further")
	var slack: float = float(remote.call(&"reach_slack"))
	_expect(slack > 0.1 and slack <= 1.5,
		"A client's player reaches further on the host, by its lag, capped (%.2f m)" % slack)
	var point := Interactable.new()
	remote.get_parent().add_child(point)
	var reach: float = Interactable.REMOTE_REACH
	point.global_position = remote.reach_origin() + Vector3(reach + slack * 0.5, 0.0, 0.0)
	_expect(point._within_reach(remote), "A request from just past the old reach is accepted for a lagging client")
	point.global_position = remote.reach_origin() + Vector3(reach + slack + 0.2, 0.0, 0.0)
	_expect(not point._within_reach(remote), "...but not from further than the slack")
	point.global_position = (player.call(&"reach_origin") as Vector3) + Vector3(reach + 0.2, 0.0, 0.0)
	_expect(not point._within_reach(player), "The host's own player keeps the plain reach")
	point.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

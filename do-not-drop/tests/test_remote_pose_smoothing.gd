extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_remote_pose_smoothing.gd
##
## Remote players and boxes drawn smoothly (N-217, docs/investigacion-red.md fase 2):
## - what goes over the wire: players and boxes sync at 30 Hz, each pose
##   carries its owner's clock (net_time); a player sends net_yaw (relative to
##   the truck's heading while riding) instead of `rotation`;
## - a remote player's poses go into a NetPoseSmoother when a whole packet has
##   landed (the synchronizer's `synchronized`, whatever order the properties
##   came in), and it's drawn a cushion behind the newest one, moving evenly
##   between them, turning with them; its head, gait speed and jump clip are
##   drawn from the same moment, not ahead of the body; riding, inside this
##   peer's truck, facing the right way on a truck pitched 15 and rolled 10
##   degrees (under 0.2 degrees off);
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
		# The clock first: the pose is filed once the whole packet is in, not when net_time lands.
		remote.set(&"net_time", 100000 + roundi(along * 1000.0))
		remote.set(&"net_in_vehicle", false)
		remote.set(&"net_position", start + Vector3(SPEED * along, 0.0, 0.0))
		remote.set(&"net_yaw", lerpf(yaw_from, yaw_to, float(index) / float(packets - 1)))
		remote.set(&"locomotion_speed", float(index))
		(remote.get_node(^"Head") as Node3D).rotation = Vector3(index * 0.01, 0.0, 0.0)
		_land(remote)
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
	var drawn_index: float = (now_drawn.x - start.x) / (SPEED / RATE)
	var gait: float = float(remote.get(&"locomotion_speed"))
	_expect(absf(gait - drawn_index) < 0.35 and gait < packets - 1.5,
		"Its gait speed is the one of the moment drawn, not the newest (%.2f for pose %.2f)" % [gait, drawn_index])
	var head: float = (remote.get_node(^"Head") as Node3D).rotation.x
	_expect(absf(head - drawn_index * 0.01) < 0.0035,
		"...and so is its head (%.4f for pose %.2f)" % [head, drawn_index])

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
		_land(remote)
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

	# --- a tilted truck: the rider faces where its owner does ---
	var ride_script: GDScript = load("res://scripts/gameplay/player/player_ride.gd")
	(van as RigidBody3D).freeze = true
	var tilted := Basis.from_euler(Vector3(deg_to_rad(15.0), 0.7, deg_to_rad(10.0)))
	(van as Node3D).global_transform = Transform3D(tilted, (van as Node3D).global_position)
	(van as Node3D).reset_physics_interpolation()
	player.global_position = (van as Node3D).global_transform * Vector3(0.3, 0.4, 2.4)
	player.rotation = Vector3(0.0, 1.9, 0.0)
	ride_script.call(&"publish_net_state", player)
	var owner_yaw: float = ride_script.call(&"yaw_of", player.global_basis)
	_expect(bool(player.get(&"net_in_vehicle")), "The owner standing in the tilted bay publishes in the truck's space")
	for index: int in range(6):
		remote.set(&"net_in_vehicle", true)
		remote.set(&"net_position", player.get(&"net_position"))
		remote.set(&"net_yaw", player.get(&"net_yaw"))
		remote.set(&"net_time", base_ms + 1000 + index * 33)
		_land(remote)
		await create_timer(1.0 / RATE).timeout
	await create_timer(NetPoseSmoother.MAX_DELAY + 0.05).timeout
	await process_frame
	await physics_frame
	var yaw_error: float = absf(angle_difference(remote.rotation.y, owner_yaw))
	_expect(yaw_error < deg_to_rad(0.2),
		"On a truck pitched 15 and rolled 10 degrees the rider faces as its owner does (%.3f deg off)"
			% rad_to_deg(yaw_error))
	(van as Node3D).global_transform = Transform3D(Basis(), (van as Node3D).global_position)

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
		_land(puppet)
		if index == 9:
			break
		await create_timer(1.0 / RATE).timeout
	await process_frame
	var box_smoother: NetPoseSmoother = (puppet.get(&"_net_view") as PackageNetPose).smoother
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


## A whole synced packet has landed: what SceneMultiplayer signals after setting its properties.
func _land(node: Node) -> void:
	(node.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer).synchronized.emit()


func _expect_wire(sync: MultiplayerSynchronizer, what: String) -> void:
	_expect(is_equal_approx(sync.replication_interval, 0.0333),
		"%s sync at 30 Hz (interval %.4f)" % [what.capitalize(), sync.replication_interval])
	var clock := NodePath(".:net_time")
	_expect(sync.replication_config.has_property(clock), "%s send their clock" % what.capitalize())
	var mode: int = sync.replication_config.property_get_replication_mode(clock)
	_expect(mode == SceneReplicationConfig.REPLICATION_MODE_ALWAYS
		and sync.replication_config.property_get_spawn(clock), "...with every pose and on spawn")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

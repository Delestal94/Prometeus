extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_ride_sync.gd
##
## Multiplayer bugs from a playtest (2026-09-24). On clients the boxes in the
## back bounced about, went through the walls and seemed to fall out, and
## players standing in the back slid through the closed doors: boxes, players
## and the truck all arrived as separate world positions, out of step, and a
## client's truck (a teleported copy) carried nobody. A client also couldn't
## drive (the truck's controls_enabled never reached it), and a wide box on
## the rack stuck out through the side wall.
##
## Offline, a node whose authority is another peer behaves exactly like a
## client's copy of it, so the puppet side is tested that way.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	await physics_frame
	# Untyped: the truck's own constants and carries() are read below.
	var van = level.vehicle
	var world: Node3D = level.get_node(^"World")
	var player: Node3D = level.local_player

	# --- what goes over the wire ---
	var van_config: SceneReplicationConfig = (van.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer).replication_config
	_expect(van_config.has_property(NodePath(".:controls_enabled")),
		"The truck's controls_enabled replicates, so a client at the wheel sends its input")
	var player_config: SceneReplicationConfig = (player.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer).replication_config
	_expect(player_config.has_property(NodePath(".:net_position")) and player_config.has_property(NodePath(".:net_in_vehicle"))
		and not player_config.has_property(NodePath(".:position")), "Players replicate a truck-relative position, not a raw one")
	var packages: Array[Node] = []
	packages.assign(get_nodes_in_group(&"cargo"))
	var package_config: SceneReplicationConfig = (packages[0].get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer).replication_config
	_expect(package_config.has_property(NodePath(".:net_transform")) and package_config.has_property(NodePath(".:net_in_vehicle"))
		and not package_config.has_property(NodePath(".:position")), "Boxes replicate a truck-relative transform, not a raw one")

	# --- the cargo bay ---
	_expect(van.carries(van.to_global(Vector3(0.0, 1.0, 2.0))), "A point in the middle of the bay rides with the truck")
	_expect(not van.carries(van.to_global(Vector3(0.0, 1.0, 8.0))), "A point behind the truck doesn't")
	_expect(not van.carries(van.to_global(Vector3(3.0, 1.0, 2.0))), "A point beside the truck doesn't")

	# --- a shelved box is sent in the truck's space ---
	var mounts: Array[Node] = []
	for mount: Node in get_nodes_in_group(&"package_mount"):
		if String(mount.get_parent().name).contains("Seat"):
			mounts.append(mount)
	var box: Node3D = packages[0]
	player.call(&"pick_up", box.get_path())
	mounts[0].call(&"interact", player)
	await physics_frame
	_expect(bool(box.get(&"net_in_vehicle")), "A box on the rack is published as riding the truck")
	var published: Transform3D = van.global_transform * (box.get(&"net_transform") as Transform3D)
	_expect(published.origin.distance_to(box.global_position) < 0.01, "Its published transform is its pose in the truck's space")
	_expect(absf(van.to_local(box.global_position).x - (-0.52)) < 0.01, "A standard box stays centred on its rack marker")

	# --- a wide box doesn't reach into the side wall ---
	var flat: Node3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	flat.set(&"package_id", &"test_flat_box")
	flat.set(&"content", load("res://data/contents/sourdough.tres"))
	world.add_child(flat)
	await process_frame
	player.call(&"pick_up", flat.get_path())
	mounts[1].call(&"interact", player)
	var half: Vector3 = flat.call(&"get_half_extents")
	var outer_face: float = absf(van.to_local(flat.global_position).x) + maxf(half.x, half.z)
	_expect(outer_face <= van.CARGO_WALL_INNER_X - van.CARGO_WALL_CLEARANCE + 0.001,
		"A 0.95 m box on the rack clears the side wall (outer face at %.3f)" % outer_face)

	# --- a client's copy of a riding box sits on the client's truck ---
	var puppet: Node3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	puppet.set(&"package_id", &"test_puppet_box")
	puppet.set_multiplayer_authority(2)
	world.add_child(puppet)
	await process_frame
	var local_pose := Transform3D(Basis(Vector3.UP, 0.4), Vector3(-0.5, 0.8, 2.6))
	puppet.set(&"net_in_vehicle", true)
	puppet.set(&"net_transform", local_pose)
	# The network moves the client's truck somewhere else entirely.
	van.global_transform = Transform3D(Basis(Vector3.UP, 0.7), van.global_position + Vector3(4.0, 0.0, -9.0))
	van.reset_physics_interpolation()
	await process_frame
	var expected: Transform3D = van.get_global_transform_interpolated() * local_pose
	_expect(puppet.global_position.distance_to(expected.origin) < 0.01,
		"A client puts a riding box on its own copy of the truck (off by %.3f)" % puppet.global_position.distance_to(expected.origin))
	_expect(not puppet.is_physics_interpolated(), "A client's box, placed each frame, isn't interpolated on top")
	puppet.set(&"net_in_vehicle", false)
	puppet.set(&"net_transform", Transform3D(Basis(), Vector3(10.0, 1.0, 10.0)))
	await process_frame
	_expect(puppet.global_position.distance_to(Vector3(10.0, 1.0, 10.0)) < 0.01, "A box outside the truck is placed in world space")

	# --- a player standing in the back rides along ---
	await physics_frame
	await physics_frame
	var spot := Vector3(0.4, 0.27, 2.2)
	player.global_position = van.to_global(spot)
	await physics_frame
	await physics_frame
	var heading_before: float = (-(player.global_basis.z)).signed_angle_to(-van.global_basis.z, Vector3.UP)
	van.global_transform = Transform3D(van.global_basis.rotated(Vector3.UP, 0.3), van.global_position + van.global_basis.z * -3.0)
	van.reset_physics_interpolation()
	await physics_frame
	var drift: Vector3 = van.to_local(player.global_position) - spot
	_expect(Vector2(drift.x, drift.z).length() < 0.05,
		"A player standing in the bay moves with the truck instead of being swept by its walls (drift %s)" % drift)
	var heading_after: float = (-(player.global_basis.z)).signed_angle_to(-van.global_basis.z, Vector3.UP)
	_expect(absf(heading_after - heading_before) < 0.02, "...and turns with it")
	_expect(bool(player.get(&"net_in_vehicle")), "The rider is published as riding the truck")

	# --- everyone else sees that rider inside their own truck ---
	var remote: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	remote.name = "Player_2"
	world.add_child(remote)
	await process_frame
	_expect(not remote.call(&"is_local"), "Player_2 is another peer's player here")
	_expect(not remote.is_physics_interpolated(), "A remote player, placed each frame, isn't interpolated on top")
	var rider_spot := Vector3(-0.3, 0.26, 3.1)
	remote.set(&"net_in_vehicle", true)
	remote.set(&"net_position", rider_spot)
	await process_frame
	var rider_expected: Vector3 = van.get_global_transform_interpolated() * rider_spot
	_expect(remote.global_position.distance_to(rider_expected) < 0.01,
		"A remote rider is placed inside this peer's truck (off by %.3f)" % remote.global_position.distance_to(rider_expected))

	# --- ...and on the host, where the truck is simulated, in step with it ---
	# There the rider is a solid body in the moving bay. Placed each frame
	# against the truck as drawn (interpolated, up to a tick behind the
	# simulated one), it sat up to 0.3 m off at 15 m/s on every physics step
	# and rammed the loose boxes: they took damage and were squeezed out
	# through the floor (3-process probe, 2026-09-24).
	var tick_probe := GDScript.new()
	tick_probe.source_code = "extends Node\nvar sample: Callable\nfunc _physics_process(_d: float) -> void:\n\tif sample.is_valid(): sample.call()\n"
	tick_probe.reload()
	var sampler := Node.new()
	sampler.set_script(tick_probe)
	sampler.process_physics_priority = 1000  # After the players, before the step.
	root.add_child(sampler)
	var worst: Array[float] = [0.0]
	sampler.set(&"sample", func() -> void:
		worst[0] = maxf(worst[0], van.to_local(remote.global_position).distance_to(rider_spot)))
	van.freeze = false
	for i: int in range(40):
		van.linear_velocity = -van.global_basis.z * 15.0
		await physics_frame
		await process_frame
		await process_frame
	sampler.set(&"sample", Callable())
	_expect(van.is_physics_interpolated_and_enabled(), "The simulated truck is interpolated (the host's case)")
	_expect(worst[0] < 0.02, "On the host a remote rider's body keeps its place in the simulated truck (off by up to %.3f)" % worst[0])
	sampler.free()

	# --- riding a moving truck, a player doesn't strike the loose boxes ---
	van.freeze = false
	van.linear_velocity = Vector3(0.0, 0.0, -12.0)
	_expect(int(player.call(&"_on_foot_mask", true)) & 4 == 0,
		"Riding a moving truck, a player passes loose boxes instead of striking them at its speed")
	_expect(int(player.call(&"_on_foot_mask", false)) & 4 == 4, "On foot outside the truck, boxes collide as usual")
	van.linear_velocity = Vector3.ZERO
	_expect(int(player.call(&"_on_foot_mask", true)) & 4 == 4, "In a parked truck (loading), boxes collide as usual")
	van.freeze = true

	level.free()
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: boxes and riders are sent in the truck's space, ride with it on every peer, and clear the walls")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

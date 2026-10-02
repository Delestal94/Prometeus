extends Node
## Seated body placement, driver hand IK, and entering/leaving seats. Player
## retains the replicated properties and RPC entry point used by the network.

var player: Player


func _ready() -> void:
	player = get_parent() as Player


func reach_origin() -> Vector3:
	var seat: Node3D = player.get_node_or_null(player.seat_node_path) as Node3D if not player.seat_node_path.is_empty() else null
	return seat.global_position if seat != null else player.global_position


func gather_package_input() -> Dictionary:
	# A seated passenger is not walking, so the movement actions can also feed
	# directional trap sequences while the primary action steadies the package.
	# On foot they only do while the primary action is held -- which also
	# stops the walk (player.gd) -- or every step taken with a box in hand
	# read as a wrong key (playtest 2026-09-28).
	var holding: bool = Input.is_action_pressed(&"package_action_primary")
	# The primary going down, for the traps answered by one tap (Fragile's
	# "Amortiguá"): the edge, so holding it never counts again.
	var tap: bool = Input.is_action_just_pressed(&"package_action_primary")
	# WASD or the left stick as two axes in the player's own view (A/D right,
	# W/S forward): what Balance's "Contrapesá" pushes with. The host turns them
	# into the truck's frame from the player's seat, and only counts them while
	# the primary is held. The keys' edges (direction_pressed) are separate.
	var lean: float = Input.get_axis(&"drive_left", &"drive_right")
	var lean_fwd: float = Input.get_axis(&"walk_backward", &"walk_forward")
	var direction: Variant = null
	if player.seat_node_path.is_empty() and not holding:
		return {"steady": holding, "calm": holding, "direction_pressed": direction, "tap": tap, "lean": lean,
			"lean_fwd": lean_fwd}
	if Input.is_action_just_pressed(&"walk_forward"):
		direction = &"up"
	elif Input.is_action_just_pressed(&"walk_backward"):
		direction = &"down"
	elif Input.is_action_just_pressed(&"drive_left"):
		direction = &"left"
	elif Input.is_action_just_pressed(&"drive_right"):
		direction = &"right"
	return {"steady": holding, "calm": holding, "direction_pressed": direction, "tap": tap, "lean": lean,
			"lean_fwd": lean_fwd}


## How far a seated body rolls toward the side its box's gesture asks (rad).
const GESTURE_ROLL: float = 0.22


## What the box this player tends says their body is doing (Balance's lean,
## Liquid's scrub, -1..1 with +1 to the truck's right): it comes with the
## box's care state, so every peer sees the same lean.
func gesture_push() -> float:
	return push_for_peer(player.get_tree(), player.get_multiplayer_authority())


## Rolls a seated body so its head goes toward `truck_right * push` (a seat on
## the truck's side sits across it, so this is not its own roll or pitch): the
## turn is about the horizontal axis at right angles to the truck's right.
static func lean_body(body: Node3D, truck_right: Vector3, push: float) -> void:
	if body == null or absf(push) <= 0.01:
		return
	var toward: Vector3 = body.global_basis.inverse() * truck_right
	toward.y = 0.0
	if toward.length() > 0.01:
		body.rotate_object_local(Vector3.UP.cross(toward.normalized()), push * GESTURE_ROLL)


static func push_for_peer(tree: SceneTree, peer_id: int) -> float:
	for node: Node in tree.get_nodes_in_group(&"cargo"):
		var package := node as DeliveryPackage
		if package != null and package.tender_peer_id == peer_id:
			return float((package.care_state.get("gesture", {}) as Dictionary).get("push", 0.0))
	return 0.0


func pose_seated_body(delta: float) -> void:
	if player.seat_node_path.is_empty():
		stop_driver_ik()
		if player._body_visual != null:
			# Clear the seat's world-space offset on every peer after standing.
			player._body_visual.position = Vector3.ZERO
			player._body_visual.rotation.y = 0.0
			player._body_visual.rotation.z = 0.0
			player._body_visual.position.y = sin(player._bob_time * TAU) * 0.025 * player._bob_amount
			var flinch: float = sin(player._flinch_time / 0.32 * PI) * 0.26
			player._body_visual.rotation.x = move_toward(player._body_visual.rotation.x, flinch, delta * 12.0)
		return
	var seat: Node3D = player.get_node_or_null(player.seat_node_path) as Node3D
	if seat == null:
		return
	player._seat_pose_blend = minf(player._seat_pose_blend + delta * 7.0, 1.0)
	var seat_pose: Transform3D = seat.global_transform if player.is_physics_interpolated_and_enabled() else Player._drawn_transform(seat)
	var target_pose := seat_pose.translated_local(seat_body_offset(seat.name))
	player._body_visual.global_transform = player._body_visual.global_transform.interpolate_with(target_pose, player._seat_pose_blend)
	var lean: float = 0.18 if seat.name == &"DriverEyePoint" else (0.0 if String(seat.name).begins_with("RackSeat") else 0.08)
	player._body_visual.rotation.x = lean + sin(Time.get_ticks_msec() * 0.008) * 0.025
	# Leaning into the counterweight, swaying with the scrub.
	var push: float = lerpf(float(player.get_meta(&"seat_push", 0.0)), gesture_push(), minf(1.0, delta * 8.0))
	player.set_meta(&"seat_push", push)
	var truck: Node3D = player.get_tree().get_first_node_in_group(&"vehicle") as Node3D
	if truck != null:
		lean_body(player._body_visual, truck.global_basis.x, push)
	configure_driver_ik(seat)


func seat_body_offset(seat_name: StringName) -> Vector3:
	if seat_name == &"DriverEyePoint":
		return Vector3(0.0, -0.75, -0.37)
	if String(seat_name).begins_with("RackSeat"):
		return Vector3(0.0, -0.42, -0.18)
	if seat_name == &"CenterSeatEyePoint":
		return Vector3(0.19, -0.45, -0.26)
	return Vector3(0.0, -0.45, -0.26)


func configure_driver_ik(seat: Node3D) -> void:
	if player._driver_ik_ready or seat.name != &"DriverEyePoint" or player._body_visual == null:
		return
	var wheel: Node3D = seat.get_parent().get_parent().find_child("SteeringWheel", true, false) as Node3D
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(player._body_visual)
	if wheel == null or skeleton == null:
		return
	for side: float in player.DRIVER_ARM_BONES:
		var bones: Array = player.DRIVER_ARM_BONES[side]
		var target := Marker3D.new()
		target.name = "DriverHandTargetLeft" if side < 0.0 else "DriverHandTargetRight"
		target.position = Vector3(side * 0.19, 0.0, -0.03)
		wheel.add_child(target)
		var ik := SkeletonIK3D.new()
		ik.name = "DriverIK" + str(side)
		ik.root_bone = bones[0]
		ik.tip_bone = bones[1]
		ik.override_tip_basis = false
		skeleton.add_child(ik)
		ik.target_node = target.get_path()
		ik.start(false)
		player._driver_ik_nodes.append(ik)
		player._driver_arm_targets.append(target)
	player._driver_ik_ready = not player._driver_ik_nodes.is_empty()


func stop_driver_ik() -> void:
	if not player._driver_ik_ready:
		return
	for ik: SkeletonIK3D in player._driver_ik_nodes:
		if is_instance_valid(ik):
			ik.stop()
			ik.queue_free()
	player._driver_ik_nodes.clear()
	for target: Node3D in player._driver_arm_targets:
		if is_instance_valid(target):
			target.queue_free()
	player._driver_arm_targets.clear()
	player._driver_ik_ready = false


func apply_board_seat(seat_camera_path: NodePath, seat_path: NodePath) -> void:
	player._seated = true
	# Whatever this seat gives them comes next (tend_package); nothing carries over.
	player.tended_package = null
	player._seat_pose_blend = 0.0
	player.collision_layer = 0
	player.collision_mask = 0
	player.velocity = Vector3.ZERO
	player._camera.current = false
	player.seat_node_path = seat_path
	player._seat_camera_path = seat_camera_path
	var bus: Node = player.get_node_or_null("/root/EventBus")
	if bus != null:
		bus.emit_signal(&"quick_fade_requested", 0.2)
	var seat_camera := player.get_node_or_null(seat_camera_path) as SeatCamera
	if seat_camera != null:
		seat_camera.activate()


func apply_tend_package(package_path: NodePath) -> void:
	# The host hands a box over to whoever is seated there; one who already
	# stood up here (the host's message crossed their own leave) has no seat to
	# tend from. An empty path (let go of it) is always fine.
	if not package_path.is_empty() and not player._seated:
		return
	player.tended_package = player.get_node_or_null(package_path) as DeliveryPackage
	if player.is_local() and player.tended_package != null:
		player._show_first_trap_tip(player.tended_package)


func leave_seat() -> void:
	if not player._seated:
		return
	var seat: Node3D = player.get_node_or_null(player.seat_node_path) as Node3D
	release_seat_occupant(seat)
	if seat != null:
		player.global_position = seat_exit_position(seat)
		player.reset_physics_interpolation()
	var seat_camera := player.get_node_or_null(player._seat_camera_path) as SeatCamera
	if seat_camera != null:
		seat_camera.deactivate()
	player._seated = false
	player.tended_package = null
	player.seat_node_path = NodePath()
	player._seat_camera_path = NodePath()
	player.collision_layer = 8
	player.collision_mask = player.ON_FOOT_MASK
	player._camera.current = true


func seat_exit_position(seat: Node3D) -> Vector3:
	var exit_point := seat.get_node_or_null(^"ExitPoint") as Node3D
	var spot: Vector3 = exit_point.global_position if exit_point != null else seat.global_position - seat.global_basis.z * player.SEAT_EXIT_STEP
	var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 0.2, spot + Vector3.DOWN * 3.0, 1 | 2, [player.get_rid()])
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3) + Vector3.UP * 0.02 if not hit.is_empty() else spot


func release_seat_occupant(seat: Node3D) -> void:
	if seat == null:
		return
	var interaction := seat.get_node_or_null(^"InteractionArea") as SeatPoint
	if interaction == null:
		return
	var peer_id: int = player.get_multiplayer_authority()
	var network := player.get_node_or_null("/root/NetworkManager") as NetSession
	if network != null and network.is_online() and not network.is_host():
		interaction.rpc_id(1, &"release_occupant", peer_id)
	else:
		interaction.release_occupant(peer_id)

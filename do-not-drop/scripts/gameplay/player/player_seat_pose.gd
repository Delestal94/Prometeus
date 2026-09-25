extends Node
## Seated body placement, driver hand IK, and entering/leaving seats. Player
## retains the replicated properties and RPC entry point used by the network.

var player


func _ready() -> void:
	player = get_parent()


func reach_origin() -> Vector3:
	var seat: Node3D = player.get_node_or_null(player.seat_node_path) as Node3D if not player.seat_node_path.is_empty() else null
	return seat.global_position if seat != null else player.global_position


func gather_package_input() -> Dictionary:
	# A seated passenger is not walking, so the movement actions can also feed
	# directional trap sequences while the primary action steadies the package.
	var holding: bool = Input.is_action_pressed(&"package_action_primary")
	var direction: Variant = null
	if Input.is_action_just_pressed(&"walk_forward"):
		direction = &"up"
	elif Input.is_action_just_pressed(&"walk_backward"):
		direction = &"down"
	elif Input.is_action_just_pressed(&"drive_left"):
		direction = &"left"
	elif Input.is_action_just_pressed(&"drive_right"):
		direction = &"right"
	return {"steady": holding, "calm": holding, "direction_pressed": direction}


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
	configure_driver_ik(seat)


func seat_body_offset(seat_name: StringName) -> Vector3:
	if seat_name == &"DriverEyePoint":
		return Vector3(0.0, -0.73, -0.37)
	if String(seat_name).begins_with("RackSeat"):
		return Vector3(0.0, -0.35, -0.14)
	if seat_name == &"CenterSeatEyePoint":
		return Vector3(0.19, -0.38, -0.16)
	return Vector3(0.0, -0.38, -0.16)


func configure_driver_ik(seat: Node3D) -> void:
	if player._driver_ik_ready or seat.name != &"DriverEyePoint" or player._body_visual == null:
		return
	var wheel: Node3D = seat.get_parent().get_parent().find_child("SteeringWheel", true, false) as Node3D
	var skeleton: Skeleton3D = player._find_skeleton(player._body_visual)
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
	var seat_camera: Node = player.get_node_or_null(seat_camera_path)
	if seat_camera != null and seat_camera.has_method(&"activate"):
		seat_camera.call(&"activate")


func apply_tend_package(package_path: NodePath) -> void:
	player.tended_package = player.get_node_or_null(package_path) as DeliveryPackage


func leave_seat() -> void:
	if not player._seated:
		return
	var seat: Node3D = player.get_node_or_null(player.seat_node_path) as Node3D
	release_seat_occupant(seat)
	if seat != null:
		player.global_position = seat_exit_position(seat)
		player.reset_physics_interpolation()
	var seat_camera: Node = player.get_node_or_null(player._seat_camera_path)
	if seat_camera != null and seat_camera.has_method(&"deactivate"):
		seat_camera.call(&"deactivate")
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
	var interaction: Node = seat.get_node_or_null(^"InteractionArea")
	if interaction == null or not interaction.has_method(&"release_occupant"):
		return
	var peer_id: int = player.get_multiplayer_authority()
	var network: Node = player.get_node_or_null("/root/NetworkManager")
	if network != null and network.call(&"is_online") and not network.call(&"is_host"):
		interaction.rpc_id(1, &"release_occupant", peer_id)
	else:
		interaction.call(&"release_occupant", peer_id)

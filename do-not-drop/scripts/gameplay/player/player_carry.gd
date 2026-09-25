extends Node
## Package carry/drop behavior. Player owns the replicated state and RPC
## entry points; this child owns how a box is positioned and handed off.

var player


func _ready() -> void:
	player = get_parent()


func update_carried_package() -> void:
	var carry_transform := Transform3D(player.global_basis, carry_position())
	# The box waits for the reaching hands, then follows the lift instead of
	# teleporting to chest height on the first pickup tick.
	if player._pickup_elapsed < 1.3:
		var origin: Transform3D = player._pickup_from
		var pickup_vehicle: Node3D = player._find_vehicle()
		if player._pickup_in_vehicle and pickup_vehicle != null:
			origin = pickup_vehicle.global_transform * origin
		var lift: float = smoothstep(0.42, 1.3, player._pickup_elapsed)
		if player.locomotion_speed > 0.3:
			lift = maxf(lift, smoothstep(0.16, 0.5, player._pickup_elapsed))
		carry_transform = origin.interpolate_with(carry_transform, lift)
	# Use truck-local coordinates aboard so a client's trailing truck copy does
	# not leave the host-authoritative package behind the hands at speed.
	var vehicle: Node3D = player._find_vehicle()
	var aboard: bool = vehicle != null and bool(vehicle.call(&"carries", carry_transform.origin, player.RIDE_MARGIN))
	if aboard:
		carry_transform = vehicle.global_transform.affine_inverse() * carry_transform
	player.carried_package.rpc_id(1, &"submit_carry_transform", carry_transform, aboard)
	player._package_focus.dof_blur_far_enabled = true
	player._package_focus.dof_blur_far_distance = 1.45
	player._package_focus.dof_blur_far_transition = 1.0
	player._package_focus.dof_blur_amount = 0.18


func clear_carry_focus() -> void:
	if player._package_focus != null:
		player._package_focus.dof_blur_far_enabled = false


func carry_position() -> Vector3:
	var from: Vector3 = player._camera.global_position
	var target: Vector3 = player._hold_point.global_position
	target.y = clampf(target.y, player.global_position.y + 0.8, player.global_position.y + 1.3)
	var offset: Vector3 = target - from
	var reach: float = offset.length()
	if reach < 0.001:
		return target
	var direction: Vector3 = offset / reach
	var half: Vector3 = player.carried_package.get_half_extents()
	var support: float = (absf(direction.dot(player.global_basis.x)) * half.x
		+ absf(direction.dot(player.global_basis.y)) * half.y
		+ absf(direction.dot(player.global_basis.z)) * half.z)
	var min_distance: float = maxf(player.CARRY_MIN_DISTANCE, support + player.CARRY_FACE_CLEARANCE)
	var hit: Dictionary = raycast(from, target + direction * support, player.WORLD_BLOCKING_MASK)
	if hit.is_empty():
		return from + direction * maxf(reach, min_distance)
	var allowed: float = from.distance_to(hit["position"]) - support - 0.02
	return from + direction * clampf(allowed, min_distance, maxf(reach, min_distance))


func raycast(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [player.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(query)


func transfer_target() -> Node:
	var eye: Vector3 = player._camera.global_position
	var forward: Vector3 = -player._camera.global_basis.z
	var best: Node = null
	var best_score: float = 0.7
	for node: Node in player.get_tree().get_nodes_in_group(&"player"):
		var teammate := node as Player
		if teammate == null or teammate == player or teammate.carried_package != null:
			continue
		var to_teammate: Vector3 = teammate.global_position - eye
		var distance: float = to_teammate.length()
		if distance > 2.4 or distance < 0.05:
			continue
		var score: float = forward.dot(to_teammate / distance)
		if score > best_score:
			best_score = score
			best = teammate
	return best


func drop_carried() -> void:
	if player.carried_package == null:
		return
	var drop_transform := Transform3D(player.global_basis, drop_position(player.carried_package.get_half_extents()))
	var vehicle: Node3D = player._find_vehicle()
	var aboard: bool = vehicle != null and bool(vehicle.call(&"carries", drop_transform.origin, player.RIDE_MARGIN))
	if aboard:
		drop_transform = vehicle.global_transform.affine_inverse() * drop_transform
	player.carried_package.rpc_id(1, &"request_drop", drop_transform, aboard)
	# The host confirms this on every peer; clear locally now for responsive hands.
	player.carried_package = null


func drop_position(half_extents: Vector3) -> Vector3:
	var forward: Vector3 = -player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var chest: Vector3 = player.global_position + Vector3.UP * player.DROP_CHEST_HEIGHT
	var distance: float = player.BODY_RADIUS + player.DROP_GAP + half_extents.z
	var wall: Dictionary = raycast(chest, chest + forward * (distance + half_extents.z), player.WORLD_BLOCKING_MASK)
	if not wall.is_empty():
		distance = maxf(chest.distance_to(wall["position"]) - half_extents.z - player.DROP_SETTLE_MARGIN, 0.0)
	var spot: Vector3 = chest + forward * distance
	var ground: Dictionary = raycast(spot, spot - Vector3.UP * player.DROP_GROUND_PROBE, player.WORLD_BLOCKING_MASK)
	if ground.is_empty():
		return spot
	return Vector3(spot.x, (ground["position"] as Vector3).y + half_extents.y + player.DROP_SETTLE_MARGIN, spot.z)


func apply_pick_up(package_path: NodePath) -> void:
	var was_empty: bool = player.carried_package == null
	player.carried_package = player.get_node_or_null(package_path) as DeliveryPackage
	if was_empty and player.carried_package != null:
		player._pickup_elapsed = 0.0
		player._pickup_from = player.carried_package.global_transform
		player.pickup_high_weight = player.pickup_high_weight_for_package(player.carried_package)
		var pickup_vehicle: Node3D = player._find_vehicle()
		player._pickup_in_vehicle = pickup_vehicle != null and bool(pickup_vehicle.call(&"carries", player._pickup_from.origin, player.RIDE_MARGIN))
		if player._pickup_in_vehicle:
			player._pickup_from = pickup_vehicle.global_transform.affine_inverse() * player._pickup_from
	if player.is_local() and was_empty and player.carried_package != null:
		player._play_one_shot(player.ANIM_PICKUP, player.PICKUP_ANIM_LOCK_MS)


func apply_drop_carried() -> void:
	player.carried_package = null
	if player.is_local():
		clear_carry_focus()

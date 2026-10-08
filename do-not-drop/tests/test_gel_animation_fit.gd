extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_animation_fit.gd
##
## S-311.25 exercises the real gel rig at both leg/arm extremes: gait distance
## follows leg length, both wrists land on the real box, and the visible head
## is fitted below the reference truck's cab roof and rear-door opening.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const VEHICLE_SCENE: String = "res://scenes/gameplay/vehicle/vehicle.tscn"
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Shaper := preload("res://scripts/gameplay/player/gel/gel_body_shaper.gd")
const MotionFit := preload("res://scripts/gameplay/player/gel/gel_animation_fit.gd")
const CarryPose := preload("res://scripts/gameplay/player/carry_pose.gd")
const SeatPose := preload("res://scripts/gameplay/player/player_seat_pose.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	var gel: Node3D = GEL_SCENE.instantiate()
	root.add_child(gel)
	var vehicle: VehicleBody3D = (load(VEHICLE_SCENE) as PackedScene).instantiate()
	root.add_child(vehicle)
	await process_frame
	player.set_physics_process(false)

	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(gel)
	var animation: AnimationPlayer = PlayerAppearance.find_animation_player(gel)
	var shaper: GelBodyShaper = Shaper.new()
	_expect(skeleton != null and animation != null and shaper.setup(gel),
		"the real gel rig exposes its skeleton, clips and proportion shaper")
	if skeleton != null and animation != null:
		_check_gaits(player, animation, shaper)
		await _check_box_hands(player, skeleton, shaper)
		_check_truck_clearance(gel, skeleton, animation, shaper, vehicle)

	player.free()
	gel.free()
	vehicle.free()
	if _failures == 0:
		print("PASS: gel stride, package hands and truck clearances adapt at proportion extremes")
	quit(_failures)


func _check_gaits(player: Player, animation: AnimationPlayer, shaper: GelBodyShaper) -> void:
	var animator := PlayerAnimator.new(player, animation, null)
	var clip: Animation = animation.get_animation(Player.ANIM_WALK)
	var base_stride: float = PlayerAnimator.WALK_AUTHORED_SPEED * clip.length
	for leg_length: float in [0.75, 1.25]:
		var proportions := Proportions.new()
		proportions.leg_length = leg_length
		shaper.apply(proportions)
		animator.set_leg_length_factor(leg_length)
		player.anim_state = Player.ANIM_WALK
		player.locomotion_speed = PlayerAnimator.WALK_AUTHORED_SPEED
		animator.animate()
		var expected_scale: float = 1.0 / leg_length
		_expect(is_equal_approx(animation.speed_scale, expected_scale),
			"leg length %.2f sets gait playback to %.3f" % [leg_length, expected_scale])
		var travelled_per_cycle: float = player.locomotion_speed * clip.length / animation.speed_scale
		_expect(is_equal_approx(travelled_per_cycle, base_stride * leg_length),
			"leg length %.2f produces a matching visual stride" % leg_length)


func _check_box_hands(
	player: Player,
	skeleton: Skeleton3D,
	shaper: GelBodyShaper
) -> void:
	var package: DeliveryPackage = PACKAGE_SCENE.instantiate()
	root.add_child(package)
	package.freeze = true
	package.global_position = Vector3(0.0, 1.0, -0.7)
	for arm_length: float in [0.75, 1.25]:
		var proportions := Proportions.new()
		proportions.arm_length = arm_length
		shaper.apply(proportions)
		var pose: Node3D = CarryPose.new()
		player.add_child(pose)
		pose.call(&"setup", player, skeleton)
		pose.call(&"update_pose", package, 1.0, 1.0)
		var wrists: Dictionary = {}
		var capture := func() -> void:
			for side: String in ["L", "R"]:
				var hand: int = skeleton.find_bone("hand." + side)
				wrists[side] = skeleton.to_global(skeleton.get_bone_global_pose(hand).origin)
		skeleton.skeleton_updated.connect(capture)
		for _frame: int in 5:
			await process_frame
		skeleton.skeleton_updated.disconnect(capture)
		for side: String in ["L", "R"]:
			var target := pose.get_node_or_null("PackageGrip" + side) as Marker3D
			_expect(target != null and wrists.has(side),
				"arm length %.2f exposes the %s wrist and box target" % [arm_length, side])
			if target != null and wrists.has(side):
				var gap: float = (wrists[side] as Vector3).distance_to(target.global_position)
				_expect(gap < 0.04,
					"arm length %.2f keeps the %s hand on the box (gap %.3f m)" % [arm_length, side, gap])
		pose.free()
	package.free()


func _check_truck_clearance(
	gel: Node3D,
	skeleton: Skeleton3D,
	animation: AnimationPlayer,
	shaper: GelBodyShaper,
	vehicle: VehicleBody3D
) -> void:
	var proportions := Proportions.new()
	proportions.total_height = 1.20
	proportions.leg_length = 1.25
	proportions.torso_length = 1.15
	proportions.neck_length = 1.25
	proportions.head_size = 1.25
	shaper.apply(proportions)
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(gel)
	var head: int = skeleton.find_bone(&"head")
	var head_cap: float = mesh.get_aabb().end.y - skeleton.get_bone_global_rest(head).origin.y

	var floor_shape := vehicle.get_node(^"FloorCollision") as CollisionShape3D
	var floor_box := floor_shape.shape as BoxShape3D
	var floor_y: float = floor_shape.global_position.y + floor_box.size.y * 0.5
	var door_shape := vehicle.get_node(^"RearDoorCollision") as CollisionShape3D
	var door_box := door_shape.shape as BoxShape3D
	var door_top: float = door_shape.global_position.y + door_box.size.y * 0.5
	gel.global_position = Vector3(0.0, floor_y, 4.2)
	animation.play(Player.ANIM_WALK)
	animation.seek(0.0, true)
	animation.advance(0.0)
	var doorway_head: float = _head_top(skeleton, head, head_cap, proportions.head_size)
	MotionFit.fit_head_below(gel, doorway_head, door_top)
	_expect(_head_top(skeleton, head, head_cap, proportions.head_size) <= door_top - 0.019,
		"the tallest moving gel clears the real rear-door opening")

	var driver_seat := vehicle.get_node(^"CabinInterior/DriverEyePoint") as Node3D
	var cab_shape := vehicle.get_node(^"CabinCollision") as CollisionShape3D
	var cab_top: float = _shape_top(cab_shape)
	gel.global_position = driver_seat.global_position + SeatPose.new().seat_body_offset(&"DriverEyePoint")
	animation.play(Player.ANIM_SIT)
	animation.seek(0.0, true)
	animation.advance(0.0)
	var seated_head: float = _head_top(skeleton, head, head_cap, proportions.head_size)
	MotionFit.fit_head_below(gel, seated_head, cab_top)
	_expect(_head_top(skeleton, head, head_cap, proportions.head_size) <= cab_top - 0.019,
		"the tallest seated gel clears the real cab roof")


func _head_top(skeleton: Skeleton3D, head: int, head_cap: float, head_size: float) -> float:
	return skeleton.to_global(skeleton.get_bone_global_pose(head).origin).y + head_cap * head_size


func _shape_top(shape_node: CollisionShape3D) -> float:
	var points := (shape_node.shape as ConvexPolygonShape3D).points
	var highest: float = -INF
	for point: Vector3 in points:
		highest = maxf(highest, shape_node.to_global(point).y)
	return highest


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

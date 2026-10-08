extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_fairness.gd
##
## S-311.24 keeps proportions presentation-only: the real player's capsule,
## camera and interaction reach stay fixed. On the gel rig the lowest foot is
## planted on the same floor and the existing package IK targets the real box.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Shaper := preload("res://scripts/gameplay/player/gel/gel_body_shaper.gd")
const Grounding := preload("res://scripts/gameplay/player/gel/gel_foot_grounding.gd")
const CarryPose := preload("res://scripts/gameplay/player/carry_pose.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	var gel: Node3D = GEL_SCENE.instantiate()
	root.add_child(gel)
	var grounding: Node3D = Grounding.new()
	root.add_child(grounding)
	await process_frame
	player.set_physics_process(false)
	var capsule_node := player.get_node(^"CollisionShape3D") as CollisionShape3D
	var capsule := capsule_node.shape as CapsuleShape3D
	var physical_before: Array = [capsule.radius, capsule.height, capsule_node.position,
		player.get_node(^"Head").position, player.get_node(^"Head/Camera3D").position,
		(player.get_node(^"Head/InteractionProbe/ProbeShape") as CollisionShape3D).shape.radius,
		player.reach_origin()]

	_expect(grounding.setup(gel), "the gel rig exposes both leg chains for foot IK")
	var floor_targets: Array[Vector3] = [grounding.target_position(0), grounding.target_position(1)]
	var shaper: GelBodyShaper = Shaper.new()
	_expect(shaper.setup(gel), "the proportion shaper accepts the same gel rig")
	var proportions := Proportions.new()
	proportions.total_height = 1.20
	proportions.leg_length = 0.75
	proportions.arm_length = 1.25
	_expect(shaper.apply(proportions), "extreme visual proportions are applied")
	grounding.update_floor(0.0, true)
	for side: int in 2:
		_expect(is_equal_approx(grounding.target_position(side).y, floor_targets[side].y),
			"foot %d keeps the authored ankle clearance above the floor" % side)
	_expect(grounding.influence(0) > 0.0 or grounding.influence(1) > 0.0,
		"at least the lowest foot is planted")
	grounding.update_floor(0.0, false)
	_expect(grounding.influence(0) == 0.0 and grounding.influence(1) == 0.0,
		"airborne animation releases both foot solvers")

	_check_package_hands(player, gel)
	var physical_after: Array = [capsule.radius, capsule.height, capsule_node.position,
		player.get_node(^"Head").position, player.get_node(^"Head/Camera3D").position,
		(player.get_node(^"Head/InteractionProbe/ProbeShape") as CollisionShape3D).shape.radius,
		player.reach_origin()]
	_expect(physical_after == physical_before,
		"body proportions never change the capsule, camera or interaction reach")

	grounding.clear()
	player.free()
	gel.free()
	grounding.free()
	if _failures == 0:
		print("PASS: gel proportions stay visual while feet and package hands keep contact")
	quit(_failures)


func _check_package_hands(player: Player, gel: Node3D) -> void:
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(gel)
	var package: DeliveryPackage = PACKAGE_SCENE.instantiate()
	root.add_child(package)
	package.global_position = Vector3(0.0, 1.0, -0.7)
	var pose: Node3D = CarryPose.new()
	player.add_child(pose)
	pose.call(&"setup", player, skeleton)
	pose.call(&"update_pose", package, 1.0, 1.0)
	for side: String in ["L", "R"]:
		var target := pose.get_node_or_null("PackageGrip" + side) as Marker3D
		_expect(target != null, "gel %s hand gets a package IK target" % side)
		if target != null:
			var sign_value: float = -1.0 if side == "L" else 1.0
			var half: Vector3 = package.get_half_extents()
			var expected: Vector3 = package.to_global(Vector3(
				sign_value * (half.x + 0.025), minf(half.y * 0.65, 0.16), half.z * 0.72
			)) + package.global_basis.z * 0.065
			_expect(target.global_position.distance_to(expected) < 0.001,
				"gel %s hand targets the real box corner" % side)
	pose.free()
	package.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

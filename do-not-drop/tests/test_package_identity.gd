extends SceneTree

var failures := 0

func _initialize() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	_expect_identity(level.get_node("World/Package"), Vector3(0.65, 0.65, 0.65), &"FragileGlassMarks")
	_expect_identity(level.get_node("World/PackageNoisy"), Vector3(0.65, 0.65, 0.65), &"NoisyVentMarks")
	_expect_identity(level.get_node("World/PackageBalance"), Vector3(0.42, 0.98, 0.42), &"BalanceSeal")
	_expect_identity(level.get_node("World/PackageGrowingWeight"), Vector3(0.95, 0.42, 0.95), &"WeightBands")
	if failures == 0:
		print("PASS: every trap has a distinct package silhouette and visual mark")
	quit(failures)

func _expect_identity(package: Node, expected_size: Vector3, marker: StringName) -> void:
	var box: MeshInstance3D = package.get_node("Box")
	var mesh: BoxMesh = box.mesh as BoxMesh
	_expect(mesh != null and mesh.size.is_equal_approx(expected_size), "%s has its own silhouette" % package.name)
	_expect(package.has_node(NodePath(marker)), "%s has a visible identity mark" % package.name)
	var feedback: Node = package.get_node("PackageFeedbackComponent")
	feedback._on_package_damaged(package.get("package_id"), 20.0)
	_expect(feedback._shipping_label.get_parent() == package.get_parent(), "%s drops its detailed shipping label after a strong hit" % package.name)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

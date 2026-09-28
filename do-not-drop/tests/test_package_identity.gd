extends SceneTree
## Every trap ships in its own printed, openable box with its own contents
## (data/contents/*.tres), sized like its collider.

var failures := 0

func _initialize() -> void:
	var fixtures: Array[Dictionary] = [
		{"trap": "fragile", "content": "porcelain_vase", "size": Vector3(0.65, 0.65, 0.65)},
		{"trap": "noisy", "content": "hen", "size": Vector3(0.65, 0.65, 0.65)},
		{"trap": "balance", "content": "wedding_cake", "size": Vector3(0.42, 0.98, 0.42)},
		{"trap": "growing_weight", "content": "sourdough", "size": Vector3(0.95, 0.42, 0.95)},
	]
	var packages: Array[Node] = []
	for fixture: Dictionary in fixtures:
		var package: Node = load("res://scenes/gameplay/package/package.tscn").instantiate()
		package.name = "Package%s" % String(fixture["trap"]).to_pascal_case()
		package.set(&"package_id", StringName("identity_%s" % fixture["trap"]))
		package.set(&"trap_definition", load("res://data/traps/%s.tres" % fixture["trap"]))
		package.set(&"content", load("res://data/contents/%s.tres" % fixture["content"]))
		root.add_child(package)
		packages.append(package)
	await process_frame
	await process_frame
	for i: int in fixtures.size():
		_expect_identity(packages[i], fixtures[i]["size"], StringName(fixtures[i]["content"]))
	if failures == 0:
		print("PASS: every trap has its own box, contents, label and damage marks")
	quit(failures)

func _expect_identity(package: Node, expected_size: Vector3, content_id: StringName) -> void:
	var content: Resource = package.call(&"content_definition")
	_expect(content != null and content.get(&"id") == content_id, "%s carries %s" % [package.name, content_id])
	var shape: BoxShape3D = (package.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	_expect(shape != null and shape.size.is_equal_approx(expected_size), "%s collider matches its box" % package.name)
	var model: Node = package.get_node_or_null("Box/Model")
	_expect(model != null, "%s has a box model" % package.name)
	if model != null:
		for flap: String in ["FlapFront", "FlapBack", "FlapRight", "FlapLeft", "Body"]:
			_expect(model.find_child(flap, true, false) != null, "%s box has %s" % [package.name, flap])
	_expect(package.has_node("Box/Contents/Intact") and package.has_node("Box/Contents/Ruined"), "%s has its contents inside" % package.name)
	var feedback: Node = package.get_node("PackageFeedbackComponent")
	_expect(feedback._shipping_label.collision_layer == 0, "%s label does not block its carrier" % package.name)
	var text: Label3D = feedback._shipping_label.find_children("*", "Label3D", false, false).front()
	_expect(text.text.contains(String(content.get(&"display_name"))), "%s label declares its contents" % package.name)
	feedback._on_package_damaged(package.get("package_id"), 10.0)
	_expect(feedback._dent_pieces[0].scale.x > 0.0, "%s visibly dents after an impact" % package.name)
	feedback._on_package_damaged(package.get("package_id"), 20.0)
	_expect(feedback._shipping_label.get_parent() == package.get_parent(), "%s drops its detailed shipping label after a strong hit" % package.name)
	_expect(feedback._shipping_label.collision_layer == 4, "%s fallen label becomes physical" % package.name)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

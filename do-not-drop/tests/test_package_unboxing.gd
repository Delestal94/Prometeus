extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_package_unboxing.gd
##
## Opening a package: the lid is host state (package.gd), the flaps and the
## contents are presentation (package_contents_view.gd). Covers opening and
## closing, contents that follow the trap state, an open box spilling its
## contents as real rigid bodies when it tips over, and the resident
## noticing a box handed over open.

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_open_and_close()
	await _test_contents_follow_state()
	await _test_spill_on_tip()
	await _test_open_delivery_is_marked()
	if failures == 0:
		print("PASS: packages open, show their contents, spill when tipped open, and an open delivery is noticed")
	quit(failures)


func _make_package(trap: String, id: StringName) -> RigidBody3D:
	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	package.set(&"trap_definition", load("res://data/traps/%s.tres" % trap))
	package.set(&"package_id", id)
	root.add_child(package)
	return package


func _test_open_and_close() -> void:
	var package := _make_package("fragile", &"unbox_open")
	package.freeze = true
	await process_frame
	await process_frame
	var view: Node = package.get_node("PackageContentsView")
	var flap: Node3D = package.get_node("Box/Model").find_child("FlapFront", true, false)
	var contents: Node3D = package.get_node("Box/Contents")
	_expect(is_zero_approx(flap.rotation.x), "Starts taped shut")
	_expect(not contents.visible, "Nothing is drawn inside a closed box")
	_expect(String(view.call(&"describe")).is_empty(), "A closed box tells you nothing about its contents")

	package.call(&"request_set_open", true)
	_expect(bool(package.get(&"is_open")), "The host opens it on request")
	await create_timer(0.8).timeout
	_expect(flap.rotation.x > 1.6, "The front flap swings out (got %.2f rad)" % flap.rotation.x)
	var side: Node3D = package.get_node("Box/Model").find_child("FlapRight", true, false)
	_expect(side.rotation.z < -1.4, "The side flaps stand up too")
	_expect(contents.visible and (package.get_node("Box/Contents/Intact") as Node3D).visible, "The intact vase is visible inside")
	_expect(String(view.call(&"describe")).contains("Jarrón de porcelana"), "Looking in names what's there")

	package.call(&"request_set_open", false)
	await create_timer(0.6).timeout
	_expect(is_zero_approx(snappedf(flap.rotation.x, 0.001)), "Closing folds the flaps back down")
	_expect(not contents.visible, "And hides the contents again")
	package.free()


func _test_contents_follow_state() -> void:
	var package := _make_package("fragile", &"unbox_state")
	package.freeze = true
	await process_frame
	await process_frame
	package.call(&"set_open", true)
	var view: Node = package.get_node("PackageContentsView")
	var bus: Node = root.get_node("EventBus")
	bus.emit_signal(&"package_state_changed", &"unbox_state", ITrapBehavior.TrapState.AT_RISK)
	_expect((package.get_node("Box/Contents/Damage") as Node3D).visible, "AT_RISK shows the cracks")
	_expect(String(view.call(&"describe")).contains("con fisuras"), "And says so")
	bus.emit_signal(&"package_state_changed", &"unbox_state", ITrapBehavior.TrapState.RUINED)
	_expect(not (package.get_node("Box/Contents/Intact") as Node3D).visible, "RUINED hides the whole vase")
	_expect((package.get_node("Box/Contents/Ruined") as Node3D).visible, "...and shows the shards instead")
	package.free()


func _test_spill_on_tip() -> void:
	var package := _make_package("noisy", &"unbox_spill")
	package.gravity_scale = 0.0
	await process_frame
	await process_frame
	package.call(&"set_open", true)
	package.rotation = Vector3(0.0, 0.0, deg_to_rad(100.0))
	for i: int in 4:
		await physics_frame
	_expect(bool(package.get(&"contents_spilled")), "An open box on its side spills")
	_expect(int(package.get(&"trap_state")) == ITrapBehavior.TrapState.RUINED, "Spilling the contents loses the package")
	var spilled: int = 0
	for node: Node in root.get_children():
		if node is RigidBody3D and String(node.name).begins_with("SpilledContent"):
			spilled += 1
	_expect(spilled >= 2, "The hen and the straw come out as rigid bodies (got %d)" % spilled)
	_expect(not (package.get_node("Box/Contents/Intact") as Node3D).visible, "The box is empty afterwards")
	package.call(&"set_open", false)
	_expect(bool(package.get(&"is_open")), "There's nothing left to close it on")
	for node: Node in root.get_children():
		if String(node.name).begins_with("SpilledContent"):
			node.free()
	package.free()

	# A closed box can go over without anything coming out.
	var closed := _make_package("noisy", &"unbox_closed_tip")
	closed.gravity_scale = 0.0
	await process_frame
	closed.rotation = Vector3(0.0, 0.0, deg_to_rad(100.0))
	for i: int in 4:
		await physics_frame
	_expect(not bool(closed.get(&"contents_spilled")), "A taped box keeps its contents when it tips")
	closed.free()


func _test_open_delivery_is_marked() -> void:
	var house: Node3D = load("res://scripts/gameplay/route/delivery_house.gd").new()
	root.add_child(house)
	var opened := _make_package("fragile", &"unbox_deliver_open")
	opened.freeze = true
	await process_frame
	opened.call(&"set_open", true)
	house.call(&"_on_doorbell_rung", opened)
	_expect(house.get(&"outcome") == &"delivered_at_risk", "A box handed over open counts as delivered with reservations")
	house.free()

	var house2: Node3D = load("res://scripts/gameplay/route/delivery_house.gd").new()
	root.add_child(house2)
	var closed := _make_package("fragile", &"unbox_deliver_closed")
	closed.freeze = true
	await process_frame
	house2.call(&"_on_doorbell_rung", closed)
	_expect(house2.get(&"outcome") == &"delivered_ok", "The same box closed is a clean delivery")
	house2.free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1

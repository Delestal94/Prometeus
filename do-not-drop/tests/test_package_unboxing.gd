extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_package_unboxing.gd
##
## Opening a package: the lid is host state (package.gd), the flaps and the
## contents are presentation (package_contents_view.gd). Covers opening and
## closing, contents that follow the trap state, an open box spilling its
## contents as real rigid bodies when it tips over (and doing it cheaply: a
## ruined box throws every shard in one physics tick, N-220), and the resident
## noticing a box handed over open.

## What spilling a ruined box (a hen's eight shards plus the straw) may take, in
## ms. With simplified convex shapes (simplify = true) it took 10-70 ms per
## shard (150-250 ms for the hen) on a fast desktop; the plain hull takes
## ~2 ms in all. Generous on purpose: only the old cost may fail it.
const SPILL_BUDGET_MS: float = 60.0

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_content_model_contract()
	_test_trap_content_catalog()
	await _test_open_and_close()
	await _test_contents_follow_state()
	await _test_spill_on_tip()
	await _test_spill_cost()
	await _test_open_delivery_is_marked()
	if failures == 0:
		print("PASS: packages open, show their contents, spill when tipped open, and an open delivery is noticed")
	quit(failures)


func _test_content_model_contract() -> void:
	var files: PackedStringArray = DirAccess.get_files_at("res://data/contents")
	files.sort()
	for file: String in files:
		if not file.ends_with(".tres"):
			continue
		var content: Resource = load("res://data/contents/%s" % file)
		var content_id: String = String(content.get(&"id"))
		var model: PackedScene = content.get(&"model") as PackedScene
		_expect(model != null, "%s has a content model" % content_id)
		if model == null:
			continue
		var instance: Node = model.instantiate()
		for node_name: String in ["Filler", "Intact", "Damage", "Ruined"]:
			_expect(instance.get_node_or_null(NodePath(node_name)) != null,
				"%s model has %s" % [content_id, node_name])
		instance.free()


func _test_trap_content_catalog() -> void:
	var expected := {
		"balance": ["glass_tower", "wedding_cake"],
		"explosive": ["fireworks_crate"],
		"fragile": ["porcelain_vase", "antique_lamp"],
		"growing_weight": ["sourdough"],
		"hostile": ["raccoon_cage"],
		"liquid": ["milk_canister"],
		"noisy": ["hen", "puppy"],
	}
	for trap_id: String in expected:
		var definition: Resource = load("res://data/traps/%s.tres" % trap_id)
		var actual: Array[String] = []
		for content: Resource in definition.get(&"contents"):
			actual.append(String(content.get(&"id")))
		_expect(actual == expected[trap_id], "%s has its intended contents (got %s)" % [trap_id, str(actual)])


func _make_package(trap: String, id: StringName) -> RigidBody3D:
	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	package.set(&"trap_definition", load("res://data/traps/%s.tres" % trap))
	var fixtures := {"fragile": "porcelain_vase", "noisy": "hen"}
	if fixtures.has(trap):
		package.set(&"content", load("res://data/contents/%s.tres" % fixtures[trap]))
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
	# Spilling opens a rescue (docs/jugabilidad-paquetes-rescate.md), not an
	# instant loss: the box is at risk until it's recovered or the window ends.
	var rescuing: bool = package.get(&"care").phase == &"crisis"
	_expect(int(package.get(&"trap_state")) == ITrapBehavior.TrapState.AT_RISK and rescuing,
		"Spilling the contents starts a rescue instead of losing the package")
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


func _test_spill_cost() -> void:
	var package := _make_package("noisy", &"unbox_spill_cost")
	package.freeze = true
	await process_frame
	await process_frame
	package.call(&"set_open", true)
	var started: int = Time.get_ticks_usec()
	root.get_node("EventBus").emit_signal(&"package_contents_spilled", &"unbox_spill_cost", Vector3.ZERO,
		ITrapBehavior.TrapState.RUINED)
	var spill_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	var shards: int = 0
	for node: Node in root.get_children():
		if node is RigidBody3D and String(node.name).begins_with("SpilledContent"):
			shards += 1
	_expect(shards >= 8, "A ruined hen box throws its shards and the straw (got %d bodies)" % shards)
	_expect(spill_ms < SPILL_BUDGET_MS,
		"Spilling a ruined box stays under %.0f ms (took %.1f ms): convex shapes are not simplified"
		% [SPILL_BUDGET_MS, spill_ms])
	for node: Node in root.get_children():
		if String(node.name).begins_with("SpilledContent"):
			node.free()
	package.free()
	await process_frame


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

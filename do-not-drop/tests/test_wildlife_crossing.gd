extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_wildlife_crossing.gd
## The deer crossing, with the real truck: at full speed without braking the
## truck catches the deer frozen in the lane -- the cargo takes the hit, the
## team pays the fine and the HUD says why; slowed down after the warning,
## the deer is across and gone before the truck gets there. Also checks
## the wildlife models carry the joints their animation needs.

var _failures: int = 0
var _impacts: Array[float] = []
var _banners: Array[Dictionary] = []
var _resolved: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_models_have_joints()
	var bus: Node = root.get_node(^"/root/EventBus")
	bus.connect(&"vehicle_impact", func(strength: float, _at: Vector3) -> void: _impacts.append(strength))
	bus.connect(&"route_event_started", func(_id: StringName, event: Dictionary) -> void: _banners.append(event))
	bus.connect(&"route_event_resolved", func(id: StringName, success: bool, _peer: int) -> void: _resolved.append([id, success]))

	var fast := await _drive_through(20.0)
	_expect(fast.hit, "Full speed without braking: the truck hits the deer")
	_expect(fast.money_lost == 30, "The team pays the $30 fine (lost %d)" % fast.money_lost)
	_expect(fast.impacts > 0, "The hit reaches the cargo as a vehicle impact")
	_expect(fast.banner.contains("ciervo"), "The HUD tells the crew what happened")
	_expect(fast.deer_gone, "The deer gets up and runs off into the trees")
	_expect(fast.incident, "The hit is flagged as an incident with no countdown (incident, duration 0)")
	# An incident has nothing to respond to: it closes itself, even after the
	# stretch it happened on is gone, so no banner hangs waiting for it.
	var waited: float = 0.0
	while _resolved.is_empty() and waited < WildlifeCrossing.INCIDENT_SECONDS + 2.0:
		await create_timer(0.25).timeout
		waited += 0.25
	_expect(_resolved.size() == 1 and _resolved[0] == [&"deer_hit", false],
		"The deer hit is resolved (as a failure) a few seconds later: %s" % [_resolved])

	var careful := await _drive_through(11.0)
	_expect(not careful.hit, "Slowed down after the warning: the deer is across before the truck arrives")
	_expect(careful.money_lost == 0 and careful.impacts == 0, "No fine and no jolt for a careful driver")
	_expect(careful.deer_gone, "The deer clears the road and disappears")

	if _failures == 0:
		print("PASS: deer crossing -- hit costs cargo and money, braking avoids it; wildlife models are rigged")
	quit(_failures)


func _drive_through(speed: float) -> Dictionary:
	_impacts.clear()
	_banners.clear()
	_resolved.clear()
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 400.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	world.add_child(ground)
	var crossing := WildlifeCrossing.new()
	crossing.side = 1.0
	world.add_child(crossing)
	var van := (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	van.position = Vector3(-1.5, 0.7, 70.0)
	world.add_child(van)
	van.controls_enabled = false
	var run_manager: Node = root.get_node(^"/root/RunManager")
	run_manager.set(&"is_running", true)
	var crew: Node = root.get_node(^"/root/CrewProgression")
	if crew.has_method(&"reset_run"):
		crew.call(&"reset_run")
	var money_before: int = int(crew.get(&"team_money"))
	for tick in range(30):
		await physics_frame
	# Hold a steady speed toward the crossing (the truck drives toward -Z).
	for tick in range(360):
		if not crossing.hit:
			van.set_controls(0.5, 0.0, false)  # A driver on the throttle (also keeps it unparked).
			van.linear_velocity = Vector3(0.0, van.linear_velocity.y, -speed)
		else:
			van.set_controls(0.0, 0.0, false)
		await physics_frame
		if van.global_position.z < -40.0 and crossing.state == WildlifeCrossing.State.DONE:
			break
	for tick in range(240):
		await physics_frame
		if crossing.state == WildlifeCrossing.State.DONE:
			break
	var result := {
		"hit": crossing.hit,
		"money_lost": money_before - int(crew.get(&"team_money")),
		"impacts": _impacts.size(),
		"banner": String(_banners[-1].get("title", "")).to_lower() if not _banners.is_empty() else "",
		"deer_gone": crossing.state == WildlifeCrossing.State.DONE and not crossing.deer.visible,
		"incident": not _banners.is_empty() and bool(_banners[-1].get("incident", false)) and int(_banners[-1].get("duration", -1)) == 0,
	}
	run_manager.set(&"is_running", false)
	world.free()
	await process_frame
	return result


func _test_models_have_joints() -> void:
	# The deer is rigged and keyframed: it needs the animations the crossing
	# and the roadside behaviour ask for.
	var deer := (load("res://assets/models/environment/wildlife/sm_env_animal_stag_rigged.glb") as PackedScene).instantiate()
	var animator := deer.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_expect(animator != null, "The deer has an AnimationPlayer")
	if animator != null:
		for animation: String in ["Gallop", "Idle", "Eating", "Idle_Headlow", "Idle_2", "Idle_HitReact_Left", "Idle_HitReact_Right"]:
			_expect(animator.has_animation(animation), "The deer can play %s" % animation)
	deer.free()
	var expected := {
		"rabbit": ["Legs_Front", "Legs_Back", "Ears", "Tail"],
		"frog": ["Legs_Front", "Legs_Back", "Throat"],
		"bird": ["Wing_L", "Wing_R", "Head", "Tail"],
	}
	for species: String in expected:
		var model := (load("res://assets/models/environment/wildlife/sm_env_animal_%s.glb" % species) as PackedScene).instantiate()
		for joint: String in expected[species]:
			_expect(model.find_child(joint, true, false) != null, "The %s has its %s joint" % [species, joint])
		model.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

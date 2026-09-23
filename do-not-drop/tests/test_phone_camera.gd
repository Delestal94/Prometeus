extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_phone_camera.gd
##
## The delivery photo: the phone picks the right door, files exactly one
## photo against it, refuses to double-count, and -- the part that gives the
## mechanic its point -- a photographed delivery survives the resident's
## complaint at the results screen while an undocumented one doesn't.
##
## Rendering is off here, so the captured image is always null; that's the
## behaviour being pinned down too. The photo has to still count as taken
## even when there's no framebuffer to read, otherwise the whole feature
## would quietly depend on a display being present.

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	var manager: Node = root.get_node("RunManager")
	var phone: Node = level.get_node("PhoneCamera")
	var lens: Node3D = phone.get_node("PhoneLens")
	var houses: Array = (level.get_node("World/Route")).get(&"houses")
	_expect(houses.size() >= 2, "The route built enough houses to tell them apart (got %d)" % houses.size())

	# --- the lens sees what the player's eyes see, not the inside of their head ---
	var eyes := Camera3D.new()
	eyes.cull_mask = 0xFFFFF & ~2
	eyes.near = 0.03
	level.add_child(eyes)
	phone.call(&"_match_lens", eyes)
	_expect((lens as Camera3D).cull_mask == eyes.cull_mask, "The lens culls the local body like the first-person camera does")
	_expect(is_equal_approx((lens as Camera3D).near, 0.03), "The lens keeps the first-person near plane")
	eyes.queue_free()

	# --- nothing delivered yet: there's nothing to document anywhere ---
	lens.global_position = houses[0].call(&"porch_position")
	_expect(phone.subject_house() == -1, "A door nobody delivered to is not a photo subject")

	# --- deliver at house 0, then stand at its porch ---
	# finish_run() only scores a run that actually started, so start one by
	# hand here: this test is about the phone, not about the loading flow
	# that test_house_delivery_flow.gd already drives end to end.
	manager.start_run()
	manager.expected_houses = houses.size()
	houses[0].set(&"delivered", true)
	manager.register_delivery(0, &"delivered_ruined", &"box_a")
	_expect(phone.subject_house() == 0, "The nearest delivered door is the subject (got %d)" % phone.subject_house())

	# Far enough away and it stops being the subject -- standing on the road
	# a hundred metres on shouldn't let you document a doorstep.
	lens.global_position = houses[0].call(&"porch_position") + Vector3(0.0, 0.0, 120.0)
	_expect(phone.subject_house() == -1, "A delivered door out of range is not the subject")
	lens.global_position = houses[0].call(&"porch_position")

	# --- the shutter files the photo, once ---
	await phone.shoot()
	_expect(bool(manager.deliveries[0]["photo"]), "The shutter files the photo against that door")
	_expect(not manager.delivery_photos.has(0), "No image is stored when there's no framebuffer to read")
	await phone.shoot()
	_expect(manager.deliveries.size() == 1 and int(manager.results.get("photos", -1)) != 2,
		"A second shot at the same door doesn't file a second photo")

	# --- the payoff: the photo settles the complaint ---
	manager.finish_run(true)
	var documented: Dictionary = manager.results
	_expect(int(documented["photos"]) == 1, "Results count the photo (got %d)" % int(documented["photos"]))
	var complaints: Array = documented["complaints"]
	_expect(complaints.size() == 1, "A box delivered wrecked draws exactly one complaint (got %d)" % complaints.size())
	_expect(bool(complaints[0]["dismissed"]), "The photo gets the complaint dismissed")
	var with_photo: int = int(documented["delivery_points"])

	# Same delivery, same wrecked box, no photo: now the complaint lands.
	manager.reset_run()
	manager.start_run()
	manager.expected_houses = houses.size()
	manager.register_delivery(0, &"delivered_ruined", &"box_a")
	manager.finish_run(true)
	var undocumented: Dictionary = manager.results
	_expect(not bool((undocumented["complaints"] as Array)[0]["dismissed"]), "Without a photo the complaint stands")
	var without_photo: int = int(undocumented["delivery_points"])
	var gap: int = manager.POINTS_PHOTO_BONUS + manager.COMPLAINT_PENALTY
	_expect(with_photo - without_photo == gap,
		"Taking the photo is worth the bonus plus the penalty it avoids (got %d, expected %d)" % [with_photo - without_photo, gap])

	level.free()
	await create_timer(0.1).timeout
	if failures == 0:
		print("PASS: the phone documents the right door once, and the photo is what settles the complaint")
	quit(failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1

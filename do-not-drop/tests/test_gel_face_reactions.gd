extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_face_reactions.gd
## S-311.59: gameplay state temporarily overrides a player's selected face.

const Reactions := preload("res://scripts/gameplay/player/gel/gel_face_reactions.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player_script := GDScript.new()
	player_script.source_code = "extends CharacterBody3D\n" \
		+ "var _ragdolled: bool = false\nvar net_in_vehicle: bool = false\n" \
		+ "var face_eyes: StringName = &\"classic\"\nvar face_mouth: StringName = &\"smile\"\n" \
		+ "var carried_package: Node = null\nvar tended_package: Node = null\n" \
		+ "var assisted_package: Node = null\nvar _body_visual: Node = null\n" \
		+ "var _character_face: Node = null\n"
	player_script.reload()
	var player := player_script.new() as CharacterBody3D
	root.add_child(player)

	var face_script := GDScript.new()
	face_script.source_code = "extends Node\nvar face_id: StringName = &\"none\"\n" \
		+ "var eyes_id: StringName = &\"none\"\nvar mouth_id: StringName = &\"none\"\n" \
		+ "func set_face(value: StringName) -> void:\n\tface_id = value\n" \
		+ "func set_expression(eyes: StringName, mouth: StringName) -> void:\n" \
		+ "\tface_id = &\"\"\n\teyes_id = eyes\n\tmouth_id = mouth\n"
	face_script.reload()
	var face: Node = face_script.new()
	player.add_child(face)
	var reactions: Node = Reactions.new()
	player.add_child(reactions)
	reactions.call(&"set_face_target", face)
	reactions.call(&"_process", 0.0)
	_expect(reactions.get(&"current_face_id") == &"base" and face.get(&"face_id") == &"none",
		"idle restores the selected base face")

	var package_script := GDScript.new()
	package_script.source_code = "extends Node\nvar package_id: StringName = &\"fragile\"\n" \
		+ "var trap_state: int = 1\nvar carrier: Node = null\nvar tender_peer_id: int = 0\n" \
		+ "func run_state() -> int:\n\treturn trap_state\n"
	package_script.reload()
	var package: Node = package_script.new()
	root.add_child(package)
	package.add_to_group(&"cargo")
	player.set(&"carried_package", package)
	reactions.call(&"_process", 0.0)
	_expect(face.get(&"face_id") == &"worried", "an at-risk held box makes the player worried")

	package.set(&"trap_state", ITrapBehavior.TrapState.OK)
	player.set(&"carried_package", null)
	reactions.call(&"_on_house_delivery_recorded", 2, &"delivered_ok", &"fragile")
	_expect(face.get(&"face_id") == &"happy", "a perfect delivery of the remembered box makes the player happy")

	player.velocity.y = -2.0
	reactions.call(&"_process", 0.0)
	_expect(face.get(&"face_id") == &"surprised", "falling overrides the delivery smile with surprise")
	player.set(&"_ragdolled", true)
	reactions.call(&"_process", 0.0)
	_expect(face.get(&"face_id") == &"crossed", "ragdoll uses the dizzy crossed face")
	reactions.call(&"set_knocked_out", true)
	_expect(face.get(&"face_id") == &"knockout", "knockout has highest priority and uses X eyes")

	reactions.call(&"set_knocked_out", false)
	player.set(&"_ragdolled", false)
	player.velocity.y = 0.0
	reactions.set(&"_happy_until", Time.get_ticks_msec() - 1)
	reactions.call(&"_process", 0.0)
	_expect(face.get(&"face_id") == &"none" and reactions.get(&"current_face_id") == &"base",
		"temporary reactions return to the selected face")
	reactions.call(&"set_base_face", &"loved")
	_expect(face.get(&"face_id") == &"loved", "customisation can replace the neutral face")

	reactions.set(&"_happy_until", 0)
	reactions.call(&"_on_house_delivery_recorded", 3, &"delivered_ok", &"somebody_elses")
	_expect(face.get(&"face_id") == &"loved", "somebody else's perfect delivery does not change this face")
	reactions.call(&"_on_house_delivery_recorded", 3, &"delivered_at_risk", &"fragile")
	_expect(face.get(&"face_id") == &"loved", "only a perfect delivery triggers happiness")

	var real: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	root.add_child(real)
	await process_frame
	var real_reactions: Node = real.get_node_or_null(^"GelFaceReactions")
	_expect(real_reactions != null, "every player includes the face-reaction component")
	if real_reactions != null:
		real_reactions.call(&"_process", 0.0)
		_expect(real_reactions.get(&"face") == real.get(&"_character_face"),
			"the component controls the current face until the gel body replaces it")

	real.free()
	package.free()
	player.free()
	if _failures == 0:
		print("PASS: gel faces react to package danger, delivery, falling, ragdoll and knockout")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

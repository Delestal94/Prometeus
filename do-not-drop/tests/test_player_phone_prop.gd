extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_player_phone_prop.gd
##
## S-304: the phone in the gel character's right hand while its owner has the
## phone camera open (player_phone_prop.gd), so the rest of the crew can see it.
## Checks that:
## - the phone is not even built by default (nothing costs anything for a player
##   who never opens it) and `PlayerPhoneProp:phone_raised` is replicated by player.tscn, spawn
##   state included, so a late joiner sees the phone already up;
## - setting `phone_raised` builds the phone under a BoneAttachment3D on hand.R,
##   shows it, and the right hand really comes up to the head while the left arm
##   stays where it was;
## - the prop sits on the owner's LOCAL_BODY layer (culled from their own first-
##   person camera and phone lens) and on WORLD for a remote copy, and casts a
##   shadow like the body;
## - clearing `phone_raised` lowers the arm and removes the prop and the IK;
## - sitting, a ragdoll fall, a carried box, an emote and a knockout each put the
##   phone away at once, and it comes back when they end;
## - PhoneCamera opening and closing flips `phone_raised` on the local player
##   only, never on another player's copy;
## - NetworkManager.PROTOCOL_VERSION moved with the new replicated property.
##
## Nothing is drawn headless: how the arm and phone read is for revisor-visual.

const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const PHONE_CAMERA: String = "res://scripts/presentation/phone_camera.gd"
const RenderLayers = preload("res://scripts/core/render_layers.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_replication()
	var player: Player = await _spawn(1)
	await _check_default_and_raise(player)
	await _check_blockers(player)
	await _check_layers(player)
	await _check_phone_camera(player)
	if _failures == 0:
		print("PASS: the raised phone shows in the owner's right hand for every peer")
	quit(_failures)


func _spawn(peer_id: int) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_%d" % peer_id
	root.add_child(player)
	await process_frame
	await process_frame
	return player


func _check_replication() -> void:
	var scene: SceneState = PLAYER_SCENE.get_state()
	var config: SceneReplicationConfig
	for index: int in scene.get_node_count():
		for prop: int in scene.get_node_property_count(index):
			if scene.get_node_property_name(index, prop) == &"replication_config":
				var found: SceneReplicationConfig = scene.get_node_property_value(index, prop) as SceneReplicationConfig
				if found != null and found.has_property(^".:anim_clip"):
					config = found
	_expect(config != null, "player.tscn has a replication config for the player")
	if config == null:
		return
	_expect(config.has_property(^"PlayerPhoneProp:phone_raised"), "phone_raised is replicated with the player")
	_expect(config.property_get_spawn(^"PlayerPhoneProp:phone_raised"), "phone_raised is part of the spawn state")
	var mode: int = config.property_get_replication_mode(^"PlayerPhoneProp:phone_raised")
	_expect(mode == SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE, "phone_raised only goes out when it changes")
	var manager: Node = root.get_node(^"/root/NetworkManager")
	_expect(int(manager.get(&"PROTOCOL_VERSION")) >= 62, "The protocol version moved with phone_raised (S-304)")


func _check_default_and_raise(player: Player) -> void:
	var prop: Node3D = player.get_node(^"PlayerPhoneProp")
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(player._body_visual)
	_expect(not _raised(player), "The phone starts down")
	_expect(prop.phone() == null, "No phone exists until it is raised")
	var hand_probe := BoneAttachment3D.new()
	hand_probe.bone_name = &"hand.R"
	skeleton.add_child(hand_probe)
	var left_probe := BoneAttachment3D.new()
	left_probe.bone_name = &"hand.L"
	skeleton.add_child(left_probe)
	await process_frame
	var down_hand: Vector3 = hand_probe.global_position - player.global_position
	var down_left: Vector3 = left_probe.global_position - player.global_position
	var head: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(&"head")).origin
	head -= player.global_position

	_raise(player, true)
	await _settle(player)
	var phone: Node3D = prop.phone()
	_expect(phone != null and phone.is_visible_in_tree(), "Raising the phone shows it")
	if phone != null:
		_expect(phone.get_parent() is BoneAttachment3D
				and (phone.get_parent() as BoneAttachment3D).bone_name == &"hand.R",
			"The phone hangs from a bone attachment on hand.R")
		_expect(phone.get_parent().get_parent() == skeleton, "The attachment lives on the character's skeleton")
		var long_side: float = _longest_extent(phone)
		_expect(long_side > 0.1 and long_side < 0.35, "The phone is phone-sized (%.2f m)" % long_side)
	var up_hand: Vector3 = hand_probe.global_position - player.global_position
	_expect(up_hand.y > down_hand.y + 0.3,
		"The right hand comes up (%.2f m -> %.2f m)" % [down_hand.y, up_hand.y])
	_expect(up_hand.y > head.y - 0.2 and up_hand.z < -0.1,
		"The hand is up by the face and in front of it (%s, head at y %.2f)" % [up_hand, head.y])
	_expect(up_hand.distance_to(prop.wrist_target().position) < 0.05,
		"The IK reaches its target (off by %.3f m)" % up_hand.distance_to(prop.wrist_target().position))
	_expect(left_probe.global_position.distance_to(player.global_position + down_left) < 0.05,
		"The left arm stays put")
	if phone != null:
		var phone_in_player: Vector3 = player.to_local(phone.global_position)
		_expect(phone_in_player.y > down_hand.y + 0.3 and phone_in_player.z < -0.15,
			"The phone is held up in front, not at the side (%s)" % phone_in_player)
		# The screen looks back at the player's eyes (+Z) and the camera lenses
		# away from them: the phone's -Z is its screen.
		var screen: Vector3 = player.global_basis.inverse() * (-phone.global_basis.z).normalized()
		_expect(screen.z > 0.7, "The screen faces the player's eyes (normal %s)" % screen)

	_raise(player, false)
	await _settle(player)
	_expect(prop.phone() == null and prop.wrist_target() == null, "Putting the phone away removes it and the IK")
	await process_frame
	var back_hand: Vector3 = hand_probe.global_position - player.global_position
	_expect(back_hand.distance_to(down_hand) < 0.05,
		"The arm is back at the side (%s vs %s)" % [back_hand, down_hand])
	hand_probe.queue_free()
	left_probe.queue_free()


func _check_blockers(player: Player) -> void:
	var prop: Node3D = player.get_node(^"PlayerPhoneProp")
	_raise(player, true)
	await _settle(player)
	_expect(prop.phone() != null, "Raised again, the phone is back")

	player.seat_node_path = NodePath("Somewhere/DriverEyePoint")
	prop.update_pose(0.016)
	_expect(prop.phone() == null, "Sitting down puts the phone away at once")
	player.seat_node_path = NodePath()
	await _settle(player)
	_expect(prop.phone() != null, "Standing up with the phone still open raises it again")

	player._ragdolled = true
	prop.update_pose(0.016)
	_expect(prop.phone() == null, "A ragdoll fall puts the phone away")
	player._ragdolled = false
	await _settle(player)

	var box := DeliveryPackage.new()
	player.carried_package = box
	prop.update_pose(0.016)
	_expect(prop.phone() == null, "Carrying a box leaves the arms to the carry pose")
	player.carried_package = null
	box.free()
	await _settle(player)

	player.anim_state = PlayerAnimator.EMOTE_CLIPS[0]
	prop.update_pose(0.016)
	_expect(prop.phone() == null, "An emote owns the arm while it plays")
	player.anim_state = Player.ANIM_IDLE
	await _settle(player)
	_expect(prop.phone() != null, "The phone comes back after the emote")

	player._gel_effects_component.knockout_cause = 1
	prop.update_pose(0.016)
	_expect(prop.phone() == null, "A knocked-out gel drops the phone")
	player._gel_effects_component.knockout_cause = 0
	_raise(player, false)
	await _settle(player)


func _check_layers(player: Player) -> void:
	_raise(player, true)
	await _settle(player)
	var phone: Node3D = player.get_node(^"PlayerPhoneProp").phone()
	_expect(phone != null, "The phone exists to check its layers")
	if phone != null:
		_expect(_all_layers(phone, RenderLayers.LOCAL_BODY),
			"The local player's phone is on the local-body layer, culled from their own view")
		_expect(_all_shadows(phone), "The phone casts a shadow like the body does")
	_raise(player, false)
	await _settle(player)
	# A remote copy of the same player is drawn for everyone else.
	var remote: Player = PLAYER_SCENE.instantiate()
	remote.name = "Player_2"
	root.add_child(remote)
	await process_frame
	await process_frame
	_expect(not remote.is_local(), "Player_2 is another peer's copy here")
	_raise(remote, true)
	await _settle(remote)
	var remote_phone: Node3D = remote.get_node(^"PlayerPhoneProp").phone()
	_expect(remote_phone != null and remote_phone.is_visible_in_tree(),
		"A replicated phone_raised raises the phone on the remote copy")
	if remote_phone != null:
		_expect(_all_layers(remote_phone, RenderLayers.WORLD), "A remote player's phone is on the world layer")
	remote.free()


func _check_phone_camera(local: Player) -> void:
	var remote: Player = PLAYER_SCENE.instantiate()
	remote.name = "Player_3"
	root.add_child(remote)
	var eyes := Camera3D.new()
	root.add_child(eyes)
	eyes.current = true
	# Loaded at run time: the script names autoloads, which a --script run only has once the tree exists.
	var camera: CanvasLayer = (load(PHONE_CAMERA) as GDScript).new()
	root.add_child(camera)
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_expect(not _raised(local) and not _raised(remote), "Both players start with the phone down")
	# Opening needs a captured mouse, which a headless run never grants (it reads
	# back as visible); then the same call _open() makes stands in for it.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera.call(&"toggle")
		_expect(bool(camera.get(&"is_open")), "The phone camera opens")
	else:
		camera.call(&"_hold_phone", true)
		camera.set(&"is_open", true)
	_expect(_raised(local), "Opening the camera raises the local player's phone")
	_expect(not _raised(remote), "Another player's copy is not touched")
	camera.call(&"toggle")
	_expect(not bool(camera.get(&"is_open")) and not _raised(local), "Closing the camera puts the local phone away")
	camera.call(&"_hold_phone", true)
	camera.set(&"is_open", true)
	camera.call(&"_on_run_ended", 0, {})
	_expect(not _raised(local), "The end of the run closes the camera and lowers the phone")
	# The online pause menu only frees the mouse; the camera must close then too.
	camera.call(&"_hold_phone", true)
	camera.set(&"is_open", true)
	camera.set(&"_previous_camera", eyes)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await process_frame
	_expect(not bool(camera.get(&"is_open")) and not _raised(local),
		"Freeing the mouse (online pause) closes the camera and lowers the phone")
	camera.free()
	remote.free()
	eyes.free()


func _raise(player: Player, raised: bool) -> void:
	player.get_node(^"PlayerPhoneProp").set(&"phone_raised", raised)


func _raised(player: Player) -> bool:
	return bool(player.get_node(^"PlayerPhoneProp").get(&"phone_raised"))


## Frames for the arm to finish rising or lowering (0.2 s of game time).
func _settle(player: Player) -> void:
	for step: int in 6:
		player.get_node(^"PlayerPhoneProp").update_pose(0.1)
		await process_frame


func _longest_extent(node: Node3D) -> float:
	var box := AABB()
	var first: bool = true
	for mesh: Node in node.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		var bounds: AABB = instance.global_transform * instance.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	return maxf(box.size.x, maxf(box.size.y, box.size.z))


func _all_layers(node: Node, layers: int) -> bool:
	for visual: Node in node.find_children("*", "VisualInstance3D", true, false):
		if (visual as VisualInstance3D).layers != layers:
			return false
	return true


func _all_shadows(node: Node) -> bool:
	for mesh: Node in node.find_children("*", "GeometryInstance3D", true, false):
		if (mesh as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + message)

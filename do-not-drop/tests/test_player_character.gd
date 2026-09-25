extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_player_character.gd
## The player's body is Astra's rounded character (2026-09-24), exported for
## the game by art/rounded_character/build_game_export.py. Guards what
## player.gd relies on from that GLB: the clips it plays, the bones the
## driver IK solves, the T-shirt as surface 0 (crew colour) plus its trim,
## a real player's height and facing, and the Sit clip while seated.
## Also the height-weighted pickup (player.gd _pickup_clip()): PickUpHigh
## takes a waist-high box without squatting, lasts as long as PickUpPackage,
## and a pickup plays a blend of both by where the hands meet the box.
## And steps while turning in place (player.gd movement_state()): the
## TurnInPlace clip lifts and re-plants each foot, and only a player standing
## on the floor and turning fast enough plays it -- not walking, not a slow
## turn, not over a one-shot.
## And the shorts' crotch rides with the thighs (model_fixes.py): its bottom
## carries thigh weight, or it hangs as a pointed fold between the knees in
## Sit. The deformation itself is measured by check_deformation.py.

const CHARACTER: String = "res://assets/models/characters/sm_char_player_rounded.glb"
const PlayerScript: GDScript = preload("res://scripts/gameplay/player/player.gd")

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var model: Node3D = (load(CHARACTER) as PackedScene).instantiate()
	root.add_child(model)
	await process_frame

	var anim: AnimationPlayer = _find(model, "AnimationPlayer") as AnimationPlayer
	_expect(anim != null, "The GLB carries an AnimationPlayer")
	if anim != null:
		for clip: String in ["Idle", "Walk", "Jump", "PickUpPackage", "PickUpHigh", "Sit", "TurnInPlace"]:
			_expect(anim.has_animation(clip), "Clip %s is exported" % clip)
		if anim.has_animation("Jump") and anim.has_animation("PickUpPackage"):
			# player.gd locks one-shots for 1.5 s / 1.55 s: the clips must outlast that.
			_expect(anim.get_animation("Jump").length >= 1.5, "Jump outlasts JUMP_ANIM_LOCK_MS")
			_expect(anim.get_animation("PickUpPackage").length >= 1.55, "PickUpPackage outlasts PICKUP_ANIM_LOCK_MS")
		if anim.has_animation("PickUpHigh") and anim.has_animation("PickUpPackage"):
			var lengths: Vector2 = Vector2(anim.get_animation("PickUpPackage").length, anim.get_animation("PickUpHigh").length)
			_expect(is_equal_approx(lengths.x, lengths.y), "PickUpHigh lasts as long as PickUpPackage, so they blend (got %s)" % lengths)

	var skeleton: Skeleton3D = _find(model, "Skeleton3D") as Skeleton3D
	_expect(skeleton != null, "The GLB carries a Skeleton3D")
	if skeleton != null:
		for bone: String in ["upper_arm.L", "hand.L", "upper_arm.R", "hand.R", "head", "grip.L", "grip.R"]:
			_expect(skeleton.find_bone(bone) >= 0, "Bone %s exists" % bone)
		var head: Vector3 = skeleton.to_global(skeleton.get_bone_global_rest(skeleton.find_bone("head")).origin)
		_expect(head.y > 1.0 and head.y < 1.4, "Neck/head joint sits at a player's height (got %.2f m)" % head.y)
		# The character's left hand is on its -X side when it faces Godot's -Z.
		var left: Vector3 = skeleton.to_global(skeleton.get_bone_global_rest(skeleton.find_bone("hand.L")).origin)
		_expect(left.x < -0.3, "Faces -Z like the rest of the game (left hand at x %.2f)" % left.x)
		_expect(skeleton.find_bone("pelvis") >= 0, "Bone pelvis exists")
		if anim != null and anim.has_animation("PickUpHigh") and skeleton.find_bone("pelvis") >= 0:
			_check_pickup_heights(anim, skeleton)
		if anim != null and anim.has_animation("TurnInPlace"):
			_check_turn_steps(anim, skeleton)

	var mesh: MeshInstance3D = _find(model, "MeshInstance3D") as MeshInstance3D
	_expect(mesh != null and mesh.mesh != null, "One skinned mesh")
	if mesh != null and mesh.mesh != null:
		var names: Array[String] = []
		var triangles: int = 0
		for surface: int in mesh.mesh.get_surface_count():
			var material: Material = mesh.mesh.surface_get_material(surface)
			names.append(material.resource_name if material != null else "")
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		_expect(names[0] == "Shirt", "Surface 0 is the T-shirt (got %s)" % names[0])
		_expect(names.has("ShirtTrim"), "The T-shirt trim is its own surface")
		_expect(triangles < 25000, "Game export stays decimated (%d triangles)" % triangles)
		if skeleton != null:
			_check_crotch_weights(mesh, skeleton)
	model.free()

	# In the player: crew colour on shirt and trim, every body mesh on the
	# right render layer, Sit while seated.
	var vehicle: Node = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
	var player: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	player.set_multiplayer_authority(1)
	root.add_child(vehicle)
	root.add_child(player)
	await process_frame
	var body_mesh: MeshInstance3D = _find(player.get_node(^"BodyVisual"), "MeshInstance3D") as MeshInstance3D
	var shirt := body_mesh.get_surface_override_material(0) as StandardMaterial3D
	_expect(shirt != null and shirt.albedo_color == Color("f4c562"), "Peer 1's shirt wears its crew colour")
	var trim_tinted: bool = false
	for surface: int in body_mesh.mesh.get_surface_count():
		var source: Material = body_mesh.mesh.surface_get_material(surface)
		if source != null and source.resource_name == "ShirtTrim":
			var trim := body_mesh.get_surface_override_material(surface) as StandardMaterial3D
			trim_tinted = trim != null and trim.albedo_color == Color("f4c562").darkened(0.18)
	_expect(trim_tinted, "The T-shirt trim follows the crew colour, a shade darker")
	_expect(_all_layers(player.get_node(^"BodyVisual"), 2), "Every body mesh of the local player is on LOCAL_BODY")

	var player_anim: AnimationPlayer = _find(player.get_node(^"BodyVisual"), "AnimationPlayer") as AnimationPlayer
	var seat: Node3D = vehicle.get_node(^"CabinInterior/DriverEyePoint")
	player.call(&"board_seat", seat.get_node(^"FirstPersonCamera").get_path(), seat.get_path())
	for _i: int in range(10):
		await physics_frame
	await process_frame
	_expect(player_anim.current_animation == "Sit", "Seated players play Sit (got %s)" % player_anim.current_animation)
	player.call(&"leave_seat")
	for _i: int in range(5):
		await physics_frame
	await process_frame
	_expect(player_anim.current_animation != "Sit", "Standing up leaves the Sit clip")

	# Height-weighted pickup: grip height above the feet -> PickUpHigh weight.
	for sample: Vector2 in [Vector2(0.2, 0.0), Vector2(PlayerScript.PICKUP_LOW_GRIP, 0.0),
			Vector2((PlayerScript.PICKUP_LOW_GRIP + PlayerScript.PICKUP_HIGH_GRIP) / 2.0, 0.5),
			Vector2(PlayerScript.PICKUP_HIGH_GRIP, 1.0), Vector2(1.5, 1.0)]:
		var weight: float = PlayerScript.pickup_high_weight_for(sample.x)
		_expect(is_equal_approx(weight, sample.y), "Grip at %.2f m weighs PickUpHigh %.2f (got %.2f)" % [sample.x, sample.y, weight])
	var package: Node3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	root.add_child(package)
	package.set(&"freeze", true)
	var feet: Vector3 = player.global_position
	package.global_position = feet + Vector3(0.0, package.call(&"get_half_extents").y, -0.6)
	var on_floor: float = player.call(&"pickup_high_weight_for_package", package)
	package.global_position = feet + Vector3(0.0, 0.8, -0.6)
	var on_shelf: float = player.call(&"pickup_high_weight_for_package", package)
	_expect(on_floor < 0.05, "A box on the floor squats all the way (PickUpHigh weight %.2f)" % on_floor)
	_expect(on_shelf > 0.95, "A box at the waist doesn't squat (PickUpHigh weight %.2f)" % on_shelf)
	package.free()
	# Weight -> clip: the authored clips at the ends, a baked blend between.
	for sample: Array in [[0.0, "PickUpPackage"], [1.0, "PickUpHigh"], [0.5, "pickup_blend/4"]]:
		player.set(&"pickup_high_weight", sample[0])
		var picked: String = String(player.call(&"_pickup_clip"))
		_expect(picked == sample[1], "Weight %.1f plays %s (got %s)" % [sample[0], sample[1], picked])
	player.call(&"_play_one_shot", &"PickUpPackage", 1550)
	await process_frame
	_expect(player_anim.current_animation == "pickup_blend/4",
		"A half-height pickup plays the blended clip (got %s)" % player_anim.current_animation)

	# Turning in place: standing and turning fast steps, walking or a slow
	# turn doesn't, and the hysteresis holds a turn that eases a little.
	for sample: Array in [
			[0.0, true, 3.0, false, "TurnInPlace", "standing, turning fast"],
			[3.6, true, 3.0, false, "Walk", "walking while turning"],
			[1.2, true, 3.0, false, "Walk", "strolling while turning"],
			[0.0, true, 0.4, false, "Idle", "standing, turning slowly"],
			[0.0, true, 0.0, false, "Idle", "standing still"],
			[0.0, false, 3.0, false, "Idle", "airborne, turning fast"],
			[0.0, true, 1.1, true, "TurnInPlace", "a turn easing off (hysteresis)"],
			[0.0, true, 1.1, false, "Idle", "that rate from standing still"]]:
		var state: String = String(PlayerScript.movement_state(sample[0], sample[1], sample[2], sample[3]))
		_expect(state == sample[4], "%s plays %s (got %s)" % [sample[5], sample[4], state])
	# The rate comes from the look yaw actually applied to the body.
	var tick: float = 1.0 / 60.0
	var start_yaw: float = player.rotation.y
	for _i: int in range(30):
		player.call(&"_apply_look", Vector2(0.05, 0.0))
		player.call(&"_measure_turn_rate", tick)
	var turned: float = absf(angle_difference(start_yaw, player.rotation.y)) / (30.0 * tick)
	var fast_rate: float = player.get(&"turn_rate")
	_expect(turned > PlayerScript.TURN_STEP_ABOVE and fast_rate > PlayerScript.TURN_STEP_ABOVE,
		"Looking around fast measures the body's turn (%.2f rad/s, body %.2f rad/s)" % [fast_rate, turned])
	for _i: int in range(60):
		player.call(&"_apply_look", Vector2(0.005, 0.0))
		player.call(&"_measure_turn_rate", tick)
	var slow_rate: float = player.get(&"turn_rate")
	_expect(slow_rate < PlayerScript.TURN_STEP_BELOW, "A slow look settles under the step rate (%.2f rad/s)" % slow_rate)
	# One-shots keep their lock: turning during a pickup doesn't cut it.
	player.call(&"_play_one_shot", &"PickUpPackage", 1550)
	player.call(&"_apply_look", Vector2(0.2, 0.0))
	player.call(&"_update_movement_anim", 0.0)
	_expect(player.get(&"anim_state") == &"PickUpPackage", "Turning doesn't interrupt a pickup (got %s)" % player.get(&"anim_state"))
	# anim_state carries it to every peer: TurnInPlace plays, seated still sits.
	player.set(&"_anim_lock_until_msec", 0)
	player.set(&"anim_state", &"TurnInPlace")
	await process_frame
	_expect(player_anim.current_animation == "TurnInPlace", "anim_state TurnInPlace plays the clip (got %s)" % player_anim.current_animation)
	_expect(player_anim.get_animation("TurnInPlace").loop_mode == Animation.LOOP_LINEAR, "TurnInPlace loops")

	player.free()
	vehicle.free()
	if _failures == 0:
		print("PASS: the rounded character carries its clips, bones, shirt colour and seated pose")
	quit(_failures)


## Pelvis and hands at the grab (0.45 s): the floor clip squats, the high
## one doesn't and reaches higher; a 50% blend lands halfway.
func _check_pickup_heights(anim: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var library := AnimationLibrary.new()
	library.add_animation(&"half", PlayerScript.blend_clips(anim.get_animation("PickUpPackage"), anim.get_animation("PickUpHigh"), 0.5))
	anim.add_animation_library(&"test", library)
	var rest: float = _bone_height(anim, skeleton, "PickUpPackage", 0.0, "pelvis")
	var low: float = _bone_height(anim, skeleton, "PickUpPackage", 0.45, "pelvis")
	var high: float = _bone_height(anim, skeleton, "PickUpHigh", 0.45, "pelvis")
	var half: float = _bone_height(anim, skeleton, "test/half", 0.45, "pelvis")
	_expect(rest - low > 0.15, "PickUpPackage squats to the floor (pelvis drops %.2f m)" % (rest - low))
	_expect(rest - high < 0.06, "PickUpHigh doesn't squat (pelvis drops %.2f m)" % (rest - high))
	_expect(absf(half - (low + high) / 2.0) < 0.02, "A 50%% blend squats halfway (pelvis %.3f, ends %.3f / %.3f)" % [half, low, high])
	var hand_low: float = _bone_height(anim, skeleton, "PickUpPackage", 0.45, "hand.L")
	var hand_high: float = _bone_height(anim, skeleton, "PickUpHigh", 0.45, "hand.L")
	_expect(hand_high - hand_low > 0.3, "PickUpHigh grabs higher, at the waist (hands %.2f vs %.2f m)" % [hand_high, hand_low])
	anim.remove_animation_library(&"test")


## TurnInPlace: slower than Walk, each foot lifts clearly and sets back down
## where it stood, and one foot is always on the floor.
func _check_turn_steps(anim: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var length: float = anim.get_animation("TurnInPlace").length
	_expect(length > anim.get_animation("Walk").length * 2.0, "TurnInPlace steps slower than Walk (%.2f s loop)" % length)
	var rest: Dictionary = {}
	for side: String in ["L", "R"]:
		rest[side] = _bone_height(anim, skeleton, "Idle", 0.0, "foot." + side)
	var top: Dictionary = {"L": 0.0, "R": 0.0}
	var planted: Dictionary = {"L": 0, "R": 0}
	var airborne: int = 0
	var samples: int = 48
	for i: int in samples + 1:
		var t: float = length * i / samples
		var up: Dictionary = {}
		for side: String in ["L", "R"]:
			up[side] = _bone_height(anim, skeleton, "TurnInPlace", t, "foot." + side) - rest[side]
			top[side] = maxf(top[side], up[side])
			if absf(up[side]) < 0.01:
				planted[side] += 1
		if up["L"] > 0.01 and up["R"] > 0.01:
			airborne += 1
	for side: String in ["L", "R"]:
		_expect(top[side] > 0.04, "TurnInPlace lifts foot.%s (%.3f m)" % [side, top[side]])
		_expect(planted[side] > samples / 3, "TurnInPlace sets foot.%s back down (%d of %d samples)" % [side, planted[side], samples + 1])
		var start: float = _bone_height(anim, skeleton, "TurnInPlace", 0.0, "foot." + side) - rest[side]
		_expect(absf(start) < 0.005, "TurnInPlace starts with foot.%s where Idle has it (%.4f m)" % [side, start])
	_expect(airborne == 0, "TurnInPlace always keeps a foot on the floor (%d samples with both up)" % airborne)


## Midline vertices at the bottom of the shorts' crotch: before model_fixes.py
## split them between both thighs they were all pelvis (thigh share ~0).
func _check_crotch_weights(mesh: MeshInstance3D, skeleton: Skeleton3D) -> void:
	var surface: int = -1
	for i: int in mesh.mesh.get_surface_count():
		var material: Material = mesh.mesh.surface_get_material(i)
		if material != null and material.resource_name == "Shorts":
			surface = i
	_expect(surface >= 0, "The shorts are their own surface")
	if surface < 0 or mesh.skin == null:
		return
	var thighs: Array[int] = []
	for bind: int in mesh.skin.get_bind_count():
		var bone_name: String = String(mesh.skin.get_bind_name(bind))
		if bone_name.is_empty():
			bone_name = skeleton.get_bone_name(mesh.skin.get_bind_bone(bind))
		if bone_name in ["thigh.L", "thigh.R"]:
			thighs.append(bind)
	var arrays: Array = mesh.mesh.surface_get_arrays(surface)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride: int = bones.size() / points.size()
	var min_x: float = INF
	var max_x: float = -INF
	for point: Vector3 in points:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
	var mid_x: float = (min_x + max_x) / 2.0
	var bottom: float = INF
	for point: Vector3 in points:
		if absf(point.x - mid_x) < 0.015:
			bottom = minf(bottom, point.y)
	var share: float = 0.0
	var count: int = 0
	for i: int in points.size():
		if absf(points[i].x - mid_x) < 0.015 and points[i].y < bottom + 0.03:
			for k: int in stride:
				if bones[i * stride + k] in thighs:
					share += weights[i * stride + k]
			count += 1
	share /= maxf(count, 1)
	_expect(count > 0 and share > 0.5,
		"The shorts' crotch bottom rides with the thighs (thigh weight %.2f over %d vertices)" % [share, count])


func _bone_height(anim: AnimationPlayer, skeleton: Skeleton3D, clip: String, time: float, bone: String) -> float:
	anim.play(clip)
	anim.seek(time, true)
	return skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin).y


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child: Node in node.get_children():
		var found: Node = _find(child, type_name)
		if found != null:
			return found
	return null


func _all_layers(node: Node, layers: int) -> bool:
	if node is VisualInstance3D and (node as VisualInstance3D).layers != layers:
		return false
	for child: Node in node.get_children():
		if not _all_layers(child, layers):
			return false
	return true


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

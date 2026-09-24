extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_player_character.gd
## The player's body is Astra's rounded character (2026-09-24), exported for
## the game by art/rounded_character/build_game_export.py. Guards what
## player.gd relies on from that GLB: the clips it plays, the bones the
## driver IK solves, the T-shirt as surface 0 (crew colour) plus its trim,
## a real player's height and facing, and the Sit clip while seated.

const CHARACTER: String = "res://assets/models/characters/sm_char_player_rounded.glb"

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var model: Node3D = (load(CHARACTER) as PackedScene).instantiate()
	root.add_child(model)
	await process_frame

	var anim: AnimationPlayer = _find(model, "AnimationPlayer") as AnimationPlayer
	_expect(anim != null, "The GLB carries an AnimationPlayer")
	if anim != null:
		for clip: String in ["Idle", "Walk", "Jump", "PickUpPackage", "Sit"]:
			_expect(anim.has_animation(clip), "Clip %s is exported" % clip)
		if anim.has_animation("Jump") and anim.has_animation("PickUpPackage"):
			# player.gd locks one-shots for 1.5 s / 1.55 s: the clips must outlast that.
			_expect(anim.get_animation("Jump").length >= 1.5, "Jump outlasts JUMP_ANIM_LOCK_MS")
			_expect(anim.get_animation("PickUpPackage").length >= 1.55, "PickUpPackage outlasts PICKUP_ANIM_LOCK_MS")

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

	player.free()
	vehicle.free()
	if _failures == 0:
		print("PASS: the rounded character carries its clips, bones, shirt colour and seated pose")
	quit(_failures)


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

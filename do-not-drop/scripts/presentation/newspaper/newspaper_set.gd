class_name NewspaperSet
extends Node3D
## The next-day scene's set (N-606.3): the Boss's office in the morning, the
## Boss seated with his paper up, and nothing else. It lives in its own World3D
## (NewspaperDirector's SubViewport), so it doesn't care where the truck ended,
## the hour or the weather. Built by code from the game's own pieces, as the
## N-606.6 study settled it: the depot kit's desk, lamp, blinds, clock and cork
## board; the rounded body (as it is: S-311) in a light-blue office shirt with a
## moustache, so he isn't one of the crew; four sheets of newsprint with a
## centre fold, held by the lower corners, the outer corners drooping.
##
## The director moves the camera; this only knows where the paper is
## (paper_point(), paper_up(), paper_normal()) and how the Boss holds it
## (set_lowered() from reading to looking at the crew, set_reaction()).

const KIT = preload("res://scripts/gameplay/depot/depot_kit.gd")
const APPEARANCE = preload("res://scripts/gameplay/player/player_appearance.gd")
const FACE = preload("res://scripts/presentation/character_face.gd")
const STOCK_SHADER = preload("res://scripts/presentation/newspaper/newspaper_stock.gdshader")
const CHIEF_MODEL: String = "res://assets/models/characters/sm_char_player_rounded.glb"
const THERMOS_MODEL: String = "res://assets/models/props/cargo/sm_prop_cargo_thermos.glb"
const SHIRT: Color = Color("7fa6c9")
const MOUSTACHE: Color = Color("4a2a17")
const CHIEF_SEAT: Vector3 = Vector3(0, 0.48, 0.57)
## Where the paper is while he reads, and once lowered to look at the crew.
const PAPER_READING: Vector3 = Vector3(0, 1.18, -0.12)
const PAPER_READING_TILT: Vector3 = Vector3(-60, 0, -1)
const PAPER_LOWERED: Vector3 = Vector3(0, 0.87, -0.12)
const PAPER_LOWERED_TILT: Vector3 = Vector3(-62, 0, -1)
## A sheet's size in metres (one spread across, folded in the middle).
const SHEET_WIDTH: float = 0.94
const SHEET_HEIGHT: float = 0.66
const SHEETS: int = 4

var chief: Node3D
var face: Node3D
var skeleton: Skeleton3D
var paper: Node3D
var lowered: float = 0.0
var _grip_targets: Array[Marker3D] = []
var _head_bone: int = -1
var _head_rest: Quaternion
var _head_reading: Quaternion
var _leaves: Array[MeshInstance3D] = []
var _clock: float = 0.0


func _init() -> void:
	name = "NewspaperSet"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Builds the office, the light, the Boss and the paper with these prints:
## `inner` faces him, `outer` faces the room.
func build(inner: Texture2D, outer: Texture2D) -> void:
	_build_room()
	_build_lights()
	_build_chief()
	_build_paper(inner, outer)
	_build_grip()
	set_lowered(0.0)


## Puts new prints on the paper (once the pages are drawn and baked).
func set_prints(inner: Texture2D, outer: Texture2D) -> void:
	for index: int in _leaves.size():
		var reverse: bool = index % 2 == 1
		var material: ShaderMaterial = _leaves[index].material_override
		material.set_shader_parameter("page_texture", outer if reverse else inner)
		material.set_shader_parameter("reverse_texture", inner if reverse else outer)


## 0 reading (paper up, head bent over it), 1 lowered (he looks at the crew).
func set_lowered(amount: float) -> void:
	lowered = clampf(amount, 0.0, 1.0)
	var t: float = smoothstep(0.0, 1.0, lowered)
	paper.position = PAPER_READING.lerp(PAPER_LOWERED, t)
	paper.rotation_degrees = PAPER_READING_TILT.lerp(PAPER_LOWERED_TILT, t)
	if skeleton != null and _head_bone >= 0:
		skeleton.set_bone_pose_rotation(_head_bone, _head_reading.slerp(_head_rest, t))
	_place_grip()


func set_reaction(eyes: StringName, mouth: StringName) -> void:
	if face != null:
		face.call(&"set_expression", eyes, mouth)


## Breathing and the paper settling in his hands; the face blinks on its own.
func _process(delta: float) -> void:
	_clock += delta
	if chief != null:
		chief.position.y = CHIEF_SEAT.y + sin(_clock * 1.65) * 0.0025
	if paper != null and lowered <= 0.0:
		paper.position.y = PAPER_READING.y + sin(_clock * 1.65) * 0.002
		paper.rotation_degrees.z = PAPER_READING_TILT.z + sin(_clock) * 0.2
		_place_grip()


## A point of the inner spread (uv 0..1 across both pages) in world space.
func paper_point(uv: Vector2) -> Vector3:
	return paper.to_global(sheet_vertex(uv))


## The way that is up on the page, and the way out of it toward the reader.
func paper_up() -> Vector3:
	return paper.global_basis.y.normalized()


func paper_normal() -> Vector3:
	return paper.global_basis.z.normalized()


func paper_right() -> Vector3:
	return paper.global_basis.x.normalized()


## The sheet's shape: a shallow V at the fold, curled edges, a little ripple,
## and the outer corners drooping because he holds it only by the bottom.
static func sheet_vertex(uv: Vector2, sheet: int = 0) -> Vector3:
	var x: float = (uv.x - 0.5) * (SHEET_WIDTH + sheet * 0.0017)
	var fold: float = absf(x) * 0.15
	var curl: float = pow(absf(x) / 0.47, 3.0) * 0.011 * sin(uv.y * PI)
	var ripple: float = sin(uv.x * 21.0 + uv.y * 11.0) * 0.0012
	var cross_fold: float = exp(-absf(uv.y - 0.51) * 65.0) * 0.0015
	var reach: float = minf(absf(x) / 0.47, 1.0)
	var unheld: float = maxf(0.0, 1.0 - uv.y)
	var droop: float = -0.1 * reach * reach * unheld * unheld
	var belly: float = -0.006 * sin(reach * PI) * sin(clampf(uv.y, 0.0, 1.0) * PI)
	return Vector3(x, (0.5 - uv.y) * (SHEET_HEIGHT + sheet * 0.0014),
			fold + curl + ripple + cross_fold + droop + belly - sheet * 0.0006)


func _build_room() -> void:
	var kit := KIT.new(self)
	var steel: StandardMaterial3D = KIT.flat(Color("263238"), 0.68, 0.15)
	var plaster: StandardMaterial3D = KIT.flat(Color("b8c4ba"), 0.94)
	var wood: StandardMaterial3D = KIT.detailed(Color("b08a5a"), "wood_planks", 1.0)
	var blue: StandardMaterial3D = KIT.flat(Color("2f5d8a"))
	var yellow: StandardMaterial3D = KIT.flat(UiTheme.YELLOW)
	kit.box(Vector3(6.2, 0.12, 5.0), Vector3(0, -0.06, 0), KIT.flat(Color("737a74")))
	kit.box(Vector3(6.2, 3.1, 0.12), Vector3(0, 1.55, 2.12), plaster)
	kit.box(Vector3(0.12, 3.1, 4.4), Vector3(3.06, 1.55, 0), plaster)
	kit.box(Vector3(6.1, 0.06, 0.04), Vector3(0, 1.02, 2.04), steel)
	kit.box(Vector3(6.1, 0.12, 0.04), Vector3(0, 0.08, 2.04), steel)
	# The window wall: dark mullions and half-drawn blinds, like the mezzanine.
	kit.box(Vector3(0.12, 0.9, 4.4), Vector3(-3.06, 0.45, 0), plaster)
	kit.box(Vector3(0.12, 0.42, 4.4), Vector3(-3.06, 2.89, 0), plaster)
	var window_material: StandardMaterial3D = KIT.flat(Color("667d7e"), 0.9)
	kit.box(Vector3(0.03, 1.75, 4.35), Vector3(-3.08, 1.8, 0), window_material)
	kit.shadowless(window_material)
	for z: float in [-2.1, -0.65, 0.75, 2.1]:
		kit.box(Vector3(0.14, 1.8, 0.08), Vector3(-3.0, 1.8, z), steel)
	for y: float in [1.0, 2.65]:
		kit.box(Vector3(0.14, 0.08, 4.4), Vector3(-3.0, y, 0), steel)
	_model("sm_env_depot_office_blind", Vector3(-2.98, 1.45, -0.85), -PI / 2.0)
	_model("sm_env_depot_office_blind", Vector3(-2.98, 1.45, 0.42), -PI / 2.0)
	# The depot's own desk, cleared in the middle for the paper and the mate.
	var desk: Node3D = _model("sm_env_depot_dispatch_desk", Vector3(0.0, 0, -0.26), PI)
	if desk != null:
		desk.scale = Vector3(1.65, 1, 1.25)
		var cleared: Array[StringName] = [&"Keyboard", &"Keys", &"Mouse", &"Cradle", &"Mug", &"MugCoffee", &"Clip",
				&"Clipboard", &"ClipSheet"]
		for part: Node in desk.find_children("*", "MeshInstance3D", true, false):
			var part_name: String = String(part.name)
			if part_name.begins_with("Monitor") or part_name.begins_with("Screen") or part_name.begins_with("Scanner") \
					or part.name in cleared:
				(part as Node3D).hide()
	_model("sm_env_depot_desk_lamp", Vector3(-0.95, 0.765, -0.1), -0.2)
	_model("sm_env_depot_cork_board", Vector3(1.62, 0.15, 2.04))
	for index: int in 3:
		kit.box(Vector3(0.17, 0.22, 0.012), Vector3(1.36 + index * 0.26, 1.63 + (index % 2) * 0.08, 2.008),
				KIT.flat(UiTheme.PAPER))
		for row: int in 3:
			kit.box(Vector3(0.10 - row * 0.014, 0.006, 0.002),
					Vector3(1.36 + index * 0.26, 1.66 + (index % 2) * 0.08 - row * 0.035, 1.999), steel)
	var clock: Node3D = _model("sm_env_depot_wall_clock", Vector3(-1.58, 2.16, 2.005), PI)
	if clock != null:
		clock.scale = Vector3.ONE * 0.36
	for hand: Array in [["sm_env_depot_clock_hand_hour", 1.982, -0.65], ["sm_env_depot_clock_hand_minute", 1.98, 1.1]]:
		var piece: Node3D = _model(hand[0], Vector3(-1.58, 2.16, hand[1]), PI)
		if piece != null:
			piece.scale = Vector3.ONE * 0.36
			piece.rotation.z = hand[2]
	# Filing cabinet and chair, in the depot's blue and yellow.
	kit.box(Vector3(0.68, 1.06, 0.65), Vector3(2.29, 0.53, 1.59), blue)
	for index: int in 3:
		kit.box(Vector3(0.61, 0.29, 0.028), Vector3(2.29, 0.18 + index * 0.33, 1.25), steel)
		kit.box(Vector3(0.17, 0.026, 0.04), Vector3(2.29, 0.27 + index * 0.33, 1.22), yellow)
	kit.box(Vector3(0.5, 0.08, 0.5), Vector3(0, 0.5, 0.6), steel)
	kit.box(Vector3(0.52, 0.58, 0.1), Vector3(0, 0.9, 0.95), blue)
	for x: float in [-0.22, 0.22]:
		kit.box(Vector3(0.045, 0.45, 0.045), Vector3(x, 0.23, 0.6), steel)
	# The mate and the thermos, at hand and clear of the paper.
	kit.cylinder(0.067, 0.105, Transform3D(Basis.IDENTITY, Vector3(0.89, 0.827, -0.58)), wood)
	kit.cylinder(0.05, 0.01, Transform3D(Basis.IDENTITY, Vector3(0.89, 0.882, -0.58)), KIT.flat(Color("455038")))
	kit.cylinder(0.007, 0.19, Transform3D(Basis(Vector3.FORWARD, -0.2), Vector3(0.92, 0.96, -0.58)),
			KIT.flat(Color("adb6b5"), 0.3, 0.7), 8)
	if ResourceLoader.exists(THERMOS_MODEL):
		var thermos: Node3D = (load(THERMOS_MODEL) as PackedScene).instantiate()
		add_child(thermos)
		thermos.position = Vector3(1.08, 0.77, -0.05)
		thermos.scale = Vector3.ONE * 0.7
	# A document tray and a pen: a desk that is worked at.
	kit.box(Vector3(0.37, 0.012, 0.26), Vector3(-1.10, 0.786, -0.50), blue)
	for x: float in [-1.28, -0.92]:
		kit.box(Vector3(0.012, 0.05, 0.26), Vector3(x, 0.811, -0.50), blue)
	for z: float in [-0.625, -0.375]:
		kit.box(Vector3(0.37, 0.05, 0.012), Vector3(-1.10, 0.811, z), blue)
	for sheet: int in 3:
		kit.box(Vector3(0.29, 0.002, 0.21), Vector3(-1.10 + sheet * 0.003, 0.80 + sheet * 0.003, -0.5),
				KIT.flat(Color("dedbd0")))
	kit.cylinder(0.006, 0.19, Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(-0.82, 0.789, -0.51)), steel, 8)
	kit.contact(Vector3(0, 0.006, -0.26), Vector2(2.8, 1.5))
	kit.contact(Vector3(0, 0.008, 0.6), Vector2(0.8, 0.8))
	kit.commit("Office")


## Warm morning light from the window, a cool fill and the desk lamp. No fog,
## no sky: a set, lit like one.
func _build_lights() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("303a3c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b5c4ca")
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -135, 0)
	sun.light_color = Color("ffdcb0")
	sun.light_energy = 0.40
	add_child(sun)
	var key := SpotLight3D.new()
	add_child(key)
	key.position = Vector3(-1.65, 2.75, -1.6)
	key.look_at_from_position(key.position, Vector3(0, 1.04, 0.05))
	key.spot_range = 5.2
	key.spot_angle = 65
	key.light_color = Color("ffdcb0")
	key.light_energy = 0.24
	key.shadow_enabled = true
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.5, 2.45, -1.6)
	fill.omni_range = 5.0
	fill.light_color = Color("c6d5df")
	fill.light_energy = 0.2
	add_child(fill)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-0.93, 1.11, -0.27)
	lamp.omni_range = 1.3
	lamp.light_color = Color("ffe2b8")
	lamp.light_energy = 0.26
	add_child(lamp)


func _build_chief() -> void:
	chief = (load(CHIEF_MODEL) as PackedScene).instantiate()
	chief.name = "Boss"
	add_child(chief)
	chief.position = CHIEF_SEAT
	APPEARANCE.tint_shirt(chief, SHIRT)
	skeleton = APPEARANCE.find_skeleton(chief)
	if skeleton == null:
		return
	face = FACE.new()
	face.call(&"setup", chief, skeleton, 1)
	face.call(&"set_expression", &"sleepy", &"smile")
	_add_moustache()
	var animation: AnimationPlayer = APPEARANCE.find_animation_player(chief)
	if animation != null and animation.has_animation(&"Sit"):
		animation.play(&"Sit")
		animation.seek(0.8, true)
		animation.advance(0)
		animation.pause()
	_head_bone = skeleton.find_bone("head")
	if _head_bone < 0:
		return
	_head_rest = skeleton.get_bone_pose_rotation(_head_bone)
	var parent_pose: Transform3D = skeleton.get_bone_global_pose(skeleton.get_bone_parent(_head_bone))
	var tilt_axis: Vector3 = (skeleton.global_basis * parent_pose.basis).inverse() * Vector3.RIGHT
	_head_reading = Quaternion(tilt_axis.normalized(), -0.22) * _head_rest


## Two flattened capsules under the nose, on the head bone so they follow
## every tilt, placed with the face patch's own head shape.
func _add_moustache() -> void:
	var attach := BoneAttachment3D.new()
	attach.name = "Moustache"
	attach.bone_name = "head"
	skeleton.add_child(attach)
	var bone: int = skeleton.find_bone("head")
	var head_rest: Transform3D = chief.global_transform.affine_inverse() * skeleton.global_transform \
			* skeleton.get_bone_global_rest(bone)
	var to_bone: Transform3D = head_rest.affine_inverse()
	var hair: StandardMaterial3D = KIT.flat(MOUSTACHE, 0.9)
	for side: float in [-1.0, 1.0]:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.026
		capsule.height = 0.14
		var tuft := MeshInstance3D.new()
		tuft.mesh = capsule
		tuft.material_override = hair
		attach.add_child(tuft)
		var anchor: Vector3 = FACE._patch_point(Vector2(0.5 - side * 0.055, 0.64))
		var lie := Basis(Vector3.BACK, side * (PI / 2.0 - 0.38)) * Basis.from_scale(Vector3(1.0, 1.0, 0.55))
		tuft.transform = to_bone * Transform3D(lie, anchor + Vector3(0, 0, -0.012))


func _build_paper(inner: Texture2D, outer: Texture2D) -> void:
	paper = Node3D.new()
	paper.name = "Paper"
	add_child(paper)
	paper.position = PAPER_READING
	paper.rotation_degrees = PAPER_READING_TILT
	# Nested sheets, each with a front and a back; staggered lower edges show
	# the stack in profile.
	for sheet: int in SHEETS:
		for reverse: bool in [false, true]:
			var leaf := MeshInstance3D.new()
			leaf.mesh = _folded_sheet(sheet, reverse)
			var material := ShaderMaterial.new()
			material.shader = STOCK_SHADER
			material.set_shader_parameter("sheet_tint", 1.0 - sheet * 0.012)
			material.set_shader_parameter("self_light", 0.5)
			leaf.material_override = material
			paper.add_child(leaf)
			_leaves.append(leaf)
	set_prints(inner, outer)


func _folded_sheet(sheet: int, reverse: bool) -> ArrayMesh:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for strip: int in 32:
		for row: int in 24:
			var uv00 := Vector2(float(strip) / 32.0, float(row) / 24.0)
			var uv11 := Vector2(float(strip + 1) / 32.0, float(row + 1) / 24.0)
			var uv01 := Vector2(uv00.x, uv11.y)
			var uv10 := Vector2(uv11.x, uv00.y)
			var triangles: Array[Vector2] = [uv00, uv10, uv01, uv10, uv11, uv01]
			if reverse:
				triangles.reverse()
			for uv: Vector2 in triangles:
				mesh.set_uv(Vector2(1.0 - uv.x, uv.y) if reverse else uv)
				var vertex: Vector3 = sheet_vertex(uv, sheet)
				vertex.z -= 0.0003 if reverse else 0.0
				mesh.add_vertex(vertex)
	mesh.generate_normals()
	return mesh.commit()


## The hands close on the lower outer corners, just past the print.
func _build_grip() -> void:
	if skeleton == null:
		return
	for side: String in ["L", "R"]:
		var bone: int = skeleton.find_bone("hand." + side)
		if bone < 0 or skeleton.find_bone("upper_arm." + side) < 0:
			continue
		var target := Marker3D.new()
		target.name = "Grip" + side
		add_child(target)
		target.set_meta(&"side", -1.0 if side == "L" else 1.0)
		target.global_basis = (skeleton.global_basis * skeleton.get_bone_global_pose(bone).basis).orthonormalized()
		_grip_targets.append(target)
		var solver := SkeletonIK3D.new()
		solver.root_bone = "upper_arm." + side
		solver.tip_bone = "hand." + side
		solver.override_tip_basis = true
		skeleton.add_child(solver)
		solver.target_node = solver.get_path_to(target)
		solver.start(false)


func _place_grip() -> void:
	for target: Marker3D in _grip_targets:
		var side: float = float(target.get_meta(&"side", 1.0))
		target.global_position = paper.to_global(sheet_vertex(Vector2(-0.035 if side < 0.0 else 1.035, 1.08)))


func _model(asset: String, at: Vector3, yaw: float = 0.0) -> Node3D:
	var path: String = KIT.depot_model(asset)
	if not ResourceLoader.exists(path):
		return null
	var prop: Node3D = (load(path) as PackedScene).instantiate()
	add_child(prop)
	prop.position = at
	prop.rotation.y = yaw
	return prop

extends Node3D
class_name DoorReaction
## What the neighbour does at the door (tareas de Nacho N-604), on every peer:
## DeliveryHouse calls react() from the record the host relays to everyone
## (house_delivery_recorded / house_refused_package), so a client sees the
## same scene as the host -- and the same line, chosen from the session seed.
##
##   delivered_ok       happy: a hop, "¡Justo lo que esperaba!"
##   delivered_at_risk  suspicious: lifts the box to look it over
##   delivered_ruined   opens it and grabs their head in both hands
##   wrong              a box that isn't theirs: shakes their head, hands it
##                      back and goes in again (the house keeps waiting)
##   missed             nobody home: a note stuck to the door
##
## The lines themselves live in DeliveryHouse.REACTION_LINES (five per
## outcome); a speech bubble shows the one picked for BUBBLE_SECONDS.

const BUBBLE_SECONDS: float = 6.0
const WRONG_SECONDS: float = 4.0
const BUBBLE_HEIGHT: float = 2.35
const BUBBLE_FONT: Font = preload("res://assets/fonts/Nunito-Variable.ttf")
const NOTE_FONT: Font = preload("res://assets/fonts/Nunito-Variable.ttf")
const INK := Color("1e2235")
const PAPER := Color("fbf8ee")
## Where each hand grabs, from the head bone (x: to either side, z: forward),
## in the resident's own space.
const HEAD_GRAB := Vector3(0.13, 0.12, 0.06)

var resident: Node3D
var house_index: int = 0
## Where the "nobody home" note goes: on the door, in this node's parent space.
var door_point: Vector3 = Vector3(0.0, 1.3, -2.3)
var bubble: Label3D
var note: Label3D
var last_line: String = ""
var last_action: StringName = &""
var _bubble_back: MeshInstance3D
var _animation: AnimationPlayer
var _skeleton: Skeleton3D
var _head_ik: Array[SkeletonIK3D] = []
var _head_targets: Array[Marker3D] = []
var _hide_timer: SceneTreeTimer


func setup(resident_node: Node3D, index: int, door_at: Vector3) -> void:
	resident = resident_node
	house_index = index
	door_point = door_at
	_animation = resident.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = resident.find_child("Skeleton3D", true, false) as Skeleton3D
	_build_bubble()


## Picks the line for this house and outcome: same seed, same line on every
## peer; a different house or outcome, a different pick.
static func pick_line(lines: Array, session_seed: int, index: int, outcome: StringName) -> String:
	if lines.is_empty():
		return ""
	return str(lines[posmod(hash([session_seed, index, outcome]), lines.size())])


func react(outcome: StringName, line: String) -> void:
	last_line = line
	match outcome:
		&"missed":
			_leave_note(line)
			return
		&"delivered_ok":
			_play(&"Jump", &"Idle")
			last_action = &"happy"
		&"delivered_at_risk":
			_play(&"PickUpPackage", &"Idle")
			last_action = &"inspect"
		&"delivered_ruined":
			_play(&"Idle", &"")
			_grab_head()
			last_action = &"grab_head"
		_:
			_play(&"Idle", &"")
			last_action = &"idle"
	resident.visible = true
	_say(line, BUBBLE_SECONDS)


## Not their box: out they come, shake their head, back inside.
func refuse(line: String) -> void:
	last_line = line
	last_action = &"shake_head"
	resident.visible = true
	_play(&"Idle", &"")
	var tween: Tween = resident.create_tween()
	var base_yaw: float = resident.rotation.y
	for swing: float in [0.35, -0.35, 0.3, -0.3, 0.0]:
		tween.tween_property(resident, ^"rotation:y", base_yaw + swing, 0.16)
	_say(line, WRONG_SECONDS)
	var timer: SceneTreeTimer = get_tree().create_timer(WRONG_SECONDS)
	timer.timeout.connect(func() -> void:
		# Unless the delivery went through in the meantime.
		if last_action == &"shake_head" and is_instance_valid(resident):
			resident.visible = false)


func _play(clip: StringName, then: StringName) -> void:
	if _animation == null:
		return
	var found: StringName = _find_clip(clip)
	if found == &"":
		return
	_animation.play(found)
	if then != &"":
		var next: StringName = _find_clip(then)
		if next != &"":
			_animation.queue(next)


## Clip names in the import can carry a library prefix or a suffix.
func _find_clip(clip: StringName) -> StringName:
	for name: StringName in _animation.get_animation_list():
		if String(name) == String(clip) or String(name).ends_with("/" + String(clip)) or String(name).begins_with(String(clip)):
			return name
	return &""


## Both hands to the head: an IK chain per arm, from the upper arm to the
## hand, reaching for a point either side of the face.
func _grab_head() -> void:
	if _skeleton == null or not _head_ik.is_empty():
		return
	var head_bone: int = _skeleton.find_bone("Head")
	if head_bone < 0:
		return
	# The head as modelled (its rest pose), not wherever the clip has it now.
	var head: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_rest(head_bone).origin
	for side: String in ["L", "R"]:
		if _skeleton.find_bone("Hand_" + side) < 0 or _skeleton.find_bone("UpperArm_" + side) < 0:
			continue
		var target := Marker3D.new()
		target.name = "HeadGrab" + side
		# The model faces +Z; its left arm (UpperArm_L / Hand_L) rests at -X.
		var offset := Vector3(HEAD_GRAB.x * (-1.0 if side == "L" else 1.0), HEAD_GRAB.y, HEAD_GRAB.z)
		resident.add_child(target)
		target.global_position = head + resident.global_basis.orthonormalized() * offset
		_head_targets.append(target)
		var solver := SkeletonIK3D.new()
		solver.name = "HeadGrabIK" + side
		solver.root_bone = "UpperArm_" + side
		solver.tip_bone = "Hand_" + side
		solver.influence = 1.0
		_skeleton.add_child(solver)
		solver.target_node = target.get_path()
		solver.start()
		_head_ik.append(solver)


func _say(line: String, seconds: float) -> void:
	bubble.text = line
	bubble.visible = not line.is_empty()
	_bubble_back.visible = bubble.visible
	_fit_back()
	_hide_timer = get_tree().create_timer(seconds)
	var timer: SceneTreeTimer = _hide_timer
	timer.timeout.connect(func() -> void:
		if _hide_timer == timer:
			bubble.visible = false
			_bubble_back.visible = false)


func _leave_note(line: String) -> void:
	last_action = &"note"
	if note == null:
		var paper := MeshInstance3D.new()
		paper.name = "NotePaper"
		var quad := QuadMesh.new()
		quad.size = Vector2(0.34, 0.26)
		var material := StandardMaterial3D.new()
		material.albedo_color = PAPER
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad.material = material
		paper.mesh = quad
		paper.position = door_point
		paper.rotation = Vector3(0.0, PI, deg_to_rad(4.0))
		get_parent().add_child(paper)
		note = Label3D.new()
		note.name = "DoorNote"
		note.font = NOTE_FONT
		note.font_size = 28
		note.pixel_size = 0.001
		note.modulate = INK
		note.outline_size = 0
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.width = 300
		note.position = door_point + Vector3(0.0, 0.0, -0.005)
		note.rotation = Vector3(0.0, PI, deg_to_rad(4.0))
		get_parent().add_child(note)
	note.text = line


func _build_bubble() -> void:
	_bubble_back = MeshInstance3D.new()
	_bubble_back.name = "BubbleBack"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = PAPER
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.render_priority = -1
	quad.material = material
	_bubble_back.mesh = quad
	_bubble_back.visible = false
	add_child(_bubble_back)
	bubble = Label3D.new()
	bubble.name = "SpeechBubble"
	bubble.font = BUBBLE_FONT
	bubble.font_size = 40
	bubble.pixel_size = 0.0035
	bubble.modulate = INK
	bubble.outline_size = 0
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = false
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.width = 420
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.visible = false
	add_child(bubble)
	var at: Vector3 = resident.position + Vector3(0.0, BUBBLE_HEIGHT, 0.0)
	bubble.position = at
	_bubble_back.position = at


## The paper behind the text grows with the line (wrapping at `width`).
func _fit_back() -> void:
	var lines: int = maxi(1, ceili(float(bubble.text.length()) / 24.0))
	(_bubble_back.mesh as QuadMesh).size = Vector2(minf(1.6, 0.12 + bubble.text.length() * 0.055), 0.2 + lines * 0.16)

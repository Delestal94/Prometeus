extends Node3D
## S-304: the phone in the gel character's right hand while its owner has the
## phone camera open. Pure presentation, drawn by every peer from the owner's
## replicated `phone_raised`: the owner's own body sits on RenderLayers.LOCAL_BODY
## and is culled from their first-person view, so this is how the rest of the
## crew sees someone taking a photo.
##
## The right arm is lifted with a SkeletonIK3D on upper_arm.R..hand.R (the
## driver's and the package carrier's approach) toward a point in front of the
## cheek, and the phone hangs from a BoneAttachment3D on hand.R with its screen
## turned back toward the eyes. The phone and the arm are put away the moment
## the player sits, carries a box, plays an emote or is knocked over: those own
## the arms (or the whole rig) and would only fight it.

## The refined phone: 7.2 x 14.2 x 0.9 cm, centred on its origin, screen toward
## -Z and the camera lenses at the back (tools/generate_lowpoly_assets.py phone()).
const PHONE_SCENE: PackedScene = preload("res://assets/models/props/handheld/sm_prop_phone_refined.glb")
const SHOULDER_BONE: StringName = &"upper_arm.R"
const ELBOW_BONE: StringName = &"forearm.R"
const HAND_BONE: StringName = &"hand.R"
## Seconds-per-second of the lift: the arm comes up and goes down in ~0.2 s.
const RAISE_SPEED: float = 5.0
## The gel character's arms are short and its head big, so the prop is drawn a
## little larger than a real phone to read from across the depot.
const PHONE_SCALE: float = 1.5
## Where the wrist goes, from the shoulder, in the player's frame (-Z is
## forward): up beside the cheek and out in front of it.
const WRIST_FROM_SHOULDER: Vector3 = Vector3(-0.06, 0.2, -0.3)
## Fraction of the arm's length the wrist is kept under, so the elbow always
## has a bend to hide in instead of snapping straight.
const MAX_REACH: float = 0.93
## Where the phone's centre rests, in the hand bone's frame (+Y runs along the
## fingers, -Z comes out of the palm): on the palm, its length along the fingers.
const PHONE_IN_HAND: Vector3 = Vector3(0.0, 0.07, -0.03)
## Where the screen looks, in the player's frame: back toward the eyes (+Z),
## in toward the face (-X) and a little up.
const SCREEN_NORMAL: Vector3 = Vector3(-0.3, 0.3, 0.9)

var _player: Player
var _skeleton: Skeleton3D
var _layers: int = 1
var _weight: float = 0.0
var _attachment: BoneAttachment3D
var _phone: Node3D
var _solver: SkeletonIK3D
var _target: Marker3D


func setup(player: Player, skeleton: Skeleton3D, layers: int) -> void:
	_player = player
	_skeleton = skeleton
	_layers = layers


## The prop while it exists (null once the arm is back down and it is cleared).
func phone() -> Node3D:
	return _phone


## The IK target for the wrist, in the player's frame; null while not raised.
func wrist_target() -> Marker3D:
	return _target


## 0 = arm at the side, 1 = phone held up.
func weight() -> float:
	return _weight


## True when something else owns the arms or the whole rig.
func is_blocked() -> bool:
	if _player == null:
		return true
	return not _player.seat_node_path.is_empty() \
			or _player._ragdolled \
			or is_instance_valid(_player.carried_package) \
			or _player._gel_effects_component.knocked_out \
			or _player.anim_state in PlayerAnimator.EMOTE_CLIPS


func _process(delta: float) -> void:
	update_pose(delta)


func update_pose(delta: float) -> void:
	if _player == null or _skeleton == null:
		return
	var active: bool = _player.phone_raised and not is_blocked()
	if not active and _solver == null:
		return
	if is_blocked():
		_weight = 0.0
	else:
		_weight = move_toward(_weight, 1.0 if _player.phone_raised else 0.0, delta * RAISE_SPEED)
	if active and _solver == null:
		_build()
	if _solver == null:
		return
	if _weight <= 0.0 and not active:
		_clear()
		return
	_solver.influence = smoothstep(0.0, 1.0, _weight)
	_phone.visible = true
	_phone.scale = Vector3.ONE * PHONE_SCALE * lerpf(0.5, 1.0, _weight)
	_aim_wrist()


## Wrist goal and hand orientation: the phone's own basis (X/Y/Z are the hand
## bone's, see PHONE_IN_HAND), screen toward SCREEN_NORMAL.
func _aim_wrist() -> void:
	var shoulder: int = _skeleton.find_bone(SHOULDER_BONE)
	var to_player: Transform3D = _player.global_transform.affine_inverse() * _skeleton.global_transform
	var origin: Vector3 = to_player * _skeleton.get_bone_global_pose(shoulder).origin
	var offset: Vector3 = WRIST_FROM_SHOULDER
	var limit: float = _arm_length() * MAX_REACH
	if offset.length() > limit:
		offset = offset.normalized() * limit
	_target.transform = Transform3D(Basis.looking_at(SCREEN_NORMAL.normalized(), Vector3.UP), origin + offset)


## Shoulder to elbow to wrist along the rest pose, in player metres.
func _arm_length() -> float:
	var shoulder: int = _skeleton.find_bone(SHOULDER_BONE)
	var elbow: int = _skeleton.find_bone(ELBOW_BONE)
	var hand: int = _skeleton.find_bone(HAND_BONE)
	var scale_factor: float = _skeleton.global_basis.get_scale().x
	var a: Vector3 = _skeleton.get_bone_global_rest(shoulder).origin
	var b: Vector3 = _skeleton.get_bone_global_rest(elbow).origin
	var c: Vector3 = _skeleton.get_bone_global_rest(hand).origin
	return (a.distance_to(b) + b.distance_to(c)) * scale_factor


func _build() -> void:
	var hand: int = _skeleton.find_bone(HAND_BONE)
	if hand < 0 or _skeleton.find_bone(SHOULDER_BONE) < 0:
		return
	_attachment = BoneAttachment3D.new()
	_attachment.name = "PhoneHand"
	_attachment.bone_name = HAND_BONE
	_skeleton.add_child(_attachment)
	_phone = PHONE_SCENE.instantiate() as Node3D
	_phone.name = "Phone"
	_phone.position = PHONE_IN_HAND
	_attachment.add_child(_phone)
	PlayerAppearance.set_layers(_phone, _layers)
	PlayerAppearance.enable_shadows(_phone)
	_target = Marker3D.new()
	_target.name = "PhoneWristTarget"
	add_child(_target)
	_solver = SkeletonIK3D.new()
	_solver.name = "PhoneIK"
	_solver.root_bone = SHOULDER_BONE
	_solver.tip_bone = HAND_BONE
	_solver.override_tip_basis = true
	_solver.influence = 0.0
	_skeleton.add_child(_solver)
	_aim_wrist()
	_solver.target_node = _target.get_path()
	_solver.start(false)


func _clear() -> void:
	if _solver != null:
		_solver.stop()
		_solver.queue_free()
	for node: Node in [_attachment, _target]:
		if node != null:
			node.queue_free()
	_solver = null
	_attachment = null
	_phone = null
	_target = null

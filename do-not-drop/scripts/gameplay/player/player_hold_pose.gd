extends Node3D
## S-205: the gel's hands grip the box while its player holds the primary action steadying it
## (the care / tender hold). Pure presentation, drawn by every peer.
##
## Who is holding comes from two places, so the owner answers at once and the rest of the crew
## sees it too (the owner's own body is on RenderLayers.LOCAL_BODY and culled from their first-person
## camera, so a local-only pose would only ever show in the depot mirror):
## - the owner's copy reads `PlayerHoldFeedback.holding`, set the same frame the input is read and
##   never sent anywhere (player_hold_feedback.gd);
## - every other copy reads `care_state.held_by` / `helped_by` of the boxes, which the host fills from
##   the samples it counts (package_rescue.gd steadying_peers) and republishes the moment they change.
##
## Two ways to show it, both eased in and out in about 0.1 s:
## - on foot with the box in the arms: the carry pose already holds it (carry_pose.gd), so the hands
##   only press in a few centimetres on its sides (CarryPose.squeeze);
## - seated (a box on the lap or at the seat) or helping on foot: a SkeletonIK3D per arm, the driver's
##   chains (Player.DRIVER_ARM_BONES), reaches the box's two sides.
## The driver's seat, the phone in the hand, a ragdoll fall, a knockout and an emote own the arms (or
## the whole rig), and win. The real box, its physics and its result are never touched.

## Seconds-per-second of the blend: in or out in 0.1 s.
const BLEND_SPEED: float = 10.0
## How often (s) a remote copy looks for the box its player holds: care_state arrives at 10 Hz at most.
const SCAN_SEC: float = 0.05
## The palm touches the box's side, no deeper.
const GRIP_INSET: float = 0.005
## Fraction of the arm's length the hand may be sent to, so the elbow keeps a bend (the phone's).
const MAX_REACH: float = 0.93
const DRIVER_SEAT: StringName = &"DriverEyePoint"
const NONE: int = 0
const SQUEEZE: int = 1
const REACH: int = 2

var _player: Player
var _skeleton: Skeleton3D
## 0..1 how far the hands are pressed in (carrying) or reaching the box (seated).
var _squeeze: float = 0.0
var _reach: float = 0.0
var _reach_box: Node3D
var _solvers: Array[SkeletonIK3D] = []
var _targets: Array[Marker3D] = []
var _scan_left: float = 0.0
var _remote_box: Node3D


func _ready() -> void:
	_player = get_parent() as Player


func _find_skeleton() -> bool:
	if _skeleton != null:
		return true
	if _player == null or _player._body_visual == null:
		return false
	_skeleton = PlayerAppearance.find_skeleton(_player._body_visual)
	return _skeleton != null


## 0 = hands as the other poses leave them, 1 = gripping the box.
func weight() -> float:
	return maxf(_squeeze, _reach)


## The IK targets of the left and right hand while reaching (empty otherwise).
func hand_targets() -> Array[Marker3D]:
	return _targets


## True when something else owns the arms or the whole rig.
func is_blocked() -> bool:
	if _player == null:
		return true
	var phone: Node = _player.get_node_or_null(^"PlayerPhoneProp")
	return String(_player.seat_node_path).contains(DRIVER_SEAT) \
			or _player._ragdolled \
			or _player._gel_effects_component.knocked_out \
			or _player.anim_state in PlayerAnimator.EMOTE_CLIPS \
			or (phone != null and bool(phone.get(&"phone_raised")) and not bool(phone.call(&"is_blocked")))


## The box this player's hands are steadying right now, as this peer knows it (null when none, or
## when something else owns the arms).
func gripped_package() -> Node3D:
	if is_blocked():
		return null
	if _player.is_local():
		var care: Node = _player._cargo_care
		var feedback: Variant = care.get(&"hold_feedback") if care != null else null
		if feedback != null and bool(feedback.holding) and is_instance_valid(feedback.package):
			return feedback.package as Node3D
		return null
	return _remote_box if is_instance_valid(_remote_box) else null


func _process(delta: float) -> void:
	update_pose(delta)


func update_pose(delta: float) -> void:
	if not _find_skeleton():
		return
	if not _player.is_local():
		_scan_left -= delta
		if _scan_left <= 0.0:
			_scan_left = SCAN_SEC
			_remote_box = _scan_cargo()
	var box: Node3D = gripped_package()
	var mode: int = _mode_for(box)
	var blocked: bool = is_blocked()
	_squeeze = 0.0 if blocked else move_toward(_squeeze, 1.0 if mode == SQUEEZE else 0.0, delta * BLEND_SPEED)
	_reach = 0.0 if blocked else move_toward(_reach, 1.0 if mode == REACH else 0.0, delta * BLEND_SPEED)
	var carry_pose: Variant = _player._carry_pose
	if carry_pose != null:
		carry_pose.set(&"squeeze", smoothstep(0.0, 1.0, _squeeze))
	if mode == REACH:
		_reach_box = box
	if _reach <= 0.0 or not is_instance_valid(_reach_box):
		_clear()
		return
	if _solvers.is_empty():
		_build()
	_place_targets()
	for solver: SkeletonIK3D in _solvers:
		solver.influence = smoothstep(0.0, 1.0, _reach)


## How `box` is gripped: the carried one by pressing in, any other by reaching.
func _mode_for(box: Node3D) -> int:
	if box == null:
		return NONE
	if _player.seat_node_path.is_empty() and is_instance_valid(_player.carried_package):
		return SQUEEZE if _player.carried_package == box else NONE
	return REACH


## The box some care_state says this player steadies, if any.
func _scan_cargo() -> Node3D:
	var peer_id: int = _player.get_multiplayer_authority()
	for node: Node in get_tree().get_nodes_in_group(&"cargo"):
		var package := node as DeliveryPackage
		if package != null and (int(package.care_state.get("held_by", 0)) == peer_id
				or int(package.care_state.get("helped_by", 0)) == peer_id):
			return package
	return null


func _build() -> void:
	for side: float in _player.DRIVER_ARM_BONES:
		var bones: Array = _player.DRIVER_ARM_BONES[side]
		if _skeleton.find_bone(bones[0]) < 0 or _skeleton.find_bone(bones[1]) < 0:
			continue
		var target := Marker3D.new()
		target.name = "HoldHandTargetLeft" if side < 0.0 else "HoldHandTargetRight"
		add_child(target)
		_targets.append(target)
		var solver := SkeletonIK3D.new()
		solver.name = "HoldIKLeft" if side < 0.0 else "HoldIKRight"
		solver.root_bone = bones[0]
		solver.tip_bone = bones[1]
		solver.override_tip_basis = false
		solver.influence = 0.0
		_skeleton.add_child(solver)
		_solvers.append(solver)
	_place_targets()
	for index: int in _solvers.size():
		_solvers[index].target_node = _targets[index].get_path()
		_solvers[index].start(false)


## Each hand to the side of the box nearest it, at the height the carrying hands use, no further
## than the arm reaches (a box on the rack is across the cab: the arm points to it instead).
func _place_targets() -> void:
	var half: Vector3 = (_reach_box as DeliveryPackage).get_half_extents()
	var drawn: Transform3D = Player._drawn_transform(_reach_box)
	var height: float = minf(half.y * 0.65, 0.16)
	var right: Vector3 = _player._body_visual.global_basis.x
	var low: Vector3 = drawn * Vector3(-(half.x + GRIP_INSET), height, 0.0)
	var high: Vector3 = drawn * Vector3(half.x + GRIP_INSET, height, 0.0)
	if high.dot(right) < low.dot(right):
		var swap: Vector3 = low
		low = high
		high = swap
	var index: int = 0
	for side: float in _player.DRIVER_ARM_BONES:
		if index >= _targets.size():
			break
		var bones: Array = _player.DRIVER_ARM_BONES[side]
		var shoulder: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(
			_skeleton.find_bone(bones[0])).origin
		var goal: Vector3 = low if side < 0.0 else high
		var reach: float = _arm_length(bones) * MAX_REACH
		if shoulder.distance_to(goal) > reach:
			goal = shoulder + (goal - shoulder).normalized() * reach
		_targets[index].global_position = goal
		index += 1


## Shoulder to elbow to wrist along the rest pose, in world metres.
func _arm_length(bones: Array) -> float:
	var elbow_name: String = String(bones[0]).replace("upper_arm", "forearm")
	var a: Vector3 = _skeleton.get_bone_global_rest(_skeleton.find_bone(bones[0])).origin
	var b: Vector3 = _skeleton.get_bone_global_rest(_skeleton.find_bone(elbow_name)).origin
	var c: Vector3 = _skeleton.get_bone_global_rest(_skeleton.find_bone(bones[1])).origin
	return (a.distance_to(b) + b.distance_to(c)) * _skeleton.global_basis.get_scale().x


func _clear() -> void:
	for solver: SkeletonIK3D in _solvers:
		if is_instance_valid(solver):
			solver.stop()
			solver.queue_free()
	for target: Marker3D in _targets:
		if is_instance_valid(target):
			target.queue_free()
	_solvers.clear()
	_targets.clear()
	_reach_box = null

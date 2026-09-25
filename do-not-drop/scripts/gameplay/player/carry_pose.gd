extends Node3D
## Upper-body contact overlay. The five clips still own the body/legs; hands
## follow the actual networked package, including its width and lift arc.

var _player: Node3D
var _skeleton: Skeleton3D
var _solvers: Array[SkeletonIK3D] = []
var _targets: Array[Marker3D] = []
var _hand_basis: Array[Basis] = []
var _weight: float = 0.0


func setup(player: Node3D, skeleton: Skeleton3D) -> void:
	_player = player
	_skeleton = skeleton


func update_pose(package: Node3D, elapsed: float, delta: float) -> void:
	var active: bool = is_instance_valid(package) and _player.seat_node_path.is_empty()
	var wanted: float = smoothstep(0.02, 0.42, elapsed) if active else 0.0
	_weight = move_toward(_weight, wanted, delta * 7.0)
	if active and _solvers.is_empty():
		_build()
	if not active and _weight <= 0.0:
		_clear()
		return
	for i: int in _solvers.size():
		_solvers[i].influence = _weight
		if not active:
			continue
		var side: float = -1.0 if i == 0 else 1.0
		var half: Vector3 = package.get_half_extents()
		# Contact the upper near corners: the palm remains outside the box.
		var contact: Vector3 = package.to_global(Vector3(side * (half.x + 0.025),
			minf(half.y * 0.65, 0.16), half.z * 0.72))
		# Fingertips extend beyond the wrist. Leave room along the finger axis.
		contact += package.global_basis.z * 0.065
		_targets[i].global_position = contact
		_targets[i].global_basis = package.global_basis.orthonormalized() * _hand_basis[i]


func _build() -> void:
	for side: String in ["L", "R"]:
		var hand: int = _skeleton.find_bone("hand." + side)
		if hand < 0:
			continue
		var target := Marker3D.new()
		target.name = "PackageGrip" + side
		add_child(target)
		var basis: Basis = (_player.global_basis.inverse() * _skeleton.global_basis
			* _skeleton.get_bone_global_rest(hand).basis).orthonormalized()
		var sign_value: float = -1.0 if side == "L" else 1.0
		_hand_basis.append(Basis(Vector3.UP, sign_value * PI / 2.0) * basis)
		_targets.append(target)
		var solver := SkeletonIK3D.new()
		solver.name = "PackageIK" + side
		solver.root_bone = "upper_arm." + side
		solver.tip_bone = "hand." + side
		solver.override_tip_basis = true
		solver.influence = 0.0
		_skeleton.add_child(solver)
		solver.target_node = target.get_path()
		solver.start(false)
		_solvers.append(solver)


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
	_hand_basis.clear()

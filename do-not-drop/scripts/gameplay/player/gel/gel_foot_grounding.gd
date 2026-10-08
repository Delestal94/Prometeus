class_name GelFootGrounding
extends Node3D
## Presentation-only foot planting for the proportioned gel rig (S-311.24).
## At least the lowest foot is solved onto the visual floor; a lifted foot is
## left to the animation. Physics, camera and interaction nodes are untouched.

const SIDES: Array[String] = ["L", "R"]
const PLANT_WINDOW: float = 0.08

var _model: Node3D
var _skeleton: Skeleton3D
var _feet: Array[int] = []
var _ankle_clearance: Array[float] = []
var _targets: Array[Marker3D] = []
var _solvers: Array[SkeletonIK3D] = []
var _floor_y: float = 0.0
var _grounded: bool = true


func setup(model: Node3D) -> bool:
	_model = model
	_skeleton = PlayerAppearance.find_skeleton(model)
	if _skeleton == null:
		return false
	_floor_y = model.global_position.y
	for side: String in SIDES:
		var foot: int = _skeleton.find_bone("foot." + side)
		var thigh: int = _skeleton.find_bone("thigh." + side)
		if foot < 0 or thigh < 0:
			clear()
			return false
		_feet.append(foot)
		var rest_position: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_rest(foot).origin)
		_ankle_clearance.append(maxf(rest_position.y - _floor_y, 0.0))
		var target := Marker3D.new()
		target.name = "GelFootTarget" + side
		add_child(target)
		_targets.append(target)
		var solver := SkeletonIK3D.new()
		solver.name = "GelFootIK" + side
		solver.root_bone = "thigh." + side
		solver.tip_bone = "foot." + side
		solver.override_tip_basis = false
		_skeleton.add_child(solver)
		solver.target_node = target.get_path()
		solver.start(false)
		_solvers.append(solver)
	update_floor(_floor_y, true)
	return _solvers.size() == 2


func update_floor(floor_y: float, grounded: bool = true) -> void:
	_floor_y = floor_y
	_grounded = grounded
	if _skeleton == null or _feet.size() != 2:
		return
	var positions: Array[Vector3] = []
	for foot: int in _feet:
		positions.append(_skeleton.to_global(_skeleton.get_bone_global_pose(foot).origin))
	var lowest: float = minf(positions[0].y, positions[1].y)
	for index: int in _feet.size():
		var planted: bool = grounded and positions[index].y <= lowest + PLANT_WINDOW
		_solvers[index].influence = 1.0 if planted else 0.0
		_targets[index].global_position = Vector3(
			positions[index].x, floor_y + _ankle_clearance[index], positions[index].z
		)


func _process(_delta: float) -> void:
	if is_instance_valid(_model) and _model.visible:
		update_floor(_floor_y, _grounded)


func target_position(side: int) -> Vector3:
	return _targets[side].global_position if side >= 0 and side < _targets.size() else Vector3.ZERO


func influence(side: int) -> float:
	return _solvers[side].influence if side >= 0 and side < _solvers.size() else 0.0


func clear() -> void:
	for solver: SkeletonIK3D in _solvers:
		if is_instance_valid(solver):
			solver.stop()
			solver.queue_free()
	_solvers.clear()
	for target: Marker3D in _targets:
		if is_instance_valid(target):
			target.queue_free()
	_targets.clear()
	_feet.clear()
	_ankle_clearance.clear()


func _exit_tree() -> void:
	clear()

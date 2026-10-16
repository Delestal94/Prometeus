class_name GelImpactWaves
extends Node
## Presentation-only impact ripples. Contact points are converted to mesh-local
## coordinates and uploaded through four per-instance shader slots.

const MAX_WAVES: int = 4
const WAVE_DURATION: float = 1.35

var _mesh: MeshInstance3D
var _waves: Array[Dictionary] = []


func _exit_tree() -> void:
	_waves.clear()
	_upload()


func setup(model: Node) -> bool:
	_mesh = PlayerAppearance.find_mesh_instance(model)
	clear()
	return _mesh != null


func add_impact(world_position: Vector3, strength: float = 1.0) -> void:
	if _mesh == null or not is_instance_valid(_mesh):
		return
	add_local_impact(_mesh.to_local(world_position), strength)


func add_local_impact(local_position: Vector3, strength: float = 1.0) -> void:
	var wave: Dictionary = {
		&"center": local_position,
		&"age": 0.0,
		&"strength": clampf(strength, 0.0, 1.0),
	}
	if float(wave[&"strength"]) <= 0.0:
		return
	if _waves.size() >= MAX_WAVES:
		_waves.pop_front()
	_waves.append(wave)
	_upload()


func advance(delta: float) -> void:
	var step: float = maxf(delta, 0.0)
	for index: int in range(_waves.size() - 1, -1, -1):
		_waves[index][&"age"] = float(_waves[index][&"age"]) + step
		if float(_waves[index][&"age"]) >= WAVE_DURATION:
			_waves.remove_at(index)
	_upload()


func clear() -> void:
	_waves.clear()
	_upload()


func wave_count() -> int:
	return _waves.size()


func wave_at(index: int) -> Dictionary:
	return _waves[index].duplicate()


func _upload() -> void:
	if _mesh == null or not is_instance_valid(_mesh):
		return
	var strengths := Vector4.ZERO
	for slot: int in MAX_WAVES:
		var packed := Vector4(0.0, 0.0, 0.0, -1.0)
		if slot < _waves.size():
			var wave: Dictionary = _waves[slot]
			var center: Vector3 = wave[&"center"]
			packed = Vector4(center.x, center.y, center.z, float(wave[&"age"]))
			strengths[slot] = float(wave[&"strength"])
		_mesh.set_instance_shader_parameter(&"gel_wave_%d" % slot, packed)
	_mesh.set_instance_shader_parameter(&"gel_wave_strengths", strengths)

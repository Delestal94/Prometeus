extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_impact_debris_freed.gd
## N-980.3: the chips a hard hit throws (vehicle_effects.gd, ImpactDebris) must go
## away by themselves. A GPUParticles3D is born emitting, and turning a one-shot on
## while it already emits cancels its `finished` signal, so without switching it off
## first each hit left a node, its materials and its mesh in the level for good
## (the bench's endless run gained about 0.1 nodes a second). Measured on the real
## truck, through the same call a hit makes.

const VAN_SCENE_PATH: String = "res://scenes/gameplay/vehicle/vehicle.tscn"
## Lifetime 1.1 s at explosiveness 0.95: the engine ends it after 1.155 s.
const DEBRIS_SECONDS: float = 1.5

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var van: Node3D = (load(VAN_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(van)
	await process_frame
	var effects: Node = van.find_child("VehicleEffects", true, false)
	_expect(effects != null, "The truck has its VehicleEffects")
	if effects != null:
		await _check_debris_goes_away(effects)
	van.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: the debris of a hit frees itself")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _debris() -> Array[GPUParticles3D]:
	var found: Array[GPUParticles3D] = []
	for child: Node in root.get_children():
		if child is GPUParticles3D and (child as GPUParticles3D).one_shot:
			found.append(child as GPUParticles3D)
	return found


func _check_debris_goes_away(effects: Node) -> void:
	_expect(_debris().is_empty(), "No debris before the hit")
	effects.call(&"_burst_debris", Vector3.ZERO, 20.0)
	effects.call(&"_burst_debris", Vector3.ZERO, 20.0)
	var born: Array[GPUParticles3D] = _debris()
	_expect(born.size() == 2, "Each hit throws its own debris (%d)" % born.size())
	for particles: GPUParticles3D in born:
		_expect(particles.emitting, "The debris is flying right after the hit")
	await create_timer(DEBRIS_SECONDS).timeout
	await process_frame
	_expect(_debris().is_empty(), "The debris freed itself after its life (%d left)" % _debris().size())

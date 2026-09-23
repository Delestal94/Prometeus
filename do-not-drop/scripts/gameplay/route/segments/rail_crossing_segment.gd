extends RouteSegment
class_name RailCrossingSegment
## A level crossing (docs/tareas-nacho.md #63): tracks across the road, red
## lights and a crossbuck, and every so often the barriers come down and a
## short train goes by -- a forced stop in the middle of a delivery.
##
## Whether this crossing closes is drawn from the world seed and where the
## segment sits, so every peer agrees; each peer runs the barrier and train
## off the (replicated) truck's approach. Only the host's physics decides
## anything, and there the barrier arms and train cars are solid.

const APPROACH_TRIGGER: float = 55.0
const CLOSE_CHANCE: float = 0.6
const ARM_SECONDS: float = 1.3
const WARNING_SECONDS: float = 1.2
const TRAIN_SPEED: float = 17.0
const TRAIN_SPAN: float = 42.0
const GAUGE: float = 1.435
const RAIL_STEEL := Color("5b5f62")
const SLEEPER := Color("5a4636")

enum State { WAITING, WARNING, CLOSING, TRAIN, OPENING, DONE }

var will_close: bool = false
var state: int = State.WAITING
var track_z: float = 0.0
var _timer: float = 0.0
var _arms: Array[Node3D] = []
var _lamps: Array[StandardMaterial3D] = []
var _train: Array[AnimatableBody3D] = []
var _train_x: float = 0.0
var _bell: AudioStreamPlayer3D


func _init() -> void:
	length = 32.0


func _build() -> void:
	track_z = -length * 0.5
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)
	# Tracks: two rails on sleepers, running across the road and well beyond.
	for side: float in [-0.5, 0.5]:
		_box("Rail", Vector3(TRAIN_SPAN * 2.0, 0.12, 0.08), Vector3(0.0, 0.06, track_z + side * GAUGE), RAIL_STEEL)
	for index: int in range(28):
		var x: float = -TRAIN_SPAN + 1.5 + float(index) * (TRAIN_SPAN * 2.0 - 3.0) / 27.0
		_box("Sleeper", Vector3(0.28, 0.06, GAUGE + 0.9), Vector3(x, 0.02, track_z), SLEEPER)
	_box("CrossingStopLine", Vector3(6.0, 0.02, 0.35), Vector3(1.5, 0.03, track_z + 5.5), MARKING)
	_box("CrossingStopLine", Vector3(6.0, 0.02, 0.35), Vector3(-1.5, 0.03, track_z - 5.5), MARKING)
	for side: float in [-1.0, 1.0]:
		_build_signal(Vector3(side * 5.6, 0.0, track_z + side * 3.2), side)
	_build_train()
	_bell = AudioStreamPlayer3D.new()
	_bell.name = "CrossingBell"
	_bell.stream = SynthAudio.crossing_bell()
	_bell.unit_size = 10.0
	_bell.max_distance = 70.0
	_bell.bus = &"SFX"
	_bell.position = Vector3(0.0, 2.5, track_z)
	add_child(_bell)
	var seed_value: int = 0
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network != null:
		seed_value = int(network.get(&"world_seed"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, roundi(global_position.x), roundi(global_position.z), &"rail"])
	will_close = rng.randf() < CLOSE_CHANCE


## World-space points along the tracks where the ground should be level with
## the road (route.gd turns them into terrain pads): trains don't climb hills.
func track_pads() -> Array[Vector3]:
	var pads: Array[Vector3] = []
	var x: float = -TRAIN_SPAN
	while x <= TRAIN_SPAN:
		pads.append(transform * Vector3(x, 0.0, track_z))
		x += 7.0
	return pads


## A post with the crossbuck, twin red lamps and a barrier arm that swings
## down across the whole road on this side of the tracks.
func _build_signal(at: Vector3, side: float) -> void:
	_box("CrossingPost", Vector3(0.18, 3.4, 0.18), at + Vector3(0.0, 1.7, 0.0), CONCRETE, true)
	for tilt: float in [0.6, -0.6]:
		var board: Node3D = _box("Crossbuck", Vector3(1.5, 0.22, 0.05), at + Vector3(0.0, 3.05, 0.0), MARKING)
		board.rotation.z = tilt
	for offset: float in [-0.28, 0.28]:
		var lamp: Node3D = _box("CrossingLamp", Vector3(0.22, 0.22, 0.12), at + Vector3(offset, 2.45, side * 0.12), Color("5a1210"))
		for child: Node in lamp.get_children():
			if child is MeshInstance3D:
				var glow := StandardMaterial3D.new()
				glow.albedo_color = Color("5a1210")
				glow.emission_enabled = true
				glow.emission = Color("ff2a1f")
				glow.emission_energy_multiplier = 0.0
				(child as MeshInstance3D).material_override = glow
				_lamps.append(glow)
	# The arm pivots on the post; up is vertical, down spans the road.
	var pivot := StaticBody3D.new()
	pivot.name = "BarrierArm"
	pivot.collision_layer = 1
	pivot.collision_mask = 6
	pivot.position = at + Vector3(0.0, 1.05, 0.0)
	add_child(pivot)
	var arm_length: float = 10.6
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(arm_length, 0.14, 0.12)
	mesh.mesh = box
	mesh.material_override = _material(Color("e8e3d6"))
	mesh.position = Vector3(-side * arm_length * 0.5, 0.0, 0.0)
	pivot.add_child(mesh)
	for stripe: int in range(5):
		var band := MeshInstance3D.new()
		var band_box := BoxMesh.new()
		band_box.size = Vector3(0.9, 0.15, 0.13)
		band.mesh = band_box
		band.material_override = _material(Color("c8302b"))
		band.position = Vector3(-side * (1.2 + float(stripe) * 2.0), 0.0, 0.0)
		pivot.add_child(band)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(arm_length, 0.3, 0.3)
	shape.shape = box_shape
	shape.position = mesh.position
	pivot.add_child(shape)
	pivot.set_meta(&"side", side)
	# A script-driven part: keeps it out of the static geometry merge.
	pivot.set_meta(&"animated", true)
	_set_arm(pivot, 0.0)
	_arms.append(pivot)


## 0 = up (vertical, out of the way), 1 = down across the road.
func _set_arm(arm: Node3D, down: float) -> void:
	var side: float = float(arm.get_meta(&"side", 1.0))
	arm.rotation.z = side * lerpf(-PI * 0.5, 0.0, down)


func _build_train() -> void:
	var colors: Array[Color] = [Color("2d5d7b"), Color("8c3b2e"), Color("8c3b2e"), Color("6b7a3a")]
	for index: int in range(colors.size()):
		var car := AnimatableBody3D.new()
		car.name = "TrainCar%d" % index
		car.collision_layer = 1
		car.collision_mask = 0
		car.sync_to_physics = false
		var size := Vector3(7.5, 3.0, 2.6)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		var paint := StandardMaterial3D.new()
		paint.albedo_color = colors[index]
		paint.roughness = 0.7
		mesh.material_override = paint
		mesh.position.y = size.y * 0.5 + 0.35
		car.add_child(mesh)
		var roof := MeshInstance3D.new()
		var roof_box := BoxMesh.new()
		roof_box.size = Vector3(size.x - 0.4, 0.2, size.z - 0.2)
		roof.mesh = roof_box
		roof.material_override = _material(Color("3b3f42"))
		roof.position.y = size.y + 0.45
		car.add_child(roof)
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		shape.position = mesh.position
		car.add_child(shape)
		car.set_meta(&"animated", true)
		car.visible = false
		car.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(car)
		_train.append(car)


func _physics_process(delta: float) -> void:
	match state:
		State.WAITING:
			if will_close and _truck_approaching():
				state = State.WARNING
				_timer = 0.0
				_bell.play()
		State.WARNING:
			_timer += delta
			if _timer >= WARNING_SECONDS:
				state = State.CLOSING
				_timer = 0.0
		State.CLOSING:
			_timer += delta
			for arm: Node3D in _arms:
				_set_arm(arm, clampf(_timer / ARM_SECONDS, 0.0, 1.0))
			if _timer >= ARM_SECONDS:
				state = State.TRAIN
				_train_x = -TRAIN_SPAN - 4.0
				for car: AnimatableBody3D in _train:
					car.visible = true
					car.process_mode = Node.PROCESS_MODE_INHERIT
		State.TRAIN:
			_train_x += TRAIN_SPEED * delta
			for index: int in range(_train.size()):
				var at: Vector3 = Vector3(_train_x - float(index) * 8.0, 0.0, track_z)
				_train[index].position = Vector3(at.x, _ground_offset(at), at.z)
			if _train_x - float(_train.size()) * 8.0 > TRAIN_SPAN:
				for car: AnimatableBody3D in _train:
					car.visible = false
					car.process_mode = Node.PROCESS_MODE_DISABLED
				state = State.OPENING
				_timer = 0.0
		State.OPENING:
			_timer += delta
			for arm: Node3D in _arms:
				_set_arm(arm, 1.0 - clampf(_timer / ARM_SECONDS, 0.0, 1.0))
			if _timer >= ARM_SECONDS:
				state = State.DONE
				_bell.stop()
	var flashing: bool = state in [State.WARNING, State.CLOSING, State.TRAIN, State.OPENING]
	var phase: bool = fmod(Time.get_ticks_msec() / 450.0, 2.0) < 1.0
	for index: int in range(_lamps.size()):
		_lamps[index].emission_energy_multiplier = (2.2 if (index % 2 == 0) == phase else 0.0) if flashing else 0.0


## Height of the (levelled) ground under a point of the track, in local
## space: on a continuous-terrain route the whole segment sits on it.
func _ground_offset(_at: Vector3) -> float:
	return float(get_meta(&"track_height", 0.0))


func _truck_approaching() -> bool:
	var truck := get_tree().get_first_node_in_group(&"vehicle") as Node3D
	if truck == null:
		return false
	var local: Vector3 = to_local(truck.global_position)
	# Still before the tracks (entry is +Z), and close enough to see it happen.
	return local.z > track_z and local.z - track_z < APPROACH_TRIGGER and absf(local.x) < 12.0

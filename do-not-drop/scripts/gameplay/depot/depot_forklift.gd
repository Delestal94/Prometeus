class_name DepotForklift
extends AnimatableBody3D
## A stand-up reach forklift working the stock aisle: it drives a pallet down
## the lane, lifts it toward the top of the racking, lowers it again and backs
## up to where it started -- beeping as it reverses, beacon turning. It stops
## dead for anyone standing in its way, like a real one should.
##
## Local presentation, same as the depot's staff: every peer runs its own.

const BODY := Color("e8772e")
const DARK := Color("263238")
const STEEL := Color("59656a")
const TYRE := Color("1b1f22")
const FORK := Color("3b4247")
const BEACON := Color("ffb02e")
const SPEED: float = 1.6
const LIFT_SPEED: float = 0.55
const LIFT_TOP: float = 2.3
const SAFETY_DISTANCE: float = 2.3

## Depot-space lane ends: it faces +Z at `start` and drives to `end`.
var start: Vector3 = Vector3.ZERO
var end: Vector3 = Vector3(0.0, 0.0, 10.0)
var _phase: int = 0  # 0 drive out, 1 lift, 2 lower, 3 reverse, 4 rest
var _lift: float = 0.0
var _rest: float = 1.5
var _carriage: Node3D
var _beacon: MeshInstance3D
var _beacon_light: OmniLight3D
var _beeper: AudioStreamPlayer3D
var _engine: AudioStreamPlayer3D
var _time: float = 0.0


func _ready() -> void:
	sync_to_physics = true
	collision_layer = 1
	collision_mask = 0
	_build()


## Where it starts, facing down the lane. Call before adding it to the tree:
## a body synced to physics takes its first transform from there, and one set
## in its own _ready() is overwritten by the physics state.
func place(lane_start: Vector3, lane_end: Vector3) -> void:
	start = lane_start
	end = lane_end
	position = lane_start
	rotation.y = PI  # Model built facing -Z; the lane runs toward +Z.


func _physics_process(delta: float) -> void:
	_time += delta
	var blocked: bool = _someone_ahead()
	match _phase:
		0:
			if not blocked and _drive_toward(end, delta):
				_phase = 1
		1:
			_lift = move_toward(_lift, LIFT_TOP, LIFT_SPEED * delta)
			if is_equal_approx(_lift, LIFT_TOP):
				_phase = 2
		2:
			_lift = move_toward(_lift, 0.0, LIFT_SPEED * delta)
			if is_zero_approx(_lift):
				_phase = 3
		3:
			if not blocked and _drive_toward(start, delta):
				_phase = 4
				_rest = 3.0
		4:
			_rest -= delta
			if _rest <= 0.0:
				_phase = 0
	_carriage.position.y = _lift
	var reversing: bool = _phase == 3 and not blocked
	if reversing != _beeper.playing:
		if reversing:
			_beeper.play()
		else:
			_beeper.stop()
	var moving: bool = (_phase == 0 or _phase == 3) and not blocked
	_engine.pitch_scale = lerpf(_engine.pitch_scale, 1.25 if moving or _phase in [1, 2] else 0.85, clampf(delta * 3.0, 0.0, 1.0))
	var flash: bool = sin(_time * 9.0) > 0.2
	(_beacon.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0 if flash else 0.4
	_beacon_light.light_energy = 0.9 if flash else 0.1


## Moves along the lane (it only ever drives straight, forward or back) and
## says whether it has arrived.
func _drive_toward(target: Vector3, delta: float) -> bool:
	var offset: Vector3 = target - position
	offset.y = 0.0
	if offset.length() < 0.02:
		position = Vector3(target.x, position.y, target.z)
		return true
	position += offset.normalized() * minf(SPEED * delta, offset.length())
	return false


## Anyone within a couple of metres in the direction of travel stops it.
func _someone_ahead() -> bool:
	if _phase != 0 and _phase != 3:
		return false
	var parent := get_parent_node_3d()
	var heading: Vector3 = (end - start).normalized() if _phase == 0 else (start - end).normalized()
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Node3D
		if player == null:
			continue
		var local: Vector3 = parent.to_local(player.global_position) if parent != null else player.global_position
		var to_player := Vector3(local.x - position.x, 0.0, local.z - position.z)
		var along: float = to_player.dot(heading)
		if along > -0.5 and along < SAFETY_DISTANCE + 1.2 and absf(to_player.cross(Vector3.UP).dot(heading)) < 1.3:
			return true
	return false


func _build() -> void:
	# Built facing -Z: forks out front (-Z), operator platform at the back.
	var kit := DepotKit.new(self, "Frame", self)
	var body := DepotKit.flat(BODY, 0.55, 0.1)
	var dark := DepotKit.flat(DARK, 0.7)
	var steel := DepotKit.flat(STEEL, 0.45, 0.5)
	var tyre := DepotKit.flat(TYRE, 0.95)
	kit.box(Vector3(1.15, 0.55, 1.5), Vector3(0.0, 0.45, 0.45), body, true)
	kit.box(Vector3(1.18, 0.12, 1.54), Vector3(0.0, 0.76, 0.45), dark)
	kit.box(Vector3(1.0, 0.95, 0.32), Vector3(0.0, 1.2, 1.0), body)  # counterweight hood
	kit.box(Vector3(0.9, 0.08, 0.5), Vector3(0.0, 0.3, 1.45), DepotKit.flat(Color("7a8387"), 0.8, 0.3))  # step plate
	# Overhead guard: four posts and a slatted roof.
	for x: float in [-0.52, 0.52]:
		for z: float in [0.0, 1.15]:
			kit.box(Vector3(0.06, 1.45, 0.06), Vector3(x, 1.5, z), dark)
	for index: int in range(5):
		kit.box(Vector3(1.1, 0.04, 0.08), Vector3(0.0, 2.22, 0.05 + index * 0.27), dark)
	kit.box(Vector3(0.3, 0.3, 0.18), Vector3(0.28, 1.35, 0.6), dark)  # control console
	kit.cylinder(0.035, 0.28, Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0.28, 1.6, 0.55)), DepotKit.flat(Color("c0392b"), 0.5), 8)
	# Mast rails.
	for x: float in [-0.42, 0.42]:
		kit.box(Vector3(0.1, 2.9, 0.12), Vector3(x, 1.55, -0.38), steel)
	kit.box(Vector3(0.94, 0.1, 0.12), Vector3(0.0, 3.0, -0.38), steel)
	# Wheels.
	for x: float in [-0.5, 0.5]:
		for z: float in [-0.1, 1.0]:
			kit.cylinder(0.2, 0.18, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x, 0.2, z)), tyre, 12)
	# Warning stripes on the counterweight.
	kit.box(Vector3(1.02, 0.18, 0.02), Vector3(0.0, 0.95, 1.17), DepotKit.detailed(Color.WHITE, "res://assets/textures/environment/tx_env_warning_256.png", 0.5, 0.7))
	kit.commit("ForkliftBody")
	# The carriage rides the mast: backrest, forks, and a pallet of stock.
	_carriage = Node3D.new()
	_carriage.name = "Carriage"
	add_child(_carriage)
	var lift_kit := DepotKit.new(_carriage, "CarriageColliders")
	var fork := DepotKit.flat(FORK, 0.5, 0.5)
	lift_kit.box(Vector3(1.0, 0.7, 0.06), Vector3(0.0, 0.55, -0.48), steel)
	for x: float in [-0.25, 0.25]:
		lift_kit.box(Vector3(0.1, 0.05, 1.1), Vector3(x, 0.14, -1.05), fork)
	lift_kit.model("res://assets/models/environment/props/sm_env_prop_pallet.glb", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.85), Vector3(0.0, 0.17, -1.05)))
	var box_paths: Array[String] = [
		"res://assets/models/cargo/sm_cargo_box_cube.glb",
		"res://assets/models/cargo/sm_cargo_box_flat.glb",
		"res://assets/models/cargo/sm_cargo_box_tall.glb",
	]
	var spots: Array[Vector3] = [Vector3(-0.22, 0.22, -1.3), Vector3(0.22, 0.22, -1.3), Vector3(-0.22, 0.22, -0.8), Vector3(0.22, 0.22, -0.8), Vector3(0.0, 0.63, -1.05)]
	for index: int in range(spots.size()):
		lift_kit.model(box_paths[index % box_paths.size()], Transform3D(Basis(Vector3.UP, index * 0.2).scaled(Vector3.ONE * 0.62), spots[index]))
	lift_kit.commit("CarriageMesh")
	# Driver: stands on the rear platform at the controls.
	var driver: Node3D = DepotWorker.CHARACTER_SCENE.instantiate()
	driver.name = "Operator"
	driver.position = Vector3(-0.05, 0.34, 1.45)
	add_child(driver)
	for node: Node in driver.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
			var suit := mesh_instance.mesh.surface_get_material(0) as BaseMaterial3D
			if suit != null:
				var tinted := suit.duplicate() as BaseMaterial3D
				tinted.albedo_color = Color("ffc93c")
				mesh_instance.set_surface_override_material(0, tinted)
			break
	var anim := driver.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim != null and anim.has_animation(&"Idle"):
		anim.get_animation(&"Idle").loop_mode = Animation.LOOP_LINEAR
		anim.play(&"Idle")
	_beacon = MeshInstance3D.new()
	_beacon.name = "Beacon"
	var lens := CylinderMesh.new()
	lens.top_radius = 0.07
	lens.bottom_radius = 0.09
	lens.height = 0.14
	_beacon.mesh = lens
	_beacon.material_override = DepotKit.glow(BEACON, 0.4).duplicate()
	_beacon.position = Vector3(0.4, 2.31, 1.05)
	add_child(_beacon)
	_beacon_light = OmniLight3D.new()
	_beacon_light.light_color = BEACON
	_beacon_light.omni_range = 4.5
	_beacon_light.position = _beacon.position + Vector3(0.0, 0.2, 0.0)
	add_child(_beacon_light)
	_beeper = AudioStreamPlayer3D.new()
	_beeper.name = "ReverseBeeper"
	_beeper.stream = SynthAudio.reverse_beep()
	_beeper.bus = &"SFX"
	_beeper.volume_db = -14.0
	_beeper.unit_size = 4.0
	_beeper.max_distance = 30.0
	add_child(_beeper)
	_engine = AudioStreamPlayer3D.new()
	_engine.name = "Motor"
	_engine.stream = SynthAudio.engine_loop()
	_engine.bus = &"SFX"
	_engine.volume_db = -30.0
	_engine.unit_size = 3.0
	_engine.max_distance = 25.0
	_engine.autoplay = true
	add_child(_engine)

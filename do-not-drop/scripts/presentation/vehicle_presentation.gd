extends Node3D
## Presentation only. Native VehicleWheel3D poses come from physics on the host
## and replication on clients; never rotate the wheels a second time here.

@export var steering_ratio: float = 7.0
@export var headlight_energy: float = 1.6
@export var impact_flicker_seconds: float = 0.16
@export var engine_volume_db: float = -21.0
@export var audio_enabled: bool = true

@onready var vehicle: VehicleBody3D = get_parent()
@onready var steering_wheel: MeshInstance3D = vehicle.get_node("CabinInterior/SteeringWheel")
var headlights: Array[SpotLight3D] = []
var engine_player: AudioStreamPlayer3D
var _steering_rest: Basis
var _front_materials: Array[StandardMaterial3D] = []
var _rear_materials: Array[StandardMaterial3D] = []
var _flicker_remaining: float = 0.0
var _motor_mix: float = 0.0


func _ready() -> void:
	_steering_rest = steering_wheel.basis
	_build_wheel_details()
	_build_steering_details()
	for side: String in ["Left", "Right"]:
		var front: MeshInstance3D = vehicle.get_node("BodyVisuals/" + side + "Headlight")
		_front_materials.append(_unique_material(front))
		var beam := SpotLight3D.new()
		beam.name = side + "HeadlightBeam"
		beam.position = front.position + Vector3(0.0, 0.0, -0.07)
		beam.light_color = Color("ffe9b0")
		beam.spot_range = 24.0
		beam.spot_angle = 32.0
		beam.spot_attenuation = 1.2
		beam.shadow_enabled = false
		front.get_parent().add_child(beam)
		headlights.append(beam)
		_rear_materials.append(_unique_material(vehicle.get_node("CargoBay/" + side + "TailLight")))
	engine_player = AudioStreamPlayer3D.new()
	engine_player.name = "EngineAudio"
	engine_player.position = Vector3(0.0, 0.0, -1.4)
	engine_player.stream = preload("res://scripts/presentation/synth_audio.gd").engine_loop()
	engine_player.unit_size = 7.0
	engine_player.max_distance = 45.0
	engine_player.volume_db = -60.0
	add_child(engine_player)
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.vehicle_impact.connect(_on_impact)
	update_presentation(0.0)


func _process(delta: float) -> void:
	update_presentation(delta)


func update_presentation(delta: float) -> void:
	# TorusMesh lies in its local XZ plane: its axle is local Y, even when tilted.
	steering_wheel.basis = _steering_rest * Basis(Vector3.UP, -vehicle.steering * steering_ratio)
	_flicker_remaining = maxf(0.0, _flicker_remaining - delta)
	var running: bool = vehicle.presentation_engine_running
	var flicker: float = 0.3 if _flicker_remaining > 0.0 else 1.0
	for index: int in range(headlights.size()):
		headlights[index].light_energy = headlight_energy * flicker if running else 0.0
		_front_materials[index].emission_energy_multiplier = 0.8 * flicker if running else 0.0
	for material: StandardMaterial3D in _rear_materials:
		material.emission_energy_multiplier = 2.4 if vehicle.presentation_braking else (0.18 if running else 0.0)
	_update_engine(delta, running)


func _update_engine(delta: float, running: bool) -> void:
	var target_mix: float = 1.0 if running and audio_enabled else 0.0
	_motor_mix = move_toward(_motor_mix, target_mix, delta * 4.0)
	if target_mix > 0.0 and not engine_player.playing:
		engine_player.play()
	if _motor_mix <= 0.0:
		engine_player.stop()
		return
	var speed: float = clampf(vehicle.linear_velocity.length() / 20.0, 0.0, 1.0)
	var load_amount: float = clampf(absf(vehicle.engine_force) / maxf(vehicle.maximum_engine_force, 1.0), 0.0, 1.0)
	var target_pitch: float = 0.85 + speed * 1.45 + load_amount * 0.25
	engine_player.pitch_scale = lerpf(engine_player.pitch_scale, target_pitch, 1.0 - exp(-5.0 * delta))
	engine_player.volume_db = engine_volume_db + linear_to_db(maxf(_motor_mix, 0.001)) + load_amount * 3.0


func _on_impact(strength: float, impact_position: Vector3) -> void:
	if strength >= 7.0 and vehicle.global_position.distance_to(impact_position) < 5.0:
		# One brief dip, not repeated flashes. It never affects physics or visibility masks.
		_flicker_remaining = impact_flicker_seconds


func _unique_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	var material: StandardMaterial3D = mesh.get_active_material(0).duplicate()
	mesh.material_override = material
	return material


func _build_wheel_details() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d4d9c2")
	material.roughness = 0.6
	for wheel: Node in vehicle.get_children():
		if not wheel is VehicleWheel3D:
			continue
		# Radial spokes make existing wheel motion readable on the smooth cylinders.
		for index: int in range(3):
			var spoke := MeshInstance3D.new()
			spoke.name = "VisualSpoke%d" % index
			var box := BoxMesh.new()
			box.size = Vector3(0.018, 0.035, 0.38)
			spoke.mesh = box
			spoke.material_override = material
			spoke.position.x = signf(wheel.position.x) * 0.175
			spoke.rotation.x = float(index) * PI / 3.0
			wheel.add_child(spoke)


func _build_steering_details() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("42575b")
	material.roughness = 0.8
	for index: int in range(3):
		var spoke := MeshInstance3D.new()
		spoke.name = "Spoke%d" % index
		var box := BoxMesh.new()
		box.size = Vector3(0.025, 0.025, 0.15)
		spoke.mesh = box
		spoke.material_override = material
		var angle: float = float(index) * TAU / 3.0
		spoke.position = Vector3(sin(angle), 0.0, cos(angle)) * 0.075
		spoke.rotation.y = angle
		steering_wheel.add_child(spoke)
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.055
	cylinder.bottom_radius = 0.055
	cylinder.height = 0.045
	cylinder.radial_segments = 12
	hub.mesh = cylinder
	hub.material_override = material
	steering_wheel.add_child(hub)

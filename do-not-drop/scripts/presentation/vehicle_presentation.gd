extends Node3D
## Presentation only. Native VehicleWheel3D poses come from physics on the host
## and replication on clients; never rotate the wheels a second time here.

@export var steering_ratio: float = 7.0
@export var headlight_energy: float = 1.6
@export var impact_flicker_seconds: float = 0.16
@export var engine_volume_db: float = -21.0
@export var impact_thud_volume_db: float = -6.0
@export var screech_volume_db: float = -14.0
@export var audio_enabled: bool = true

## Exaggerated exterior lean beyond what the real suspension already does
## (docs/especificaciones-visuales.md #21). Deliberately scoped to
## BodyVisuals only, not CabinInterior/CargoBay -- rotating the seats would
## also rotate every FirstPersonCamera anchored under them, stacking a third
## continuous motion on top of the shake and head bob those already have.
## This reads for passengers glancing out a window, for other players
## watching the van drive by, and for the dev third-person camera (#75);
## the driver's own felt sense of weight is a separate, riskier follow-up.
@export var max_roll_degrees: float = 6.0
@export var max_pitch_degrees: float = 3.0
@export var lean_smooth_speed: float = 5.0
## Cargo sink (#96): how far the body visibly settles per kg of cargo
## currently aboard, capped so a maxed-out Peso Creciente box can't sink the
## whole van through the road.
@export var cargo_sink_per_kg: float = 0.0025
@export var cargo_sink_max: float = 0.08
@export var sink_smooth_speed: float = 2.0
## Dust under the wheels (#49): a continuous, low-key puff while grounded
## and moving, ramping up with skid. Not a one-shot burst like the confetti
## on a ruined package -- a steady trickle, on or off.
@export var dust_color: Color = Color("9c8060")
@export var dust_min_speed_kmh: float = 6.0

@onready var vehicle: VehicleBody3D = get_parent()
@onready var steering_wheel: MeshInstance3D = vehicle.get_node("CabinInterior/SteeringWheel")
@onready var body_visuals: Node3D = vehicle.get_node("BodyVisuals")
var headlights: Array[SpotLight3D] = []
var engine_player: AudioStreamPlayer3D
var impact_player: AudioStreamPlayer3D
var screech_player: AudioStreamPlayer3D
var _steering_rest: Basis
var _front_materials: Array[StandardMaterial3D] = []
var _rear_materials: Array[StandardMaterial3D] = []
var _wheels: Array[VehicleWheel3D] = []
var _dust_emitters: Array[GPUParticles3D] = []
var _flicker_remaining: float = 0.0
var _motor_mix: float = 0.0
var _screech_mix: float = 0.0
var _roll: float = 0.0
var _pitch: float = 0.0
var _sink: float = 0.0


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
	impact_player = AudioStreamPlayer3D.new()
	impact_player.name = "ImpactAudio"
	impact_player.stream = preload("res://scripts/presentation/synth_audio.gd").impact_thud()
	impact_player.unit_size = 10.0
	impact_player.max_distance = 60.0
	add_child(impact_player)
	screech_player = AudioStreamPlayer3D.new()
	screech_player.name = "ScreechAudio"
	screech_player.position = Vector3(0.0, -0.3, 1.2)
	screech_player.stream = preload("res://scripts/presentation/synth_audio.gd").tire_screech()
	screech_player.unit_size = 8.0
	screech_player.max_distance = 35.0
	screech_player.volume_db = -60.0
	add_child(screech_player)
	for wheel: Node in vehicle.get_children():
		if wheel is VehicleWheel3D:
			_wheels.append(wheel)
	_build_dust_emitters()
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
	_update_screech(delta)
	_apply_body_lean(delta)
	_apply_cargo_sink(delta)
	_apply_dust()


func _apply_body_lean(delta: float) -> void:
	var speed_factor: float = clampf(vehicle.speed_kmh / maxf(vehicle.maximum_speed_kmh, 1.0), 0.0, 1.0)
	var target_roll: float = -vehicle.steering * speed_factor
	var target_pitch: float = 0.0
	if vehicle.presentation_braking:
		target_pitch = -1.0  # nose dips down under hard braking
	elif vehicle.presentation_engine_running and vehicle.engine_force < -1.0:
		target_pitch = 0.35  # slight nose-up squat while accelerating
	_roll = move_toward(_roll, target_roll, lean_smooth_speed * delta)
	_pitch = move_toward(_pitch, target_pitch, lean_smooth_speed * delta)
	body_visuals.rotation = Vector3(deg_to_rad(max_pitch_degrees) * _pitch, 0.0, deg_to_rad(max_roll_degrees) * _roll)


## Total mass of whatever cargo is actually aboard right now -- packages
## aren't children of the vehicle in the scene tree (they're independent
## RigidBody3D resting on the CargoBay floor via contact), so this asks the
## "cargo" group directly rather than walking the vehicle's own children.
func _apply_cargo_sink(delta: float) -> void:
	var total_mass: float = 0.0
	for package: Node in get_tree().get_nodes_in_group(&"cargo"):
		if bool(package.get(&"is_loaded")):
			total_mass += float(package.get(&"mass"))
	var target_sink: float = clampf(total_mass * cargo_sink_per_kg, 0.0, cargo_sink_max)
	_sink = move_toward(_sink, target_sink, sink_smooth_speed * delta)
	body_visuals.position.y = -_sink


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


## Average skid across every wheel touching the ground -- VehicleWheel3D's
## own get_skidinfo() (0 = full grip, 1 = full slide), so this needs no
## separate slip calculation of its own. Screeching while airborne would be
## wrong, so wheels not in contact just don't count.
func _update_screech(delta: float) -> void:
	var skid_total: float = 0.0
	var grounded_count: int = 0
	for wheel: VehicleWheel3D in _wheels:
		if wheel.is_in_contact():
			skid_total += 1.0 - wheel.get_skidinfo()
			grounded_count += 1
	var average_skid: float = skid_total / grounded_count if grounded_count > 0 else 0.0
	var moving: bool = vehicle.linear_velocity.length() > 1.5
	var target_mix: float = average_skid if (moving and audio_enabled) else 0.0
	_screech_mix = move_toward(_screech_mix, target_mix, delta * 4.0)
	if _screech_mix > 0.02 and not screech_player.playing:
		screech_player.play()
	if _screech_mix <= 0.02:
		screech_player.stop()
		return
	screech_player.volume_db = screech_volume_db + linear_to_db(_screech_mix)
	screech_player.pitch_scale = lerpf(0.85, 1.15, _screech_mix)


## One small dust puff per wheel, parented to the wheel itself so it rides
## along with suspension travel and steering for free -- no particle texture
## needed, same tiny-box-mesh trick as the confetti burst on a ruined package.
func _build_dust_emitters() -> void:
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 35.0
	process_material.initial_velocity_min = 0.4
	process_material.initial_velocity_max = 1.4
	process_material.gravity = Vector3(0.0, -3.5, 0.0)
	process_material.color = dust_color
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.05
	for wheel: VehicleWheel3D in _wheels:
		var particles := GPUParticles3D.new()
		particles.name = "DustEmitter"
		particles.emitting = false
		particles.amount = 14
		particles.lifetime = 0.55
		particles.explosiveness = 0.0
		particles.process_material = process_material
		particles.draw_pass_1 = mesh
		particles.position = Vector3(0.0, -wheel.wheel_radius, 0.0)
		wheel.add_child(particles)
		_dust_emitters.append(particles)


## Continuous, not a one-shot burst: on while grounded, moving and (mostly)
## on the road, ramping up with skid rather than snapping to full intensity.
func _apply_dust() -> void:
	var speed_factor: float = clampf((vehicle.speed_kmh - dust_min_speed_kmh) / 20.0, 0.0, 1.0)
	for index: int in range(_wheels.size()):
		var wheel: VehicleWheel3D = _wheels[index]
		var particles: GPUParticles3D = _dust_emitters[index]
		var grounded: bool = wheel.is_in_contact()
		var skid: float = (1.0 - wheel.get_skidinfo()) if grounded else 0.0
		var intensity: float = clampf(maxf(speed_factor, skid) if grounded else 0.0, 0.0, 1.0)
		particles.emitting = intensity > 0.05
		particles.amount_ratio = maxf(intensity, 0.15)


func _on_impact(strength: float, impact_position: Vector3) -> void:
	if strength >= 7.0 and vehicle.global_position.distance_to(impact_position) < 5.0:
		# One brief dip, not repeated flashes. It never affects physics or visibility masks.
		_flicker_remaining = impact_flicker_seconds
		impact_player.volume_db = impact_thud_volume_db + linear_to_db(clampf(strength / 15.0, 0.2, 1.0))
		impact_player.pitch_scale = randf_range(0.92, 1.08)
		impact_player.play()


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

extends Node3D
## Presentation only. Native VehicleWheel3D poses come from physics on the host
## and replication on clients; never rotate the wheels a second time here.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
@export var steering_ratio: float = 7.0
@export var headlight_energy: float = 1.6
@export var impact_flicker_seconds: float = 0.16
@export var engine_volume_db: float = WorldMix.ENGINE_DB
@export var impact_thud_volume_db: float = WorldMix.IMPACT_DB
@export var screech_volume_db: float = WorldMix.SCREECH_DB
@export var audio_enabled: bool = true

## Exaggerated exterior lean beyond what the real suspension already does
## (docs/especificaciones-visuales.md #21). Deliberately scoped to
## BodyVisuals only, not CabinInterior/CargoBay -- rotating the seats would
## also rotate every FirstPersonCamera anchored under them, stacking a third
## continuous motion on top of the shake and head bob those already have.
## This reads for passengers glancing out a window, for other players
## watching the van drive by, and for the dev third-person camera (#75);
## the driver's own felt sense of weight is a separate, riskier follow-up.
## BodyVisuals now holds the whole authored truck, interior included, so the
## lean and sink only play for a viewer outside it: from a seat or the cargo
## aisle the walls, rack and seats must stay put against the physics the
## crew and the boxes actually touch.
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

## Reusable across vehicles (docs/tareas-nacho.md #87): everything this
## script needs from its parent is found by node name/pattern anywhere under
## it, not by a fixed path like "CabinInterior/SteeringWheel" -- a second
## vehicle only needs to name its own nodes "SteeringWheel", "BodyVisuals",
## and any number of "*Headlight"/"*TailLight" meshes; it doesn't need the
## same folder structure as vehicle.tscn at all.
@onready var vehicle: VehicleBody3D = get_parent()
@onready var steering_wheel: Node3D = vehicle.find_child("SteeringWheel", true, false)
@onready var body_visuals: Node3D = vehicle.find_child("BodyVisuals", true, false)
var headlights: Array[SpotLight3D] = []
var engine_player: AudioStreamPlayer3D
## The engine in three layers (tareas de Nacho N-401): ticking over, the
## mid-range loop above (engine_player), and revving hard -- crossfaded by a
## simulated rev counter with a gearbox, so each gear change drops the revs
## for a moment. The classic truck shifts slow and low; the agile one revs
## higher and snaps through its gears.
var engine_idle_player: AudioStreamPlayer3D
var engine_high_player: AudioStreamPlayer3D
## What the rev counter reads, and the gear it's in (0 = first).
var engine_rpm: float = 0.0
var engine_gear: int = 0
## Seconds left of the current gear change (throttle lifted, revs falling).
var shift_remaining: float = 0.0
const ENGINE_PROFILES: Dictionary = {
	&"classic": {"idle_rpm": 800.0, "redline_rpm": 4200.0, "shift_up_rpm": 3500.0, "shift_down_rpm": 1500.0,
		"ratios": [3.4, 2.1, 1.45, 1.0], "shift_seconds": 0.38, "pitch": 1.0},
	&"agile": {"idle_rpm": 950.0, "redline_rpm": 5800.0, "shift_up_rpm": 5000.0, "shift_down_rpm": 2100.0,
		"ratios": [3.2, 2.25, 1.65, 1.25, 1.0], "shift_seconds": 0.16, "pitch": 1.14},
}
var impact_player: AudioStreamPlayer3D
var screech_player: AudioStreamPlayer3D
## The horn, created by vehicle.gd once the truck is ready (after this node's
## own _ready), so it's picked up on the first routing pass that finds it.
var horn_player: AudioStreamPlayer3D
var _steering_rest: Basis
var _front_materials: Array[StandardMaterial3D] = []
var _rear_materials: Array[StandardMaterial3D] = []
var _wheels: Array[VehicleWheel3D] = []
var _dust_emitters: Array[GPUParticles3D] = []
## Development-only third-person view (#75): only ever built in a debug
## build (OS.is_debug_build() -- editor runs and non-optimized exports, off
## in a real release export), so it never ships as a real feature for
## players. Toggling only ever changes *this* client's own Viewport.current
## camera, never anything replicated -- safe to leave input-unhandled and
## read directly, same as any other purely local camera swap in this
## project (see Player/FirstPersonCamera's own activate()/deactivate()).
var _dev_camera: Camera3D
var _dev_camera_active: bool = false
var _dev_camera_previous: Camera3D = null
## Every seat camera this vehicle owns (found by walking the tree, not a
## hardcoded list of paths -- so a second vehicle with a different seat
## count doesn't need this file touched at all, see docs/tareas-nacho.md
## item #87). Used only to decide "Interior" vs. "Exterior" audio bus
## routing for this vehicle's own sounds (#80/#81) -- each client checks
## its own active camera independently, no networking involved.
var _seat_cameras: Array[Camera3D] = []
var _last_bus: StringName = &""
var _flicker_remaining: float = 0.0
var _motor_mix: float = 0.0
var _screech_mix: float = 0.0
var _roll: float = 0.0
var _pitch: float = 0.0
var _sink: float = 0.0
## Chase view for a passenger with nothing left to save (spectator_camera.gd).
var spectator_camera: Camera3D
## The seated driver's right-hand IK target (player.gd hangs it on the wheel)
## and where it rests on the rim, and how much it's still pressing the horn
## (tareas de Slatex #11): the character's own hand leaves the rim for the hub
## while the horn sounds. No driver, no hand -- nothing stands in for one.
var _horn_hand: Node3D
var _horn_hand_rest: Vector3
var _horn_press: float = 0.0
const HORN_PRESS_SECONDS: float = 0.45
const HORN_HAND_AT := Vector3(0.03, 0.05, -0.02)


func _ready() -> void:
	# A vehicle whose art is hung at runtime (reference_truck.gd) calls
	# bind_model() once it exists; one authored in the scene binds right here.
	bind_model(steering_wheel,
		vehicle.find_children("*Headlight", "MeshInstance3D", true, false),
		vehicle.find_children("*TailLight", "MeshInstance3D", true, false))
	engine_player = AudioStreamPlayer3D.new()
	engine_player.bus = &"SFX"
	engine_player.name = "EngineAudio"
	engine_player.position = Vector3(0.0, 0.0, -1.4)
	engine_player.stream = preload("res://scripts/presentation/synth_audio.gd").engine_loop()
	engine_player.unit_size = 7.0
	engine_player.max_distance = 45.0
	engine_player.volume_db = -60.0
	add_child(engine_player)
	engine_idle_player = _engine_layer_player("EngineIdleAudio", preload("res://scripts/presentation/synth_audio.gd").engine_idle_loop())
	engine_high_player = _engine_layer_player("EngineHighAudio", preload("res://scripts/presentation/synth_audio.gd").engine_high_loop())
	impact_player = AudioStreamPlayer3D.new()
	impact_player.bus = &"SFX"
	impact_player.name = "ImpactAudio"
	impact_player.stream = preload("res://scripts/presentation/synth_audio.gd").impact_thud()
	impact_player.unit_size = 10.0
	impact_player.max_distance = 60.0
	add_child(impact_player)
	screech_player = AudioStreamPlayer3D.new()
	screech_player.bus = &"SFX"
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
	_collect_seat_cameras(vehicle)
	var effects: Node = preload("res://scripts/presentation/vehicle_effects.gd").new()
	effects.name = "VehicleEffects"
	add_child(effects)
	var clutter: Node = preload("res://scripts/presentation/cargo_clutter.gd").new()
	clutter.name = "CargoClutter"
	add_child(clutter)
	spectator_camera = preload("res://scripts/presentation/spectator_camera.gd").new()
	spectator_camera.vehicle = vehicle
	add_child(spectator_camera)
	if OS.is_debug_build():
		_build_dev_camera()
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.vehicle_impact.connect(_on_impact)
		bus.horn_honked.connect(func(_peer_id: int) -> void: _horn_press = HORN_PRESS_SECONDS)
		bus.run_ended.connect(func(_score: int, _results: Dictionary) -> void:
			if spectator_camera != null and spectator_camera.current:
				spectator_camera.call(&"stop")
			preload("res://scripts/presentation/spectator_camera.gd").orbit_results(vehicle))
	update_presentation(0.0)


func _process(delta: float) -> void:
	update_presentation(delta)


## Points presentation at the vehicle's art: a steering wheel whose local Y
## is its column axis (pointing away from the driver), and the lens meshes
## that glow as head and tail lights. Safe to call again with new art.
func bind_model(wheel: Node3D, front_lenses: Array, rear_lenses: Array) -> void:
	steering_wheel = wheel
	if steering_wheel != null:
		_steering_rest = steering_wheel.basis
	for beam: SpotLight3D in headlights:
		beam.queue_free()
	headlights.clear()
	_front_materials.clear()
	_rear_materials.clear()
	for front: Node in front_lenses:
		var front_mesh: MeshInstance3D = front
		var material: StandardMaterial3D = _unique_material(front_mesh)
		material.emission_enabled = true
		material.emission = Color("ffe2a0")
		_front_materials.append(material)
		# Beams hang in BodyVisuals space, aimed down the road (-Z) whatever
		# axes the lens mesh itself was authored with.
		var beam := SpotLight3D.new()
		beam.name = front_mesh.name + "Beam"
		body_visuals.add_child(beam)
		beam.position = body_visuals.to_local(front_mesh.global_position) + Vector3(0.0, 0.0, -0.07)
		beam.rotation = Vector3(deg_to_rad(-4.0), 0.0, 0.0)
		beam.light_color = Color("ffe9b0")
		beam.spot_range = 24.0
		beam.spot_angle = 32.0
		beam.spot_attenuation = 1.2
		beam.shadow_enabled = false
		headlights.append(beam)
	for rear: Node in rear_lenses:
		var material: StandardMaterial3D = _unique_material(rear as MeshInstance3D)
		material.emission_enabled = true
		material.emission = Color("e2261a")
		_rear_materials.append(material)


func update_presentation(delta: float) -> void:
	if steering_wheel != null:
		steering_wheel.basis = _steering_rest * Basis(Vector3.UP, -vehicle.steering * steering_ratio)
		_update_horn_hand(delta)
	_flicker_remaining = maxf(0.0, _flicker_remaining - delta)
	var running: bool = vehicle.presentation_engine_running
	var flicker: float = 0.3 if _flicker_remaining > 0.0 else 1.0
	# At night, in rain or fog the beams reach further and burn brighter
	# (world_mood.gd, tareas de Nacho #70): there they're how you see the road.
	var boost: float = float(WorldMood.active.get("headlight_boost", 1.0))
	for index: int in range(headlights.size()):
		headlights[index].light_energy = headlight_energy * boost * flicker if running else 0.0
		headlights[index].spot_range = 24.0 * minf(boost, 2.2)
		headlights[index].spot_angle = 32.0 + minf(boost - 1.0, 1.5) * 6.0
		_front_materials[index].emission_energy_multiplier = 0.8 * flicker if running else 0.0
	for material: StandardMaterial3D in _rear_materials:
		material.emission_energy_multiplier = 2.4 if vehicle.presentation_braking else (0.18 if running else 0.0)
	_apply_bus_routing()
	_update_engine(delta, running)
	_update_screech(delta)
	_apply_body_lean(delta)
	_apply_cargo_sink(delta)
	_apply_dust()


func _update_horn_hand(delta: float) -> void:
	_horn_press = maxf(0.0, _horn_press - delta)
	var target := steering_wheel.get_node_or_null(^"DriverHandTargetRight") as Node3D
	if target == null:
		return
	# A new driver brings a new target; its rest is wherever it was placed.
	if not is_instance_valid(_horn_hand) or target != _horn_hand:
		_horn_hand = target
		_horn_hand_rest = target.position
	var reach: float = clampf(_horn_press / HORN_PRESS_SECONDS * 3.0, 0.0, 1.0)
	target.position = _horn_hand_rest.lerp(HORN_HAND_AT, reach)


func _apply_body_lean(delta: float) -> void:
	var speed_factor: float = clampf(vehicle.speed_kmh / maxf(vehicle.maximum_speed_kmh, 1.0), 0.0, 1.0)
	var target_roll: float = -vehicle.steering * speed_factor
	var target_pitch: float = 0.0
	if vehicle.presentation_braking:
		target_pitch = -1.0  # nose dips down under hard braking
	elif vehicle.presentation_engine_running and vehicle.engine_force < -1.0:
		target_pitch = 0.35  # slight nose-up squat while accelerating
	if _viewer_inside():
		target_roll = 0.0
		target_pitch = 0.0
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
	if _viewer_inside():
		target_sink = 0.0
	_sink = move_toward(_sink, target_sink, sink_smooth_speed * delta)
	body_visuals.position.y = -_sink


## Whether this client's own camera is in one of the vehicle's seats or
## standing inside its cab/cargo box. Purely local, like the audio bus pick.
func viewer_inside() -> bool:
	return _viewer_inside()


func _viewer_inside() -> bool:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or camera == _dev_camera:
		return false
	if camera in _seat_cameras:
		return true
	var local: Vector3 = vehicle.to_local(camera.global_position)
	return absf(local.x) < 1.15 and local.y > -0.3 and local.y < 2.7 and local.z > -2.9 and local.z < 4.6


func _engine_layer_player(node_name: String, stream: AudioStream) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.bus = &"SFX"
	player.name = node_name
	player.position = engine_player.position
	player.stream = stream
	player.unit_size = engine_player.unit_size
	player.max_distance = engine_player.max_distance
	player.volume_db = -60.0
	add_child(player)
	return player


func _engine_profile() -> Dictionary:
	return ENGINE_PROFILES.get(StringName(vehicle.get(&"variant_id")), ENGINE_PROFILES[&"classic"])


## Revs from road speed through the current gear (top gear reaches just under
## the shift point at top speed), a flare of revs off the line under load, and
## the gearbox: over shift_up_rpm it changes up -- throttle lifted for
## shift_seconds while the revs fall to the new gear's -- and under
## shift_down_rpm it changes down.
func update_rev_counter(delta: float, speed_kmh: float, load_amount: float) -> void:
	var profile: Dictionary = _engine_profile()
	var ratios: Array = profile.ratios
	var idle: float = profile.idle_rpm
	var redline: float = profile.redline_rpm
	var top_speed: float = maxf(float(vehicle.get(&"maximum_speed_kmh")), 1.0)
	var per_kmh: float = float(profile.shift_up_rpm) * 0.96 / (top_speed * float(ratios[-1]))
	engine_gear = clampi(engine_gear, 0, ratios.size() - 1)
	var from_road: float = absf(speed_kmh) * per_kmh * float(ratios[engine_gear])
	if shift_remaining <= 0.0:
		if from_road > float(profile.shift_up_rpm) and engine_gear < ratios.size() - 1:
			engine_gear += 1
			shift_remaining = float(profile.shift_seconds)
		elif from_road < float(profile.shift_down_rpm) and engine_gear > 0 and speed_kmh > 1.0:
			engine_gear -= 1
			from_road = absf(speed_kmh) * per_kmh * float(ratios[engine_gear])
	shift_remaining = maxf(shift_remaining - delta, 0.0)
	var flare: float = idle + load_amount * (redline - idle) * 0.3
	var target: float = clampf(maxf(from_road, flare), idle, redline)
	if shift_remaining > 0.0:
		# Clutch in: the revs drop to the new gear's quickly, no throttle.
		target = clampf(absf(speed_kmh) * per_kmh * float(ratios[engine_gear]), idle, redline)
		engine_rpm = move_toward(engine_rpm, target, (redline - idle) * delta / maxf(float(profile.shift_seconds), 0.05))
	else:
		engine_rpm = lerpf(engine_rpm if engine_rpm > 0.0 else idle, target, 1.0 - exp(-7.0 * delta))


## 0 at idle, 1 at the redline.
func rev_fraction() -> float:
	var profile: Dictionary = _engine_profile()
	return clampf((engine_rpm - float(profile.idle_rpm)) / (float(profile.redline_rpm) - float(profile.idle_rpm)), 0.0, 1.0)


## Idle fades out as the revs rise, the high layer fades in near the top and
## the mid loop fills between; the weights sum to 1 and each player gets the
## square root of its weight (equal power), so the blend holds its loudness.
func engine_layer_weights() -> Vector3:
	var r: float = rev_fraction()
	var idle: float = 1.0 - smoothstep(0.04, 0.38, r)
	var high: float = smoothstep(0.5, 0.9, r)
	return Vector3(idle, clampf(1.0 - idle - high, 0.0, 1.0), high)


func _update_engine(delta: float, running: bool) -> void:
	var target_mix: float = 1.0 if running and audio_enabled else 0.0
	_motor_mix = move_toward(_motor_mix, target_mix, delta * 4.0)
	var layers: Array[AudioStreamPlayer3D] = [engine_idle_player, engine_player, engine_high_player]
	if target_mix > 0.0 and not engine_player.playing:
		for player: AudioStreamPlayer3D in layers:
			player.play()
	if _motor_mix <= 0.0:
		for player: AudioStreamPlayer3D in layers:
			player.stop()
		engine_rpm = 0.0
		engine_gear = 0
		return
	var speed_kmh: float = vehicle.linear_velocity.length() * 3.6
	var load_amount: float = clampf(absf(vehicle.engine_force) / maxf(vehicle.maximum_engine_force, 1.0), 0.0, 1.0)
	update_rev_counter(delta, speed_kmh, load_amount)
	var profile: Dictionary = _engine_profile()
	var weights: Vector3 = engine_layer_weights()
	# Each layer's pitch follows the revs from its own reference point.
	var references: Array[float] = [float(profile.idle_rpm), lerpf(profile.idle_rpm, profile.redline_rpm, 0.45), float(profile.redline_rpm) * 0.85]
	var on_throttle: float = 0.0 if shift_remaining > 0.0 else load_amount
	for index: int in range(layers.size()):
		var player: AudioStreamPlayer3D = layers[index]
		player.pitch_scale = clampf(engine_rpm / references[index] * float(profile.pitch), 0.5, 2.6)
		player.volume_db = engine_volume_db + linear_to_db(maxf(_motor_mix * sqrt(weights[index]), 0.001)) + on_throttle * 3.0


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


func _collect_seat_cameras(node: Node) -> void:
	if node is Camera3D and node != _dev_camera:
		_seat_cameras.append(node)
	for child: Node in node.get_children():
		_collect_seat_cameras(child)


## Interior vs. exterior (#80/#81): whichever bus applies is whatever this
## client is currently listening through, not a property of the sound
## source -- so this checks the local Viewport's own active camera, not
## anything replicated. Only writes .bus when it actually changes to avoid
## needless AudioServer churn every single frame.
func _apply_bus_routing() -> void:
	var current_camera: Camera3D = get_viewport().get_camera_3d()
	var inside: bool = current_camera != null and current_camera in _seat_cameras
	var target_bus: StringName = &"Interior" if inside else &"Exterior"
	if horn_player == null:
		horn_player = vehicle.get_node_or_null(^"HornAudio") as AudioStreamPlayer3D
		if horn_player != null:
			_last_bus = &""
	if target_bus == _last_bus:
		return
	_last_bus = target_bus
	for player: AudioStreamPlayer3D in [engine_player, engine_idle_player, engine_high_player, impact_player, screech_player, horn_player]:
		if player != null:
			player.bus = target_bus


func _build_dev_camera() -> void:
	_dev_camera = Camera3D.new()
	_dev_camera.name = "DevThirdPersonCamera"
	_dev_camera.current = false
	# Behind and above (forward is local -Z), tilted down to frame the van --
	# fixed offset instead of look_at(), which needs the node in the tree.
	_dev_camera.position = Vector3(0.0, 2.6, 6.5)
	_dev_camera.rotation_degrees = Vector3(-16.0, 180.0, 0.0)
	add_child(_dev_camera)


func _unhandled_input(event: InputEvent) -> void:
	if _dev_camera != null and event.is_action_pressed(&"dev_camera_toggle"):
		_toggle_dev_camera()


func _toggle_dev_camera() -> void:
	if _dev_camera_active:
		_dev_camera.current = false
		if _dev_camera_previous != null and is_instance_valid(_dev_camera_previous):
			_dev_camera_previous.current = true
		_dev_camera_active = false
	else:
		_dev_camera_previous = get_viewport().get_camera_3d()
		_dev_camera.current = true
		_dev_camera_active = true


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

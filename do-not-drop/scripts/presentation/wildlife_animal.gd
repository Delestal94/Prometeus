extends Node3D
## Brings a wildlife model to life by turning its joints (see
## assets/tools/build_wildlife.py for the pivot names): no armature, no
## AnimationPlayer, just a handful of rotations driven by time.
##
## The deer is the exception: it's a rigged, skinned model with keyframed
## animations (Quaternius' "Stag", CC0 -- see assets/README.md), so it plays
## those instead, cross-fading between them by mode.
##
## Roadside animals are pure scenery and run all of this locally on each
## client -- a rabbit hopping off a few frames earlier on one screen than on
## another changes nothing. The deer that crosses the road is steered by
## WildlifeCrossing instead, which only asks for poses (run(), tumble()...).

enum Mode { IDLE, RUN, FREEZE, TUMBLE, FLEE, GONE }

## How close the truck has to come before a shy animal bolts, per species.
const SPOOK_DISTANCE := {&"deer": 22.0, &"rabbit": 14.0, &"frog": 7.0, &"bird": 16.0}
## Beyond this from the camera nothing is animated (it's too far to notice).
const ANIMATE_DISTANCE: float = 80.0
## Roadside animals only: seconds of fleeing before they're out of sight.
const FLEE_SECONDS := {&"deer": 3.5, &"rabbit": 2.2, &"frog": 1.4, &"bird": 3.0}

var species: StringName = &""
var mode: Mode = Mode.IDLE
## Set by WildlifeCrossing: it moves this animal, so no self-fleeing.
var steered: bool = false

var _time: float = 0.0
var _phase: float = 0.0
var _joints: Dictionary = {}
var _rest: Dictionary = {}
var _body: Node3D
var _body_rest: Transform3D
var _flee_direction: Vector3 = Vector3.ZERO
var _flee_time: float = 0.0
var _hop_timer: float = 0.0
var _hop_time: float = -1.0
## Rigged deer only.
var _animator: AnimationPlayer
var _current_animation: StringName = &""
var _idle_timer: float = 0.0

## The Stag is authored ~5 m tall facing +Z; a deer here stands ~1.2 m at the
## shoulder facing -Z like every other model.
const RIGGED_SCALE: float = 0.4
const RIGGED_LOOPS: Array[StringName] = [&"Gallop", &"Walk", &"Idle", &"Idle_2", &"Idle_Headlow", &"Eating"]
## Grazing routine: mostly eating, sometimes head-up looking around.
const RIGGED_IDLES: Array[StringName] = [&"Eating", &"Eating", &"Idle", &"Idle_Headlow", &"Idle_2"]
const RIGGED_BLEND: float = 0.25


func _ready() -> void:
	_animator = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animator != null:
		_setup_rigged()
		return
	for candidate: StringName in [&"Deer", &"Rabbit", &"Frog", &"Bird"]:
		var found := find_child(String(candidate), true, false) as Node3D
		if found != null:
			species = StringName(String(candidate).to_lower())
			_body = found
			_body_rest = found.transform
			break
	for joint_name: String in ["Leg_FL", "Leg_FR", "Leg_BL", "Leg_BR",
			"Leg_FL_Lower", "Leg_FR_Lower", "Leg_BL_Lower", "Leg_BR_Lower", "Neck", "Head", "Tail",
			"Legs_Front", "Legs_Back", "Ears", "Throat", "Wing_L", "Wing_R"]:
		var joint := find_child(joint_name, true, false) as Node3D
		if joint != null:
			_joints[joint_name] = joint
			_rest[joint_name] = joint.transform
	# Every animal on its own clock, so a field of rabbits doesn't twitch in sync.
	var seed_value: int = hash(Vector3i(global_position.round()))
	_phase = float(absi(seed_value) % 1000) / 1000.0 * TAU
	_hop_timer = 1.5 + float(absi(seed_value) % 400) / 100.0


func _setup_rigged() -> void:
	species = &"deer"
	var fix := Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * RIGGED_SCALE), Vector3.ZERO)
	for child: Node in get_children():
		if child is Node3D:
			(child as Node3D).transform = fix * (child as Node3D).transform
	for animation_name: StringName in RIGGED_LOOPS:
		if _animator.has_animation(animation_name):
			_animator.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	var seed_value: int = hash(Vector3i(global_position.round()))
	_phase = float(absi(seed_value) % 1000) / 1000.0
	_play(RIGGED_IDLES[absi(seed_value) % RIGGED_IDLES.size()])
	# Start each deer somewhere in its loop, so a herd isn't in lockstep.
	_animator.seek(_phase * _animator.current_animation_length, true)
	_idle_timer = 4.0 + _phase * 6.0


func _play(animation_name: StringName, speed: float = 1.0) -> void:
	if _animator == null or not _animator.has_animation(animation_name):
		return
	_animator.speed_scale = speed
	if animation_name != _current_animation:
		_current_animation = animation_name
		_animator.play(animation_name, RIGGED_BLEND)


func run() -> void:
	mode = Mode.RUN


func freeze_in_headlights() -> void:
	mode = Mode.FREEZE


func tumble() -> void:
	mode = Mode.TUMBLE


func idle() -> void:
	mode = Mode.IDLE


func _process(delta: float) -> void:
	if mode == Mode.GONE or (_body == null and _animator == null):
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var near: bool = camera == null or camera.global_position.distance_squared_to(global_position) <= ANIMATE_DISTANCE * ANIMATE_DISTANCE
	if _animator != null:
		_animator.active = near  # A skinned deer nobody can see costs nothing.
	if not near:
		return
	_time += delta
	if not steered:
		_update_roadside(delta)
	if _animator != null:
		_animate_rigged(delta)
		return
	match species:
		&"deer":
			_pose_deer()
		&"rabbit":
			_pose_hopper(delta, 0.18, 0.5)
		&"frog":
			_pose_hopper(delta, 0.12, 0.35)
		&"bird":
			_pose_bird()


## Roadside behaviour: idle until the truck comes close, then flee away from
## it and disappear into the scenery.
func _update_roadside(delta: float) -> void:
	if mode == Mode.FLEE:
		_flee_time += delta
		var speed: float = {&"deer": 8.0, &"rabbit": 5.0, &"frog": 1.6, &"bird": 5.5}.get(species, 4.0)
		global_position += _flee_direction * speed * delta
		if species == &"bird":
			global_position.y += 2.5 * delta
		if _flee_time > float(FLEE_SECONDS.get(species, 2.0)):
			mode = Mode.GONE
			visible = false
		return
	var vehicle := get_tree().get_first_node_in_group(&"vehicle") as Node3D
	if vehicle == null:
		return
	var away: Vector3 = global_position - vehicle.global_position
	away.y = 0.0
	if away.length() < float(SPOOK_DISTANCE.get(species, 12.0)):
		mode = Mode.FLEE
		_flee_direction = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		look_at(global_position + _flee_direction, Vector3.UP)  # Front (-Z) toward the escape.


func _joint(joint_name: String) -> Node3D:
	return _joints.get(joint_name) as Node3D


func _turn(joint_name: String, euler: Vector3) -> void:
	var joint := _joint(joint_name)
	if joint != null:
		joint.transform = (_rest[joint_name] as Transform3D) * Transform3D(Basis.from_euler(euler), Vector3.ZERO)


func _animate_rigged(delta: float) -> void:
	match mode:
		Mode.RUN, Mode.FLEE:
			_play(&"Gallop", 1.25)
		Mode.FREEZE:
			# Head up, barely moving: the headlights stare.
			_play(&"Idle", 0.2)
		Mode.TUMBLE:
			_play(&"Idle_HitReact_Left" if _phase < 0.5 else &"Idle_HitReact_Right")
		_:
			_idle_timer -= delta
			if _idle_timer <= 0.0 or not _current_animation in RIGGED_IDLES:
				_idle_timer = 5.0 + fmod(_time * 1.7, 6.0)
				_play(RIGGED_IDLES[int(_time * 3.0) % RIGGED_IDLES.size()])


## Legs in trot order: diagonal pairs move together (front-left with
## back-right), the way a deer covers ground at a run.
const DEER_LEG_PHASE := {"Leg_FL": 0.0, "Leg_BR": 0.0, "Leg_FR": PI, "Leg_BL": PI}


func _pose_deer() -> void:
	var t: float = _time + _phase
	var body := _body_rest
	if mode == Mode.RUN or mode == Mode.FLEE:
		var stride: float = t * TAU * 2.2
		for leg: String in DEER_LEG_PHASE:
			var p: float = stride + float(DEER_LEG_PHASE[leg])
			var front: bool = leg.begins_with("Leg_F")
			# Upper leg swings from shoulder/hip; the lower leg folds up only
			# while the hoof travels forward through the air, then straightens
			# to take the weight.
			_turn(leg, Vector3(sin(p) * (0.55 if front else 0.48), 0.0, 0.0))
			_turn(leg + "_Lower", Vector3(-maxf(cos(p), 0.0) * (0.95 if front else 0.75), 0.0, 0.0))
		_turn("Neck", Vector3(-0.22 + sin(stride * 2.0) * 0.04, 0.0, 0.0))
		_turn("Head", Vector3(0.18, 0.0, 0.0))
		_turn("Tail", Vector3(0.7, 0.0, 0.0))  # White flag up: a running deer.
		body.origin.y += absf(cos(stride)) * 0.045
		body.basis = body.basis * Basis(Vector3.RIGHT, sin(stride * 2.0) * 0.02)
	elif mode == Mode.TUMBLE:
		var index: float = 0.0
		for leg: String in DEER_LEG_PHASE:
			index += 1.0
			_turn(leg, Vector3(sin(t * 13.0 + index * 1.7) * 0.6, 0.0, 0.0))
			_turn(leg + "_Lower", Vector3(-0.6 - sin(t * 11.0 + index) * 0.3, 0.0, 0.0))
		_turn("Neck", Vector3(0.3, 0.0, sin(t * 9.0) * 0.25))
		_turn("Head", Vector3.ZERO)
	else:
		for leg: String in DEER_LEG_PHASE:
			_turn(leg, Vector3.ZERO)
			_turn(leg + "_Lower", Vector3.ZERO)
		if mode == Mode.FREEZE:
			# Head up, dead still, staring into the headlights.
			_turn("Neck", Vector3(0.12, 0.0, 0.0))
			_turn("Head", Vector3(0.1, 0.0, 0.0))
			_turn("Tail", Vector3(0.45, 0.0, 0.0))
		else:
			# Grazing: a long spell with the muzzle in the grass, then up to
			# look around (and chew), then back down.
			var cycle: float = fmod(t, 10.0)
			var down: float = smoothstep(0.0, 1.4, cycle) * (1.0 - smoothstep(6.0, 7.4, cycle))
			var chew: float = sin(t * 9.0) * 0.03 * (1.0 - down)
			_turn("Neck", Vector3(-1.75 * down, sin(t * 0.6) * 0.3 * (1.0 - down), 0.0))
			_turn("Head", Vector3(-0.95 * down + chew, 0.0, 0.0))
			_turn("Tail", Vector3(0.0, sin(t * 8.0) * 0.35 * float(fmod(t, 5.0) < 0.5), 0.0))
	_body.transform = body


## Rabbit and frog: sit still with small twitches, hop every few seconds,
## and hop repeatedly (further) when fleeing.
func _pose_hopper(delta: float, hop_height: float, hop_seconds: float) -> void:
	var t: float = _time + _phase
	var fleeing: bool = mode == Mode.FLEE or mode == Mode.RUN
	_hop_timer -= delta
	if _hop_time < 0.0 and (fleeing or _hop_timer <= 0.0):
		_hop_time = 0.0
		_hop_timer = 2.5 + fmod(t * 3.7, 3.0)
	var body := _body_rest
	var legs: float = 0.0
	if _hop_time >= 0.0:
		_hop_time += delta
		var k: float = clampf(_hop_time / hop_seconds, 0.0, 1.0)
		body.origin.y += sin(k * PI) * hop_height * (1.6 if fleeing else 1.0)
		body.basis = body.basis * Basis(Vector3.RIGHT, (0.5 - k) * 0.5)
		legs = sin(k * PI)
		if k >= 1.0:
			_hop_time = -1.0
	_turn("Legs_Back", Vector3(-legs * 0.9, 0.0, 0.0))
	_turn("Legs_Front", Vector3(legs * 0.6, 0.0, 0.0))
	_turn("Ears", Vector3(-legs * 0.5 + sin(t * 1.3) * 0.05, 0.0, sin(t * 5.0) * 0.08 * float(fmod(t, 3.0) < 0.4)))
	var throat := _joint("Throat")
	if throat != null:
		throat.transform = (_rest["Throat"] as Transform3D).scaled_local(Vector3.ONE * (1.0 + maxf(sin(t * 5.0), 0.0) * 0.6))
	_turn("Tail", Vector3(0.0, sin(t * 9.0) * 0.3, 0.0))
	_body.transform = body


func _pose_bird() -> void:
	var t: float = _time + _phase
	if mode == Mode.FLEE or mode == Mode.RUN:
		var flap: float = sin(t * TAU * 7.0)
		_turn("Wing_L", Vector3(0.0, 0.0, -0.9 - flap * 0.9))
		_turn("Wing_R", Vector3(0.0, 0.0, 0.9 + flap * 0.9))
		_turn("Tail", Vector3(-0.3, 0.0, 0.0))
		return
	# Hop-and-peck on the ground.
	var peck: float = maxf(sin(t * 2.1) * sin(t * 5.3), 0.0)
	_turn("Head", Vector3(-peck * 0.9, sin(t * 0.9) * 0.4, 0.0))
	_turn("Tail", Vector3(sin(t * 3.0) * 0.15, 0.0, 0.0))
	_turn("Wing_L", Vector3.ZERO)
	_turn("Wing_R", Vector3.ZERO)

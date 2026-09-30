extends Node
## Running (N-115): hold "sprint" and the crew member covers ground faster, at the
## price of whatever they carry. Player owns the replicated state (anim_state
## says Run for every peer, locomotion_speed the pace); this child owns the
## speeds, the footfalls, and the two bets of running with a box:
##
## - every step shakes the box: the owner reports it, the HOST applies a small
##   hit through the usual damage road (DeliveryPackage.apply_run_jolt(), which
##   each trap feels its own way -- ITrapBehavior.on_carried_step());
## - a step can also trip the runner: the owner reports how bad the ground is
##   (a sharp turn, a slope, gravel, a collision), the HOST rolls it against a
##   seed and, on a trip, the box drops with an impact (DeliveryPackage.
##   stumble_drop()). The roll is a pure function of (seed, step number, hazard):
##   the same on every peer that counts the same steps.
##
## Nothing runs seated, driving, or on top of a truck that is moving.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const TutorialData = preload("res://scripts/ui/tutorial_catalog.gd")
const RunShake = preload("res://scripts/gameplay/package/package_run_shake.gd")
const SynthAudioSteps = preload("res://scripts/presentation/synth_audio_steps.gd")

## Ground speeds, m/s. Walking is Player.WALK_SPEED (3.6).
const RUN_SPEED: float = 6.0
## With a box in the arms; Growing weight's box (heavier by the second) only lets you jog.
const CARRY_RUN_SPEED: float = 5.0
const HEAVY_RUN_SPEED: float = 4.2
const HEAVY_TRAP: StringName = &"growing_weight"
## Ground covered per footfall while running, m (a step every ~0.4 s at full speed).
const STEP_DISTANCE: float = 2.0
## Under this pace nobody is running, whatever the button says.
const MIN_STEP_SPEED: float = 3.0
## First person: the view opens a little and the walk bob grows.
const FOV_BONUS: float = 4.0
const BOB_SCALE: float = 2.6
const BLEND_SPEED: float = 4.0
## After a trip: no running for a while, and a stagger.
const STUMBLE_LOCKOUT: float = 1.5
const STAGGER_SECONDS: float = 0.5
const STAGGER_SPEED_SCALE: float = 0.5
## How hard the box is thrown ahead of the runner when it drops, m/s.
const STUMBLE_PUSH: float = 1.8
## Chance to trip per step: a floor of bad luck, plus the terrain's share.
const BASE_STUMBLE_CHANCE: float = 0.008
const HAZARD_STUMBLE_CHANCE: float = 0.14
## Hazard terms (0..1 each, summed and clamped): look turn rate, rad/s;
## floor slope, degrees; the collision with anything in the way; the ground.
const TURN_HAZARD_FROM: float = 1.6
const TURN_HAZARD_FULL: float = 3.6
const SLOPE_HAZARD_FROM: float = 9.0
const SLOPE_HAZARD_FULL: float = 24.0
const CRASH_HAZARD: float = 0.8
const VERGE_HAZARD: float = 0.2
## strings of the first-time tip live in tutorial_catalog.gd.
const TIP_ID: StringName = &"sprint_carry"
const FOOTSTEP_PITCH_SPREAD: float = 0.06

## Set by tests to fix the trip seed; 0 lets the session's seed decide.
var seed_override: int = 0
## Owner: running this tick. Everyone else: the owner's anim_state says Run.
var running: bool = false
## 0..1 ease of `running`, for the view bob.
var run_blend: float = 0.0
## Footfalls counted since the level began (tests read it).
var steps_taken: int = 0

var player: Player
var _stride: float = 0.0
var _lockout: float = 0.0
var _stagger: float = 0.0
## Host: steps reported by the owner with a box in the arms, the number the roll uses.
var _host_steps: int = 0
var _solo_seed: int = 0
var _footstep_player: AudioStreamPlayer3D
var _was_running_with_box: bool = false
## The physics tick ground_speed() last decided in: a tick the controller
## skipped (a menu is open) is not a tick spent running.
var _decided_tick: int = -1


func _init() -> void:
	name = &"Sprint"  # The same node path on every peer, or the RPCs below don't find it.


func _ready() -> void:
	player = get_parent() as Player
	_solo_seed = randi() | 1


## The view opens while running, and the walk bob grows with the run.
func fov_bonus() -> float:
	return FOV_BONUS if running else 0.0


func bob_scale() -> float:
	return lerpf(1.0, BOB_SCALE, run_blend)


# --- Speed and eligibility (owner) ------------------------------------------------


## Ground speed for a package in the arms, running or not.
static func speed_for(is_running: bool, package: DeliveryPackage) -> float:
	if not is_running:
		return Player.WALK_SPEED
	if package == null:
		return RUN_SPEED
	return HEAVY_RUN_SPEED if is_heavy(package) else CARRY_RUN_SPEED


static func is_heavy(package: DeliveryPackage) -> bool:
	return package != null and package.trap_definition != null \
			and StringName(package.trap_definition.get(&"id")) == HEAVY_TRAP


## True while the crew member is in a state that allows running at all.
func can_run() -> bool:
	if player == null or player._seated or not player.seat_node_path.is_empty():
		return false
	return not on_moving_truck()


## Standing on a truck that is going somewhere: the floor is not theirs to run on.
func on_moving_truck() -> bool:
	if not player._riding:
		return false
	var vehicle: Node3D = player._find_vehicle()
	return vehicle is RigidBody3D and (vehicle as RigidBody3D).linear_velocity.length() > Player.RIDING_SPEED


## Owner: does this tick's input ask for a run that is allowed?
func wants_run(input_vector: Vector2) -> bool:
	if _lockout > 0.0 or input_vector.length() < 0.1 or not can_run():
		return false
	return Input.is_action_pressed(&"sprint")


## Owner, once per physics tick before moving: decides `running` and returns the
## ground speed to walk or run at.
func ground_speed(input_vector: Vector2) -> float:
	running = wants_run(input_vector)
	_decided_tick = Engine.get_physics_frames()
	var speed: float = speed_for(running, player.carried_package)
	if _stagger > 0.0:
		speed *= STAGGER_SPEED_SCALE
	var running_with_box: bool = running and player.carried_package != null
	if running_with_box and not _was_running_with_box:
		_show_first_run_tip()
	_was_running_with_box = running_with_box
	return speed


# --- Every peer: footfalls -------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_lockout = maxf(_lockout - delta, 0.0)
	_stagger = maxf(_stagger - delta, 0.0)
	var local: bool = player.is_local()
	if not local:
		running = player.anim_state == Player.ANIM_RUN and player.seat_node_path.is_empty()
	elif _decided_tick != Engine.get_physics_frames() or not can_run():
		running = false
	run_blend = move_toward(run_blend, 1.0 if running else 0.0, BLEND_SPEED * delta)
	var pace: float = player.locomotion_speed
	if not running or pace < MIN_STEP_SPEED or (local and not player.is_on_floor()):
		return
	_stride += pace * delta
	while _stride >= STEP_DISTANCE:
		_stride -= STEP_DISTANCE
		_on_step()


func _on_step() -> void:
	steps_taken += 1
	_play_footstep()
	var box: DeliveryPackage = player.carried_package if is_instance_valid(player.carried_package) else null
	if box == null:
		return
	# Everyone sees the box bounce in the arms; only the owner reports it.
	RunShake.bounce(box, steps_taken)
	if player.is_local():
		rpc_id(1, &"submit_run_step", measure_hazard())


func _play_footstep() -> void:
	if _footstep_player == null:
		_footstep_player = AudioStreamPlayer3D.new()
		_footstep_player.name = "Footstep"
		_footstep_player.bus = &"SFX"
		_footstep_player.stream = SynthAudioSteps.footstep()
		_footstep_player.volume_db = WorldMix.FOOTSTEP_DB
		_footstep_player.unit_size = 5.0
		_footstep_player.max_distance = 25.0
		player.add_child(_footstep_player)  # In 3D space: this node is not a Node3D.
	_footstep_player.pitch_scale = 1.0 + randf_range(-FOOTSTEP_PITCH_SPREAD, FOOTSTEP_PITCH_SPREAD)
	_footstep_player.play()


# --- Owner: how bad is the ground under this step ---------------------------------------------


## 0 (a clear straight road) .. 1 (everything at once): what the owner tells the
## host about this step. The host clamps it, it is a trust-the-client input like
## the rest of on-foot movement.
func measure_hazard() -> float:
	var turning: float = (player.turn_rate - TURN_HAZARD_FROM) / (TURN_HAZARD_FULL - TURN_HAZARD_FROM)
	var hazard: float = clampf(turning, 0.0, 1.0) * 0.5
	if player.is_on_floor():
		var slope: float = rad_to_deg(player.get_floor_angle())
		hazard += clampf((slope - SLOPE_HAZARD_FROM) / (SLOPE_HAZARD_FULL - SLOPE_HAZARD_FROM), 0.0, 1.0) * 0.5
		hazard += ground_roughness() * 0.5
	for index: int in player.get_slide_collision_count():
		if player.get_slide_collision(index).get_normal().y < 0.5:
			hazard += CRASH_HAZARD
			break
	return clampf(hazard, 0.0, 1.0)


## The route says how rough the ground is under the runner (gravel, the verge);
## anywhere else (the depot, the yard) it is flat.
func ground_roughness() -> float:
	var route: Node = player.get_tree().get_first_node_in_group(&"route") if player.is_inside_tree() else null
	if route == null or not route.has_method(&"ground_roughness"):
		return 0.0
	return float(route.call(&"ground_roughness", player.global_position))


# --- Host: the shaking and the trip -----------------------------------------------------------


## The trip's dice: a number in [0, 1) that only depends on the seed and the step.
static func stumble_roll(seed_value: int, step: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, step])
	return rng.randf()


static func stumble_chance(hazard: float) -> float:
	return BASE_STUMBLE_CHANCE + clampf(hazard, 0.0, 1.0) * HAZARD_STUMBLE_CHANCE


## The session's seed for this runner: the same on every peer of a seeded
## session, a per-runner one playing solo.
func run_seed() -> int:
	if seed_override != 0:
		return seed_override
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	var world_seed: int = int(network.get(&"world_seed")) if network != null else 0
	return hash([world_seed, player.get_multiplayer_authority()]) if world_seed != 0 else _solo_seed


func would_stumble(step: int, hazard: float) -> bool:
	return stumble_roll(run_seed(), step) < stumble_chance(hazard)


## The owner reports a running step with a box in their arms. Only the host
## acts on it, and only for the box this player is really carrying.
@rpc("any_peer", "call_local", "reliable")
func submit_run_step(hazard: float) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != player.get_multiplayer_authority():
		return
	host_run_step(hazard)


## The host's half of a step (also what tests call). Returns true when it tripped.
func host_run_step(hazard: float) -> bool:
	var box: DeliveryPackage = player.carried_package
	if not is_instance_valid(box) or box.carrier != player or not box.is_held:
		return false
	RunShake.jolt(box)
	_host_steps += 1
	if not would_stumble(_host_steps, hazard):
		return false
	var ahead: Vector3 = -player.global_basis.z
	ahead.y = 0.0
	var push: Vector3 = ahead.normalized() * STUMBLE_PUSH + Vector3.UP * 0.6
	RunShake.stumble(box, push)
	rpc(&"play_stumble")
	return true


## The trip, on every peer: the runner staggers and cannot run for a moment.
@rpc("any_peer", "call_local", "reliable")
func play_stumble() -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	_lockout = STUMBLE_LOCKOUT
	_stagger = STAGGER_SECONDS
	running = false
	player.locomotion_speed = minf(player.locomotion_speed, Player.WALK_SPEED)
	if player.is_local():
		player.animator.play_one_shot(Player.ANIM_JUMP, 420)
	player._flinch_time = 0.32


# --- Tip ---------------------------------------------------------------------------------------


func _show_first_run_tip() -> void:
	var profile: Node = get_node_or_null(^"/root/UnlockManager")
	if profile == null or not bool(profile.call(&"mark_tip_seen", TIP_ID)):
		return
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.emit_signal(&"tutorial_tip_requested", TutorialData.sprint_carry_tip())

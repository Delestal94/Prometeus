extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_player_sprint.gd
##
## Running (N-115, player/player_sprint.gd, player_animator.gd):
## - the sprint action exists (Shift / left-stick click) and is rebindable in
##   GameSettings like the rest;
## - speeds: 6 m/s on foot, 5 with a box, a jog (4.2) with a Growing weight box,
##   3.6 walking; nobody runs seated, driving or on top of a moving truck;
## - every step shakes the box through the usual damage road (package_run_shake.gd
##   -> ITrapBehavior.on_carried_step): Fragile loses integrity, Balance leans,
##   Liquid spills, Noisy gets agitated, Explosive burns fuse, Hostile gets
##   angry, Growing weight ignores it; walking costs nothing;
## - the trip is a pure function of (seed, step, hazard): the same on every
##   peer with the same seed, more likely on bad ground; on the host the box
##   ends up on the floor, no longer held, having taken a hit;
## - the first run with a box shows the tip once; the box bounces (feedback);
## - the host gates step reports (owner only, not seated/still, token bucket, NaN hazard);
##   a remote jog (Walk above walking pace) counts as running;
## - PlayerAnimator: Run picked with hysteresis, plays "Run" if the library has
##   it and Walk sped up if not; the other peer sees the same state
##   (anim_state / locomotion_speed are replicated) and hears the footfalls;
## - the real character (sm_char_player_rounded.glb) ships its own looping "Run"
##   clip (N-115.3), played at speed / 6 m/s, never the Walk fallback.

const Sprint = preload("res://scripts/gameplay/player/player_sprint.gd")
const RunShake = preload("res://scripts/gameplay/package/package_run_shake.gd")
const SynthAudioSteps = preload("res://modules/synth_audio/synth_audio_steps.gd")
const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const TRAP_KINDS: Array[String] = ["fragile", "balance", "liquid", "noisy", "explosive", "hostile", "growing_weight"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_test_input_and_settings()
	_test_speeds()
	await _test_every_trap_feels_the_steps()
	_test_trip_is_deterministic()
	# Building level_base's route takes 4-10 s a time (more on a CI runner); loading it
	# for every section put this test at 60-117 s against CI's 120 s limit (issue #291).
	# Two levels: the driver seat leaves the player seated for good, so it gets its own.
	var level: Node = await _load_level()
	await _test_no_running_seated_or_on_a_moving_truck(level)
	await _unload_level(level)
	# The rest share one level, in an order where each leaves what the next needs:
	# a fresh player for the animation, a box that never bounced for the tip's creak,
	# the remote peers while the box is held, and the trip (it drops the box) last.
	level = await _load_level()
	await _test_animator_picks_run_or_the_fallback(level)
	_test_character_library_has_a_looping_run(level)
	await _test_first_run_tip_and_box_bounce(level)
	await _test_other_peer_sees_the_run(level)
	await _test_remote_jog_and_the_hosts_step_bucket(level)
	_test_trip_drops_the_box(level)
	await _unload_level(level)
	if _failures == 0:
		print("PASS: sprint speeds, no running seated/driving/on a moving truck, per-trap step shaking,"
				+ " deterministic trip, tip, Run or Walk fallback with hysteresis, and the remote peer's run")
	quit(_failures)


# --- Input ---------------------------------------------------------------------------------


func _test_input_and_settings() -> void:
	_expect(InputMap.has_action(&"sprint"), "The sprint action exists in the Input Map")
	var has_key: bool = false
	var has_stick: bool = false
	for event: InputEvent in InputMap.action_get_events(&"sprint"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_SHIFT:
			has_key = true
		if event is InputEventJoypadButton \
				and (event as InputEventJoypadButton).button_index == JOY_BUTTON_LEFT_STICK:
			has_stick = true
	_expect(has_key, "Sprint defaults to Shift on the keyboard")
	_expect(has_stick, "Sprint defaults to the left-stick click on a gamepad")
	var settings: Node = root.get_node(^"/root/GameSettings")
	_expect(&"sprint" in settings.REBINDABLE_ACTIONS, "Sprint is one of the rebindable actions in Options")
	var before: Dictionary = settings.key_bindings.duplicate()
	settings.bind_key(&"sprint", KEY_CTRL)
	var rebound: bool = false
	for event: InputEvent in InputMap.action_get_events(&"sprint"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_CTRL:
			rebound = true
	_expect(rebound and settings.binding_label(&"sprint") == OS.get_keycode_string(KEY_CTRL),
			"Rebinding sprint reaches the Input Map at once (got %s)" % settings.binding_label(&"sprint"))
	settings.key_bindings = before
	settings.bind_key(&"sprint", KEY_SHIFT)


# --- Speeds --------------------------------------------------------------------------------


func _test_speeds() -> void:
	var box: DeliveryPackage = _package("fragile")
	var heavy: DeliveryPackage = _package("growing_weight")
	var walking: float = Sprint.speed_for(false, null)
	var on_foot: float = Sprint.speed_for(true, null)
	var with_box: float = Sprint.speed_for(true, box)
	var with_heavy: float = Sprint.speed_for(true, heavy)
	_expect(is_equal_approx(walking, Player.WALK_SPEED), "Walking stays at 3.6 m/s (got %s)" % walking)
	_expect(is_equal_approx(on_foot, 6.0), "Running on foot is 6 m/s (got %s)" % on_foot)
	_expect(is_equal_approx(with_box, 5.0), "Running with a box is 5 m/s (got %s)" % with_box)
	_expect(is_equal_approx(with_heavy, 4.2), "Running with a Growing weight box jogs at 4.2 m/s (got %s)" % with_heavy)
	_expect(with_heavy > walking and with_heavy < with_box, "The jog is faster than walking, slower than a box run")
	box.free()
	heavy.free()


func _test_no_running_seated_or_on_a_moving_truck(level: Node) -> void:
	var player: Player = level.local_player
	var sprint: Node = player.get_node(^"Sprint")
	var forward := Vector2(0.0, -1.0)
	Input.action_press(&"sprint")
	await physics_frame
	_expect(sprint.wants_run(forward), "Holding sprint while walking on foot is a run")
	_expect(not sprint.wants_run(Vector2.ZERO), "Sprint with no movement input is not a run")
	var pace: float = sprint.ground_speed(forward)
	_expect(is_equal_approx(pace, 6.0), "On foot the ground speed is 6 m/s (got %s)" % pace)
	var vehicle: RigidBody3D = level.get_node("World/Vehicle")
	player._riding = true
	vehicle.linear_velocity = Vector3(0.0, 0.0, 6.0)
	_expect(not sprint.wants_run(forward), "Nobody runs on top of a truck that is moving")
	vehicle.linear_velocity = Vector3.ZERO
	_expect(sprint.wants_run(forward), "...but a parked truck's bay is fine to run in")
	player._riding = false
	player._seated = true
	_expect(not sprint.wants_run(forward), "Nobody runs seated")
	player._seated = false
	var driver_seat: Node = vehicle.get_node("CabinInterior/DriverEyePoint/InteractionArea")
	vehicle.call(&"set_door_open", &"cab_left", true)
	driver_seat.interact(player)
	_expect(not player.seat_node_path.is_empty() and not sprint.wants_run(forward), "Nobody runs while driving")


# --- Steps shake the box -----------------------------------------------------------------------


func _test_every_trap_feels_the_steps() -> void:
	root.get_node(^"/root/RunManager").call(&"start_run")
	for kind: String in TRAP_KINDS:
		var box: DeliveryPackage = _package(kind)
		root.add_child(box)
		await physics_frame
		var before: float = box.integrity
		for i: int in 10:
			RunShake.jolt(box)
		var lost: float = before - box.integrity
		var behavior: Resource = box.trap_behavior
		match kind:
			"fragile":
				_expect(lost > 5.0, "Ten running steps hurt a Fragile box (lost %.1f)" % lost)
			"balance":
				behavior.on_physics_process(box, 0.016, {})
				_expect(behavior.tilt_degrees > 5.0,
						"Running rocks a Balance box: it leans (got %.1f deg)" % behavior.tilt_degrees)
			"liquid":
				_expect(behavior.spill_amount > 10.0, "Running sloshes a Liquid box (%.1f)" % behavior.spill_amount)
			"noisy":
				_expect(behavior.agitation > 20.0, "Running riles a Noisy box (agitation %.1f)" % behavior.agitation)
			"explosive":
				_expect(behavior.seconds_left < 14.0,
						"Running burns an Explosive box's fuse (%.2f s left)" % behavior.seconds_left)
			"hostile":
				_expect(behavior.aggression > 5.0, "Running irritates a Hostile box (got %.1f)" % behavior.aggression)
			"growing_weight":
				_expect(is_zero_approx(lost), "Growing weight ignores the shaking, it costs speed (lost %.1f)" % lost)
		box.free()
	# Walking is no steps at all: a fresh box next to one that ran loses nothing.
	var walked: DeliveryPackage = _package("fragile")
	root.add_child(walked)
	var runner: DeliveryPackage = _package("fragile")
	root.add_child(runner)
	var padded: DeliveryPackage = _package("fragile")
	padded.impact_absorption = 0.5
	root.add_child(padded)
	await physics_frame
	for i: int in 10:
		RunShake.jolt(runner)
		RunShake.jolt(padded)
	_expect(is_equal_approx(walked.integrity, walked.integrity_max) and runner.integrity < walked.integrity,
			"Running with a box damages it more than walking (walked %.1f, ran %.1f)" % [
			walked.integrity, runner.integrity])
	_expect(padded.integrity > runner.integrity,
			"Padding on the box softens the steps (%.1f vs %.1f)" % [padded.integrity, runner.integrity])
	walked.free()
	runner.free()
	padded.free()
	root.get_node(^"/root/RunManager").call(&"reset_run")


# --- The trip -----------------------------------------------------------------------------------


func _test_trip_is_deterministic() -> void:
	var first: Array[bool] = []
	var second: Array[bool] = []
	var other: Array[bool] = []
	for step: int in 400:
		first.append(Sprint.stumble_roll(1234, step) < Sprint.stumble_chance(1.0))
		second.append(Sprint.stumble_roll(1234, step) < Sprint.stumble_chance(1.0))
		other.append(Sprint.stumble_roll(999, step) < Sprint.stumble_chance(1.0))
	_expect(first == second, "The same seed trips at the same steps every time")
	_expect(other != first, "A different seed trips at different steps")
	var bad_ground: int = 0
	var clear_ground: int = 0
	for step: int in 4000:
		var roll: float = Sprint.stumble_roll(77, step)
		bad_ground += int(roll < Sprint.stumble_chance(1.0))
		clear_ground += int(roll < Sprint.stumble_chance(0.0))
	_expect(bad_ground > clear_ground * 4,
			"Bad ground trips far more than a clear road (%d vs %d in 4000 steps)" % [bad_ground, clear_ground])
	_expect(clear_ground > 0 and clear_ground < 120, "Even a clear road has a small chance (%d in 4000)" % clear_ground)


## On the host the trip drops the box. Runs last on the shared level: the trip locks
## the runner out of running for STUMBLE_LOCKOUT and leaves the box loose.
func _test_trip_drops_the_box(level: Node) -> void:
	root.get_node(^"/root/RunManager").call(&"start_run")
	var player: Player = level.local_player
	var package: DeliveryPackage = level.get_node("World/Package")
	if player.carried_package != package:  # The tip's section already picked it up.
		package.get_node("InteractionArea").interact(player)
	_expect(player.carried_package == package and package.is_held, "The runner carries the box")
	# A second peer's component with the same seed agrees on every step.
	var mirror: Node = Sprint.new()
	var host_sprint: Node = player.get_node(^"Sprint")
	host_sprint.seed_override = 4242
	mirror.seed_override = 4242
	var tripped_at: int = -1
	var mirror_tripped_at: int = -1
	for step: int in range(1, 600):
		if mirror.would_stumble(step, 0.8):
			mirror_tripped_at = step
			break
	var before_tripping: float = package.integrity
	for step: int in range(1, 600):
		if host_sprint.host_run_step(0.8):
			tripped_at = step
			break
		if not package.is_held:
			break
	_expect(tripped_at > 0 and tripped_at == mirror_tripped_at,
			"The host trips at the step every peer computes from the seed (host %d, mirror %d)" % [
			tripped_at, mirror_tripped_at])
	_expect(not package.is_held and package.carrier == null, "The tripped box is no longer held")
	_expect(player.carried_package == null, "...and the runner's hands are empty")
	_expect(package.integrity < before_tripping - 5.0,
			"...and it landed with a hit on top of the steps (%.1f -> %.1f)" % [before_tripping, package.integrity])
	_expect(not package.freeze and package.collision_layer == 4, "...loose on the floor, a physical box again")
	mirror.free()


# --- The tip and the bounce --------------------------------------------------------------------


func _test_first_run_tip_and_box_bounce(level: Node) -> void:
	var profile: Node = root.get_node(^"/root/UnlockManager")
	var seen_before: Dictionary = profile.seen_tips.duplicate(true)
	profile.seen_tips = {}
	var tips: Array[String] = []
	var bus: Node = root.get_node(^"/root/EventBus")
	var listener := func(text: String) -> void: tips.append(text)
	bus.tutorial_tip_requested.connect(listener)
	var player: Player = level.local_player
	var package: DeliveryPackage = level.get_node("World/Package")
	package.get_node("InteractionArea").interact(player)
	var sprint: Node = player.get_node(^"Sprint")
	Input.action_press(&"sprint")
	await physics_frame
	sprint.ground_speed(Vector2(0.0, -1.0))
	sprint.ground_speed(Vector2(0.0, -1.0))
	Input.action_release(&"sprint")
	var tip: String = tr("UI_TUT_TIP_SPRINT_CARRY")
	_expect(tips.count(tip) == 1, "The first run with a box shows the tip once (got %s)" % [tips])
	_expect(tip.begins_with("Correr con la caja"), "The tip says running with the box shakes it (got %s)" % tip)
	# Every footfall bounces the box in the arms.
	var feedback: Node = package.get_node("PackageFeedbackComponent")
	feedback.set("_bounce_time", -1.0)
	feedback.set("_impact_shake_strength", 0.0)
	RunShake.bounce(package, 1)
	_expect(is_zero_approx(float(feedback.get("_bounce_time"))) and float(feedback.get("_impact_shake_strength")) > 0.2,
			"A running step bounces and shakes the box's mesh")
	_expect(package.linear_velocity == Vector3.ZERO and package.freeze, "...without touching the real body")
	RunShake.bounce(package, 2)
	_expect(package.get_node_or_null(^"RunCreak") != null, "...and every other step it creaks")
	# The ground under the runner: the route grades it for the trip's hazard.
	var route: Node = level.get_node("World/Route")
	_expect(route.is_in_group(&"route"), "The route is in the 'route' group the runner asks")
	route.terrain.add_span(Vector3(9000.0, 0.0, 9000.0), Vector3(9000.0, 0.0, 9100.0), true, 6.0)
	route.terrain.add_span(Vector3(9500.0, 0.0, 9000.0), Vector3(9500.0, 0.0, 9100.0), false, 6.0)
	_expect(is_equal_approx(route.ground_roughness(Vector3(9001.0, 0.0, 9050.0)), 1.0), "Gravel is the roughest ground")
	_expect(is_zero_approx(route.ground_roughness(Vector3(9501.0, 0.0, 9050.0))), "Asphalt is smooth")
	_expect(is_equal_approx(route.ground_roughness(Vector3(9510.0, 0.0, 9050.0)), route.VERGE_ROUGHNESS),
			"The verge is a little rough")
	bus.tutorial_tip_requested.disconnect(listener)
	profile.seen_tips = seen_before
	profile.call(&"save_profile")


# --- Animation -----------------------------------------------------------------------------------


func _test_animator_picks_run_or_the_fallback(level: Node) -> void:
	var player: Player = level.local_player
	# Headless has no captured mouse, so the controller never moves by itself:
	# drop it onto the depot floor by hand.
	for i: int in 30:
		player.velocity = Vector3(0.0, -6.0, 0.0)
		player.move_and_slide()
		await physics_frame
	_expect(player.is_on_floor(), "The player stands on the floor before the animation checks")
	# Hysteresis: in above 4.6 m/s, out under 4.0.
	var animator := PlayerAnimator.new(player, null, null)
	var states: Array[StringName] = []
	for pace: float in [3.6, 4.7, 4.3, 4.1, 3.9, 4.5, 4.7, 3.0]:
		animator.update_movement(pace, 2.0)
		states.append(player.anim_state)
	var expected: Array[StringName] = [&"Walk", &"Run", &"Run", &"Run", &"Walk", &"Walk", &"Run", &"Walk"]
	_expect(states == expected, "Run comes in above 4.6 and out under 4.0 m/s, like Walk/Stroll (got %s)" % [states])
	animator.update_movement(4.2, 2.0)
	_expect(player.anim_state == &"Walk", "The 4.2 m/s jog stays a fast Walk (got %s)" % player.anim_state)

	# Playback with and without a Run clip in the library.
	player.anim_state = Player.ANIM_RUN
	player.locomotion_speed = 6.0
	player.seat_node_path = NodePath()
	var with_run: AnimationPlayer = _fake_animation_player(true)
	PlayerAnimator.new(player, with_run, null).animate()
	_expect(with_run.current_animation == "Run", "With a Run clip in the library the runner plays Run")
	_expect(is_equal_approx(with_run.speed_scale, 1.0), "...at the authored pace (scale %s)" % with_run.speed_scale)
	var without_run: AnimationPlayer = _fake_animation_player(false)
	PlayerAnimator.new(player, without_run, null).animate()
	_expect(without_run.current_animation == "Walk", "Without a Run clip Walk plays instead")
	_expect(without_run.speed_scale > 1.5 and without_run.speed_scale <= PlayerAnimator.RUN_FALLBACK_MAX_SCALE,
			"...sped up past the walking cap (speed_scale %.2f)" % without_run.speed_scale)
	with_run.free()
	without_run.free()


## N-115.3: the Blender clip, not the fallback. Looping (the glTF importer drops the flag;
## PlayerAnimator.LOOPING sets it), as long as Walk so the phase-keeping switch lands on
## the same foot, and scaled by speed so the planted feet keep pace from 4 to 6 m/s.
func _test_character_library_has_a_looping_run(level: Node) -> void:
	var player: Player = level.local_player
	var playing: AnimationPlayer = player.animator.anim_player
	_expect(playing != null and playing.has_animation(Player.ANIM_RUN),
			"The character's library has a Run clip (sm_char_player_rounded.glb)")
	if playing == null or not playing.has_animation(Player.ANIM_RUN):
		return
	var run: Animation = playing.get_animation(Player.ANIM_RUN)
	var walk_length: float = playing.get_animation(Player.ANIM_WALK).length
	_expect(run.loop_mode == Animation.LOOP_LINEAR, "Run loops (got loop_mode %d)" % run.loop_mode)
	_expect(is_equal_approx(run.length, walk_length),
			"Run lasts as long as Walk (%.3f vs %.3f s)" % [run.length, walk_length])
	player.seat_node_path = NodePath()
	player.anim_state = Player.ANIM_RUN
	for pace: float in [6.0, 5.0, 4.0]:
		player.locomotion_speed = pace
		player.animator.animate()
		_expect(playing.current_animation == "Run", "At %.1f m/s the runner plays Run, not Walk (got %s)" % [
				pace, playing.current_animation])
		_expect(is_equal_approx(playing.speed_scale, pace / PlayerAnimator.RUN_AUTHORED_SPEED),
				"...at speed / 6 m/s so the feet don't skate (%.1f m/s: x%.3f)" % [pace, playing.speed_scale])


func _test_other_peer_sees_the_run(level: Node) -> void:
	var remote: Player = PLAYER_SCENE.instantiate()
	remote.name = "Player_2"
	level.get_node("World").add_child(remote)
	await physics_frame
	_expect(not remote.is_local(), "The second crew member belongs to another peer")
	var sprint: Node = remote.get_node(^"Sprint")
	_expect(not sprint.running, "A standing peer is not running")
	# What the owner replicates: anim_state Run and the pace.
	remote.anim_state = Player.ANIM_RUN
	remote.locomotion_speed = 6.0
	var footsteps_before: int = sprint.steps_taken
	for i: int in 90:
		await physics_frame
	var footsteps: int = sprint.steps_taken - footsteps_before
	_expect(sprint.running, "The other peer plays the run from anim_state and the pace")
	_expect(footsteps in [4, 5], "Its footfalls come at the running cadence: 4-5 in 1.5 s (got %d)" % footsteps)
	await process_frame
	var playing: AnimationPlayer = remote.animator.anim_player
	_expect(playing.current_animation == "Run" and is_equal_approx(playing.speed_scale, 1.0),
			"...and sees the character's Run clip at its authored pace (got %s x%.2f)" % [
			playing.current_animation, playing.speed_scale])
	remote.anim_state = Player.ANIM_WALK
	remote.locomotion_speed = Player.WALK_SPEED
	await physics_frame
	await physics_frame
	_expect(not sprint.running, "Back to walking, the footfalls stop")
	var synchronizer := remote.get_node("MultiplayerSynchronizer") as MultiplayerSynchronizer
	var replicated: Array[String] = []
	for path: NodePath in synchronizer.replication_config.get_properties():
		replicated.append(String(path))
	_expect(replicated.has(".:anim_state") and replicated.has(".:locomotion_speed"),
			"The run travels as anim_state plus the pace, which the synchronizer replicates (got %s)" % [replicated])
	var footstep: AudioStreamWAV = SynthAudioSteps.footstep()
	_expect(footstep.data.size() > 1000 and footstep == SynthAudioSteps.footstep(),
			"The footfall is a shared synthesized sound")
	remote.free()  # The next section adds its own Player_2.
	await physics_frame


## The box is in the local runner's arms by now (the tip's section): held and frozen,
## nothing but the remote's steps can shake it.
func _test_remote_jog_and_the_hosts_step_bucket(level: Node) -> void:
	var package: DeliveryPackage = level.get_node("World/Package")
	var remote: Player = PLAYER_SCENE.instantiate()
	remote.name = "Player_2"
	level.get_node("World").add_child(remote)
	await physics_frame
	var sprint: Node = remote.get_node(^"Sprint")
	var feedback: Node = package.get_node("PackageFeedbackComponent")
	# The Growing weight jog stays Walk in anim_state, at 4.2 m/s: still a run for the others.
	remote.carried_package = package
	remote.anim_state = Player.ANIM_WALK
	remote.locomotion_speed = 4.2
	feedback.set("_impact_shake_strength", 0.0)
	var before: int = sprint.steps_taken
	for i: int in 60:
		await physics_frame
	_expect(sprint.running, "A remote jog (Walk at 4.2 m/s) counts as running")
	_expect(sprint.steps_taken - before >= 2, "...its steps are counted (%d in 1 s)" % (sprint.steps_taken - before))
	_expect(float(feedback.get("_impact_shake_strength")) > 0.0, "...and the box it carries bounces")
	# Walking pace: no steps.
	remote.locomotion_speed = 3.6
	await physics_frame
	await physics_frame
	before = sprint.steps_taken
	for i: int in 60:
		await physics_frame
	_expect(not sprint.running and sprint.steps_taken == before,
			"A remote walking at 3.6 m/s counts no steps (%d)" % (sprint.steps_taken - before))
	remote.carried_package = null

	# The host's gate on step reports, with an injected clock.
	remote.locomotion_speed = 4.2
	var owner_peer: int = remote.get_multiplayer_authority()
	_expect(is_equal_approx(sprint.host_accepts_step(owner_peer, 0.4, 1000), 0.4), "The owner's report is accepted")
	_expect(sprint.host_accepts_step(owner_peer + 1, 0.4, 5000) < 0.0, "Somebody else's report is rejected")
	remote.seat_node_path = NodePath("Somewhere/DriverEyePoint")
	_expect(sprint.host_accepts_step(owner_peer, 0.4, 9000) < 0.0, "A seated player's report is rejected")
	remote.seat_node_path = NodePath()
	remote.locomotion_speed = 1.0
	_expect(sprint.host_accepts_step(owner_peer, 0.4, 13000) < 0.0, "A report at a stand-still pace is rejected")
	remote.locomotion_speed = 4.2
	var accepted: int = 0
	for i: int in 10:
		accepted += int(sprint.host_accepts_step(owner_peer, 0.4, 100000) >= 0.0)
	_expect(accepted == 2, "Ten reports in the same instant: the bucket lets 2 through (got %d)" % accepted)
	accepted = 0
	for i: int in 20:
		accepted += int(sprint.host_accepts_step(owner_peer, 0.4, 200000 + i * 340) >= 0.0)
	_expect(accepted == 20, "A full-speed runner's reports, one every 340 ms, all count (got %d)" % accepted)
	_expect(is_equal_approx(sprint.host_accepts_step(owner_peer, NAN, 300000), 1.0), "A NaN hazard counts as the worst")
	_expect(is_equal_approx(sprint.host_accepts_step(owner_peer, INF, 300400), 1.0),
			"An infinite hazard is the worst too")
	_expect(is_equal_approx(sprint.host_accepts_step(owner_peer, 7.0, 300800), 1.0), "A hazard past 1 is clamped")
	remote.free()
	await physics_frame


# --- Helpers ---------------------------------------------------------------------------------


func _package(kind: String) -> DeliveryPackage:
	var box: DeliveryPackage = load("res://scenes/gameplay/package/package.tscn").instantiate()
	box.trap_definition = load("res://data/traps/%s.tres" % kind)
	box.package_id = StringName("run_%s" % kind)
	return box


func _fake_animation_player(with_run: bool) -> AnimationPlayer:
	var animation_player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	# Not a ternary of literals: that yields an untyped Array, a runtime error that skipped this check.
	var clips: Array[StringName] = [&"Idle", &"Walk"]
	if with_run:
		clips.append(&"Run")
	for clip: StringName in clips:
		var animation := Animation.new()
		animation.length = 1.0
		library.add_animation(clip, animation)
	animation_player.add_animation_library(&"", library)
	root.add_child(animation_player)
	return animation_player


func _load_level() -> Node:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	return level


func _unload_level(level: Node) -> void:
	Input.action_release(&"sprint")
	root.get_node(^"/root/RunManager").call(&"reset_run")
	level.free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

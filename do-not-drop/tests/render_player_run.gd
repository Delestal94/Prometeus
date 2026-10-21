extends SceneTree
## Run WITHOUT --headless:
##   Godot --path do-not-drop --resolution 1280x720 --script res://tests/render_player_run.gd
##
## N-115.3: the Run clip in game. In the real level (level_base.tscn, HUD hidden,
## truck parked), one crew member plays Run the way every other peer sees it
## (anim_state replicated as Run with the running speed) and is frozen at four
## points of the stride; a second one walks beside it, frozen too, to compare
## the gait. Each pose is shot from the side and from three quarters.
## Saves user://player_run_<phase>_<side|three_quarter>.png (phase 0..3 of the
## Run cycle) and user://player_run_vs_walk.png, and prints the clip lengths.
## Players get multiplayer authority 2 and 3: offline the local id is 1, so
## they are remote puppets that only play anim_state, like teammates.

const RUN_SPEED: float = 6.0
const WALK_SPEED: float = 3.6

var _level: Node3D
var _van: Node3D
var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	_level = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(_level)
	current_scene = _level
	_level.get_node("HUD").hide()
	_van = _level.vehicle
	_van.set_physics_process(false)
	_van.get_node("VehicleInputComponent").set_physics_process(false)
	_van.get_node("VehiclePresentation").audio_enabled = false
	for i: int in range(20):
		await physics_frame
	for child in _level.get_node("World").get_children():
		if child.is_in_group(&"player"):
			child.hide()
			child.process_mode = Node.PROCESS_MODE_DISABLED
	_camera = Camera3D.new()
	_level.add_child(_camera)
	_camera.fov = 50.0
	_camera.near = 0.03
	_camera.make_current()

	# Open ground beside the truck, both facing along the truck's length.
	var runner: Node3D = _spawn_player(2, _ground(_van.to_global(Vector3(-4.5, 0, 1.5))))
	var walker: Node3D = _spawn_player(3, _ground(_van.to_global(Vector3(-4.5, 0, -2.5))))
	for player: Node3D in [runner, walker]:
		player.look_at(player.global_position + _van.global_basis.z, Vector3.UP)
		player.rotation.x = 0.0
		player.rotation.z = 0.0
	runner.set(&"locomotion_speed", RUN_SPEED)
	runner.set(&"anim_state", &"Run")
	walker.set(&"locomotion_speed", WALK_SPEED)
	walker.set(&"anim_state", &"Walk")
	for i: int in range(30):
		await physics_frame
	var run_anim: AnimationPlayer = runner.get(&"animator").anim_player
	var walk_anim: AnimationPlayer = walker.get(&"animator").anim_player
	if run_anim == null or not run_anim.has_animation(&"Run"):
		push_error("The character has no Run clip: PlayerAnimator falls back to a fast Walk.")
		quit(1)
		return
	var run_length: float = run_anim.get_animation(&"Run").length
	var walk_length: float = walk_anim.get_animation(&"Walk").length
	print("CLIP Run=%.3f s Walk=%.3f s current=%s / %s" % [
		run_length, walk_length, run_anim.current_animation, walk_anim.current_animation])
	# The animator re-times the clip every frame from the speed: stop both
	# players now that their clips play, so a seek holds until the shot.
	runner.process_mode = Node.PROCESS_MODE_DISABLED
	walker.process_mode = Node.PROCESS_MODE_DISABLED

	for phase: int in range(4):
		_freeze(run_anim, run_length * phase / 4.0)
		_freeze(walk_anim, walk_length * phase / 4.0)
		_aim_at(runner, Vector3(3.2, 0.9, 0.0))
		await _save("%d_side" % phase)
		_aim_at(runner, Vector3(2.3, 1.3, -2.3))
		await _save("%d_three_quarter" % phase)

	# Both gaits in one frame, at mid stride, from the side.
	_freeze(run_anim, run_length * 0.25)
	_freeze(walk_anim, walk_length * 0.25)
	var middle: Vector3 = (runner.global_position + walker.global_position) * 0.5
	_camera.global_position = middle + _van.global_basis.x * -7.0 + Vector3.UP * 1.1
	_camera.look_at(middle + Vector3.UP * 0.8, Vector3.UP)
	await _save("vs_walk")
	_level.free()
	quit(0)


func _spawn_player(peer: int, at: Vector3) -> Node3D:
	var player: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	player.name = "Player_%d" % peer
	player.position = at
	_level.add_child(player)
	player.set(&"net_position", at)
	return player


func _ground(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 5.0, point + Vector3.DOWN * 10.0, 1)
	var hit: Dictionary = _level.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else point


func _freeze(anim: AnimationPlayer, at_seconds: float) -> void:
	anim.seek(at_seconds, true)
	anim.speed_scale = 0.0


## The camera at `offset` from the player, in the player's own space (x to its
## side, z ahead), looking at its waist.
func _aim_at(player: Node3D, offset: Vector3) -> void:
	_camera.global_position = player.to_global(offset)
	_camera.look_at(player.global_position + Vector3.UP * 0.8, Vector3.UP)


func _save(label: String) -> void:
	for i: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var output: String = "user://player_run_%s.png" % label
	if root.get_texture().get_image().save_png(output) != OK:
		push_error("Screenshot failed: %s" % output)
		return
	print("RENDER: ", ProjectSettings.globalize_path(output))

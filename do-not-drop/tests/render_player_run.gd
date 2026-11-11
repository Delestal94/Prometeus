extends SceneTree
## Run WITHOUT --headless:
##   Godot --path do-not-drop --resolution 1280x720 --script res://tests/render_player_run.gd
##
## N-115.3: the Run clip in game. One crew member plays Run the way every other
## peer sees it (anim_state replicated as Run with the running speed) and is
## frozen at 8 points of the stride (every 1/8 of the cycle, so the flight
## phase can show); a second one walks, frozen too, to compare the gait.
## The level is only used for its lighting and the player scene: the whole
## World (depot, truck, road) is hidden and the crew stands on a private open
## stage far from it (a flat floor, a pale unshaded dome behind, one key light
## with a hard shadow), so nothing blocks the camera or hides the jelly body.
## Saves user://player_run_<phase>_<view>.png, phase 0..7 of the Run cycle:
##   side           camera at waist height, from the runner's side
##   low            camera at foot height (narrow lens): do both feet leave the floor?
##   three_quarter  from the front/side, only for the even phases
## and user://player_run_vs_walk.png (runner and walker 2.5 m apart, side by
## side across the camera, mid stride). Prints "CLIP" with the clip lengths and,
## per phase, a "FEET" line: height of foot.L / foot.R (and any toe bone) above
## the floor, how far each is above its standing rest height, and FLIGHT when
## both feet are higher than FLIGHT_MARGIN over it. The bones are joints, not
## soles, so the rest height is the baseline; if the skeleton has no foot bones
## the line says so. A "FEET summary" line lists the phases with flight.
## Players get multiplayer authority 2 and 3: offline the local id is 1, so
## they are remote puppets that only play anim_state, like teammates.

const RUN_SPEED: float = 6.0
const WALK_SPEED: float = 3.6
const PHASES: int = 8
## Far from the level, high enough to never meet its ground.
const STAGE: Vector3 = Vector3(900.0, 200.0, 900.0)
const FLOOR_COLOR: Color = Color(0.46, 0.47, 0.5)
const BACKDROP_COLOR: Color = Color(0.86, 0.88, 0.9)
## A foot counts as off the floor when its bone is this much (m) above its rest height.
const FLIGHT_MARGIN: float = 0.03
const WALKER_GAP: float = 2.5

var _level: Node3D
var _van: Node3D
var _camera: Camera3D
var _flight_phases: Array[int] = []


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
	_build_stage()
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

	# Both face world +Z; the walker waits out of frame until the comparison.
	var runner: Node3D = _spawn_player(2, STAGE)
	var walker: Node3D = _spawn_player(3, STAGE + Vector3(0.0, 0.0, 6.0))
	for player: Node3D in [runner, walker]:
		player.look_at(player.global_position + Vector3.BACK, Vector3.UP)
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
	walker.hide()

	for phase: int in range(PHASES):
		var at_seconds: float = run_length * phase / float(PHASES)
		_freeze(run_anim, at_seconds)
		for i: int in range(3):
			await process_frame
		_report_feet(runner, phase, at_seconds)
		_camera.fov = 50.0
		_aim_at(runner, Vector3(3.2, 0.9, 0.0), 0.8)
		await _save("%d_side" % phase)
		# Camera at the feet and a narrow lens: the floor line shows the flight.
		_camera.fov = 30.0
		_aim_at(runner, Vector3(3.2, 0.15, 0.0), 0.4)
		await _save("%d_low" % phase)
		_camera.fov = 50.0
		if phase % 2 == 0:
			_aim_at(runner, Vector3(2.3, 1.3, -2.3), 0.8)
			await _save("%d_three_quarter" % phase)
	print("FEET summary: flight (both feet above rest + %.2f m) in phases %s of %d" % [
		FLIGHT_MARGIN, _flight_phases, PHASES])

	# Both gaits in one frame, at mid stride, across the camera, close.
	_freeze(run_anim, run_length * 0.25)
	_freeze(walk_anim, walk_length * 0.25)
	runner.global_position = STAGE + Vector3(0.0, 0.0, -WALKER_GAP * 0.5)
	walker.global_position = STAGE + Vector3(0.0, 0.0, WALKER_GAP * 0.5)
	walker.show()
	_camera.fov = 50.0
	_camera.global_position = STAGE + Vector3(-4.0, 1.0, 0.0)
	_camera.look_at(STAGE + Vector3(0.0, 0.9, 0.0), Vector3.UP)
	await _save("vs_walk")
	_level.free()
	quit(0)


## A flat floor with collision (layer 1), a pale unshaded dome around it and a
## key light with a hard shadow, all far from the level. The level's own sun is
## turned off and World hidden so the only things in frame are the crew and this.
func _build_stage() -> void:
	_level.get_node("World").hide()
	_level.get_node("Sun").hide()
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	_level.add_child(floor_body)
	floor_body.global_position = STAGE + Vector3.DOWN * 0.5
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = FLOOR_COLOR
	floor_material.roughness = 1.0
	floor_mesh.material_override = floor_material
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_level.add_child(floor_mesh)
	floor_mesh.global_position = STAGE
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 28.0
	sphere.height = 56.0
	dome.mesh = sphere
	var dome_material := StandardMaterial3D.new()
	dome_material.albedo_color = BACKDROP_COLOR
	dome_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dome_material.cull_mode = BaseMaterial3D.CULL_FRONT
	dome.material_override = dome_material
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_level.add_child(dome)
	dome.global_position = STAGE
	# Light travels toward +Z and a little to -X: the shadow falls ahead of the
	# runner, which both the side and the low cameras see.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, 160.0, 0.0)
	key.light_energy = 1.1
	key.shadow_enabled = true
	key.shadow_opacity = 1.0
	key.shadow_blur = 0.5
	key.shadow_bias = 0.03
	key.directional_shadow_max_distance = 40.0
	_level.add_child(key)


func _spawn_player(peer: int, at: Vector3) -> Node3D:
	var player: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	player.name = "Player_%d" % peer
	player.position = at
	_level.add_child(player)
	player.set(&"net_position", at)
	return player


func _freeze(anim: AnimationPlayer, at_seconds: float) -> void:
	anim.seek(at_seconds, true)
	anim.speed_scale = 0.0


## The camera at `offset` from the player, in the player's own space (x to its
## side), looking at the player's axis `target_height` metres above the feet.
func _aim_at(player: Node3D, offset: Vector3, target_height: float) -> void:
	_camera.global_position = player.to_global(offset)
	_camera.look_at(player.global_position + Vector3.UP * target_height, Vector3.UP)


## FEET line for the pose now showing: foot (and toe) bone heights above the
## floor and above their standing rest heights.
func _report_feet(player: Node3D, phase: int, at_seconds: float) -> void:
	var skeleton: Skeleton3D = _find_skeleton(player.get_node(^"BodyVisual"))
	if skeleton == null:
		print("FEET phase %d: no skeleton under BodyVisual" % phase)
		return
	var feet: Array[int] = []
	for i: int in range(skeleton.get_bone_count()):
		var bone_name: String = String(skeleton.get_bone_name(i)).to_lower()
		if bone_name.begins_with("foot") or bone_name.begins_with("toe"):
			feet.append(i)
	if feet.is_empty():
		var names: PackedStringArray = []
		for i: int in range(skeleton.get_bone_count()):
			names.append(skeleton.get_bone_name(i))
		print("FEET no foot/toe bones in the skeleton, no flight data. Bones: %s" % ", ".join(names))
		return
	var text := ""
	var lifts: Array[float] = []
	for bone: int in feet:
		var now: float = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin).y - STAGE.y
		var rest: float = skeleton.to_global(skeleton.get_bone_global_rest(bone).origin).y - STAGE.y
		text += " %s y=%.3f (rest %.3f, lift %+.3f)" % [skeleton.get_bone_name(bone), now, rest, now - rest]
		# The flight check uses the foot bones only, not the toes.
		if String(skeleton.get_bone_name(bone)).to_lower().begins_with("foot"):
			lifts.append(now - rest)
	var flight: bool = lifts.size() >= 2 and lifts.min() > FLIGHT_MARGIN
	if flight:
		_flight_phases.append(phase)
	print("FEET phase %d/%d t=%.3f:%s%s" % [phase, PHASES, at_seconds, text,
		"  FLIGHT (both feet up)" if flight else ""])


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _save(label: String) -> void:
	for i: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var output: String = "user://player_run_%s.png" % label
	if root.get_texture().get_image().save_png(output) != OK:
		push_error("Screenshot failed: %s" % output)
		return
	print("RENDER: ", ProjectSettings.globalize_path(output))

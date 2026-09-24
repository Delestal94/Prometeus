class_name DepotWorker
extends AnimatableBody3D
## One of the depot's staff. Uses the crew's own character model in a hi-vis
## uniform, so the place is never empty while you get ready.
##
## A worker either stands at a post (the counter, the office) or walks a loop
## of waypoints, pausing at each. Either way they turn to face a player who
## comes close and say something -- a line from their `lines`, floating over
## their head for a few seconds.
##
## Purely local presentation: every peer runs its own, identically seeded, so
## nothing here is replicated. The capsule is an AnimatableBody3D so a walker
## nudges players aside instead of walking through them.

const CHARACTER_SCENE: PackedScene = preload("res://assets/models/characters/sm_char_player_lowpoly.glb")
const ANIM_IDLE: StringName = &"Idle"
const ANIM_WALK: StringName = &"Walk"
const GREET_DISTANCE: float = 3.2
const TURN_SPEED: float = 4.0
const LINE_SECONDS: float = 3.5
const LINE_COOLDOWN: float = 14.0

@export var uniform: Color = Color("ff9f1c")
@export var walk_speed: float = 1.25
## Seconds spent at each waypoint before moving on.
@export var pause_seconds: float = 2.5
## Loop of points (depot space) for a walker; empty for a worker at a post.
var waypoints: Array[Vector3] = []
var lines: PackedStringArray = []
var _visual: Node3D
var _anim: AnimationPlayer
var _bubble: Label3D
var _next: int = 0
var _wait: float = 0.0
var _line_left: float = 0.0
var _line_cooldown: float = 0.0
var _line_index: int = 0
var _home_yaw: float = 0.0


func _ready() -> void:
	sync_to_physics = true
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.875, 0.0)
	add_child(shape)
	_visual = CHARACTER_SCENE.instantiate()
	_visual.name = "Body"
	add_child(_visual)
	_tint()
	_anim = _visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim != null:
		for clip: StringName in [ANIM_IDLE, ANIM_WALK]:
			if _anim.has_animation(clip):
				_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_play(ANIM_IDLE)
		# Staff don't breathe in lockstep.
		_anim.seek(randf() * 2.0, true)
	_bubble = Label3D.new()
	_bubble.name = "SpeechBubble"
	_bubble.font = preload("res://assets/fonts/Nunito-Variable.ttf")
	_bubble.font_size = 40
	_bubble.pixel_size = 0.0042
	_bubble.outline_size = 12
	_bubble.modulate = Color("fff6e6")
	_bubble.outline_modulate = Color("1e2235")
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position = Vector3(0.0, 2.15, 0.0)
	_bubble.visible = false
	add_child(_bubble)
	_home_yaw = rotation.y
	_wait = randf() * pause_seconds


func _physics_process(delta: float) -> void:
	_line_cooldown = maxf(_line_cooldown - delta, 0.0)
	if _line_left > 0.0:
		_line_left -= delta
		_bubble.visible = _line_left > 0.0
	var player: Node3D = _nearest_player()
	var near: bool = player != null and player.global_position.distance_to(global_position) < GREET_DISTANCE
	if near:
		_face(player.global_position, delta)
		_play(ANIM_IDLE)
		if _line_cooldown <= 0.0 and not lines.is_empty():
			_say(lines[_line_index % lines.size()])
			_line_index += 1
		return
	if waypoints.is_empty():
		rotation.y = lerp_angle(rotation.y, _home_yaw, clampf(delta * TURN_SPEED * 0.5, 0.0, 1.0))
		return
	if _wait > 0.0:
		_wait -= delta
		_play(ANIM_IDLE)
		return
	var target: Vector3 = waypoints[_next]
	var here: Vector3 = position
	var to_target := Vector3(target.x - here.x, 0.0, target.z - here.z)
	if to_target.length() < 0.08:
		_next = (_next + 1) % waypoints.size()
		_wait = pause_seconds
		return
	var step: Vector3 = to_target.normalized() * minf(walk_speed * delta, to_target.length())
	position = here + step
	rotation.y = lerp_angle(rotation.y, atan2(-to_target.x, -to_target.z), clampf(delta * TURN_SPEED, 0.0, 1.0))
	_play(ANIM_WALK)


func _say(text: String) -> void:
	_bubble.text = text
	_bubble.visible = true
	_line_left = LINE_SECONDS
	_line_cooldown = LINE_COOLDOWN


func _face(point: Vector3, delta: float) -> void:
	var local: Vector3 = get_parent_node_3d().to_local(point) if get_parent_node_3d() != null else point
	var to_point := Vector3(local.x - position.x, 0.0, local.z - position.z)
	if to_point.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-to_point.x, -to_point.z), clampf(delta * TURN_SPEED, 0.0, 1.0))


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Node3D
		if player == null or not player.visible:
			continue
		var distance: float = player.global_position.distance_squared_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _play(clip: StringName) -> void:
	if _anim != null and _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip, 0.25)


## Same approach as the player's uniform: the suit material is duplicated per
## worker, never edited in place on the shared imported resource.
func _tint() -> void:
	for node: Node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() == 0:
			continue
		var suit := mesh_instance.mesh.surface_get_material(0) as BaseMaterial3D
		if suit != null:
			var tinted := suit.duplicate() as BaseMaterial3D
			tinted.albedo_color = uniform
			mesh_instance.set_surface_override_material(0, tinted)
		return

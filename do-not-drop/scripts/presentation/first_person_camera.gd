extends Camera3D
## A seat's own camera, parented directly to the seat anchor -- it inherits
## that seat's moving transform for free through the normal scene tree, no
## per-frame following needed. Mouse/right stick rotate relative to that anchor,
## C/right-stick click recenter. A seat interaction calls activate().
## A short shake on vehicle_impact keeps physical feedback raw
## and un-smoothed, the way PEAK's first-person camera sells its chaos.

@export var shake_decay: float = 6.0
@export var shake_position_scale: float = 0.012
@export var shake_rotation_scale_deg: float = 1.6
## A brief FOV kick on impact, standing in for the "slow-mo breve" of
## docs/requerimientos-tecnicos.md 3.4: real slow motion would mean touching
## Engine.time_scale, which also slows the host-authoritative physics for
## everyone. This reads as the same kind of punch, costs nothing, and is
## purely local -- nobody else's game is affected by what this camera does.
@export var impact_fov_kick_degrees: float = 7.0
@export var fov_recover_speed: float = 5.0
@export var mouse_sensitivity: float = 0.0028
@export var stick_sensitivity: float = 2.4  ## Radians per second at full deflection.
@export_range(0.0, 180.0) var yaw_limit_degrees: float = 160.0
@export_range(0.0, 89.0) var pitch_limit_degrees: float = 80.0

## Wider than Player's own on-foot WALK_FOV (78°) -- item #64: driving
## shouldn't share the exact same frame as walking, and a touch more field
## of view suits the extra spatial awareness manoeuvring the van needs.
const BASE_FOV: float = 82.0
const RenderLayers = preload("res://scripts/presentation/render_layers.gd")

var _shake_strength: float = 0.0
var _rng := RandomNumberGenerator.new()
var _base_transform: Transform3D
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
## Holding "look_back" swings the view over the shoulder toward the cargo
## (tareas de Nacho #35) and lets go back to wherever you were looking.
var _look_back: float = 0.0
const LOOK_BACK_YAW_DEGREES: float = 155.0
const LOOK_BACK_SPEED: float = 6.0


func _ready() -> void:
	RenderLayers.configure_first_person(self)
	RenderLayers.show_viewmodel(self, current)
	fov = GameSettings.preferred_fov
	near = 0.03
	# Explicit far plane instead of the engine default: the route is 220 m and
	# the scenery blocks beside it reach ~250 m, so this keeps everything in
	# view with room to spare. Worth pinning down now that RouteStreamer can
	# generate road indefinitely -- an unbounded default is the kind of thing
	# that only shows up as a problem once the world stops being hand-placed.
	far = 600.0
	_base_transform = transform
	# Look and shake move this camera every rendered frame (_process), not on
	# physics ticks. Off, it still rides the seat's interpolated pose -- the
	# van stays smooth -- but its own turn applies the frame it happens.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.randomize()
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("vehicle_impact", _on_vehicle_impact)
		bus.connect("package_ruined", _on_package_ruined)


func activate() -> void:
	reset_look()
	current = true
	RenderLayers.show_viewmodel(self, true)


func deactivate() -> void:
	current = false
	RenderLayers.show_viewmodel(self, false)
	_shake_strength = 0.0
	fov = GameSettings.preferred_fov
	reset_look()


func reset_look() -> void:
	_look_yaw = 0.0
	_look_pitch = 0.0
	transform = _base_transform


func _can_look() -> bool:
	return current and not get_tree().paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _can_look():
		return
	if event is InputEventMouseMotion:
		_apply_look(event.relative * mouse_sensitivity)
	elif event.is_action_pressed(&"look_center"):
		reset_look()
		get_viewport().set_input_as_handled()


func _apply_look(motion: Vector2) -> void:
	# Sensitivity and Y inversion are player settings now (GameSettings), and
	# both get applied in this one place so mouse and stick stay consistent
	# with each other. 1.0 / not-inverted is exactly the tuning this shipped
	# with, so the defaults change nothing.
	motion.x *= GameSettings.look_sensitivity
	motion.y *= GameSettings.look_sensitivity * GameSettings.look_y_sign()
	_look_yaw = clampf(_look_yaw - motion.x, -deg_to_rad(yaw_limit_degrees), deg_to_rad(yaw_limit_degrees))
	_look_pitch = clampf(_look_pitch - motion.y, -deg_to_rad(pitch_limit_degrees), deg_to_rad(pitch_limit_degrees))


func _look_transform() -> Transform3D:
	# Look is relative to the seat; head rotation must not rotate the eye position.
	var pose := _base_transform
	# Over whichever shoulder you were already turned toward (left by default).
	var back_yaw: float = deg_to_rad(LOOK_BACK_YAW_DEGREES) * (-1.0 if _look_yaw < -0.05 else 1.0)
	var yaw: float = lerp_angle(_look_yaw, back_yaw, _look_back)
	var pitch: float = lerpf(_look_pitch, 0.0, _look_back)
	pose.basis = _base_transform.basis * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	return pose


func _process(delta: float) -> void:
	RenderLayers.show_viewmodel(self, current)
	if not current:
		return
	if get_tree().paused:
		return
	if _can_look():
		var stick: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
		_apply_look(stick * stick_sensitivity * delta)
	var wants_back: bool = _can_look() and InputMap.has_action(&"look_back") and Input.is_action_pressed(&"look_back")
	_look_back = move_toward(_look_back, 1.0 if wants_back else 0.0, LOOK_BACK_SPEED * delta)
	var look_pose: Transform3D = _look_transform()
	var preferred_fov: float = GameSettings.preferred_fov
	if not is_equal_approx(fov, preferred_fov):
		fov = move_toward(fov, preferred_fov, fov_recover_speed * absf(fov - preferred_fov) * delta + 0.01)
	_shake_strength = maxf(0.0, _shake_strength - shake_decay * delta)
	if _shake_strength <= 0.0:
		transform = look_pose
		return
	var jitter := Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	) * shake_position_scale * _shake_strength
	var wobble_x: float = deg_to_rad(_rng.randf_range(-1.0, 1.0) * shake_rotation_scale_deg * _shake_strength)
	var wobble_y: float = deg_to_rad(_rng.randf_range(-1.0, 1.0) * shake_rotation_scale_deg * _shake_strength)
	transform = look_pose.translated_local(jitter).rotated_local(Vector3.RIGHT, wobble_x).rotated_local(Vector3.UP, wobble_y)


func _on_vehicle_impact(strength: float, _impact_position: Vector3) -> void:
	if not current:
		return
	_shake_strength = clampf(_shake_strength + strength * 0.15 * GameSettings.camera_shake_scale, 0.0, 1.0)
	fov = GameSettings.preferred_fov + impact_fov_kick_degrees * _shake_strength * GameSettings.camera_shake_scale


## A ruined package deserves its own jolt (docs/especificaciones-visuales.md
## #67) -- until now only an actual vehicle collision could shake the
## camera, so losing cargo to a trap running out (Ruidoso escaping, say,
## with no fresh impact involved) felt weightless by comparison. No FOV
## kick here on purpose: that's reserved for the physical punch of a real
## collision, not diluted into every kind of bad news.
func _on_package_ruined(_package_id: StringName, _cause: String) -> void:
	if not current:
		return
	_shake_strength = clampf(_shake_strength + 0.6 * GameSettings.camera_shake_scale, 0.0, 1.0)

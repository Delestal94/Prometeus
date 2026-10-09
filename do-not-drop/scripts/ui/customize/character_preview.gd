extends SubViewportContainer
## The customisation screen's stage (N-506): the real player model, its real
## face (CharacterFace) and shirt tint, in a small lit studio of its own. The
## camera eases between a close-up of the head (face) and the whole body
## (uniform); drag with the mouse or push the right stick to turn the
## character. Presentation only, nothing here is saved or replicated.

const PLAYER_SCENE: PackedScene = preload("res://assets/models/characters/sm_char_player_rounded.glb")
const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const GEL_MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body.tres")
const CharacterFace = preload("res://scripts/presentation/character_face.gd")
const GelShaper = preload("res://scripts/gameplay/player/gel/gel_body_shaper.gd")
const GelGrounding = preload("res://scripts/gameplay/player/gel/gel_foot_grounding.gd")

enum Framing { FACE, BODY }

## Where the camera looks and from how far (model space: the character
## faces -Z, its head centre is at y 1.445 -- character_face.gd).
const SHOTS: Dictionary = {
	Framing.FACE: {"target": Vector3(0.0, 1.38, 0.0), "distance": 2.4, "height": 0.05},
	Framing.BODY: {"target": Vector3(0.0, 0.8, 0.0), "distance": 4.5, "height": 0.3},
}
const FOV: float = 30.0
## A three-quarter view to start with: flat-on reads as a mugshot.
const REST_YAW: float = deg_to_rad(-18.0)
const DRAG_TURN: float = 0.012  # radians per pixel
const STICK_TURN: float = 3.0  # radians per second at full tilt
const SHOT_TIME: float = 0.4

## The face on the model, for the panel and the tests.
var face: Node
var mannequin: Node3D
var gel_mannequin: Node3D
var framing: Framing = Framing.BODY
var _camera: Camera3D
var _yaw: float = REST_YAW
var _target: Vector3
var _distance: float
var _height: float
var _shot_tween: Tween
var _bounce_tween: Tween
var _dragging: bool = false
var _gel_shaper: GelBodyShaper = GelShaper.new()
var _gel_grounding: Node3D


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	_build_studio(viewport)
	var shot: Dictionary = SHOTS[framing]
	_target = shot.target
	_distance = shot.distance
	_height = shot.height
	_place_camera()


## Shirt colour and expression, as everybody will see them.
func show_look(shirt: Color, eyes: StringName, mouth: StringName) -> void:
	PlayerAppearance.tint_shirt(mannequin, shirt)
	face.call(&"set_expression", eyes, mouth)


## Shows the editable gel body and applies only when its values changed.
func show_proportions(proportions: GelBodyProportions) -> void:
	mannequin.visible = false
	gel_mannequin.visible = true
	_gel_shaper.apply(proportions)


func show_character() -> void:
	mannequin.visible = true
	gel_mannequin.visible = false


func proportion_application_count() -> int:
	return _gel_shaper.application_count


## A quick squash and stretch: "that changed".
func bounce() -> void:
	if _bounce_tween != null:
		_bounce_tween.kill()
	mannequin.scale = Vector3(1.06, 0.93, 1.06)
	_bounce_tween = create_tween()
	_bounce_tween.tween_property(mannequin, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func set_framing(next: Framing, instant: bool = false) -> void:
	framing = next
	var shot: Dictionary = SHOTS[next]
	if _shot_tween != null:
		_shot_tween.kill()
	if instant or not is_inside_tree():
		_target = shot.target
		_distance = shot.distance
		_height = shot.height
		_place_camera()
		return
	_shot_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_shot_tween.tween_property(self, "_target", shot.target, SHOT_TIME)
	_shot_tween.tween_property(self, "_distance", shot.distance, SHOT_TIME)
	_shot_tween.tween_property(self, "_height", shot.height, SHOT_TIME)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var stick: float = Input.get_axis(&"look_left", &"look_right")
	if not is_zero_approx(stick):
		_yaw += stick * STICK_TURN * delta
	mannequin.rotation.y = _yaw
	gel_mannequin.rotation.y = _yaw
	_place_camera()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_yaw += motion.relative.x * DRAG_TURN
		accept_event()


func _place_camera() -> void:
	if _camera == null:
		return
	_camera.position = _target + Vector3(0.0, _height, -_distance)
	_camera.look_at(_target, Vector3.UP)


func _build_studio(viewport: SubViewport) -> void:
	var world := Node3D.new()
	world.name = "Studio"
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("fff3e2")
	environment.environment.ambient_light_energy = 0.55
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(environment)
	# Key from the front left, warm; fill from the right, cool; a rim from
	# behind to lift the silhouette off the backdrop.
	for light_setup: Array in [[Vector3(-28, -150, 0), Color("fff1dc"), 1.05],
			[Vector3(-12, 140, 0), Color("dbe8ff"), 0.35], [Vector3(-20, 15, 0), Color("ffffff"), 0.7]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = light_setup[0]
		light.light_color = light_setup[1]
		light.light_energy = light_setup[2]
		world.add_child(light)
	_camera = Camera3D.new()
	_camera.fov = FOV
	world.add_child(_camera)
	world.add_child(_floor_shadow())
	mannequin = PLAYER_SCENE.instantiate() as Node3D
	mannequin.name = "Mannequin"
	world.add_child(mannequin)
	face = CharacterFace.new()
	face.call(&"setup", mannequin, PlayerAppearance.find_skeleton(mannequin), 1)
	var animation: AnimationPlayer = PlayerAppearance.find_animation_player(mannequin)
	if animation != null and animation.has_animation(&"Idle"):
		animation.get_animation(&"Idle").loop_mode = Animation.LOOP_LINEAR
		animation.play(&"Idle")
	gel_mannequin = GEL_SCENE.instantiate() as Node3D
	gel_mannequin.name = "GelMannequin"
	gel_mannequin.visible = false
	world.add_child(gel_mannequin)
	var gel_mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(gel_mannequin)
	if gel_mesh != null:
		gel_mesh.material_override = GEL_MATERIAL
	_gel_shaper.setup(gel_mannequin)
	_gel_grounding = GelGrounding.new()
	_gel_grounding.name = "GelFootGrounding"
	world.add_child(_gel_grounding)
	_gel_grounding.setup(gel_mannequin)
	var gel_animation: AnimationPlayer = PlayerAppearance.find_animation_player(gel_mannequin)
	if gel_animation != null and gel_animation.has_animation(&"Idle"):
		gel_animation.get_animation(&"Idle").loop_mode = Animation.LOOP_LINEAR
		gel_animation.play(&"Idle")


## A soft round contact shadow: the character stands on something.
func _floor_shadow() -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(UiTheme.INK, 0.28))
	gradient.set_color(1, Color(UiTheme.INK, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.3, 1.3)
	var shadow := MeshInstance3D.new()
	shadow.name = "FloorShadow"
	shadow.mesh = quad
	shadow.material_override = material
	shadow.position.y = 0.005
	return shadow

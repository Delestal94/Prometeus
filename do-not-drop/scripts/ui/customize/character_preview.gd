extends SubViewportContainer
## The customisation screen's stage (N-506): the real player model, its real
## face (CharacterFace) and shirt tint, in a small lit studio of its own. The
## camera eases between a close-up of the head (face) and the whole body
## (uniform); drag with the mouse or push the right stick to turn the
## character. Presentation only, nothing here is saved or replicated.

const PLAYER_SCENE: PackedScene = preload("res://assets/models/characters/sm_char_player_rounded.glb")
const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const CharacterFace = preload("res://scripts/gameplay/player/gel/gel_face.gd")
const GelShaper = preload("res://scripts/gameplay/player/gel/gel_body_shaper.gd")
const GelGrounding = preload("res://scripts/gameplay/player/gel/gel_foot_grounding.gd")
const GelJiggleController = preload("res://scripts/gameplay/player/gel/gel_jiggle.gd")
const GelSquashController = preload("res://scripts/gameplay/player/gel/gel_squash_stretch.gd")
const GelWaveController = preload("res://scripts/gameplay/player/gel/gel_impact_waves.gd")
const GelDragController = preload("res://scripts/gameplay/player/gel/gel_inertial_drag.gd")
const HairAttachment = preload("res://scripts/gameplay/player/gel/gel_hair_attachment.gd")
const HairLibrary = preload("res://scripts/gameplay/player/gel/gel_hair_library.gd")
const CostumeCatalog = preload("res://scripts/gameplay/player/gel/gel_costume_catalog.gd")
const CostumeLibrary = preload("res://scripts/gameplay/player/gel/gel_costume_library.gd")
const CostumeFitter = preload("res://scripts/gameplay/player/gel/gel_costume_fitter.gd")
const CostumeSprings = preload("res://scripts/gameplay/player/gel/gel_costume_springs.gd")
const AccessoryCatalog = preload("res://scripts/gameplay/player/gel/gel_accessory_catalog.gd")
const AccessoryLibrary = preload("res://scripts/gameplay/player/gel/gel_accessory_library.gd")

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
var _gel_jiggle: Node
var _gel_squash: Node
var _gel_waves: Node
var _gel_drag: Node
var _hair_attachment: BoneAttachment3D
var _face_hair_attachments: Array[BoneAttachment3D] = []
var _costume: Node3D
var _costume_fitter
var _accessory: Node3D


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
	GameSettings.gel_material_mode_changed.connect(_set_opaque_gel)
	var shot: Dictionary = SHOTS[framing]
	_target = shot.target
	_distance = shot.distance
	_height = shot.height
	_place_camera()


## Shirt colour and expression, as everybody will see them.
func show_look(shirt: Color, eyes: StringName, mouth: StringName) -> void:
	PlayerAppearance.set_gel_team_accent(gel_mannequin, shirt)
	face.call(&"set_expression", eyes, mouth)


func show_skin(skin_id: StringName, team_color: Color) -> void:
	PlayerAppearance.apply_gel_skin(gel_mannequin, skin_id, team_color)


## Shows the editable gel body and applies only when its values changed.
func show_proportions(proportions: GelBodyProportions) -> void:
	mannequin.visible = false
	gel_mannequin.visible = true
	_gel_shaper.apply(proportions)
	if face is GelFace:
		(face as GelFace).apply_proportions(proportions)
	if _hair_attachment != null:
		_hair_attachment.call(&"apply_proportions", proportions)
	_fit_face_hair(proportions)
	if _costume_fitter != null:
		_costume_fitter.apply(proportions)
	if _gel_jiggle != null:
		_gel_jiggle.apply_proportions(proportions)


func show_character() -> void:
	mannequin.visible = false
	gel_mannequin.visible = true


## Rebuilds only the lightweight cosmetic roots; the gel body, camera and
## simulation controllers stay alive so changing a card is immediate.
func show_cosmetics(
	hair_id: StringName,
	eyebrows_id: StringName,
	moustache_id: StringName,
	costume_id: StringName,
	accessory_id: StringName,
	proportions: GelBodyProportions
) -> void:
	_clear_cosmetics()
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(gel_mannequin)
	if skeleton == null:
		return
	_hair_attachment = HairAttachment.new()
	_hair_attachment.call(&"setup", skeleton, hair_id, 1)
	_add_face_hair(skeleton, HairLibrary.build_eyebrows(eyebrows_id), eyebrows_id)
	_add_face_hair(skeleton, HairLibrary.build_moustache(moustache_id), moustache_id)
	_costume = CostumeLibrary.build_costume(costume_id)
	gel_mannequin.add_child(_costume)
	_costume_fitter = CostumeFitter.new()
	_costume_fitter.setup(_costume, gel_mannequin)
	var springs := CostumeSprings.new()
	_costume.add_child(springs)
	if not springs.setup(_costume):
		springs.free()
	if accessory_id != &"none":
		_accessory = AccessoryLibrary.build_accessory(accessory_id)
		gel_mannequin.add_child(_accessory)
	var hat_rule: int = _strongest_hat_rule(
		CostumeCatalog.costume(costume_id).get(&"hat_rule", &"none"),
		AccessoryCatalog.accessory(accessory_id).get(&"hat_rule", &"none") if accessory_id != &"none" else &"none"
	)
	_hair_attachment.call(&"set_hat_rule", hat_rule)
	show_proportions(proportions)


func _add_face_hair(skeleton: Skeleton3D, visual: Node3D, style_id: StringName) -> void:
	if style_id == &"none":
		visual.free()
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = visual.name
	attachment.bone_name = &"head"
	skeleton.add_child(attachment)
	attachment.add_child(visual)
	_face_hair_attachments.append(attachment)


func _fit_face_hair(proportions: GelBodyProportions) -> void:
	for attachment: BoneAttachment3D in _face_hair_attachments:
		if attachment.get_child_count() > 0:
			HairAttachment.fit_head_visual(attachment.get_child(0) as Node3D, proportions)


func _strongest_hat_rule(first: StringName, second: StringName) -> int:
	if first == &"hide" or second == &"hide":
		return HairAttachment.HatRule.HIDE
	if first == &"compress" or second == &"compress":
		return HairAttachment.HatRule.COMPRESS
	return HairAttachment.HatRule.NONE


func _clear_cosmetics() -> void:
	if is_instance_valid(_hair_attachment):
		_hair_attachment.free()
	_hair_attachment = null
	for attachment: BoneAttachment3D in _face_hair_attachments:
		if is_instance_valid(attachment):
			attachment.free()
	_face_hair_attachments.clear()
	if is_instance_valid(_costume):
		_costume.free()
	_costume = null
	_costume_fitter = null
	if is_instance_valid(_accessory):
		_accessory.free()
	_accessory = null


func proportion_application_count() -> int:
	return _gel_shaper.application_count


func _set_opaque_gel(use_opaque: bool) -> void:
	PlayerAppearance.set_gel_material(gel_mannequin, use_opaque)


## A quick squash and stretch: "that changed".
func bounce() -> void:
	if _bounce_tween != null:
		_bounce_tween.kill()
	gel_mannequin.scale = Vector3(1.06, 0.93, 1.06)
	_bounce_tween = create_tween()
	_bounce_tween.tween_property(gel_mannequin, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if gel_mannequin.visible and _gel_squash != null:
		_gel_squash.trigger_landing(4.5)
	if gel_mannequin.visible and _gel_waves != null:
		_gel_waves.add_local_impact(Vector3(0.0, 0.85, 0.28), 0.8)


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
	if gel_mannequin.visible and _gel_jiggle != null:
		_gel_jiggle.advance_motion(Vector3.ZERO, _yaw, true, delta)
	if gel_mannequin.visible and _gel_squash != null:
		_gel_squash.advance_motion(Vector3.ZERO, true, delta)
	if gel_mannequin.visible and _gel_waves != null:
		_gel_waves.advance(delta)
	if gel_mannequin.visible and _gel_drag != null:
		_gel_drag.advance_motion(Vector3.ZERO, _yaw, delta)
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
	mannequin.visible = false
	world.add_child(mannequin)
	var animation: AnimationPlayer = PlayerAppearance.find_animation_player(mannequin)
	if animation != null and animation.has_animation(&"Idle"):
		animation.get_animation(&"Idle").loop_mode = Animation.LOOP_LINEAR
		animation.play(&"Idle")
	gel_mannequin = GEL_SCENE.instantiate() as Node3D
	gel_mannequin.name = "GelMannequin"
	world.add_child(gel_mannequin)
	var gel_mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(gel_mannequin)
	if gel_mesh != null:
		PlayerAppearance.set_gel_material(gel_mannequin, GameSettings.uses_opaque_gel())
	PlayerAppearance.set_gel_look(gel_mannequin, Color(0.78, 0.82, 0.92), 1.0, 1.0)
	face = CharacterFace.new()
	face.call(&"setup", gel_mannequin, PlayerAppearance.find_skeleton(gel_mannequin), 1)
	_gel_shaper.setup(gel_mannequin)
	_gel_jiggle = GelJiggleController.new()
	_gel_jiggle.name = "GelJiggle"
	world.add_child(_gel_jiggle)
	_gel_jiggle.setup(gel_mannequin, GelBodyProportions.new(), multiplayer.get_unique_id())
	_gel_squash = GelSquashController.new()
	_gel_squash.name = "GelSquashStretch"
	world.add_child(_gel_squash)
	_gel_squash.setup(gel_mannequin)
	_gel_waves = GelWaveController.new()
	_gel_waves.name = "GelImpactWaves"
	world.add_child(_gel_waves)
	_gel_waves.setup(gel_mannequin)
	_gel_drag = GelDragController.new()
	_gel_drag.name = "GelInertialDrag"
	world.add_child(_gel_drag)
	_gel_drag.setup(gel_mannequin)
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

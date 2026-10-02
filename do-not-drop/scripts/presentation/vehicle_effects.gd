extends Node
## The truck's small physical tells, all pure presentation (never simulation,
## never replicated -- every client draws its own from the synced truck):
##   - exhaust smoke from the tail pipe, thicker under throttle (tareas #24);
##   - chips and dust thrown off a hard hit, where it happened (#40);
##   - dark tyre marks left on the road by a skidding wheel (#25);
##   - a brief chromatic split of the screen on a really hard hit, for whoever
##     rides inside (#13), scaled by the player's "camera shake" setting.
## Created by VehiclePresentation, which it reads for the wheels and cameras.

const WheelDust = preload("res://scripts/presentation/wheel_dust.gd")
## vehicle_presentation.gd and vehicle.gd have no class_name; this preloads them for the types (N-224.4).
const VehiclePresentation = preload("res://scripts/presentation/vehicle_presentation.gd")
const Vehicle = preload("res://scripts/gameplay/vehicle/vehicle.gd")
const GAME_SETTINGS := preload("res://scripts/core/game_settings.gd")

## A pale neutral grey, lighter than the asphalt behind it (N-324): the old dark
## 0.32 grey read as a row of dots. The alpha lives in the colour ramp.
const SMOKE_COLOR := Color(0.78, 0.78, 0.76)
## Smoke grey by time of day (DAY, DUSK, NIGHT): not the day grey times a light
## factor but a table with a floor. By day a warm grey, darker than the white box
## and lighter than the asphalt; at night a mid grey that still stands out against
## the dark road (a dimmed day grey vanished).
const SMOKE_GREY_BY_TIME: Array[float] = [0.78, 0.68, 0.5]
## Radial falloff of one puff (its own, not the dust's: that one halves the alpha
## at mid radius): full at the centre, 0.75 at 35 % of the radius, 0.35 at 70 %,
## clear at the rim: body enough to read, still no hard edge.
const SMOKE_FALLOFF_OFFSETS: Array[float] = [0.0, 0.35, 0.7, 1.0]
const SMOKE_FALLOFF_ALPHAS: Array[float] = [1.0, 0.75, 0.35, 0.0]
## Opacity over a puff's life: clear at birth, a veil with some body at the peak (not
## a solid ball: at 1.0 the puffs seen from the side looked like foam), then gone.
const SMOKE_LIFE_OFFSETS: Array[float] = [0.0, 0.1, 0.5, 1.0]
const SMOKE_LIFE_ALPHAS: Array[float] = [0.0, 0.85, 0.55, 0.0]
## Quad edge of one puff; it grows 0.5 -> 2.86 times that over its life, so the
## first is 0.22-0.24 m and the last 1.1-1.4 m (scale 0.9-1.1).
const SMOKE_PUFF_SIZE: float = 0.44
const SMOKE_GROW_FROM: float = 0.5
const SMOKE_GROW_TO: float = 2.86
## Few and big beat many and small; spaced out so the trail reads as puffs.
const SMOKE_PUFFS: int = 28
const SMOKE_LIFETIME: float = 2.4
## Back, a little toward the driver's side and barely up: the puffs travel 4-6 m behind
## the tail (initial speed 1.6-2.2 m/s, light damping 0.2-0.4), spread out into separate
## puffs, before the SMOKE_RISE lifts them. With damping above the rise (the first
## tuning) each puff stopped 0.6 m from the pipe and climbed in a column half hidden
## by the open left door. Sideways (-X) it hid behind that door.
const SMOKE_DIRECTION := Vector3(-0.15, 0.35, 1.0)
const SMOKE_RISE: float = 0.4
## Tail pipe: 0.2 m inside the side, at the box's rear edge (the rear step sticks out
## 0.27 m past it) and 0.1 m under the cargo floor, about 0.6 m above the road: high
## enough that a puff (up to 1.4 m wide) does not sink into it. SMOKE_PIPE_BACK is
## how far before the rear edge.
const SMOKE_PIPE_INSET: float = 0.2
const SMOKE_PIPE_BACK: float = 0.0
const SMOKE_PIPE_BELOW_FLOOR: float = 0.1
## If the truck lacks the floor box (a stripped-down test truck).
const SMOKE_PIPE_FALLBACK := Vector3(-0.88, -0.055, 4.49)
## Rain and fog thin the smoke, as they do the dust.
const SMOKE_WET_ALPHA: float = 0.6
const SMOKE_SAMPLE_SECONDS: float = 0.2
## Share of the puffs shown at idle; a full throttle brings them to 1.0.
const SMOKE_IDLE_RATIO: float = 0.7
const DEBRIS_MIN_STRENGTH: float = 7.0
const ABERRATION_MIN_STRENGTH: float = 9.0
const ABERRATION_SECONDS: float = 0.35
const SKID_MAX_MARKS: int = 600
const SKID_SPACING: float = 0.3
const SKID_MIN_SPEED_KMH: float = 12.0
## get_skidinfo() is 1 while the tyre grips and drops toward 0 as it slides.
const SKID_THRESHOLD: float = 0.55

var presentation: VehiclePresentation
var vehicle: Vehicle
var _exhaust: GPUParticles3D
var _smoke_material: ParticleProcessMaterial
static var _smoke_puff_material: StandardMaterial3D
var _smoke_sample_left: float = 0.0
var _skids: MultiMeshInstance3D
var _skid_next: int = 0
var _skid_last: Dictionary = {}
var _aberration: ColorRect
var _aberration_left: float = 0.0
var _aberration_peak: float = 0.0


func _ready() -> void:
	presentation = get_parent() as VehiclePresentation
	vehicle = presentation.vehicle
	_build_skid_marks()
	_build_aberration()
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"vehicle_impact", _on_impact)


func _process(delta: float) -> void:
	if _exhaust == null:
		_try_build_exhaust()
	if _exhaust != null:
		update_exhaust(delta)
	_update_skids()
	if _aberration_left > 0.0:
		_aberration_left = maxf(0.0, _aberration_left - delta)
		var amount: float = _aberration_peak * (_aberration_left / ABERRATION_SECONDS)
		(_aberration.material as ShaderMaterial).set_shader_parameter(&"amount", amount)
		_aberration.visible = amount > 0.0005


## Where the tail pipe sits, in the vehicle's space, from the cargo floor's box
## alone: its shape and transform are fixed on the body. Not from the art's AABB
## (it takes in the lowered ramp and the open rear doors and put the pipe 2.5 m
## behind the tail) and not from a wheel (VehicleWheel3D moves its own position
## with the suspension, and the pipe went 1.3 m under the road). Under the box at
## its rear corner on the driver's side (-X): SMOKE_PIPE_INSET inside the side,
## SMOKE_PIPE_BACK before the rear edge, SMOKE_PIPE_BELOW_FLOOR under the floor.
static func exhaust_anchor(vehicle_body: Node) -> Vector3:
	var anchor: Vector3 = SMOKE_PIPE_FALLBACK
	var floor_node := vehicle_body.get_node_or_null(^"FloorCollision") as CollisionShape3D
	if floor_node != null and floor_node.shape is BoxShape3D:
		var size: Vector3 = (floor_node.shape as BoxShape3D).size
		anchor.x = floor_node.position.x - size.x * 0.5 + SMOKE_PIPE_INSET
		anchor.z = floor_node.position.z + size.z * 0.5 - SMOKE_PIPE_BACK
		anchor.y = floor_node.position.y - size.y * 0.5 - SMOKE_PIPE_BELOW_FLOOR
	return anchor


## The tail pipe hangs on the vehicle, like the dust emitters (see exhaust_anchor),
## so it does not wait for the art: it is built on the first frame.
func _try_build_exhaust() -> void:
	_exhaust = GPUParticles3D.new()
	_exhaust.name = "ExhaustSmoke"
	_exhaust.amount = SMOKE_PUFFS
	_exhaust.lifetime = SMOKE_LIFETIME
	_exhaust.process_material = _build_smoke_material()
	# A soft, camera-facing puff; a low-poly sphere showed as a row of hard-edged dark dots.
	var puff := QuadMesh.new()
	puff.size = Vector2(SMOKE_PUFF_SIZE, SMOKE_PUFF_SIZE)
	puff.material = smoke_puff_material()
	_exhaust.draw_pass_1 = puff
	_exhaust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Rear is +Z (the truck faces -Z).
	_exhaust.position = exhaust_anchor(vehicle)
	# The smoke stays where it was born (world coordinates): the truck leaves it behind.
	# GPUParticles only simulate while a camera sees this box (30 m back: the plume left
	# behind at ~40 km/h): looking forward from the cab it sleeps, and that is the known limit.
	_exhaust.visibility_aabb = AABB(Vector3(-2.0, -1.0, -1.0), Vector3(4.0, 4.0, 30.0))
	vehicle.add_child(_exhaust)
	sample_smoke_look()


## Idle puffs now and then, a fuller plume under throttle. The engine's state and
## the throttle are read every frame (cheap); the light and the weather only every
## SMOKE_SAMPLE_SECONDS. Quiet while the viewer's camera is within CAMERA_CLEARANCE
## of the pipe, so no puff is born in the face of someone on the rack.
func update_exhaust(delta: float) -> void:
	_smoke_sample_left -= delta
	if _smoke_sample_left <= 0.0:
		sample_smoke_look()
	var running: bool = vehicle.presentation_engine_running
	var throttle: float = clampf(absf(vehicle.engine_force) / 1700.0, 0.0, 1.0)
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var near_camera: bool = camera != null and camera.global_position.distance_to(
			_exhaust.global_position) < WheelDust.CAMERA_CLEARANCE
	_exhaust.emitting = running and not near_camera
	_exhaust.amount_ratio = lerpf(SMOKE_IDLE_RATIO, 1.0, throttle)


## The smoke's grey follows the hour (SMOKE_GREY_BY_TIME, with a floor at night)
## and rain or fog thin it.
func sample_smoke_look() -> void:
	_smoke_sample_left = SMOKE_SAMPLE_SECONDS
	if _smoke_material == null:
		return
	var time_of_day: int = int(WorldMood.active.get("time", WorldMood.TimeOfDay.DAY))
	var grey: float = SMOKE_GREY_BY_TIME[clampi(time_of_day, 0, SMOKE_GREY_BY_TIME.size() - 1)]
	var thin: float = SMOKE_WET_ALPHA if WheelDust.wetness_now() > 0.0 else 1.0
	_smoke_material.color = Color(grey, grey, grey, thin)


func _build_smoke_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	_smoke_material = material
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.05
	material.direction = SMOKE_DIRECTION
	material.spread = 18.0
	# Slow and damped: the puffs follow one another along the plume instead of
	# piling up on the pipe, and it never gets far from the tail.
	material.initial_velocity_min = 1.6
	material.initial_velocity_max = 2.2
	material.gravity = Vector3(0.0, SMOKE_RISE, 0.0)
	material.damping_min = 0.2
	material.damping_max = 0.4
	material.scale_min = 0.9
	material.scale_max = 1.1
	material.angle_min = -180.0
	material.angle_max = 180.0
	material.angular_velocity_min = -25.0
	material.angular_velocity_max = 25.0
	material.color = SMOKE_COLOR
	var grow := Curve.new()
	# A Curve clamps its points to 0..1 unless told otherwise.
	grow.max_value = ceilf(SMOKE_GROW_TO)
	grow.add_point(Vector2(0.0, SMOKE_GROW_FROM))
	grow.add_point(Vector2(1.0, SMOKE_GROW_TO))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	material.scale_curve = grow_texture
	# Born clear, a light veil, then gone: never a solid ball.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array(SMOKE_LIFE_OFFSETS)
	var colors := PackedColorArray()
	for alpha: float in SMOKE_LIFE_ALPHAS:
		colors.append(Color(1, 1, 1, alpha))
	fade.colors = colors
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	material.color_ramp = fade_texture
	return material


## The puff's own soft disc (not the dust's, which halves the alpha at mid radius):
## SMOKE_FALLOFF_*, so the alpha that reaches the screen is not lowered and the
## quad still has no visible edge. Unshaded, billboard, alpha, no shadow; static
## and cached, one material for every truck. (proximity_fade needs the depth
## texture, which GL Compatibility lacks: the pipe is high enough not to need it.)
static func smoke_puff_material() -> StandardMaterial3D:
	if _smoke_puff_material != null:
		return _smoke_puff_material
	var falloff := Gradient.new()
	falloff.offsets = PackedFloat32Array(SMOKE_FALLOFF_OFFSETS)
	var colors := PackedColorArray()
	for alpha: float in SMOKE_FALLOFF_ALPHAS:
		colors.append(Color(1, 1, 1, alpha))
	falloff.colors = colors
	var disc := GradientTexture2D.new()
	disc.gradient = falloff
	disc.fill = GradientTexture2D.FILL_RADIAL
	disc.fill_from = Vector2(0.5, 0.5)
	disc.fill_to = Vector2(1.0, 0.5)
	disc.width = 64
	disc.height = 64
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.vertex_color_use_as_albedo = true
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.albedo_texture = disc
	look.disable_receive_shadows = true
	_smoke_puff_material = look
	return look


func _on_impact(strength: float, impact_position: Vector3) -> void:
	if vehicle.global_position.distance_to(impact_position) > 6.0:
		return
	if strength >= DEBRIS_MIN_STRENGTH:
		_burst_debris(impact_position, strength)
	if strength >= ABERRATION_MIN_STRENGTH and _riding_inside():
		var settings: GAME_SETTINGS = get_node_or_null(^"/root/GameSettings") as GAME_SETTINGS
		var scale: float = settings.camera_shake_scale if settings != null else 1.0
		_aberration_peak = clampf(strength / 20.0, 0.0, 1.0) * 0.018 * scale
		_aberration_left = ABERRATION_SECONDS if _aberration_peak > 0.0 else 0.0


func _burst_debris(at: Vector3, strength: float) -> void:
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = 70.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 2.0 + strength * 0.35
	material.gravity = Vector3(0.0, -9.8, 0.0)
	material.angular_velocity_min = -540.0
	material.angular_velocity_max = 540.0
	material.scale_min = 0.5
	material.scale_max = 1.3
	var tint := Gradient.new()
	tint.set_color(0, Color("5d5146"))
	tint.set_color(1, Color("a79a82"))
	var tint_texture := GradientTexture1D.new()
	tint_texture.gradient = tint
	material.color_initial_ramp = tint_texture
	var chip := BoxMesh.new()
	chip.size = Vector3(0.07, 0.03, 0.05)
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.roughness = 1.0
	chip.material = look
	var particles := GPUParticles3D.new()
	particles.name = "ImpactDebris"
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = clampi(int(strength * 2.5), 12, 60)
	particles.lifetime = 1.1
	particles.process_material = material
	particles.draw_pass_1 = chip
	var world: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	world.add_child(particles)
	particles.global_position = at + Vector3.UP * 0.3
	particles.reset_physics_interpolation()
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


func _build_skid_marks() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.24, SKID_SPACING + 0.08)
	quad.orientation = PlaneMesh.FACE_Y
	var look := StandardMaterial3D.new()
	look.albedo_color = Color(0.08, 0.08, 0.09, 0.55)
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Drawn a hair in front of the asphalt it sits on, never fighting it.
	look.render_priority = 1
	quad.material = look
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = SKID_MAX_MARKS
	multimesh.visible_instance_count = 0
	_skids = MultiMeshInstance3D.new()
	_skids.name = "SkidMarks"
	_skids.multimesh = multimesh
	_skids.top_level = true
	_skids.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_skids.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_skids)
	_skids.global_transform = Transform3D.IDENTITY


## Every SKID_SPACING metres a sliding, grounded wheel lays one dark strip
## under itself, oriented along the way it's travelling. A ring buffer: the
## oldest marks give way to new ones, so a long run never piles up.
func _update_skids() -> void:
	if vehicle.speed_kmh < SKID_MIN_SPEED_KMH:
		_skid_last.clear()
		return
	var multimesh: MultiMesh = _skids.multimesh
	for wheel: VehicleWheel3D in presentation.wheels():
		if not wheel.is_in_contact() or wheel.get_skidinfo() > SKID_THRESHOLD:
			_skid_last.erase(wheel)
			continue
		var ground: Vector3 = wheel.global_position - vehicle.global_basis.y * (wheel.wheel_radius - 0.03)
		var last: Variant = _skid_last.get(wheel)
		if last != null and (last as Vector3).distance_to(ground) < SKID_SPACING:
			continue
		var along: Vector3 = (ground - last) if last != null else -vehicle.global_basis.z
		var up: Vector3 = wheel.get_contact_normal() if wheel.get_contact_normal() != Vector3.ZERO else Vector3.UP
		along = (along - up * along.dot(up)).normalized()
		if along == Vector3.ZERO:
			continue
		var basis := Basis(up.cross(along).normalized(), up, along)
		multimesh.set_instance_transform(_skid_next, Transform3D(basis, ground + up * 0.02))
		_skid_next = (_skid_next + 1) % SKID_MAX_MARKS
		multimesh.visible_instance_count = mini(multimesh.visible_instance_count + 1, SKID_MAX_MARKS)
		_skid_last[wheel] = ground


func _build_aberration() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ImpactAberration"
	layer.layer = 0
	add_child(layer)
	_aberration = ColorRect.new()
	_aberration.set_anchors_preset(Control.PRESET_FULL_RECT)
	_aberration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen: hint_screen_texture, filter_linear;
uniform float amount = 0.0;
void fragment() {
	vec2 from_centre = SCREEN_UV - vec2(0.5);
	vec2 shift = from_centre * amount;
	float r = texture(screen, SCREEN_UV + shift).r;
	float g = texture(screen, SCREEN_UV).g;
	float b = texture(screen, SCREEN_UV - shift).b;
	COLOR = vec4(r, g, b, 1.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	_aberration.material = material
	_aberration.visible = false
	layer.add_child(_aberration)


## Only for whoever is actually aboard: a pedestrian watching the truck hit
## something shouldn't have their own view split.
func _riding_inside() -> bool:
	var camera: Camera3D = get_viewport().get_camera_3d()
	return camera != null and presentation.is_seat_camera(camera)

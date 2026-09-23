extends Node
## The truck's small physical tells, all pure presentation (never simulation,
## never replicated -- every client draws its own from the synced truck):
##   - exhaust smoke from the tail pipe, thicker under throttle (tareas #24);
##   - chips and dust thrown off a hard hit, where it happened (#40);
##   - dark tyre marks left on the road by a skidding wheel (#25);
##   - a brief chromatic split of the screen on a really hard hit, for whoever
##     rides inside (#13), scaled by the player's "camera shake" setting.
## Created by VehiclePresentation, which it reads for the wheels and cameras.

const SMOKE_COLOR := Color(0.32, 0.33, 0.34, 0.42)
const DEBRIS_MIN_STRENGTH: float = 7.0
const ABERRATION_MIN_STRENGTH: float = 9.0
const ABERRATION_SECONDS: float = 0.35
const SKID_MAX_MARKS: int = 600
const SKID_SPACING: float = 0.3
const SKID_MIN_SPEED_KMH: float = 12.0
## get_skidinfo() is 1 while the tyre grips and drops toward 0 as it slides.
const SKID_THRESHOLD: float = 0.55

var presentation: Node
var vehicle: VehicleBody3D
var _exhaust: GPUParticles3D
var _skids: MultiMeshInstance3D
var _skid_next: int = 0
var _skid_last: Dictionary = {}
var _aberration: ColorRect
var _aberration_left: float = 0.0
var _aberration_peak: float = 0.0


func _ready() -> void:
	presentation = get_parent()
	vehicle = presentation.get(&"vehicle")
	_build_skid_marks()
	_build_aberration()
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"vehicle_impact", _on_impact)


func _process(delta: float) -> void:
	if _exhaust == null:
		_try_build_exhaust()
	if _exhaust != null:
		var running: bool = bool(vehicle.get(&"presentation_engine_running"))
		var throttle: float = clampf(absf(vehicle.engine_force) / 1700.0, 0.0, 1.0)
		_exhaust.emitting = running
		_exhaust.amount_ratio = lerpf(0.25, 1.0, throttle)
	_update_skids()
	if _aberration_left > 0.0:
		_aberration_left = maxf(0.0, _aberration_left - delta)
		var amount: float = _aberration_peak * (_aberration_left / ABERRATION_SECONDS)
		(_aberration.material as ShaderMaterial).set_shader_parameter(&"amount", amount)
		_aberration.visible = amount > 0.0005


## The truck's art is hung at runtime (reference_truck.gd), after this node
## is ready: the tail pipe goes at the back left corner of whatever was built.
func _try_build_exhaust() -> void:
	var body: Node3D = presentation.get(&"body_visuals")
	if body == null:
		return
	var bounds := AABB()
	var first: bool = true
	for mesh: Node in body.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (body.global_transform.affine_inverse() * (mesh as Node3D).global_transform) * (mesh as MeshInstance3D).get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		return
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0.0, 0.35, 1.0)
	material.spread = 12.0
	material.initial_velocity_min = 0.6
	material.initial_velocity_max = 1.2
	material.gravity = Vector3(0.0, 0.5, 0.0)
	material.damping_min = 0.6
	material.damping_max = 1.0
	material.scale_min = 0.6
	material.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 3.2))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	material.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, SMOKE_COLOR)
	fade.set_color(1, Color(SMOKE_COLOR, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	material.color_ramp = fade_texture
	# A soft low-poly blob rather than a cube, so it reads as smoke.
	var puff := SphereMesh.new()
	puff.radius = 0.15
	puff.height = 0.28
	puff.radial_segments = 6
	puff.rings = 3
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.vertex_color_use_as_albedo = true
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = look
	_exhaust = GPUParticles3D.new()
	_exhaust.name = "ExhaustSmoke"
	_exhaust.amount = 18
	_exhaust.lifetime = 1.8
	_exhaust.process_material = material
	_exhaust.draw_pass_1 = puff
	_exhaust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Rear is +Z (the truck faces -Z); low on the driver's side, under the bed.
	_exhaust.position = Vector3(bounds.position.x + 0.45, bounds.position.y + 0.32, bounds.end.z - 0.15)
	_exhaust.visibility_aabb = AABB(Vector3(-2.0, -1.0, -1.0), Vector3(4.0, 4.0, 6.0))
	body.add_child(_exhaust)


func _on_impact(strength: float, impact_position: Vector3) -> void:
	if vehicle.global_position.distance_to(impact_position) > 6.0:
		return
	if strength >= DEBRIS_MIN_STRENGTH:
		_burst_debris(impact_position, strength)
	if strength >= ABERRATION_MIN_STRENGTH and _riding_inside():
		var settings: Node = get_node_or_null(^"/root/GameSettings")
		var scale: float = float(settings.get(&"camera_shake_scale")) if settings != null else 1.0
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
	for wheel: VehicleWheel3D in presentation.get(&"_wheels"):
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
	return camera != null and camera in (presentation.get(&"_seat_cameras") as Array)

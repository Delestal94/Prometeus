class_name GelPlayerVFX
extends Node
## Bounded, presentation-only gel accents: landing drops/splash/bubbles, a
## short world-space running trail and fading floor/wall marks. Every effect
## reads the mesh instance colour and owns a fixed resource budget.

const LANDING_DROP_COUNT: int = 12
const SPLASH_COUNT: int = 10
const BUBBLE_COUNT: int = 7
const TRAIL_COUNT: int = 16
const MAX_MARKS: int = 12
const MARK_LIFETIME: float = 3.5
const LANDING_MIN_SPEED: float = 2.5
const TRAIL_MIN_SPEED: float = 3.2
const WALL_MARK_MIN_SPEED: float = 5.5
const WALL_MARK_COOLDOWN: float = 0.16
const MARK_SHADER_SOURCE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.5, 0.9, 0.75, 0.62);
void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float angle = atan(point.y, point.x);
	float edge = 0.76 + sin(angle * 5.0 + 0.7) * 0.09 + sin(angle * 9.0) * 0.045;
	float mask = 1.0 - smoothstep(edge - 0.12, edge, length(point));
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.18;
	ALPHA = tint.a * mask;
}
"""

var _mesh: MeshInstance3D
var _player: CharacterBody3D
var _landing_drops: GPUParticles3D
var _landing_splash: GPUParticles3D
var _landing_bubbles: GPUParticles3D
var _running_trail: GPUParticles3D
var _particles: Array[GPUParticles3D] = []
var _marks: Array[Dictionary] = []
var _gel_color: Color = Color("83e2ba")
var _last_velocity: Vector3 = Vector3.ZERO
var _was_grounded: bool = true
var _has_motion_sample: bool = false
var _wall_mark_cooldown: float = 0.0
var _mark_shader: Shader


func _exit_tree() -> void:
	# Marks live in world space rather than under the player. Queue their
	# cleanup because the player parent is already busy leaving the tree.
	for mark: Dictionary in _marks:
		var node := mark[&"node"] as MeshInstance3D
		if is_instance_valid(node):
			node.queue_free()
	_marks.clear()
	for particles: GPUParticles3D in _particles:
		if is_instance_valid(particles):
			particles.emitting = false


func setup(model: Node, player: CharacterBody3D) -> bool:
	_mesh = PlayerAppearance.find_mesh_instance(model)
	_player = player
	if _mesh == null or not model is Node3D:
		return false
	_mark_shader = Shader.new()
	_mark_shader.code = MARK_SHADER_SOURCE
	_landing_drops = _build_particles(&"LandingDrops", LANDING_DROP_COUNT, 0.72)
	_landing_splash = _build_particles(&"LandingSplash", SPLASH_COUNT, 0.48)
	_landing_bubbles = _build_particles(&"LandingBubbles", BUBBLE_COUNT, 0.9)
	_running_trail = _build_particles(&"RunningTrail", TRAIL_COUNT, 0.36)
	_particles = [_landing_drops, _landing_splash, _landing_bubbles, _running_trail]
	for particles: GPUParticles3D in _particles:
		(model as Node3D).add_child(particles)
		particles.position = Vector3(0.0, 0.08, 0.0)
	_configure_motions()
	_running_trail.one_shot = false
	_running_trail.local_coords = false
	_running_trail.emitting = false
	reset_motion()
	sync_color()
	return true


func update_vfx(player: CharacterBody3D, delta: float, effects_enabled: bool = true) -> void:
	var step: float = maxf(delta, 0.0)
	_wall_mark_cooldown = maxf(_wall_mark_cooldown - step, 0.0)
	advance_marks(step)
	sync_color()
	var grounded: bool = player.is_on_floor()
	if not _has_motion_sample:
		_last_velocity = player.velocity
		_was_grounded = grounded
		_has_motion_sample = true
		set_trail_active(false)
		return
	if effects_enabled and not _was_grounded and grounded:
		var landing_speed: float = absf(minf(_last_velocity.y, 0.0))
		if landing_speed >= LANDING_MIN_SPEED:
			trigger_landing(landing_speed, player.global_position)
	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	set_trail_active(effects_enabled and grounded and horizontal_speed >= TRAIL_MIN_SPEED)
	if effects_enabled:
		_check_wall_marks(player)
	_last_velocity = player.velocity
	_was_grounded = grounded


func trigger_landing(speed: float, world_position: Vector3) -> void:
	if speed < LANDING_MIN_SPEED:
		return
	sync_color()
	for particles: GPUParticles3D in [_landing_drops, _landing_splash, _landing_bubbles]:
		particles.restart()
		particles.emitting = true
	spawn_mark(world_position + Vector3.UP * 0.012, Vector3.UP, 0.34)


func spawn_mark(world_position: Vector3, world_normal: Vector3, size: float = 0.26) -> void:
	var normal: Vector3 = world_normal.normalized()
	if normal.length_squared() <= 0.000001:
		normal = Vector3.UP
	while _marks.size() >= MAX_MARKS:
		_free_mark(0)
	var mark := MeshInstance3D.new()
	mark.name = &"GelMark"
	mark.add_to_group(&"gel_vfx_mark")
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * clampf(size, 0.08, 0.55)
	quad.orientation = PlaneMesh.FACE_Z
	mark.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = _mark_shader
	material.set_shader_parameter(&"tint", Color(_gel_color, 0.62))
	mark.material_override = material
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(mark)
	mark.global_position = world_position + normal * 0.006
	var up: Vector3 = Vector3.FORWARD if absf(normal.dot(Vector3.UP)) > 0.92 else Vector3.UP
	mark.look_at(mark.global_position + normal, up)
	_marks.append({&"node": mark, &"material": material, &"normal": normal, &"age": 0.0})


func advance_marks(delta: float) -> void:
	var step: float = maxf(delta, 0.0)
	for index: int in range(_marks.size() - 1, -1, -1):
		var mark: Dictionary = _marks[index]
		mark[&"age"] = float(mark[&"age"]) + step
		var age: float = float(mark[&"age"])
		if age >= MARK_LIFETIME:
			_free_mark(index)
			continue
		var material := mark[&"material"] as ShaderMaterial
		material.set_shader_parameter(
			&"tint", Color(_gel_color, 0.62 * (1.0 - age / MARK_LIFETIME))
		)


func sync_color() -> void:
	if _mesh == null or not is_instance_valid(_mesh):
		return
	var color: Variant = _mesh.get_instance_shader_parameter(&"gel_color")
	if color is Color:
		_gel_color = color
	for particles: GPUParticles3D in _particles:
		var motion := particles.process_material as ParticleProcessMaterial
		if motion != null:
			motion.color = _gel_color


func set_trail_active(active: bool) -> void:
	if _running_trail != null:
		_running_trail.emitting = active


func reset_motion() -> void:
	_last_velocity = Vector3.ZERO
	_was_grounded = true
	_has_motion_sample = false
	_wall_mark_cooldown = 0.0
	set_trail_active(false)


func clear_all() -> void:
	for index: int in range(_marks.size() - 1, -1, -1):
		_free_mark(index)
	for particles: GPUParticles3D in _particles:
		if is_instance_valid(particles):
			particles.emitting = false


func mark_count() -> int:
	return _marks.size()


func mark_alpha(index: int) -> float:
	var material := _marks[index][&"material"] as ShaderMaterial
	return (material.get_shader_parameter(&"tint") as Color).a


func mark_normal(index: int) -> Vector3:
	return _marks[index][&"normal"] as Vector3


func mark_color(index: int) -> Color:
	var material := _marks[index][&"material"] as ShaderMaterial
	return material.get_shader_parameter(&"tint") as Color


func particle_budget() -> int:
	return LANDING_DROP_COUNT + SPLASH_COUNT + BUBBLE_COUNT + TRAIL_COUNT


func all_particles() -> Array[GPUParticles3D]:
	return _particles.duplicate()


func landing_drops() -> GPUParticles3D:
	return _landing_drops


func landing_splash() -> GPUParticles3D:
	return _landing_splash


func landing_bubbles() -> GPUParticles3D:
	return _landing_bubbles


func running_trail() -> GPUParticles3D:
	return _running_trail


func _check_wall_marks(player: CharacterBody3D) -> void:
	if _wall_mark_cooldown > 0.0:
		return
	for index: int in player.get_slide_collision_count():
		var collision: KinematicCollision3D = player.get_slide_collision(index)
		var normal: Vector3 = collision.get_normal()
		if absf(normal.y) > 0.72:
			continue
		var speed: float = maxf(-_last_velocity.dot(normal), 0.0)
		if speed >= WALL_MARK_MIN_SPEED:
			spawn_mark(collision.get_position(), normal, 0.24)
			_wall_mark_cooldown = WALL_MARK_COOLDOWN
			return


func _configure_motions() -> void:
	_configure_motion(_landing_drops, Vector3.UP, 78.0, 1.1, 2.7, Vector3(0.0, -8.5, 0.0), 0.18)
	_configure_motion(_landing_splash, Vector3.UP, 88.0, 0.35, 1.25, Vector3(0.0, -5.0, 0.0), 0.3)
	_configure_motion(_landing_bubbles, Vector3.UP, 26.0, 0.35, 0.9, Vector3(0.0, 1.1, 0.0), 0.22)
	_configure_motion(_running_trail, Vector3.UP, 38.0, 0.08, 0.35, Vector3(0.0, 0.35, 0.0), 0.16)


func _configure_motion(particles: GPUParticles3D, direction: Vector3, spread: float,
		velocity_min: float, velocity_max: float, gravity: Vector3, radius: float) -> void:
	var motion := particles.process_material as ParticleProcessMaterial
	motion.direction = direction
	motion.spread = spread
	motion.initial_velocity_min = velocity_min
	motion.initial_velocity_max = velocity_max
	motion.gravity = gravity
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = radius
	motion.scale_min = 0.55
	motion.scale_max = 1.3


func _build_particles(node_name: StringName, count: int, lifetime: float) -> GPUParticles3D:
	var drop_mesh := SphereMesh.new()
	drop_mesh.radius = 0.03
	drop_mesh.height = 0.06
	drop_mesh.radial_segments = 6
	drop_mesh.rings = 3
	var surface := StandardMaterial3D.new()
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.albedo_color = Color(1.0, 1.0, 1.0, 0.76)
	surface.roughness = 0.12
	surface.metallic_specular = 0.8
	surface.vertex_color_use_as_albedo = true
	drop_mesh.material = surface
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.emitting = false
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = lifetime
	particles.explosiveness = 1.0
	particles.visibility_aabb = AABB(Vector3(-2.0, -1.0, -2.0), Vector3(4.0, 4.0, 4.0))
	particles.draw_pass_1 = drop_mesh
	particles.process_material = ParticleProcessMaterial.new()
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


func _free_mark(index: int) -> void:
	var node := _marks[index][&"node"] as MeshInstance3D
	_marks.remove_at(index)
	if is_instance_valid(node):
		node.free()

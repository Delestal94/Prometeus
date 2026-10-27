class_name GelKnockout
extends Node
## Presentation-only knockout for the gel body. A replicated cause on
## PlayerGelEffects selects one of the reversible shapes; this component owns
## the shared timeline, packed shader state and two bounded droplet bursts.

enum Phase { ALIVE, MELTING, PUDDLE, REASSEMBLING }
enum Cause { NONE, MELT, CRUSHED, EXPLOSION, WATER, RUN_OVER }

const MELT_SECONDS: float = 0.85
const REASSEMBLE_SECONDS: float = 1.05
const MELT_DROP_COUNT: int = 18
const REASSEMBLE_DROP_COUNT: int = 14
const MAX_SHADER_AMOUNT: float = 0.999

var phase: Phase = Phase.ALIVE
var cause: Cause = Cause.NONE
var amount: float = 0.0
var _mesh: MeshInstance3D
var _melt_drops: GPUParticles3D
var _reassemble_drops: GPUParticles3D


func setup(model: Node) -> bool:
	_mesh = PlayerAppearance.find_mesh_instance(model)
	if _mesh == null:
		return false
	_melt_drops = _build_drops(&"KnockoutMeltDrops", MELT_DROP_COUNT, false)
	_reassemble_drops = _build_drops(&"KnockoutReassembleDrops", REASSEMBLE_DROP_COUNT, true)
	add_child(_melt_drops)
	add_child(_reassemble_drops)
	_melt_drops.position = Vector3(0.0, 0.72, 0.0)
	_reassemble_drops.position = Vector3(0.0, 0.06, 0.0)
	reset()
	return true


func set_knocked_out(active: bool) -> void:
	set_knockout_cause(Cause.MELT if active else Cause.NONE)


func set_knockout_cause(next_cause: Cause) -> void:
	if next_cause == Cause.NONE:
		if phase == Phase.ALIVE or phase == Phase.REASSEMBLING:
			return
		phase = Phase.REASSEMBLING
		_configure_drops(_reassemble_drops, cause, true)
		_emit(_reassemble_drops)
		return
	if cause == next_cause and (phase == Phase.PUDDLE or phase == Phase.MELTING):
		return
	cause = next_cause
	phase = Phase.MELTING
	_configure_drops(_melt_drops, cause, false)
	_emit(_melt_drops)
	_write_shader_amount()


func advance(delta: float) -> void:
	var step: float = maxf(delta, 0.0)
	match phase:
		Phase.MELTING:
			amount = move_toward(amount, 1.0, step / MELT_SECONDS)
			if is_equal_approx(amount, 1.0):
				amount = 1.0
				phase = Phase.PUDDLE
		Phase.REASSEMBLING:
			amount = move_toward(amount, 0.0, step / REASSEMBLE_SECONDS)
			if is_zero_approx(amount):
				amount = 0.0
				phase = Phase.ALIVE
				cause = Cause.NONE
	_write_shader_amount()


func reset() -> void:
	phase = Phase.ALIVE
	cause = Cause.NONE
	amount = 0.0
	if _melt_drops != null:
		_melt_drops.emitting = false
	if _reassemble_drops != null:
		_reassemble_drops.emitting = false
	_write_shader_amount()


func is_active() -> bool:
	return phase != Phase.ALIVE


func melt_drops() -> GPUParticles3D:
	return _melt_drops


func reassemble_drops() -> GPUParticles3D:
	return _reassemble_drops


func _write_shader_amount() -> void:
	if _mesh != null and is_instance_valid(_mesh):
		# Positive values remain contact compression. A negative integer packs
		# the cause and its fractional part packs the transition amount, keeping
		# both gel shaders within the 16-uniform limit.
		var packed: float = 0.0
		if cause != Cause.NONE:
			packed = -(float(cause) + minf(amount, MAX_SHADER_AMOUNT))
		_mesh.set_instance_shader_parameter(
			&"gel_contact_compression", packed
		)


func _emit(particles: GPUParticles3D) -> void:
	if particles == null:
		return
	var color: Variant = _mesh.get_instance_shader_parameter(&"gel_color")
	var material := particles.process_material as ParticleProcessMaterial
	if material != null and color is Color:
		material.color = color
	particles.layers = _mesh.layers
	particles.restart()
	particles.emitting = true


func _configure_drops(particles: GPUParticles3D, active_cause: Cause, returning: bool) -> void:
	var motion := particles.process_material as ParticleProcessMaterial
	if motion == null:
		return
	if returning:
		motion.direction = Vector3.UP
		motion.spread = 28.0
		motion.initial_velocity_min = 0.35
		motion.initial_velocity_max = 0.9
		motion.gravity = Vector3(0.0, 1.8, 0.0)
		motion.emission_sphere_radius = 0.72 if active_cause == Cause.EXPLOSION else 0.5
		motion.radial_accel_min = -9.0 if active_cause == Cause.EXPLOSION else -5.0
		motion.radial_accel_max = -6.0 if active_cause == Cause.EXPLOSION else -3.0
		return
	motion.radial_accel_min = 0.0
	motion.radial_accel_max = 0.0
	match active_cause:
		Cause.CRUSHED:
			motion.direction = Vector3(1.0, 0.12, 0.0)
			motion.spread = 58.0
			motion.initial_velocity_min = 0.8
			motion.initial_velocity_max = 1.8
			motion.gravity = Vector3(0.0, -7.0, 0.0)
			motion.emission_sphere_radius = 0.28
		Cause.EXPLOSION:
			motion.direction = Vector3.UP
			motion.spread = 180.0
			motion.initial_velocity_min = 2.8
			motion.initial_velocity_max = 4.8
			motion.gravity = Vector3(0.0, -6.5, 0.0)
			motion.emission_sphere_radius = 0.36
		Cause.WATER:
			motion.direction = Vector3.DOWN
			motion.spread = 32.0
			motion.initial_velocity_min = 0.35
			motion.initial_velocity_max = 1.1
			motion.gravity = Vector3(0.0, -2.0, 0.0)
			motion.emission_sphere_radius = 0.42
		Cause.RUN_OVER:
			motion.direction = Vector3(1.0, 0.08, 0.0)
			motion.spread = 18.0
			motion.initial_velocity_min = 1.5
			motion.initial_velocity_max = 3.0
			motion.gravity = Vector3(0.0, -8.5, 0.0)
			motion.emission_sphere_radius = 0.22
		_:
			motion.direction = Vector3.UP
			motion.spread = 72.0
			motion.initial_velocity_min = 1.3
			motion.initial_velocity_max = 2.8
			motion.gravity = Vector3(0.0, -8.5, 0.0)
			motion.emission_sphere_radius = 0.2


func _build_drops(node_name: StringName, count: int, rising: bool) -> GPUParticles3D:
	var drop_mesh := SphereMesh.new()
	drop_mesh.radius = 0.035
	drop_mesh.height = 0.07
	drop_mesh.radial_segments = 6
	drop_mesh.rings = 3
	var drop_surface := StandardMaterial3D.new()
	drop_surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_surface.albedo_color = Color(1.0, 1.0, 1.0, 0.84)
	drop_surface.roughness = 0.12
	drop_surface.metallic_specular = 0.85
	drop_surface.vertex_color_use_as_albedo = true
	drop_mesh.material = drop_surface

	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 24.0 if rising else 72.0
	motion.initial_velocity_min = 0.45 if rising else 1.3
	motion.initial_velocity_max = 1.15 if rising else 2.8
	motion.gravity = Vector3(0.0, 2.4 if rising else -8.5, 0.0)
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.48 if rising else 0.2
	motion.radial_accel_min = -5.0 if rising else 0.0
	motion.radial_accel_max = -3.0 if rising else 0.0
	motion.scale_min = 0.65
	motion.scale_max = 1.35
	motion.color = Color("83e2ba")

	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.emitting = false
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = 0.72
	particles.explosiveness = 1.0
	particles.visibility_aabb = AABB(Vector3(-2.0, -1.0, -2.0), Vector3(4.0, 4.0, 4.0))
	particles.draw_pass_1 = drop_mesh
	particles.process_material = motion
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles

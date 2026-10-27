class_name GelKnockout
extends Node
## Presentation-only knockout for the gel body. A replicated boolean on Player
## selects the target state; this component owns the reversible melt timeline,
## shader deformation and two bounded one-shot droplet bursts.

enum Phase { ALIVE, MELTING, PUDDLE, REASSEMBLING }

const MELT_SECONDS: float = 0.85
const REASSEMBLE_SECONDS: float = 1.05
const MELT_DROP_COUNT: int = 18
const REASSEMBLE_DROP_COUNT: int = 14
const PACKED_KNOCKOUT_MIN: float = -1.0

var phase: Phase = Phase.ALIVE
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
	if active:
		if phase == Phase.PUDDLE or phase == Phase.MELTING:
			return
		phase = Phase.MELTING
		_emit(_melt_drops)
	else:
		if phase == Phase.ALIVE or phase == Phase.REASSEMBLING:
			return
		phase = Phase.REASSEMBLING
		_emit(_reassemble_drops)


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
	_write_shader_amount()


func reset() -> void:
	phase = Phase.ALIVE
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
		# Positive values remain contact compression. Negative values encode the
		# knockout amount so both gel shaders stay within the 16-uniform limit.
		_mesh.set_instance_shader_parameter(
			&"gel_contact_compression", lerpf(0.0, PACKED_KNOCKOUT_MIN, amount)
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

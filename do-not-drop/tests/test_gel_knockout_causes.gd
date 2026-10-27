extends SceneTree
## S-311.93: each replicated knockout cause selects a distinct bounded particle
## motion and shader silhouette, while all four reverse through the same safe
## reassembly path.

const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const Knockout = preload("res://scripts/gameplay/player/gel/gel_knockout.gd")
const CAUSES: Array[int] = [
	Knockout.Cause.CRUSHED,
	Knockout.Cause.EXPLOSION,
	Knockout.Cause.WATER,
	Knockout.Cause.RUN_OVER,
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	await process_frame
	var effects := player.get_node(^"GelEffects") as PlayerGelEffects
	var knockout: Node = effects.get_node(^"GelKnockout")
	var body: Node3D = player.get(&"_body_visual") as Node3D
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(body)
	_expect(effects != null and knockout != null and mesh != null,
		"the player exposes the cause-aware knockout component")
	_check_replication(player)
	_check_shader_contract()
	for cause: int in CAUSES:
		_check_cause(effects, knockout, mesh, cause)

	player.free()
	if _failures == 0:
		print("PASS: crushed, explosion, water and run-over knockouts stay distinct and reversible")
	quit(_failures)


func _check_cause(effects: PlayerGelEffects, knockout: Node,
		mesh: MeshInstance3D, cause: int) -> void:
	_expect(effects.set_local_knockout_cause(cause),
		"the owner can publish knockout cause %d" % cause)
	_expect(effects.knockout_cause == cause and knockout.cause == cause,
		"cause %d reaches the visual component" % cause)
	knockout.advance(Knockout.MELT_SECONDS * 0.5)
	var packed: float = -float(mesh.get_instance_shader_parameter(&"gel_contact_compression"))
	var packed_cause: int = int(floor(packed + 0.0001))
	var packed_amount: float = packed - floor(packed)
	_expect(packed_cause == cause and packed_amount > 0.45 and packed_amount < 0.55,
		"cause %d and its transition share one bounded shader uniform" % cause)
	_check_particle_motion(knockout.melt_drops(), cause)
	knockout.advance(Knockout.MELT_SECONDS)
	_expect(knockout.phase == Knockout.Phase.PUDDLE and is_equal_approx(knockout.amount, 1.0),
		"cause %d reaches its held final silhouette" % cause)
	_expect(effects.set_local_knocked_out(false), "the owner can clear cause %d" % cause)
	var returning := knockout.reassemble_drops().process_material as ParticleProcessMaterial
	_expect(returning != null and returning.radial_accel_max < 0.0,
		"cause %d pulls its bounded drops back toward the body" % cause)
	knockout.advance(Knockout.REASSEMBLE_SECONDS + 0.05)
	_expect(knockout.phase == Knockout.Phase.ALIVE
			and knockout.cause == Knockout.Cause.NONE
			and is_zero_approx(float(mesh.get_instance_shader_parameter(
				&"gel_contact_compression"))),
		"cause %d reassembles to the exact alive state" % cause)


func _check_particle_motion(particles: GPUParticles3D, cause: int) -> void:
	var motion := particles.process_material as ParticleProcessMaterial
	_expect(particles.one_shot and particles.amount == Knockout.MELT_DROP_COUNT,
		"cause %d keeps a fixed outgoing droplet budget" % cause)
	match cause:
		Knockout.Cause.CRUSHED:
			_expect(motion.direction.x > 0.9 and motion.spread > 50.0,
				"crushing squirts the pancake sideways")
		Knockout.Cause.EXPLOSION:
			_expect(is_equal_approx(motion.spread, 180.0)
					and motion.initial_velocity_min > 2.5,
				"explosion throws droplets radially before reassembly")
		Knockout.Cause.WATER:
			_expect(motion.direction.is_equal_approx(Vector3.DOWN)
					and motion.gravity.y < 0.0,
				"water dissolution carries gel downward")
		Knockout.Cause.RUN_OVER:
			_expect(motion.direction.x > 0.9 and motion.spread < 20.0,
				"run-over droplets follow a narrow wheel-direction skid")


func _check_replication(player: Player) -> void:
	var sync := player.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var path := NodePath("GelEffects:knockout_cause")
	_expect(sync.replication_config.has_property(path)
			and sync.replication_config.property_get_spawn(path)
			and sync.replication_config.property_get_replication_mode(path)
				== SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE,
		"the exact cause reaches peers and late joiners")


func _check_shader_contract() -> void:
	for path: String in [
		"res://shaders/gel/gel_body.gdshader",
		"res://shaders/gel/gel_body_opaque.gdshader",
	]:
		var source: String = FileAccess.get_file_as_string(path)
		_expect(source.count("instance uniform ") == 16,
			"%s preserves the per-instance uniform budget" % path)
		for marker: String in ["Crushed:", "Explosion:", "Water:", "Run over:"]:
			_expect(source.contains(marker), "%s implements %s" % [path, marker])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

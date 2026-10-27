extends SceneTree
## S-311.92: the replicated gel knockout melts through the shared shader into
## a held puddle, emits bounded colour-matched drops and reverses cleanly when
## the player respawns.

const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const Knockout = preload("res://scripts/gameplay/player/gel/gel_knockout.gd")

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
	var contact: Node = effects.get_node(^"GelContact")
	var body: Node3D = player.get(&"_body_visual") as Node3D
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(body)
	_expect(effects != null and knockout != null and mesh != null,
		"the real player owns one knockout component bound to its gel mesh")
	_check_replication(player)
	_check_shader_contract()
	contact.trigger_contact(Vector3.RIGHT, 2.0)
	contact.advance(0.05)
	_expect(float(mesh.get_instance_shader_parameter(&"gel_contact_compression")) > 0.05,
		"the shared packed channel still carries ordinary contact compression")

	_expect(effects.set_local_knocked_out(true), "the local owner can start knockout")
	_expect(effects.knocked_out and knockout.phase == Knockout.Phase.MELTING,
		"knockout enters the melt phase")
	var face := player.get_node(^"GelFaceReactions") as GelFaceReactions
	_expect(face.knocked_out, "the existing X-eyes face follows knockout")
	knockout.advance(Knockout.MELT_SECONDS * 0.45)
	var packed_mid: float = float(mesh.get_instance_shader_parameter(
		&"gel_contact_compression"))
	_expect(knockout.amount > 0.4 and knockout.amount < 0.5 and packed_mid < -0.4,
		"the reversible timeline uploads a negative packed shader amount")
	knockout.advance(Knockout.MELT_SECONDS)
	_expect(knockout.phase == Knockout.Phase.PUDDLE
			and is_equal_approx(knockout.amount, 1.0),
		"the body holds as a puddle until respawn")
	_check_drops(knockout, mesh)

	_expect(effects.set_local_knocked_out(false), "the local owner can start respawn")
	knockout.advance(Knockout.REASSEMBLE_SECONDS * 0.5)
	_expect(knockout.phase == Knockout.Phase.REASSEMBLING
			and knockout.amount > 0.45 and knockout.amount < 0.55,
		"respawn reverses the same deformation without a visual jump")
	knockout.advance(Knockout.REASSEMBLE_SECONDS)
	_expect(knockout.phase == Knockout.Phase.ALIVE
			and is_zero_approx(knockout.amount)
			and is_zero_approx(float(mesh.get_instance_shader_parameter(
				&"gel_contact_compression"))),
		"reassembly restores the exact undeformed shader state")
	_expect(not face.knocked_out, "the knockout face clears on respawn")
	contact.trigger_contact(Vector3.LEFT, 2.0)
	contact.advance(0.05)
	_expect(float(mesh.get_instance_shader_parameter(&"gel_contact_compression")) > 0.05,
		"contact deformation resumes after reassembly")

	player.free()
	if _failures == 0:
		print("PASS: gel knockout melts, holds, replicates and reassembles with bounded drops")
	quit(_failures)


func _check_replication(player: Player) -> void:
	var sync := player.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var path := NodePath("GelEffects:knocked_out")
	_expect(sync.replication_config.has_property(path)
			and sync.replication_config.property_get_spawn(path)
			and sync.replication_config.property_get_replication_mode(path)
				== SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE,
		"knockout reaches peers and late joiners through the existing synchronizer")


func _check_shader_contract() -> void:
	for path: String in [
		"res://shaders/gel/gel_body.gdshader",
		"res://shaders/gel/gel_body_opaque.gdshader",
	]:
		var source: String = FileAccess.get_file_as_string(path)
		_expect(source.count("instance uniform ") == 16,
			"%s keeps the per-instance uniform budget" % path)
		_expect(source.contains("clamp(-gel_contact_compression, 0.0, 1.0)")
				and source.contains("puddle_spread")
				and source.contains("puddle_height"),
			"%s contains the reversible shader puddle deformation" % path)


func _check_drops(knockout: Node, mesh: MeshInstance3D) -> void:
	var melt: GPUParticles3D = knockout.melt_drops()
	var rebuild: GPUParticles3D = knockout.reassemble_drops()
	_expect(melt.one_shot and rebuild.one_shot
			and melt.amount == Knockout.MELT_DROP_COUNT
			and rebuild.amount == Knockout.REASSEMBLE_DROP_COUNT,
		"melt and reassembly use fixed one-shot particle budgets")
	_expect(melt.amount + rebuild.amount <= 32,
		"one complete knockout never allocates an unbounded cloud")
	_expect(melt.draw_pass_1 is SphereMesh and rebuild.draw_pass_1 is SphereMesh,
		"both transitions use small gel droplets")
	var gel_color: Variant = mesh.get_instance_shader_parameter(&"gel_color")
	var particle_color: Color = (melt.process_material as ParticleProcessMaterial).color
	_expect(gel_color is Color and particle_color.is_equal_approx(gel_color as Color),
		"the knockout drops inherit this player's gel colour")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

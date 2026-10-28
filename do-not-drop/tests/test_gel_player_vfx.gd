extends SceneTree
## S-311.95: landing particles, running trail and fading surface marks inherit
## the player's gel colour and remain inside fixed particle/mark budgets.

const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const VFX = preload("res://scripts/gameplay/player/gel/gel_player_vfx.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	await process_frame
	var effects := player.get_node(^"GelEffects") as PlayerGelEffects
	var vfx: Node = effects.get_node(^"GelVFX")
	var body: Node3D = player.get(&"_body_visual") as Node3D
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(body)
	_expect(vfx != null and mesh != null, "the real player owns one gel VFX budget")
	var gel_color := Color("e76fae")
	mesh.set_instance_shader_parameter(&"gel_color", gel_color)
	vfx.sync_color()
	_check_particles(vfx, gel_color)
	_check_marks(vfx, gel_color)

	player.free()
	await process_frame
	_expect(get_nodes_in_group(&"gel_vfx_mark").is_empty(),
		"freeing the player also frees every world-space gel mark")
	if _failures == 0:
		print("PASS: gel landing, trail and fading marks share skin colour and fixed budgets")
	quit(_failures)


func _check_particles(vfx: Node, gel_color: Color) -> void:
	var particles: Array[GPUParticles3D] = vfx.all_particles()
	_expect(particles.size() == 4 and vfx.particle_budget() == 45,
		"four particle systems own one fixed 45-particle budget")
	_expect(vfx.landing_drops().amount == VFX.LANDING_DROP_COUNT
			and vfx.landing_splash().amount == VFX.SPLASH_COUNT
			and vfx.landing_bubbles().amount == VFX.BUBBLE_COUNT
			and vfx.running_trail().amount == VFX.TRAIL_COUNT,
		"drops, splash, bubbles and trail keep their authored caps")
	vfx.trigger_landing(VFX.LANDING_MIN_SPEED + 1.0, Vector3.ZERO)
	_expect(vfx.landing_drops().emitting and vfx.landing_splash().emitting
			and vfx.landing_bubbles().emitting,
		"one landing starts droplets, a low splash and rising bubbles")
	for emitter: GPUParticles3D in particles:
		var motion := emitter.process_material as ParticleProcessMaterial
		_expect(motion.color.is_equal_approx(gel_color),
			"%s inherits the current skin colour" % emitter.name)
	vfx.set_trail_active(true)
	_expect(vfx.running_trail().emitting and not vfx.running_trail().local_coords
			and vfx.running_trail().lifetime <= 0.4,
		"the running trail is short and leaves particles in world space")
	vfx.set_trail_active(false)
	_expect(not vfx.running_trail().emitting, "the trail stops immediately below running speed")


func _check_marks(vfx: Node, gel_color: Color) -> void:
	for index: int in 80:
		var normal := Vector3.UP if index % 2 == 0 else Vector3.RIGHT
		vfx.spawn_mark(Vector3(float(index) * 0.01, 0.0, 0.0), normal)
		_expect(vfx.mark_count() <= VFX.MAX_MARKS,
			"surface marks never exceed the fixed pool while spawning")
	_expect(vfx.mark_count() == VFX.MAX_MARKS
			and get_nodes_in_group(&"gel_vfx_mark").size() == VFX.MAX_MARKS,
		"floor and wall marks remain physically bounded in the scene tree")
	_expect(vfx.mark_normal(VFX.MAX_MARKS - 2).is_equal_approx(Vector3.UP)
			and vfx.mark_normal(VFX.MAX_MARKS - 1).is_equal_approx(Vector3.RIGHT),
		"the same mark system aligns to floors and walls")
	var mark_color: Color = vfx.mark_color(0)
	_expect(Color(mark_color, 1.0).is_equal_approx(Color(gel_color, 1.0)),
		"surface marks inherit the skin RGB")
	var initial_alpha: float = vfx.mark_alpha(0)
	vfx.advance_marks(VFX.MARK_LIFETIME * 0.5)
	_expect(vfx.mark_alpha(0) < initial_alpha and vfx.mark_alpha(0) > 0.0,
		"marks fade continuously during their bounded lifetime")
	vfx.advance_marks(VFX.MARK_LIFETIME * 0.51)
	_expect(vfx.mark_count() == 0 and get_nodes_in_group(&"gel_vfx_mark").is_empty(),
		"expired marks release every node instead of accumulating")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

class_name PackageBoxMotion
extends RefCounted
## How the box moves on its own mesh: the settle bounce, the jitter of agitation and hits, the dents, the label
## that tears off and the confetti. Split out of package_feedback.gd (N-225.5) like package_rescue.gd is of
## package.gd: the state stays on the PackageFeedback, which keeps the handlers of the signals that set it
## off and the order of _process. Presentation only: never touches the RigidBody3D's real transform.

const WOBBLE_AMPLITUDE: float = 0.028
## A one-shot decaying jitter on any hit (item #23), on top of Ruidoso's own
## continuous agitation wobble -- both read from the same _wobble_nodes.
const IMPACT_SHAKE_DECAY: float = 5.0
## Settle bounce when placed (item #22): a quick squash that overshoots
## back to normal instead of just appearing locked in place.
const BOUNCE_DURATION: float = 0.4
const BOUNCE_AMPLITUDE: float = -0.16
const BOUNCE_DECAY: float = 9.0
const BOUNCE_FREQUENCY: float = 16.0


static func update_box_scale(f: PackageFeedback) -> void:
	f._box.scale = Vector3.ONE * f._growth_scale * bounce_scale_factor(f)


## Item #22: a quick damped squash-and-settle, roughly a classic spring
## curve, instead of a hard scale snap. Only touches Box's scale (position
## and the other nodes are untouched), so it composes cleanly with growth's
## own scale via update_box_scale().
static func apply_bounce(f: PackageFeedback, delta: float) -> void:
	if f._bounce_time < 0.0:
		return
	f._bounce_time += delta
	if f._bounce_time >= BOUNCE_DURATION:
		f._bounce_time = -1.0
	update_box_scale(f)


static func bounce_scale_factor(f: PackageFeedback) -> float:
	if f._bounce_time < 0.0:
		return 1.0
	return 1.0 + BOUNCE_AMPLITUDE * exp(-BOUNCE_DECAY * f._bounce_time) * cos(BOUNCE_FREQUENCY * f._bounce_time)


## Combines Ruidoso's continuous agitation wobble with the universal,
## decaying impact shake (item #23) -- both move the same nodes, additively,
## so a Ruidoso box that also just got hit shudders harder for a moment
## rather than one effect silently overwriting the other. Position-only and
## purely local (never touches the RigidBody3D's real transform), so it
## can't desync physics or networking -- every client computes this
## independently from the same already-replicated integrity/damage events.
static func apply_jitter(f: PackageFeedback, delta: float) -> void:
	f._impact_shake_strength = maxf(0.0, f._impact_shake_strength - IMPACT_SHAKE_DECAY * delta)
	var wobble_amount: float = f._distress if f._trap_id == &"noisy" else 0.0
	var total: float = clampf(wobble_amount + f._impact_shake_strength, 0.0, 1.5)
	if total <= 0.0:
		for entry: Dictionary in f._wobble_nodes.values():
			(entry["node"] as Node3D).position = entry["base_position"]
		return
	f._wobble_seed += delta * 14.0
	for entry: Dictionary in f._wobble_nodes.values():
		var node: Node3D = entry["node"]
		var base: Vector3 = entry["base_position"]
		var jitter := Vector3(
			sin(f._wobble_seed * 1.7 + base.x * 10.0),
			sin(f._wobble_seed * 2.3 + base.y * 10.0),
			sin(f._wobble_seed * 1.3 + base.z * 10.0),
		) * WOBBLE_AMPLITUDE * total
		node.position = base + jitter


static func apply_damage_deformation(f: PackageFeedback) -> void:
	for index: int in f._dent_pieces.size():
		var threshold: float = float(index) * 0.28
		var amount: float = clampf((f._impact_damage_visual - threshold) / 0.45, 0.0, 1.0)
		f._dent_pieces[index].scale = Vector3.ONE * amount


static func detach_shipping_label(f: PackageFeedback) -> void:
	if f._label_detached or f._shipping_label == null:
		return
	var package: Node3D = f.get_parent() as Node3D
	var world: Node = package.get_parent()
	if world == null:
		return
	var drop_transform: Transform3D = f._shipping_label.global_transform
	f._shipping_label.reparent(world)
	# Drop the Box's pulse/growth scale: a loose physics body must be unscaled.
	f._shipping_label.global_transform = drop_transform.orthonormalized()
	f._shipping_label.reset_physics_interpolation()
	f._shipping_label.freeze = false
	f._shipping_label.collision_layer = 4
	f._shipping_label.collision_mask = DeliveryPackage.LOOSE_MASK
	f._shipping_label.linear_velocity = (package as RigidBody3D).linear_velocity + Vector3(0.0, 1.2, 0.4)
	f._label_detached = true


## A handful of tiny colored cubes flung outward and pulled down by gravity --
## no particle texture/material asset needed, matches the placeholder-box style
## everything else in the prototype already uses.
static func burst_confetti(f: PackageFeedback, slow_ruin: bool = false) -> GPUParticles3D:
	var origin: Vector3 = (f.get_parent() as Node3D).global_position
	var particles := GPUParticles3D.new()
	particles.name = "RuinConfetti" if slow_ruin else "ConfettiBurst"
	particles.top_level = true
	particles.emitting = false
	particles.one_shot = true
	particles.amount = PackageFeedback.CONFETTI_COUNT
	particles.lifetime = PackageFeedback.CONFETTI_LIFETIME
	particles.explosiveness = 1.0
	particles.draw_pass_1 = BoxMesh.new()
	(particles.draw_pass_1 as BoxMesh).size = Vector3.ONE * 0.09

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 180.0
	process_material.initial_velocity_min = 1.8
	process_material.initial_velocity_max = 4.2
	process_material.gravity = Vector3(0.0, -9.0, 0.0)
	process_material.color = PackageFeedback.CONFETTI_COLORS[randi() % PackageFeedback.CONFETTI_COLORS.size()]
	particles.process_material = process_material
	particles.speed_scale = PackageFeedback.RUIN_PARTICLE_SPEED if slow_ruin else 1.0

	# current_scene is null in headless test trees that never loaded a scene --
	# falls back to the tree root so this still works there, not just in-game.
	var tree: SceneTree = f.get_tree()
	var container: Node = tree.current_scene if tree.current_scene != null else tree.root
	container.add_child(particles)
	particles.global_position = origin
	particles.reset_physics_interpolation()
	particles.emitting = true
	if slow_ruin:
		tree.create_timer(PackageFeedback.RUIN_HOLD_SECONDS).timeout.connect(func() -> void:
			if is_instance_valid(particles):
				particles.speed_scale = 1.0)
	particles.finished.connect(particles.queue_free)
	return particles

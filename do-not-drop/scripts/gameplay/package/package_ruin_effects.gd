extends RefCounted
## One distinct "it broke" moment per trap (S-310), so the ruin of each kind of
## box is a clip worth sharing and tells the player WHICH trap lost the cargo:
##   fragile        -> porcelain shards        (RuinShards)
##   liquid         -> splash + spreading puddle (RuinLiquid: RuinSplash, RuinPuddle)
##   explosive      -> confetti + colored smoke  (RuinBlast: RuinBlastConfetti, RuinSmoke)
##   noisy, hostile -> the animal bolts out of the box and runs off (RuinCritter)
##   balance        -> the tower collapses into loose crates (RuinTower)
##   growing_weight -> a heavy thud: dust ring on the floor (RuinDust)
##
## Presentation only: every peer builds its own copy from the relayed
## package_ruined signal (see package_feedback.gd), nothing is replicated and no
## simulation state or Engine.time_scale is touched. All meshes are primitives
## with unshadowed StandardMaterial3D (GL Compatibility, no textures, no lights).
##
## Budget: every effect stays under ~40 particles (WorldQuality scales the
## GPUParticles3D amounts down on lower presets) and frees itself. Duration is
## measured in EFFECT time; when `slow` is on (GameSettings.impact_effects) the
## first HOLD_SECONDS of real time run at HOLD_SPEED, the local freeze-frame of
## S-111, which adds HOLD_SECONDS * (1 - HOLD_SPEED) ~= 0.3 s of real time:
##   regular effects  <= 1.6 s effect time -> <= 1.9 s real
##   the critter      == 3.0 s effect time -> <= 3.3 s real (explicit exception: it must run for 3 s)
## The safety timers below are set just above those real-time totals.

const HOLD_SECONDS: float = 0.35
const HOLD_SPEED: float = 0.15
const FREE_MARGIN_REGULAR: float = 1.95
const FREE_MARGIN_CRITTER: float = 3.45
const CRITTER_SECONDS: float = 3.0
const LIQUID_SECONDS: float = 1.6
const TOWER_SECONDS: float = 1.5
const DUST_SECONDS: float = 1.2
## The crate is 0.65 m: its floor contact is this far below its center.
const GROUND_DROP: float = 0.325
const GRAVITY: float = 12.0

const PAPER: Color = Color("fff6e6")
const CARDBOARD: Color = Color("e0a867")
const INK: Color = Color("1e2235")
const SKY: Color = Color("4cc9f0")
const MARKING: Color = Color("d4d9c2")
const CONFETTI_COLORS: Array[Color] = [Color("f47e6d"), Color("f4c562"), Color("83e2ba"), Color("6db3d6")]

const TRAP_IDS: Array[StringName] = [
	&"fragile", &"liquid", &"explosive", &"noisy", &"hostile", &"balance", &"growing_weight"]


static func has_effect(trap_id: StringName) -> bool:
	return trap_id in TRAP_IDS


## Builds the effect for `trap_id` at the global position of `package` and returns its root, or
## null when the trap has no effect of its own (the caller keeps the generic
## confetti). The root is a top_level child of the current scene (or of the tree
## root in headless tests that never loaded one) and queue_frees itself.
static func spawn(trap_id: StringName, package: Node3D, slow: bool) -> Node3D:
	if package == null or not package.is_inside_tree() or not has_effect(trap_id):
		return null
	var tree: SceneTree = package.get_tree()
	var origin: Vector3 = package.global_position
	var container: Node = tree.current_scene if tree.current_scene != null else tree.root
	var root: Node3D = null
	match trap_id:
		&"fragile":
			root = _build_shards()
		&"liquid":
			root = Node3D.new()
			root.name = "RuinLiquid"
		&"explosive":
			root = Node3D.new()
			root.name = "RuinBlast"
		&"noisy", &"hostile":
			root = Node3D.new()
			root.name = "RuinCritter"
		&"balance":
			root = Node3D.new()
			root.name = "RuinTower"
		_:
			root = Node3D.new()
			root.name = "RuinDust"
	root.top_level = true
	container.add_child(root)
	# Global position only sticks once the node is inside the tree.
	root.global_position = origin
	root.reset_physics_interpolation()
	var tween: Tween = null
	var free_after: float = FREE_MARGIN_REGULAR
	match trap_id:
		&"fragile":
			(root as GPUParticles3D).finished.connect(root.queue_free)
			(root as GPUParticles3D).emitting = true
		&"liquid":
			tween = _play_liquid(root, LIQUID_SECONDS)
		&"explosive":
			_play_blast(root)
			tween = _timeline(root, 1.4, Callable())
		&"balance":
			tween = _play_tower(root, TOWER_SECONDS)
		&"growing_weight":
			tween = _play_dust(root, DUST_SECONDS)
		_:
			tween = _play_critter(root, CRITTER_SECONDS, trap_id == &"hostile")
			free_after = FREE_MARGIN_CRITTER
	_hold(root, slow, tween)
	_free_after(root, free_after)
	return root


# ---- shared plumbing -------------------------------------------------------


## Drives `update(effect_seconds)` over `seconds` and frees the root at the end.
## A Tween (not _process) so the freeze-frame is just its speed scale.
static func _timeline(root: Node3D, seconds: float, update: Callable) -> Tween:
	var tween: Tween = root.create_tween()
	if update.is_valid():
		tween.tween_method(update, 0.0, seconds, seconds)
	else:
		tween.tween_interval(seconds)
	tween.tween_callback(root.queue_free)
	return tween


## The local freeze-frame: particles and the tween crawl for HOLD_SECONDS, then
## return to full speed. Only when impact effects are on.
static func _hold(root: Node3D, slow: bool, tween: Tween) -> void:
	if not slow:
		return
	for particles: GPUParticles3D in _all_particles(root):
		particles.speed_scale = HOLD_SPEED
	if tween != null:
		tween.set_speed_scale(HOLD_SPEED)
	# Captures the id, not the node: a lambda holding a freed Object logs
	# "Lambda capture ... was freed" when the timer fires after the effect ended.
	var root_id: int = root.get_instance_id()
	root.get_tree().create_timer(HOLD_SECONDS).timeout.connect(func() -> void:
		var alive: Node3D = instance_from_id(root_id) as Node3D
		if alive == null:
			return
		for particles: GPUParticles3D in _all_particles(alive):
			particles.speed_scale = 1.0
		if tween != null and tween.is_valid():
			tween.set_speed_scale(1.0))


static func _all_particles(root: Node) -> Array[GPUParticles3D]:
	var found: Array[GPUParticles3D] = []
	if root is GPUParticles3D:
		found.append(root as GPUParticles3D)
	for node: Node in root.find_children("*", "GPUParticles3D", true, false):
		found.append(node as GPUParticles3D)
	return found


## Belt and braces: whatever happens to the tween or the `finished` signal, the
## effect never outlives its promised time.
static func _free_after(root: Node, seconds: float) -> void:
	var root_id: int = root.get_instance_id()  # see _hold(): never capture the node itself
	root.get_tree().create_timer(seconds).timeout.connect(func() -> void:
		var alive: Node = instance_from_id(root_id) as Node
		if alive != null:
			alive.queue_free())


static func _material(color: Color, vertex_color: bool = false, translucent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	material.vertex_color_use_as_albedo = vertex_color
	if translucent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


static func _add_mesh(parent: Node3D, node_name: String, mesh: Mesh, material: Material,
		position: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = position
	parent.add_child(instance)
	return instance


## A random-per-particle palette (constant steps, no blending between colors).
static func _palette(colors: Array[Color]) -> GradientTexture1D:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	for index: int in colors.size():
		offsets.append(float(index) / float(colors.size()))
	gradient.offsets = offsets
	gradient.colors = PackedColorArray(colors)
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## Full size for most of the life, then shrinks to nothing (or grows first).
static func _size_curve(start: float, peak: float, end: float) -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, start))
	curve.add_point(Vector2(0.35, peak))
	curve.add_point(Vector2(1.0, end))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


## Opaque until `fade_from`, then transparent by the end of the life.
static func _fade_ramp(fade_from: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, fade_from, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


static func _particles(node_name: String, amount: int, lifetime: float, mesh: Mesh,
		process_material: ParticleProcessMaterial) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.emitting = false
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = lifetime
	particles.explosiveness = 1.0
	particles.draw_pass_1 = mesh
	particles.process_material = process_material
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


# ---- fragile: porcelain shards ---------------------------------------------


## Flat cream/white slivers that spin out and fall away. GPU particle collision
## does not exist on GL Compatibility, so they shrink out as they drop instead
## of bouncing on the floor.
static func _build_shards() -> GPUParticles3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.11, 0.012, 0.075)
	mesh.material = _material(Color.WHITE, true)
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 75.0
	process_material.initial_velocity_min = 2.2
	process_material.initial_velocity_max = 5.0
	process_material.gravity = Vector3(0.0, -13.0, 0.0)
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.2
	process_material.angle_min = 0.0
	process_material.angle_max = 360.0
	process_material.angular_velocity_min = -720.0
	process_material.angular_velocity_max = 720.0
	process_material.scale_min = 0.6
	process_material.scale_max = 1.3
	process_material.scale_curve = _size_curve(1.0, 1.0, 0.0)
	process_material.color_initial_ramp = _palette([PAPER, Color("f2e3c4"), Color.WHITE, Color("e6ebee")])
	var shards := _particles("RuinShards", 26, 0.95, mesh, process_material)
	return shards


# ---- liquid: splash + puddle -----------------------------------------------


static func _play_liquid(root: Node3D, seconds: float) -> Tween:
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _material(Color.WHITE, true)
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 60.0
	process_material.initial_velocity_min = 2.0
	process_material.initial_velocity_max = 4.5
	process_material.gravity = Vector3(0.0, -12.0, 0.0)
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.2
	process_material.scale_min = 0.7
	process_material.scale_max = 1.5
	process_material.scale_curve = _size_curve(1.0, 1.0, 0.0)
	process_material.color_initial_ramp = _palette([SKY, Color("7fd9f5"), Color("2fa8d6")])
	var splash := _particles("RuinSplash", 18, 0.8, mesh, process_material)
	root.add_child(splash)
	splash.emitting = true

	# A flat disc on the floor: grows fast, lingers, then fades.
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.01
	disc.radial_segments = 24
	disc.rings = 1
	var puddle_material := _material(Color(SKY.r, SKY.g, SKY.b, 0.75), false, true)
	var puddle := _add_mesh(root, "RuinPuddle", disc, puddle_material, Vector3(0.0, 0.01 - GROUND_DROP, 0.0))
	puddle.scale = Vector3(0.1, 1.0, 0.1)
	var grow_seconds: float = 0.5
	var fade_from: float = 1.0
	var update := func(t: float) -> void:
		var grown: float = 1.0 - pow(1.0 - clampf(t / grow_seconds, 0.0, 1.0), 3.0)
		var radius: float = lerpf(0.1, 1.0, grown)
		puddle.scale = Vector3(radius, 1.0, radius)
		var alpha: float = 0.75 * (1.0 - clampf((t - fade_from) / (seconds - fade_from), 0.0, 1.0))
		puddle_material.albedo_color.a = alpha
	return _timeline(root, seconds, update)


# ---- explosive: confetti + colored smoke -------------------------------------


static func _play_blast(root: Node3D) -> void:
	var confetti_mesh := BoxMesh.new()
	confetti_mesh.size = Vector3.ONE * 0.09
	confetti_mesh.material = _material(Color.WHITE, true)
	var confetti_material := ParticleProcessMaterial.new()
	confetti_material.direction = Vector3.UP
	confetti_material.spread = 180.0
	confetti_material.initial_velocity_min = 3.0
	confetti_material.initial_velocity_max = 6.5
	confetti_material.gravity = Vector3(0.0, -10.0, 0.0)
	confetti_material.angular_velocity_min = -360.0
	confetti_material.angular_velocity_max = 360.0
	confetti_material.scale_curve = _size_curve(1.0, 1.0, 0.0)
	confetti_material.color_initial_ramp = _palette(CONFETTI_COLORS)
	root.add_child(_particles("RuinBlastConfetti", 20, 1.1, confetti_mesh, confetti_material))

	# Cartoon smoke: a few big translucent puffs, no fire.
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 0.3
	smoke_mesh.height = 0.6
	smoke_mesh.radial_segments = 8
	smoke_mesh.rings = 4
	smoke_mesh.material = _material(Color.WHITE, true, true)
	var smoke_material := ParticleProcessMaterial.new()
	smoke_material.direction = Vector3.UP
	smoke_material.spread = 180.0
	smoke_material.initial_velocity_min = 0.8
	smoke_material.initial_velocity_max = 2.2
	smoke_material.gravity = Vector3(0.0, 1.0, 0.0)
	smoke_material.damping_min = 1.5
	smoke_material.damping_max = 2.5
	smoke_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke_material.emission_sphere_radius = 0.15
	smoke_material.scale_curve = _size_curve(0.4, 1.3, 1.7)
	smoke_material.color_initial_ramp = _palette(CONFETTI_COLORS)
	smoke_material.color_ramp = _fade_ramp(0.3)
	root.add_child(_particles("RuinSmoke", 8, 1.2, smoke_mesh, smoke_material))
	for particles: GPUParticles3D in _all_particles(root):
		particles.emitting = true


# ---- noisy / hostile: the animal bolts ---------------------------------------


## Low-poly critter built from primitives, its nose toward -Z.
static func _build_critter(body_color: Color, eye_color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "CritterPivot"
	var fur := _material(body_color)
	var body := CapsuleMesh.new()
	body.radius = 0.1
	body.height = 0.32
	var body_node := _add_mesh(pivot, "Body", body, fur)
	body_node.rotation.x = PI / 2.0
	var head := SphereMesh.new()
	head.radius = 0.09
	head.height = 0.18
	_add_mesh(pivot, "Head", head, fur, Vector3(0.0, 0.06, -0.17))
	var ear := CapsuleMesh.new()
	ear.radius = 0.03
	ear.height = 0.13
	for side: float in [-1.0, 1.0]:
		var ear_node := _add_mesh(pivot, "Ear", ear, fur, Vector3(0.055 * side, 0.17, -0.16))
		ear_node.rotation.z = -0.25 * side
	var eye := SphereMesh.new()
	eye.radius = 0.018
	eye.height = 0.036
	eye.radial_segments = 6
	eye.rings = 3
	var eye_material := _material(eye_color)
	for side: float in [-1.0, 1.0]:
		_add_mesh(pivot, "Eye", eye, eye_material, Vector3(0.042 * side, 0.09, -0.245))
	var tail := SphereMesh.new()
	tail.radius = 0.04
	tail.height = 0.08
	_add_mesh(pivot, "Tail", tail, _material(PAPER), Vector3(0.0, 0.03, 0.2))
	return pivot


## Hops away in a random direction with a little sideways wiggle: pure
## kinematics of the time `t` (no RigidBody), so the freeze-frame and the
## cleanup come for free. It pops out of the box in one big arc, hops along the
## floor and shrinks away over the last 0.4 s.
static func _play_critter(root: Node3D, seconds: float, hostile: bool) -> Tween:
	var pivot: Node3D = _build_critter(Color("5b3a78") if hostile else Color("f4c562"),
		Color("ff5e5b") if hostile else INK)
	root.add_child(pivot)
	var angle: float = randf() * TAU
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	var side := Vector3(-direction.z, 0.0, direction.x)
	var speed: float = 2.8 if hostile else 2.0
	var hop_height: float = 0.1 if hostile else 0.16
	var hop_period: float = 0.26 if hostile else 0.34
	var phase: float = randf() * TAU
	var rest_y: float = 0.1 - GROUND_DROP
	var jump_seconds: float = 0.4
	var update := func(t: float) -> void:
		var lift: float
		var pitch: float
		if t < jump_seconds:
			var u: float = t / jump_seconds
			lift = lerpf(0.0, rest_y, u) + 0.4 * 4.0 * u * (1.0 - u)
			pitch = 0.5 * (1.0 - 2.0 * u)
		else:
			var p: float = fmod(t - jump_seconds, hop_period) / hop_period
			lift = rest_y + hop_height * 4.0 * p * (1.0 - p)
			pitch = 0.35 * (1.0 - 2.0 * p)
		var wiggle: float = sin(t * 3.1 + phase) * 0.35
		pivot.position = direction * speed * t + side * wiggle + Vector3(0.0, lift, 0.0)
		var heading: Vector3 = direction * speed + side * cos(t * 3.1 + phase) * 0.35 * 3.1
		pivot.rotation = Vector3(pitch, atan2(-heading.x, -heading.z), 0.0)
		var pop: float = lerpf(0.3, 1.0, clampf(t / 0.12, 0.0, 1.0))
		var vanish: float = clampf((seconds - t) / 0.4, 0.0, 1.0)
		pivot.scale = Vector3.ONE * minf(pop, vanish)
	update.call(0.0)
	return _timeline(root, seconds, update)


# ---- balance: the tower collapses ---------------------------------------------


static func _play_tower(root: Node3D, seconds: float) -> Tween:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.26, 0.18, 0.26)
	var tones: Array[Color] = [CARDBOARD, Color("c78f50"), Color("ecc48f")]
	var ground_y: float = 0.09 - GROUND_DROP
	var pieces: Array[Dictionary] = []
	for index: int in 5:
		var node := _add_mesh(root, "TowerCrate", mesh, _material(tones[index % tones.size()]))
		var start := Vector3(randf_range(-0.03, 0.03), 0.33 + 0.09 + 0.18 * index, randf_range(-0.03, 0.03))
		var vy: float = randf_range(0.0, 1.5)
		var fall_seconds: float = (vy + sqrt(vy * vy + 2.0 * GRAVITY * (start.y - ground_y))) / GRAVITY
		var heading: float = randf() * TAU
		pieces.append({
			"node": node,
			"start": start,
			"velocity": Vector3(cos(heading), 0.0, sin(heading)) * randf_range(2.4, 3.6),
			"vy": vy,
			"delay": 0.03 * index,
			"fall": fall_seconds,
			"bounce": 0.28 * (GRAVITY * fall_seconds - vy),
			"tilt": Vector3(randf_range(-0.35, 0.35), randf_range(-PI, PI), randf_range(-0.35, 0.35)),
		})
	var update := func(t: float) -> void:
		var vanish: float = clampf((seconds - t) / 0.35, 0.0, 1.0)
		for piece: Dictionary in pieces:
			var node: MeshInstance3D = piece["node"]
			var elapsed: float = maxf(t - float(piece["delay"]), 0.0)
			var start: Vector3 = piece["start"]
			# Horizontal drag: closed form, so it slides to a stop.
			var slide: Vector3 = (piece["velocity"] as Vector3) * ((1.0 - exp(-3.0 * elapsed)) / 3.0)
			var height: float
			var fall_seconds: float = piece["fall"]
			if elapsed < fall_seconds:
				height = start.y + float(piece["vy"]) * elapsed - 0.5 * GRAVITY * elapsed * elapsed
			else:
				var since: float = elapsed - fall_seconds
				height = ground_y + maxf(float(piece["bounce"]) * since - 0.5 * GRAVITY * since * since, 0.0)
			node.position = Vector3(start.x + slide.x, height, start.z + slide.z)
			node.rotation = (piece["tilt"] as Vector3) * (1.0 - exp(-4.0 * elapsed))
			node.scale = Vector3.ONE * vanish
	update.call(0.0)
	return _timeline(root, seconds, update)


# ---- growing weight: heavy thud ---------------------------------------------


## The box "slams down": a dust ring races out along the floor. The box's own
## squash is the settle bounce in package_feedback.gd (Box scale only).
static func _play_dust(root: Node3D, seconds: float) -> Tween:
	var floor_y: float = 0.02 - GROUND_DROP
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.rings = 16
	torus.ring_segments = 6
	var ring_material := _material(Color(MARKING.r, MARKING.g, MARKING.b, 0.8), false, true)
	var ring := _add_mesh(root, "RuinDustRing", torus, ring_material, Vector3(0.0, floor_y, 0.0))

	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.12
	puff_mesh.height = 0.24
	puff_mesh.radial_segments = 8
	puff_mesh.rings = 4
	puff_mesh.material = _material(Color.WHITE, true, true)
	var puff_material := ParticleProcessMaterial.new()
	puff_material.direction = Vector3.UP
	puff_material.spread = 15.0
	puff_material.initial_velocity_min = 0.3
	puff_material.initial_velocity_max = 0.7
	puff_material.gravity = Vector3.ZERO
	puff_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	puff_material.emission_ring_axis = Vector3.UP
	puff_material.emission_ring_height = 0.05
	puff_material.emission_ring_radius = 0.5
	puff_material.emission_ring_inner_radius = 0.3
	puff_material.radial_velocity_min = 1.2
	puff_material.radial_velocity_max = 2.2
	puff_material.scale_curve = _size_curve(0.6, 1.2, 1.7)
	puff_material.color_initial_ramp = _palette([MARKING, Color("e0c9a0"), Color("bfc4b0")])
	puff_material.color_ramp = _fade_ramp(0.25)
	var puffs := _particles("RuinDustPuffs", 10, 0.7, puff_mesh, puff_material)
	puffs.position = Vector3(0.0, floor_y + 0.03, 0.0)
	root.add_child(puffs)
	puffs.emitting = true

	var expand_seconds: float = 0.6
	var update := func(t: float) -> void:
		var u: float = clampf(t / expand_seconds, 0.0, 1.0)
		var radius: float = lerpf(0.5, 2.6, 1.0 - pow(1.0 - u, 3.0))
		ring.scale = Vector3(radius, 0.5, radius)
		ring_material.albedo_color.a = 0.8 * (1.0 - u)
	return _timeline(root, seconds, update)

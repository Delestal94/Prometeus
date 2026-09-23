extends Node
## A presentation-only child: changing color never changes simulation state.
##
## The confetti burst on ruin is deliberately loud (docs/requerimientos-tecnicos.md
## 3.4, "momentos clipeables") -- package_ruined is already relayed to every peer
## (see package.gd's _emit_event), so each client's own local burst fires in lockstep
## with everyone else's without this script needing to know or care about the network.

const CONFETTI_COLORS: Array[Color] = [Color("f47e6d"), Color("f4c562"), Color("83e2ba"), Color("6db3d6")]
const CONFETTI_COUNT: int = 28
const CONFETTI_LIFETIME: float = 1.1

## Nodes wobbled for the Ruidoso trap and on impacts: Box holds the whole
## cardboard model and what's inside it, so everything shudders together.
const WOBBLE_NODE_NAMES: Array[StringName] = [&"Box"]
const GROWING_WEIGHT_MAX_SCALE: float = 1.35
const GROWING_WEIGHT_SINK: float = 0.09
const WOBBLE_AMPLITUDE: float = 0.028
## Creaks retrigger more often the closer the box is to failing -- at full
## distress roughly one every 0.8s, calm but not fresh roughly one every 4s.
const CREAK_INTERVAL_MAX: float = 4.0
const CREAK_INTERVAL_MIN: float = 0.8
## A one-shot decaying jitter on any hit (item #23), on top of Ruidoso's own
## continuous agitation wobble -- both read from the same _wobble_nodes.
const IMPACT_SHAKE_DECAY: float = 5.0
const IMPACT_SHAKE_PER_DAMAGE: float = 0.05
## Settle bounce when placed (item #22): a quick squash that overshoots
## back to normal instead of just appearing locked in place.
const BOUNCE_DURATION: float = 0.4
const BOUNCE_AMPLITUDE: float = -0.16
const BOUNCE_DECAY: float = 9.0
const BOUNCE_FREQUENCY: float = 16.0
const INK: Color = Color("1e2235")
const LABEL_DROP_DAMAGE: float = 18.0
const LABEL_TEXTURE: Texture2D = preload("res://assets/textures/cargo/tx_cargo_shipping_label_512.png")
const LABEL_ASPECT: float = 320.0 / 512.0
## Fallback when a package has no PackageContent: the fragile box.
const DEFAULT_BOX_MODEL: String = "res://assets/models/cargo/sm_cargo_box_cube.glb"
## Printed cardboard is tinted, not repainted, by trap state: the print stays
## readable while the box still reads as "worried" or "wrecked" at a glance.
const STATE_TINT: Array[Color] = [Color(1, 1, 1), Color(1.0, 0.88, 0.76), Color(0.8, 0.64, 0.6)]

@export var box_node_path: NodePath = ^"../Box"

## One per package, shared by every surface of its box model: highlight
## (emission) and the state tint change it per instance.
var _material: StandardMaterial3D
## Soft rim shown while a player is aiming at this box (see highlight()).
## Built with the box model, which only exists a frame after spawning; a
## highlight asked for before that is remembered and applied then.
var _outline: Node3D
var _outline_wanted: bool = false
const OUTLINE_WIDTH: float = 0.012
const OUTLINE_COLOR := Color(1.0, 0.84, 0.48)
var _package_id: StringName
var _box: Node3D
var _state: int = 0
## Distress reported per-frame via package_integrity_changed (already
## relayed to every client for the HUD) -- 0 fresh, 1 about to fail. Reused
## here as a generic "how bad is it" scalar instead of adding new signals:
## every trap already funnels its own specific mechanic into this same
## shared integrity axis (docs/parametros-diseno.md), so it's free.
var _distress: float = 0.0
var _trap_id: StringName = &""
var _wobble_nodes: Dictionary = {}  ## name -> {"node": Node3D, "base_position": Vector3}
var _wobble_seed: float = 0.0
var _chime_player: AudioStreamPlayer3D
var _groan_player: AudioStreamPlayer3D
var _creak_player: AudioStreamPlayer3D
var _creak_countdown: float = 0.0
var _impact_shake_strength: float = 0.0
var _growth_scale: float = 1.0
var _bounce_time: float = -1.0  ## negative: no bounce in progress
var _shipping_label: RigidBody3D
var _label_detached: bool = false
var _dent_pieces: Array[MeshInstance3D] = []
var _impact_damage_visual: float = 0.0


func _ready() -> void:
	var parent: Node = get_parent()
	_package_id = parent.get("package_id")
	var definition: Resource = parent.get(&"trap_definition") as Resource
	_trap_id = StringName(definition.get(&"id")) if definition != null else &""
	# Distinct phase per package so several Ruidoso boxes riding together
	# don't all shudder in perfect unison.
	_wobble_seed = randf() * TAU
	_box = get_node(box_node_path) as Node3D
	_material = StandardMaterial3D.new()
	_material.roughness = 0.9
	call_deferred(&"_apply_identity", parent)
	# Populated for every trap type, not just Ruidoso -- item #23's impact
	# shake rides the same nodes regardless of what the package's trap is.
	for wobble_name: StringName in WOBBLE_NODE_NAMES:
		var node: Node3D = get_node_or_null(NodePath("../" + String(wobble_name))) as Node3D
		if node != null:
			_wobble_nodes[wobble_name] = {"node": node, "base_position": node.position}
	match _trap_id:
		&"noisy":
			_groan_player = _make_player(SynthAudio.creature_groan(), -60.0)
		&"fragile":
			_chime_player = _make_player(SynthAudio.glass_chime(), -8.0)
		&"growing_weight":
			_creak_player = _make_player(SynthAudio.wood_creak(), -10.0)
			_creak_countdown = CREAK_INTERVAL_MAX
	_set_state(0)
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("package_state_changed", _on_package_state_changed)
		bus.connect("package_ruined", _on_package_ruined)
		bus.connect("package_integrity_changed", _on_integrity_changed)
		bus.connect("package_damaged", _on_package_damaged)
		bus.connect("package_placed", _on_package_placed)


func _apply_identity(package: Node) -> void:
	var content: Resource = package.call(&"content_definition") if package.has_method(&"content_definition") else null
	var shape_size := Vector3(0.65, 0.65, 0.65)
	var box_scene: PackedScene = null
	var shipping_data: String = "Contenido sin declarar"
	if content != null:
		shape_size = content.get(&"box_size")
		box_scene = content.get(&"box_model")
		shipping_data = "%s\n%s · %s" % [content.get(&"display_name"), content.get(&"declared_weight"), content.get(&"handling")]
	if box_scene == null:
		box_scene = load(DEFAULT_BOX_MODEL)
	var model: Node3D = box_scene.instantiate()
	model.name = "Model"
	# Box GLBs sit on their base; the package's origin is its centre.
	model.position.y = -shape_size.y * 0.5
	_box.add_child(model)
	_adopt_box_material(model)
	var collider: CollisionShape3D = package.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if collider != null:
		var shape := BoxShape3D.new()
		shape.size = shape_size
		collider.shape = shape
	_add_shipping_label(package, shipping_data, shape_size)
	_add_dent_pieces(shape_size * 0.5)
	_build_outline(shape_size)


## An inverted hull: a plain box a hair larger than the box body, drawn
## only from the inside and opaque, so it shows as a thin warm rim around the
## silhouette and never over the printed faces. It's sized from the body
## mesh (the model is hollow -- it opens for unboxing -- so its own mesh
## can't be reused as the hull without its inner walls showing through).
func _build_outline(shape_size: Vector3) -> void:
	var body_bounds := AABB(Vector3(-shape_size.x, 0.0, -shape_size.z) * 0.5, shape_size)
	var body := _box.find_child("Body", true, false) as MeshInstance3D
	if body != null:
		body_bounds = _box.global_transform.affine_inverse() * body.global_transform * body.get_aabb()
	var hull := BoxMesh.new()
	hull.size = body_bounds.size + Vector3.ONE * OUTLINE_WIDTH * 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.albedo_color = OUTLINE_COLOR
	_outline = MeshInstance3D.new()
	_outline.name = "HighlightOutline"
	(_outline as MeshInstance3D).mesh = hull
	(_outline as MeshInstance3D).material_override = material
	(_outline as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline.position = body_bounds.get_center()
	_box.add_child(_outline)
	_apply_outline()


func _apply_outline() -> void:
	if _outline != null:
		_outline.visible = _outline_wanted


## Every surface of the box shares one imported material (the printed
## atlas); this swaps in a per-package copy so glowing or tinting one box
## never touches the others.
func _adopt_box_material(model: Node) -> void:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface: int in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if source != null and _material.albedo_texture == null:
				var copy := source.duplicate() as StandardMaterial3D
				copy.emission_enabled = _material.emission_enabled
				copy.emission = _material.emission
				copy.emission_energy_multiplier = _material.emission_energy_multiplier
				_material = copy
			mesh_instance.set_surface_override_material(surface, _material)
	_set_state(_state)


func _add_dent_pieces(half: Vector3) -> void:
	var dents := Node3D.new()
	dents.name = "DamageDents"
	_box.add_child(dents)
	var spots: Array = [
		[Vector3(-half.x * 0.55, half.y * 0.45, half.z + 0.004), 0.0],
		[Vector3(half.x * 0.5, -half.y * 0.4, half.z + 0.004), 0.0],
		[Vector3(half.x + 0.004, half.y * 0.3, -half.z * 0.4), PI * 0.5],
	]
	for spot: Array in spots:
		var dent := _box_piece(Vector3(0.14, 0.1, 0.012), Color("6e4a2a"))
		dent.position = spot[0]
		dent.rotation = Vector3(0.0, spot[1], 0.45)
		dent.scale = Vector3.ZERO
		dents.add_child(dent)
		_dent_pieces.append(dent)


## The courier's label, stuck on the back of the box: printed paper plus the
## declared contents written on it. Same detachable rigid body as before --
## a hard enough hit tears it off.
func _add_shipping_label(package: Node, shipping_data: String, box_size: Vector3) -> void:
	var width: float = minf(0.4, box_size.x * 0.78)
	var height: float = width * LABEL_ASPECT
	_shipping_label = RigidBody3D.new()
	_shipping_label.name = "ShippingLabel"
	_shipping_label.freeze = true
	# While attached this is paper painted on the box, not a second solid
	# object for the carrier to collide with. Collision is enabled only once
	# a hard impact tears it free.
	_shipping_label.collision_layer = 0
	_shipping_label.collision_mask = 0
	# A few millimetres proud of the face: closer than this and depth
	# precision at a few metres makes box and paper fight (flicker).
	_shipping_label.position = Vector3(0.0, -box_size.y * 0.5 + minf(box_size.y * 0.42, height * 0.5 + 0.06), -box_size.z * 0.5 - 0.006)
	_shipping_label.rotation.y = PI
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, 0.01)
	collision.shape = shape
	_shipping_label.add_child(collision)
	var paper := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	paper.mesh = quad
	paper.material_override = _label_material()
	_shipping_label.add_child(paper)
	var text := Label3D.new()
	text.text = shipping_data
	text.font_size = 32
	text.pixel_size = width / 512.0 * 0.62
	text.outline_size = 0
	text.modulate = INK
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.width = 480.0
	# Under "CONTENIDO DECLARADO", on the left of the printed label.
	text.position = Vector3(-width * 0.04, -height * 0.11, 0.004)
	_shipping_label.add_child(text)
	# On the Box, not the package root: the box wobbles, bounces and grows
	# (traps, impacts, placing it down), and a label left behind had the box
	# face sweeping back and forth through it -- the label kept vanishing.
	_box.add_child(_shipping_label)


static var _label_material_cache: StandardMaterial3D


func _label_material() -> StandardMaterial3D:
	if _label_material_cache == null:
		_label_material_cache = StandardMaterial3D.new()
		_label_material_cache.albedo_texture = LABEL_TEXTURE
		_label_material_cache.roughness = 0.8
		_label_material_cache.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _label_material_cache


func _box_piece(size: Vector3, color: Color) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	piece.mesh = mesh
	piece.material_override = _flat_material(color)
	return piece


## Shared across every package instance, keyed by color: these decorative
## pieces (the dents) are never
## mutated after creation, unlike _box's own _material (highlight/state
## color do change that one per-instance) -- so unlike that one, these are
## safe to reuse instead of allocating a fresh StandardMaterial3D per box.
static var _flat_material_cache: Dictionary = {}


func _flat_material(color: Color) -> StandardMaterial3D:
	if not _flat_material_cache.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		_flat_material_cache[color] = material
	return _flat_material_cache[color]


func _make_player(stream: AudioStreamWAV, volume_db: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.unit_size = 6.0
	player.max_distance = 20.0
	add_child(player)
	return player


func _on_package_state_changed(id: StringName, new_state: int) -> void:
	if id != _package_id:
		return
	_set_state(new_state)
	# Frágil's audible cue (docs/especificaciones-visuales.md #43): a bright
	# chime on the way into AT_RISK, the same clip pitched down a fourth for
	# RUINED so the two severities are easy to tell apart by ear alone.
	if _trap_id == &"fragile" and new_state != 0:
		_chime_player.pitch_scale = 1.0 if new_state == 1 else 0.75
		_chime_player.play()


func _on_package_ruined(id: StringName, _cause: String) -> void:
	if id == _package_id:
		_burst_confetti()


func _on_integrity_changed(id: StringName, integrity: float, maximum: float) -> void:
	if id != _package_id:
		return
	_distress = clampf(1.0 - integrity / maxf(maximum, 0.01), 0.0, 1.0)
	if _trap_id == &"growing_weight":
		_apply_growth()


## Item #23: any hit visibly rattles the box a little, on its own mesh, not
## only in the camera shake -- a fragile package taking a hit and a noisy
## one getting bumped both react, not just whichever trap already had a
## continuous effect running.
func _on_package_damaged(id: StringName, damage: float) -> void:
	if id != _package_id:
		return
	_impact_shake_strength = clampf(_impact_shake_strength + damage * IMPACT_SHAKE_PER_DAMAGE, 0.0, 1.0)
	_impact_damage_visual = clampf(_impact_damage_visual + damage * 0.035, 0.0, 1.0)
	_apply_damage_deformation()
	if damage >= LABEL_DROP_DAMAGE:
		_detach_shipping_label()


func _apply_damage_deformation() -> void:
	for index: int in _dent_pieces.size():
		var threshold: float = float(index) * 0.28
		var amount: float = clampf((_impact_damage_visual - threshold) / 0.45, 0.0, 1.0)
		_dent_pieces[index].scale = Vector3.ONE * amount


func _detach_shipping_label() -> void:
	if _label_detached or _shipping_label == null:
		return
	var package: Node3D = get_parent() as Node3D
	var world: Node = package.get_parent()
	if world == null:
		return
	var drop_transform: Transform3D = _shipping_label.global_transform
	_shipping_label.reparent(world)
	# Drop the Box's pulse/growth scale: a loose physics body must be unscaled.
	_shipping_label.global_transform = drop_transform.orthonormalized()
	_shipping_label.freeze = false
	_shipping_label.collision_layer = 4
	_shipping_label.collision_mask = 7
	_shipping_label.linear_velocity = (package as RigidBody3D).linear_velocity + Vector3(0.0, 1.2, 0.4)
	_label_detached = true


## Item #22: a quick settle bounce instead of the box appearing locked in
## place the instant it's set down.
func _on_package_placed(id: StringName) -> void:
	if id == _package_id:
		_bounce_time = 0.0


func _process(delta: float) -> void:
	_apply_jitter(delta)
	_apply_bounce(delta)
	match _trap_id:
		&"noisy":
			_apply_groan()
		&"growing_weight":
			_apply_creak(delta)


## Peso Creciente: the crate visibly swells and settles lower as its mass
## multiplier climbs, instead of only the HUD number changing. Straps stay
## their original size on purpose -- them visibly failing to contain a
## growing box reads as more urgent than if they grew to match it. Scale is
## tracked separately from the bounce's own scale pulse (_update_box_scale
## combines them) so placing a Peso Creciente package mid-grow doesn't have
## the two fight over Box.scale.
func _apply_growth() -> void:
	_growth_scale = lerpf(1.0, GROWING_WEIGHT_MAX_SCALE, _distress)
	_box.position.y = -GROWING_WEIGHT_SINK * _distress
	_update_box_scale()


func _update_box_scale() -> void:
	_box.scale = Vector3.ONE * _growth_scale * _bounce_scale_factor()


## Item #22: a quick damped squash-and-settle, roughly a classic spring
## curve, instead of a hard scale snap. Only touches Box's scale (position
## and the other nodes are untouched), so it composes cleanly with growth's
## own scale via _update_box_scale().
func _apply_bounce(delta: float) -> void:
	if _bounce_time < 0.0:
		return
	_bounce_time += delta
	if _bounce_time >= BOUNCE_DURATION:
		_bounce_time = -1.0
	_update_box_scale()


func _bounce_scale_factor() -> float:
	if _bounce_time < 0.0:
		return 1.0
	return 1.0 + BOUNCE_AMPLITUDE * exp(-BOUNCE_DECAY * _bounce_time) * cos(BOUNCE_FREQUENCY * _bounce_time)


## Combines Ruidoso's continuous agitation wobble with the universal,
## decaying impact shake (item #23) -- both move the same nodes, additively,
## so a Ruidoso box that also just got hit shudders harder for a moment
## rather than one effect silently overwriting the other. Position-only and
## purely local (never touches the RigidBody3D's real transform), so it
## can't desync physics or networking -- every client computes this
## independently from the same already-replicated integrity/damage events.
func _apply_jitter(delta: float) -> void:
	_impact_shake_strength = maxf(0.0, _impact_shake_strength - IMPACT_SHAKE_DECAY * delta)
	var wobble_amount: float = _distress if _trap_id == &"noisy" else 0.0
	var total: float = clampf(wobble_amount + _impact_shake_strength, 0.0, 1.5)
	if total <= 0.0:
		for entry: Dictionary in _wobble_nodes.values():
			(entry["node"] as Node3D).position = entry["base_position"]
		return
	_wobble_seed += delta * 14.0
	for entry: Dictionary in _wobble_nodes.values():
		var node: Node3D = entry["node"]
		var base: Vector3 = entry["base_position"]
		var jitter := Vector3(
			sin(_wobble_seed * 1.7 + base.x * 10.0),
			sin(_wobble_seed * 2.3 + base.y * 10.0),
			sin(_wobble_seed * 1.3 + base.z * 10.0),
		) * WOBBLE_AMPLITUDE * total
		node.position = base + jitter


## Ruidoso's audible half of the same distress that drives the wobble:
## louder and higher-pitched the more agitated it is, silent at rest so a
## calm crate isn't moaning in the background the whole ride.
func _apply_groan() -> void:
	if _distress <= 0.0:
		_groan_player.stop()
		return
	if not _groan_player.playing:
		_groan_player.play()
	_groan_player.volume_db = lerpf(-40.0, -6.0, _distress)
	_groan_player.pitch_scale = lerpf(0.85, 1.3, _distress)


## Peso Creciente's audible half: a creak burst, retriggered on its own
## schedule rather than every frame -- real creaking is intermittent, and
## the interval itself shortens as the box gets closer to unmanageable.
func _apply_creak(delta: float) -> void:
	if _distress <= 0.0:
		_creak_countdown = CREAK_INTERVAL_MAX
		return
	_creak_countdown -= delta
	if _creak_countdown <= 0.0:
		_creak_countdown = lerpf(CREAK_INTERVAL_MAX, CREAK_INTERVAL_MIN, _distress)
		_creak_player.pitch_scale = randf_range(0.9, 1.1)
		_creak_player.play()


## A handful of tiny colored cubes flung outward and pulled down by gravity --
## no particle texture/material asset needed, matches the placeholder-box style
## everything else in the prototype already uses.
func _burst_confetti() -> void:
	var origin: Vector3 = (get_parent() as Node3D).global_position
	var particles := GPUParticles3D.new()
	particles.top_level = true
	particles.emitting = false
	particles.one_shot = true
	particles.amount = CONFETTI_COUNT
	particles.lifetime = CONFETTI_LIFETIME
	particles.explosiveness = 1.0
	particles.draw_pass_1 = BoxMesh.new()
	(particles.draw_pass_1 as BoxMesh).size = Vector3.ONE * 0.09

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 180.0
	process_material.initial_velocity_min = 1.8
	process_material.initial_velocity_max = 4.2
	process_material.gravity = Vector3(0.0, -9.0, 0.0)
	process_material.color = CONFETTI_COLORS[randi() % CONFETTI_COLORS.size()]
	particles.process_material = process_material

	# current_scene is null in headless test trees that never loaded a scene --
	# falls back to the tree root so this still works there, not just in-game.
	var container: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	container.add_child(particles)
	particles.global_position = origin
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


## Called by package_pickup_point.gd while this package is (or stops being)
## the player's current interaction target -- a highlight instead of only
## the HUD's text prompt saying "Agarrar paquete" (item #98). An emission
## overlay, not a swapped albedo: the box's real color already carries its
## trap state, this just glows on top without fighting _set_state() for it.
func highlight(enabled: bool) -> void:
	_outline_wanted = enabled
	_apply_outline()


func _set_state(new_state: int) -> void:
	_state = new_state
	_material.albedo_color = STATE_TINT[clampi(new_state, 0, STATE_TINT.size() - 1)]

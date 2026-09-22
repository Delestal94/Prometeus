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

## Nodes wobbled for the Ruidoso trap -- every sibling that's actually part
## of the crate's look, so the whole box seems agitated, not just one plate.
const WOBBLE_NODE_NAMES: Array[StringName] = [&"Box", &"StrapX", &"StrapZ", &"Status", &"TopMark"]
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
const CARD_BOARD: Color = Color("7a5a36")
const INK: Color = Color("24150b")
const DANGER: Color = Color("bd4237")
const LABEL_DROP_DAMAGE: float = 18.0

@export var box_mesh_path: NodePath = ^"../Box"
@export var status_label_path: NodePath = ^"../Status"

var _material: StandardMaterial3D
var _package_id: StringName
var _label: Label3D
var _box: MeshInstance3D
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


func _ready() -> void:
	var parent: Node = get_parent()
	_package_id = parent.get("package_id")
	var definition: Resource = parent.get(&"trap_definition") as Resource
	_trap_id = StringName(definition.get(&"id")) if definition != null else &""
	# Distinct phase per package so several Ruidoso boxes riding together
	# don't all shudder in perfect unison.
	_wobble_seed = randf() * TAU
	_box = get_node(box_mesh_path) as MeshInstance3D
	_material = StandardMaterial3D.new()
	_material.roughness = 0.95
	_box.material_override = _material
	_label = get_node(status_label_path) as Label3D
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
	var box_mesh := BoxMesh.new()
	var shape_size := Vector3(0.65, 0.65, 0.65)
	var shipping_data: String = "4 kg · M\nFRÁGIL"
	match _trap_id:
		&"noisy":
			shipping_data = "6 kg · M\nVENTILADO"
			_add_vent_marks()
		&"balance":
			shape_size = Vector3(0.42, 0.98, 0.42)
			shipping_data = "3 kg · ALTO\nVERTICAL"
			_add_balance_seal()
		&"growing_weight":
			shape_size = Vector3(0.95, 0.42, 0.95)
			shipping_data = "? kg · XL\nDENSO"
			_add_weight_bands()
		_:
			_add_fragile_marks()
	box_mesh.size = shape_size
	_box.mesh = box_mesh
	_box.material_override = _material
	var collider: CollisionShape3D = package.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if collider != null:
		var shape := BoxShape3D.new()
		shape.size = shape_size
		collider.shape = shape
	_label.visible = false
	var top: Label3D = package.get_node_or_null(^"TopMark") as Label3D
	if top != null:
		top.visible = false
	_add_shipping_label(package, shipping_data)


func _add_shipping_label(package: Node, shipping_data: String) -> void:
	_shipping_label = RigidBody3D.new()
	_shipping_label.name = "ShippingLabel"
	_shipping_label.freeze = true
	_shipping_label.collision_layer = 4
	_shipping_label.collision_mask = 7
	_shipping_label.position = Vector3(0.0, 0.0, 0.342)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.46, 0.30, 0.02)
	collision.shape = shape
	_shipping_label.add_child(collision)
	var paper := _box_piece(Vector3(0.46, 0.25, 0.012), Color("efe2bd"))
	paper.position = Vector3(0.0, 0.0, 0.006)
	_shipping_label.add_child(paper)
	var text := Label3D.new()
	text.text = shipping_data
	text.font_size = 17
	text.pixel_size = 0.0015
	text.outline_size = 1
	text.modulate = INK
	text.position = Vector3(0.0, 0.0, 0.014)
	_shipping_label.add_child(text)
	package.add_child(_shipping_label)


func _add_fragile_marks() -> void:
	var marks := _identity_root(&"FragileGlassMarks")
	for angle: float in [-0.7, 0.7]:
		var crack := _box_piece(Vector3(0.04, 0.04, 0.46), DANGER)
		crack.position = Vector3(0.0, 0.0, 0.335)
		crack.rotation.z = angle
		marks.add_child(crack)


func _add_vent_marks() -> void:
	var vents := _identity_root(&"NoisyVentMarks")
	for x: float in [-0.18, -0.06, 0.06, 0.18]:
		var hole := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.035
		mesh.bottom_radius = 0.035
		mesh.height = 0.015
		hole.mesh = mesh
		hole.material_override = _flat_material(INK)
		hole.position = Vector3(x, 0.0, 0.334)
		hole.rotation.x = PI * 0.5
		vents.add_child(hole)


func _add_balance_seal() -> void:
	var seal := _box_piece(Vector3(0.13, 0.13, 0.025), DANGER)
	seal.position = Vector3(0.0, 0.0, 0.336)
	_identity_root(&"BalanceSeal").add_child(seal)


func _add_weight_bands() -> void:
	var bands := _identity_root(&"WeightBands")
	for z: float in [-0.28, 0.28]:
		var band := _box_piece(Vector3(0.98, 0.08, 0.06), INK)
		band.position = Vector3(0.0, 0.0, z)
		bands.add_child(band)


func _identity_root(identity_name: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = identity_name
	get_parent().add_child(root)
	return root


func _box_piece(size: Vector3, color: Color) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	piece.mesh = mesh
	piece.material_override = _flat_material(color)
	return piece


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


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
	if damage >= LABEL_DROP_DAMAGE:
		_detach_shipping_label()


func _detach_shipping_label() -> void:
	if _label_detached or _shipping_label == null:
		return
	var package: Node3D = get_parent() as Node3D
	var world: Node = package.get_parent()
	if world == null:
		return
	var drop_transform: Transform3D = _shipping_label.global_transform
	_shipping_label.reparent(world)
	_shipping_label.global_transform = drop_transform
	_shipping_label.freeze = false
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
	_material.emission_enabled = enabled
	_material.emission = Color.WHITE
	_material.emission_energy_multiplier = 0.9 if enabled else 0.0


func _set_state(new_state: int) -> void:
	match new_state:
		0:
			_material.albedo_color = Color("e8be77")
			_label.text = "FRÁGIL\n↑ ↑"
		1:
			_material.albedo_color = Color("ff883d")
			_label.text = "¡CUIDADO!\n↑ ↑"
		2:
			_material.albedo_color = Color("9a4547")
			_label.text = "ROTO\n× ×"

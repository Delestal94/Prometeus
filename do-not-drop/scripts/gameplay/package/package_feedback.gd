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
	if _trap_id == &"noisy":
		for wobble_name: StringName in WOBBLE_NODE_NAMES:
			var node: Node3D = get_node_or_null(NodePath("../" + String(wobble_name))) as Node3D
			if node != null:
				_wobble_nodes[wobble_name] = {"node": node, "base_position": node.position}
	_set_state(0)
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("package_state_changed", _on_package_state_changed)
		bus.connect("package_ruined", _on_package_ruined)
		bus.connect("package_integrity_changed", _on_integrity_changed)


func _on_package_state_changed(id: StringName, new_state: int) -> void:
	if id == _package_id:
		_set_state(new_state)


func _on_package_ruined(id: StringName, _cause: String) -> void:
	if id == _package_id:
		_burst_confetti()


func _on_integrity_changed(id: StringName, integrity: float, maximum: float) -> void:
	if id != _package_id:
		return
	_distress = clampf(1.0 - integrity / maxf(maximum, 0.01), 0.0, 1.0)
	if _trap_id == &"growing_weight":
		_apply_growth()


func _process(delta: float) -> void:
	if _trap_id == &"noisy":
		_apply_wobble(delta)


## Peso Creciente: the crate visibly swells and settles lower as its mass
## multiplier climbs, instead of only the HUD number changing. Straps stay
## their original size on purpose -- them visibly failing to contain a
## growing box reads as more urgent than if they grew to match it.
func _apply_growth() -> void:
	var scale_factor: float = lerpf(1.0, GROWING_WEIGHT_MAX_SCALE, _distress)
	_box.scale = Vector3.ONE * scale_factor
	_box.position.y = -GROWING_WEIGHT_SINK * _distress


## Ruidoso: a small continuous shudder scaled by agitation, on every visible
## part of the crate. Position-only and purely local (never touches the
## RigidBody3D's real transform), so it can't desync physics or networking --
## every client computes its own wobble independently from the same
## already-replicated integrity value.
func _apply_wobble(delta: float) -> void:
	if _distress <= 0.0:
		# Calmed down (or freshly initialized): snap back to rest instead of
		# leaving whatever jitter offset was last applied.
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
		) * WOBBLE_AMPLITUDE * _distress
		node.position = base + jitter


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

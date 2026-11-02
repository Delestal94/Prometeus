class_name PackingVfx
extends Node3D
## The packing table's effects in the company world, on every peer from the business events it already applies
## (CompanyNet.event_applied), never sent:
## - an order completed (expansion D-1914): a box sealed for its order and packed well (its trap intensity under
##   CompanyTuning.TRAP_INTENSITY_MID, BoxTrap.level() "low") bursts in confetti over the table, with a "✓" that
##   rises and fades.
## Each effect is a one-shot CPUParticles3D (GL Compatibility, no GPU particles needed) of BURST_AMOUNT small
## quads plus a Label3D, freed after EFFECT_SECONDS; at most MAX_EFFECTS live at once (the oldest goes first), so
## a busy shed never stacks them.

const EFFECT_SECONDS: float = 1.4
const MAX_EFFECTS: int = 6
const BURST_AMOUNT: int = 36
const MARK_RISE_M: float = 0.6
const MARK_HEIGHT_M: float = 1.3
const KIND_DONE: StringName = &"done"
const DONE_MARK: String = "✓"

## Live effects, oldest first.
var _effects: Array[Node3D] = []


## The effects under `root` (CompanyRoot), following root.net's events.
static func add_to(root: Node) -> PackingVfx:
	var vfx := PackingVfx.new()
	vfx.name = "PackingVfx"
	root.add_child(vfx)
	var net: Object = root.get(&"net")
	if net != null and net.has_signal(&"event_applied"):
		net.connect(&"event_applied", vfx.on_event)
	return vfx


## A business event applied on this peer: a box sealed plays its effect at its table.
func on_event(_seq: int, kind: StringName, data: Dictionary) -> void:
	if kind != CompanyTableNet.SEALED:
		return
	var effect: StringName = effect_for(data)
	var spot: Variant = data.get("pos")
	if effect != &"" and spot is Vector3:
		play(effect, spot)


## Which effect a box_sealed calls for: KIND_DONE for a well packed box with its order, &"" for none.
static func effect_for(data: Dictionary) -> StringName:
	var order: String = str(data.get("order", ""))
	var intensity: float = float(data.get("trap_intensity", 1.0))
	if order != "" and intensity < CompanyTuning.TRAP_INTENSITY_MID:
		return KIND_DONE
	return &""


## Plays `effect` at `spot` (global): the burst and its mark, gone after EFFECT_SECONDS.
func play(effect: StringName, spot: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Effect_%s" % effect
	add_child(holder)
	holder.global_position = spot
	holder.add_child(_burst(effect))
	var mark: Label3D = _mark(effect)
	holder.add_child(mark)
	var rise := mark.create_tween()
	rise.set_parallel(true)
	rise.tween_property(mark, ^"position:y", MARK_HEIGHT_M + MARK_RISE_M, EFFECT_SECONDS)
	rise.tween_property(mark, ^"modulate:a", 0.0, EFFECT_SECONDS).set_ease(Tween.EASE_IN)
	_effects.append(holder)
	while _effects.size() > MAX_EFFECTS:
		var oldest: Node3D = _effects.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	get_tree().create_timer(EFFECT_SECONDS).timeout.connect(_expire.bind(holder))
	return holder


## The effects alive now.
func live() -> Array[Node3D]:
	var alive: Array[Node3D] = []
	for effect: Node3D in _effects:
		if is_instance_valid(effect) and not effect.is_queued_for_deletion():
			alive.append(effect)
	return alive


func _expire(holder: Node3D) -> void:
	_effects.erase(holder)
	if is_instance_valid(holder):
		holder.queue_free()


func _burst(_effect: StringName) -> CPUParticles3D:
	var burst := CPUParticles3D.new()
	burst.name = "Burst"
	burst.one_shot = true
	burst.amount = BURST_AMOUNT
	burst.lifetime = EFFECT_SECONDS * 0.8
	burst.explosiveness = 0.9
	burst.position = Vector3.UP * 1.0
	burst.direction = Vector3.UP
	burst.spread = 55.0
	burst.initial_velocity_min = 2.5
	burst.initial_velocity_max = 4.5
	burst.gravity = Vector3(0.0, -7.0, 0.0)
	burst.angular_velocity_min = -360.0
	burst.angular_velocity_max = 360.0
	burst.scale_amount_min = 0.6
	burst.scale_amount_max = 1.2
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.05)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = material
	burst.mesh = quad
	var colors := Gradient.new()
	colors.colors = PackedColorArray([UiTheme.MINT, UiTheme.YELLOW, UiTheme.WHITE])
	colors.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	burst.color_initial_ramp = colors
	burst.emitting = true
	return burst


func _mark(_effect: StringName) -> Label3D:
	var mark := Label3D.new()
	mark.name = "Mark"
	mark.text = DONE_MARK
	mark.modulate = UiTheme.MINT
	mark.outline_modulate = UiTheme.INK
	mark.outline_size = 16
	mark.font_size = 96
	mark.pixel_size = 0.006
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.position = Vector3.UP * MARK_HEIGHT_M
	return mark

extends Node
## Presentation-only: the box's flaps, what's inside it, and what falls out.
##
## Never decides anything. package.gd owns the facts (is_open,
## contents_spilled, trap state) on the host and relays them through the
## EventBus; every peer runs this on its own copy and animates the same
## thing, like package_feedback.gd's confetti and torn label.
##
## The box model (built by package_feedback.gd under Box/Model) has its four
## flaps pivoted on their hinges; the content model (PackageContent.model)
## is placed on the box floor under Box, so it swells and shudders with the
## box. It carries four parts: Filler (packing), Intact, Damage (extra bits
## shown while AT_RISK) and Ruined (loose pieces).

## How far each flap swings past closed. Outer flaps (front/back, the ones
## with the tape) fold out and hang a little; the side flaps stand up.
const OUTER_OPEN_ANGLE: float = deg_to_rad(108.0)
const INNER_OPEN_ANGLE: float = deg_to_rad(100.0)
const OPEN_SECONDS: float = 0.55
const CLOSE_SECONDS: float = 0.4
## Board thickness of the box models (assets/tools/build_cargo_packages.py):
## the content sits on the inner floor, not the outer bottom.
const BOARD: float = 0.012
## Loose pieces lie around for a while, then go -- an endless run can spill a
## lot of boxes, and nothing reads them back.
const DEBRIS_LIFETIME: float = 25.0
const FILLER_BITS: int = 10
## environment | vehicle | packages: pieces land on the road, the cargo floor
## or other boxes, but sit on no layer of their own, so they never block a
## player or trip a trap's impact check.
const DEBRIS_MASK: int = 1 | 2 | 4

var _package: RigidBody3D
var _package_id: StringName
var _box: Node3D
var _flaps: Dictionary = {}  ## flap name -> Node3D
var _contents: Node3D
var _filler: Node3D
var _intact: Node3D
var _damage: Node3D
var _ruined: Node3D
var _state: int = 0
var _open: bool = false
var _spilled: bool = false
var _taped: bool = true
## 0 closed .. 1 fully open; the flaps are posed from it every time it moves.
var open_amount: float = 0.0:
	set(value):
		open_amount = value
		_pose_flaps()
var _tween: Tween
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	_package = get_parent() as RigidBody3D
	_package_id = _package.get(&"package_id")
	_box = _package.get_node_or_null(^"Box") as Node3D
	_audio = AudioStreamPlayer3D.new()
	_audio.unit_size = 5.0
	_audio.max_distance = 18.0
	add_child(_audio)
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("package_lid_changed", _on_lid_changed)
		bus.connect("package_state_changed", _on_state_changed)
		bus.connect("package_contents_spilled", _on_contents_spilled)
	# After package_feedback.gd's own deferred _apply_identity (an earlier
	# sibling, so its call is queued first): the box model has to exist.
	call_deferred(&"_build")


func _build() -> void:
	if _box == null or _contents != null:
		return
	var model: Node = _box.get_node_or_null(^"Model")
	if model != null:
		for flap_name: StringName in [&"FlapFront", &"FlapBack", &"FlapRight", &"FlapLeft"]:
			var flap: Node3D = model.find_child(String(flap_name), true, false) as Node3D
			if flap != null:
				_flaps[flap_name] = flap
	var content: Resource = _package.call(&"content_definition") if _package.has_method(&"content_definition") else null
	if content != null and content.get(&"model") != null:
		var size: Vector3 = content.get(&"box_size")
		_contents = (content.get(&"model") as PackedScene).instantiate()
		_contents.name = "Contents"
		_contents.position.y = -size.y * 0.5 + BOARD
		_box.add_child(_contents)
		_filler = _contents.get_node_or_null(^"Filler") as Node3D
		_intact = _contents.get_node_or_null(^"Intact") as Node3D
		_damage = _contents.get_node_or_null(^"Damage") as Node3D
		_ruined = _contents.get_node_or_null(^"Ruined") as Node3D
	# Late joiners (and a box opened before this ran) get the replicated
	# state snapped into place, no animation.
	_state = int(_package.get(&"trap_state"))
	_spilled = bool(_package.get(&"contents_spilled"))
	_open = bool(_package.get(&"is_open")) or _spilled
	_taped = not _open
	open_amount = 1.0 if _open else 0.0
	_refresh_contents()


func is_built() -> bool:
	return _contents != null or not _flaps.is_empty()


## What a player looking in would see, for the HUD: "Jarrón de porcelana
## (intacto)". Empty while closed.
func describe() -> String:
	var content: Resource = _package.call(&"content_definition") if _package.has_method(&"content_definition") else null
	if content == null or not _open:
		return ""
	if _spilled:
		return "Vacía: se cayó %s" % String(content.get(&"display_name")).to_lower()
	return "%s (%s)" % [content.get(&"display_name"), content.call(&"condition_text", _state)]


func _on_lid_changed(id: StringName, open: bool) -> void:
	if id != _package_id:
		return
	if _contents == null and _flaps.is_empty():
		_build()
	if open == _open:
		return
	_open = open
	_play_lid_sound(open)
	_taped = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	if open:
		_tween.tween_property(self, ^"open_amount", 1.0, OPEN_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_property(self, ^"open_amount", 0.0, CLOSE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_refresh_contents)
	_refresh_contents()


func _on_state_changed(id: StringName, new_state: int) -> void:
	if id != _package_id:
		return
	_state = new_state
	_refresh_contents()


## Outer flaps lead on the way open and trail on the way shut, the side
## flaps the other way round -- the same order a person folds a real box, so
## the flaps never pass through each other.
func _pose_flaps() -> void:
	# The open tween overshoots past 1 (TRANS_BACK); only that overshoot, not
	# the 1.5x lead, may carry a flap beyond its resting open angle.
	var overshoot: float = maxf(open_amount - 1.0, 0.0)
	var outer: float = clampf(open_amount * 1.5, 0.0, 1.0) + overshoot
	var inner: float = clampf(open_amount * 1.5 - 0.5, 0.0, 1.0) + overshoot
	_set_flap(&"FlapFront", Vector3(outer * OUTER_OPEN_ANGLE, 0.0, 0.0))
	_set_flap(&"FlapBack", Vector3(-outer * OUTER_OPEN_ANGLE, 0.0, 0.0))
	_set_flap(&"FlapRight", Vector3(0.0, 0.0, -inner * INNER_OPEN_ANGLE))
	_set_flap(&"FlapLeft", Vector3(0.0, 0.0, inner * INNER_OPEN_ANGLE))
	if _contents != null:
		# Nothing to draw inside a shut box.
		_contents.visible = open_amount > 0.001


func _set_flap(flap_name: StringName, rotation: Vector3) -> void:
	var flap: Node3D = _flaps.get(flap_name) as Node3D
	if flap != null:
		flap.rotation = rotation


func _refresh_contents() -> void:
	if _contents == null:
		return
	_contents.visible = open_amount > 0.001
	var ruined: bool = _state >= ITrapBehavior.TrapState.RUINED
	_set_visible(_filler, not _spilled)
	_set_visible(_intact, not _spilled and not ruined)
	_set_visible(_damage, not _spilled and _state == ITrapBehavior.TrapState.AT_RISK)
	_set_visible(_ruined, not _spilled and ruined)


func _set_visible(node: Node3D, value: bool) -> void:
	if node != null:
		node.visible = value


func _play_lid_sound(open: bool) -> void:
	_audio.stream = SynthAudio.tape_rip() if open and _taped else SynthAudio.cardboard_flap()
	_audio.pitch_scale = randf_range(0.92, 1.08)
	_audio.play()


## The contents come out as real rigid bodies: the item itself (or, if it was
## already wrecked, each of its pieces) plus a handful of packing scraps.
func _on_contents_spilled(id: StringName, velocity: Vector3, state_before: int) -> void:
	if id != _package_id or _spilled:
		return
	if _contents == null and _flaps.is_empty():
		_build()
	_spilled = true
	_open = true
	open_amount = 1.0
	var world: Node = _package.get_parent()
	if _contents != null and world != null:
		var pieces: Array[Node] = []
		if state_before >= ITrapBehavior.TrapState.RUINED and _ruined != null:
			pieces.assign(_ruined.get_children())
		elif _intact != null:
			pieces.append(_intact)
		for piece: Node in pieces:
			if piece is MeshInstance3D:
				_throw_piece(world, piece as MeshInstance3D, velocity)
		if _filler != null:
			_throw_filler(world, velocity)
	_refresh_contents()
	_audio.stream = SynthAudio.impact_thud()
	_audio.pitch_scale = 1.3
	_audio.play()


func _throw_piece(world: Node, source: MeshInstance3D, velocity: Vector3) -> void:
	var body := _debris_body(world, source.global_transform)
	var mesh := MeshInstance3D.new()
	mesh.mesh = source.mesh
	for surface: int in source.get_surface_override_material_count():
		mesh.set_surface_override_material(surface, source.get_surface_override_material(surface))
	body.add_child(mesh)
	var collider := CollisionShape3D.new()
	collider.shape = source.mesh.create_convex_shape(true, true)
	body.add_child(collider)
	body.mass = 1.0
	body.linear_velocity = velocity + _pop(1.6)
	body.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))


func _throw_filler(world: Node, velocity: Vector3) -> void:
	var filler_mesh: MeshInstance3D = _filler as MeshInstance3D
	if filler_mesh == null:
		filler_mesh = _filler.find_children("*", "MeshInstance3D", true, false).front() as MeshInstance3D
	var material: Material = null
	if filler_mesh != null and filler_mesh.mesh != null and filler_mesh.mesh.get_surface_count() > 0:
		material = filler_mesh.mesh.surface_get_material(0)
	var origin: Transform3D = _filler.global_transform
	for i: int in FILLER_BITS:
		var at := origin.translated(Vector3(randf_range(-0.15, 0.15), 0.08, randf_range(-0.15, 0.15)))
		var body := _debris_body(world, at)
		var bit := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(randf_range(0.05, 0.1), 0.006, 0.016)
		box.material = material
		bit.mesh = box
		body.add_child(bit)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		collider.shape = shape
		body.add_child(collider)
		body.mass = 0.02
		# Paper flutters: heavy drag instead of dropping like a stone.
		body.linear_damp = 3.0
		body.angular_damp = 1.0
		body.linear_velocity = velocity + _pop(2.4)


func _debris_body(world: Node, at: Transform3D) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "SpilledContent"
	body.collision_layer = 0
	body.collision_mask = DEBRIS_MASK
	world.add_child(body, true)
	body.global_transform = at
	get_tree().create_timer(DEBRIS_LIFETIME).timeout.connect(body.queue_free)
	return body


func _pop(strength: float) -> Vector3:
	return Vector3(randf_range(-1.0, 1.0), randf_range(0.8, 1.4), randf_range(-1.0, 1.0)) * strength

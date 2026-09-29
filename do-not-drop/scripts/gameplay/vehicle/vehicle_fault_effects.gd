extends Node3D
class_name VehicleFaultEffects
## What a truck fault looks and sounds like (tareas de Nacho N-214.2), on
## every peer. VehicleFaults decides and keeps the list; this only draws it,
## from the same relayed EventBus signals, so it never touches the
## simulation (vehicle.gd is frozen: the model's parts are hidden from
## outside, never edited).
##
## - Mirror: the driver's side mirror breaks off the van (housing and glass
##   hidden, a copy tumbles onto the road) with a glass crack.
## - Rear door: a metal clank at the doors on the hit; the door swinging open
##   itself is VehicleFaults' job on the host and the van's own animation.
## A repair puts the mirror back.

## Model node names of the exterior mirrors (truck_reference_lowpoly.glb);
## the side is picked by position, not by name.
const MIRROR_PARTS: Array[String] = ["MirrorHousing_*", "MirrorSurface_*"]
## How long the broken-off piece takes to reach the road and stays there.
const FALL_SECONDS: float = 0.7
const DEBRIS_SECONDS: float = 6.0

## The van whose parts break; null leaves only the bookkeeping.
var vehicle: Node3D
## Every peer: the mirror parts hidden by the current fault.
var hidden_parts: Array[Node3D] = []
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	_audio = AudioStreamPlayer3D.new()
	_audio.name = "FaultAudio"
	_audio.bus = &"SFX"
	add_child(_audio)
	EventBus.vehicle_fault_started.connect(_on_fault_started)
	EventBus.vehicle_fault_repaired.connect(_on_fault_repaired)
	EventBus.run_started.connect(func(_route_id: StringName, _players: Array) -> void: restore())


## Every hidden part back in place: a repair or a fresh run.
func restore() -> void:
	for part: Node3D in hidden_parts:
		if is_instance_valid(part):
			part.visible = true
	hidden_parts.clear()


## The exterior mirror parts on the driver's side (the van's -X, where
## DriverEyePoint sits), or none if the model isn't there.
func driver_mirror_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = []
	if vehicle == null:
		return parts
	for pattern: String in MIRROR_PARTS:
		for node: Node in vehicle.find_children(pattern, "Node3D", true, false):
			var part := node as Node3D
			if vehicle.to_local(part.global_position).x < 0.0:
				parts.append(part)
	return parts


func _on_fault_started(fault_id: StringName, _impact_position: Vector3) -> void:
	match fault_id:
		&"mirror":
			_break_mirror()
		&"rear_door":
			if vehicle != null:
				_play(SynthAudio.impact_thud(), vehicle.to_global(Vector3(0.0, 1.4, 4.2)), 1.6, -4.0)


func _on_fault_repaired(fault_id: StringName, _method: StringName) -> void:
	if fault_id == &"mirror":
		restore()


func _break_mirror() -> void:
	var parts: Array[Node3D] = driver_mirror_parts()
	if parts.is_empty():
		return
	_play(SynthAudio.glass_chime(), parts[0].global_position, 0.7, 0.0)
	var world: Node = vehicle.get_parent()
	for part: Node3D in parts:
		if not part.visible:
			continue
		part.visible = false
		hidden_parts.append(part)
		if world == null or not part.is_inside_tree():
			continue
		# A loose copy left behind on the road: the van drives on without it.
		var piece := part.duplicate(0) as Node3D
		piece.top_level = true
		piece.visible = true
		world.add_child(piece)
		piece.global_transform = part.global_transform
		var landing: Vector3 = piece.global_position
		landing.y = vehicle.global_position.y + 0.05
		var tween := piece.create_tween().set_parallel()
		tween.tween_property(piece, ^"global_position", landing, FALL_SECONDS) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(piece, ^"rotation", piece.rotation + Vector3(1.4, 0.6, 2.1), FALL_SECONDS)
		tween.chain().tween_interval(DEBRIS_SECONDS)
		tween.chain().tween_callback(piece.queue_free)


func _play(stream: AudioStream, at: Vector3, pitch: float, volume_db: float) -> void:
	if not _audio.is_inside_tree():
		return
	_audio.global_position = at
	_audio.stream = stream
	_audio.pitch_scale = pitch
	_audio.volume_db = volume_db
	_audio.play()

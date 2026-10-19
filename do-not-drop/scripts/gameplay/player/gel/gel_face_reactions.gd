class_name GelFaceReactions
extends Node
## Presentation-only face state for a player. Gameplay remains authoritative
## elsewhere; this component observes replicated player/package state and the
## relayed delivery event, then chooses one stable face from FaceCatalog.

const Catalog = preload("res://scripts/core/face_catalog.gd")
const OUTCOME_OK: StringName = &"delivered_ok"
const BASE_FACE: StringName = &"base"
const FALL_SPEED: float = -1.0
const DELIVERY_HOLD_MSEC: int = 1800
const BOX_MEMORY_MSEC: int = 2500

var player: Node
var face: Node
var current_face_id: StringName = BASE_FACE
var knocked_out: bool = false

var _base_face_id: StringName = &"none"
var _last_applied: StringName = &""
var _last_base_eyes: StringName = &""
var _last_base_mouth: StringName = &""
var _box_id: StringName = &""
var _box_seen_at: int = -BOX_MEMORY_MSEC
var _happy_until: int = 0


func _init() -> void:
	name = &"GelFaceReactions"


func _ready() -> void:
	player = get_parent()
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"house_delivery_recorded", _on_house_delivery_recorded)


func _process(_delta: float) -> void:
	if player == null:
		return
	var held: Node = _held_box()
	if held != null:
		_box_id = StringName(held.get(&"package_id"))
		_box_seen_at = Time.get_ticks_msec()
	if not is_instance_valid(face):
		set_face_target(_find_face())
	_refresh()


## Explicit future gameplay hook. Knockout has priority over every transient.
func set_knocked_out(active: bool) -> void:
	knocked_out = active
	_refresh()


## Lets customisation (S-311.61) replace the neutral gel face without knowing
## anything about the temporary gameplay reactions.
func set_base_face(face_id: StringName) -> void:
	_base_face_id = StringName(Catalog.gel_face(face_id).id)
	_last_applied = &""
	_refresh()


func set_face_target(target: Node) -> void:
	if target == face:
		return
	face = target
	_last_applied = &""
	if face != null and face.has_method(&"set_face"):
		_base_face_id = StringName(face.get(&"face_id"))
	_refresh()


func reaction_face() -> StringName:
	if knocked_out:
		return &"knockout"
	if bool(player.get(&"_ragdolled")):
		return &"crossed"
	if _is_falling():
		return &"surprised"
	var held: Node = _held_box()
	if held != null and _package_state(held) == ITrapBehavior.TrapState.AT_RISK:
		return &"worried"
	if Time.get_ticks_msec() < _happy_until:
		return &"happy"
	return BASE_FACE


func owns_box(package_id: StringName) -> bool:
	var held: Node = _held_box()
	if held != null and StringName(held.get(&"package_id")) == package_id:
		return true
	var peer_id: int = player.get_multiplayer_authority()
	for candidate: Node in get_tree().get_nodes_in_group(&"cargo"):
		if StringName(candidate.get(&"package_id")) != package_id:
			continue
		if candidate.get(&"carrier") == player or int(candidate.get(&"tender_peer_id")) == peer_id:
			return true
	return false


func _refresh() -> void:
	if player == null or not is_instance_valid(face):
		return
	var next: StringName = reaction_face()
	current_face_id = next
	if next == BASE_FACE:
		_apply_base()
	elif next != _last_applied:
		_apply_face(next)


func _apply_base() -> void:
	if face.has_method(&"set_face"):
		if _last_applied != BASE_FACE:
			face.call(&"set_face", _base_face_id)
			_last_applied = BASE_FACE
		return
	var eyes := StringName(player.get(&"face_eyes"))
	var mouth := StringName(player.get(&"face_mouth"))
	if _last_applied == BASE_FACE and eyes == _last_base_eyes and mouth == _last_base_mouth:
		return
	face.call(&"set_expression", eyes, mouth)
	_last_base_eyes = eyes
	_last_base_mouth = mouth
	_last_applied = BASE_FACE


func _apply_face(face_id: StringName) -> void:
	if face.has_method(&"set_face"):
		face.call(&"set_face", face_id)
	else:
		var expression: Dictionary = Catalog.gel_face(face_id)
		face.call(&"set_expression", expression.eyes, expression.mouth)
	_last_applied = face_id


func _find_face() -> Node:
	var body: Node = player.get(&"_body_visual")
	if is_instance_valid(body):
		var gel_face: Node = body.find_child("GelFace", true, false)
		if gel_face != null:
			return gel_face
	var legacy: Node = player.get(&"_character_face")
	return legacy if is_instance_valid(legacy) else null


func _held_box() -> Node:
	for property: StringName in [&"carried_package", &"tended_package", &"assisted_package"]:
		var candidate: Variant = player.get(property)
		if is_instance_valid(candidate) and candidate is Node:
			return candidate
	return null


func _package_state(package: Node) -> int:
	if package.has_method(&"run_state"):
		return int(package.call(&"run_state"))
	return int(package.get(&"trap_state"))


func _is_falling() -> bool:
	if not player is CharacterBody3D or bool(player.get(&"net_in_vehicle")):
		return false
	var body := player as CharacterBody3D
	return not body.is_on_floor() and body.velocity.y < FALL_SPEED


func _on_house_delivery_recorded(_house_index: int, outcome: StringName, package_id: StringName) -> void:
	if outcome != OUTCOME_OK:
		return
	var remembered: bool = package_id == _box_id \
		and Time.get_ticks_msec() - _box_seen_at <= BOX_MEMORY_MSEC
	if remembered or owns_box(package_id):
		_happy_until = Time.get_ticks_msec() + DELIVERY_HOLD_MSEC
		_refresh()

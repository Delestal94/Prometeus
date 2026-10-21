class_name PlayerGelAppearance
extends Node
## Binds the active gel model to the host-owned appearance state. Shape and
## skin update only when their compact replicated values change.

const Shaper := preload("res://scripts/gameplay/player/gel/gel_body_shaper.gd")

var _body: Node3D
var _state: PlayerGelProportionSync
var _shaper := Shaper.new()
var _team_color: Color = Color.TRANSPARENT
var _settings: Node


func setup(body: Node3D) -> void:
	_body = body
	_state = get_parent().get_node(^"GelProportions") as PlayerGelProportionSync
	_settings = get_node_or_null(^"/root/GameSettings")
	var use_opaque: bool = bool(_settings.call(&"uses_opaque_gel")) if _settings != null else false
	PlayerAppearance.set_gel_material(_body, use_opaque)
	_shaper.setup(_body)
	_shaper.apply(_state.proportions)
	_state.proportions_changed.connect(_shaper.apply)
	_state.skin_changed.connect(_apply_skin)
	if _settings != null:
		_settings.connect(&"gel_material_mode_changed", _set_opaque)
	_apply_skin(_state.skin_id)


func set_team_color(color: Color) -> void:
	_team_color = color
	if _state != null:
		_apply_skin(_state.skin_id)


func _apply_skin(skin_id: StringName) -> void:
	if _body != null:
		PlayerAppearance.apply_gel_skin(_body, skin_id, _team_color)


func _set_opaque(use_opaque: bool) -> void:
	if _body == null:
		return
	PlayerAppearance.set_gel_material(_body, use_opaque)
	_apply_skin(_state.skin_id)

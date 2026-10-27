class_name PlayerGelEffects
extends Node
## Owns the local, presentation-only gel effects attached to a player. Keeping
## their orchestration here prevents player.gd from accumulating visual logic.

const Knockout = preload("res://scripts/gameplay/player/gel/gel_knockout.gd")

@onready var _contact: Node = $GelContact
@onready var _environment: Node = $GelEnvironment
@onready var _knockout: Node = $GelKnockout

## Owner-authored presentation state. MultiplayerSynchronizer replicates this
## child property so player.gd does not absorb another visual responsibility.
var knocked_out: bool = false:
	set(value):
		if knocked_out == value:
			return
		knocked_out = value
		if is_node_ready():
			_apply_knockout(value)


func setup(model: Node, phase_seed: int) -> void:
	_contact.setup(model)
	_environment.setup(model, phase_seed)
	_knockout.setup(model)
	_apply_knockout(knocked_out)


func update_effects(player: CharacterBody3D, delta: float) -> void:
	if not _knockout.is_active():
		_contact.update_contact(player, delta)
	_environment.update_environment(delta)
	_knockout.advance(delta)


## Gameplay causes use this owner-side hook; remote peers receive the property.
func set_local_knocked_out(active: bool) -> bool:
	var player := get_parent() as Player
	if player == null or not player.is_local():
		return false
	knocked_out = active
	return true


func _apply_knockout(active: bool) -> void:
	_contact.reset_deformation()
	_knockout.set_knocked_out(active)
	var reactions := get_parent().get_node_or_null(^"GelFaceReactions") as GelFaceReactions
	if reactions != null:
		reactions.set_knocked_out(active)


func knockout_amount() -> float:
	return _knockout.amount


func knockout_phase() -> int:
	return _knockout.phase

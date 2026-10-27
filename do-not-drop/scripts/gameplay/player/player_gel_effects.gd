class_name PlayerGelEffects
extends Node
## Owns the local, presentation-only gel effects attached to a player. Keeping
## their orchestration here prevents player.gd from accumulating visual logic.

const Knockout = preload("res://scripts/gameplay/player/gel/gel_knockout.gd")

@onready var _contact: Node = $GelContact
@onready var _environment: Node = $GelEnvironment
@onready var _knockout: Node = $GelKnockout

## Owner-authored presentation state. MultiplayerSynchronizer replicates the
## cause so every peer chooses the same bounded particles and shader shape.
var knockout_cause: int = Knockout.Cause.NONE:
	set(value):
		var normalized := clampi(value, Knockout.Cause.NONE, Knockout.Cause.RUN_OVER)
		if knockout_cause == normalized:
			return
		knockout_cause = normalized
		if is_node_ready():
			_apply_knockout(normalized)
var knocked_out: bool:
	get:
		return knockout_cause != Knockout.Cause.NONE


func setup(model: Node, phase_seed: int) -> void:
	_contact.setup(model)
	_environment.setup(model, phase_seed)
	_knockout.setup(model)
	_apply_knockout(knockout_cause)


func update_effects(player: CharacterBody3D, delta: float) -> void:
	if not _knockout.is_active():
		_contact.update_contact(player, delta)
	_environment.update_environment(delta)
	_knockout.advance(delta)


## Gameplay causes use this owner-side hook; remote peers receive the property.
func set_local_knocked_out(active: bool) -> bool:
	return set_local_knockout_cause(Knockout.Cause.MELT if active else Knockout.Cause.NONE)


func set_local_knockout_cause(cause: int) -> bool:
	var player := get_parent() as Player
	if player == null or not player.is_local():
		return false
	knockout_cause = cause
	return true


func _apply_knockout(cause: int) -> void:
	_contact.reset_deformation()
	_knockout.set_knockout_cause(cause)
	var reactions := get_parent().get_node_or_null(^"GelFaceReactions") as GelFaceReactions
	if reactions != null:
		reactions.set_knocked_out(cause != Knockout.Cause.NONE)


func knockout_amount() -> float:
	return _knockout.amount


func knockout_phase() -> int:
	return _knockout.phase

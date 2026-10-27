class_name PlayerGelEffects
extends Node
## Owns the local, presentation-only gel effects attached to a player. Keeping
## their orchestration here prevents player.gd from accumulating visual logic.

const Knockout = preload("res://scripts/gameplay/player/gel/gel_knockout.gd")

@onready var _contact: Node = $GelContact
@onready var _environment: Node = $GelEnvironment
@onready var _knockout: Node = $GelKnockout


func setup(model: Node, phase_seed: int) -> void:
	_contact.setup(model)
	_environment.setup(model, phase_seed)
	_knockout.setup(model)


func update_effects(player: CharacterBody3D, delta: float) -> void:
	if not _knockout.is_active():
		_contact.update_contact(player, delta)
	_environment.update_environment(delta)
	_knockout.advance(delta)


func set_knocked_out(active: bool) -> void:
	_contact.reset_deformation()
	_knockout.set_knocked_out(active)


func knockout_amount() -> float:
	return _knockout.amount


func knockout_phase() -> int:
	return _knockout.phase

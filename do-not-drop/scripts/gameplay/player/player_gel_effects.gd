class_name PlayerGelEffects
extends Node
## Owns the local, presentation-only gel effects attached to a player. Keeping
## their orchestration here prevents player.gd from accumulating visual logic.

@onready var _contact: Node = $GelContact
@onready var _environment: Node = $GelEnvironment


func setup(model: Node, phase_seed: int) -> void:
	_contact.setup(model)
	_environment.setup(model, phase_seed)


func update_effects(player: CharacterBody3D, delta: float) -> void:
	_contact.update_contact(player, delta)
	_environment.update_environment(delta)

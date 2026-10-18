extends Node
## Presentation-only lifecycle for the replicated gel ragdoll.
##
## The host sends one impulse and seed through Player.receive_package_hit().
## Every peer then simulates the same player's visible rig locally. The
## CharacterBody3D capsule, its collision contract and its authority stay
## untouched.

signal finished

const GelRagdoll := preload("res://scripts/gameplay/player/gel/gel_active_ragdoll.gd")
const MAX_CAPSULE_OFFSET: float = 0.45

var last_seed: int = 0
var _active_ragdoll: Node


func start(player: Node, push: Vector3, simulation_seed: int) -> bool:
	if _active_ragdoll != null or not push.is_finite():
		return false
	var body_visual := player.get(&"_body_visual") as Node3D
	var proportions: Resource = player.get_node(^"GelProportions").get(&"proportions")
	if body_visual == null:
		return false
	var ragdoll: Node = GelRagdoll.new()
	player.add_child(ragdoll)
	if not ragdoll.setup(body_visual, proportions, 1 | 64, player):
		ragdoll.queue_free()
		return false
	ragdoll.set_recovery_anchor_limit(MAX_CAPSULE_OFFSET)
	last_seed = simulation_seed
	_active_ragdoll = ragdoll
	_run_fall(ragdoll, push, simulation_seed)
	return true


func is_active() -> bool:
	return _active_ragdoll != null


func active_ragdoll() -> Node:
	return _active_ragdoll


func _run_fall(ragdoll: Node, push: Vector3, simulation_seed: int) -> void:
	ragdoll.fall(push, Vector3.ZERO, simulation_seed)
	await ragdoll.finished
	if _active_ragdoll == ragdoll:
		_active_ragdoll = null
	finished.emit()

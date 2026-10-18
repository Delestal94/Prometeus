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
const WORLD_LAYER: int = 1
const CARGO_LAYER: int = 4
const VEHICLE_SHELL_LAYER: int = 64
const RAGDOLL_COLLISION_MASK: int = WORLD_LAYER | CARGO_LAYER | VEHICLE_SHELL_LAYER

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
	if not ragdoll.setup(body_visual, proportions, RAGDOLL_COLLISION_MASK, player):
		ragdoll.queue_free()
		return false
	ragdoll.set_recovery_anchor_limit(MAX_CAPSULE_OFFSET)
	last_seed = simulation_seed
	_active_ragdoll = ragdoll
	_run_fall(ragdoll, push, _carrier_velocity(player), simulation_seed)
	return true


func is_active() -> bool:
	return _active_ragdoll != null


func active_ragdoll() -> Node:
	return _active_ragdoll


func _run_fall(
	ragdoll: Node,
	push: Vector3,
	carried_velocity: Vector3,
	simulation_seed: int
) -> void:
	ragdoll.fall(push, carried_velocity, simulation_seed)
	await ragdoll.finished
	if _active_ragdoll == ragdoll:
		_active_ragdoll = null
	finished.emit()


## Matches the legacy ragdoll contract: a fall that starts in the cargo bay
## inherits the moving truck's linear and angular point velocity. Vehicle
## already replicates that state, so every peer can seed its visual copy.
func _carrier_velocity(player: Node3D) -> Vector3:
	if not player.has_method(&"_find_vehicle"):
		return Vector3.ZERO
	var carrier: Node = player.call(&"_find_vehicle") as Node
	if carrier == null or not carrier.has_method(&"carries") \
			or not carrier.has_method(&"point_velocity"):
		return Vector3.ZERO
	if not bool(carrier.call(&"carries", player.global_position)):
		return Vector3.ZERO
	var carried: Variant = carrier.call(&"point_velocity", player.global_position)
	if carried is Vector3 and (carried as Vector3).is_finite():
		return carried as Vector3
	return Vector3.ZERO

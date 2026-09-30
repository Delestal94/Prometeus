extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/ragdoll/tests/test_ragdoll.gd
##
## The ragdoll module on its own (docs/modulos.md): fall() hides the
## character and spawns six rigid capsules under the scene root with the
## collision mask handed in; the pieces start out with the carrier's
## velocity when one says it carries the character; a second fall() while
## one is active does nothing; after LIFETIME the character is visible
## again and the ragdoll is gone.

var _failures: int = 0


class Carrier extends Node3D:
	func carries(_point: Vector3) -> bool:
		return true

	func point_velocity(_point: Vector3) -> Vector3:
		return Vector3(0.0, 0.0, -8.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var player := CharacterBody3D.new()
	player.position = Vector3(2.0, 1.0, -3.0)
	scene.add_child(player)
	var carrier := Carrier.new()
	scene.add_child(carrier)
	var ragdoll := PlayerRagdoll.new()
	player.add_child(ragdoll)
	ragdoll.setup(player, carrier, 1 | 64)
	ragdoll.fall(Vector3(0.0, 3.0, 0.0))
	await physics_frame
	_expect(not player.visible, "The character is hidden while the pieces fly")
	_expect(ragdoll.get_parent() == scene, "The ragdoll moves under the scene root")
	var pieces: Array[Node] = []
	for child: Node in ragdoll.get_children():
		if child is RigidBody3D:
			pieces.append(child)
	_expect(pieces.size() == 6, "Six pieces (got %d)" % pieces.size())
	var carried: bool = true
	for piece: Node in pieces:
		var body := piece as RigidBody3D
		if body.collision_mask != (1 | 64) or body.collision_layer != 0:
			_expect(false, "%s uses the handed-in mask and no layer (mask %d)" % [body.name, body.collision_mask])
		if body.linear_velocity.z > -4.0:
			carried = false
	_expect(carried, "Pieces start out moving with the carrier")
	var before: int = ragdoll.get_child_count()
	ragdoll.fall(Vector3.UP)
	await physics_frame
	_expect(ragdoll.get_child_count() == before, "A second fall while active does nothing")
	await create_timer(PlayerRagdoll.LIFETIME + 0.2).timeout
	await process_frame
	_expect(player.visible, "After LIFETIME the character is back")
	_expect(not is_instance_valid(ragdoll) or ragdoll.is_queued_for_deletion(), "The ragdoll frees itself")
	scene.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: the ragdoll spawns, inherits the carrier's motion and restores the character")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

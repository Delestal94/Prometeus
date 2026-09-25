class_name PlayerRagdoll
extends Node3D
## Lightweight physical ragdoll for the low-poly player. The shipped GLB has
## no PhysicalBone rig, so this builds articulated rigid bodies at runtime
## instead of pretending an animation is physics. It is visual-only: the
## CharacterBody remains the network authority and is restored afterwards.

const LIFETIME := 2.8
var _owner_player: CharacterBody3D
var _active := false

func setup(owner_player: CharacterBody3D) -> void:
	_owner_player = owner_player


func fall(impulse: Vector3) -> void:
	if _active or _owner_player == null:
		return
	_active = true
	_owner_player.visible = false
	# Knocked over in the back of the moving truck, the pieces start out
	# moving with it: from a standstill they were left on the road, or swept
	# by the truck's walls.
	var carried: Vector3 = Vector3.ZERO
	var vehicle: Node = get_tree().get_first_node_in_group(&"vehicle")
	if vehicle != null and vehicle.has_method(&"carries") and bool(vehicle.call(&"carries", _owner_player.global_position)):
		carried = vehicle.call(&"point_velocity", _owner_player.global_position)
	var root := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	global_transform = Transform3D(Basis.IDENTITY, _owner_player.global_position + Vector3.UP * 0.9)
	reparent(root)
	for part: Dictionary in [
		{"name":"Torso", "p":Vector3(0,0.45,0), "s":Vector3(0.34,0.55,0.2)},
		{"name":"Head", "p":Vector3(0,0.93,0), "s":Vector3(0.22,0.22,0.22)},
		{"name":"ArmL", "p":Vector3(-0.32,0.55,0), "s":Vector3(0.11,0.42,0.11)},
		{"name":"ArmR", "p":Vector3(0.32,0.55,0), "s":Vector3(0.11,0.42,0.11)},
		{"name":"LegL", "p":Vector3(-0.15,-0.1,0), "s":Vector3(0.13,0.55,0.13)},
		{"name":"LegR", "p":Vector3(0.15,-0.1,0), "s":Vector3(0.13,0.55,0.13)}]:
		_make_part(part, impulse, carried)
	await get_tree().create_timer(LIFETIME).timeout
	if _owner_player != null and is_instance_valid(_owner_player):
		_owner_player.visible = true
		_owner_player.velocity = Vector3.ZERO
	queue_free()


func _make_part(data: Dictionary, impulse: Vector3, carried: Vector3 = Vector3.ZERO) -> void:
	var body := RigidBody3D.new()
	body.name = String(data["name"])
	body.position = data["p"]
	body.mass = 1.0
	body.collision_layer = 0
	# The ground and the truck's cargo shell (vehicle.gd SHELL_LAYER), never
	# the truck itself: a ragdoll flopping in the bay mustn't shove it.
	body.collision_mask = 1 | 64
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	var size: Vector3 = data["s"]
	capsule.radius = maxf(size.x, size.z) * 0.5
	capsule.height = size.y
	mesh.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("83e2ba")
	material.roughness = 0.85
	mesh.material_override = material
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var collision := CapsuleShape3D.new()
	collision.radius = capsule.radius
	collision.height = capsule.height
	shape.shape = collision
	body.add_child(shape)
	add_child(body)
	body.linear_velocity = carried
	body.apply_central_impulse(impulse * (0.7 + randf() * 0.4) + Vector3(randf_range(-1,1), randf(), randf_range(-1,1)))
	body.apply_torque_impulse(Vector3(randf_range(-2,2), randf_range(-2,2), randf_range(-2,2)))

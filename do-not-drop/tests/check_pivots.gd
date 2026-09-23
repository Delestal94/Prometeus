extends SceneTree

const PATHS: Array[String] = [
	"res://assets/models/truck_reference_lowpoly.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_cottage.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_cabin.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_bungalow.glb",
	"res://assets/models/environment/forest/sm_env_forest_oak.glb",
	"res://assets/models/environment/forest/sm_env_forest_birch.glb",
	"res://assets/models/environment/forest/sm_env_forest_pine_tall.glb",
	"res://assets/models/environment/forest/sm_env_forest_maple.glb",
	"res://assets/models/environment/forest/sm_env_forest_dead.glb",
	"res://assets/models/environment/forest/sm_env_forest_pine_sapling.glb",
	"res://assets/models/environment/forest/sm_env_forest_bush_round.glb",
	"res://assets/models/environment/forest/sm_env_forest_fern.glb",
	"res://assets/models/environment/forest/sm_env_forest_grass_clump.glb",
	"res://assets/models/environment/forest/sm_env_forest_wildflower.glb",
	"res://assets/models/environment/forest/sm_env_forest_mushroom.glb",
	"res://assets/models/environment/forest/sm_env_forest_fallen_log.glb",
	"res://assets/models/environment/forest/sm_env_forest_rock.glb",
	"res://assets/models/environment/forest/sm_env_forest_bramble_thicket.glb",
	"res://assets/models/environment/forest/sm_env_forest_tall_fern_cluster.glb",
	"res://assets/models/environment/forest/sm_env_forest_mossy_stump.glb",
	"res://assets/models/environment/forest/sm_env_forest_mossy_rock_cluster.glb",
	"res://assets/models/environment/forest/sm_env_forest_deadfall_branch.glb",
	"res://assets/models/environment/forest/sm_env_forest_tall_grass_clump.glb",
	"res://assets/models/environment/props/sm_env_prop_street_lamp.glb",
	"res://assets/models/environment/props/sm_env_prop_bench.glb",
	"res://assets/models/environment/props/sm_env_prop_mailbox.glb",
	"res://assets/models/environment/props/sm_env_prop_traffic_cone.glb",
	"res://assets/models/environment/props/sm_env_prop_road_barrier.glb",
	"res://assets/models/vehicles/sm_vehicle_parked_hatchback.glb",
	"res://assets/models/vehicles/sm_vehicle_parked_pickup.glb",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path: String in PATHS:
		_check(path)
	quit()


func _check(path: String) -> void:
	if not ResourceLoader.exists(path):
		print("MISSING: ", path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		print("LOAD FAIL: ", path)
		return
	var inst: Node3D = packed.instantiate()
	root.add_child(inst)
	var aabb: AABB = _gather2(inst, inst)
	print("%s | min_y=%.3f max_y=%.3f height=%.3f center_xz=(%.3f,%.3f)" % [
		path.get_file(), aabb.position.y, aabb.position.y + aabb.size.y, aabb.size.y,
		aabb.position.x + aabb.size.x * 0.5, aabb.position.z + aabb.size.z * 0.5
	])
	inst.queue_free()


func _gather2(root_node: Node, node: Node) -> AABB:
	var result := AABB()
	var has_any := false
	for child in node.get_children():
		if child is VisualInstance3D:
			var local_aabb: AABB = child.get_aabb()
			var xform: Transform3D = root_node.global_transform.affine_inverse() * child.global_transform
			var world_aabb: AABB = xform * local_aabb
			if not has_any:
				result = world_aabb
				has_any = true
			else:
				result = result.merge(world_aabb)
		var child_aabb: AABB = _gather2(root_node, child)
		if child_aabb.size != Vector3.ZERO or child_aabb.position != Vector3.ZERO:
			if not has_any:
				result = child_aabb
				has_any = true
			else:
				result = result.merge(child_aabb)
	return result

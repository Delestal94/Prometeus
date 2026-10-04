extends SceneTree
## Run (through the revisor-visual agent): Godot --path do-not-drop --script res://tests/check_pivots.gd
## Prints each imported model's height, lowest point and XZ centre, to check its
## pivot sits on the ground and centred before placing it in the world.

const PATHS: Array[String] = [
	"res://assets/models/truck_reference_lowpoly.glb",
	"res://assets/models/props/cargo/sm_prop_cargo_toolbox.glb",
	"res://assets/models/props/cargo/sm_prop_cargo_thermos.glb",
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
	# N-325 narrow bridge railing: 6 m along X, origin at the centre of the base (min_y 0).
	"res://assets/models/environment/props/sm_env_prop_bridge_railing.glb",
	"res://assets/models/vehicles/sm_vehicle_parked_hatchback.glb",
	"res://assets/models/vehicles/sm_vehicle_parked_pickup.glb",
	# N-321 tow crane of the mud stretch: wheels on y=0, origin at the centre of the base, faces -Z.
	"res://assets/models/vehicles/sm_vehicle_tow_crane.glb",
	# N-319.2 depot kit: floor pieces sit at min_y 0; wall pieces too (origin on the floor at
	# the wall); ceiling pieces (lamp, tube, ducts, tray) hang from their origin.
	"res://assets/models/environment/depot/sm_env_depot_bay_lamp_bell.glb",
	"res://assets/models/environment/depot/sm_env_depot_tube_linear.glb",
	"res://assets/models/environment/depot/sm_env_depot_duct_straight.glb",
	"res://assets/models/environment/depot/sm_env_depot_duct_elbow.glb",
	"res://assets/models/environment/depot/sm_env_depot_cable_tray.glb",
	"res://assets/models/environment/depot/sm_env_depot_dispatch_desk.glb",
	"res://assets/models/environment/depot/sm_env_depot_bollard.glb",
	"res://assets/models/environment/depot/sm_env_depot_column_guard.glb",
	"res://assets/models/environment/depot/sm_env_depot_wheel_chock.glb",
	"res://assets/models/environment/depot/sm_env_depot_wheel_stop.glb",
	"res://assets/models/environment/depot/sm_env_depot_door_light.glb",
	"res://assets/models/environment/depot/sm_env_depot_roll_cage.glb",
	"res://assets/models/environment/depot/sm_env_depot_roll_cage_loaded.glb",
	"res://assets/models/environment/depot/sm_env_depot_flat_cardboard_stack.glb",
	"res://assets/models/environment/depot/sm_env_depot_pallet_wrapped.glb",
	"res://assets/models/environment/depot/sm_env_depot_sorting_table.glb",
	"res://assets/models/environment/depot/sm_env_depot_rolling_ladder.glb",
	"res://assets/models/environment/depot/sm_env_depot_stair.glb",
	"res://assets/models/environment/depot/sm_env_depot_railing_segment.glb",
	"res://assets/models/environment/depot/sm_env_depot_railing_post.glb",
	"res://assets/models/environment/depot/sm_env_depot_office_blind.glb",
	"res://assets/models/environment/depot/sm_env_depot_window_frame.glb",
	"res://assets/models/environment/depot/sm_env_depot_window_mullion.glb",
	"res://assets/models/environment/depot/sm_env_depot_cage_panel.glb",
	"res://assets/models/environment/depot/sm_env_depot_cage_window.glb",
	"res://assets/models/environment/depot/sm_env_depot_extinguisher.glb",
	"res://assets/models/environment/depot/sm_env_depot_extinguisher_cabinet.glb",
	"res://assets/models/environment/depot/sm_env_depot_electrical_panel.glb",
	"res://assets/models/environment/depot/sm_env_depot_first_aid.glb",
	"res://assets/models/environment/depot/sm_env_depot_time_clock.glb",
	"res://assets/models/environment/depot/sm_env_depot_recycle_station.glb",
	"res://assets/models/environment/depot/sm_env_depot_water_dispenser.glb",
	"res://assets/models/environment/depot/sm_env_depot_wet_floor_cone.glb",
	"res://assets/models/environment/depot/sm_env_depot_wet_floor_sign.glb",
	"res://assets/models/environment/depot/sm_env_depot_pictogram_sign.glb",
	"res://assets/models/environment/depot/sm_env_depot_fridge.glb",
	"res://assets/models/environment/depot/sm_env_depot_kitchenette.glb",
	"res://assets/models/environment/depot/sm_env_depot_scissor_lift.glb",
	"res://assets/models/environment/depot/sm_env_depot_compressor.glb",
	"res://assets/models/environment/depot/sm_env_depot_workbench_vise.glb",
	# N-319 iteration 3: floor props at min_y 0; wall boards at their mounting height
	# (origin on the floor at the wall); hard hat and vest hang from their wall peg (origin);
	# the locker door's origin is its hinge at the floor; the magnets share the fridge's origin.
	"res://assets/models/environment/depot/sm_env_depot_tire_stack.glb",
	"res://assets/models/environment/depot/sm_env_depot_tool_board.glb",
	"res://assets/models/environment/depot/sm_env_depot_paint_swatch_board.glb",
	"res://assets/models/environment/depot/sm_env_depot_desk_lamp.glb",
	"res://assets/models/environment/depot/sm_env_depot_cork_board.glb",
	"res://assets/models/environment/depot/sm_env_depot_mug.glb",
	"res://assets/models/environment/depot/sm_env_depot_service_bell.glb",
	"res://assets/models/environment/depot/sm_env_depot_locker_door_open.glb",
	"res://assets/models/environment/depot/sm_env_depot_hard_hat.glb",
	"res://assets/models/environment/depot/sm_env_depot_safety_vest.glb",
	"res://assets/models/environment/depot/sm_env_depot_fridge_magnets.glb",
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
			# Chained local transforms: global_transform can still be stale
			# right after add_child() here, which reported every rotated part
			# centred on the model's origin (a boiler "2 m under the rails").
			var xform: Transform3D = _relative(root_node as Node3D, child as Node3D)
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


func _relative(root_node: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node3D = node
	while current != null and current != root_node:
		xform = current.transform * xform
		current = current.get_parent() as Node3D
	return xform

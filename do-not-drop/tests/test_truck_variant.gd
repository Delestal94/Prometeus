extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_truck_variant.gd
## The second truck and the paint (docs/tareas-nacho.md #85-#89): the agile
## variant really drives differently, the paint recolours the body without
## touching the shared imported material, both are replicated to clients,
## and a locked truck or paint can't be picked.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var van: VehicleBody3D = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
	root.add_child(van)
	for _i: int in range(3):
		await process_frame
	var classic_speed: float = van.maximum_speed_kmh
	var classic_mass: float = van.mass
	var classic_steer: float = van.maximum_steering
	van.variant_id = &"agile"
	_expect(van.maximum_speed_kmh > classic_speed and van.mass < classic_mass and van.maximum_steering > classic_steer,
		"The agile truck is faster, lighter and twitchier (%.0f km/h, %.0f kg)" % [van.maximum_speed_kmh, van.mass])
	van.variant_id = &"no_such_truck"
	_expect(van.variant_id == &"classic" and is_equal_approx(van.maximum_speed_kmh, classic_speed), "An unknown truck falls back to the classic")

	var body_panel: MeshInstance3D = null
	var shared: Material = null
	for mesh: Node in van.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		for surface: int in range(m.mesh.get_surface_count()):
			var material: Material = m.mesh.surface_get_material(surface)
			if material != null and material.resource_name == "DT_White":
				body_panel = m
				shared = material
				break
		if body_panel != null:
			break
	_expect(body_panel != null, "The model has body panels to paint")
	var shared_color: Color = (shared as BaseMaterial3D).albedo_color
	van.paint_id = &"violet"
	var painted: Color = (body_panel.get_active_material(0) as BaseMaterial3D).albedo_color
	for surface: int in range(body_panel.mesh.get_surface_count()):
		if body_panel.mesh.surface_get_material(surface) == shared:
			painted = (body_panel.get_active_material(surface) as BaseMaterial3D).albedo_color
	_expect(painted.is_equal_approx(van.PAINTS[&"violet"]), "The body wears the violet paint")
	_expect((shared as BaseMaterial3D).albedo_color == shared_color, "The imported material itself is untouched")

	var config: SceneReplicationConfig = (van.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer).replication_config
	_expect(config.has_property(NodePath(".:variant_id")) and config.has_property(NodePath(".:paint_id")), "Truck and paint replicate to every client")

	var manager: Node = root.get_node(^"/root/UnlockManager")
	manager.set(&"storage_path", "user://test_truck_variant_profile.json")
	manager.call(&"reset_profile")
	_expect(not manager.call(&"select_truck", &"agile"), "A locked truck can't be chosen")
	_expect(not manager.call(&"select_paint", &"violet"), "A locked paint can't be chosen")
	manager.get(&"unlocked")[&"agile_van"] = true
	manager.get(&"unlocked")[&"violet_paint"] = true
	_expect(manager.call(&"select_truck", &"agile") and manager.call(&"select_paint", &"violet"), "Unlocked, both can be chosen")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_truck_variant_profile.json"))
	manager.set(&"storage_path", manager.get(&"SAVE_PATH"))
	manager.call(&"load_profile")
	van.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: the agile truck drives differently, paint recolours the body, both replicate and respect unlocks")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

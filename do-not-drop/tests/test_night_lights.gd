extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_night_lights.gd
##
## After dark (N-304, LowpolyMaterials.light_up(), night_flares.gd):
## - at night the village's street lamps and the parked cars' lamps glow and
##   carry a halo, and the houses' windows are lit; at dusk the same, dimmer;
## - by day nothing glows and there are no halos;
## - a night route never leaves its glow behind for the next, daytime one
##   (the batcher's merged meshes are cached per darkness);
## - the house that waits for its box still has its porch light on.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 4242)
	network.set(&"world_house_count", 3)

	var night: Dictionary = await _survey("soleado_noche")
	_expect(night.halos > 5, "At night the lamps have halos (%d)" % night.halos)
	_expect(night.lamp_glow > 0, "At night the street lamps' glass glows (%d surfaces)" % night.lamp_glow)
	_expect(night.window_glow > 0, "At night the houses' windows are lit (%d surfaces)" % night.window_glow)
	_expect(night.porch_on, "The waiting house's porch light is on")
	var dusk: Dictionary = await _survey("soleado_atardecer")
	_expect(dusk.halos > 0 and dusk.energy > 0.0 and dusk.energy < night.energy,
		"At dusk the same lights, dimmer (%.2f vs %.2f)" % [dusk.energy, night.energy])
	var day: Dictionary = await _survey("soleado_dia")
	_expect(day.halos == 0 and day.lamp_glow == 0 and day.window_glow == 0,
		"By day nothing glows (halos %d, lamps %d, windows %d)" % [day.halos, day.lamp_glow, day.window_glow])

	WorldMood.forced_label = ""
	LowpolyMaterials.set_night_level(0.0)
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	if _failures == 0:
		print("PASS: lamps, headlights and windows light up after dark, dimmer at dusk, never by day")
	quit(_failures)


## Builds the route (batched, as in the game) under a forced mood and counts
## what glows.
func _survey(label: String) -> Dictionary:
	WorldMood.forced_label = label
	var route: Node3D = load("res://scenes/gameplay/route/route.tscn").instantiate()
	root.add_child(route)
	await process_frame
	var result := {"halos": 0, "lamp_glow": 0, "window_glow": 0, "energy": 0.0, "porch_on": false}
	var flares := route.get_node_or_null(^"NightFlares") as MultiMeshInstance3D
	if flares != null:
		result.halos = flares.multimesh.instance_count
	for node: Node in route.find_children("*", "GeometryInstance3D", true, false):
		for material: Material in _materials(node):
			var base := material as BaseMaterial3D
			if base == null or not base.emission_enabled:
				continue
			if base.resource_name.begins_with("lamp_glass"):
				result.lamp_glow += 1
				result.energy = maxf(result.energy, base.emission_energy_multiplier)
			elif base.resource_name.begins_with("window"):
				result.window_glow += 1
	for house: Node in route.get(&"houses"):
		var marker: Node = house.get(&"waiting_marker")
		var porch: OmniLight3D = marker.get(&"porch_light") if marker != null else null
		if marker != null and bool(marker.get(&"waiting")) and porch != null and porch.visible and porch.light_energy > 0.0:
			result.porch_on = true
	route.queue_free()
	await process_frame
	return result


func _materials(node: Node) -> Array[Material]:
	var found: Array[Material] = []
	var mesh: Mesh = null
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
		for surface: int in range((node as MeshInstance3D).get_surface_override_material_count()):
			var override: Material = (node as MeshInstance3D).get_surface_override_material(surface)
			if override != null:
				found.append(override)
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		mesh = (node as MultiMeshInstance3D).multimesh.mesh
	if mesh != null:
		for surface: int in range(mesh.get_surface_count()):
			var material: Material = mesh.surface_get_material(surface)
			if material != null:
				found.append(material)
	return found


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

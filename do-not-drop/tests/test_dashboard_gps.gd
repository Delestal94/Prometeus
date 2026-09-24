extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_dashboard_gps.gd
## The GPS on the truck's dashboard (tareas de Nacho N-502): on a delivery it
## shows the distance along the road to the next house still waiting, the
## box code it ordered and an arrow toward it; once every house is done it
## points at the goal. In Endless it shows the distance driven and the record.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 4242)
	network.set(&"world_house_count", 2)
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var truck: VehicleBody3D = level.get(&"vehicle")
	var gps := truck.find_child("DashboardGps", true, false) as DashboardGps
	_expect(gps != null, "The truck's dashboard has a GPS")
	if gps != null:
		var route: Node3D = level.get_node(^"World/Route")
		var houses: Array = route.get(&"houses")
		gps.refresh()
		_expect(gps.target_house == 0, "It starts pointing at the first house")
		var expected: float = float(route.call(&"stop_road_distance", 0)) - float(route.call(&"road_distance", truck.global_position))
		_expect(expected > 100.0, "The first house is well down the road (%.0f m)" % expected)
		_expect(gps.distance_label.text == DashboardGps._metres(expected), "It shows the distance along the road (%s, expected %s)" % [gps.distance_label.text, DashboardGps._metres(expected)])
		var house: DeliveryHouse = houses[0]
		var code: String = house.assigned_label.get_slice(" ", house.assigned_label.get_slice_count(" ") - 1)
		_expect(not code.is_empty() and gps.detail_label.text == "CASA 1 · %s" % code.to_upper(), "and the house with the code of its box (%s)" % gps.detail_label.text)
		_expect(gps.arrow.visible and absf(gps.arrow.rotation.z) < PI * 0.5, "The arrow points somewhere ahead, not behind (%.0f°)" % rad_to_deg(gps.arrow.rotation.z))

		# The arrow follows the truck: turned to face the house's right side,
		# the house is to its left.
		var to_house: Vector3 = house.global_position - truck.global_position
		to_house.y = 0.0
		truck.global_basis = Basis.looking_at(to_house.rotated(Vector3.UP, -PI * 0.5), Vector3.UP)
		gps.refresh()
		_expect(gps.arrow.rotation.z < -PI * 0.3, "With the house off to the left, the arrow turns left (%.0f°)" % rad_to_deg(gps.arrow.rotation.z))

		var bus: Node = root.get_node(^"/root/EventBus")
		bus.emit_signal(&"house_delivery_recorded", 0, &"delivered_ok", &"")
		_expect(gps.target_house == 1 and gps.detail_label.text.begins_with("CASA 2"), "Delivered: it moves on to the next house (%s)" % gps.detail_label.text)
		bus.emit_signal(&"house_delivery_recorded", 1, &"missed", &"")
		_expect(gps.target_house == -1 and gps.detail_label.text == "LLEGADA", "All done: it points at the goal (%s)" % gps.detail_label.text)
	level.queue_free()
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	root.get_node(^"/root/RunManager").call(&"reset_run")
	await process_frame
	await process_frame

	var endless: Node = load("res://scenes/gameplay/level_endless.tscn").instantiate()
	root.add_child(endless)
	current_scene = endless
	await process_frame
	var endless_gps := (endless.get(&"vehicle") as Node).find_child("DashboardGps", true, false) as DashboardGps
	_expect(endless_gps != null, "The GPS is there in Endless too")
	if endless_gps != null:
		endless_gps.refresh()
		_expect(endless_gps.detail_label.text.contains("RÉCORD") and not endless_gps.arrow.visible, "In Endless: distance driven and the record, no arrow (%s)" % endless_gps.detail_label.text)
	endless.queue_free()
	await process_frame

	if _failures == 0:
		print("PASS: the dashboard GPS guides to each waiting house, then the goal, and shows the record in Endless")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

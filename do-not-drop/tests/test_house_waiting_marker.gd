extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_house_waiting_marker.gd
## Knowing from the road which house still waits, and for what (tareas de
## Nacho N-501): every house has its porch light on, a mailbox with its
## number and a yard sign with the code of the box it ordered -- the same
## one the depot's board shows. When its delivery is recorded (relayed to
## every peer) the light goes out and the sign comes down; another house's
## record doesn't touch it.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 777)
	network.set(&"world_house_count", 2)
	var route: Node3D = (load("res://scenes/gameplay/route/route.tscn") as PackedScene).instantiate()
	route.set(&"batch_dressing", false)
	root.add_child(route)
	await process_frame
	var houses: Array = route.get(&"houses")
	_expect(houses.size() == 2, "Two houses on the route")
	route.call(&"assign_packages", [[&"fragile_a", "Frágil A-3"], [&"noisy_b", "Ruidoso B-1"]])

	var first: HouseWaitingMarker = (houses[0] as DeliveryHouse).waiting_marker
	var second: HouseWaitingMarker = (houses[1] as DeliveryHouse).waiting_marker
	_expect(first != null and second != null, "Every house has its waiting marker")
	if first != null and second != null:
		_expect(first.porch_light.visible and first.sign_board.visible and first.balloon.visible, "A house waiting for its box has the porch light on, the sign up and its balloon flying")
		_expect(first.code_label.text == "A-3", "The sign shows the ordered box's shelf code, as on the board (%s)" % first.code_label.text)
		_expect(first.code_labels.size() == 2 and first.code_labels.all(func(l: Label3D) -> bool: return l.text == "A-3"), "Both boards of the V show the code")
		_expect(first.trap_labels.all(func(l: Label3D) -> bool: return l.text == "FRÁGIL"), "and its trap under it")
		_expect(first.number_labels.size() == 2 and first.number_labels.all(func(l: Label3D) -> bool: return l.text == "1") and second.number_label.text == "2", "Each mailbox carries its house number on both flanks, the sides the road sees")
		# Side-on to the road: one board reads coming from each way along it.
		# A Label3D is read from its own +Z.
		var facing_a: Vector3 = first.code_labels[0].global_basis.z
		var facing_b: Vector3 = first.code_labels[1].global_basis.z
		var along_road: Vector3 = (houses[0] as Node3D).global_basis.x
		# The boards turn 30 degrees off the front: each one faces half along
		# the road (sin 30 = 0.5), the other way from its twin.
		_expect(facing_a.dot(along_road) > 0.4 and facing_b.dot(along_road) < -0.4, "Each board of the V faces one way along the road (%.2f, %.2f)" % [facing_a.dot(along_road), facing_b.dot(along_road)])
		_expect(second.code_label.text == "B-1", "The second house shows its own code")
		# A long trap name shrinks to fit its board instead of running off it.
		second.set_order("Peso creciente C-2")
		var trap_label: Label3D = second.trap_labels[0]
		var trap_width: float = trap_label.text.length() * 0.6 * trap_label.font_size * trap_label.pixel_size
		_expect(trap_label.text == "PESO CRECIENTE" and trap_width <= HouseWaitingMarker.BOARD_SIZE.x - 0.2,
			"'PESO CRECIENTE' fits its 2.4 m board (about %.2f m)" % trap_width)
		second.set_order("Ruidoso B-1")
		# Clear of the porch: every model is measured, porch and eaves included.
		for house: DeliveryHouse in houses:
			var marker: HouseWaitingMarker = house.waiting_marker
			var front: float = marker.house_bounds.position.z
			var deepest: float = -INF
			for face: Node3D in marker.sign_board.get_children():
				for mesh: Node in face.get_children():
					if mesh is MeshInstance3D:
						var box: AABB = (house.global_transform.affine_inverse() * (mesh as MeshInstance3D).global_transform) * (mesh as MeshInstance3D).get_aabb()
						deepest = maxf(deepest, box.end.z)
			_expect(deepest < front, "House %d: the sign stands in front of the porch (reaches z %.2f, porch at %.2f)" % [house.house_index, deepest, front])
			var ball_top: float = house.to_local(marker.balloon.get_child(1).global_position).y
			_expect(ball_top > marker.house_bounds.end.y, "House %d: the balloon floats over the roof (%.1f m, roof %.1f m)" % [house.house_index, ball_top, marker.house_bounds.end.y])

		root.get_node(^"/root/EventBus").emit_signal(&"house_delivery_recorded", 0, &"delivered_ok", &"fragile_a")
		_expect(not first.porch_light.visible and not first.sign_board.visible and not first.balloon.visible, "Delivered: the light goes out and the sign and balloon come down")
		_expect(second.porch_light.visible and second.sign_board.visible, "The other house is still waiting")
		root.get_node(^"/root/EventBus").emit_signal(&"house_delivery_recorded", 1, &"missed", &"")
		_expect(not second.sign_board.visible, "Driven past counts too: nothing left to wait for")

	route.free()
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	await process_frame
	if _failures == 0:
		print("PASS: waiting houses show their light, number and ordered code, and stop once resolved")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

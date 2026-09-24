extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_house_waiting_marker.gd
## Knowing from the road which house still waits, and for what (tareas de
## Nacho N-501): every house has its porch light on, a mailbox with its
## number and a yard sign with the code of the box it ordered -- the same
## one the depot's board shows. When its delivery is recorded (relayed to
## every peer) the light goes out and the sign comes down; another house's
## record doesn't touch it. The doorbell panel (N-302) hangs on each model's
## wall beside the door with the house number, lit while the house waits and
## dark once its delivery is recorded; ringing happens where it always did.

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

		# The doorbell panel, on every model.
		for house: DeliveryHouse in houses:
			_expect_doorbell(house)
		for variant: int in range(DeliveryHouse.HOUSE_VISUALS.size()):
			var bare := DeliveryHouse.new()
			bare.visual_variant = variant
			bare.house_index = 4
			root.add_child(bare)
			_expect_doorbell(bare)
			bare.free()

		root.get_node(^"/root/EventBus").emit_signal(&"house_delivery_recorded", 0, &"delivered_ok", &"fragile_a")
		_expect(not first.porch_light.visible and not first.sign_board.visible and not first.balloon.visible, "Delivered: the light goes out and the sign and balloon come down")
		_expect(second.porch_light.visible and second.sign_board.visible, "The other house is still waiting")
		_expect(not (houses[0] as DeliveryHouse).doorbell_lit and not _doorbell_glows(houses[0]), "Delivered: the doorbell goes dark")
		_expect((houses[1] as DeliveryHouse).doorbell_lit and _doorbell_glows(houses[1]), "The other house's doorbell stays lit")
		root.get_node(^"/root/EventBus").emit_signal(&"house_delivery_recorded", 1, &"missed", &"")
		_expect(not second.sign_board.visible, "Driven past counts too: nothing left to wait for")

	route.free()
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	await process_frame
	if _failures == 0:
		print("PASS: waiting houses show their light, number and ordered code, and stop once resolved")
	quit(_failures)


## A waiting house's doorbell: the model on its own wall (measured front of
## each visual, build_doorbell.py's origin is the plate's back), on the
## knob's side, clear of the door frame and the shutters, at doorbell height
## over the porch floor (y 0.31); its window showing the house number, lit;
## and the place you ring from right in front of it.
func _expect_doorbell(house: DeliveryHouse) -> void:
	var panel: Node3D = house.doorbell_panel
	_expect(panel != null and panel.find_child("Button", true, false) != null and panel.find_child("NumberPlate", true, false) != null,
		"House %d (model %d): a doorbell panel with its button and number window" % [house.house_index, house.visual_variant])
	if panel == null:
		return
	var wall_z: float = DeliveryHouse.DOORBELL_WALL_Z[posmod(house.visual_variant, DeliveryHouse.HOUSE_VISUALS.size())]
	var half_width: float = 0.06
	_expect(is_equal_approx(panel.position.z, wall_z) and panel.position.x - half_width > 0.645 and panel.position.x + half_width < 0.785,
		"House %d (model %d): the panel sits on the wall (z %.2f, wall %.2f) between the door frame and the shutter (x %.3f)" % [house.house_index, house.visual_variant, panel.position.z, wall_z, panel.position.x])
	var button_height: float = (panel.find_child("Button", true, false) as Node3D).global_position.y - house.global_position.y - 0.31
	_expect(button_height > 1.0 and button_height < 1.4, "House %d: the bell push is at doorbell height (%.2f m over the porch)" % [house.house_index, button_height])
	_expect(house.doorbell.global_position.distance_to(panel.global_position) < 0.5, "House %d: you ring from right in front of the panel" % house.house_index)
	_expect(house.doorbell_number.text == str(house.house_index + 1), "House %d: the doorbell shows its number (%s)" % [house.house_index, house.doorbell_number.text])
	_expect(house.doorbell_number.global_basis.z.dot(-house.global_basis.z) > 0.99, "House %d: the number reads from the street side" % house.house_index)
	_expect(house.doorbell_lit and _doorbell_glows(house), "House %d: a waiting house's doorbell is lit" % house.house_index)


func _doorbell_glows(house: DeliveryHouse) -> bool:
	var button := house.doorbell_panel.find_child("Button", true, false) as MeshInstance3D
	var window := house.doorbell_panel.find_child("NumberPlate", true, false) as MeshInstance3D
	return (button.material_override as StandardMaterial3D).emission_enabled and (window.material_override as StandardMaterial3D).emission_enabled


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_seated_body.gd
## Covers item #81 of docs/especificaciones-visuales.md: a seated player used
## to go fully invisible (board_seat() set visible = false), so teammates had
## nobody to look at during the whole ride. Now BodyVisual tracks the seat's
## pose every frame instead, on every peer independently -- board_seat() is a
## targeted RPC that only ever runs on the boarding peer's own client, so
## this checks that seat_node_path (the one new replicated property) is
## enough for the body to find and follow the seat without anything else.

var _failures: int = 0


func _initialize() -> void:
	var vehicle: Node = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
	var player: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	root.add_child(vehicle)
	root.add_child(player)
	await process_frame
	await physics_frame

	var seat: Node3D = vehicle.get_node(^"CabinInterior/DriverEyePoint")
	var camera: Node = seat.get_node(^"FirstPersonCamera")

	_expect(bool(player.get(&"visible")), "Starts visible, same as any on-foot player")

	player.call(&"board_seat", camera.get_path(), seat.get_path())
	# Two frames: the first process_frame signal after board_seat() still
	# observes BodyVisual's pre-seating transform (the node's own _process()
	# for that tick hasn't necessarily run before the signal fires) --
	# whatever the exact ordering, only the second frame onward is reliably
	# caught up, so that's what every other player's client would actually see.
	await process_frame
	await process_frame

	_expect(bool(player.get(&"visible")), "Still visible after boarding -- no more disappearing")
	# Node3D, not MeshInstance3D: BodyVisual is now the rigged character
	# scene's root (2026-09-22), a plain Node3D holding a Skeleton3D/mesh,
	# not a bare mesh itself.
	var body: Node3D = player.get_node(^"BodyVisual")
	var offset: Vector3 = body.global_position - seat.global_position
	_expect(offset.length() < 1.0 and offset.y < -0.2,
		"BodyVisual sits at the seat, lower than the eye point (got offset %s)" % offset)

	# Move the seat (as if the van itself drove off) and confirm the body
	# keeps up next frame -- this is what makes it "ride along" instead of
	# being posed once and left behind.
	var before: Vector3 = body.global_position
	vehicle.global_position += Vector3(5.0, 0.0, 0.0)
	await process_frame
	await process_frame
	_expect(body.global_position.distance_to(before) > 4.0,
		"BodyVisual follows the seat every frame, not just once at boarding")

	player.free()
	vehicle.free()
	if _failures == 0:
		print("PASS: a seated player's body tracks their seat instead of vanishing")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_play_area.gd
##
## The player stays where the world is built (scripts/gameplay/play_area.gd,
## playtest 2026-09-28): the depot and its yard before the run, a leash
## around the truck on the road, and a notice when they're stopped.

const PlayArea = preload("res://scripts/gameplay/play_area.gd")

var _failures: int = 0
var _notices: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	root.get_node("EventBus").depot_notice.connect(func(text: String) -> void: _notices.append(text))
	var area: PlayArea = level.get_node("PlayArea")
	var depot: Node3D = level.depot
	var inside: Vector3 = depot.to_global(Vector3(0.0, 0.0, 12.0))
	_expect(area.keep_inside(inside).is_equal_approx(inside), "Inside the depot nothing moves")
	var yard: Vector3 = depot.to_global(Vector3(3.0, 0.0, -PlayArea.YARD_APRON + 1.0))
	_expect(area.keep_inside(yard).is_equal_approx(yard), "The yard in front of the door is walkable")
	var far: Vector3 = depot.to_global(Vector3(0.0, 0.0, -60.0))
	var kept: Vector3 = depot.to_local(area.keep_inside(far))
	_expect(is_equal_approx(kept.z, -PlayArea.YARD_APRON), "Walking off past the yard stops at its edge")
	var player: CharacterBody3D = level.local_player
	player.global_position = far
	for _i: int in 3:
		await physics_frame
	_expect(depot.to_local(player.global_position).z >= -PlayArea.YARD_APRON - 0.01, "The local player is kept in the yard")
	_expect(_notices.has("Quedate en el depósito"), "...and told why (got %s)" % str(_notices))
	# On the road: a leash around the truck.
	var vehicle: Node3D = level.vehicle
	vehicle.call(&"set_door_open", &"cab_left", true)
	level.get_node("World/Vehicle/CabinInterior/DriverEyePoint/InteractionArea").interact(player)
	player.call(&"leave_seat")
	_expect(bool(root.get_node("RunManager").is_running), "The run is under way")
	var road_far: Vector3 = vehicle.global_position + Vector3(80.0, 0.0, 0.0)
	var leashed: Vector3 = area.keep_inside(road_far)
	var reach := Vector2(leashed.x - vehicle.global_position.x, leashed.z - vehicle.global_position.z).length()
	_expect(is_equal_approx(reach, PlayArea.LEASH_RADIUS), "On the road, a player on foot stays within the leash (%.1f m)" % reach)
	var near: Vector3 = vehicle.global_position + Vector3(10.0, 0.0, 0.0)
	_expect(area.keep_inside(near).is_equal_approx(near), "...and walks freely around the truck")
	level.free()
	if _failures == 0:
		print("PASS: the player keeps to the depot and yard, then to a leash around the truck")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

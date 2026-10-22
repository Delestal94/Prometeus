extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_multi_vehicle.gd
##
## With two vehicles in the "vehicle" group (the company's fleet, expansion D-0302.2.b.4,
## scripts/gameplay/vehicle/vehicle_pick.gd) the owner of a player or of a box is aboard the vehicle that carries
## its point, not the group's first:
## - VehiclePick.pick(): the vehicle that carries the point; the current one is kept while it still carries it
##   (two overlapping bays do not flip); with none carrying, the current one, else the first; a single vehicle
##   (or none) is answered as before.
## - A Player (solo, authority) standing in the second fake vehicle reports it as its vehicle and publishes
##   net_in_vehicle with the position in its space; walking back to the first moves it over.
## - A DeliveryPackage in the second one does the same.

const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")

var _failures: int = 0


class Bay extends Node3D:
	var half: Vector3 = Vector3(2.0, 2.0, 3.0)

	func carries(world_point: Vector3, margin: float = 0.0) -> bool:
		var local: Vector3 = to_local(world_point).abs()
		return local.x <= half.x + margin and local.y <= half.y + margin and local.z <= half.z + margin


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var first := _bay(Vector3(0, 0, 0))
	var second := _bay(Vector3(20, 0, 0))
	_check_pick(first, second)
	await _check_player(first, second)
	await _check_package(first, second)
	if _failures == 0:
		print("PASS: a rider and a box are aboard the vehicle that carries them when there are two")
	quit(_failures)


func _bay(at: Vector3) -> Bay:
	var bay := Bay.new()
	bay.add_to_group(&"vehicle")
	root.add_child(bay)
	bay.global_position = at
	return bay


func _check_pick(first: Bay, second: Bay) -> void:
	_expect(VehiclePick.pick(self, null, Vector3(20, 0, 0)) == second, "the point in the second bay picks the second")
	_expect(VehiclePick.pick(self, second, Vector3(0, 0, 0)) == first, "a point left behind moves to the first")
	_expect(VehiclePick.pick(self, first, Vector3(20, 0, 0)) == second, "the current one is dropped once it no longer carries")
	_expect(VehiclePick.pick(self, second, Vector3(100, 0, 0)) == second, "nothing carries: the current one stays")
	_expect(VehiclePick.pick(self, null, Vector3(100, 0, 0)) == first, "nothing carries and no current: the first")
	second.global_position = Vector3(1, 0, 0)
	_expect(VehiclePick.pick(self, second, Vector3(1, 0, 0)) == second, "overlapping bays keep the current one")
	second.global_position = Vector3(20, 0, 0)


func _check_player(first: Bay, second: Bay) -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	await physics_frame
	player.global_position = Vector3(21, 0.5, 0)
	_expect(player.call(&"_find_vehicle") == second, "a player in the second bay is aboard the second")
	player.call(&"_publish_net_state")
	_expect(player.net_in_vehicle and player.net_position.distance_to(Vector3(1, 0.5, 0)) < 0.01,
		"it publishes its position in the second bay's space (%s)" % player.net_position)
	player.global_position = Vector3(0.5, 0.5, 0)
	_expect(player.call(&"_find_vehicle") == first, "walking back to the first moves it over")
	player.queue_free()


func _check_package(first: Bay, second: Bay) -> void:
	var box: Node3D = PACKAGE_SCENE.instantiate()
	root.add_child(box)
	await physics_frame
	box.global_position = Vector3(20.5, 0.5, 0)
	_expect(box.call(&"_find_vehicle") == second, "a box in the second bay is aboard the second")
	box.global_position = Vector3(0.5, 0.5, 0)
	_expect(box.call(&"_find_vehicle") == first, "a box in the first bay is aboard the first")
	box.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

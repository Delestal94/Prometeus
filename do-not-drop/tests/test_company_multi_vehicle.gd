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
## - A DeliveryPackage in the second one does the same and, riding still in it while the second one
##   drives on (the box carried along), its NetRestThrottle rests: its pose in that vehicle's space
##   doesn't change (D-2002.4: in the first one's space it would move every tick and send at 30/s).
##
## And every other peer's copy goes on that same vehicle (D-0302.2.b.4.b):
## - VehiclePick.index_of() / at() / told(): the group's vehicles in tree order, an index for each; a copy takes the
##   one named, keeps its current one (else the first) while none is named or one it lacks.
## - player.tscn and package.tscn replicate net_vehicle with the pose (REPLICATION_MODE_ALWAYS, in the spawn
##   state for a late joiner); the owner publishes the index of the vehicle it rides (1 in the second, 0 in the
##   first, -1 on foot or loose).
## - What the pose packet carries (the synchronizer's ALWAYS properties, copied as SceneMultiplayer sets them,
##   then its `synchronized`) puts a copy owned by another peer (a Player_2, a box of peer 2) on the second
##   vehicle wherever this peer has it, and on the first once the owner names the first.
## - The host's box: a carrier's pose in the second's space (submit_carry_transform's `vehicle` index) lands on
##   the second even when the box's own vehicle is still the first and it stands outside both (a carrier backing
##   into the second van), stays there on the next tick, and a drop there (request_drop's index) too.
## - The carrier's own client draws its predicted hands in its own vehicle's space (predict_carry's `vehicle`),
##   while the host's copy names none yet.
## - One vehicle: nothing changes; a copy rides the only one whatever index it is told.

const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const RIDE = preload("res://scripts/gameplay/player/player_ride.gd")
const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
## Where this peer's copy of the second vehicle is when the copies are checked: not where the owner had it.
const ELSEWHERE := Vector3(20, 0, 8)

var _failures: int = 0


class Bay extends Node3D:
	var half: Vector3 = Vector3(2.0, 2.0, 3.0)

	func carries(world_point: Vector3, margin: float = 0.0) -> bool:
		var local: Vector3 = to_local(world_point).abs()
		return local.x <= half.x + margin and local.y <= half.y + margin and local.z <= half.z + margin

	func needs_sweep(_body: RigidBody3D, _margin: float = 0.0) -> bool:
		return false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var first := _bay(Vector3(0, 0, 0))
	var second := _bay(Vector3(20, 0, 0))
	_check_pick(first, second)
	_check_index(first, second)
	_check_replicated()
	await _check_player(first, second)
	await _check_package(first, second)
	await _check_single(first, second)
	if _failures == 0:
		print("PASS: a rider and a box are aboard the vehicle that carries them when there are two,"
			+ " and every other peer's copy goes on that one")
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
	_expect(VehiclePick.pick(self, first, Vector3(20, 0, 0)) == second,
		"the current one is dropped once it no longer carries")
	_expect(VehiclePick.pick(self, second, Vector3(100, 0, 0)) == second, "nothing carries: the current one stays")
	_expect(VehiclePick.pick(self, null, Vector3(100, 0, 0)) == first, "nothing carries and no current: the first")
	second.global_position = Vector3(1, 0, 0)
	_expect(VehiclePick.pick(self, second, Vector3(1, 0, 0)) == second, "overlapping bays keep the current one")
	second.global_position = Vector3(20, 0, 0)


func _check_index(first: Bay, second: Bay) -> void:
	_expect(VehiclePick.index_of(self, first) == 0 and VehiclePick.index_of(self, second) == 1,
		"the vehicles are indexed in tree order (got %d, %d)"
		% [VehiclePick.index_of(self, first), VehiclePick.index_of(self, second)])
	_expect(VehiclePick.index_of(self, null) == -1, "no vehicle is index -1")
	_expect(VehiclePick.at(self, 0) == first and VehiclePick.at(self, 1) == second, "at() finds each by its index")
	_expect(VehiclePick.at(self, -1) == null and VehiclePick.at(self, 2) == null,
		"at() finds none for -1 or an index this peer has no vehicle for")
	_expect(VehiclePick.told(self, first, 1) == second, "a copy told the second goes on the second")
	_expect(VehiclePick.told(self, second, -1) == second and VehiclePick.told(self, second, 7) == second,
		"told none, or one it lacks, a copy keeps its current vehicle")
	_expect(VehiclePick.told(self, null, -1) == first, "told none with no current one: the first")


## net_vehicle travels in the pose packet of both scenes, and in the spawn state a late joiner gets.
func _check_replicated() -> void:
	for scene: PackedScene in [PLAYER_SCENE, PACKAGE_SCENE]:
		var node: Node = scene.instantiate()
		var config: SceneReplicationConfig = (node.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer) \
			.replication_config
		var path := NodePath(".:net_vehicle")
		_expect(config.has_property(path)
			and config.property_get_replication_mode(path) == SceneReplicationConfig.REPLICATION_MODE_ALWAYS
			and config.property_get_spawn(path),
			"%s replicates net_vehicle with every pose and in its spawn state" % scene.resource_path)
		node.free()


func _check_player(first: Bay, second: Bay) -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	await physics_frame
	player.global_position = Vector3(21, 0.5, 0)
	_expect(player.call(&"_find_vehicle") == second, "a player in the second bay is aboard the second")
	RIDE.publish_net_state(player)
	_expect(player.net_in_vehicle and player.net_position.distance_to(Vector3(1, 0.5, 0)) < 0.01,
		"it publishes its position in the second bay's space (%s)" % player.net_position)
	_expect(player.net_vehicle == 1, "it names the second vehicle with the pose (got %d)" % player.net_vehicle)
	await _check_remote_player(first, second, player)
	player.global_position = Vector3(0.5, 0.5, 0)
	_expect(player.call(&"_find_vehicle") == first, "walking back to the first moves it over")
	RIDE.publish_net_state(player)
	_expect(player.net_vehicle == 0, "in the first it names the first (got %d)" % player.net_vehicle)
	player.global_position = Vector3(10, 0.5, 0)
	RIDE.publish_net_state(player)
	_expect(not player.net_in_vehicle and player.net_vehicle == -1,
		"on foot between them it names none (got %d)" % player.net_vehicle)
	player.queue_free()


## Another peer's copy of the rider the owner just published in the second bay.
func _check_remote_player(first: Bay, second: Bay, player: Player) -> void:
	var copy: Player = PLAYER_SCENE.instantiate()
	copy.name = "Player_2"
	root.add_child(copy)
	await physics_frame
	_expect(not copy.is_local(), "Player_2 is another peer's player here")
	_send_pose(player, copy)
	var sent: Vector3 = copy.net_position
	_move(second, ELSEWHERE)
	await physics_frame
	var expected: Vector3 = second.global_transform * sent
	_expect(copy.call(&"_find_vehicle") == second and copy.global_position.distance_to(expected) < 0.01,
		"the copy of a rider in the second goes on this peer's second vehicle (off by %.2f m)"
		% copy.global_position.distance_to(expected))
	copy.net_vehicle = 0
	await physics_frame
	expected = first.global_transform * sent
	_expect(copy.call(&"_find_vehicle") == first and copy.global_position.distance_to(expected) < 0.01,
		"named the first, the same pose goes on the first (off by %.2f m)" % copy.global_position.distance_to(expected))
	_move(second, Vector3(20, 0, 0))
	copy.queue_free()


func _check_package(first: Bay, second: Bay) -> void:
	var box: Node3D = PACKAGE_SCENE.instantiate()
	root.add_child(box)
	await physics_frame
	box.global_position = Vector3(20.5, 0.5, 0)
	_expect(box.call(&"_find_vehicle") == second, "a box in the second bay is aboard the second")
	box.global_position = Vector3(0.5, 0.5, 0)
	_expect(box.call(&"_find_vehicle") == first, "a box in the first bay is aboard the first")
	await _check_box_rests(box as RigidBody3D, second)
	await _check_remote_box(second, box as RigidBody3D)
	await _check_carry(first, second, box as RigidBody3D)
	await _check_predicted(first, second)
	box.queue_free()


## The box riding in `bay` while it drives on, carried along each tick as the vehicle carries it.
func _check_box_rests(box: RigidBody3D, bay: Bay) -> void:
	box.freeze = true
	box.global_position = bay.global_position + Vector3(0.5, 0.5, 0)
	var throttle := box.get_node(^"NetRestThrottle") as NetRestThrottle
	var ride: Vector3 = box.global_position - bay.global_position
	for _tick: int in range(90):
		bay.global_position += Vector3(0, 0, 0.2)
		box.global_position = bay.global_position + ride
		await physics_frame
	_expect(box.get(&"net_in_vehicle") == true and box.call(&"_find_vehicle") == bay,
		"a box riding in the second bay publishes its pose in that bay's space")
	_expect(int(box.get(&"net_vehicle")) == 1, "...naming the second (got %d)" % int(box.get(&"net_vehicle")))
	_expect(throttle.is_resting(), "riding still in the second bay while it drives, the box's sends rest")
	bay.global_position = Vector3(20, 0, 0)


## A client's copy of the host's box riding in the second bay.
func _check_remote_box(second: Bay, box: RigidBody3D) -> void:
	box.global_position = Vector3(20.5, 0.5, 0.3)
	box.call(&"_publish_net_state")
	var copy: Node3D = PACKAGE_SCENE.instantiate()
	copy.set_multiplayer_authority(2)
	root.add_child(copy)
	await process_frame
	_send_pose(box, copy)
	var sent: Transform3D = copy.get(&"net_transform")
	# A client's copy of a vehicle is frozen and not interpolated (the player's check above had the host's case).
	second.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_move(second, ELSEWHERE)
	await process_frame
	var expected: Vector3 = second.global_transform * sent.origin
	_expect(copy.call(&"_find_vehicle") == second and copy.global_position.distance_to(expected) < 0.01,
		"a client's copy of a box in the second goes on its second vehicle (off by %.2f m)"
		% copy.global_position.distance_to(expected))
	second.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	_move(second, Vector3(20, 0, 0))
	copy.queue_free()


## The host's box, its own vehicle still the first, carried by someone whose hands are in the second's space.
func _check_carry(first: Bay, second: Bay, box: RigidBody3D) -> void:
	box.freeze = true
	box.global_position = Vector3(0.5, 0.5, 0)
	_expect(box.call(&"_find_vehicle") == first, "the box starts in the first")
	box.global_position = Vector3(10, 0.5, 0)
	box.call(&"set_held", true)
	# Just outside the second's bay, within the carrier's margin (player.RIDE_MARGIN): aboard for the carrier.
	var carry := Transform3D(Basis(), Vector3(-2.3, 0.5, 0.0))
	box.call(&"submit_carry_transform", carry, true, Transform3D(), VehiclePick.index_of(self, second))
	var expected: Vector3 = second.global_transform * carry.origin
	_expect(box.global_position.distance_to(expected) < 0.01,
		"the host puts the carried box in the space of the vehicle the carrier names (off by %.2f m)"
		% box.global_position.distance_to(expected))
	await physics_frame
	_expect(box.global_position.distance_to(expected) < 0.01 and box.call(&"_find_vehicle") == second,
		"...and keeps it there on the next tick (off by %.2f m)" % box.global_position.distance_to(expected))
	var set_down := Transform3D(Basis(), Vector3(0.5, 0.5, 1.0))
	box.call(&"request_drop", set_down, true, VehiclePick.index_of(self, second))
	expected = second.global_transform * set_down.origin
	_expect(box.global_position.distance_to(expected) < 0.01,
		"set down in the second, it lands in the second (off by %.2f m)" % box.global_position.distance_to(expected))
	box.freeze = true


## The carrier's own client: the host's copy names no vehicle yet, the hands are in the carrier's second.
func _check_predicted(first: Bay, second: Bay) -> void:
	var copy: Node3D = PACKAGE_SCENE.instantiate()
	copy.set_multiplayer_authority(2)
	root.add_child(copy)
	await process_frame
	copy.set(&"net_vehicle", -1)
	copy.set(&"net_transform", Transform3D(Basis(), Vector3(10, 0.5, 0)))
	_expect(copy.call(&"_find_vehicle") == first, "the host's copy names none: here the box's vehicle is the first")
	var hands := Transform3D(Basis(), Vector3(-1.5, 1.0, 0.5))
	copy.call(&"predict_carry", hands, true, second)
	copy.call(&"_process", 0.0)
	var expected: Vector3 = second.get_global_transform_interpolated() * hands.origin
	_expect(copy.global_position.distance_to(expected) < 0.01,
		"the carrier's client draws its hands on its own vehicle, the second, not the box's (off by %.2f m)"
		% copy.global_position.distance_to(expected))
	copy.queue_free()


## One vehicle: as before D-0302.2.b.4.b.
func _check_single(first: Bay, second: Bay) -> void:
	second.remove_from_group(&"vehicle")
	var box: Node3D = PACKAGE_SCENE.instantiate()
	root.add_child(box)
	await physics_frame
	(box as RigidBody3D).freeze = true
	box.global_position = Vector3(0.5, 0.5, 0)
	box.call(&"_publish_net_state")
	_expect(int(box.get(&"net_vehicle")) == 0, "riding the only vehicle, a box names it 0")
	box.queue_free()
	var copy: Player = PLAYER_SCENE.instantiate()
	copy.name = "Player_3"
	root.add_child(copy)
	await physics_frame
	copy.net_in_vehicle = true
	copy.net_vehicle = 3
	copy.net_position = Vector3(0.5, 0.5, 1.0)
	await physics_frame
	_expect(copy.call(&"_find_vehicle") == first
		and copy.global_position.distance_to(first.global_transform * copy.net_position) < 0.01,
		"with one vehicle a copy rides it whatever index it is told")
	copy.queue_free()
	second.add_to_group(&"vehicle")
	await physics_frame


## What a synchronized pose packet does on the copy: every property `owner_node`'s synchronizer sends each tick
## (REPLICATION_MODE_ALWAYS) set on `copy`, then its `synchronized` (the copy's pose buffer takes it).
func _send_pose(owner_node: Node, copy: Node) -> void:
	var sync := owner_node.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var config: SceneReplicationConfig = sync.replication_config
	for path: NodePath in config.get_properties():
		if config.property_get_replication_mode(path) != SceneReplicationConfig.REPLICATION_MODE_ALWAYS:
			continue
		var holder := NodePath(path.get_concatenated_names())
		var property := NodePath(path.get_concatenated_subnames())
		copy.get_node(holder).set_indexed(property, owner_node.get_node(holder).get_indexed(property))
	(copy.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer).synchronized.emit()


## This peer's copy of a vehicle moved by the network (no interpolation from where it was).
func _move(bay: Bay, to: Vector3) -> void:
	bay.global_position = to
	bay.reset_physics_interpolation()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

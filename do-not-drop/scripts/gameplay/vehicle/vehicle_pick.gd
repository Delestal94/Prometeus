class_name VehiclePick
extends RefCounted
## Which vehicle of the "vehicle" group a rider or a box is aboard (expansion D-0302.2.b.4).
##
## Delivery and Endless have one truck, and every caller took the group's first node. The company's world has
## a fleet (CompanyFleet): with two vehicles out the second one carried nobody. The owner of a player or a box
## picks the vehicle that carries its point; the group's first is only the answer when there is nothing better.
## The vehicle's `carries` is asked by name (vehicle.gd has no class name; test fakes offer it too).
##
## Everyone else's copy (D-0302.2.b.4.b) is told which one by the owner: its index in listed() (index_of()),
## replicated with the pose (Player.net_vehicle, DeliveryPackage.net_vehicle) and with a carried box's pose
## (submit_carry_transform, request_drop), and found here with at() / told(). listed() is the group in tree
## order, the same on every peer: the fleet is built under World/Vehicles in the fleet's order everywhere
## (CompanyFleet.build()).

const GROUP: StringName = &"vehicle"

## listed(), kept for the rest of the process frame while the group's size holds: the copies ask it every frame.
static var _listed: Array = []
static var _listed_frame: int = -1
static var _listed_count: int = -1


## The vehicle to use for a body at `point`: `current` if it is still valid and carries the point (so a rider
## standing where two cargo bays overlap does not flip between them), else the first vehicle that does, else
## `current` if valid, else the group's first vehicle with `carries`. `margin` is the give once aboard.
static func pick(tree: SceneTree, current: Node3D, point: Vector3, margin: float = 0.0) -> Node3D:
	if tree == null:
		return null
	var keep: Node3D = current if is_instance_valid(current) else null
	if keep != null and (tree.get_node_count_in_group(GROUP) < 2 or _carries(keep, point, margin)):
		return keep
	var fallback: Node3D = keep
	for node: Node in tree.get_nodes_in_group(GROUP):
		var vehicle := node as Node3D
		if vehicle == null or not vehicle.has_method(&"carries"):
			continue
		if _carries(vehicle, point, margin):
			return vehicle
		if fallback == null:
			fallback = vehicle
	return fallback


## The group's vehicles (the nodes with `carries`) in tree order: what an index means on the wire.
static func listed(tree: SceneTree) -> Array:
	var count: int = tree.get_node_count_in_group(GROUP)
	var frame: int = Engine.get_process_frames()
	if frame != _listed_frame or count != _listed_count:
		_listed.clear()
		for node: Node in tree.get_nodes_in_group(GROUP):
			if node is Node3D and node.has_method(&"carries"):
				_listed.append(node)
		_listed_frame = frame
		_listed_count = count
	return _listed


## Where `vehicle` is in listed(), what its owner replicates; -1 for none (or one not in the group).
static func index_of(tree: SceneTree, vehicle: Node3D) -> int:
	if tree == null or not is_instance_valid(vehicle):
		return -1
	return listed(tree).find(vehicle)


## The vehicle at `index` of listed() on this peer; null for -1 or one this peer doesn't have.
static func at(tree: SceneTree, index: int) -> Node3D:
	if tree == null or index < 0:
		return null
	var all: Array = listed(tree)
	if index >= all.size() or not is_instance_valid(all[index]):
		return null
	return all[index] as Node3D


## Someone else's copy of a rider or a box: the vehicle its owner says (`index`, at()); while it says none (on
## foot, loose on the ground) or names one this peer lacks, `current` if still valid, else the first listed.
static func told(tree: SceneTree, current: Node3D, index: int) -> Node3D:
	var named: Node3D = at(tree, index)
	if named != null:
		return named
	if is_instance_valid(current):
		return current
	return at(tree, 0)


static func _carries(vehicle: Node3D, point: Vector3, margin: float) -> bool:
	return bool(vehicle.call(&"carries", point, margin))

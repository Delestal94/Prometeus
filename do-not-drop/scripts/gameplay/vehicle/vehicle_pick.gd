class_name VehiclePick
extends RefCounted
## Which vehicle of the "vehicle" group a rider or a box is aboard (expansion D-0302.2.b.4).
##
## Delivery and Endless have one truck, and every caller took the group's first node. The company's world has
## a fleet (CompanyFleet): with two vehicles out the second one carried nobody. The owner of a player or a box
## picks the vehicle that carries its point; the group's first is only the answer when there is nothing better.
## The vehicle's `carries` is asked by name (vehicle.gd has no class name; test fakes offer it too).

const GROUP: StringName = &"vehicle"


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


static func _carries(vehicle: Node3D, point: Vector3, margin: float) -> bool:
	return bool(vehicle.call(&"carries", point, margin))

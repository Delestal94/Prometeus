class_name DispatchRack
extends RefCounted
## A fleet vehicle's rack as the dispatch board uses it (expansion D-0717.b, D-0302.2.b.3).
##
## "Load" on the board puts each box on a free PackageMountPoint of the vehicle, the same store() a player's hands
## use (row 18 of red-autoridad.md), so the van that leaves really carries them. Host only (S3): a package is the
## host's, and every peer sees it on the rack through its synchronizer (is_loaded, current_mount_path, its pose in
## the vehicle's space), no event of its own. A box stays there until a hand takes it. Static, over the nodes it
## is given: CompanyDispatch calls it.

## The group of a PackageMountPoint's InteractionArea (vehicle.tscn).
const MOUNT_GROUP: StringName = &"package_mount"


## The free mounts of `body`, in tree order. Empty with no body, or outside the tree.
static func free_mounts(body: Node3D) -> Array[Node]:
	var mounts: Array[Node] = []
	if body == null or not body.is_inside_tree():
		return mounts
	for mount: Node in body.get_tree().get_nodes_in_group(MOUNT_GROUP):
		if body.is_ancestor_of(mount) and mount.has_method(&"store") and mount.get(&"occupied_by") == null:
			mounts.append(mount)
	return mounts


## The DeliveryPackage of `box_id` under `packages` (World/Packages), or null.
static func package_of(packages: Node, box_id: StringName) -> DeliveryPackage:
	if packages == null or not is_instance_valid(packages):
		return null
	for child: Node in packages.get_children():
		var package := child as DeliveryPackage
		if package != null and package.package_id == box_id:
			return package
	return null


## Host: puts the boxes on `body`'s free mounts, in order, and returns the ids that went: one in hands, with no
## package or past the last free mount does not.
static func store(body: Node3D, packages: Node, box_ids: Array[StringName]) -> Array[StringName]:
	var placed: Array[StringName] = []
	var mounts: Array[Node] = free_mounts(body)
	for box_id: StringName in box_ids:
		var package: DeliveryPackage = package_of(packages, box_id)
		if mounts.is_empty() or package == null or package.is_held:
			continue
		mounts.pop_front().call(&"store", package)
		placed.append(box_id)
	return placed


## `vehicle` as the board reads it for `body`: the same definition, or a copy with cargo_slots cut to the free
## mounts when `body`'s rack has less room (a box that came back from a trip takes one up). Null for none.
static func with_free_slots(vehicle: VehicleDefinition, body: Node3D) -> VehicleDefinition:
	if vehicle == null or body == null:
		return vehicle
	var room: int = free_mounts(body).size()
	if room >= vehicle.cargo_slots:
		return vehicle
	var copy := vehicle.duplicate() as VehicleDefinition
	copy.cargo_slots = room
	return copy

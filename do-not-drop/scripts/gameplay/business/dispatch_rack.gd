class_name DispatchRack
extends RefCounted
## A fleet vehicle's rack as the dispatch board uses it (expansion D-0717.b, D-0302.2.b.3).
##
## "Load" on the board puts each box on a free PackageMountPoint of the vehicle, the same store() a player's hands
## use (row 18 of red-autoridad.md), so the van that leaves really carries them. Host only (S3): a package is the
## host's, and every peer sees it on the rack through its synchronizer (is_loaded, current_mount_path, its pose in
## the vehicle's space), no event of its own. Static, over the nodes it is given: CompanyDispatch and CompanyFleet
## call it.
##
## What rides is what is in the bay (rides()), not what is_loaded says: is_loaded and a mount's occupied_by only go
## when a hand takes the box, and a box on a rack that drives is loose, so it can fall out and they never notice. A
## mount holding a box that isn't in the bay counts as free (free_mounts()); the host lets it go (release_strays()).

## The group of a PackageMountPoint's InteractionArea (vehicle.tscn).
const MOUNT_GROUP: StringName = &"package_mount"
## The group of every DeliveryPackage (package.tscn).
const CARGO_GROUP: StringName = &"cargo"
## How far past the bay's walls a box still rides (m): one against the open rear doors doesn't flicker in and out.
const BAY_MARGIN_M: float = 0.3


## The free mounts of `body`, in tree order: empty, or naming a box that left its bay. Empty with no body, or outside
## the tree.
static func free_mounts(body: Node3D) -> Array[Node]:
	var found: Array[Node] = []
	for mount: Node in _mounts(body):
		var held: Variant = mount.get(&"occupied_by")
		if not is_instance_valid(held) or _is_stray(body, held):
			found.append(mount)
	return found


## Whether `package` really rides on `body`: it is in its bay, on the rack or not (vehicle.gd carries()).
static func rides(body: Node3D, package: DeliveryPackage) -> bool:
	return body != null and package != null and bool(body.call(&"carries", package.global_position, BAY_MARGIN_M))


## Host: the boxes `body`'s mounts name that left its bay let those mounts go (no longer loaded, on every peer through
## their synchronizers), and stay where they are.
static func release_strays(body: Node3D) -> void:
	for mount: Node in _mounts(body):
		var held: Variant = mount.get(&"occupied_by")
		if is_instance_valid(held) and _is_stray(body, held):
			(held as DeliveryPackage).release_mount()


## Host: `move` puts `body` somewhere else in one go (a tow, a recovery: vehicle.gd park()) and what rides in its bay
## goes with it, each box where it was in the bay and still, on the rack or on the floor (D-0307.1.f). One it lost on
## the way stays where it fell, off its mount; one in hands goes with whoever holds it.
static func haul(body: Node3D, move: Callable) -> void:
	release_strays(body)
	var riding: Array[Array] = []
	if body.is_inside_tree():
		var to_body: Transform3D = body.global_transform.affine_inverse()
		for node: Node in body.get_tree().get_nodes_in_group(CARGO_GROUP):
			var package := node as DeliveryPackage
			if package != null and package.multiplayer == body.multiplayer and not package.is_held \
					and rides(body, package):
				riding.append([package, to_body * package.global_transform])
	move.call()
	for entry: Array in riding:
		var package: DeliveryPackage = entry[0]
		package.global_transform = body.global_transform * (entry[1] as Transform3D)
		package.linear_velocity = Vector3.ZERO
		package.angular_velocity = Vector3.ZERO
		package.reset_physics_interpolation()


## The DeliveryPackage of `box_id` under `packages` (World/Packages), or null.
static func package_of(packages: Node, box_id: StringName) -> DeliveryPackage:
	if packages == null or not is_instance_valid(packages):
		return null
	for child: Node in packages.get_children():
		var package := child as DeliveryPackage
		if package != null and package.package_id == box_id:
			return package
	return null


## Host: puts the boxes on `body`'s free mounts, in order, and returns the ids that went: one in hands, already on a
## rack, with no package or past the last free mount does not.
static func store(body: Node3D, packages: Node, box_ids: Array[StringName]) -> Array[StringName]:
	var placed: Array[StringName] = []
	release_strays(body)
	var mounts: Array[Node] = free_mounts(body)
	for box_id: StringName in box_ids:
		var package: DeliveryPackage = package_of(packages, box_id)
		if mounts.is_empty() or package == null or package.is_held or package.is_loaded:
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


## The mounts of `body`, in tree order. Empty with no body, or outside the tree.
static func _mounts(body: Node3D) -> Array[Node]:
	var mounts: Array[Node] = []
	if body == null or not body.is_inside_tree():
		return mounts
	for mount: Node in body.get_tree().get_nodes_in_group(MOUNT_GROUP):
		if body.is_ancestor_of(mount) and mount.has_method(&"store"):
			mounts.append(mount)
	return mounts


## Whether `held`, what a mount of `body` names, is a box that is not in its bay.
static func _is_stray(body: Node3D, held: Variant) -> bool:
	return held is DeliveryPackage and not rides(body, held as DeliveryPackage)

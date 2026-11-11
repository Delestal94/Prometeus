class_name ForkliftBody
extends RefCounted
## The shed forklift's own volume on its driver's body (expansion D-0606.c4, "Modo Empresa").
##
## Driving the forklift is walking (ForkliftView): the body that moves is the driver's own Player, a CharacterBody3D
## whose capsule used to be all that collided, so the forks went through shelves and walls and the counterweight
## through whatever stood behind. While somebody drives, ForkliftView adds these boxes to that body on every peer and
## takes them off when it gets off (attach() / detach()), so it bumps as a forklift would:
## - REAR: the chassis and the counterweight behind the seat;
## - MAST: the uprights and the backrest in front of the seat, up to the top of the mast;
## - FORKS: the forks out to their tips at their height, with the pallet they carry (PalletBox, its long side along
##   them): lower than a shelf they stop at its face, the pallet on them still in reach of its slot; above it they
##   pass over and the mast stops it, unless a wall behind the shelf stops their tips first (a shelf is 1 m deep, the
##   forks 1.2 m, and the default shelves stand against the wall).
## The seat is left to the capsule (it lies between REAR and MAST), and every box keeps clear of the floor, so the
## capsule alone stands, steps and slides on it.
##
## Getting on puts the boxes where the player happens to look, so a box that lands inside something stays disabled
## until it is clear (attach()): the physics would push the body out at random, through a wall or under it. And the
## forks do not ride into what is under or over them (mast_blocked(), ForkliftView stops the mast there): that would
## lift the whole body and its driver onto it, off a forklift that is drawn on the floor.
##
## In the forklift's own frame, which is its driver's: it faces -Z with its origin on the floor under the driver, and
## the player turns it (ForkliftView sets it there, facing where the player faces). Nothing travels: every peer adds
## the same boxes to the same player and only the driver's own peer moves it (move_and_slide), so that is where they
## stop it. A driver that is not a CollisionObject3D (a test's stand-in) gets nothing. A parked forklift has no
## collider, like the jack and the pallets on the floor (PalletYardView): nobody has to walk round it, and a driver
## who gets off is never shut in between its parts.

const REAR: StringName = &"rear"
const MAST: StringName = &"mast"
const FORKS: StringName = &"forks"
const PARTS: Array[StringName] = [REAR, MAST, FORKS]
## The shapes' node names on the driver's body: SHAPE_PREFIX + the part.
const SHAPE_PREFIX: String = "ForkliftShape_"

## Where the rear and the mast start over the floor (m): over a kerb the capsule steps up (character_step, 0.22 m),
## so it never stops them first, and the capsule, not a box, is what stands on it. The forks start at their own
## height, FORK_FLOOR_GAP_M over the floor at the lowest.
const BODY_BOTTOM_M: float = 0.25
const FORK_FLOOR_GAP_M: float = 0.05
## The rear: 1 m wide, from just behind the capsule (its radius is 0.35 m) to the back of the counterweight, as high
## as the counterweight (ForkliftView's boxes).
const REAR_WIDTH_M: float = 1.0
const REAR_FROM_M: float = 0.4
const REAR_TO_M: float = 1.2
const REAR_TOP_M: float = 1.2
## The mast: from just ahead of the capsule to where the forks start, as wide as the backrest, as high as the mast.
const MAST_WIDTH_M: float = 0.9
const MAST_FROM_M: float = 0.4
const MAST_TOP_M: float = 2.7
## How thick the bare forks' box is over the forks (m): something solid to stop at, not a 5 cm blade.
const BARE_FORKS_M: float = 0.15
## What a box has to keep out of: environment and vehicle_shell. A loose package is in the player's mask too, but the
## boxes shove it aside.
const SOLID_MASK: int = 1 | 64
## How far ahead of the forks the mast looks for what it would run into (m): about two frames of the mast at 30 FPS.
const MAST_BRAKE_M: float = 0.03
## How much the forks' box is trimmed on each side when the mast looks (m): forks stopped at a face lie against it,
## and a face beside them is not under them.
const FACE_INSET_M: float = 0.05


## The boxes of a forklift whose forks are at `height` (m), carrying a pallet or not: part -> {size, center}
## (Vector3, metres, the forklift's frame).
static func boxes(height: float, carrying: bool) -> Dictionary:
	var footprint: Vector2 = CompanyTuning.PALLET_FOOTPRINT_M
	var tip: float = CompanyTuning.FORKLIFT_TIP_M
	var forks_from: float = tip - footprint.x * 0.5
	var rear_height: float = REAR_TOP_M - BODY_BOTTOM_M
	var mast_height: float = MAST_TOP_M - BODY_BOTTOM_M
	var lift: float = clampf(height, 0.0, CompanyTuning.FORKLIFT_MAX_LIFT_M)
	var bottom: float = maxf(lift, FORK_FLOOR_GAP_M)
	var top: float = lift + ForkliftView.FORK_THICKNESS + (PalletBox.height() if carrying else BARE_FORKS_M)
	return {
		REAR: {"size": Vector3(REAR_WIDTH_M, rear_height, REAR_TO_M - REAR_FROM_M),
			"center": Vector3(0.0, BODY_BOTTOM_M + rear_height * 0.5, (REAR_FROM_M + REAR_TO_M) * 0.5)},
		MAST: {"size": Vector3(MAST_WIDTH_M, mast_height, forks_from - MAST_FROM_M),
			"center": Vector3(0.0, BODY_BOTTOM_M + mast_height * 0.5, -(MAST_FROM_M + forks_from) * 0.5)},
		FORKS: {"size": Vector3(footprint.y, top - bottom, footprint.x),
			"center": Vector3(0.0, (bottom + top) * 0.5, -tip)},
	}


## Puts the boxes of a forklift with its forks at `height`, `carrying` or not, on `body`, or fits the ones it has. A
## new box starts disabled and counts from the first call that finds it clear, so moving off a wall (or turning away
## from it) is what brings it in. False, adding nothing, when `body` is not a CollisionObject3D.
static func attach(body: Node, height: float, carrying: bool) -> bool:
	if not body is CollisionObject3D:
		return false
	var wanted: Dictionary = boxes(height, carrying)
	for part: StringName in PARTS:
		var shape := body.get_node_or_null(NodePath(SHAPE_PREFIX + String(part))) as CollisionShape3D
		if shape == null:
			shape = CollisionShape3D.new()
			shape.name = SHAPE_PREFIX + String(part)
			shape.shape = BoxShape3D.new()
			shape.disabled = true
			body.add_child(shape)
		var box := shape.shape as BoxShape3D
		var size: Vector3 = wanted[part]["size"]
		var center: Vector3 = wanted[part]["center"]
		# Only what changed: a shape rebuilt every frame of the mast costs the physics server for nothing.
		if not box.size.is_equal_approx(size):
			box.size = size
		if not shape.position.is_equal_approx(center):
			shape.position = center
		if shape.disabled and _is_clear(body as CollisionObject3D, size, center):
			shape.disabled = false
	return true


## Takes the forklift's boxes off `body` (nothing for a body without them).
static func detach(body: Node) -> void:
	if not is_instance_valid(body):
		return
	for part: StringName in PARTS:
		var shape: Node = body.get_node_or_null(NodePath(SHAPE_PREFIX + String(part)))
		if shape != null:
			body.remove_child(shape)
			shape.queue_free()


## Whether `body` carries the forklift's boxes.
static func is_on(body: Node) -> bool:
	return is_instance_valid(body) and body.get_node_or_null(NodePath(SHAPE_PREFIX + String(REAR))) != null


## Whether forks at `height`, `carrying` or not, on `body` would run into something solid going `dir` (-1 down, 1 up).
## Forks whose box is not in yet (attach()) stop nothing and nothing stops them.
static func mast_blocked(body: Node, height: float, carrying: bool, dir: int) -> bool:
	if not is_instance_valid(body):
		return false
	var forks := body.get_node_or_null(NodePath(SHAPE_PREFIX + String(FORKS))) as CollisionShape3D
	if forks == null or forks.disabled:
		return false
	var next: Dictionary = boxes(height + float(dir) * MAST_BRAKE_M, carrying)[FORKS]
	var trim := Vector3(FACE_INSET_M * 2.0, 0.0, FACE_INSET_M * 2.0)
	return not _is_clear(body as CollisionObject3D, (next["size"] as Vector3) - trim, next["center"])


## Whether a box of `size` at `center` in `body`'s frame has nothing solid in it. False for a body out of the tree.
static func _is_clear(body: CollisionObject3D, size: Vector3, center: Vector3) -> bool:
	if not body.is_inside_tree():
		return false
	var box := BoxShape3D.new()
	box.size = size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = body.global_transform * Transform3D(Basis.IDENTITY, center)
	query.collision_mask = SOLID_MASK
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

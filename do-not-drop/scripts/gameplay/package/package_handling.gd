class_name PackageHandling
extends RefCounted
## Carrying, passing, setting down, shelving and handing over the box (host side). Split out of package.gd
## (N-225.4) like package_rescue.gd: the state stays on the DeliveryPackage, which keeps thin wrappers and the
## RPCs (authority, request budget and arguments are checked there; whether the sender is the carrier, here).
##
## By name on purpose (N-224.4, test_dynamic_dispatch_budget): the truck (vehicle.gd has no class name and tests
## put plain-Node fakes with carries and point_velocity in the "vehicle" group) and RunManager's
## consumed_packages (see package_autoloads.gd: typing the autoload makes a compile cycle).

## How close a receiving player has to be to take the box from the carrier's hands.
const TRANSFER_REACH: float = 2.4
## A resident took the box at the door: it floats from the hands to the doorway (HAND_OVER_SECONDS) and the
## resident takes it in (TAKE_IN_SECONDS), then it's gone (tareas de Slatex #15).
const HAND_OVER_SECONDS: float = 0.45
const TAKE_IN_SECONDS: float = 0.3


## The carrier's pose, applied on the host's copy: `in_vehicle` puts it on the host's own truck (each peer's
## copy of the truck is a little behind the host's, and a world pose put the box a metre behind the hands at
## speed). `sender` is the remote sender (0: a genuine local call).
static func accept_carry(p: DeliveryPackage, sender: int, carry_transform: Transform3D, in_vehicle: bool) -> void:
	if sender != 0 and (not is_instance_valid(p.carrier) or sender != p.carrier.get_multiplayer_authority()):
		return
	if not p.is_held:
		return
	var vehicle: Node3D = p._find_vehicle()
	p._carry_in_vehicle = in_vehicle and vehicle != null
	p._carry_pose = carry_transform
	p.global_transform = vehicle.global_transform * carry_transform if p._carry_in_vehicle else carry_transform


static func set_held(p: DeliveryPackage, held: bool) -> void:
	p.is_held = held
	p.freeze = held
	# Disabled while carried: a held package following the hold point every
	# frame shouldn't shove the player or clip weirdly through the world.
	p.collision_layer = 0 if held else 4
	p.collision_mask = 0 if held else DeliveryPackage.LOOSE_MASK
	# The velocity sampled before a pickup has nothing to do with the first
	# physics step after a drop; comparing the two read as a hard impact.
	p._has_previous_velocity = false
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO


## Host-only: pickup points call this instead of set_held(true) directly, so the package knows who has it --
## needed to validate drop requests and to clear that player's hands on every peer when the box leaves them.
static func take_by(p: DeliveryPackage, player: Node) -> void:
	var peer_id: int = int(player.get_multiplayer_authority())
	var vehicle: Node3D = p._find_vehicle()
	if p._is_run_active() and not p.is_held and not p.is_loaded \
			and (vehicle == null or not bool(vehicle.call(&"carries", p.global_position))):
		p._rescue_pending = true
	p.lap_mount_path = NodePath()
	if p.is_loaded:
		release_mount(p)
	set_held(p, true)
	p.carrier = player
	p._last_holder_peer = peer_id
	player.rpc(&"pick_up", p.get_path())


## Riding with the crew: on a rack, or on the lap of whoever sits tending it
## (seat_point.gd). Built from replicated state so every peer agrees; the
## carrier check only narrows it on the host, where it is known.
static func is_aboard(p: DeliveryPackage) -> bool:
	if p.is_loaded:
		return true
	if not p.is_held or p.tender_peer_id <= 0:
		return false
	return p.carrier == null or int(p.carrier.get_multiplayer_authority()) == p.tender_peer_id


## Hand-to-hand transfer. The host checks both the caller's ownership and
## physical distance, so a client cannot pass cargo across the map.
## `sender_id`: the remote sender (0: a genuine local call), checked against the carrier here.
## Needs a carrier (request_transfer() checks it).
static func transfer(p: DeliveryPackage, sender_id: int, recipient_path: NodePath) -> void:
	if sender_id != 0 and int(p.carrier.get_multiplayer_authority()) != sender_id:
		return
	var recipient: Player = p.get_node_or_null(recipient_path) as Player if RpcGuard.path_ok(recipient_path) else null
	if recipient == null or recipient == p.carrier or recipient.carried_package != null:
		return
	if DeliveryPackage._reach_origin(recipient).distance_to(DeliveryPackage._reach_origin(p.carrier)) \
			> TRANSFER_REACH + p.reach_slack(sender_id):
		return
	var giver_peer_id: int = p._last_holder_peer
	take_by(p, recipient)
	if p._is_run_active():
		p._award_milestone(giver_peer_id, &"handover")


## A carrier can always put a box back on the floor. Unlike a mount this
## keeps it loose and physical, so a mistaken pickup never traps the player.
## `in_vehicle` as in accept_carry(): set down in the truck, it's placed on
## the host's truck and starts out moving with it.
## `sender_id`: the remote sender (0: a genuine local call), checked against the carrier here.
static func drop(p: DeliveryPackage, sender_id: int, drop_transform: Transform3D, in_vehicle: bool) -> void:
	if sender_id != 0 and p.carrier != null and int(p.carrier.get_multiplayer_authority()) != sender_id:
		return
	release_carrier(p)
	var vehicle: Node3D = p._find_vehicle()
	p.global_transform = vehicle.global_transform * drop_transform if in_vehicle and vehicle != null \
			else drop_transform
	p.reset_physics_interpolation()
	set_held(p, false)
	ride_along_if_aboard(p)


## Let go of inside the moving truck (dropped, or put back on the rack
## mid-run): start with the truck's own velocity, or the box behaves as if
## dropped from a standstill and slams into the rear wall.
static func ride_along_if_aboard(p: DeliveryPackage) -> void:
	if p.freeze:
		return
	var vehicle: Node3D = p._find_vehicle()
	if vehicle != null and bool(vehicle.call(&"carries", p.global_position)) and vehicle.has_method(&"point_velocity"):
		p.linear_velocity = vehicle.call(&"point_velocity", p.global_position)


## For when the carrier goes away (disconnect) rather than letting go: the
## box must not stay frozen mid-air with collisions off forever.
static func drop_loose(p: DeliveryPackage, drop_transform: Transform3D) -> void:
	if not p.is_held:
		return
	p.carrier = null
	p.global_transform = drop_transform
	p.reset_physics_interpolation()
	set_held(p, false)


## `mount` gives the transform to snap to (the marker); `mount_point` is the
## Interactable that actually tracks occupancy (its InteractionArea child --
## see package_mount_point.gd's `occupied_by`). They're usually different
## nodes, so release_mount() needs the latter, not the former.
static func place_at(p: DeliveryPackage, mount: Node3D, mount_point: Node) -> void:
	release_carrier(p)
	p.global_transform = mount.global_transform
	# Snapped onto the shelf: drawn there at once, not slid in from the hands.
	p.reset_physics_interpolation()
	set_held(p, false)
	p.is_loaded = true
	p.current_mount_path = (mount_point if mount_point != null else mount).get_path()
	# Frozen while loading, until level_base.gd starts the run. A box put back
	# mid-run has to ride physically like the rest, not stay glued to the shelf.
	p.freeze = not p._is_run_active()
	ride_along_if_aboard(p)
	p._emit_event(&"package_placed", [p.package_id])
	if p._rescue_pending:
		p._rescue_pending = false
		p._award_milestone(p._last_holder_peer, &"rescued")


## A resident took the box at the door. Its carrier's hands have to empty on
## every peer before the node goes away, or they keep "holding" a freed box.
##
## With `hand_over_at` (the resident at the door) it doesn't just vanish: see play_consume().
static func consume(p: DeliveryPackage, hand_over_at: Variant) -> void:
	release_carrier(p)
	release_mount(p)
	# It's a scene node, not a spawned one: freeing it here never reached the
	# clients, where it stayed at the door, full size and still "cargo".
	if p.is_inside_tree():
		var run: Node = PackageAutoloads.run_manager(p)
		if run != null:
			(run.get(&"consumed_packages") as Array).append(String(p.get_path()))
		var network := PackageAutoloads.network(p)
		if network != null and network.is_online() and network.is_host():
			p._remote_consume.rpc(hand_over_at)
	play_consume(p, hand_over_at)


## With `hand_over_at` the box floats from the hands to the doorway and the resident takes it in, then it's
## gone. Already out of play from the first frame -- no collisions, no longer cargo -- so nothing can grab it
## back.
static func play_consume(p: DeliveryPackage, hand_over_at: Variant) -> void:
	p._consumed = true
	if hand_over_at == null or not p.is_inside_tree():
		p.remove_from_group(&"cargo")
		p.call_deferred(&"queue_free")
		return
	p.remove_from_group(&"cargo")
	p.set_deferred(&"freeze", true)
	p.collision_layer = 0
	p.collision_mask = 0
	var tween: Tween = p.create_tween()
	tween.tween_property(p, ^"global_position", hand_over_at as Vector3, HAND_OVER_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(p, ^"scale", Vector3.ONE * 0.05, TAKE_IN_SECONDS) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(p.queue_free)


static func release_carrier(p: DeliveryPackage) -> void:
	p.lap_mount_path = NodePath()
	if p.carrier != null and is_instance_valid(p.carrier) and p.carrier.is_inside_tree():
		p.carrier.rpc(&"drop_carried")
	p.carrier = null


## Frees the shelf slot this package occupies, if any. Without this the mount
## stays marked occupied forever and nothing can ever be placed there again --
## including this same box on the way back (docs/colaboracion-equipo.md).
static func release_mount(p: DeliveryPackage) -> void:
	if p.current_mount != null and is_instance_valid(p.current_mount):
		p.current_mount.set(&"occupied_by", null)
	p.current_mount = null
	p.current_mount_path = NodePath()
	p.is_loaded = false

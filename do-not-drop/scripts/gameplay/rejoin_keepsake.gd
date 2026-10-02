class_name RejoinKeepsake
extends Node
## N-221: someone who drops out and comes back gets back where they were, the
## seat they sat in and the box in their hands, instead of appearing like any
## other late joiner. Host only; a level builds one (level_common.gd).
##
## When a player leaves the roster (NetworkManager.peer_removed, while its
## player still stands) the host notes what it had: where it stood (in the
## truck's own space when it rode in it), the seat it sat in, the box it held
## and the lap bay that box was bound for. Leaving still lets go of all of it
## right away (player.gd _exit_tree: the seat frees, the box drops loose,
## S-209): the crew isn't left waiting on someone who may never come back.
## When the same person is back -- NetworkManager.peer_returned, which only
## fires for the same identity (a Steam id, or the next link of the LAN hash
## chain: nobody else can claim it) -- the note follows them to their new peer
## id, and the level spawns them from it (place(), give_back()):
## - in the truck if they were in it (the seat again if it is still free,
##   else, mid-run, another free seat or the bay as any late joiner);
## - on foot where they stood, if that still makes sense: before the run in
##   the depot, mid-run near the truck (RETURN_RADIUS) -- the road behind it
##   may already be gone;
## - with their box back in their hands if nobody touched it since: still
##   loose, not shelved nor lost, nobody else picked it up, and within
##   BOX_REACH of where they come back.
## Anything else falls back to the late-join placement (late_join_seating.gd).
## A note lives as long as the level: a restart puts everyone in the depot
## anyway. Nothing here travels: the spawn data, the seat and the pick_up are
## those of any join.

## vehicle.gd and package_mount_point.gd have no class name.
const VehicleScript = preload("res://scripts/gameplay/vehicle/vehicle.gd")
const PackageMountPoint = preload("res://scripts/gameplay/interaction/package_mount_point.gd")

## Mid-run, someone who was on foot comes back where they stood only this
## close to the truck; further, the road there may have been streamed away.
const RETURN_RADIUS: float = 40.0
## The box comes back to their hands only from this close to where they appear.
const BOX_REACH: float = 3.0
## Notes kept for those who left (and for returners not spawned yet), each;
## the oldest go first.
const MEMORY: int = 16

var vehicle: Node3D
var late_join: LateJoinSeating
## {peer id that left: note}.
var _kept: Dictionary = {}
## {peer id back, not spawned yet: note}.
var _returned: Dictionary = {}


## Host: `peer_id` left; `player` is its player, still standing (null if it
## had none yet: someone back who left again before being spawned keeps the
## note it came back to).
func remember(peer_id: int, player: Node3D) -> void:
	var body: Player = player as Player if is_instance_valid(player) else null
	if body == null:
		if _returned.has(peer_id):
			_kept[peer_id] = _returned[peer_id]
			_returned.erase(peer_id)
			_prune(_kept)
		return
	_returned.erase(peer_id)
	var seat_path: NodePath = body.seat_node_path
	var riding: bool = body.net_in_vehicle
	var aboard: bool = is_instance_valid(vehicle) and (not seat_path.is_empty() or riding)
	var local: Vector3 = Vector3.ZERO
	if aboard:
		local = body.net_position if riding and seat_path.is_empty() \
				else vehicle.to_local(body.global_position)
	var box: DeliveryPackage = body.carried_package
	if box != null and (not is_instance_valid(box) or box.carrier != body):
		box = null
	var note: Dictionary = {
		"peer": peer_id, "player": weakref(body), "position": body.global_position,
		"aboard": aboard, "local": local, "seat": seat_path,
		"underway": late_join != null and late_join.underway(),
		"box": box.get_path() if box != null else NodePath(),
		"lap": box.lap_mount_path if box != null else NodePath(),
	}
	_kept.erase(peer_id)
	_kept[peer_id] = note
	_prune(_kept)


## Host (NetworkManager.peer_returned): `id` is `previous_id` back. The note
## follows it; one already moved to an id that never made it in follows too.
func on_returned(id: int, previous_id: int) -> void:
	var note: Dictionary = _kept.get(previous_id, _returned.get(previous_id, {}))
	if note.is_empty():
		return
	_kept.erase(previous_id)
	_returned.erase(previous_id)
	_returned[id] = note
	_prune(_returned)


## Host: the note for `id`, back and not spawned yet ({} if none).
func note_for(id: int) -> Dictionary:
	return _returned.get(id, {})


## Whether the player `note` was taken from is still in the tree (a ghost
## dropped this frame is freed at its end): its seat and box aren't free yet.
func lingers(note: Dictionary) -> bool:
	var old: Object = (note.get("player") as WeakRef).get_ref() if note.get("player") is WeakRef else null
	return old != null and is_instance_valid(old) and (old as Node).is_inside_tree()


## Where `note`'s player comes back: {"position": world, "seat": SeatPoint or
## null, "local": truck space, only when in the truck}, or {} for the usual
## placement (depot, or late-join seating mid-run).
func place(note: Dictionary) -> Dictionary:
	var underway: bool = late_join != null and late_join.underway()
	if bool(note.aboard) and is_instance_valid(vehicle):
		var seat: SeatPoint = _free_seat(NodePath(note.seat))
		if seat != null:
			var at: Vector3 = late_join.standing_spot(seat) if late_join != null \
					else vehicle.to_local(seat.global_position)
			return {"position": vehicle.to_global(at), "seat": seat, "local": at}
		if not NodePath(note.seat).is_empty() and underway and late_join != null:
			return late_join.place()  # Their seat was taken: another, or the bay.
		var local: Vector3 = note.local
		var taken: SeatPoint = _seat_at(NodePath(note.seat))
		if taken != null and late_join != null:
			local = late_join.standing_spot(taken)  # Beside it, not in whoever sits there.
		return {"position": vehicle.to_global(local), "seat": null, "local": local}
	var position: Vector3 = note.position
	if underway:
		if bool(note.underway) and is_instance_valid(vehicle) \
				and position.distance_to(vehicle.global_position) <= RETURN_RADIUS:
			return {"position": position, "seat": null}
		return {}
	return {} if bool(note.underway) else {"position": position, "seat": null}


## Host, right after `player` was spawned from `note` (and before it is
## seated): its box back in its hands, if nobody touched it since. Spends the
## note.
func give_back(player: Node3D, note: Dictionary) -> void:
	_returned.erase(int(player.get_multiplayer_authority()))
	var box: DeliveryPackage = get_node_or_null(NodePath(note.box)) as DeliveryPackage \
			if not NodePath(note.box).is_empty() else null
	if box == null or not box.is_inside_tree() or box.is_queued_for_deletion():
		return
	if box.is_held or box.is_loaded or box._lost or box._last_holder_peer != int(note.peer):
		return
	if box.global_position.distance_to(player.global_position) > BOX_REACH:
		return
	# Taking it back is not a rescue: take_by() marks a box picked up off the
	# road mid-run as one, and shelving it would credit "rescued".
	var rescue_pending: bool = box._rescue_pending
	box.take_by(player)
	box._rescue_pending = rescue_pending
	var lap: PackageMountPoint = get_node_or_null(NodePath(note.lap)) as PackageMountPoint \
			if not NodePath(note.lap).is_empty() else null
	if lap != null and lap.occupied_by == null:
		SeatTending.bind_lap(box, lap)


## Host, after give_back(): sits `player` back at `seat`. A seat behind a
## closed door (the driver's) gets it opened first -- whoever comes back to the
## wheel needn't walk round -- and shut again if the seat turns them down (a
## box in hand, say): they stand beside it instead.
func seat_back(player: Node3D, seat: SeatPoint) -> void:
	var opened: bool = _open_door(seat)
	late_join.seat_player(player, seat)
	if opened and seat.occupant != player:
		(vehicle as VehicleScript).set_door_open(seat.required_door, false)


## The seat at the anchor `seat_path` if it would take someone now, its door
## (if it has one) aside: seat_back() opens it. Nothing changes here.
func _free_seat(seat_path: NodePath) -> SeatPoint:
	var seat: SeatPoint = _seat_at(seat_path)
	if seat == null or is_instance_valid(seat.occupant) or seat.is_occupied():
		return null
	var opened: bool = _open_door(seat)
	var takes: bool = seat.can_interact(self)
	if opened:
		(vehicle as VehicleScript).set_door_open(seat.required_door, false)
	return seat if takes else null


## The seat at the anchor `seat_path`, free or not (null if none).
func _seat_at(seat_path: NodePath) -> SeatPoint:
	var anchor: Node = get_node_or_null(seat_path) if not seat_path.is_empty() else null
	return anchor.get_node_or_null(^"InteractionArea") as SeatPoint if anchor != null else null


## Opens `seat`'s door if it has one and it is shut; true if it did.
func _open_door(seat: SeatPoint) -> bool:
	var truck: VehicleScript = vehicle as VehicleScript
	if seat.required_door == &"" or truck == null or truck.is_door_open(seat.required_door):
		return false
	truck.set_door_open(seat.required_door, true)
	return true


static func _prune(notes: Dictionary) -> void:
	while notes.size() > MEMORY:
		notes.erase(notes.keys()[0])

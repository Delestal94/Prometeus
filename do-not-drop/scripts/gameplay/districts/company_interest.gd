class_name CompanyInterest
extends WorldCellInterest
## Who gets the updates of the company's vehicles and loose boxes (expansion D-0316): the
## world_cells module's WorldCellInterest with this game's numbers and anchors.
##
## Every player is an anchor of the map's cells, at anchor_point(): its reach_origin() when it has
## one (a seated Player's body stays where it sat down; its seat rides along), else where it stands.
## On the host, a vehicle (CompanyTrips.VEHICLE_GROUP) or a loose box (LOOSE_BOX_GROUP) is sent to a
## peer only while that peer's player is within CompanyTuning.CELL_LOAD_RADIUS cells of it, and stops
## once it is past CELL_UNLOAD_RADIUS: a player who stays in the shed gets nothing of a trip on the
## other side of the map, while the host keeps simulating every vehicle (decision 2026-10-04, point
## 6). The driver (the vehicle's driver_peer_id) always gets the vehicle it drives; a rider counts at
## its seat, so it gets the vehicle and the boxes it rides with. A peer whose player has no node here
## yet gets everything, as before. On a client, the copy of a far vehicle or box is hidden and taken out of
## physics until an update puts it back near (nobody sees it jump, or bumps into it, meanwhile); a
## box shown again derives its own layers again (its is_held setter, out of physics if consumed:
## copy_shown).
##
## Contract for what joins those groups (WorldCellInterest's header):
## - an RPC called on the body itself (the synchronizer's root) skips the peers it is hidden from,
##   broadcasts included: a one-shot fact or a removal of a vehicle or loose box (a vehicle sold) goes
##   as an ON_CHANGE property of its synchronizer, as an RPC on a node that isn't tracked (CompanyNet's
##   events), or after untrack() / release(), or the far peers keep a stale copy for good. A loose box
##   comes in through add_loose_box(), which on the host releases it on DeliveryPackage.consuming,
##   emitted before consume() broadcasts _remote_consume on the box (D-0316.3);
## - nothing a MultiplayerSpawner spawns: hiding it would despawn it on that peer;
## - its synchronizer's public_visibility and per-peer flags are this node's; any other condition
##   goes in add_visibility_filter() (red-autoridad.md rule 10 and 11).
##
## cell_anchors() is where the map's cells load around (CompanyRoot feeds CompanyCells with it): on
## the host every player and every vehicle; on a client only its own player, so a player in the
## shed doesn't load, nor carry the cost of, a route it is not on.
##
## A crew member is a node of `crew_group` (CompanyRoot.CREW_GROUP) owned by its peer
## (get_multiplayer_authority()); only nodes of this node's own multiplayer count.

## The group loose boxes join to be sent only to the players near them (add_loose_box(), D-0316.3).
const LOOSE_BOX_GROUP: StringName = &"company_loose_box"

## The group of the players (CompanyRoot.CREW_GROUP, handed in by the root).
var crew_group: StringName = &"company_crew"


func _init() -> void:
	grid.cell_size = CompanyTuning.CELL_SIZE
	grid.load_radius = CompanyTuning.CELL_LOAD_RADIUS
	grid.unload_radius = CompanyTuning.CELL_UNLOAD_RADIUS
	update_interval_sec = CompanyTuning.INTEREST_UPDATE_REAL_SECONDS
	keepalive_sec = CompanyTuning.INTEREST_KEEPALIVE_REAL_SECONDS
	keepalive_pulse_sec = CompanyTuning.INTEREST_PULSE_REAL_SECONDS
	groups = [CompanyTrips.VEHICLE_GROUP, LOOSE_BOX_GROUP]
	anchor_of = _anchor_of
	viewers_of = _viewers_of
	copy_shown.connect(_on_copy_shown)


## Every peer: `box` (a company DeliveryPackage) is a loose box from now on, sent only to the players
## near it: it joins LOOSE_BOX_GROUP. On the host `removing` (the box's consuming signal, emitted before
## its removal is broadcast on the box itself) releases it first, so that broadcast reaches the far
## peers too (D-0316.3). The caller hands the signal in (CompanyRoot: the package's consuming).
func add_loose_box(box: Node3D, removing: Signal) -> void:
	box.add_to_group(LOOSE_BOX_GROUP)
	if is_inside_tree() and multiplayer.is_server() and not removing.is_null():
		removing.connect(release.bind(box))


## Where a crew member counts as being: its reach_origin() when it has one (a seated Player: its seat,
## while its body stays where it sat down), else where it stands.
static func anchor_point(member: Node3D) -> Vector3:
	if member.has_method(&"reach_origin"):
		var at: Variant = member.call(&"reach_origin")
		if at is Vector3:
			return at
	return member.global_position


## The player node `peer` owns among `scope`'s session's nodes in `group`, or null.
static func crew_member(scope: Node, peer: int, group: StringName) -> Node3D:
	if scope == null or not scope.is_inside_tree():
		return null
	for node: Node in scope.get_tree().get_nodes_in_group(group):
		var member := node as Node3D
		if member != null and member.is_inside_tree() and member.multiplayer == scope.multiplayer \
				and member.get_multiplayer_authority() == peer:
			return member
	return null


## Where the map's cells load around, for `scope`'s session: on the host (`as_host`) every crew
## member and every node of `vehicle_group`; on a client only the crew member it owns. A crew member
## counts at anchor_point() (a rider at its seat), a vehicle where it stands.
static func cell_anchors(scope: Node, group: StringName, vehicle_group: StringName, as_host: bool) -> Array[Vector3]:
	var found: Array[Vector3] = []
	if scope == null or not scope.is_inside_tree():
		return found
	var groups_to_read: Array[StringName] = [group]
	if as_host:
		groups_to_read.append(vehicle_group)
	for group_name: StringName in groups_to_read:
		for node: Node in scope.get_tree().get_nodes_in_group(group_name):
			var body := node as Node3D
			if body == null or not body.is_inside_tree() or body.multiplayer != scope.multiplayer:
				continue
			if as_host or body.is_multiplayer_authority():
				found.append(anchor_point(body) if group_name == group else body.global_position)
	return found


func _anchor_of(peer: int) -> Variant:
	var member: Node3D = crew_member(self, peer, crew_group)
	return anchor_point(member) if member != null else null


## The driver of a vehicle gets it whatever its player's pose says (it predicts the vehicle).
func _viewers_of(body: Node3D) -> Array:
	var driver: Variant = body.get(&"driver_peer_id")
	return [int(driver)] if driver is int and int(driver) > 0 else []


## A loose box's copy shown again: its own is_held setter derives its layers again (none while held,
## its own while loose); one written as 0 while the copy was hidden can't be told from the hiding. A
## box already consumed (play_consume() took it out of physics) stays out.
func _on_copy_shown(body: Node3D) -> void:
	var box := body as DeliveryPackage
	if box == null:
		return
	if box._consumed:
		box.collision_layer = 0
		box.collision_mask = 0
	else:
		box.is_held = box.is_held

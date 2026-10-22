class_name CompanyFleet
extends Node3D
## The company's vehicles in its world, on every peer (expansion D-0302.2.b, with D-0316): this node is
## CompanyRoot's World/Vehicles.
##
## One vehicle per entry of the company's fleet (vehicle_ids()), at most MAX_VEHICLES: the definition of
## data/vehicles/ the entry names ("id"), or the first with its fleet key ("vehicle", as CompanyShop writes it;
## the starting fleet's ahead of the rest). A fleet with no vehicle that exists is CompanyTuning.STARTING_FLEET:
## new_company() doesn't write the gift van into CompanyState.fleet yet (D-0207; the dealer, D-1201, will). Each
## is its definition's scene with its variant, named by its id (a second of the same id "<id>_2", node_names()),
## so the node and its MultiplayerSynchronizer have the same path on every peer and pair up with the host's, as
## the delivery's static truck does. Each joins CompanyTrips.VEHICLE_GROUP: the host's gate watches it,
## CompanyInterest sends it only to the players near it and to its driver, and the host's cells load around it.
## Parked side by side in the playon, the yard outside the shed's north exit (park_transform()): rear doors
## PARK_GAP_M past the north wall, facing the exit, nose away from the shed. The playon is PLAYON_DEPTH_M deep
## from the outside of that wall and PLAYON_WIDTH_M wide (PLAYON_SLOTS vans side by side), and its far edge is where
## CompanyTrips' gate stands (gate_of()): a parked vehicle is inside it, a trip starts only when one is driven
## out of the compound (the rectangle of the shed and the playon, yard_back_m() / yard_half_width_m(): out across
## the far edge, round its sides or its back, wherever there is no fence). The shed's own exit (2 m) is narrower
## than a van (2.2 m): the vehicles live and are loaded in the playon, the exit is for people and boxes.
##
## Driven (D-0302.2.b.2): each is built drivable_outside_run (vehicle.gd), on every peer, so the van drives, parks
## and brakes in this world as it does in a delivery run; its telemetry and impacts stay the run's. The host's is
## built parked (vehicle.gd park(): frozen, `_parked`), held still by vehicle.gd while nobody drives and let go the
## moment somebody takes the wheel; the driver's client predicts its copy as in a delivery (N-218).
##
## Parked, the host's (solo too) is frozen; a client's copy is frozen and drawn from the host's poses. While it
## stays put it sends its pose every NetRestThrottle.rest_interval (a child watching the pose and the driver's
## input), at the full rate again the tick it moves or someone drives: parked, it costs the shed's bandwidth next
## to nothing.
##
## How a client knows the fleet: the host's snapshot, whose company part is the host's CompanyState (fleet and
## stage). The client builds its vehicles when the snapshot is in (CompanyNet.company_state_restored), only the
## missing ones, and then tells the host which it has (_have_fleet, on this node: it has no synchronizer and is
## on every peer from the world's _ready). Rule 10 of red-autoridad.md: on the host each vehicle's synchronizer
## starts invisible to every peer (a visibility filter, on top of CompanyInterest's flags, rule 11) and opens to a
## peer, vehicle by vehicle, only once that peer said it has it (ack()) and its world is up (is_peer_ready()). The
## node's own word is the only safe one, as for CompanyPackages: a snapshot may not go out (too big) or not apply
## there (a part it refuses), and a synchronizer that reaches a peer before its node exists is never resolved
## there (package.gd's _enter_tree note). A vehicle built later on the host stays closed to a peer until that
## peer acks it. A peer that leaves, or whose world comes up again, is closed until it acks again, and the host
## takes it off any wheel it held (release_peer()): a dropped driver doesn't keep the van, nor its input.
##
## Bought mid-day (D-0302.2.b.5): a shop_bought of a vehicle (CompanyShopNet) is applied to every peer's company, and
## the fleet then builds the new one on each (_on_event(), build() adds only the missing), a client telling the host
## it has it (tell_host()) so its synchronizer opens. The shop refuses the vehicle past PLAYON_SLOTS (CompanyShop).
##
## Not here yet: selling one (D-0528 is postponed) and CompanyTrips.forget() for one that leaves mid-day. Closing
## the world frees them all, which is no vehicle leaving: the day is saved as it stood (D-2005). Nothing here names
## an autoload (lesson N-919).

const FleetCargo = preload("res://scripts/gameplay/fleet/fleet_cargo.gd")

## Host: `vehicle_id` fell out of the world and was put back in the playon (recover_fallen()): CompanyRoot closes
## its trip (CompanyTrips.forget()), so the day never waits for a vehicle that is not out.
signal vehicle_recovered(vehicle_id: StringName)

## This node's name under World, the same on every peer.
const NODE_NAME: String = "Vehicles"
## Most vehicles one fleet builds (rule 5: a snapshot can't make a client build more).
const MAX_VEHICLES: int = 16
## Metres from the outside of the shed's north wall to a parked vehicle's rear doors: room for its ramp, and
## for the crew to carry the boxes from the exit.
const PARK_GAP_M: float = 2.0
## Metres between two vehicles parked side by side (a van is 2.2 m wide).
const PARK_SPACING_M: float = 3.5
## The playon, the yard outside the shed's north exit: metres from the outside of the north wall to its far edge,
## where the trips' gate stands (gate_of()). A van parked by park_transform() has its nose 9.3 m past the wall; the
## rest is the room between it and the gate.
const PLAYON_DEPTH_M: float = 12.0
## ... and its width, centred on the exit: the gate's opening (CompanyTrips.setup()) and, at least, the compound's
## (yard_half_width_m()). PLAYON_SLOTS vans side by side (PARK_SPACING_M) fit; a vehicle beyond them (an eighth
## and on: the fleet may have MAX_VEHICLES) stands past the playon's side, outside the compound from the start
## (its first position only sets its side: no trip), until the dealer (D-1201) limits the fleet to the yard.
const PLAYON_WIDTH_M: float = 26.0
const PLAYON_SLOTS: int = 7
## Height (m) under which a vehicle fell through the world (a zone with no ground under it): it is put back
## where it parks (recover_fallen()).
const FALL_Y_M: float = -10.0
## Height a parked vehicle is put at: the host's sits on the ground on its first tick (vehicle.gd
## _snap_to_ground, RIDE_HEIGHT 0.666 over it), a client's is moved by the host's first pose.
const PARK_HEIGHT_M: float = 0.7
## What a vehicle's NetRestThrottle watches, those its scene has: the pose it sends and the input its driver's
## client numbers (vehicle.gd net_input_seq), so it never rests while someone drives.
const REST_WATCHED: Array[StringName] = [&"net_position", &"net_rotation", &"net_input_seq"]
const SYNC_PATH: NodePath = ^"MultiplayerSynchronizer"

## The CompanyNet whose company the fleet is (on a client, once its snapshot is in). Null: nothing is built.
var net: CompanyNet = null
## The shed whose exit they park at (CompanyRoot.shed).
var shed: Node3D = null
## Where the definitions are read: CompanyCatalog.load_all(), once, unless a test hands its own.
var catalog: CompanyCatalog = null

## Decided when hooked (_hook()): the host (solo too) builds now and gates; a client builds on its snapshot.
var _host: bool = false
## Host: the vehicles each peer said it has, so their synchronizers reach it (rule 10), {peer: {name: true}}.
var _opened: Dictionary = {}
## The session whose peers' worlds are up (CompanyRoot.session), or null: every connected peer counts.
var _session: Node = null


## The fleet under `world` (World/Vehicles), parked at `company_shed`'s exit, from `company_net`'s company; the
## host hears joiners' worlds come up from `session` (CompanyRoot.session; null: only CompanyNet's snapshots).
## The host (solo too) builds its vehicles now, a client once the host's snapshot is in.
static func add_to(world: Node, company_net: CompanyNet, session: Node, company_shed: Node3D) -> CompanyFleet:
	var fleet := CompanyFleet.new()
	fleet.name = NODE_NAME
	fleet.net = company_net
	fleet.shed = company_shed
	world.add_child(fleet)
	fleet._hook(session)
	return fleet


## Every peer: a vehicle for each of `company`'s fleet (vehicle_ids()) that isn't here yet, parked in its place
## (park_transform()); on the host its synchronizer reaches only the peers opened to (open_to()). Returns how
## many it added.
func build(company: Object) -> int:
	if company == null or not is_inside_tree():
		return 0
	if catalog == null:
		catalog = CompanyCatalog.load_all()
	var fleet: Variant = company.get(&"fleet")
	var ids: Array[StringName] = vehicle_ids(fleet if fleet is Array else [], catalog)
	var names: Array[String] = node_names(ids)
	var added: int = 0
	for index: int in range(ids.size()):
		if has_node(NodePath(names[index])):
			continue  # Built already (a snapshot after a seq gap), or a clutter's name: never two of a name.
		var body: Node3D = _make(catalog.vehicle(ids[index]), names[index])
		if body == null:
			continue
		body.transform = global_transform.affine_inverse() * park_transform(shed, company, index)
		add_child(body)
		added += 1
	return added


## Host: `peer` has the vehicles `names` (its _have_fleet, after building them), so their synchronizers reach it
## from now on (rule 10); CompanyInterest still decides by distance. Refused, changing nothing (false), unless
## `peer` is connected with its world up (the session's is_peer_ready()) and `names` holds 1 to MAX_VEHICLES
## names of vehicles here, each short (RpcGuard.text_ok()).
func ack(peer: int, names: PackedStringArray) -> bool:
	if not _host or not is_inside_tree() or not multiplayer.get_peers().has(peer):
		return false
	if _session != null and _session.has_method(&"is_peer_ready") and not bool(_session.call(&"is_peer_ready", peer)):
		return false
	if names.is_empty() or names.size() > MAX_VEHICLES:
		return false
	for node_name: String in names:
		if not RpcGuard.text_ok(node_name) or vehicle(node_name) == null:
			return false
	var had: Dictionary = _opened.get(peer, {})
	for node_name: String in names:
		had[node_name] = true
	_opened[peer] = had
	_refresh(peer)
	return true


## Host: `peer` left, or its world came up again (its copies are gone): no vehicle's synchronizer reaches it
## until it acks again, and it holds no wheel (release_peer()).
func close_to(peer: int) -> void:
	release_peer(peer)
	if _opened.erase(peer) and is_inside_tree() and multiplayer.get_peers().has(peer):
		_refresh(peer)


## Host: `peer` drives none of the vehicles, sits in none of their seats, as SeatPoint.release_occupant() leaves a
## driver who got up: a dropped driver kept the wheel (and, back under the same id, sent its input to it again).
func release_peer(peer: int) -> void:
	if not _host or peer <= 0:
		return
	for body: Node3D in vehicles():
		for seat: Node in body.find_children("*", "SeatPoint", true, false):
			var occupant: Variant = seat.get(&"occupant")
			if typeof(occupant) != TYPE_OBJECT:
				continue
			if not is_instance_valid(occupant) or (occupant as Node).get_multiplayer_authority() == peer:
				seat.set(&"occupant", null)
		if int(body.get(&"driver_peer_id")) == peer:
			release_wheel(body)


## Host: nobody drives `body`: no driver, its controls off and neither throttle nor steering, the handbrake on. Whoever
## sat there stays in the seat; to drive again it gets up and boards again (boarding turns the controls back on).
func release_wheel(body: Node3D) -> void:
	body.set(&"driver_peer_id", 0)
	body.set(&"controls_enabled", false)
	if body.has_method(&"set_controls"):
		body.call(&"set_controls", 0.0, 0.0, true)


## Host: the synchronizer of the vehicle `node_name` reaches `peer` (it acked it, ack()).
func is_open_to(peer: int, node_name: String) -> bool:
	return (_opened.get(peer, {}) as Dictionary).has(node_name)


## The vehicle named `node_name` (a vehicle id, node_names()), or null.
func vehicle(node_name: String) -> Node3D:
	var found := get_node_or_null(NodePath(node_name)) as Node3D
	return found if found != null and found.is_in_group(CompanyTrips.VEHICLE_GROUP) else null


## The vehicles here, in the order they were built. Not every child: the van drops its loose cargo clutter
## (cargo_clutter.gd, local scenery that is never replicated) next to itself.
func vehicles() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child: Node in get_children():
		if child is Node3D and child.is_in_group(CompanyTrips.VEHICLE_GROUP):
			found.append(child as Node3D)
	return found


## The definitions (data/vehicles/ ids) of the vehicles of `fleet` (CompanyState.fleet entries), in order: an
## entry's "id" when it names one, else the first with its fleet key ("vehicle", or "key" as
## CompanyState.gate_owned() reads it), the starting fleet's ahead of the rest; an entry naming none is skipped.
## None at all: CompanyTuning.STARTING_FLEET. At most MAX_VEHICLES, and only definitions a vehicle can be built
## from (usable()).
static func vehicle_ids(fleet: Array, from: CompanyCatalog) -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Variant in fleet:
		if ids.size() >= MAX_VEHICLES:
			break
		var id: StringName = definition_of(entry, from)
		if id != &"":
			ids.append(id)
	if ids.is_empty():
		for id: StringName in CompanyTuning.STARTING_FLEET:
			if ids.size() < MAX_VEHICLES and usable(from.vehicle(id)):
				ids.append(id)
	return ids


## The definition a fleet entry is (vehicle_ids()), or "" for one that isn't a dictionary or names none.
static func definition_of(entry: Variant, from: CompanyCatalog) -> StringName:
	if not entry is Dictionary:
		return &""
	var fields: Dictionary = entry
	var named: Variant = fields.get("id")
	if CompanyAsk.is_id(named) and usable(from.vehicle(StringName(named))):
		return StringName(named)
	var key: Variant = fields.get("vehicle", fields.get("key"))
	if not CompanyAsk.is_id(key) or String(key).is_empty():
		return &""
	var candidates: Array[StringName] = CompanyTuning.STARTING_FLEET.duplicate()
	candidates.append_array(from.ids(CompanyCatalog.VEHICLES))
	for id: StringName in candidates:
		var definition: VehicleDefinition = from.vehicle(id)
		if usable(definition) and definition.fleet_key == StringName(key):
			return id
	return &""


## A definition a vehicle of the world is built from: valid (with a scene) and an id that is a node name and
## fits a trip event (CompanyTrips.id_fits()).
static func usable(definition: VehicleDefinition) -> bool:
	if definition == null or not definition.is_valid():
		return false
	var id: String = String(definition.id)
	return id.validate_node_name() == id and CompanyTrips.id_fits(definition.id)


## A node name per id, in order: the id itself, then "<id>_2", "<id>_3"... (or the next one free), so every name
## is unique and the same on every peer.
static func node_names(ids: Array[StringName]) -> Array[String]:
	var names: Array[String] = []
	var seen: Dictionary = {}
	for id: StringName in ids:
		var count: int = int(seen.get(id, 0)) + 1
		var node_name: String = String(id) if count == 1 else "%s_%d" % [id, count]
		while names.has(node_name):
			count += 1
			node_name = "%s_%d" % [id, count]
		seen[id] = count
		names.append(node_name)
	return names


## The middle of `at_shed`'s exit, in world space: the north wall's gate, at the inner edge of the floor of
## `company`'s stage (CompanyState.warehouse_stage; 0 with none). The playon (gate_of(), park_transform()) is
## measured from here.
static func exit_of(at_shed: Node3D, company: Object) -> Vector3:
	var stage: Variant = company.get(&"warehouse_stage") if company != null else 0
	var local := Vector3(0.0, 0.0, -WarehouseStages.floor_size_m(int(stage) if stage is int else 0).y * 0.5)
	return at_shed.to_global(local) if at_shed != null and at_shed.is_inside_tree() else local


## The middle of the playon's far edge, in world space: where CompanyTrips' gate stands (CompanyRoot), PLAYON_DEPTH_M
## past the outside of the exit's wall, its opening PLAYON_WIDTH_M wide. Outward is the shed's north (-Z).
static func gate_of(at_shed: Node3D, company: Object) -> Vector3:
	var facing: Basis = at_shed.global_basis.orthonormalized() if at_shed != null and at_shed.is_inside_tree() \
		else Basis.IDENTITY
	return exit_of(at_shed, company) + facing * Vector3(0.0, 0.0, -(CompanyShed.WALL_THICKNESS + PLAYON_DEPTH_M))


## CompanyTrips' gate for the shed `at_shed` of `company`: across the playon's far edge (gate_of()), PLAYON_WIDTH_M
## wide, outward the shed's north, the whole compound inside (yard_back_m() / yard_half_width_m()). The host's
## CompanyTrips watches it and a client's CompanyGateBrake builds the same one (D-0316.4): it is all the shed's
## transform and the company's stage, which the snapshot brings.
static func trip_gate(at_shed: Node3D, company: Object) -> TripGate:
	var north: Vector3 = -at_shed.global_basis.z if at_shed != null and at_shed.is_inside_tree() else Vector3.FORWARD
	var gate := TripGate.new(gate_of(at_shed, company), north, PLAYON_WIDTH_M)
	gate.set_yard(yard_back_m(company), yard_half_width_m(company))
	return gate


## How far behind the gate's line the compound reaches (the shed's floor and its two walls, then the playon), in
## metres: the TripGate yard's back edge.
static func yard_back_m(company: Object) -> float:
	var stage: Variant = company.get(&"warehouse_stage") if company != null else 0
	return WarehouseStages.floor_size_m(int(stage) if stage is int else 0).y + 2.0 * CompanyShed.WALL_THICKNESS \
		+ PLAYON_DEPTH_M


## Half of the compound's width: the playon's, or the shed's with its walls when that is wider.
static func yard_half_width_m(company: Object) -> float:
	var stage: Variant = company.get(&"warehouse_stage") if company != null else 0
	var shed_width: float = WarehouseStages.floor_size_m(int(stage) if stage is int else 0).x \
		+ 2.0 * CompanyShed.WALL_THICKNESS
	return maxf(PLAYON_WIDTH_M, shed_width) * 0.5


## Where the `index`-th vehicle parks, in world space: centred on the exit (exit_of()), the next ones side by side
## (+X, -X, then twice as far...), rear doors PARK_GAP_M past the outside of the north wall and facing the exit,
## nose away from the shed (a vehicle's front is its -Z, vehicle.gd).
static func park_transform(at_shed: Node3D, company: Object, index: int) -> Transform3D:
	var placed: bool = at_shed != null and at_shed.is_inside_tree()
	var facing: Basis = at_shed.global_basis.orthonormalized() if placed else Basis.IDENTITY
	var step: int = (maxi(index, 0) + 1) / 2
	var side: float = 1.0 if index % 2 == 1 else -1.0
	var back: float = CompanyShed.WALL_THICKNESS + PARK_GAP_M + FleetCargo.CARGO_BAY.end.z
	var offset := Vector3(PARK_SPACING_M * float(step) * side, PARK_HEIGHT_M, -back)
	return Transform3D(facing, exit_of(at_shed, company) + facing * offset)


## Host: `vehicle_id` is put back in its place in the playon (park_transform()), still, with whoever is at its wheel
## (the tow home, D-0307.1: CompanyTow). False for a vehicle that is not here or cannot be parked.
func send_home(vehicle_id: StringName) -> bool:
	var all: Array[Node3D] = vehicles()
	for index: int in range(all.size()):
		if StringName(all[index].name) == vehicle_id and all[index].has_method(&"park"):
			var company: Object = net.company if net != null else null
			all[index].call(&"park", park_transform(shed, company, index))
			return true
	return false


## Host: a vehicle under FALL_Y_M (it fell through a hole in the ground) is put back where it parks, still, and
## vehicle_recovered says which. Returns how many were put back. Done every physics tick.
func recover_fallen() -> int:
	var count: int = 0
	var all: Array[Node3D] = vehicles()
	for index: int in range(all.size()):
		var body: Node3D = all[index]
		if body.global_position.y >= FALL_Y_M or not body.has_method(&"park"):
			continue
		var company: Object = net.company if net != null else null
		body.call(&"park", park_transform(shed, company, index))
		vehicle_recovered.emit(StringName(body.name))
		count += 1
	return count


func _physics_process(_delta: float) -> void:
	if _host:
		recover_fallen()


## The host (solo too) builds now and gates every synchronizer until each peer acks it, closing a peer that leaves
## or whose world comes up again; a client builds once the host's snapshot is in, then acks.
func _hook(session: Node) -> void:
	if net == null or not is_inside_tree():
		return
	_host = net.is_host()
	_session = session
	set_physics_process(_host)
	net.event_applied.connect(_on_event)
	if not _host:
		net.company_state_restored.connect(_on_snapshot)
		return
	for gone: StringName in [&"peer_removed", &"peer_level_ready"]:
		if session != null and session.has_signal(gone):
			session.connect(gone, close_to)
	multiplayer.peer_disconnected.connect(close_to)
	build(net.company)


## `definition`'s vehicle named `node_name`, frozen, in VEHICLE_GROUP and with its NetRestThrottle, not in the
## tree yet (on the host its synchronizer gated: _filter()); null when its scene doesn't make a Node3D.
func _make(definition: VehicleDefinition, node_name: String) -> Node3D:
	var made: Node = definition.scene.instantiate()
	if not made is Node3D:
		made.free()
		return null
	var body := made as Node3D
	body.name = node_name
	if definition.variant != &"" and &"variant_id" in body:
		body.set(&"variant_id", definition.variant)
	if body is RigidBody3D:
		(body as RigidBody3D).freeze = true
	# Drives outside a delivery run too, on every peer (the client's input component reads it), and the host's
	# starts parked so vehicle.gd lets it go when somebody drives. Only vehicles that have them (vehicle.gd).
	if &"drivable_outside_run" in body:
		body.set(&"drivable_outside_run", true)
	if _host and body.has_method(&"park"):
		body.call(&"park")
	body.add_to_group(CompanyTrips.VEHICLE_GROUP)
	var sync := body.get_node_or_null(SYNC_PATH) as MultiplayerSynchronizer
	if sync == null:
		return body
	# About 30 poses a second on the move (D-2002.4), set before the throttle's _ready keeps it as its full rate.
	sync.replication_interval = CompanyTuning.FLEET_POSE_INTERVAL_SEC
	var throttle := NetRestThrottle.new()
	throttle.name = "NetRestThrottle"
	throttle.watched.assign(REST_WATCHED.filter(func(property: StringName) -> bool: return property in body))
	body.add_child(throttle)
	if _host:
		sync.add_visibility_filter(_filter(_opened, node_name))
	return body


## The filter of the synchronizer of the vehicle `node_name` on the host: a peer that acked it. Built in a static
## function, so it holds no reference to this node (as CompanyPackages' does).
static func _filter(peers: Dictionary, node_name: String) -> Callable:
	return func(peer: int) -> bool: return (peers.get(peer, {}) as Dictionary).has(node_name)


func _refresh(peer: int) -> void:
	for body: Node3D in vehicles():
		var sync := body.get_node_or_null(SYNC_PATH) as MultiplayerSynchronizer
		if sync != null and sync.is_inside_tree():
			sync.update_visibility(peer)


## Every peer: a shop_bought of a vehicle has changed the company's fleet, so the vehicle it adds is built here too
## (build() makes only the missing ones); a client then tells the host which it has.
func _on_event(_seq: int, kind: StringName, data: Dictionary) -> void:
	if kind != CompanyShopNet.BOUGHT:
		return
	var item: ShopItem = net.shop.find(data.get("item"))
	if item == null or item.kind != &"vehicle":
		return
	if build(net.company) > 0 and not _host:
		tell_host()


## Client: the host's snapshot is in, its company in this peer's CompanyState: the vehicles it lacks, then the
## host is told which it has (tell_host()).
func _on_snapshot(_snapshot_seq: int) -> void:
	build(net.company)
	tell_host()


## Client: tells the host every vehicle it has (_have_fleet), so their synchronizers may reach it. Nothing when it
## has none or isn't connected to a host (a client whose session never came up). Returns whether it was sent.
func tell_host() -> bool:
	var link: MultiplayerPeer = multiplayer.multiplayer_peer if is_inside_tree() else null
	if _host or link == null or link is OfflineMultiplayerPeer or multiplayer.is_server():
		return false
	if link.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	var names := PackedStringArray()
	for body: Node3D in vehicles():
		names.append(String(body.name))
	if names.is_empty():
		return false
	_have_fleet.rpc_id(1, names)
	return true


## Host, from a client: it has the vehicles `names` (tell_host()). Sent once per snapshot, so it spends the critical
## reserve (a lost one leaves those vehicles dead on that peer); checked and applied by ack().
@rpc("any_peer", "call_remote", "reliable")
func _have_fleet(names: PackedStringArray) -> void:
	if not _host or not RpcGuard.allow_critical_request(self) or names.size() > MAX_VEHICLES:
		return
	ack(RpcGuard.sender(self), names)

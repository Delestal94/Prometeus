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
## Parked side by side outside the shed's exit (park_transform()): rear doors PARK_GAP_M past the north wall,
## facing the exit, nose away from the shed, its centre past the gate's line, so nothing starts a trip at spawn.
##
## Parked, the host's (solo too) is frozen, as the delivery's level holds its truck before a run (vehicle.gd parks
## itself only during a run); a client's copy is frozen and drawn from the host's poses. While it stays put it
## sends its pose every NetRestThrottle.rest_interval (a child watching the pose and the driver's input), at the
## full rate again the tick it moves or someone drives: parked, it costs the shed's bandwidth next to nothing.
##
## How a client knows the fleet: the host's snapshot, whose company part is the host's CompanyState (fleet and
## stage). The client builds its vehicles when the snapshot is in (CompanyNet.company_state_restored), only the
## missing ones. Rule 10 of red-autoridad.md, its snapshot clause: on the host each vehicle's synchronizer starts
## invisible to every peer (a visibility filter, on top of CompanyInterest's flags, rule 11) and opens to a peer
## (open_to()) once a snapshot went to it (its world came up, NetworkManager.peer_level_ready, or it asked,
## CompanyNet.snapshot_requested), deferred to the end of that frame: the snapshot goes on the reliable channel
## the synchronizer's first packet (its path) takes too, so it lands, and builds the vehicle, before that packet.
## A synchronizer that reaches a peer before its node exists is never resolved there (package.gd's _enter_tree
## note). A peer that leaves is closed again.
##
## Not here yet (D-0302.2.b.2): a vehicle bought or sold mid-day (an event, acknowledged as CompanyPackages does:
## an event may land while a client waits for a snapshot), driving it (vehicle.gd drives only during a delivery
## run) and CompanyTrips.forget() for one that leaves mid-day. Closing the world frees them all, which is no
## vehicle leaving: the day is saved as it stood (D-2005). Nothing here names an autoload (lesson N-919).

const FleetCargo = preload("res://scripts/gameplay/fleet/fleet_cargo.gd")

## This node's name under World, the same on every peer.
const NODE_NAME: String = "Vehicles"
## Most vehicles one fleet builds (rule 5: a snapshot can't make a client build more).
const MAX_VEHICLES: int = 16
## Metres from the outside of the shed's north wall to a parked vehicle's rear doors: room for its ramp, and
## for the crew to carry the boxes from the exit.
const PARK_GAP_M: float = 2.0
## Metres between two vehicles parked side by side (a van is 2.2 m wide).
const PARK_SPACING_M: float = 3.5
## Height a parked vehicle is put at: the host's sits on the ground on its first tick (vehicle.gd
## _snap_to_ground, RIDE_HEIGHT 0.666 over it), a client's is moved by the host's first pose.
const PARK_HEIGHT_M: float = 0.7
## What a vehicle's NetRestThrottle watches, those its scene has: the pose it sends and the input its driver's
## client numbers (vehicle.gd net_input_seq), so it never rests while someone drives.
const REST_WATCHED: Array[StringName] = [&"net_position", &"net_rotation", &"net_input_seq"]
const SYNC_PATH: NodePath = ^"MultiplayerSynchronizer"

## The CompanyNet whose company the fleet is (on a client, once its snapshot is in) and, on the host, whose
## snapshots open the vehicles to each peer. Null: nothing is built.
var net: CompanyNet = null
## The shed whose exit they park at (CompanyRoot.shed).
var shed: Node3D = null
## Where the definitions are read: CompanyCatalog.load_all(), once, unless a test hands its own.
var catalog: CompanyCatalog = null

## Decided when hooked (_hook()): the host (solo too) builds now and gates; a client builds on its snapshot.
var _host: bool = false
## Host: the peers the vehicles' synchronizers reach (rule 10), {peer: true}.
var _opened: Dictionary = {}


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


## Host: the vehicles' synchronizers reach `peer` from now on (a snapshot went to it: it has every vehicle, or
## will before their first packet; rule 10). A peer that isn't connected stays closed.
func open_to(peer: int) -> void:
	if not _host or not is_inside_tree() or not multiplayer.get_peers().has(peer):
		return
	_opened[peer] = true
	_refresh(peer)


## Host: `peer` left (or is leaving): no vehicle's synchronizer reaches it until a snapshot opens them again.
func close_to(peer: int) -> void:
	if _opened.erase(peer) and is_inside_tree() and multiplayer.get_peers().has(peer):
		_refresh(peer)


## Host: the vehicles' synchronizers may reach `peer` (open_to()); CompanyInterest still decides by distance.
func is_open_to(peer: int) -> bool:
	return _opened.has(peer)


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
## `company`'s stage (CompanyState.warehouse_stage; 0 with none). It is where CompanyTrips' gate stands.
static func exit_of(at_shed: Node3D, company: Object) -> Vector3:
	var stage: Variant = company.get(&"warehouse_stage") if company != null else 0
	var local := Vector3(0.0, 0.0, -WarehouseStages.floor_size_m(int(stage) if stage is int else 0).y * 0.5)
	return at_shed.to_global(local) if at_shed != null and at_shed.is_inside_tree() else local


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


## The host (solo too) builds now, gates every synchronizer and opens it to each peer after its snapshot; a client
## builds once the host's snapshot is in.
func _hook(session: Node) -> void:
	if net == null or not is_inside_tree():
		return
	_host = net.is_host()
	if not _host:
		net.company_state_restored.connect(_on_snapshot)
		return
	if session != null and session.has_signal(&"peer_level_ready"):
		session.connect(&"peer_level_ready", _open_later)
	if session != null and session.has_signal(&"peer_removed"):
		session.connect(&"peer_removed", close_to)
	multiplayer.peer_disconnected.connect(close_to)
	net.snapshot_requested.connect(_open_later)
	build(net.company)
	# After CompanyNet's own deferred snapshot to the peers already up (_snapshot_ready_peers(), queued first).
	_open_ready_peers.call_deferred(session)


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
	body.add_to_group(CompanyTrips.VEHICLE_GROUP)
	var sync := body.get_node_or_null(SYNC_PATH) as MultiplayerSynchronizer
	if sync == null:
		return body
	var throttle := NetRestThrottle.new()
	throttle.name = "NetRestThrottle"
	throttle.watched.assign(REST_WATCHED.filter(func(property: StringName) -> bool: return property in body))
	body.add_child(throttle)
	if _host:
		sync.add_visibility_filter(_filter(_opened))
	return body


## The filter of a vehicle's synchronizer on the host: a peer opened to. Built in a static function, so it holds
## no reference to this node (as CompanyPackages' does).
static func _filter(peers: Dictionary) -> Callable:
	return func(peer: int) -> bool: return peers.has(peer)


func _refresh(peer: int) -> void:
	for body: Node3D in vehicles():
		var sync := body.get_node_or_null(SYNC_PATH) as MultiplayerSynchronizer
		if sync != null and sync.is_inside_tree():
			sync.update_visibility(peer)


## Host: a snapshot just went to `peer` (inside that signal): opened at the end of the frame, after it.
func _open_later(peer: int) -> void:
	open_to.call_deferred(peer)


## Host, once the world is up: the peers whose world was already up got CompanyNet's snapshot (deferred before
## this) and are opened to.
func _open_ready_peers(session: Node) -> void:
	if not is_inside_tree():
		return
	var ready_check: bool = session != null and session.has_method(&"is_peer_ready")
	for peer: int in multiplayer.get_peers():
		if not ready_check or bool(session.call(&"is_peer_ready", peer)):
			open_to(peer)


## Client: the host's snapshot is in, its company in this peer's CompanyState: the vehicles it lacks.
func _on_snapshot(_snapshot_seq: int) -> void:
	build(net.company)

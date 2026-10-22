class_name CompanyPackages
extends RefCounted
## The DeliveryPackage each taped box becomes, the same on every peer (expansion D-0715.b; contract
## docs/expansion-distritos/diseno/red-autoridad.md, section 2 row 15 and rule 10). It lives in
## CompanyTableNet as `packages`.
##
## box_sealed carries what the host decided: node_name (Package_<package_id>), pos and basis (where
## it stands, in the world's space), trap (an id of data/traps/), trap_intensity, absorption and
## quality. CompanyTableNet checks those fields here (fields_ok()) with the rest of the event, before
## anything changes, builds the package from the taped box this peer still holds (make():
## BoxToPackage.build) and, once the box is off the table, puts it in the world (put()). Where the
## event says so the host's word wins: node name and package id, trap, absorption, and quality and
## intensity in BoxToPackage.META_TRAP_PLAN (the plan BoxTrap would give, with the host's numbers).
##
## The packages go under `parent`, the same path on every peer, so each one's MultiplayerSynchronizer
## pairs up with the host's. Unset (the tables alone in a test, a world not up yet) nothing is built
## and box_sealed applies all the same.
##
## Rule 10, on the host: the synchronizer starts invisible to every peer and opens only after the
## event went out (deferred: CompanyNet sends it right after applying it), and only to the peers it
## went to (connected and with their world up, as CompanyNet's event targets). A peer that comes up
## later has no such node (live boxes aren't in the snapshot yet) and never gets its updates, nor
## does one that left or whose world came up again: a synchronizer that reaches a peer before its
## node is never resolved there (package.gd's _enter_tree note).
##
## `added` tells the world each package that went in (CompanyRoot freezes the host's in a cell
## that isn't loaded, D-0318.1). Nothing here sends anything or names an autoload: NetworkManager is
## reached by path, as CompanyNet does.

## Every peer, right after `package` went under `parent`, while box_sealed is being applied (no
## CompanyNet request may be made here).
signal added(package: DeliveryPackage)

const NODE_PREFIX: String = "Package_"
const TRAPS_DIR: String = "res://data/traps/"
const SYNC_PATH: NodePath = ^"MultiplayerSynchronizer"

## Where the packages go, the same path on every peer (CompanyRoot: World/Packages). Null: none is
## built.
var parent: Node = null

## Host: {package: {open: bool, peers: {peer: true}}} of every package whose synchronizer this
## filters (rule 10), until it leaves the tree.
var _gates: Dictionary = {}
## The MultiplayerAPI and session whose peers are watched (_watch()).
var _watched_api: MultiplayerAPI = null
var _watched_network: Node = null
static var _known_traps: Dictionary = {}
static var _traps_read: bool = false


## Node name of the package `package_id` becomes on every peer.
static func node_name_of(package_id: StringName) -> String:
	return NODE_PREFIX + String(package_id)


## A trap id that came over the network names a trap: exactly the name of one of data/traps/'s
## files (case included), never a path.
static func trap_known(trap: Variant) -> bool:
	if not CompanyAsk.is_id(trap):
		return false
	if not _traps_read:
		_traps_read = true
		# ResourceLoader lists exported files by their original names (no .remap).
		for file: String in ResourceLoader.list_directory(TRAPS_DIR):
			if file.ends_with(".tres") or file.ends_with(".res"):
				_known_traps[StringName(file.get_basename())] = true
	return _known_traps.has(StringName(trap))


## box_sealed's package fields, checked as data from the network (rule 5): node_name is
## Package_<package_id> and a valid node name, pos a finite Vector3 and basis a Basis that together
## make a pose a body can take (RpcGuard.finite_transform: finite, not flattened or blown up), trap
## a known one (trap_known()), quality in 0..QUALITY_MAX and trap_intensity and absorption in 0..1.
static func fields_ok(data: Dictionary, package_id: StringName) -> bool:
	var node_name: Variant = data.get("node_name")
	if not CompanyAsk.is_id(node_name) or String(node_name) != node_name_of(package_id):
		return false
	if String(node_name).validate_node_name() != String(node_name):
		return false
	var pos: Variant = data.get("pos")
	var basis: Variant = data.get("basis")
	if not (pos is Vector3 and basis is Basis and RpcGuard.finite_vec3(pos)):
		return false
	if not RpcGuard.finite_transform(Transform3D(basis, pos)):
		return false
	if not trap_known(data.get("trap")):
		return false
	return _in_range(data.get("quality"), CompanyTuning.QUALITY_MAX) \
		and _in_range(data.get("trap_intensity"), 1.0) and _in_range(data.get("absorption"), 1.0)


## True when packages are built here: a parent in the tree.
func active() -> bool:
	return parent != null and is_instance_valid(parent) and parent.is_inside_tree()


## True when `node_name` is free under the parent (or nothing is built here).
func can_add(node_name: String) -> bool:
	return not active() or not parent.has_node(NodePath(node_name))


## The package `box` (taped, the one this peer holds) becomes with box_sealed's checked `data`
## (fields_ok()), not in the tree yet; null when nothing is built here or the box makes none
## (BoxToPackage.build: no known product).
func make(box: PackedBox, data: Dictionary) -> DeliveryPackage:
	if not active():
		return null
	var package: DeliveryPackage = BoxToPackage.build(box)
	if package == null:
		return null
	var trap := load(TRAPS_DIR + String(data["trap"]) + ".tres") as TrapDefinition
	if trap == null:
		package.free()
		return null
	package.name = String(data["node_name"])
	package.package_id = StringName(data["package_id"])
	package.trap_definition = trap
	package.impact_absorption = float(data["absorption"])
	var plan: Dictionary = BoxTrap.plan(box, {})
	plan.merge({
		"trap_id": trap.id, "quality": float(data["quality"]),
		"intensity": float(data["trap_intensity"]),
		"level": BoxTrap.level(float(data["trap_intensity"])), "absorption": float(data["absorption"]),
	}, true)
	package.set_meta(BoxToPackage.META_TRAP_PLAN, plan)
	var at := Transform3D(data["basis"] as Basis, data["pos"] as Vector3)
	package.transform = (parent as Node3D).global_transform.affine_inverse() * at \
		if parent is Node3D else at
	return package


## Puts a package make() built under the parent and tells `added`. On the host its synchronizer is
## held back from every peer until the event went out (rule 10).
func put(package: DeliveryPackage) -> void:
	if package == null or not active():
		return
	if parent.multiplayer.is_server():
		_gate(package)
	parent.add_child(package)
	added.emit(package)


## Host: true when rule 10 lets the synchronizer of `package` reach `peer`: the event that made it
## went out, and to that peer (the filter it carries says so). False for a package not built here
## on the host. The package's other filters (package.gd: the peer's world is up) still apply.
func sends_to(package: Node, peer: int) -> bool:
	return _gates.has(package) and bool(_filter(_gates[package]).call(peer))


## Host: the synchronizer of `package` hidden from every peer but those the event goes to, and from
## those too until it went out (_open(), deferred).
func _gate(package: DeliveryPackage) -> void:
	var sync := package.get_node_or_null(SYNC_PATH) as MultiplayerSynchronizer
	if sync == null:
		return
	_watch()
	var gate: Dictionary = {"open": false, "peers": _event_peers()}
	sync.add_visibility_filter(_filter(gate))
	_gates[package] = gate
	package.tree_exited.connect(_drop_gate.bind(package), CONNECT_ONE_SHOT)
	_open.call_deferred(package)


## The visibility filter of a gated synchronizer: open, and to a peer the event went to. Built in a
## static function, so it holds no reference to this object (a package may outlive it a frame).
static func _filter(gate: Dictionary) -> Callable:
	return func(peer: int) -> bool:
		return bool(gate["open"]) and (gate["peers"] as Dictionary).has(peer)


func _drop_gate(package: Node) -> void:
	_gates.erase(package)


## Host: the event that made `package` went out; its synchronizer opens to the peers it went to.
## Untyped: the package may be gone by now (a freed object doesn't convert to DeliveryPackage).
func _open(package: Variant) -> void:
	if not is_instance_valid(package) or not _gates.has(package):
		return
	_gates[package]["open"] = true
	var sync := (package as Node).get_node_or_null(SYNC_PATH) as MultiplayerSynchronizer
	if sync != null and sync.is_inside_tree():
		sync.update_visibility()


## Host: the peers an event goes to now, as CompanyNet's targets: connected and, with a session,
## with their world up (is_peer_ready()).
func _event_peers() -> Dictionary:
	var peers: Dictionary = {}
	var peer: MultiplayerPeer = parent.multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return peers
	var network: Node = parent.get_node_or_null(^"/root/NetworkManager")
	var ready_check: bool = network != null and network.has_method(&"is_peer_ready")
	for id: int in parent.multiplayer.get_peers():
		if not ready_check or bool(network.call(&"is_peer_ready", id)):
			peers[id] = true
	return peers


## Host: hears peers leave (their copies are gone) and worlds come up (a fresh world has none of
## the packages made before), once per API and session.
func _watch() -> void:
	var api: MultiplayerAPI = parent.multiplayer
	if api != _watched_api:
		if _watched_api != null and _watched_api.peer_disconnected.is_connected(_forget_peer):
			_watched_api.peer_disconnected.disconnect(_forget_peer)
		_watched_api = api
		api.peer_disconnected.connect(_forget_peer)
	var network: Node = parent.get_node_or_null(^"/root/NetworkManager")
	if network != null and network != _watched_network and network.has_signal(&"peer_level_ready"):
		_watched_network = network
		network.connect(&"peer_level_ready", _forget_peer)


## Host: `peer` no longer holds any package made so far: none of their synchronizers reaches it. One
## still connected (its world came up again) is re-checked at once; one that left is already dropped
## by the replication (it has no visibility left to update).
func _forget_peer(peer: int) -> void:
	var connected: bool = active() and parent.multiplayer.get_peers().has(peer)
	for package: Variant in _gates.keys():
		if not is_instance_valid(package):
			_gates.erase(package)
			continue
		(_gates[package]["peers"] as Dictionary).erase(peer)
		var sync := (package as Node).get_node_or_null(SYNC_PATH) as MultiplayerSynchronizer
		if connected and sync != null and sync.is_inside_tree():
			sync.update_visibility(peer)


## An int or a finite float in 0..`top`.
static func _in_range(value: Variant, top: float) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and float(value) >= 0.0 and float(value) <= top

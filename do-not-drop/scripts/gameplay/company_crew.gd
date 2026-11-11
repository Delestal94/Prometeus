class_name CompanyCrew
extends RefCounted
## The crew of the company world (the D-0214 follow-up; out of company_root.gd in D-0254).
##
## Every player here is spawned by the host alone, through World/PlayerSpawner (the path LoadingScreen waits on):
## one player per peer whose world is up, at the first spot around SPAWN nobody stands on (free_spawn()), freed when
## its peer leaves the roster, after CompanyNet let go of what it held (D-2006). Solo, and a host alone, is a crew of
## one: the same player at SPAWN it always was. Every peer's player is one of the crew (GROUP, join()), so the host
## has an anchor for each one and knows who is in the shed (in_shed(), D-0316.1).
##
## CompanyRoot holds one (CompanyRoot.crew) and keeps the old names as aliases (CREW_GROUP, SPAWN, crew_spawn(),
## free_spawn(), join_crew()). The root's `player`, this peer's own, and its build mode's are set here as the spawns
## land; no node of its own besides the spawner.

const PLAYER_SCENE: String = "res://scenes/gameplay/player/player.tscn"
const Ride = preload("res://scripts/gameplay/player/player_ride.gd")
## Where the player appears: on the dock floor, facing the shed (north, -Z). The first of the
## roster (the host, solo too) stands right here; the rest side by side (spawn_spot()).
const SPAWN: Vector3 = Vector3(0.0, 1.0, 2.6)
## Meters between two crew members spawned side by side along X: a player's capsule is narrower,
## so nobody lands on anybody, and a crew of 8 spans 6.4 m of the starting shed's 12.
const SPACING: float = 0.8
## A spawn spot is taken while a crew member stands closer than this share of SPACING to it.
const CLEARANCE: float = 0.9
## Spawn spots tried before giving up and using the last (8 players fill the first 8).
const MAX_SLOTS: int = 16
## The group of every player here: this is the company, there is no vehicle to practise for
## (the delivery practice card, player_cargo_care.gd, checks it).
const GROUP: StringName = &"company_crew"
## Every player node is named this and its peer id (player.gd takes its authority from it).
const PLAYER_PREFIX: String = "Player_"

## Every peer: where the host's spawns of the crew land (World/PlayerSpawner, as in the delivery).
var spawner: MultiplayerSpawner

var _root: CompanyRoot
var _world: Node3D
## Decided when the world comes up: this peer is the host (solo too) and spawns the crew. A client
## whose session ended later stays a client here: it spawns nothing while the menu loads.
var _spawns: bool = false
## Callable() -> bool: the world stopped (a client whose host is gone): nothing spawns any more.
var _stopped: Callable = Callable()


## The crew's spawner under `world`, on every peer at the same path so the host's spawns land on each client,
## and the session's news of peers coming and going. The host (solo too) spawns its own player now and the
## others' as their worlds come up (sync()); a client takes its own when it arrives (_on_spawned()).
static func add_to(root: CompanyRoot, world: Node3D, stopped: Callable) -> CompanyCrew:
	var crew := CompanyCrew.new()
	crew._root = root
	crew._world = world
	crew._stopped = stopped
	crew.spawner = MultiplayerSpawner.new()
	crew.spawner.name = "PlayerSpawner"
	crew.spawner.spawn_path = NodePath("..")
	crew.spawner.spawn_function = crew._create_member
	world.add_child(crew.spawner)
	crew.spawner.spawned.connect(crew._on_spawned)
	crew._spawns = root.net != null and root.net.is_host()
	var session: NetSession = root.session
	if session != null and not session.peer_level_ready.is_connected(crew._on_changed):
		session.peer_level_ready.connect(crew._on_changed)
		session.roster_changed.connect(crew._on_changed)
	crew.sync()
	return crew


## The `slot`-th spawn spot: the first at SPAWN, the rest SPACING apart to either side in
## turn (+X, -X, then twice as far...).
static func spawn_spot(slot: int) -> Vector3:
	var step: int = (maxi(slot, 0) + 1) / 2
	var side: float = 1.0 if slot % 2 == 1 else -1.0
	return SPAWN + Vector3(SPACING * float(step) * side, 0.0, 0.0)


## The first spawn spot (spawn_spot(0), 1, 2...) with nobody of `taken` (where the crew stands, in
## the world's space) closer than CLEARANCE across the floor: a newcomer never lands on
## someone, whoever left before it. The last spot tried when every one is taken.
static func free_spawn(taken: Array[Vector3]) -> Vector3:
	var spot: Vector3 = SPAWN
	for slot: int in range(MAX_SLOTS):
		spot = spawn_spot(slot)
		var clear: bool = true
		for at: Vector3 in taken:
			if Vector2(at.x - spot.x, at.z - spot.z).length() < SPACING * CLEARANCE:
				clear = false
				break
		if clear:
			return spot
	return spot


## Every player of the company's world, before it enters the tree: one of the crew (GROUP),
## sending its pose at the shed's rate while on foot (D-2002.3, CompanyTuning.SHED_POSE_RATE_HZ),
## at SEATED_POSE_RATE_HZ seated (D-2002.4) and at the game's in its bay. Only the owner's copy sends.
static func join(crew_member: Player) -> void:
	crew_member.add_to_group(GROUP)
	Ride.set_on_foot_pose_rate(crew_member, CompanyTuning.SHED_POSE_RATE_HZ)
	Ride.set_seated_pose_rate(crew_member, CompanyTuning.SEATED_POSE_RATE_HZ)


## The session's roster online, else (solo, a host's room closed) this peer alone.
static func ids_of(session: NetSession, api: MultiplayerAPI) -> Array[int]:
	var ids: Array[int] = []
	if session != null and is_instance_valid(session) and session.is_online():
		ids.assign(session.peer_ids)
	else:
		ids.append(api.get_unique_id())
	return ids


## Host (DayCycle.crew_in_shed, S4): someone of `root`'s crew is in `shed` (CompanyShed.holds()),
## so the shed's minute runs. A player is where its reach starts (Player.reach_origin(), as
## CompanyNet's rule 4): its seat while seated, since the body stays where it sat down and only its
## visual rides along, and on the host a remote one's newest pose. Only the players of the root's
## multiplayer count, as in CompanyInterest; one whose peer left is out of the tree, or on its way
## out, and doesn't. With no shed, or nobody spawned yet (the world just up), it is yes: nothing
## freezes before there is someone to leave.
static func in_shed(root: Node, shed: CompanyShed) -> bool:
	if not root.is_inside_tree() or shed == null or not is_instance_valid(shed) or not shed.is_inside_tree():
		return true
	var anyone: bool = false
	for node: Node in root.get_tree().get_nodes_in_group(GROUP):
		var member := node as Node3D
		if member == null or not member.is_inside_tree() or member.is_queued_for_deletion():
			continue
		if member.multiplayer != root.multiplayer:
			continue
		var at: Vector3 = (member as Player).reach_origin() if member is Player else member.global_position
		if shed.holds(at):
			return true
		anyone = true
	return not anyone


static func player_name(id: int) -> String:
	return PLAYER_PREFIX + str(id)


## Host (solo too): a player for every peer on the roster whose world is up, in roster order, at
## the first spawn spot nobody stands on (free_spawn()); a player whose peer left the roster goes
## first, so its spot is free again. It goes after CompanyNet let go of what it held: the session
## tells peer_removed (CompanyNet drops the units at the player's feet, D-2006) before
## roster_changed, and the node is only freed at the end of the frame.
func sync() -> void:
	if not _spawns or (_stopped.is_valid() and _stopped.call()) or not _root.is_inside_tree() or spawner == null:
		return
	var session: NetSession = _root.session
	var ids: Array[int] = ids_of(session, _root.multiplayer)
	for child: Node in _world.get_children():
		var child_name: String = String(child.name)
		if child_name.begins_with(PLAYER_PREFIX) and not ids.has(int(child_name.trim_prefix(PLAYER_PREFIX))):
			child.queue_free()
	for id: int in ids:
		if _world.has_node(NodePath(player_name(id))):
			continue
		if session != null and not session.is_peer_ready(id):
			continue
		spawner.spawn({"peer_id": id, "position": free_spawn(_spots())})
	_refresh_local_player()


## Every peer, from the host's spawn data {peer_id, position}: a player driven by that peer, one
## of the crew before it enters the tree (join()). A position that isn't a finite Vector3
## falls back to SPAWN.
func _create_member(data: Variant) -> Node:
	var spawn: Dictionary = data if data is Dictionary else {}
	var id: int = int(spawn.get("peer_id", 0)) if typeof(spawn.get("peer_id")) == TYPE_INT else 0
	var at: Variant = spawn.get("position")
	var member := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	member.name = player_name(id)
	member.position = at if at is Vector3 and RpcGuard.finite_vec3(at) else SPAWN
	if id > 0:
		member.set_multiplayer_authority(id)
	join(member)
	return member


## Where each player of this world stands, in the world's space; those on their way out left out.
func _spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for child: Node in _world.get_children():
		var member := child as Player
		if member != null and member.is_in_group(GROUP) and not member.is_queued_for_deletion():
			spots.append(_world.to_local(member.global_position))
	return spots


## A peer's world is up (peer_level_ready: its id) or the roster changed (roster_changed: the ids).
func _on_changed(_why: Variant) -> void:
	sync()


## A client: a spawn from the host landed; its own player is the one it drives.
func _on_spawned(_member: Node) -> void:
	_refresh_local_player()


## The root's `player` is this peer's own, wherever it came from; the build mode keeps it still while it
## builds (ShedBuilder.player). Both let go of it as it leaves the tree (_on_local_player_leaving()).
func _refresh_local_player() -> void:
	var own: Node3D = _world.get_node_or_null(NodePath(player_name(_root.multiplayer.get_unique_id()))) as Node3D
	if own != null and own.is_queued_for_deletion():
		own = null
	if own == _root.player:
		return
	_root.player = own
	if own != null:
		own.tree_exiting.connect(_on_local_player_leaving.bind(own), CONNECT_ONE_SHOT)
	if _root.builder != null:
		_root.builder.player = own


## This peer's own player leaves the tree: the host despawned it, the session that spawned it ended
## or the world closes. Neither the root's `player` nor the build mode keeps pointing at a node about to be
## freed. Not the spawner's despawned: that fires while the node is still in place.
func _on_local_player_leaving(leaving: Node3D) -> void:
	if _root.player != leaving:
		return
	_root.player = null
	if _root.builder != null and is_instance_valid(_root.builder):
		_root.builder.player = null

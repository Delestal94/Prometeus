extends Node
## Session setup and the peer roster. Host-authoritative, per
## docs/requerimientos-tecnicos.md: clients send input, the host simulates,
## the result is replicated.
##
## Two transports, same Godot MultiplayerPeer interface underneath:
##
##   STEAM -- a Steam lobby relayed by Valve. No port forwarding, no firewall
##            prompts, NAT punch-through handled for us. This is how the game
##            ships, and how PEAK and Lethal Company do it.
##   ENET  -- a plain UDP socket. Kept for local development, where Steam P2P
##            is awkward (two instances on one machine share one account) and
##            127.0.0.1 is simply easier.
##
## Everything Steam is reached through Engine.get_singleton and
## ClassDB.instantiate rather than by name. Naming SteamMultiplayerPeer
## directly would stop this script from compiling on any machine without the
## GodotSteam extension installed -- including CI and the headless tests.
##
## Offline counts as a session of one. The level spawns players the same way
## either way, so single-player isn't a separate code path that silently rots
## while the networked one gets all the attention.

enum Transport { AUTO, STEAM, ENET }

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 8
const HOST_ID: int = 1
## Increment whenever peers can no longer share the same replicated scene or
## handshake. Both sides exchange it before either starts scene replication.
const PROTOCOL_VERSION: int = 2
## Valve's sample app. Fine for development -- it gives us P2P and NAT
## punch-through without owning an app id -- but not for shipping.
const APP_ID_SPACEWAR: int = 480

signal roster_changed(peer_ids: Array)
signal session_ready(is_host: bool)
signal session_failed(reason: String)

## Force a transport for testing; AUTO picks Steam when it's available.
var transport: Transport = Transport.AUTO
var active_transport: Transport = Transport.ENET
var lobby_id: int = 0
var peer_ids: Array[int] = [HOST_ID]
## The number every peer's procedural world is built from.
##
## route.gd and route_streamer.gd used to call _rng.randomize() on each
## machine independently, which meant **every player got a different road**:
## the van's transform replicates from the host, so a client watched it
## drive through houses that weren't there and off a road that ran somewhere
## else entirely. Nothing caught it because both sides individually worked.
## The host picks the seed and hands it to each joiner before they load the
## level; 0 means "no session decided one", i.e. solo play, where randomize()
## is exactly right.
var world_seed: int = 0
## How many delivery houses this session's route has (docs/tareas-nacho.md
## #104). The route used to work it out from each machine's own roster, but a
## client's roster starts as just [host, itself], so from three players up
## every peer built a different number of houses. The host's route decides it
## once, the first time it builds, and each joiner gets it with the seed; a
## host restart keeps it, since clients don't reload their world. 0 means
## "not decided yet" (and always, playing solo).
var world_house_count: int = 0
## Traps this session's depot leaves off the shelves: the ones the *host's*
## profile hasn't unlocked yet (UnlockManager.locked_traps()), fixed when the
## room is created and handed to each joiner. Every peer has to shelve the
## same boxes -- they're the same replicated nodes -- so a client's own
## profile doesn't get a say. Only read while world_seed != 0; solo play asks
## UnlockManager directly.
var world_locked_traps: Array = []
## The host profile's completed-run count drives order difficulty. Like the
## locked list, it must be shared: a joiner's local profile may be different.
var world_completed_runs: int = 0
## How long a joiner may take to receive the host's world and load it before
## the connection is dropped (Godot's auth timeout). Long enough for a slow
## level load, short enough that a host on another version doesn't leave the
## joiner staring at "Conectando…" for a minute.
const JOIN_HANDSHAKE_TIMEOUT: float = 8.0
var _awaiting_handshake: bool = false
## The level the session plays in. The host records it whenever its own
## level is up, so a joiner arriving mid-reload still gets the right one.
var session_scene: String = ""
const DEFAULT_LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"
const LEVEL_SCENES: Array[String] = ["res://scenes/gameplay/level_base.tscn", "res://scenes/gameplay/level_endless.tscn"]

## Host only: peers whose copy of the current level is loaded. Players are
## only spawned to (and their state only sent to) those, so a host restart
## -- everyone reloads, each at their own pace -- never sends a spawn to a
## level that isn't there yet. The host itself always counts.
var _ready_peers: Array[int] = [HOST_ID]
## A peer's level is up and can take spawns and the session's state (host).
signal peer_level_ready(peer_id: int)
## Why the last session ended, for the menu to show once it's back up (a
## failure while in a level has only the level's overlay listening).
var _failure_message: String = ""

var _steam: Object = null
var _steam_ready: bool = false
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
## A Steam lobby to join as soon as the menu is up: an invite accepted from
## outside the menu, or the game launched by one (+connect_lobby <id>).
var _pending_lobby: int = 0


## Steam starts with the game, not with the first "Crear sala": until it was
## initialised Steam didn't know the game was open, so a friend showed as
## not playing, couldn't be invited, and "Unirse a la partida" from the
## friends list went nowhere -- they had to press "Crear sala" first just to
## be found. Headless runs (tests, CI) leave the local Steam client alone.
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	steam_available()
	var args: PackedStringArray = OS.get_cmdline_args()
	var at: int = args.find("+connect_lobby")
	if at >= 0 and at + 1 < args.size():
		_pending_lobby = int(args[at + 1])


## The main menu asks once it's ready; 0 means nothing to join.
func take_pending_lobby() -> int:
	var lobby: int = _pending_lobby
	_pending_lobby = 0
	return lobby


func _process(_delta: float) -> void:
	if _steam != null and _steam.has_method(&"run_callbacks"):
		_steam.call(&"run_callbacks")


## True once a real peer is attached. Offline play leaves this false.
func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer is not OfflineMultiplayerPeer


func is_host() -> bool:
	return not is_online() or multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id() if is_online() else HOST_ID


## The address friends on the same network should type into "Unirse", or ""
## when this machine has no private LAN address at all.
func lan_address() -> String:
	for address: String in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10."):
			return address
		if address.begins_with("172."):
			var second: int = int(address.get_slice(".", 1))
			if second >= 16 and second <= 31:
				return address
	return ""


## Whether this build can actually use Steam right now: the extension is
## present, and Steam itself is running and logged in.
func steam_available() -> bool:
	if not ClassDB.class_exists(&"SteamMultiplayerPeer"):
		return false
	return _init_steam()


func chosen_transport() -> Transport:
	if transport == Transport.AUTO:
		return Transport.STEAM if steam_available() else Transport.ENET
	return transport


func host_session(port: int = DEFAULT_PORT) -> Error:
	_ensure_signals()
	# Decided once, here, so every joiner gets the same one no matter which
	# transport they arrive on. Never 0: that value means "solo".
	world_seed = randi() | 1
	world_house_count = 0
	var unlocks: Node = get_node_or_null(^"/root/UnlockManager")
	world_locked_traps = unlocks.call(&"locked_traps") if unlocks != null else []
	world_completed_runs = int(unlocks.get(&"completed_runs")) if unlocks != null else 0
	if chosen_transport() == Transport.STEAM:
		return _host_steam()
	return _host_enet(port)


## Steam takes a lobby id, ENet takes an address. Both arrive here as text so
## the UI doesn't have to care which transport is live.
func join_session(target: String, port: int = DEFAULT_PORT) -> Error:
	_ensure_signals()
	if chosen_transport() == Transport.STEAM:
		return _join_steam(int(target))
	return _join_enet(target, port)


func leave_session() -> void:
	_end_session()
	roster_changed.emit(peer_ids.duplicate())


## Everything a session set up, undone: the next solo run must not keep
## building the old room's world (its seed, house count, locked traps), and
## Steam must not keep us in its lobby. The peer becomes an offline one, not
## null: with none at all every authority check spammed "No multiplayer peer
## is assigned" for as long as the level stayed up.
func _end_session() -> void:
	session_scene = ""
	world_seed = 0
	world_house_count = 0
	world_locked_traps = []
	world_completed_runs = 0
	_awaiting_handshake = false
	_restart_pending = false
	_ready_peers = [HOST_ID]
	if lobby_id != 0 and _steam != null:
		_steam.call(&"leaveLobby", lobby_id)
	lobby_id = 0
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer is not OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer_ids = [HOST_ID]


## The reason the last session ended, once (the menu shows it when it's back).
func take_failure_message() -> String:
	var message: String = _failure_message
	_failure_message = ""
	return message


# --- ENet ------------------------------------------------------------------

func _host_enet(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		session_failed.emit("No se pudo abrir el puerto %d." % port)
		return error
	multiplayer.multiplayer_peer = peer
	active_transport = Transport.ENET
	peer_ids = [HOST_ID]
	roster_changed.emit(peer_ids.duplicate())
	session_ready.emit(true)
	return OK


func _join_enet(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address, port)
	if error != OK:
		session_failed.emit("No se pudo conectar a %s:%d." % [address, port])
		return error
	multiplayer.multiplayer_peer = peer
	active_transport = Transport.ENET
	return OK


# --- Steam -----------------------------------------------------------------

func _init_steam() -> bool:
	if _steam_ready:
		return true
	if not Engine.has_singleton(&"Steam"):
		return false
	_steam = Engine.get_singleton(&"Steam")
	var response: Variant = _steam.call(&"steamInitEx") if _steam.has_method(&"steamInitEx") else _steam.call(&"steamInit")
	# steamInitEx reports a dictionary; the older steamInit a plain status.
	var status: int = int(response.get("status", 0)) if response is Dictionary else int(response)
	if status != 0:
		return false
	# A successful status here only means steam_appid.txt was readable and
	# the SDK found a locally cached Steam id -- it does NOT mean the Steam
	# client is actually running. Trusting it alone picks STEAM as the
	# transport even with Steam closed, and every lobby call after that
	# just hangs forever with nothing to answer it. isSteamRunning() checks
	# for the live client process, which is what we actually need.
	if _steam.has_method(&"isSteamRunning") and not bool(_steam.call(&"isSteamRunning")):
		return false
	_steam_ready = true
	_connect_steam_signals()
	return true


func _connect_steam_signals() -> void:
	if _steam.has_signal(&"lobby_created") and not _steam.is_connected(&"lobby_created", _on_lobby_created):
		_steam.connect(&"lobby_created", _on_lobby_created)
	if _steam.has_signal(&"lobby_joined") and not _steam.is_connected(&"lobby_joined", _on_lobby_joined):
		_steam.connect(&"lobby_joined", _on_lobby_joined)
	# Accepting an invite from the friends list is the way people actually
	# join a game like this, so it has to work without any menu.
	if _steam.has_signal(&"join_requested") and not _steam.is_connected(&"join_requested", _on_join_requested):
		_steam.connect(&"join_requested", _on_join_requested)


func _host_steam() -> Error:
	if not _init_steam():
		session_failed.emit("Steam no está disponible.")
		return ERR_UNAVAILABLE
	active_transport = Transport.STEAM
	# Friends-only: this is a game you play with people you know, and it
	# saves us moderating public lobbies we have no way to moderate.
	_steam.call(&"createLobby", 1, MAX_PLAYERS)
	return OK


func _join_steam(target_lobby: int) -> Error:
	if not _init_steam():
		session_failed.emit("Steam no está disponible.")
		return ERR_UNAVAILABLE
	if target_lobby == 0:
		session_failed.emit("Falta el id de la sala.")
		return ERR_INVALID_PARAMETER
	active_transport = Transport.STEAM
	_steam.call(&"joinLobby", target_lobby)
	return OK


func _on_lobby_created(status: int, created_lobby_id: int) -> void:
	if status != 1:
		session_failed.emit("No se pudo crear la sala de Steam.")
		return
	lobby_id = created_lobby_id
	var peer: Object = ClassDB.instantiate(&"SteamMultiplayerPeer")
	peer.call(&"create_host", 0)
	peer.set(&"server_relay", true)
	multiplayer.multiplayer_peer = peer as MultiplayerPeer
	peer_ids = [HOST_ID]
	roster_changed.emit(peer_ids.duplicate())
	session_ready.emit(true)


func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:
		_fail("full" if response == 4 else "No se pudo entrar a la sala.")
		return
	lobby_id = joined_lobby_id
	var owner_id: int = int(_steam.call(&"getLobbyOwner", joined_lobby_id))
	if owner_id == int(_steam.call(&"getSteamID")):
		return  # The host already made its peer in _on_lobby_created.
	var peer: Object = ClassDB.instantiate(&"SteamMultiplayerPeer")
	peer.call(&"create_client", owner_id, 0)
	# A client only has a connection to the host, so everything it sends to
	# another client (its own movement, above all) has to go through the host.
	# With relay off on this side, Godot tried to send it straight to the
	# other client, and those packets were dropped: from three players up,
	# each client saw the others stuck where they spawned, a metre in the air,
	# and the boxes they carried floating on their own.
	peer.set(&"server_relay", true)
	multiplayer.multiplayer_peer = peer as MultiplayerPeer


## Accepting an invite (or "Unirse a la partida") works from anywhere: in the
## menu it joins right away; playing solo or in another room, that's left
## and the menu takes the join over, since it's what loads the host's level.
func _on_join_requested(invited_lobby_id: int, _friend_id: int) -> void:
	if invited_lobby_id == lobby_id and is_online():
		return
	if is_online():
		leave_session()
	transport = Transport.STEAM
	var scene: Node = get_tree().current_scene
	if scene != null and scene.scene_file_path == MAIN_MENU_SCENE:
		scene.call(&"join_steam_lobby", invited_lobby_id)
		return
	_pending_lobby = invited_lobby_id
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(MAIN_MENU_SCENE)


# --- Roster ----------------------------------------------------------------

## Hooked up when a session starts rather than in _ready: this autoload runs
## before the tree is fully standing, and the MultiplayerAPI we'd reach that
## early isn't reliably the one in use later.
func _ensure_signals() -> void:
	multiplayer.auth_callback = _receive_auth
	multiplayer.auth_timeout = JOIN_HANDSHAKE_TIMEOUT
	if not multiplayer.peer_authenticating.is_connected(_peer_authenticating):
		multiplayer.peer_authenticating.connect(_peer_authenticating)
		multiplayer.peer_authentication_failed.connect(_auth_failed)
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## On the host a peer only connects once its authentication completed, which
## it does after loading the level (level_ready()): it can take spawns now.
func _on_peer_connected(id: int) -> void:
	if not peer_ids.has(id):
		peer_ids.append(id)
	if multiplayer.is_server() and not _ready_peers.has(id):
		_ready_peers.append(id)
	roster_changed.emit(peer_ids.duplicate())
	if multiplayer.is_server():
		peer_level_ready.emit(id)


func _on_peer_disconnected(id: int) -> void:
	peer_ids.erase(id)
	_ready_peers.erase(id)
	roster_changed.emit(peer_ids.duplicate())


func _on_connected_to_server() -> void:
	var id: int = multiplayer.get_unique_id()
	if not peer_ids.has(HOST_ID):
		peer_ids.append(HOST_ID)
	if not peer_ids.has(id):
		peer_ids.append(id)
	roster_changed.emit(peer_ids.duplicate())


func is_peer_ready(id: int) -> bool:
	return not is_online() or id == HOST_ID or _ready_peers.has(id)


# Hold scene replication until the joiner's level exists. Authentication
# packets are the only traffic Godot permits before both sides complete_auth.
func _peer_authenticating(id: int) -> void:
	if multiplayer.is_server():
		multiplayer.send_auth(id, var_to_bytes({"version": PROTOCOL_VERSION, "seed": world_seed,
			"houses": world_house_count, "locked": world_locked_traps, "runs": world_completed_runs,
			"scene": _current_level_scene()}))
	elif id != HOST_ID:
		multiplayer.complete_auth(id)


## The level to hand a joiner: the one up right now, else the last one this
## host had up (it may be mid-reload), else the default.
func _current_level_scene() -> String:
	var scene: Node = get_tree().current_scene
	var path: String = scene.scene_file_path if scene != null else ""
	if path in LEVEL_SCENES:
		return path
	return session_scene if session_scene in LEVEL_SCENES else DEFAULT_LEVEL_SCENE


func _handshake_error(state: Variant) -> String:
	if not state is Dictionary:
		return "version"
	if int(state.get("version", -1)) != PROTOCOL_VERSION:
		return "version"
	if not state.has_all(["seed", "houses", "locked", "runs", "scene"]):
		return "connection"
	if String(state.scene) not in LEVEL_SCENES:
		return "connection"
	return ""


func _ready_reply_error(reply: Variant) -> String:
	if not reply is Dictionary or not bool(reply.get("ready", false)):
		return "version"
	return "" if int(reply.get("version", -1)) == PROTOCOL_VERSION else "version"


func _receive_auth(id: int, data: PackedByteArray) -> void:
	if multiplayer.is_server():
		# Protocol 0 sent the raw word "ready". Recognize it without asking
		# bytes_to_var() to parse arbitrary UTF-8, then reject it explicitly.
		if data.get_string_from_utf8() == "ready":
			multiplayer.send_auth(id, var_to_bytes({"failure": "version"}))
			return
		var reply: Variant = bytes_to_var(data)
		if _ready_reply_error(reply).is_empty():
			multiplayer.complete_auth(id)
		else:
			multiplayer.send_auth(id, var_to_bytes({"failure": "version"}))
		return
	if id != HOST_ID:
		return
	var state: Variant = bytes_to_var(data)
	if state is Dictionary and state.has("failure"):
		_fail(String(state.failure))
		return
	var handshake_error: String = _handshake_error(state)
	if not handshake_error.is_empty():
		_fail(handshake_error)
		return
	world_seed = int(state.seed)
	world_house_count = int(state.houses)
	world_locked_traps = state.locked
	world_completed_runs = int(state.runs)
	session_scene = String(state.scene)
	# The joiner always loads the level first and only then says "ready"
	# (level_ready(), from the level itself): completing before that let the
	# host's spawns arrive at a menu and the joiner saw no players at all.
	_awaiting_handshake = true
	session_ready.emit(false)


## Every level calls this once it's up (deferred from its _ready).
func level_ready() -> void:
	if not is_online():
		return
	if is_host():
		var scene: Node = get_tree().current_scene
		if scene != null and scene.scene_file_path in LEVEL_SCENES:
			session_scene = scene.scene_file_path
		if _restart_pending:
			_restart_pending = false
			_remote_restart.rpc(world_house_count, world_completed_runs)
		return
	if _awaiting_handshake:
		_awaiting_handshake = false
		multiplayer.send_auth(HOST_ID, var_to_bytes({"ready": true, "version": PROTOCOL_VERSION}))
		multiplayer.complete_auth(HOST_ID)
		return
	# Already in the session: back from a host restart.
	_report_level_ready.rpc_id(HOST_ID)


@rpc("any_peer", "call_remote", "reliable")
func _report_level_ready() -> void:
	if not multiplayer.is_server():
		return
	var id: int = multiplayer.get_remote_sender_id()
	if not peer_ids.has(id):
		return
	if not _ready_peers.has(id):
		_ready_peers.append(id)
	peer_level_ready.emit(id)


# --- Restart -----------------------------------------------------------------

## Set by begin_restart(), consumed by the host's reloaded level (level_ready).
var _restart_pending: bool = false


## Host only, right before reloading its level: every client reloads too,
## once the host's new level is up (level_ready() sends it then, so nothing
## is spawned into the old one). The crew may have grown since the level was
## built, so the house count is decided afresh.
func begin_restart() -> void:
	if not is_online() or not is_host():
		return
	_restart_pending = true
	_ready_peers = [HOST_ID]
	world_house_count = 0
	var unlocks: Node = get_node_or_null(^"/root/UnlockManager")
	world_completed_runs = int(unlocks.get(&"completed_runs")) if unlocks != null else world_completed_runs


## A client drops its run and reloads, then reports back (level_ready()).
## Until now only the host reloaded: clients were left on the results screen,
## behind a depot door only their copy had closed, unable to drive.
@rpc("authority", "call_remote", "reliable")
func _remote_restart(house_count_value: int, completed_runs_value: int) -> void:
	world_house_count = house_count_value
	world_completed_runs = completed_runs_value
	var run: Node = get_node_or_null(^"/root/RunManager")
	if run != null:
		run.call(&"reset_run")
	get_tree().paused = false
	get_tree().reload_current_scene.call_deferred()


func _auth_failed(_id: int) -> void:
	if is_host():
		return
	_fail("timeout")


func _on_connection_failed() -> void:
	_fail("timeout")


## The host is gone. The roster isn't announced as shrunk to "just us" any
## more: that made the level think it was now the host and delete every
## player, leaving a cameraless view behind the disconnect overlay.
func _on_server_disconnected() -> void:
	_fail("Se cortó la conexión con el anfitrión.")


## Ends the session and says why, to whoever listens now (the menu, or the
## level's overlay) and to the menu once it's back up, if it wasn't then.
func _fail(reason: String) -> void:
	_end_session()
	_failure_message = reason
	session_failed.emit(reason)

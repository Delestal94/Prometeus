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
## How long a joiner waits for the host to hand over that seed before giving
## up. Joining without it would build the wrong world, so this is a real
## failure to report, not something to paper over.
const JOIN_HANDSHAKE_TIMEOUT: float = 8.0
var _awaiting_handshake: bool = false

var _steam: Object = null
var _steam_ready: bool = false


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
	world_seed = 0
	world_house_count = 0
	world_locked_traps = []
	_awaiting_handshake = false
	if lobby_id != 0 and _steam != null:
		_steam.call(&"leaveLobby", lobby_id)
		lobby_id = 0
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peer_ids = [HOST_ID]
	roster_changed.emit(peer_ids.duplicate())


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
		session_failed.emit("No se pudo entrar a la sala.")
		return
	lobby_id = joined_lobby_id
	var owner_id: int = int(_steam.call(&"getLobbyOwner", joined_lobby_id))
	if owner_id == int(_steam.call(&"getSteamID")):
		return  # The host already made its peer in _on_lobby_created.
	var peer: Object = ClassDB.instantiate(&"SteamMultiplayerPeer")
	peer.call(&"create_client", owner_id, 0)
	multiplayer.multiplayer_peer = peer as MultiplayerPeer


func _on_join_requested(invited_lobby_id: int, _friend_id: int) -> void:
	join_session(str(invited_lobby_id))


# --- Roster ----------------------------------------------------------------

## Hooked up when a session starts rather than in _ready: this autoload runs
## before the tree is fully standing, and the MultiplayerAPI we'd reach that
## early isn't reliably the one in use later.
func _ensure_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(id: int) -> void:
	if not peer_ids.has(id):
		peer_ids.append(id)
	roster_changed.emit(peer_ids.duplicate())
	if multiplayer.is_server():
		_accept_joiner.rpc_id(id, world_seed, world_house_count, world_locked_traps)


## The host's half of the join handshake. Until this lands the joiner has no
## idea which world to build, so it deliberately hasn't loaded the level yet.
@rpc("authority", "call_remote", "reliable")
func _accept_joiner(seed_value: int, house_count_value: int, locked_traps: Array) -> void:
	if not _awaiting_handshake:
		return
	_awaiting_handshake = false
	world_seed = seed_value
	world_house_count = house_count_value
	world_locked_traps = locked_traps.duplicate()
	session_ready.emit(false)


func _on_peer_disconnected(id: int) -> void:
	peer_ids.erase(id)
	roster_changed.emit(peer_ids.duplicate())


func _on_connected_to_server() -> void:
	# A client only knows its own id until the host tells it the rest; the
	# level's spawner replicates the actual player nodes either way.
	var id: int = multiplayer.get_unique_id()
	peer_ids = [HOST_ID]
	if id != HOST_ID:
		peer_ids.append(id)
	roster_changed.emit(peer_ids.duplicate())
	# session_ready waits for _accept_joiner(): loading the level before the
	# host says which seed to use is what built a different world on every
	# machine.
	_awaiting_handshake = true
	_fail_if_handshake_times_out()


func _fail_if_handshake_times_out() -> void:
	await get_tree().create_timer(JOIN_HANDSHAKE_TIMEOUT).timeout
	if not _awaiting_handshake:
		return
	_awaiting_handshake = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	session_failed.emit("El anfitrión aceptó la conexión pero nunca mandó la partida. ¿Están en la misma versión del juego?")


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	session_failed.emit("La conexión falló.")


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	peer_ids = [HOST_ID]
	session_failed.emit("Se cortó la conexión con el anfitrión.")
	roster_changed.emit(peer_ids.duplicate())

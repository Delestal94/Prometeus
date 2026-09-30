class_name NetSession
extends Node
## A co-op session: host-authoritative, two transports, a versioned join
## handshake that carries the host's world to each joiner before their level
## loads, a roster, a host-driven restart and one place that says why a
## session ended. Portable module (docs/modulos.md): the game extends it as
## an autoload and fills in the hooks at the end of this file -- what state
## the host hands a joiner, how to check and apply it, how to word a
## failure. Nothing here knows what that state means.
##
## Two transports, same Godot MultiplayerPeer interface underneath:
##
##   STEAM -- a Steam lobby relayed by Valve. No port forwarding, no firewall
##            prompts, NAT punch-through handled for us.
##   ENET  -- a plain UDP socket. For local development, where Steam P2P is
##            awkward (two instances on one machine share one account).
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
const HOST_ID: int = 1

signal roster_changed(peer_ids: Array)
signal session_ready(is_host: bool)
signal session_failed(reason: String)
## A peer's level is up and can take spawns and the session's state (host).
signal peer_level_ready(peer_id: int)

## Configuration the game sets (in _init or _ready of its subclass).
## Bumped by the game whenever peers can no longer share the same replicated
## scene, handshake or meaning of a relayed payload. Both sides exchange it
## before either starts scene replication.
var protocol_version: int = 1
var max_players: int = 8
## The scenes a session plays in; the handshake refuses any other. The
## first one is the default a joiner is sent to when the host is between
## levels.
var level_scenes: Array[String] = []
## Where an accepted Steam invite takes a peer that isn't in the menu: a
## scene with a `menu_join_method` taking the lobby id.
var main_menu_scene: String = ""
var menu_join_method: StringName = &"join_steam_lobby"

## Force a transport for testing; AUTO picks Steam when it's available.
var transport: Transport = Transport.AUTO
var active_transport: Transport = Transport.ENET
var lobby_id: int = 0
var peer_ids: Array[int] = [HOST_ID]
## How long a joiner may take to receive the host's world and load it before
## the connection is dropped (Godot's auth timeout). A host on another version
## answers with a failure right away, so this only has to cover a slow level
## load (loads of 18-34 s were measured on a 2-core CI runner).
const JOIN_HANDSHAKE_TIMEOUT: float = 45.0
## ENet drops a peer it hasn't heard from in about 5 s, and loading a level
## blocks the main thread -- and with it ENet's polling -- for longer than that
## on a slow machine: the joiner was cut off right after loading, and a host
## restart could drop everyone. A peer that really vanished is still noticed,
## just later; a clean leave is noticed at once.
## MIN must equal MAX: with a settled RTT, ENet's retry rule can disconnect at
## MIN, before MAX is reached. Both cover the handshake's level-load budget.
## This is the budget while either end may be loading: a joiner until the host
## admits it, and both ends from a host restart until the client is back.
const ENET_PEER_TIMEOUT_LIMIT: int = 32
const ENET_PEER_TIMEOUT_MIN_MSEC: int = 45000
const ENET_PEER_TIMEOUT_MAX_MSEC: int = 45000
## Once a peer is in and nobody is loading, a peer that went silent (a crash,
## a pulled cable) is dropped after this long instead: what it held is freed
## sooner, and a crashed host sends everyone back to the menu sooner. Used as
## both MIN and MAX, for the reason above (N-235).
const ENET_PEER_TIMEOUT_SESSION_MSEC: int = 20000
var _awaiting_handshake: bool = false
## The ENet timeout this end applies to each peer, {peer_id: msec}: ENet has
## no getter for it (enet_timeout_msec()).
var _enet_timeouts: Dictionary = {}
## Host: how many restarts each client still has to report back from
## (_report_level_ready). A report from an earlier restart can arrive after the
## next one was sent; only the last one owed brings its timeout down.
var _reloads_owed: Dictionary = {}
## Host: seconds between a client's level being up (admitted, or back from a
## restart) and both ends dropping to the session timeout. The first frames of
## a new level can still stall (shader compilation on GL Compatibility), so the
## load budget holds a little longer. A var so tests can shorten it.
var settle_delay_seconds: float = 3.0
## Host: announce_restart() ran and begin_restart() hasn't yet: nobody settles.
var _restart_announced: bool = false
## The level the session plays in. The host records it whenever its own
## level is up, so a joiner arriving mid-reload still gets the right one.
var session_scene: String = ""

## Host only: peers whose copy of the current level is loaded. Players are
## only spawned to (and their state only sent to) those, so a host restart
## -- everyone reloads, each at their own pace -- never sends a spawn to a
## level that isn't there yet. The host itself always counts.
var _ready_peers: Array[int] = [HOST_ID]
## Why the last session ended, for the menu to show once it's back up (a
## failure while in a level has only the level's overlay listening).
var _failure_message: String = ""

var _steam: Object = null
var _steam_ready: bool = false
## A Steam lobby to join as soon as the menu is up: an invite accepted from
## outside the menu, or the game launched by one (+connect_lobby <id>).
var _pending_lobby: int = 0
## `--net-sim=lag,jitter,loss` (NetStats): the bad connection this process
## simulates, {} for none. Steam's sockets take it as soon as Steam is up
## (_apply_steam_net_sim); on LAN whoever draws remote bodies does
## (pose_net_sim(), NetPoseSmoother).
var net_sim: Dictionary = {}
## Set by begin_restart(), consumed by the host's reloaded level (level_ready).
var _restart_pending: bool = false


## Steam starts with the game, not with the first "host": until it was
## initialised Steam didn't know the game was open, so a friend showed as
## not playing, couldn't be invited, and "join game" from the friends list
## went nowhere. Headless runs (tests, CI) leave the local Steam client alone.
func _ready() -> void:
	_read_net_sim(OS.get_cmdline_user_args())
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


## The address friends on the same network should type in, or "" when this
## machine has no private LAN address at all.
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
	# Decided once, here, so every joiner gets the same world no matter which
	# transport they arrive on.
	_on_hosting()
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
	_on_session_left()


## Everything a session set up, undone: the next solo run must not keep
## building the old room's world, and Steam must not keep us in its lobby.
## The peer becomes an offline one, not null: with none at all every
## authority check spammed "No multiplayer peer is assigned" for as long as
## the level stayed up.
func _end_session() -> void:
	session_scene = ""
	_reset_session_state()
	_awaiting_handshake = false
	_restart_pending = false
	_restart_announced = false
	_ready_peers = [HOST_ID]
	_enet_timeouts.clear()
	_reloads_owed.clear()
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
	var error: Error = peer.create_server(port, max_players - 1)
	if error != OK:
		session_failed.emit(_failure_text("port", [port]))
		return error
	multiplayer.multiplayer_peer = peer
	active_transport = Transport.ENET
	peer_ids = [HOST_ID]
	_on_session_hosted()
	roster_changed.emit(peer_ids.duplicate())
	session_ready.emit(true)
	return OK


func _join_enet(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address, port)
	if error != OK:
		session_failed.emit(_failure_text("connect", [address, port]))
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
	var init_method: StringName = &"steamInitEx" if _steam.has_method(&"steamInitEx") else &"steamInit"
	var response: Variant = _steam.call(init_method)
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
	_apply_steam_net_sim()
	return true


# --- Bad-connection simulation -------------------------------------------------

## Reads `--net-sim` once. A value that doesn't parse is reported, not
## guessed at: a test run that silently simulated nothing would lie.
func _read_net_sim(args: PackedStringArray) -> void:
	var value: String = NetStats.find_net_sim_arg(args)
	if value.is_empty():
		return
	net_sim = NetStats.parse_net_sim_value(value)
	if net_sim.is_empty():
		push_warning(("NetSession: --net-sim=%s not understood; expected lag,jitter,loss (ms, ms, %%)"
			+ " or 'standard'") % value)
		return
	print("NetSession: --net-sim %s (Steam: every packet; LAN: what the game buffers itself)"
		% NetStats.describe_sim(net_sim))


## On Steam the sockets simulate the whole connection, both ways: global
## config, so it covers every connection this process opens from now on.
func _apply_steam_net_sim() -> void:
	if net_sim.is_empty() or _steam == null:
		return
	var applied: int = NetStats.apply_steam_sim(_steam, net_sim)
	var total: int = NetStats.steam_sim_settings(net_sim).size()
	if applied < total:
		push_warning("NetSession: Steam took %d of %d --net-sim settings" % [applied, total])
	else:
		print("NetSession: Steam simulates %s" % NetStats.describe_sim(net_sim))


## The profile the game itself has to simulate (a remote body's pose
## buffer): on LAN, `--net-sim`; on Steam nothing, since the sockets already
## do it.
func pose_net_sim() -> Dictionary:
	return {} if active_transport == Transport.STEAM else net_sim.duplicate()


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
		session_failed.emit(_failure_text("steam_unavailable"))
		return ERR_UNAVAILABLE
	active_transport = Transport.STEAM
	# Friends-only: a game you play with people you know, and it saves
	# moderating public lobbies nobody can moderate.
	_steam.call(&"createLobby", 1, max_players)
	return OK


func _join_steam(target_lobby: int) -> Error:
	if not _init_steam():
		session_failed.emit(_failure_text("steam_unavailable"))
		return ERR_UNAVAILABLE
	if target_lobby == 0:
		session_failed.emit(_failure_text("no_lobby"))
		return ERR_INVALID_PARAMETER
	active_transport = Transport.STEAM
	_steam.call(&"joinLobby", target_lobby)
	return OK


func _on_lobby_created(status: int, created_lobby_id: int) -> void:
	if status != 1:
		session_failed.emit(_failure_text("lobby_create"))
		return
	lobby_id = created_lobby_id
	var peer: Object = ClassDB.instantiate(&"SteamMultiplayerPeer")
	peer.call(&"create_host", 0)
	peer.set(&"server_relay", true)
	peer.set(&"no_nagle", true)
	multiplayer.multiplayer_peer = peer as MultiplayerPeer
	peer_ids = [HOST_ID]
	_on_session_hosted()
	roster_changed.emit(peer_ids.duplicate())
	session_ready.emit(true)


func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:
		_fail("full" if response == 4 else _failure_text("lobby_join"))
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
	# each client saw the others stuck where they spawned.
	peer.set(&"server_relay", true)
	# Steam holds small messages back (Nagle) to batch them: a few ms more on
	# every pose and input, sent every tick anyway.
	peer.set(&"no_nagle", true)
	multiplayer.multiplayer_peer = peer as MultiplayerPeer


## Accepting an invite (or "join game") works from anywhere: in the menu it
## joins right away; playing solo or in another room, that's left and the
## menu takes the join over, since it's what loads the host's level.
func _on_join_requested(invited_lobby_id: int, _friend_id: int) -> void:
	if invited_lobby_id == lobby_id and is_online():
		return
	if is_online():
		leave_session()
	transport = Transport.STEAM
	var scene: Node = get_tree().current_scene
	if scene != null and main_menu_scene != "" and scene.scene_file_path == main_menu_scene:
		scene.call(menu_join_method, invited_lobby_id)
		return
	_pending_lobby = invited_lobby_id
	if main_menu_scene == "":
		return
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(main_menu_scene)


# --- Roster ----------------------------------------------------------------

## Hooked up when a session starts rather than in _ready: an autoload runs
## before the tree is fully standing, and the MultiplayerAPI reached that
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
	# Before roster_changed, so whoever reacts to the new peer already sees
	# what the game gave it (a colour, a slot).
	_peer_joined(id)
	roster_changed.emit(peer_ids.duplicate())
	if multiplayer.is_server():
		# Its level is loaded: a silent joiner is dropped within the session
		# timeout from now on (unless a restart is under way).
		_settle_peer(id)
		peer_level_ready.emit(id)


func _on_peer_disconnected(id: int) -> void:
	peer_ids.erase(id)
	_ready_peers.erase(id)
	_enet_timeouts.erase(id)
	_reloads_owed.erase(id)
	_peer_left(id)
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


# --- Handshake -----------------------------------------------------------------

# Hold scene replication until the joiner's level exists. Authentication
# packets are the only traffic Godot permits before both sides complete_auth.
func _peer_authenticating(id: int) -> void:
	_tolerate_level_loads(id)
	if multiplayer.is_server():
		# The game gets the first word (a seat, a colour): no room means no
		# handshake, and the joiner hears why.
		var refusal: String = _admit_peer(id)
		if not refusal.is_empty():
			multiplayer.send_auth(id, var_to_bytes({"failure": refusal}))
			return
		var state: Dictionary = {"version": protocol_version, "scene": _current_level_scene()}
		state.merge(_session_state())
		multiplayer.send_auth(id, var_to_bytes(state))
	elif id != HOST_ID:
		multiplayer.complete_auth(id)


## Both ends of a new ENet link (the host for the joiner, the joiner for the
## host) wait out a level load instead of dropping the other side. Steam
## peers keep their own timeouts.
func _tolerate_level_loads(id: int) -> void:
	_set_enet_timeout(id, true)


# --- ENet timeouts (N-235) -------------------------------------------------------
#
# Loading a level blocks the main thread, and with it ENet's polling. Whoever
# may be blocked, the other end waits the load budget (ENET_PEER_TIMEOUT_MAX_MSEC)
# for it; otherwise both drop a silent peer within ENET_PEER_TIMEOUT_SESSION_MSEC.
# Each end sets its own: the host for each client, a client for the host.
#   joiner   load budget from authenticating until the host admits it, then
#            the session one (the host says so: _host_load_timeout(false)),
#            settle_delay_seconds after its level is up;
#   restart  announce_restart() (or begin_restart(), if nobody announced)
#            puts the host back on the budget and tells every client
#            (_host_load_timeout(true)) while the host still polls, so ENet
#            can resend a lost notice; each client also takes it in
#            _remote_restart() before its own reload, and both come down
#            settle_delay_seconds after its last owed report is in.

## What this end tolerates from `id` right now, in ms: the load budget, the
## session timeout, or 0 (not on ENet, or not a peer of this end).
func enet_timeout_msec(id: int) -> int:
	return int(_enet_timeouts.get(id, 0))


## Applies the load budget (`loading`) or the session timeout to `id`, MIN =
## MAX. Steam peers keep their own timeouts.
func _set_enet_timeout(id: int, loading: bool) -> void:
	var enet: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var packet_peer: ENetPacketPeer = enet.get_peer(id)
	if packet_peer == null:
		return
	var msec: int = ENET_PEER_TIMEOUT_MAX_MSEC if loading else ENET_PEER_TIMEOUT_SESSION_MSEC
	packet_peer.set_timeout(ENET_PEER_TIMEOUT_LIMIT, msec, msec)
	_enet_timeouts[id] = msec


## Host: `id` has its level up and owes no reload: both ends go back to the
## session timeout, settle_delay_seconds from now if nothing changed by then
## (a restart announced or begun, a reload owed, the peer or session gone).
func _settle_peer(id: int) -> void:
	if not _may_settle(id):
		return
	if settle_delay_seconds <= 0.0 or not is_inside_tree():
		_settle_now(id, multiplayer.multiplayer_peer)
		return
	get_tree().create_timer(settle_delay_seconds).timeout.connect(
		_settle_now.bind(id, multiplayer.multiplayer_peer))


func _settle_now(id: int, peer: MultiplayerPeer) -> void:
	if multiplayer.multiplayer_peer != peer or not multiplayer.get_peers().has(id) or not _may_settle(id):
		return
	_set_enet_timeout(id, false)
	_tell_host_load(id, false)


func _may_settle(id: int) -> bool:
	return not _restart_under_way() and int(_reloads_owed.get(id, 0)) == 0


## Host: a restart was announced or begun and the clients haven't reloaded for
## it yet (level_ready() sends _remote_restart and ends it).
func _restart_under_way() -> bool:
	return _restart_pending or _restart_announced


## Host: tells a client (or all of them, `id` 0) whether to wait out a load on
## the host's link. It must leave now: a host about to reload blocks its
## polling right after. ENet's put_packet already sends at once (the module
## test checks the notice arrives without the host polling); the flush keeps
## that true without leaning on it.
func _tell_host_load(id: int, loading: bool) -> void:
	var enet: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	if id == 0:
		_host_load_timeout.rpc(loading)
	else:
		_host_load_timeout.rpc_id(id, loading)
	if enet.host != null:
		enet.host.flush()


## Client: the host says whether it may block on a level load (a restart is
## under way: the load budget) or everyone is settled (the session timeout).
@rpc("authority", "call_remote", "reliable")
func _host_load_timeout(loading: bool) -> void:
	if multiplayer.is_server():
		return
	_set_enet_timeout(HOST_ID, loading)


## The level to hand a joiner: the one up right now, else the last one this
## host had up (it may be mid-reload), else the default.
func _current_level_scene() -> String:
	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	var path: String = scene.scene_file_path if scene != null else ""
	if path in level_scenes:
		return path
	if session_scene in level_scenes:
		return session_scene
	return level_scenes[0] if not level_scenes.is_empty() else ""


## "" when the host's state can be used, else the failure code ("version",
## "connection").
func _handshake_error(state: Variant) -> String:
	if not state is Dictionary:
		return "version"
	if int(state.get("version", -1)) != protocol_version:
		return "version"
	if not state.has("scene") or String(state.scene) not in level_scenes:
		return "connection"
	return _validate_session_state(state)


func _ready_reply_error(reply: Variant) -> String:
	if not reply is Dictionary or not bool(reply.get("ready", false)):
		return "version"
	return "" if int(reply.get("version", -1)) == protocol_version else "version"


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
	# This is SceneMultiplayer's auth callback, run from inside its poll():
	# failing here must not close the peer while it is being walked.
	if state is Dictionary and state.has("failure"):
		_fail_if_current.call_deferred(String(state.failure), multiplayer.multiplayer_peer)
		return
	var handshake_error: String = _handshake_error(state)
	if not handshake_error.is_empty():
		_fail_if_current.call_deferred(handshake_error, multiplayer.multiplayer_peer)
		return
	session_scene = String(state.scene)
	_apply_session_state(state)
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
		if scene != null and scene.scene_file_path in level_scenes:
			session_scene = scene.scene_file_path
		if _restart_pending:
			_restart_pending = false
			# Everyone connected reloads now and owes a report; until the last
			# one owed is in, the host keeps waiting out their loads.
			for id: int in multiplayer.get_peers():
				_reloads_owed[id] = int(_reloads_owed.get(id, 0)) + 1
				_set_enet_timeout(id, true)
			_remote_restart.rpc(_restart_state())
		return
	if _awaiting_handshake:
		_awaiting_handshake = false
		multiplayer.send_auth(HOST_ID, var_to_bytes({"ready": true, "version": protocol_version}))
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
	_reloads_owed[id] = maxi(int(_reloads_owed.get(id, 0)) - 1, 0)
	# A report from a restart another one has replaced (begun, or sent and
	# still owed): that client reloads again and reports again. Counting it
	# ready now would spawn into a level that is about to go.
	if _restart_pending or int(_reloads_owed.get(id, 0)) > 0:
		return
	if not _ready_peers.has(id):
		_ready_peers.append(id)
	_settle_peer(id)
	peer_level_ready.emit(id)


# --- Restart -----------------------------------------------------------------

## Host, as soon as it knows it will reload for a restart (before a fade, say):
## both ends of every ENet link go back to the load budget now, while the host
## still polls and ENet can resend the notice if it's lost -- sent right before
## the reload, a lost one would wait out the whole load. Until begin_restart()
## nobody settles. A second call changes nothing; begin_restart() does this
## itself if nobody announced.
func announce_restart() -> void:
	if not is_online() or not is_host() or _restart_announced or _restart_pending:
		return
	_restart_announced = true
	for id: int in multiplayer.get_peers():
		_set_enet_timeout(id, true)
	_tell_host_load(0, true)


## Host only, right before reloading its level: every client reloads too,
## once the host's new level is up (level_ready() sends it then, so nothing
## is spawned into the old one). The host's reload blocks its polling, so
## both ends of every link are on the load budget first (announce_restart()).
func begin_restart() -> void:
	if not is_online() or not is_host():
		return
	announce_restart()
	_restart_announced = false
	_restart_pending = true
	_ready_peers = [HOST_ID]
	_before_restart()


## A client drops its run and reloads, then reports back (level_ready()).
## Its own reload blocks its polling: it waits out the host meanwhile, and the
## host waits for it until the report is in.
@rpc("authority", "call_remote", "reliable")
func _remote_restart(state: Dictionary) -> void:
	_set_enet_timeout(HOST_ID, true)
	_apply_restart_state(state)
	get_tree().paused = false
	_reload_level()


# --- Failures ------------------------------------------------------------------

func _auth_failed(id: int) -> void:
	if is_host():
		# A joiner that never made it in: whatever the game gave it goes back,
		# and so does what this end applied to its link.
		_enet_timeouts.erase(id)
		_reloads_owed.erase(id)
		_peer_left(id)
		return
	# Emitted from inside SceneMultiplayer.poll() -- its expiry loop, or
	# _del_peer inside the peer's own poll when the host drops a pending
	# joiner: closing and replacing the peer right here freed it mid-poll.
	_fail_if_current.call_deferred("timeout", multiplayer.multiplayer_peer)


## A failure raised inside SceneMultiplayer.poll() only ends the session it was
## raised for: server_disconnected may already have ended it in the same poll
## (one message, not two), or another session may have begun since.
func _fail_if_current(reason: String, peer: MultiplayerPeer) -> void:
	if multiplayer.multiplayer_peer != peer:
		return
	_fail(reason)


func _on_connection_failed() -> void:
	_fail("timeout")


## The host is gone. The roster isn't announced as shrunk to "just us":
## that made the level think it was now the host and delete every player.
func _on_server_disconnected() -> void:
	_fail(_failure_text("host_lost"))


## Ends the session and says why, to whoever listens now (the menu, or the
## level's overlay) and to the menu once it's back up, if it wasn't then.
## `reason` is either a short code the menu maps to its own text ("version",
## "timeout", "full", "connection") or a sentence from _failure_text().
func _fail(reason: String) -> void:
	_end_session()
	_failure_message = reason
	session_failed.emit(reason)


# --- Hooks the game fills in ---------------------------------------------------

## Host: what a joiner needs before loading the level (a world seed, counts,
## unlock state...). Merged into the handshake next to "version" and "scene";
## keep those two keys free.
func _session_state() -> Dictionary:
	return {}


## Joiner: "" when the host's state is usable, else a failure code
## ("connection" for a state missing what this build expects).
func _validate_session_state(_state: Dictionary) -> String:
	return ""


## Joiner: keep the host's state; the level built next reads it.
func _apply_session_state(_state: Dictionary) -> void:
	pass


## Both: forget the session's state (leave, failure). Solo play follows.
func _reset_session_state() -> void:
	pass


## Host, before the transport is up: decide the state joiners will get.
func _on_hosting() -> void:
	pass


## Host, with the transport up and the roster reset to itself, right before
## roster_changed and session_ready: per-session state that starts with the
## host in it.
func _on_session_hosted() -> void:
	pass


## After leave_session() announced the roster: announce whatever else emptied.
func _on_session_left() -> void:
	pass


## Host, as a joiner starts authenticating: "" admits it, a failure code
## ("full") refuses it before the handshake.
func _admit_peer(_id: int) -> String:
	return ""


## A peer is on the roster (every side), before roster_changed.
func _peer_joined(_id: int) -> void:
	pass


## A peer left the roster (every side), before roster_changed.
func _peer_left(_id: int) -> void:
	pass


## Host, right before it reloads for a restart: what changes for the next
## run (a fresh count, a profile value read again).
func _before_restart() -> void:
	pass


## Host: what every client applies (_apply_restart_state) before reloading.
func _restart_state() -> Dictionary:
	return {}


func _apply_restart_state(_state: Dictionary) -> void:
	pass


## Client, on a host restart, after _apply_restart_state(): reload the level,
## whose level_ready() then reports back. By default the current scene.
func _reload_level() -> void:
	get_tree().reload_current_scene.call_deferred()


## A failure code and its arguments as the player should read it. The
## default hands the code back; the game translates ("port" [port],
## "connect" [address, port], "steam_unavailable", "no_lobby", "lobby_create",
## "lobby_join", "host_lost").
func _failure_text(code: String, _args: Array = []) -> String:
	return code

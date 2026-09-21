extends Node
## Session setup and the peer roster. Host-authoritative, per
## docs/requerimientos-tecnicos.md: clients send input, the host simulates,
## the result is replicated.
##
## Offline counts as a session of one. The level spawns players the same way
## either way, so single-player isn't a separate code path that silently rots
## while the networked one gets all the attention.

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 5
const HOST_ID: int = 1

signal roster_changed(peer_ids: Array)
signal session_failed(reason: String)

var peer_ids: Array[int] = [HOST_ID]


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


## True once a real peer is attached. Offline play leaves this false.
func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer is not OfflineMultiplayerPeer


func is_host() -> bool:
	return not is_online() or multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id() if is_online() else HOST_ID


func host_session(port: int = DEFAULT_PORT) -> Error:
	_ensure_signals()
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		session_failed.emit("No se pudo abrir el puerto %d." % port)
		return error
	multiplayer.multiplayer_peer = peer
	peer_ids = [HOST_ID]
	roster_changed.emit(peer_ids.duplicate())
	return OK


func join_session(address: String, port: int = DEFAULT_PORT) -> Error:
	_ensure_signals()
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address, port)
	if error != OK:
		session_failed.emit("No se pudo conectar a %s:%d." % [address, port])
		return error
	multiplayer.multiplayer_peer = peer
	return OK


func leave_session() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peer_ids = [HOST_ID]
	roster_changed.emit(peer_ids.duplicate())


func _on_peer_connected(id: int) -> void:
	if not peer_ids.has(id):
		peer_ids.append(id)
	roster_changed.emit(peer_ids.duplicate())


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


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	session_failed.emit("La conexión falló.")


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	peer_ids = [HOST_ID]
	session_failed.emit("Se cortó la conexión con el anfitrión.")
	roster_changed.emit(peer_ids.duplicate())

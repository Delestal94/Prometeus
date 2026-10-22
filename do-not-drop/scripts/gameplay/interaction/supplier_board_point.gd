class_name SupplierBoardPoint
extends Interactable
## The spot where a player opens the supplier order screen in the company's shed (expansion
## D-0603.b.2): the grey board by the dock that CompanyShed hangs on every drawing, until the clipboard
## exists (D-0131 / D-0413).
##
## interact() runs on the host like every Interactable (a client's press arrives through
## request_interact), but what it does is open a screen on the screen of whoever used it, as the
## depot's stations do (DepotStation): the host bounces it to that player's own peer (_open_here, from
## the host only, reliable), where `opened` fires for the world adapter (SupplierBoard) to show the
## panel. Nothing is ordered here: the screen asks the host through CompanyNet.

## On the peer of the player who used the board (the host's own player, or a client's).
signal opened

const PROMPT_KEY: String = "WORLD_SHED_USE_SUPPLIER"
const REACH_RADIUS: float = 0.8


## A point `REACH_RADIUS` wide, named so its RPC path is the same on every peer.
static func make() -> SupplierBoardPoint:
	var point := SupplierBoardPoint.new()
	point.name = "SupplierBoardPoint"
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = REACH_RADIUS
	shape.shape = sphere
	point.add_child(shape)
	return point


func get_prompt() -> String:
	return tr(PROMPT_KEY)


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	var peer: int = int(player.get_multiplayer_authority())
	var offline: bool = multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	if offline or peer == multiplayer.get_unique_id():
		opened.emit()
	elif multiplayer.get_peers().has(peer):
		_open_here.rpc_id(peer)
	interacted.emit(player)


## The user's peer: the host says this player used the board. Opens nothing but its own screen.
@rpc("authority", "call_remote", "reliable")
func _open_here() -> void:
	if not RpcGuard.from_host(self):
		return
	opened.emit()

class_name NetEventBus
extends Node
## The plumbing of a host-authoritative event bus. Portable module
## (docs/modulos.md): the game extends it as an autoload and declares its
## own signals; nothing here knows what they mean.
##
## Two shapes of traffic:
##
## - relay(): a fact decided on the host (the simulation is host-run)
##   reaches every client's own bus, so their HUD and managers react the
##   same way they would offline. Emit local, per-peer UI requests with a
##   plain emit() instead.
## - request(): something any peer may initiate (a callout, a horn). The
##   client asks the host (rpc_id(1, ...)); the host is the only one allowed
##   to decide it actually happened, optionally rate-limits it per peer
##   (_accept_request), then relay()s it as a fact to everyone, the sender
##   included. The relayed signal gets the sender's peer id as its first
##   argument. Only the events listed in request_cooldowns can be requested,
##   with a few plain arguments (RpcGuard.args_ok), and every remote request
##   spends the sender's budget (RpcGuard.allow_request): request() is an
##   any_peer RPC, and without a list any client could make the host relay
##   any of the game's facts.

## The events peers may request, each with the minimum seconds between two
## accepted requests from the same peer (0 = no limit). An event not listed
## here is refused. Host-side.
var request_cooldowns: Dictionary = {}
## Host-side: [peer_id, event_name] -> Time.get_ticks_msec() of the last
## accepted request.
var _last_request_ms: Dictionary = {}


func is_online() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and peer is not OfflineMultiplayerPeer


func is_host() -> bool:
	return not is_online() or multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


## Emits locally and, if this is the host of an online session, rebroadcasts
## to every client so their own bus fires the same signal. Call this
## instead of emit_signal() for anything that originates from host-run
## simulation so clients stay in sync.
func relay(event_name: StringName, args: Array = []) -> void:
	callv(&"emit_signal", [event_name] + args)
	if is_online() and is_host():
		_relay.rpc(event_name, args)


@rpc("authority", "call_remote", "reliable")
func _relay(event_name: StringName, args: Array) -> void:
	callv(&"emit_signal", [event_name] + args)


## Any peer calls this (directly if it's already the host, via
## rpc_id(1, ...) otherwise). Accepted requests are relayed as
## `event_name(peer_id, args...)`.
@rpc("any_peer", "call_remote", "reliable")
func request(event_name: StringName, args: Array = []) -> void:
	if is_online() and not is_host():
		return
	if not RpcGuard.allow_request(self) or not RpcGuard.name_ok(event_name) or not RpcGuard.args_ok(args):
		return
	var peer_id: int = sender_id()
	if not _accept_request(peer_id, event_name, args):
		return
	relay(event_name, [peer_id] + args)


## Who called the RPC being handled: the remote peer, or this one when the
## call was local.
func sender_id() -> int:
	var remote: int = multiplayer.get_remote_sender_id()
	return remote if remote != 0 else local_id()


## Host: whether to relay a request. The default takes only the events in
## request_cooldowns, at their pace; the game overrides it for anything else
## (the shape of the arguments, a role check, a phase) and calls super().
func _accept_request(peer_id: int, event_name: StringName, _args: Array) -> bool:
	if not request_cooldowns.has(event_name):
		return false
	var cooldown: float = float(request_cooldowns.get(event_name, 0.0))
	if cooldown <= 0.0:
		return true
	var key: Array = [peer_id, event_name]
	var now_ms: int = Time.get_ticks_msec()
	if _last_request_ms.has(key) and now_ms - int(_last_request_ms[key]) < roundi(cooldown * 1000.0):
		return false
	_last_request_ms[key] = now_ms
	return true


## Forgets every peer's last request, so the next one goes through.
func reset_request_cooldowns() -> void:
	_last_request_ms.clear()

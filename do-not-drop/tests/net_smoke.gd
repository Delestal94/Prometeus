extends SceneTree
## Two-process connection smoke test. Run the host first, then the client:
##   Godot --headless --path do-not-drop --script res://tests/net_smoke.gd -- --host
##   Godot --headless --path do-not-drop --script res://tests/net_smoke.gd -- --client
## The host waits for someone to arrive; the client waits to be let in.
## Both print PASS/FAIL and set an exit code, so CI can run them as a pair.

const PORT: int = 7787
const TIMEOUT_SECONDS: float = 10.0

var _network: Node
var _waited: float = 0.0


func _initialize() -> void:
	await process_frame
	_network = root.get_node(^"/root/NetworkManager")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--host" in args:
		await _run_host()
	elif "--client" in args:
		await _run_client()
	else:
		push_error("Pass --host or --client")
		quit(2)


func _run_host() -> void:
	var error: Error = _network.call(&"host_session", PORT)
	if error != OK:
		print("FAIL: the host could not open port %d (error %d)" % [PORT, error])
		quit(1)
		return
	print("Host listening on %d, waiting for a peer..." % PORT)
	var joined: bool = await _wait_until(func() -> bool:
		return root.multiplayer.get_peers().size() >= 1)
	# Distinguishes "the API never saw the peer" from "it did, but our signal
	# never fired" -- two very different bugs.
	print("API peers: %s / roster: %s" % [str(root.multiplayer.get_peers()), str(_network.get(&"peer_ids"))])
	var rostered: bool = (_network.get(&"peer_ids") as Array).size() >= 2
	if joined and rostered:
		print("PASS: host accepted a peer and the roster caught it")
	elif joined:
		print("FAIL: the peer connected but roster_changed never updated")
	else:
		print("FAIL: nobody connected within %.0fs" % TIMEOUT_SECONDS)
	joined = joined and rostered
	_network.call(&"leave_session")
	quit(0 if joined else 1)


func _run_client() -> void:
	var error: Error = _network.call(&"join_session", "127.0.0.1", PORT)
	if error != OK:
		print("FAIL: the client could not start connecting (error %d)" % error)
		quit(1)
		return
	var connected: bool = await _wait_until(func() -> bool:
		return root.multiplayer.multiplayer_peer != null \
			and root.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
	if connected:
		print("PASS: client connected with id %d" % root.multiplayer.get_unique_id())
	else:
		print("FAIL: could not reach the host within %.0fs" % TIMEOUT_SECONDS)
	_network.call(&"leave_session")
	quit(0 if connected else 1)


func _wait_until(predicate: Callable) -> bool:
	_waited = 0.0
	while _waited < TIMEOUT_SECONDS:
		if predicate.call():
			return true
		# A --script SceneTree doesn't pump the MultiplayerAPI the way the
		# running game does, so drive it by hand here.
		if root.multiplayer.multiplayer_peer != null:
			root.multiplayer.poll()
		await process_frame
		_waited += 1.0 / 60.0
	return false

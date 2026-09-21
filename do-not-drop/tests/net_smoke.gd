extends SceneTree
## Two-process connection smoke test. Run the host first, then the client:
##   Godot --headless --path do-not-drop --script res://tests/net_smoke.gd -- --host
##   Godot --headless --path do-not-drop --script res://tests/net_smoke.gd -- --client
## The host waits for someone to arrive; the client waits to be let in.
## Both print PASS/FAIL and set an exit code, so CI can run them as a pair.
##
## IMPORTANT: use the plain (non "_console") Godot executable for this. On
## Windows, firewall rules are tied to the exact .exe path, and a rule
## approved for one build doesn't cover another -- see README.md.

const PORT: int = 7787
const TIMEOUT_SECONDS: float = 10.0

var _network: Node
var _waited: float = 0.0


func _initialize() -> void:
	await process_frame
	_network = root.get_node(^"/root/NetworkManager")
	# Force ENet: this checks local dev connectivity specifically. AUTO would
	# pick Steam whenever Steam happens to be running on the test machine,
	# and P2P between two instances signed into the same Steam account isn't
	# reliably supported anyway (see README) -- that's a Steam limitation to
	# route around here, not something this test should get tangled in.
	_network.set(&"transport", 2)  # NetworkManager.Transport.ENET
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
	# NetworkManager resets multiplayer_peer to null on connection_failed, and
	# Godot substitutes an OfflineMultiplayerPeer for a null peer -- which
	# trivially reports itself "connected" with id 1. Watching for the actual
	# failure signal, rather than just polling connection_status afterward,
	# is what keeps that substitution from reading as a false PASS.
	var failed: bool = false
	_network.connect(&"session_failed", func(_reason: String) -> void: failed = true)
	var error: Error = _network.call(&"join_session", "127.0.0.1", PORT)
	if error != OK:
		print("FAIL: the client could not start connecting (error %d)" % error)
		quit(1)
		return
	var connected: bool = await _wait_until(func() -> bool:
		if failed:
			return true  # stop waiting; the outer check below reports it
		var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
		return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
	if failed:
		print("FAIL: ENet reported connection_failed -- not a timeout, an active rejection")
	elif connected:
		print("PASS: client connected with id %d" % root.multiplayer.get_unique_id())
		# Give the host a few real frames to register the peer and reply
		# before this process (and its socket) disappears -- disconnecting
		# the instant our own side sees CONNECTED can race the host's next
		# poll() and read as nobody-ever-connected on their side.
		for _i in range(120):
			root.multiplayer.poll()
			await process_frame
	else:
		print("FAIL: could not reach the host within %.0fs (still 'connecting', no failure signal either)" % TIMEOUT_SECONDS)
	var ok: bool = connected and not failed
	_network.call(&"leave_session")
	quit(0 if ok else 1)


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

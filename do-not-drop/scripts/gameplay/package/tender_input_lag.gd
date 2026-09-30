class_name TenderInputLag
extends RefCounted
## Debug: a client's care input reaching the host late (S-205).
##
## `--fake-lag=<ms>` holds every sample a client sends to the box it tends
## (submit_tender_input, submit_care_input) back that long, plus a random
## spread of up to a third of it, so a developer can feel what a bad
## connection does to the hold feedback. Same convention as
## vehicle_net_smoother.gd: `--net-sim` on LAN (NetworkManager.pose_net_sim(),
## empty over Steam, whose sockets simulate the link instead) sets it too, and
## may also drop samples. Only active in a debug build; a release build sends
## straight away whatever the command line says.
##
## Only the way there is simulated, and only this channel: putting the box
## down, picking it up, sitting and request_stop_assist go out at once, so with
## `--fake-lag` a released box can stop being tended before the last held
## samples reach the host (the host drops those). It is a probe for the
## hold feedback, not a model of the whole link.
##
## Samples leave in the order they were sent, like the unreliable-ordered
## channel they travel on. Without lag, `send()` is a plain rpc_id(1, ...).

## [release_at, package, method, input, sent_as_host], oldest first.
var _queue: Array = []
var _last_release: float = 0.0
var _rng := RandomNumberGenerator.new()
var fake_lag: float = 0.0
## Seconds of random extra hold per sample, 0..this; below 0, a third of
## fake_lag (the `--fake-lag` spread).
var fake_jitter: float = -1.0
## Share of samples dropped (0..1).
var fake_loss: float = 0.0
## The host's own input never crosses a network, so it is not held back;
## tests offline (where everyone is the host) switch this on.
var include_host: bool = false


func _init(read_command_line: bool = true) -> void:
	_rng.randomize()
	if read_command_line and OS.is_debug_build():
		_read_args(OS.get_cmdline_user_args())
		var tree := Engine.get_main_loop() as SceneTree
		var network: Node = tree.root.get_node_or_null(^"NetworkManager") if tree != null else null
		if network != null and network.has_method(&"pose_net_sim"):
			configure_sim(network.call(&"pose_net_sim"))


func _read_args(args: PackedStringArray) -> void:
	for arg: String in args:
		if arg.begins_with("--fake-lag="):
			fake_lag = maxf(float(arg.get_slice("=", 1)) / 1000.0, 0.0)


## A NetStats `--net-sim` profile ({lag_ms, jitter_ms, loss_pct}); an empty
## one leaves things as they were.
func configure_sim(sim: Dictionary) -> void:
	if sim.is_empty():
		return
	fake_lag = maxf(float(sim.get("lag_ms", 0)) / 1000.0, 0.0)
	fake_jitter = maxf(float(sim.get("jitter_ms", 0)) / 1000.0, 0.0)
	fake_loss = clampf(float(sim.get("loss_pct", 0.0)) / 100.0, 0.0, 1.0)


func is_lagging() -> bool:
	return OS.is_debug_build() and (fake_lag > 0.0 or fake_jitter > 0.0 or fake_loss > 0.0)


## Samples still on their way to the host.
func pending() -> int:
	return _queue.size()


## Sends `input` to `package`'s host now, or holds it back when lag is on.
## `is_host`: the sender is the host itself. `now` in seconds.
func send(package: Node, method: StringName, input: Dictionary, is_host: bool, now: float) -> void:
	if not is_lagging() or (is_host and not include_host):
		package.rpc_id(1, method, input)
		return
	if fake_loss > 0.0 and _rng.randf() < fake_loss:
		return
	var spread: float = fake_jitter if fake_jitter >= 0.0 else fake_lag / 3.0
	var release_at: float = maxf(now + fake_lag + _rng.randf_range(0.0, spread), _last_release)
	_last_release = release_at
	_queue.append([release_at, package, method, input, is_host])


## Sends every held sample whose time has come. A sample held by a client that
## has since become the host (the session changed under it) is dropped, and so
## is one whose box is gone.
func flush(now: float) -> void:
	while not _queue.is_empty() and float((_queue[0] as Array)[0]) <= now:
		var held: Array = _queue.pop_front()
		var package: Variant = held[1]
		if not is_instance_valid(package):
			continue
		var node := package as Node
		if not node.is_inside_tree() or (node.multiplayer.is_server() and not bool(held[4])):
			continue
		node.rpc_id(1, held[2] as StringName, held[3] as Dictionary)


func clear() -> void:
	_queue.clear()

extends Node
## S-311.84 two-process probe used by net_pair.tscn. The host and client each
## author a clip whose final variant depends on owner-local context. The other
## process must receive anim_clip and play exactly that variant.

const TIMEOUT_SECONDS: float = 6.0
const OWNER_LOCK_MS: int = 8000

var detail: String = "replicated animation check did not finish"
var _client_peer_id: int = 0
var _client_reported: bool = false
var _client_passed: bool = false


func run_host(host_player: Player, client_player: Player, client_peer_id: int) -> bool:
	_client_peer_id = client_peer_id
	_client_reported = false
	_client_passed = false

	# The host chooses a height-dependent pickup blend. The client has no need
	# for that package or pickup height: the exact blend name is replicated.
	_set_owner_sample(host_player, Player.ANIM_PICKUP, 0.0, 0.5)
	var host_owner_ok: bool = await _wait_until(func() -> bool:
		return _plays(host_player, Player.ANIM_PICKUP, &"pickup_blend/4"))
	rpc_id(client_peer_id, &"_client_check_remote", host_player.get_path(),
		Player.ANIM_PICKUP, &"pickup_blend/4")
	var client_saw_host: bool = await _wait_until(func() -> bool: return _client_reported) \
		and _client_passed

	# The client then chooses Stroll from Walk plus its private gait hysteresis.
	# The host's remote copy must use the published result, not its own history.
	_client_reported = false
	_client_passed = false
	rpc_id(client_peer_id, &"_client_publish", client_player.get_path(), Player.ANIM_WALK, 1.5, 0.0)
	var client_owner_ok: bool = await _wait_until(func() -> bool: return _client_reported) \
		and _client_passed
	var host_saw_client: bool = client_owner_ok and await _wait_until(func() -> bool:
		return _plays(client_player, Player.ANIM_WALK, Player.ANIM_STROLL))

	# S-311.89: the radial emote uses the same replicated exact-clip contract.
	# No new RPC carries it; the client sees the owner's chosen emote through
	# anim_state / anim_clip just like every other authored animation.
	_set_owner_sample(host_player, &"Wave", 0.0, 0.0)
	var host_emote_ok: bool = await _wait_until(func() -> bool:
		return _plays(host_player, &"Wave", &"Wave"))
	_client_reported = false
	_client_passed = false
	rpc_id(client_peer_id, &"_client_check_remote", host_player.get_path(), &"Wave", &"Wave")
	var client_saw_emote: bool = await _wait_until(func() -> bool: return _client_reported) \
			and _client_passed

	# S-311.90: inactivity chooses a long idle only on the owner. Its exact
	# clip follows the same property replication as the radial emote.
	_set_owner_sample(host_player, &"InspectHand", 0.0, 0.0)
	var host_long_idle_ok: bool = await _wait_until(func() -> bool:
		return _plays(host_player, &"InspectHand", &"InspectHand"))
	_client_reported = false
	_client_passed = false
	rpc_id(client_peer_id, &"_client_check_remote", host_player.get_path(),
		&"InspectHand", &"InspectHand")
	var client_saw_long_idle: bool = await _wait_until(func() -> bool: return _client_reported) \
			and _client_passed

	# S-311.91: results choose the reaction on the owner and reuse the exact
	# replicated clip contract. Defeat is the new path; VictoryDance already
	# exercises the same authored/looping playback path as the dances.
	_set_owner_sample(host_player, PlayerAnimator.ANIM_DEFEAT, 0.0, 0.0)
	var host_defeat_ok: bool = await _wait_until(func() -> bool:
		return _plays(host_player, PlayerAnimator.ANIM_DEFEAT, PlayerAnimator.ANIM_DEFEAT))
	_client_reported = false
	_client_passed = false
	rpc_id(client_peer_id, &"_client_check_remote", host_player.get_path(),
		PlayerAnimator.ANIM_DEFEAT, PlayerAnimator.ANIM_DEFEAT)
	var client_saw_defeat: bool = await _wait_until(func() -> bool: return _client_reported) \
			and _client_passed

	_clear_owner(host_player)
	rpc_id(client_peer_id, &"_client_clear", client_player.get_path())
	await _wait_until(func() -> bool:
		return host_player.anim_clip == Player.ANIM_IDLE and client_player.anim_clip == Player.ANIM_IDLE)

	var passed: bool = host_owner_ok and client_saw_host and client_owner_ok and host_saw_client \
			and host_emote_ok and client_saw_emote and host_long_idle_ok and client_saw_long_idle \
			and host_defeat_ok and client_saw_defeat
	detail = "both authorities publish exact clips, including emote, long idle and result defeat" \
			if passed else (
		"animation pickup=%s/%s gait=%s/%s emote=%s/%s idle=%s/%s defeat=%s/%s"
		% [host_owner_ok, client_saw_host, client_owner_ok, host_saw_client, host_emote_ok,
			client_saw_emote, host_long_idle_ok, client_saw_long_idle,
			host_defeat_ok, client_saw_defeat])
	return passed


@rpc("authority", "call_remote", "reliable")
func _client_check_remote(player_path: NodePath, state: StringName, clip: StringName) -> void:
	var player := get_node_or_null(player_path) as Player
	var passed: bool = player != null and await _wait_until(func() -> bool:
		return _plays(player, state, clip))
	rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, &"_receive_report", passed)


@rpc("authority", "call_remote", "reliable")
func _client_publish(player_path: NodePath, state: StringName, speed: float, pickup_weight: float) -> void:
	var player := get_node_or_null(player_path) as Player
	if player != null:
		_set_owner_sample(player, state, speed, pickup_weight)
	var passed: bool = player != null and await _wait_until(func() -> bool:
		return _plays(player, state, Player.ANIM_STROLL))
	rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, &"_receive_report", passed)


@rpc("authority", "call_remote", "reliable")
func _client_clear(player_path: NodePath) -> void:
	var player := get_node_or_null(player_path) as Player
	if player != null:
		_clear_owner(player)


@rpc("any_peer", "call_remote", "reliable")
func _receive_report(passed: bool) -> void:
	if multiplayer.get_remote_sender_id() != _client_peer_id:
		return
	_client_passed = passed
	_client_reported = true


func _set_owner_sample(player: Player, state: StringName, speed: float, pickup_weight: float) -> void:
	player.locomotion_speed = speed
	player.pickup_high_weight = pickup_weight
	player.animator.play_one_shot(state, OWNER_LOCK_MS)


func _clear_owner(player: Player) -> void:
	player.animator.release_lock()
	player.anim_state = Player.ANIM_IDLE
	player.locomotion_speed = 0.0
	player.pickup_high_weight = 0.0


func _plays(player: Player, state: StringName, clip: StringName) -> bool:
	return player.anim_state == state and player.anim_clip == clip \
		and player.animator != null and player.animator.anim_player != null \
		and StringName(player.animator.anim_player.current_animation) == clip


func _wait_until(condition: Callable, seconds: float = TIMEOUT_SECONDS) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()

extends Node
## S-311.52 two-process probe used by net_pair.tscn. The host broadcasts one
## impulse/seed and both peers simulate the presentation rig independently.

const RAGDOLL_SEED: int = 31152
const TIMEOUT_SECONDS: float = 6.0

var detail: String = "replicated ragdoll check did not finish"
var _client_peer_id: int = 0
var _client_reported: bool = false
var _client_passed: bool = false


func run_host(player: CharacterBody3D, client_peer_id: int) -> bool:
	_client_peer_id = client_peer_id
	_client_reported = false
	_client_passed = false
	var capsule_position: Vector3 = player.global_position
	var capsule_velocity: Vector3 = player.velocity
	var authority: int = player.get_multiplayer_authority()
	player.rpc(&"receive_package_hit", Vector3(3.2, 0.0, 0.4), RAGDOLL_SEED)
	var started: bool = await _wait_until(func() -> bool:
		return bool(player.get(&"_ragdolled")), 3.0)
	var component: Node = player.get_node(^"GelRagdoll")
	var host_started: bool = started and component.call(&"is_active") \
		and int(component.get(&"last_seed")) == RAGDOLL_SEED
	var capsule_unchanged: bool = player.get_multiplayer_authority() == authority \
		and player.global_position.distance_to(capsule_position) < 0.05 \
		and player.velocity.distance_to(capsule_velocity) < 0.05
	rpc_id(client_peer_id, &"_client_check", player.get_path(), RAGDOLL_SEED)
	var report_arrived: bool = await _wait_until(func() -> bool: return _client_reported)
	var finished: bool = await _wait_until(func() -> bool:
		return not bool(player.get(&"_ragdolled")))
	var body_visual := player.get_node(^"BodyVisual") as Node3D
	var recovered: bool = finished \
		and body_visual.global_position.distance_to(player.global_position) < 0.5
	var passed: bool = host_started and capsule_unchanged and report_arrived \
		and _client_passed and recovered
	detail = ("both peers simulate seed %d, keep capsule authority/pose and recover within 0.5 m"
		% RAGDOLL_SEED) if passed else (
		"ragdoll host_started=%s capsule=%s report=%s client=%s recovered=%s"
		% [host_started, capsule_unchanged, report_arrived, _client_passed, recovered])
	return passed


@rpc("authority", "call_remote", "reliable")
func _client_check(player_path: NodePath, expected_seed: int) -> void:
	var player := get_node_or_null(player_path) as CharacterBody3D
	var capsule_position: Vector3 = player.global_position if player != null else Vector3.INF
	var started: bool = player != null and await _wait_until(func() -> bool:
		return bool(player.get(&"_ragdolled")), 3.0)
	var component: Node = player.get_node(^"GelRagdoll") if player != null else null
	var same_seed: bool = component != null and int(component.get(&"last_seed")) == expected_seed
	var capsule_unchanged: bool = player != null \
		and player.get_multiplayer_authority() == MultiplayerPeer.TARGET_PEER_SERVER \
		and player.global_position.distance_to(capsule_position) < 0.05
	var finished: bool = player != null and await _wait_until(func() -> bool:
		return not bool(player.get(&"_ragdolled")))
	var body_visual := player.get_node_or_null(^"BodyVisual") as Node3D if player != null else null
	var recovered: bool = body_visual != null \
		and body_visual.global_position.distance_to(player.global_position) < 0.5
	rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, &"_receive_report",
		started and same_seed and capsule_unchanged and finished and recovered)


@rpc("any_peer", "call_remote", "reliable")
func _receive_report(passed: bool) -> void:
	if multiplayer.get_remote_sender_id() != _client_peer_id:
		return
	_client_passed = passed
	_client_reported = true


func _wait_until(condition: Callable, seconds: float = TIMEOUT_SECONDS) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()

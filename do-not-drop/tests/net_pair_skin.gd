extends Node
## S-311.70 two-process probe used by net_pair.tscn. Each peer must receive
## and render the gel skin selected in the other peer's saved profile.

const GEL_SKINS: Script = preload("res://scripts/gameplay/player/gel/gel_skin_catalog.gd")
const TIMEOUT_SECONDS: float = 6.0

var detail: String = "replicated gel skin check did not finish"
var _client_peer_id: int = 0
var _client_reported: bool = false
var _client_passed: bool = false


func run_host(host_player: Player, client_player: Player, client_peer_id: int,
		host_skin: StringName, client_skin: StringName) -> bool:
	_client_peer_id = client_peer_id
	_client_reported = false
	_client_passed = false
	var host_passed: bool = await _wait_until(func() -> bool:
		return _skin_applied(client_player, client_skin))
	rpc_id(client_peer_id, &"_client_check", host_player.get_path(), host_skin)
	var report_arrived: bool = await _wait_until(func() -> bool: return _client_reported)
	var passed: bool = host_passed and report_arrived and _client_passed
	detail = "each peer receives and renders the other profile's gel skin" if passed else (
		"gel skin host=%s report=%s client=%s" % [host_passed, report_arrived, _client_passed])
	return passed


@rpc("authority", "call_remote", "reliable")
func _client_check(player_path: NodePath, expected_skin: StringName) -> void:
	var player := get_node_or_null(player_path) as Player
	var passed: bool = player != null and await _wait_until(func() -> bool:
		return _skin_applied(player, expected_skin))
	rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, &"_receive_report", passed)


@rpc("any_peer", "call_remote", "reliable")
func _receive_report(passed: bool) -> void:
	if multiplayer.get_remote_sender_id() != _client_peer_id:
		return
	_client_passed = passed
	_client_reported = true


func _skin_applied(player: Player, expected_id: StringName) -> bool:
	var state := player.get_node_or_null(^"GelProportions")
	var mesh := PlayerAppearance.find_mesh_instance(player.get_node(^"BodyVisual"))
	if state == null or mesh == null or StringName(state.get(&"skin_id")) != expected_id:
		return false
	var expected: Resource = GEL_SKINS.skin(expected_id)
	return mesh.get_instance_shader_parameter(&"gel_color") == expected.get(&"color")


func _wait_until(condition: Callable, seconds: float = TIMEOUT_SECONDS) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()

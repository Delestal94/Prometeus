extends Node
## S-311.99 two-process probe used by net_pair.tscn. Each peer must receive
## and render the complete gel look selected in the other peer's profile.

const GEL_SKINS: Script = preload("res://scripts/gameplay/player/gel/gel_skin_catalog.gd")
const TIMEOUT_SECONDS: float = 6.0

var detail: String = "replicated gel skin check did not finish"
var _client_peer_id: int = 0
var _client_reported: bool = false
var _client_passed: bool = false


func run_host(host_player: Player, client_player: Player, client_peer_id: int,
		host_look: Dictionary, client_look: Dictionary) -> bool:
	_client_peer_id = client_peer_id
	_client_reported = false
	_client_passed = false
	var host_passed: bool = await _wait_until(func() -> bool:
		return _look_applied(client_player, client_look))
	rpc_id(client_peer_id, &"_client_check", host_player.get_path(), host_look)
	var report_arrived: bool = await _wait_until(func() -> bool: return _client_reported)
	var passed: bool = host_passed and report_arrived and _client_passed
	detail = "each peer receives and renders the other profile's complete gel look" if passed else (
		"gel look host=%s report=%s client=%s" % [host_passed, report_arrived, _client_passed])
	return passed


@rpc("authority", "call_remote", "reliable")
func _client_check(player_path: NodePath, expected_look: Dictionary) -> void:
	var player := get_node_or_null(player_path) as Player
	var passed: bool = player != null and await _wait_until(func() -> bool:
		return _look_applied(player, expected_look))
	rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, &"_receive_report", passed)


@rpc("any_peer", "call_remote", "reliable")
func _receive_report(passed: bool) -> void:
	if multiplayer.get_remote_sender_id() != _client_peer_id:
		return
	_client_passed = passed
	_client_reported = true


func _look_applied(player: Player, expected: Dictionary) -> bool:
	var state := player.get_node_or_null(^"GelProportions")
	var mesh := PlayerAppearance.find_mesh_instance(player.get_node(^"BodyVisual"))
	var skin_id := StringName(expected[&"selected_gel_skin"])
	if state == null or mesh == null or StringName(state.get(&"skin_id")) != skin_id:
		return false
	if StringName(state.get(&"hair_id")) != StringName(expected[&"selected_gel_hair"]) \
			or StringName(state.get(&"eyebrows_id")) != StringName(expected[&"selected_gel_eyebrows"]) \
			or StringName(state.get(&"moustache_id")) != StringName(expected[&"selected_gel_moustache"]) \
			or StringName(state.get(&"costume_id")) != StringName(expected[&"selected_gel_costume"]) \
			or StringName(state.get(&"accessory_id")) != StringName(expected[&"selected_gel_accessory"]):
		return false
	var face: Node = player.get_node_or_null(^"GelFaceReactions")
	if face == null or StringName(face.get(&"base_face_id")) != StringName(expected[&"selected_gel_face"]):
		return false
	var body: Node = player.get_node(^"BodyVisual")
	var hair: Node = body.find_child("GelHair", true, false)
	var costume: Node = body.find_child("GelCostume_*", false, false)
	var accessory: Node = body.find_child("GelAccessory_*", false, false)
	if hair == null or StringName(hair.get(&"style_id")) != StringName(expected[&"selected_gel_hair"]):
		return false
	if costume == null or StringName(costume.get_meta(&"gel_costume_id", &"")) \
			!= StringName(expected[&"selected_gel_costume"]):
		return false
	if accessory == null or StringName(accessory.get_meta(&"gel_accessory_id", &"")) \
			!= StringName(expected[&"selected_gel_accessory"]):
		return false
	var expected_skin: Resource = GEL_SKINS.skin(skin_id)
	return mesh.get_instance_shader_parameter(&"gel_color") == expected_skin.get(&"color")


func _wait_until(condition: Callable, seconds: float = TIMEOUT_SECONDS) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()

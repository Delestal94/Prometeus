extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_net_bandwidth_budget.gd
##
## What the host sends each client, and uploads in all, with a full crew of
## NetworkManager.MAX_PLAYERS (N-228.5). Past Steam's send rate (256 KB/s per
## connection by default) Steam queues and the client sees an ever older
## world: in the Steam playtest of 2026-09-29 each box sent its 19-key
## care_state every rendered frame, 2-5x the limit, and the truck "kept going"
## seconds after the driver let go (docs/investigacion-red.md).
##
## Counted the way SceneMultiplayer sends it (modules/multiplayer, Godot 4.7):
## - every tick the host packs each synchronizer due for a peer into sync
##   packets of at most max_sync_packet_size (1350) bytes: 3 bytes of header a
##   packet, 8 a synchronizer (net id, size), then its always-sent properties
##   as MultiplayerAPI encodes them (a bool 1 byte, an int 2-9, the rest what
##   var_to_bytes() gives). Synchronizers on different intervals are packed
##   apart (a ceiling: sharing a tick they would share a packet);
## - a player belongs to its owner (player.gd), so another client's pose
##   reaches this one through the host (server_relay): a packet of its own,
##   6 bytes more, forwarded to every client but the owner;
## - every packet is then a datagram on the wire: PACKET_OVERHEAD_BYTES.
## Two worst cases. Steady: the whole crew with a box each moving (carried,
## tended), the rest of a full depot at rest (NetRestThrottle in
## package.tscn), the truck driving. Pile-up: every box moving at once. Steady
## fits the budget, the pile-up Steam's send rate itself, and the host's
## upload in the steady case a modest home uplink.
##
## The throttle itself, wired into a real box: one left alone drops to its
## rest interval, and moving it puts the full rate back the same tick.

## Steam's default send rate per connection (SendRateMax).
const STEAM_SEND_RATE: float = 256.0 * 1024.0
## Half of it: the other half is for RPCs, ON_CHANGE deltas, voice and
## whatever comes next.
const BUDGET_BYTES_PER_SECOND: float = STEAM_SEND_RATE * 0.5
## 80 % of a 10 Mbit/s uplink: the upload of an entry cable or VDSL plan
## (100/10, 50/10), well below any fibre; ADSL's ~1 Mbit/s can't host eight at
## any sane rate. The other 20 % is for the household, voice and the game's
## RPCs.
const HOST_UPLINK_BYTES_PER_SECOND: float = 0.8 * 10_000_000.0 / 8.0
## A property sent every tick is a pose or a flag. Anything bigger (a
## Dictionary, a String) belongs in ON_CHANGE.
const MAX_ALWAYS_PROPERTY_BYTES: int = 64
const WORST_FPS: float = 144.0
## Seven boxes in the level plus the depot's extra stock of seven.
const FULL_DEPOT: int = 14
## SceneMultiplayer's framing: scene_replication_interface.cpp (_send_sync)
## and scene_multiplayer.h (SYS_CMD_SIZE).
const SYNC_PACKET_HEADER: int = 3
const SYNC_ENTRY_HEADER: int = 8
const RELAY_HEADER: int = 6
## Around each packet, one datagram each: IPv4 + UDP 28; Steam's data header,
## at most 20 (GameNetworkingSockets: header + 1248-byte encrypted payload +
## 32 of occasional stats <= 1300); the AES-GCM tag 16; the message's header
## in the packet, 7 for the first; 9 for acks and stats riding along. Steam may
## pack several messages in one datagram, and ENet (28 + 12) does, so this is
## a ceiling. Steam's own rate doesn't even count the 28 of IP and UDP.
const PACKET_OVERHEAD_BYTES: int = 80

var _failures: int = 0
var _sync_mtu: int = 1350


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var scene_multiplayer := root.multiplayer as SceneMultiplayer
	if scene_multiplayer != null:
		_sync_mtu = scene_multiplayer.max_sync_packet_size
	var crew: int = int(root.get_node(^"/root/NetworkManager").get(&"MAX_PLAYERS"))
	_expect(crew >= 2, "NetworkManager.MAX_PLAYERS is read (got %d)" % crew)

	var box: Node = get_nodes_in_group(&"cargo")[0]
	var player: Node = level.local_player
	var van: Node = level.vehicle
	for node: Node in [box, player, van]:
		var sync := node.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
		_expect(sync.replication_interval > 0.0,
			"%s sends at a fixed rate, not once per rendered frame" % node.name)
	var box_entry: int = SYNC_ENTRY_HEADER + _payload(box)
	var player_entry: int = SYNC_ENTRY_HEADER + _payload(player)
	var van_entry: int = SYNC_ENTRY_HEADER + _payload(van)
	_expect(box_entry > SYNC_ENTRY_HEADER and player_entry > SYNC_ENTRY_HEADER and van_entry > SYNC_ENTRY_HEADER,
		"Every synchronizer checked here was found")
	var box_interval: float = _interval(box)
	var throttle: Node = box.get_node_or_null(^"NetRestThrottle")
	var rest_interval: float = float(throttle.get(&"rest_interval")) if throttle != null else box_interval
	var cargo: int = maxi(get_nodes_in_group(&"cargo").size(), FULL_DEPOT)
	var moving: int = mini(crew, cargo)
	print("Per send: box %d B, player %d B, truck %d B (net id and size included); box at rest every %.2f s" % [
		box_entry, player_entry, van_entry, rest_interval])

	var steady: Dictionary = _host_to_client(crew, [
		[box_interval, box_entry, moving], [rest_interval, box_entry, cargo - moving],
		[_interval(van), van_entry, 1], [_interval(player), player_entry, 1]], _interval(player), player_entry)
	var pile_up: Dictionary = _host_to_client(crew, [
		[box_interval, box_entry, cargo], [_interval(van), van_entry, 1],
		[_interval(player), player_entry, 1]], _interval(player), player_entry)
	print("Host -> one client, steady (%d players, %d of %d boxes moving): %.1f KB/s of %.0f -- %s" % [
		crew, moving, cargo, steady.total / 1024.0, BUDGET_BYTES_PER_SECOND / 1024.0, _breakdown(steady)])
	print("Host -> one client, every box moving: %.1f KB/s of Steam's %.0f -- %s" % [
		pile_up.total / 1024.0, STEAM_SEND_RATE / 1024.0, _breakdown(pile_up)])
	_expect(steady.total < BUDGET_BYTES_PER_SECOND,
		"Host -> one client stays under %.0f KB/s with %d players (%.1f KB/s)" % [
			BUDGET_BYTES_PER_SECOND / 1024.0, crew, steady.total / 1024.0])
	_expect(pile_up.total < STEAM_SEND_RATE,
		"Even with every box moving, Steam doesn't queue (%.1f KB/s of %.0f)" % [
			pile_up.total / 1024.0, STEAM_SEND_RATE / 1024.0])

	var upload: float = steady.total * (crew - 1)
	print("Host upload, steady: %.0f KB/s = %.1f Mbit/s to %d clients, cap %.1f Mbit/s (every box moving: %.1f)" % [
		upload / 1024.0, upload * 8.0 / 1e6, crew - 1, HOST_UPLINK_BYTES_PER_SECOND * 8.0 / 1e6,
		pile_up.total * (crew - 1) * 8.0 / 1e6])
	_expect(upload < HOST_UPLINK_BYTES_PER_SECOND,
		"The host's upload with %d players fits %.1f Mbit/s (%.1f)" % [
			crew, HOST_UPLINK_BYTES_PER_SECOND * 8.0 / 1e6, upload * 8.0 / 1e6])
	var player_rate: float = 1.0 / _interval(player)
	var client_upload: float = player_rate * (SYNC_PACKET_HEADER + player_entry + PACKET_OVERHEAD_BYTES
		+ (crew - 2) * (RELAY_HEADER + SYNC_PACKET_HEADER + player_entry + PACKET_OVERHEAD_BYTES))
	print("Each client uploads its own pose: %.1f KB/s (one copy to the host, %d relayed through it)" % [
		client_upload / 1024.0, crew - 2])

	await _check_throttle(box)
	if _failures == 0:
		print("PASS: with %d players the host fits Steam's send rate and a modest uplink" % crew)
	quit(_failures)


## Bytes per second the host puts on the wire for one client. `groups` are
## [interval, entry bytes, how many] for what the host owns; the other
## clients' players (crew - 2 of them) arrive relayed, a packet each.
func _host_to_client(crew: int, groups: Array, player_interval: float, player_entry: int) -> Dictionary:
	var by_interval: Dictionary = {}
	for group: Array in groups:
		if int(group[2]) <= 0:
			continue
		var entries: Array = by_interval.get_or_add(snappedf(float(group[0]), 0.0001), [])
		for index: int in range(int(group[2])):
			entries.append(int(group[1]))
	var data: float = 0.0
	var packets: float = 0.0
	for interval: float in by_interval:
		var packed: Vector2i = _pack(by_interval[interval])
		packets += packed.x / interval
		data += packed.y / interval
	var relayed: int = maxi(crew - 2, 0)
	var relay_packets: float = relayed / player_interval
	var relay_data: float = relay_packets * (RELAY_HEADER + SYNC_PACKET_HEADER + player_entry)
	var framing: float = (packets + relay_packets) * PACKET_OVERHEAD_BYTES
	return {
		"host": data, "relayed": relay_data, "framing": framing, "datagrams": packets + relay_packets,
		"total": data + relay_data + framing,
	}


## What SceneMultiplayer's _send_sync makes of these entries in one tick:
## (packets, bytes with their headers).
func _pack(entries: Array) -> Vector2i:
	var packets: int = 0
	var bytes: int = 0
	var offset: int = SYNC_PACKET_HEADER
	for entry: int in entries:
		if offset + entry > _sync_mtu and offset > SYNC_PACKET_HEADER:
			packets += 1
			bytes += offset
			offset = SYNC_PACKET_HEADER
		offset += entry
	if offset > SYNC_PACKET_HEADER:
		packets += 1
		bytes += offset
	return Vector2i(packets, bytes)


func _breakdown(case: Dictionary) -> String:
	return "host's sync %.1f, relayed players %.1f, datagram headers %.1f (%d datagrams/s)" % [
		float(case.host) / 1024.0, float(case.relayed) / 1024.0, float(case.framing) / 1024.0,
		roundi(float(case.datagrams))]


## A box left alone drops to its rest interval; moving it brings the full
## rate back the same tick (NetRestThrottle, package.tscn).
func _check_throttle(box: Node) -> void:
	var throttle: Node = box.get_node_or_null(^"NetRestThrottle")
	_expect(throttle != null, "Every box has a NetRestThrottle")
	if throttle == null:
		return
	var sync := box.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var active: float = sync.replication_interval
	var body := box as RigidBody3D
	body.freeze = true
	for tick: int in range(ceili(float(throttle.get(&"settle_seconds")) * Engine.physics_ticks_per_second) + 2):
		await physics_frame
	var rest: float = float(throttle.get(&"rest_interval"))
	_expect(is_equal_approx(sync.replication_interval, rest),
		"A box at rest sends every %.2f s (got %.4f)" % [rest, sync.replication_interval])
	body.global_position += Vector3(0.0, 0.0, 0.2)
	await physics_frame
	_expect(is_equal_approx(sync.replication_interval, active),
		"Moved, it's back to every tick at once (got %.4f)" % sync.replication_interval)


## Bytes one send of this node's synchronizer carries, always-sent
## properties only, as MultiplayerAPI.encode_and_compress_variant sizes them.
func _payload(node: Node) -> int:
	var sync := node.get_node_or_null(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	if sync == null:
		push_error("%s has no MultiplayerSynchronizer" % node.name)
		return 0
	var synced: Node = sync.get_node(sync.root_path)
	var config: SceneReplicationConfig = sync.replication_config
	var bytes: int = 0
	for path: NodePath in config.get_properties():
		if config.property_get_replication_mode(path) != SceneReplicationConfig.REPLICATION_MODE_ALWAYS:
			continue
		var owner_node: Node = synced.get_node(NodePath(path.get_concatenated_names()))
		var size: int = _encoded_size(owner_node.get_indexed(NodePath(path.get_concatenated_subnames())))
		_expect(size <= MAX_ALWAYS_PROPERTY_BYTES,
			"%s %s is sent every tick at %d bytes: make it ON_CHANGE" % [node.name, path, size])
		bytes += size
	return bytes


static func _encoded_size(value: Variant) -> int:
	match typeof(value):
		TYPE_BOOL:
			return 1
		TYPE_INT:
			var number: int = value
			if number >= -128 and number <= 127:
				return 2
			if number >= -32768 and number <= 32767:
				return 3
			if number >= -2147483648 and number <= 2147483647:
				return 5
			return 9
	return var_to_bytes(value).size()


func _interval(node: Node) -> float:
	var sync := node.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	return sync.replication_interval if sync.replication_interval > 0.0 else 1.0 / WORST_FPS


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

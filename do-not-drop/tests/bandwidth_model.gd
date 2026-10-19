extends RefCounted
## The bytes-on-the-wire model shared by the bandwidth budgets (test_net_bandwidth_budget.gd for
## Delivery, test_company_bandwidth_budget.gd for the company's shed). Not a test: preloaded.
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
## - an RPC is a command byte, the node's id (1-4), the method's (1-2) and the
##   argument count, then every argument encoded as above: RPC_HEADER at most;
## - every packet is then a datagram on the wire: PACKET_OVERHEAD_BYTES.

## Steam's default send rate per connection (SendRateMax).
const STEAM_SEND_RATE: float = 256.0 * 1024.0
## SceneMultiplayer's framing: scene_replication_interface.cpp (_send_sync)
## and scene_multiplayer.h (SYS_CMD_SIZE).
const SYNC_PACKET_HEADER: int = 3
const SYNC_ENTRY_HEADER: int = 8
const RELAY_HEADER: int = 6
## An RPC's own header, a ceiling (scene_rpc_interface.cpp, _send_rpc): command 1, node id 4,
## method id 2, argument count 1.
const RPC_HEADER: int = 8
## Around each packet, one datagram each: IPv4 + UDP 28; Steam's data header,
## at most 20 (GameNetworkingSockets: header + 1248-byte encrypted payload +
## 32 of occasional stats <= 1300); the AES-GCM tag 16; the message's header
## in the packet, 7 for the first; 9 for acks and stats riding along. Steam may
## pack several messages in one datagram, and ENet (28 + 12) does, so this is
## a ceiling. Steam's own rate doesn't even count the 28 of IP and UDP.
const PACKET_OVERHEAD_BYTES: int = 80
## What IPv4 and UDP add to a datagram, which ENet's own byte counts leave out.
const IP_UDP_HEADER: int = 28
## A synchronizer with no replication_interval sends once per rendered frame:
## this many, on a fast PC.
const WORST_FPS: float = 144.0


## What SceneMultiplayer's _send_sync makes of these entries in one tick:
## (packets, bytes with their headers), at most `mtu` bytes a packet.
static func pack(entries: Array, mtu: int) -> Vector2i:
	var packets: int = 0
	var bytes: int = 0
	var offset: int = SYNC_PACKET_HEADER
	for entry: int in entries:
		if offset + entry > mtu and offset > SYNC_PACKET_HEADER:
			packets += 1
			bytes += offset
			offset = SYNC_PACKET_HEADER
		offset += entry
	if offset > SYNC_PACKET_HEADER:
		packets += 1
		bytes += offset
	return Vector2i(packets, bytes)


## Bytes per second the host puts on the wire for one client. `groups` are
## [interval, entry bytes, how many] for what the host owns; `relayed` the same
## for what other clients own and reaches this one through the host, a packet
## each. {host, relayed, framing, datagrams, total}: bytes/s of the host's own
## sync packets, of the relayed ones, of the datagrams around all of them, the
## datagrams a second and the sum.
static func host_to_client(groups: Array, relayed: Array, mtu: int) -> Dictionary:
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
		var packed: Vector2i = pack(by_interval[interval], mtu)
		packets += packed.x / interval
		data += packed.y / interval
	var relay_packets: float = 0.0
	var relay_data: float = 0.0
	for group: Array in relayed:
		var count: int = maxi(int(group[2]), 0)
		relay_packets += count / float(group[0])
		relay_data += count / float(group[0]) * (RELAY_HEADER + SYNC_PACKET_HEADER + int(group[1]))
	var framing: float = (packets + relay_packets) * PACKET_OVERHEAD_BYTES
	return {
		"host": data, "relayed": relay_data, "framing": framing, "datagrams": packets + relay_packets,
		"total": data + relay_data + framing,
	}


## Bytes MultiplayerAPI.encode_and_compress_variant gives `value`. With `worst_float` a float
## counts as the 64-bit one it becomes for any value a 32-bit float can't hold (a yaw, a speed
## mid-stride): a pose at rest (0.0) would read 4 bytes less a float.
static func encoded_size(value: Variant, worst_float: bool = false) -> int:
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
		TYPE_FLOAT:
			if worst_float:
				return var_to_bytes(0.1).size()
	return var_to_bytes(value).size()


## Bytes one RPC call carries before its datagram: the header and every argument encoded.
static func rpc_size(args: Array) -> int:
	var bytes: int = RPC_HEADER
	for arg: Variant in args:
		bytes += encoded_size(arg)
	return bytes


## {property path: encoded bytes} of the properties `sync` sends every tick (REPLICATION_MODE_ALWAYS).
static func always_properties(sync: MultiplayerSynchronizer, worst_float: bool = false) -> Dictionary:
	var sizes: Dictionary = {}
	var synced: Node = sync.get_node_or_null(sync.root_path)
	var config: SceneReplicationConfig = sync.replication_config
	if synced == null or config == null:
		return sizes
	for path: NodePath in config.get_properties():
		if config.property_get_replication_mode(path) != SceneReplicationConfig.REPLICATION_MODE_ALWAYS:
			continue
		var owner_node: Node = synced.get_node_or_null(NodePath(path.get_concatenated_names()))
		if owner_node == null:
			continue
		sizes[path] = encoded_size(owner_node.get_indexed(NodePath(path.get_concatenated_subnames())), worst_float)
	return sizes


## Seconds between two sends of `sync`: its replication_interval, or a frame at WORST_FPS without one.
static func interval(sync: MultiplayerSynchronizer) -> float:
	return sync.replication_interval if sync.replication_interval > 0.0 else 1.0 / WORST_FPS

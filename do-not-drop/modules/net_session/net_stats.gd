class_name NetStats
extends RefCounted
## What the network overlay shows (N-216, net_stats_overlay.gd) and the
## `--net-sim` bad-connection profile (docs/investigacion-red.md, fase 0:
## measure before optimising further).
##
## Reading the numbers. On Steam every connection reports its own
## (Steam.getConnectionRealTimeStatus: ping, quality, bytes/s both ways and
## the bytes still waiting to go out). On LAN, ENet reports ping, its
## variance and loss per peer (ENetPacketPeer), but traffic only for the
## whole host (ENetConnection.pop_statistic, which resets on every read), so
## LAN shows KB/s as a total and has no send queue to show. The Steam
## singleton is an Object here (`steam`), never named: CI has no GodotSteam,
## and the tests hand in a stand-in.
##
## `--net-sim=lag,jitter,loss` (ms, ms, %) turns this process's connection
## into a bad one:
## - on Steam the sockets delay, jitter and drop every packet, both ways
##   (Steam's global FAKE_PACKET_* config): half the lag on what goes out and
##   half on what comes in, so the round trip grows by `lag`; each packet, in
##   each direction, waits an extra 0..jitter ms, and `loss` % are dropped;
## - on LAN (ENet simulates nothing) the host's truck poses on a client are
##   held back and dropped, through the `--fake-lag` buffer
##   (vehicle_net_smoother.gd): `lag` + 0..jitter ms late, `loss` % lost. So is
##   the care input the client sends to the host (tender_input_lag.gd, S-205),
##   one way only: `lag` + 0..jitter ms late, `loss` % lost.
## Run it on one side only (the client): on both, the two add up.
## `--net-sim` alone, or `--net-sim=standard`, is the standard test profile
## every network feature goes through: 150 ms, ±20 ms and 2 %.

const SIM_ARG: String = "--net-sim"
const STANDARD_SIM: Dictionary = {"lag_ms": 150, "jitter_ms": 20, "loss_pct": 2.0}
const STANDARD_NAMES: Array[String] = ["standard", "estandar", "std"]
const MAX_SIM_LAG_MS: int = 2000
const MAX_SIM_JITTER_MS: int = 1000

## Valve's ESteamNetworkingConfigValue ids (steamnetworkingtypes.h; the same
## numbers GodotSteam 4.22.1 exposes as Steam.NETWORKING_CONFIG_*). Fixed by
## the SDK's ABI, so they're usable without the extension loaded;
## test_net_stats checks them against the extension when it is.
const STEAM_CONFIG: Dictionary = {
	&"NETWORKING_CONFIG_FAKE_PACKET_LOSS_SEND": 2,
	&"NETWORKING_CONFIG_FAKE_PACKET_LOSS_RECV": 3,
	&"NETWORKING_CONFIG_FAKE_PACKET_LAG_SEND": 4,
	&"NETWORKING_CONFIG_FAKE_PACKET_LAG_RECV": 5,
	&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_SEND_AVG": 53,
	&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_SEND_MAX": 54,
	&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_SEND_PCT": 55,
	&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_RECV_AVG": 56,
	&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_RECV_MAX": 57,
	&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_RECV_PCT": 58,
}

## Where a number turns orange, then red, in the overlay. Ping is the round
## trip; the queue is what Steam holds back once we send past its rate limit
## (256 KB/s by default), so anything that stays there is congestion.
const PING_LIMITS_MS: Array[float] = [100.0, 200.0]
const LOSS_LIMITS_PCT: Array[float] = [1.0, 5.0]
const QUEUE_LIMITS_BYTES: Array[float] = [2048.0, 32768.0]

## The Steam singleton, or a stand-in in tests. Picked up on the first Steam
## sample when left null.
var steam: Object = null
## The previous ENet traffic read (Time.get_ticks_usec()), -1 before any.
var _last_traffic_usec: int = -1


# --- --net-sim ---------------------------------------------------------------

## The `--net-sim` value among the command-line user args: "" when there is
## none, "standard" for a bare `--net-sim`.
static func find_net_sim_arg(args: PackedStringArray) -> String:
	for arg: String in args:
		if arg == SIM_ARG:
			return STANDARD_NAMES[0]
		if arg.begins_with(SIM_ARG + "="):
			return arg.substr(SIM_ARG.length() + 1)
	return ""


## {lag_ms, jitter_ms, loss_pct} from "lag[,jitter[,loss]]" or a standard
## name; {} when the text doesn't say that. Values are clamped to sane ranges.
static func parse_net_sim_value(value: String) -> Dictionary:
	var text: String = value.strip_edges().to_lower()
	if text in STANDARD_NAMES:
		return STANDARD_SIM.duplicate()
	var parts: PackedStringArray = text.split(",")
	if text.is_empty() or parts.size() > 3:
		return {}
	var numbers: Array[float] = []
	for part: String in parts:
		var piece: String = part.strip_edges()
		if not piece.is_valid_float():
			return {}
		numbers.append(float(piece))
	while numbers.size() < 3:
		numbers.append(0.0)
	return {
		"lag_ms": clampi(roundi(numbers[0]), 0, MAX_SIM_LAG_MS),
		"jitter_ms": clampi(roundi(numbers[1]), 0, MAX_SIM_JITTER_MS),
		"loss_pct": clampf(numbers[2], 0.0, 100.0),
	}


## The profile asked for on the command line, {} without one (or a bad one).
static func parse_net_sim(args: PackedStringArray) -> Dictionary:
	var value: String = find_net_sim_arg(args)
	return {} if value.is_empty() else parse_net_sim_value(value)


## "150 ms ±20 ms 2 %": the profile in one short line (numbers and units read
## the same in both languages).
static func describe_sim(sim: Dictionary) -> String:
	if sim.is_empty():
		return ""
	return "%d ms ±%d ms %s %%" % [int(sim.lag_ms), int(sim.jitter_ms), _trim_number(float(sim.loss_pct))]


## Steam's global config values for a profile: [config_id, value, is_float]
## each. Lag splits across both directions, so the round trip grows by `lag`;
## jitter is an exponential draw averaging half of it, capped at `jitter`,
## on every packet; loss drops that share of the packets each way.
static func steam_sim_settings(sim: Dictionary) -> Array:
	var lag: int = int(sim.get("lag_ms", 0))
	var jitter: int = int(sim.get("jitter_ms", 0))
	var loss: float = float(sim.get("loss_pct", 0.0))
	var pct: float = 100.0 if jitter > 0 else 0.0
	return [
		[STEAM_CONFIG[&"NETWORKING_CONFIG_FAKE_PACKET_LAG_SEND"], lag / 2, false],
		[STEAM_CONFIG[&"NETWORKING_CONFIG_FAKE_PACKET_LAG_RECV"], lag - lag / 2, false],
		[STEAM_CONFIG[&"NETWORKING_CONFIG_FAKE_PACKET_LOSS_SEND"], loss, true],
		[STEAM_CONFIG[&"NETWORKING_CONFIG_FAKE_PACKET_LOSS_RECV"], loss, true],
		[STEAM_CONFIG[&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_SEND_AVG"], jitter / 2.0, true],
		[STEAM_CONFIG[&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_SEND_MAX"], jitter, false],
		[STEAM_CONFIG[&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_SEND_PCT"], pct, true],
		[STEAM_CONFIG[&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_RECV_AVG"], jitter / 2.0, true],
		[STEAM_CONFIG[&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_RECV_MAX"], jitter, false],
		[STEAM_CONFIG[&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_RECV_PCT"], pct, true],
	]


## Sets a profile on Steam's sockets (global scope: every connection of this
## process). Each value goes in with the setter of its documented type and,
## if Steam refuses that, with the other one. Returns how many took.
static func apply_steam_sim(steam_api: Object, sim: Dictionary) -> int:
	if steam_api == null or sim.is_empty():
		return 0
	var applied: int = 0
	for setting: Array in steam_sim_settings(sim):
		var config: int = int(setting[0])
		var as_float: bool = bool(setting[2])
		var first: StringName = &"setGlobalConfigValueFloat" if as_float else &"setGlobalConfigValueInt32"
		var second: StringName = &"setGlobalConfigValueInt32" if as_float else &"setGlobalConfigValueFloat"
		if _set_steam_config(steam_api, first, config, setting[1]) \
				or _set_steam_config(steam_api, second, config, setting[1]):
			applied += 1
	return applied


static func _set_steam_config(steam_api: Object, method: StringName, config: int, value: Variant) -> bool:
	if not steam_api.has_method(method):
		return false
	var typed: Variant = float(value) if method == &"setGlobalConfigValueFloat" else roundi(float(value))
	return bool(steam_api.call(method, config, typed))


# --- Reading the connection ----------------------------------------------------

## A row of the overlay with nothing known yet (-1 everywhere).
static func empty_row(peer_id: int) -> Dictionary:
	return {"peer_id": peer_id, "ping_ms": -1, "jitter_ms": -1.0, "loss_pct": -1.0,
		"in_kbps": -1.0, "out_kbps": -1.0, "queued_bytes": -1, "queue_ms": -1.0}


## KB/s from a byte count over a stretch of time (0 for no time at all).
static func kb_per_second(bytes: float, seconds: float) -> float:
	if seconds <= 0.0:
		return 0.0
	return maxf(bytes, 0.0) / 1024.0 / seconds


## GodotSteam's getConnectionRealTimeStatus() dictionary as an overlay row.
## Loss is what Steam's local quality leaves out (the share of packets that
## didn't arrive whole and in order); -1 quality means it doesn't know yet.
static func from_steam_status(peer_id: int, status: Dictionary) -> Dictionary:
	var row: Dictionary = empty_row(peer_id)
	var data: Dictionary = status.get("connection_status") if status.get("connection_status") is Dictionary else status
	if not data.has("ping"):
		return row
	row.ping_ms = int(data.ping)
	var quality: float = float(data.get("local_quality", -1.0))
	row.loss_pct = clampf((1.0 - quality) * 100.0, 0.0, 100.0) if quality >= 0.0 else -1.0
	if data.has("bytes_in_per_second"):
		row.in_kbps = float(data.bytes_in_per_second) / 1024.0
	if data.has("bytes_out_per_second"):
		row.out_kbps = float(data.bytes_out_per_second) / 1024.0
	if data.has("pending_unreliable") or data.has("pending_reliable"):
		row.queued_bytes = int(data.get("pending_unreliable", 0)) + int(data.get("pending_reliable", 0))
	if data.has("queue_time"):
		row.queue_ms = float(data.queue_time) / 1000.0
	return row


## An ENet peer's numbers as an overlay row: round trip and its variance in
## ms, loss as ENet keeps it (a share of ENetPacketPeer.PACKET_LOSS_SCALE).
static func from_enet(peer_id: int, rtt_ms: float, rtt_variance_ms: float, packet_loss: float) -> Dictionary:
	var row: Dictionary = empty_row(peer_id)
	row.ping_ms = roundi(rtt_ms)
	row.jitter_ms = rtt_variance_ms
	row.loss_pct = clampf(packet_loss * 100.0 / ENetPacketPeer.PACKET_LOSS_SCALE, 0.0, 100.0)
	return row


## 0 fine, 1 worrying, 2 bad, for `metric` in &"ping", &"loss", &"queue";
## unknown values (below 0) are fine.
static func severity(metric: StringName, value: float) -> int:
	var limits: Array[float] = PING_LIMITS_MS
	match metric:
		&"loss":
			limits = LOSS_LIMITS_PCT
		&"queue":
			limits = QUEUE_LIMITS_BYTES
	if value < limits[0]:
		return 0
	return 1 if value < limits[1] else 2


## The round trip to `peer_id` over `peer`, in seconds; 0 when it isn't known
## (offline, not connected, this peer itself, another transport). ENet reads
## its own peer's estimate; Steam its connection's ping (`steam_api`, or the
## Steam singleton when there is one).
static func round_trip_seconds(peer: Object, peer_id: int, steam_api: Object = null) -> float:
	var real_peer := peer as MultiplayerPeer
	if real_peer == null or real_peer is OfflineMultiplayerPeer \
			or real_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED \
			or peer_id <= 0 or peer_id == real_peer.get_unique_id():
		return 0.0
	if real_peer is ENetMultiplayerPeer:
		var packet_peer: ENetPacketPeer = (real_peer as ENetMultiplayerPeer).get_peer(peer_id)
		return packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 1000.0 if packet_peer != null else 0.0
	return steam_round_trip(peer, peer_id, steam_api)


## round_trip_seconds() over a Steam peer (anything with get_peer(id) whose
## peer has get_connection_handle()): its connection's ping, 0 when unknown --
## no handle yet (0, still connecting), no Steam, no status.
static func steam_round_trip(steam_peer: Object, peer_id: int, steam_api: Object = null) -> float:
	if steam_peer == null or not steam_peer.has_method(&"get_peer"):
		return 0.0
	if steam_api == null and Engine.has_singleton(&"Steam"):
		steam_api = Engine.get_singleton(&"Steam")
	var packet: Object = steam_peer.call(&"get_peer", peer_id)
	if steam_api == null or packet == null or not packet.has_method(&"get_connection_handle") \
			or not steam_api.has_method(&"getConnectionRealTimeStatus"):
		return 0.0
	var handle: int = int(packet.call(&"get_connection_handle"))
	if handle == 0:
		return 0.0
	var status: Variant = steam_api.call(&"getConnectionRealTimeStatus", handle, 0, true)
	return maxf(float(from_steam_status(peer_id, status if status is Dictionary else {}).ping_ms), 0.0) / 1000.0


## How much further than its reach a request from `peer_id` may land and
## still count, on the host: what someone at `speed` (m/s) covers in a round
## trip, at most `cap` metres. The client saw its target a round trip ago (and
## a cushion more, NetPoseSmoother), and its target kept moving meanwhile.
static func reach_slack(peer: Object, peer_id: int, speed: float = 5.0, cap: float = 1.5) -> float:
	return slack_for_round_trip(round_trip_seconds(peer, peer_id), speed, cap)


static func slack_for_round_trip(round_trip: float, speed: float = 5.0, cap: float = 1.5) -> float:
	return clampf(speed * round_trip, 0.0, cap)


## KB/s in and out from the bytes counted since the previous call (ENet's
## host counters reset on every read). The first call only starts the clock
## and returns -1 for both.
func rates_from_deltas(in_bytes: int, out_bytes: int, now_usec: int) -> Vector2:
	var previous: int = _last_traffic_usec
	_last_traffic_usec = now_usec
	if previous < 0 or now_usec <= previous:
		return Vector2(-1.0, -1.0)
	var seconds: float = float(now_usec - previous) / 1000000.0
	return Vector2(kb_per_second(in_bytes, seconds), kb_per_second(out_bytes, seconds))


## Everything the overlay shows about `peer` right now: {transport (&"offline",
## &"enet", &"steam" or &"other"), is_host, peers (one row per direct
## connection), in_kbps, out_kbps, queued_bytes}; -1 where it isn't known.
## `remote_ids` are the other peers in the session; a client only has a
## connection of its own to the host, so it only reads that one.
func sample(peer: Object, remote_ids: Array, now_usec: int) -> Dictionary:
	var result: Dictionary = {"transport": &"offline", "is_host": true, "peers": [],
		"in_kbps": -1.0, "out_kbps": -1.0, "queued_bytes": -1}
	if peer == null or peer is OfflineMultiplayerPeer or not peer.has_method(&"get_unique_id"):
		_last_traffic_usec = -1
		return result
	if peer is ENetMultiplayerPeer:
		result.transport = &"enet"
	elif peer.has_method(&"get_steam_id_for_peer_id") and peer.has_method(&"get_peer"):
		result.transport = &"steam"
	else:
		result.transport = &"other"
	# Still connecting, or already closed: nothing to read yet (and asking its
	# id then is an engine error).
	var real_peer := peer as MultiplayerPeer
	if real_peer != null and real_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		_last_traffic_usec = -1
		return result
	var local: int = int(peer.call(&"get_unique_id"))
	result.is_host = local == 1
	var ids: Array[int] = []
	for id: Variant in remote_ids:
		if int(id) != local and (result.is_host or int(id) == 1) and not ids.has(int(id)):
			ids.append(int(id))
	if result.transport == &"enet":
		return _sample_enet(peer as ENetMultiplayerPeer, ids, now_usec, result)
	if result.transport == &"steam":
		return _sample_steam(peer, ids, result)
	return result


func _sample_enet(enet: ENetMultiplayerPeer, ids: Array[int], now_usec: int, result: Dictionary) -> Dictionary:
	for id: int in ids:
		var packet_peer: ENetPacketPeer = enet.get_peer(id)
		if packet_peer == null:
			continue
		result.peers.append(from_enet(id, packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
			packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE),
			packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)))
	var connection: ENetConnection = enet.host
	if connection != null:
		var rates: Vector2 = rates_from_deltas(int(connection.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)),
			int(connection.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)), now_usec)
		result.in_kbps = rates.x
		result.out_kbps = rates.y
	return result


func _sample_steam(steam_peer: Object, ids: Array[int], result: Dictionary) -> Dictionary:
	if steam == null and Engine.has_singleton(&"Steam"):
		steam = Engine.get_singleton(&"Steam")
	if steam == null or not steam.has_method(&"getConnectionRealTimeStatus"):
		return result
	var total_in: float = 0.0
	var total_out: float = 0.0
	var total_queue: int = 0
	var any_rate: bool = false
	var any_queue: bool = false
	for id: int in ids:
		var packet_peer: Object = steam_peer.call(&"get_peer", id)
		if packet_peer == null or not packet_peer.has_method(&"get_connection_handle"):
			continue
		var handle: int = int(packet_peer.call(&"get_connection_handle"))
		if handle == 0:
			continue
		var status: Variant = steam.call(&"getConnectionRealTimeStatus", handle, 0, true)
		var row: Dictionary = from_steam_status(id, status if status is Dictionary else {})
		result.peers.append(row)
		if float(row.in_kbps) >= 0.0:
			total_in += float(row.in_kbps)
			total_out += maxf(float(row.out_kbps), 0.0)
			any_rate = true
		if int(row.queued_bytes) >= 0:
			total_queue += int(row.queued_bytes)
			any_queue = true
	if any_rate:
		result.in_kbps = total_in
		result.out_kbps = total_out
	if any_queue:
		result.queued_bytes = total_queue
	return result


static func _trim_number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value

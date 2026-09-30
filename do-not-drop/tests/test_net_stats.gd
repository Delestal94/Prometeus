extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_net_stats.gd
##
## The network overlay and the bad-connection simulation (N-216), without a
## real network:
## - `--net-sim=lag,jitter,loss` parses (partial values, `standard` and a bare
##   `--net-sim` are the 150 ms / ±20 ms / 2 % profile), clamps, and rejects
##   what it doesn't understand (net_stats.gd);
## - on Steam it becomes Steam's FAKE_PACKET_* global config, the lag split
##   across both directions, with the SDK's ids (checked against GodotSteam
##   when the extension is loaded), and each value retries with the other
##   setter if Steam refuses its type; NetworkManager applies it when Steam
##   comes up, and hands it to the truck's pose buffer only off Steam
##   (pose_net_sim());
## - KB/s from byte counters (ENet's reset on every read, so the first read
##   only starts the clock), ENet's loss scale, and a GodotSteam real-time
##   status turned into ping, loss, KB/s both ways and queued bytes; a Steam
##   host gets a row per client plus totals, a client only reads the host;
## - the overlay (net_stats_overlay.gd) hangs from NetworkManager, starts
##   hidden and idle, F3 (`toggle_net_stats`) shows it and hides it again,
##   solo it says so, it names the simulated profile, and a connected sample
##   lays out a row per peer, coloured by how bad each number is.

# gdlint: disable=function-name
# The stand-ins keep GodotSteam's camelCase method names.
class FakeSteam:
	extends RefCounted
	var calls: Array = []
	var statuses: Dictionary = {}
	## Config ids whose float setter fails, as Steam does for int32 values.
	var int_only: Array = []

	func setGlobalConfigValueInt32(config: int, value: int) -> bool:
		calls.append([config, value, "int"])
		return true

	func setGlobalConfigValueFloat(config: int, value: float) -> bool:
		if config in int_only:
			return false
		calls.append([config, value, "float"])
		return true

	func getConnectionRealTimeStatus(handle: int, _lanes: int, _get_status: bool) -> Dictionary:
		return statuses.get(handle, {"response": 3})


class FakeSteamConnection:
	extends RefCounted
	var handle: int = 0

	func _init(value: int) -> void:
		handle = value

	func get_connection_handle() -> int:
		return handle


class FakeSteamPeer:
	extends RefCounted
	var unique_id: int = 1
	var connections: Dictionary = {}
	var asked: Array = []

	func get_unique_id() -> int:
		return unique_id

	func get_steam_id_for_peer_id(peer_id: int) -> int:
		return 76561190000000000 + peer_id

	func get_peer(peer_id: int) -> Object:
		asked.append(peer_id)
		return connections.get(peer_id)
# gdlint: enable=function-name


var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_parsing()
	_check_steam_settings()
	_check_rates_and_rows()
	_check_steam_sample()
	_check_network_manager()
	await _check_overlay()
	if _failures == 0:
		print("PASS: net overlay reads ping, loss, KB/s and queue; --net-sim reaches Steam and the truck buffer")
	quit(_failures)


func _check_parsing() -> void:
	_expect(NetStats.parse_net_sim(PackedStringArray()).is_empty(), "No --net-sim, no simulation")
	var full: Dictionary = NetStats.parse_net_sim(PackedStringArray(["--host-lan", "--net-sim=150,20,2"]))
	_expect(full == {"lag_ms": 150, "jitter_ms": 20, "loss_pct": 2.0},
		"--net-sim=150,20,2 is 150 ms, 20 ms and 2 %% (got %s)" % full)
	_expect(NetStats.parse_net_sim(PackedStringArray(["--net-sim"])) == NetStats.STANDARD_SIM,
		"A bare --net-sim is the standard profile")
	_expect(NetStats.parse_net_sim(PackedStringArray(["--net-sim=standard"])) == NetStats.STANDARD_SIM,
		"--net-sim=standard is the standard profile")
	_expect(NetStats.STANDARD_SIM == {"lag_ms": 150, "jitter_ms": 20, "loss_pct": 2.0},
		"The standard profile is 150 ms, ±20 ms and 2 %% (got %s)" % NetStats.STANDARD_SIM)
	var partial: Dictionary = NetStats.parse_net_sim_value("80, 5")
	_expect(partial == {"lag_ms": 80, "jitter_ms": 5, "loss_pct": 0.0},
		"Missing values are zero (got %s)" % partial)
	var fractional: Dictionary = NetStats.parse_net_sim_value("100,0,0.5")
	_expect(is_equal_approx(float(fractional.get("loss_pct", -1.0)), 0.5),
		"Loss may be fractional (got %s)" % fractional)
	var clamped: Dictionary = NetStats.parse_net_sim_value("99999,-4,250")
	_expect(clamped == {"lag_ms": NetStats.MAX_SIM_LAG_MS, "jitter_ms": 0, "loss_pct": 100.0},
		"Values are clamped to sane ranges (got %s)" % clamped)
	for bad: String in ["abc", "150,x", "1,2,3,4", ""]:
		_expect(NetStats.parse_net_sim_value(bad).is_empty(), "'%s' is not a profile" % bad)
	_expect(NetStats.describe_sim(NetStats.STANDARD_SIM) == "150 ms ±20 ms 2 %",
		"The profile reads '150 ms ±20 ms 2 %%' (got '%s')" % NetStats.describe_sim(NetStats.STANDARD_SIM))


func _check_steam_settings() -> void:
	var by_id: Dictionary = {}
	for setting: Array in NetStats.steam_sim_settings(NetStats.STANDARD_SIM):
		by_id[int(setting[0])] = setting[1]
	var config: Dictionary = NetStats.STEAM_CONFIG
	_expect(by_id.size() == 10, "Ten Steam settings: lag, loss and jitter, each way (got %d)" % by_id.size())
	_expect(int(by_id.get(config[&"NETWORKING_CONFIG_FAKE_PACKET_LAG_SEND"], -1)) \
			+ int(by_id.get(config[&"NETWORKING_CONFIG_FAKE_PACKET_LAG_RECV"], -1)) == 150,
		"The lag splits across sending and receiving, adding 150 ms to the round trip (got %s)" % by_id)
	for way: String in ["SEND", "RECV"]:
		var loss: Variant = by_id.get(config[StringName("NETWORKING_CONFIG_FAKE_PACKET_LOSS_" + way)])
		_expect(loss != null and is_equal_approx(float(loss), 2.0), "Loss %s is 2 %% (got %s)" % [way, loss])
		var cap: Variant = by_id.get(config[StringName("NETWORKING_CONFIG_FAKE_PACKET_JITTER_%s_MAX" % way)])
		_expect(cap != null and int(cap) == 20, "Jitter %s is capped at 20 ms (got %s)" % [way, cap])
		var share: Variant = by_id.get(config[StringName("NETWORKING_CONFIG_FAKE_PACKET_JITTER_%s_PCT" % way)])
		_expect(share != null and is_equal_approx(float(share), 100.0),
			"Jitter %s hits every packet (got %s)" % [way, share])
	# The ids are Valve's; GodotSteam must agree wherever it's loaded.
	if ClassDB.class_exists(&"Steam"):
		for name: StringName in config:
			var known: bool = ClassDB.class_has_integer_constant(&"Steam", name)
			_expect(known and ClassDB.class_get_integer_constant(&"Steam", name) == int(config[name]),
				"Steam.%s is %d in GodotSteam" % [name, int(config[name])])

	var steam := FakeSteam.new()
	steam.int_only = [config[&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_SEND_AVG"]]
	var applied: int = NetStats.apply_steam_sim(steam, NetStats.STANDARD_SIM)
	_expect(applied == 10, "Every setting reaches Steam (got %d)" % applied)
	var avg_call: Array = steam.calls.filter(func(entry: Array) -> bool:
		return int(entry[0]) == int(config[&"NETWORKING_CONFIG_FAKE_PACKET_JITTER_SEND_AVG"]))
	_expect(avg_call.size() == 1 and avg_call[0][2] == "int" and int(avg_call[0][1]) == 10,
		"A value Steam refuses as float goes in as int32 instead (got %s)" % [avg_call])
	_expect(NetStats.apply_steam_sim(null, NetStats.STANDARD_SIM) == 0 and NetStats.apply_steam_sim(steam, {}) == 0,
		"Without Steam or without a profile nothing is set")


func _check_rates_and_rows() -> void:
	_expect(is_equal_approx(NetStats.kb_per_second(5120.0, 0.5), 10.0), "5 KB in half a second is 10 KB/s")
	_expect(NetStats.kb_per_second(5120.0, 0.0) == 0.0, "No time, no rate")
	var stats := NetStats.new()
	var first: Vector2 = stats.rates_from_deltas(999, 999, 1_000_000)
	_expect(first == Vector2(-1.0, -1.0), "The first counter read only starts the clock (got %s)" % first)
	var second: Vector2 = stats.rates_from_deltas(5120, 10240, 1_500_000)
	_expect(second.is_equal_approx(Vector2(10.0, 20.0)),
		"5 KB in and 10 KB out in 0.5 s are 10 and 20 KB/s (got %s)" % second)
	var third: Vector2 = stats.rates_from_deltas(0, 2048, 2_500_000)
	_expect(third.is_equal_approx(Vector2(0.0, 2.0)), "Each read measures only its own stretch (got %s)" % third)

	var enet_row: Dictionary = NetStats.from_enet(1, 42.4, 3.0, ENetPacketPeer.PACKET_LOSS_SCALE / 50.0)
	_expect(int(enet_row.ping_ms) == 42 and is_equal_approx(float(enet_row.loss_pct), 2.0)
			and float(enet_row.jitter_ms) == 3.0,
		"ENet's round trip, variance and loss scale read as 42 ms, ±3 ms and 2 %% (got %s)" % enet_row)

	var status: Dictionary = {"response": 1, "connection_status": {"state": 3, "ping": 152, "local_quality": 0.98,
		"remote_quality": 0.97, "bytes_in_per_second": 5120.0, "bytes_out_per_second": 40960.0,
		"pending_unreliable": 1000, "pending_reliable": 500, "sent_unacknowledged_reliable": 64, "queue_time": 4000}}
	var steam_row: Dictionary = NetStats.from_steam_status(2, status)
	_expect(int(steam_row.ping_ms) == 152, "Steam's ping comes through (got %s)" % steam_row.ping_ms)
	_expect(is_equal_approx(float(steam_row.loss_pct), 2.0),
		"98 %% local quality is 2 %% loss (got %s)" % steam_row.loss_pct)
	_expect(is_equal_approx(float(steam_row.in_kbps), 5.0) and is_equal_approx(float(steam_row.out_kbps), 40.0),
		"Bytes per second become 5 KB/s in and 40 KB/s out (got %s / %s)" % [steam_row.in_kbps, steam_row.out_kbps])
	_expect(int(steam_row.queued_bytes) == 1500 and is_equal_approx(float(steam_row.queue_ms), 4.0),
		"Queued bytes are what's pending, reliable or not (got %s B, %s ms)" % [
			steam_row.queued_bytes, steam_row.queue_ms])
	var unknown: Dictionary = NetStats.from_steam_status(3, {"response": 3})
	_expect(int(unknown.ping_ms) == -1 and float(unknown.loss_pct) == -1.0 and int(unknown.queued_bytes) == -1,
		"A connection Steam can't report on stays unknown (got %s)" % unknown)
	var fresh: Dictionary = NetStats.from_steam_status(3, {"connection_status": {"ping": 20, "local_quality": -1.0}})
	_expect(float(fresh.loss_pct) == -1.0,
		"Quality -1 (not measured yet) is unknown loss, not 200 %% (got %s)" % fresh.loss_pct)

	var ping_levels: Array = [60.0, 150.0, 250.0].map(func(ms: float) -> int: return NetStats.severity(&"ping", ms))
	_expect(ping_levels == [0, 1, 2], "Ping turns orange past 100 ms and red past 200 ms (got %s)" % [ping_levels])
	var loss_levels: Array = [0.5, 2.0, 8.0].map(func(pct: float) -> int: return NetStats.severity(&"loss", pct))
	_expect(loss_levels == [0, 1, 2], "Loss turns orange past 1 %% and red past 5 %% (got %s)" % [loss_levels])
	var queue_levels: Array = [0.0, 4096.0, 65536.0].map(func(b: float) -> int: return NetStats.severity(&"queue", b))
	_expect(queue_levels == [0, 1, 2], "A send queue that builds up turns orange, then red (got %s)" % [queue_levels])

	var offline: Dictionary = stats.sample(OfflineMultiplayerPeer.new(), [], 0)
	_expect(offline.transport == &"offline" and (offline.peers as Array).is_empty(),
		"Playing solo reads as offline (got %s)" % offline)
	var idle_enet: Dictionary = stats.sample(ENetMultiplayerPeer.new(), [1, 2], 0)
	_expect(idle_enet.transport == &"enet" and (idle_enet.peers as Array).is_empty(),
		"An ENet peer that isn't connected reads as LAN with no rows, without errors (got %s)" % idle_enet)


func _check_steam_sample() -> void:
	var steam := FakeSteam.new()
	steam.statuses[11] = {"response": 1, "connection_status": {"ping": 152, "local_quality": 0.98,
		"bytes_in_per_second": 5120.0, "bytes_out_per_second": 40960.0,
		"pending_unreliable": 1000, "pending_reliable": 500}}
	steam.statuses[12] = {"response": 1, "connection_status": {"ping": 40, "local_quality": 1.0,
		"bytes_in_per_second": 1024.0, "bytes_out_per_second": 20480.0, "pending_unreliable": 0, "pending_reliable": 0}}
	var host := FakeSteamPeer.new()
	host.connections = {2: FakeSteamConnection.new(11), 3: FakeSteamConnection.new(12), 4: FakeSteamConnection.new(0)}
	var stats := NetStats.new()
	stats.steam = steam
	var sample: Dictionary = stats.sample(host, [1, 2, 3, 4], 0)
	var rows: Array = sample.peers
	_expect(sample.transport == &"steam" and bool(sample.is_host), "A Steam host reads Steam (got %s)" % sample)
	_expect(rows.size() == 2 and int(rows[0].peer_id) == 2 and int(rows[1].peer_id) == 3,
		"A row per client with a live connection; none for a closed one (got %s)" % [rows])
	_expect(is_equal_approx(float(sample.in_kbps), 6.0) and is_equal_approx(float(sample.out_kbps), 60.0)
			and int(sample.queued_bytes) == 1500,
		"Totals add every connection up: 6 KB/s in, 60 KB/s out, 1500 B queued (got %s / %s / %s)" % [
			sample.in_kbps, sample.out_kbps, sample.queued_bytes])

	var client := FakeSteamPeer.new()
	client.unique_id = 2
	client.connections = {1: FakeSteamConnection.new(11)}
	var client_sample: Dictionary = stats.sample(client, [1, 2, 3], 0)
	_expect(not bool(client_sample.is_host) and client.asked == [1] and (client_sample.peers as Array).size() == 1,
		"A client only reads its own connection, the host's (asked %s)" % [client.asked])


func _check_network_manager() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	_expect((network.get(&"net_sim") as Dictionary).is_empty(), "No --net-sim in the tests, nothing simulated")
	network.call(&"_read_net_sim", PackedStringArray(["--net-sim=150,20,2"]))
	_expect(network.get(&"net_sim") == NetStats.STANDARD_SIM,
		"NetworkManager keeps the parsed profile (got %s)" % network.get(&"net_sim"))
	network.set(&"active_transport", 2)  # Transport.ENET
	_expect(network.call(&"pose_net_sim") == NetStats.STANDARD_SIM, "On LAN the truck's pose buffer simulates it")
	var smoother := NetPoseSmoother.new()
	smoother.configure_sim(network.call(&"pose_net_sim"))
	_expect(is_equal_approx(smoother.fake_lag, 0.15) and is_equal_approx(smoother.fake_jitter, 0.02)
			and is_equal_approx(smoother.fake_loss, 0.02),
		"A truck built on LAN under --net-sim holds poses 150 ms + 0..20 ms and drops 2 %% (got %s, %s, %s)" % [
			smoother.fake_lag, smoother.fake_jitter, smoother.fake_loss])
	network.set(&"active_transport", 1)  # Transport.STEAM
	_expect((network.call(&"pose_net_sim") as Dictionary).is_empty(), "On Steam the sockets simulate it, not the truck")
	var steam_smoother := NetPoseSmoother.new()
	steam_smoother.configure_sim(network.call(&"pose_net_sim"))
	_expect(is_equal_approx(steam_smoother.fake_loss, 0.0),
		"A truck built on Steam doesn't drop poses itself")
	var steam := FakeSteam.new()
	network.set(&"_steam", steam)
	network.call(&"_apply_steam_net_sim")
	_expect(steam.calls.size() == 10, "Steam coming up takes the profile (got %d settings)" % steam.calls.size())
	network.set(&"_steam", null)
	network.set(&"active_transport", 2)
	network.call(&"_read_net_sim", PackedStringArray(["--net-sim=loud"]))
	_expect((network.get(&"net_sim") as Dictionary).is_empty(), "A profile it can't read simulates nothing")
	network.set(&"net_sim", {})


func _check_overlay() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var overlay: CanvasLayer = network.get_node_or_null(^"NetStatsOverlay") as CanvasLayer
	_expect(overlay != null, "NetworkManager mounts the network overlay")
	if overlay == null:
		return
	_expect(not overlay.visible and not overlay.is_processing(), "The overlay starts hidden and idle")
	_expect(overlay.process_mode == Node.PROCESS_MODE_ALWAYS, "The overlay works in the pause menu too")
	_expect(InputMap.has_action(&"toggle_net_stats"), "project.godot has the toggle_net_stats action")
	var bound_f3: bool = false
	for event: InputEvent in InputMap.action_get_events(&"toggle_net_stats"):
		bound_f3 = bound_f3 or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F3)
	_expect(bound_f3, "toggle_net_stats is on F3")

	root.push_input(_f3(true))
	root.push_input(_f3(false))
	await process_frame
	_expect(overlay.visible and overlay.is_processing(), "F3 shows the overlay, and only then it refreshes")
	var title: Label = overlay.get(&"title_label")
	var message: Label = overlay.get(&"message_label")
	var sim_label: Label = overlay.get(&"sim_label")
	var grid: GridContainer = overlay.get(&"grid")
	_expect(title.text == tr("HUD_NET_STATS_TITLE_OFFLINE") and message.visible
			and message.text == tr("HUD_NET_STATS_OFFLINE"),
		"Solo, the overlay says there's no connection (got '%s' / '%s')" % [title.text, message.text])
	_expect(not grid.visible and not sim_label.visible, "Solo and without --net-sim there are no rows and no profile")
	var hint: Label = overlay.get(&"hint_label")
	_expect(hint.text == tr("HUD_NET_STATS_HINT") % "F3", "The overlay says which key hides it (got '%s')" % hint.text)

	network.set(&"net_sim", NetStats.STANDARD_SIM.duplicate())
	overlay.call(&"refresh")
	_expect(sim_label.visible and sim_label.text == tr("HUD_NET_STATS_SIM_LAN") % "150 ms ±20 ms 2 %",
		"With --net-sim the overlay names the profile (got '%s')" % sim_label.text)
	network.set(&"net_sim", {})

	var row: Dictionary = NetStats.empty_row(2)
	row.merge({"ping_ms": 152, "loss_pct": 2.0, "in_kbps": 5.0, "out_kbps": 40.0, "queued_bytes": 1500}, true)
	overlay.call(&"_draw_sample", {"transport": &"steam", "is_host": true, "peers": [row],
		"in_kbps": 5.0, "out_kbps": 40.0, "queued_bytes": 1500})
	var cells: Array = grid.get_children().filter(func(cell: Node) -> bool: return not cell.is_queued_for_deletion())
	_expect(title.text == tr("HUD_NET_STATS_TITLE") % [tr("HUD_NET_STATS_STEAM"), tr("HUD_NET_STATS_ROLE_HOST")],
		"Connected, the title names transport and role (got '%s')" % title.text)
	_expect(grid.visible and not message.visible and cells.size() == 18,
		"A header, a row per peer and the totals, six columns each (got %d cells)" % cells.size())
	if cells.size() == 18:
		var ping_cell: Label = cells[7]
		var loss_cell: Label = cells[8]
		var queue_cell: Label = cells[11]
		var in_cell: Label = cells[9]
		var out_cell: Label = cells[10]
		_expect(ping_cell.text == "152 ms" and in_cell.text == "5.0" and out_cell.text == "40.0",
			"The row reads 152 ms, 5.0 in and 40.0 out (got %s, %s, %s)" % [
				ping_cell.text, in_cell.text, out_cell.text])
		_expect(queue_cell.text == "1.5 KB", "1500 queued bytes read as 1.5 KB (got '%s')" % queue_cell.text)
		_expect(loss_cell.get_theme_color(&"font_color") == UiTheme.state_color(1),
			"2 %% loss is coloured as worrying")
		_expect(ping_cell.get_theme_color(&"font_color") == UiTheme.state_color(1),
			"152 ms is coloured as worrying")

	root.push_input(_f3(true))
	root.push_input(_f3(false))
	await process_frame
	_expect(not overlay.visible and not overlay.is_processing(), "F3 again hides it and it stops reading")


func _f3(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F3
	event.keycode = KEY_F3
	event.pressed = pressed
	return event


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

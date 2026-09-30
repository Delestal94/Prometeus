class_name NetStatsOverlay
extends CanvasLayer
## The network overlay: a key (`toggle_action`) shows, on this machine only,
## how the connection is doing -- transport and role, the `--net-sim` profile
## if one is on, and a row per direct connection with ping, loss, KB/s in
## and out and the bytes waiting to be sent, plus the totals. The numbers
## come from NetStats; this only lays them out, twice a second, and only
## while it's shown.
##
## Portable module (docs/modulos.md): a NetSession mounts it (so it lives
## across scenes and works on any screen, paused or not) and sets `session`;
## the game subclasses it for its own font and colours (_theme(),
## _severity_color()). Texts go through tr() with HUD_NET_STATS_* keys: a
## game without those translations shows the keys. Starts hidden;
## `--net-stats` on the command line starts it shown. Nothing here touches
## the network: a peer's overlay is its own business.

const START_SHOWN_ARG: String = "--net-stats"
const REFRESH_SECONDS: float = 0.5
const LAYER: int = 120
const FONT_SIZE: int = 14
const NA: String = "—"
const COLUMNS: int = 6

## The input action that shows and hides it.
var toggle_action: StringName = &"toggle_net_stats"
## The session whose `--net-sim` profile is shown; the parent when unset.
var session: NetSession = null
var stats := NetStats.new()
var title_label: Label
var sim_label: Label
var message_label: Label
var grid: GridContainer
var hint_label: Label
## The last sample shown, for tests and anyone curious.
var last_sample: Dictionary = {}
var _since_refresh: float = 0.0
var _theme_cache: Dictionary = {}


func _ready() -> void:
	name = "NetStatsOverlay"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_shown(START_SHOWN_ARG in OS.get_cmdline_user_args())


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action(toggle_action) or not event.is_action_pressed(toggle_action, false, true):
		return
	set_shown(not visible)
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh >= REFRESH_SECONDS:
		refresh()


## Built the first time it's shown: most sessions never open it, and every
## headless test would otherwise load its fonts for nothing.
func set_shown(value: bool) -> void:
	visible = value
	set_process(value)
	if value:
		if title_label == null:
			_build()
		refresh()


## Reads the connection now and redraws.
func refresh() -> void:
	_since_refresh = 0.0
	if title_label == null:
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer if is_inside_tree() else null
	var online: bool = peer != null and not peer is OfflineMultiplayerPeer
	var remote_ids: Array = Array(multiplayer.get_peers()) if online else []
	last_sample = stats.sample(peer, remote_ids, Time.get_ticks_usec())
	_draw_sample(last_sample)


func _draw_sample(sample: Dictionary) -> void:
	var transport: StringName = sample.get("transport", &"offline")
	var online: bool = transport != &"offline"
	var transport_text: String = tr("HUD_NET_STATS_STEAM") if transport == &"steam" else tr("HUD_NET_STATS_LAN")
	var host: bool = bool(sample.get("is_host", true))
	var role_text: String = tr("HUD_NET_STATS_ROLE_HOST") if host else tr("HUD_NET_STATS_ROLE_CLIENT")
	if online:
		title_label.text = tr("HUD_NET_STATS_TITLE") % [transport_text, role_text]
	else:
		title_label.text = tr("HUD_NET_STATS_TITLE_OFFLINE")
	var sim: Dictionary = _net_sim()
	sim_label.visible = not sim.is_empty()
	if not sim.is_empty():
		var sim_key: String = "HUD_NET_STATS_SIM" if transport == &"steam" else "HUD_NET_STATS_SIM_LAN"
		sim_label.text = tr(sim_key) % NetStats.describe_sim(sim)
	var rows: Array = sample.get("peers", [])
	message_label.visible = rows.is_empty()
	message_label.text = tr("HUD_NET_STATS_ALONE") if online else tr("HUD_NET_STATS_OFFLINE")
	grid.visible = online
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	if not online:
		return
	var muted: Color = _colour("muted")
	var paper: Color = _colour("paper")
	for key: String in ["HUD_NET_STATS_COL_PEER", "HUD_NET_STATS_COL_PING", "HUD_NET_STATS_COL_LOSS",
			"HUD_NET_STATS_COL_IN", "HUD_NET_STATS_COL_OUT", "HUD_NET_STATS_COL_QUEUE"]:
		_cell(tr(key), muted)
	for row: Dictionary in rows:
		var id: int = int(row.peer_id)
		_cell(tr("HUD_NET_STATS_ROLE_HOST") if id == 1 else str(id), paper)
		_cell(_ping_text(row), _metric_color(&"ping", float(row.ping_ms)))
		_cell(_percent_text(float(row.loss_pct)), _metric_color(&"loss", float(row.loss_pct)))
		_cell(_rate_text(float(row.in_kbps)), paper)
		_cell(_rate_text(float(row.out_kbps)), paper)
		_cell(_bytes_text(int(row.queued_bytes)), _metric_color(&"queue", float(row.queued_bytes)))
	_cell(tr("HUD_NET_STATS_TOTAL"), muted)
	_cell("", paper)
	_cell("", paper)
	_cell(_rate_text(float(sample.get("in_kbps", -1.0))), paper)
	_cell(_rate_text(float(sample.get("out_kbps", -1.0))), paper)
	var queued: int = int(sample.get("queued_bytes", -1))
	_cell(_bytes_text(queued), _metric_color(&"queue", float(queued)))


## The profile the session parsed from `--net-sim`, if any.
func _net_sim() -> Dictionary:
	var owner_session: NetSession = session if session != null else get_parent() as NetSession
	return owner_session.net_sim.duplicate() if owner_session != null else {}


func _build() -> void:
	_theme_cache = _theme()
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(_colour("ink"), 0.86)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	# Bottom right: the corner a HUD usually leaves free.
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -16.0
	panel.offset_bottom = -16.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	title_label = _label(column, _colour("title"))
	sim_label = _label(column, _colour("sim"))
	message_label = _label(column, _colour("paper"))
	grid = GridContainer.new()
	grid.name = "Rows"
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	column.add_child(grid)
	hint_label = _label(column, _colour("muted"))
	hint_label.text = tr("HUD_NET_STATS_HINT") % _key_name()


func _label(parent: Node, color: Color) -> Label:
	var node := Label.new()
	var font: Font = _theme_cache.get("font")
	if font != null:
		node.add_theme_font_override("font", font)
	node.add_theme_font_size_override("font_size", FONT_SIZE)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _cell(text: String, color: Color) -> void:
	var node: Label = _label(grid, color)
	node.text = text
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _colour(key: String) -> Color:
	return _theme_cache.get(key, Color.WHITE)


func _metric_color(metric: StringName, value: float) -> Color:
	if value < 0.0:
		return _colour("paper")
	return _severity_color(NetStats.severity(metric, value))


## The key that toggles the overlay, as the keyboard labels it.
func _key_name() -> String:
	if InputMap.has_action(toggle_action):
		for event: InputEvent in InputMap.action_get_events(toggle_action):
			var key := event as InputEventKey
			if key != null:
				return OS.get_keycode_string(key.physical_keycode if key.keycode == KEY_NONE else key.keycode)
	return "F3"


static func _ping_text(row: Dictionary) -> String:
	if int(row.ping_ms) < 0:
		return NA
	if float(row.jitter_ms) >= 0.0:
		return "%d ±%d ms" % [int(row.ping_ms), roundi(float(row.jitter_ms))]
	return "%d ms" % int(row.ping_ms)


static func _percent_text(value: float) -> String:
	return NA if value < 0.0 else "%.1f %%" % value


static func _rate_text(value: float) -> String:
	return NA if value < 0.0 else "%.1f" % value


static func _bytes_text(bytes: int) -> String:
	if bytes < 0:
		return NA
	return "%d B" % bytes if bytes < 1024 else "%.1f KB" % (bytes / 1024.0)


# --- Hooks the game fills in ---------------------------------------------------

## Font (or null for the default) and colours: "ink" (panel), "paper"
## (numbers), "muted" (headers), "title", "sim".
func _theme() -> Dictionary:
	return {"font": null, "ink": Color(0.1, 0.1, 0.14), "paper": Color(0.98, 0.96, 0.9),
		"muted": Color(0.6, 0.58, 0.55), "title": Color(0.55, 0.8, 1.0), "sim": Color(1.0, 0.85, 0.3)}


## The colour of a metric at NetStats.severity() 0 (fine), 1 (worse), 2 (bad).
func _severity_color(severity: int) -> Color:
	return [Color(0.55, 0.9, 0.55), Color(1.0, 0.85, 0.3), Color(1.0, 0.45, 0.4)][clampi(severity, 0, 2)]

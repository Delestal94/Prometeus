class_name CompanyPhone
extends Control
## The player's phone in the company world (expansion D-1923, with D-0331): raised with `phone_toggle` (F / LB),
## a phone screen on the right with two apps, switched by their tabs or by `company_clipboard_prev` / `_next`
## (Q / E, LB / RB while it is up):
## - Pedidos: the open orders (OrderBook.open_orders()), oldest first: id, customer, zone and the time left, or
##   "atrasado" past its due_min;
## - Mapa: the map of the zones (ZoneDefinition.bounds, metres on X/Z) with each zone's name and how many open
##   orders go there, and a dot where the player stands.
## It reads what every peer has (order book, clock, zones, its own player); nothing is sent. Like the clipboard it is
## a hand tool (group HAND_TOOL_GROUP: is_open() / stow()): raising one puts the other away. Hands busy (a package,
## a seat), another screen taking the input, or the pause keep it down; while up the mouse is free and the player's
## input is off; `phone_toggle`, ui_cancel or the clipboard's stow (B) put it away.

signal opened
signal closed

const ACTION_TOGGLE: StringName = &"phone_toggle"
const HAND_TOOL_GROUP: StringName = &"hand_tool"
const APP_ORDERS: StringName = &"orders"
const APP_MAP: StringName = &"map"
const APPS: Array[StringName] = [APP_ORDERS, APP_MAP]
## Each app's tab name (literal keys, so the translation tests see them used).
const APP_KEYS: Dictionary = {APP_ORDERS: "UI_CPHONE_APP_ORDERS", APP_MAP: "UI_CPHONE_APP_MAP"}
const SCREEN_SIZE := Vector2(380, 600)
const MAP_SIZE := Vector2(330, 420)
const MAX_ROWS: int = 9
const REFRESH_SECONDS: float = 0.5

## () -> Array: open orders; () -> float: the game minute; () -> Array: ZoneDefinitions; () -> Node3D: the player;
## () -> bool: something else owns the screen or the hands (pause, a panel, a package, a seat).
var orders_of: Callable = func() -> Array: return []
var minute_of: Callable = func() -> float: return 0.0
var zones_of: Callable = func() -> Array: return []
var player_of: Callable = func() -> Node3D: return null
var blocked: Callable = func() -> bool: return false

var app: StringName = APP_ORDERS
var _up: bool = false
var _wait: float = 0.0
var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _player_off: Node = null
var _tabs: Dictionary = {}
var _orders_box: VBoxContainer
var _map: CompanyPhoneMap


## The phone on its own layer under `root` (CompanyRoot: net, clock, zones, player).
static func add_to(root: Node) -> CompanyPhone:
	var layer := CanvasLayer.new()
	layer.name = "CompanyPhoneLayer"
	layer.layer = 5
	root.add_child(layer)
	var phone := CompanyPhone.new()
	phone.name = "CompanyPhone"
	var net: Object = root.get(&"net")
	var clock: Object = root.get(&"clock")
	if net != null:
		phone.orders_of = func() -> Array: return net.orders.book.open_orders() if net.orders != null else []
	if clock != null:
		phone.minute_of = func() -> float: return clock.minute_now()
	phone.zones_of = func() -> Array: return root.get(&"zones") if is_instance_valid(root) else []
	phone.player_of = func() -> Node3D: return root.get(&"player") as Node3D if is_instance_valid(root) else null
	phone.blocked = func() -> bool: return _hands_busy(phone.player_of.call())
	layer.add_child(phone)
	return phone


## True when `player` cannot take the phone out: gone, carrying or tending a package, seated, knocked out, or
## its input switched off by another screen.
static func _hands_busy(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return true
	if is_instance_valid(player.get(&"carried_package")) or is_instance_valid(player.get(&"tended_package")):
		return true
	var seat: Variant = player.get(&"seat_node_path")
	if seat is NodePath and not (seat as NodePath).is_empty():
		return true
	return bool(player.get(&"_ragdolled")) or not player.is_processing_unhandled_input()


func _ready() -> void:
	add_to_group(HAND_TOOL_GROUP)
	UiTheme.apply(self)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	offset_left = -SCREEN_SIZE.x - 40.0
	offset_right = -40.0
	offset_top = -SCREEN_SIZE.y * 0.5
	offset_bottom = SCREEN_SIZE.y * 0.5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	hide()


func is_open() -> bool:
	return _up


## Takes the phone out on `on_app` (the last one when &""). False when something keeps it down.
func raise(on_app: StringName = &"") -> bool:
	if _up:
		show_app(on_app if on_app != &"" else app)
		return true
	# The other hand tool goes first: up, it holds the player's input, which would read as busy hands.
	for tool: Node in get_tree().get_nodes_in_group(HAND_TOOL_GROUP):
		if tool != self and tool.has_method(&"stow"):
			tool.call(&"stow")
	if bool(blocked.call()) or get_tree().paused:
		return false
	_up = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player: Node = player_of.call()
	if player != null:
		player.set_process_unhandled_input(false)
		_player_off = player
	show()
	show_app(on_app if on_app != &"" else app)
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)
	opened.emit()
	return true


## Puts it away; nothing when it is down.
func stow() -> void:
	if not _up:
		return
	_up = false
	hide()
	Input.mouse_mode = _mouse_before
	if _player_off != null and is_instance_valid(_player_off):
		_player_off.set_process_unhandled_input(true)
	_player_off = null
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	closed.emit()


## Switches to `which` (an entry of APPS) and redraws it.
func show_app(which: StringName) -> void:
	if not APPS.has(which):
		return
	app = which
	_orders_box.get_parent().visible = app == APP_ORDERS
	_map.visible = app == APP_MAP
	for id: StringName in _tabs:
		(_tabs[id] as Button).button_pressed = id == app
	refresh()
	(_tabs[app] as Button).grab_focus.call_deferred()


## Redraws the app showing.
func refresh() -> void:
	if app == APP_ORDERS:
		_fill_orders()
	else:
		_map.zones = zones_of.call()
		_map.counts = zone_counts(orders_of.call())
		var player: Node3D = player_of.call()
		_map.player_at = player.global_position if player != null and player.is_inside_tree() else null
		_map.queue_redraw()


## The orders app's lines: [id, text, late], at most MAX_ROWS.
func order_lines() -> Array:
	var lines: Array = []
	var now: float = float(minute_of.call())
	for raw: Variant in orders_of.call():
		if not raw is Dictionary or lines.size() >= MAX_ROWS:
			continue
		var order: Dictionary = raw
		var left: int = int(order.get("due_min", 0)) - floori(now)
		var when: String = tr("UI_CPHONE_LATE") if left < 0 else tr("UI_CPHONE_LEFT") % left
		var zone: String = DistrictLabel.district_name(StringName(str(order.get("zone", ""))))
		var text: String = tr("UI_CPHONE_ROW") % [str(order.get("id", "")), str(order.get("customer", "")), zone, when]
		lines.append([str(order.get("id", "")), text, left < 0])
	return lines


## Open orders per zone id.
static func zone_counts(orders: Array) -> Dictionary:
	var counts: Dictionary = {}
	for raw: Variant in orders:
		if raw is Dictionary:
			var zone := StringName(str((raw as Dictionary).get("zone", "")))
			counts[zone] = int(counts.get(zone, 0)) + 1
	return counts


func _process(delta: float) -> void:
	if not _up:
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH_SECONDS
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not _up and event.is_action_pressed(ACTION_TOGGLE) and raise():
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _up:
		return
	if event.is_action_pressed(ACTION_TOGGLE) or event.is_action_pressed(&"ui_cancel") \
			or event.is_action_pressed(CompanyClipboard.ACTION_STOW):
		stow()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(CompanyClipboard.ACTION_PREV) or event.is_action_pressed(CompanyClipboard.ACTION_NEXT):
		var step: int = 1 if event.is_action_pressed(CompanyClipboard.ACTION_NEXT) else -1
		show_app(APPS[posmod(APPS.find(app) + step, APPS.size())])
		get_viewport().set_input_as_handled()


func _build() -> void:
	var column: VBoxContainer = UiTheme.panel(self, SCREEN_SIZE, 16, UiTheme.INK)
	column.add_theme_constant_override("separation", 8)
	var tabs := HBoxContainer.new()
	tabs.name = "Apps"
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	for id: StringName in APPS:
		var tab: Button = UiTheme.button(tabs, tr(APP_KEYS[id]))
		tab.name = "App_%s" % id
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(show_app.bind(id))
		_tabs[id] = tab
	var scroll := ScrollContainer.new()
	scroll.name = "Orders"
	scroll.custom_minimum_size = Vector2(0, MAP_SIZE.y)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_orders_box = VBoxContainer.new()
	_orders_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_orders_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_orders_box)
	_map = CompanyPhoneMap.new()
	_map.name = "Map"
	_map.custom_minimum_size = MAP_SIZE
	column.add_child(_map)
	UiTheme.label(column, tr("UI_CPHONE_HINT"), 14, UiTheme.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _fill_orders() -> void:
	for child: Node in _orders_box.get_children():
		_orders_box.remove_child(child)
		child.queue_free()
	var lines: Array = order_lines()
	if lines.is_empty():
		UiTheme.label(_orders_box, tr("UI_CPHONE_NO_ORDERS"), 16, UiTheme.MUTED).name = "Empty"
	for line: Array in lines:
		var label: Label = UiTheme.label(_orders_box, String(line[1]), 15,
			UiTheme.status(2, self) if bool(line[2]) else UiTheme.WHITE)
		label.name = "Order_%s" % line[0]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

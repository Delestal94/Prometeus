class_name CompanyDayHud
extends Control
## The company day's HUD (expansion D-1903, with D-0519): a strip in the top-left corner with the day and the
## time, the team's money and the orders still to deliver. It only reads what every peer already has: the
## clock's minute (GameClock.minute_now(), the same on every peer), the company mirror (day, money) and the
## order book (OrderBook.open_orders()). No RPC and no state of its own; it redraws REFRESH_SECONDS apart.
##
## - Time: "Día 3 · 10:45", "Pausa" while the clock is stopped (the coop pause, the frozen shed).
## - Money: "$1250", red when the company is in the red (Bankruptcy's line is the opening notice, D-0510).
## - Orders: "Pedidos: 4" (open orders), orange when one is late (minute past its `due_min`).
## Each value comes through a Callable so a test, or a world without some part, can feed it.

const REFRESH_SECONDS: float = 0.25
const KEY_DAY_TIME: String = "UI_DAYHUD_DAY_TIME"
const KEY_PAUSED: String = "UI_DAYHUD_PAUSED"
const KEY_ORDERS: String = "UI_DAYHUD_ORDERS"

## () -> float: the game minute now; () -> bool: the clock stopped; () -> int: day and money;
## () -> Array: the open orders ({due_min...}).
var minute_of: Callable = func() -> float: return float(CompanyTuning.DAY_START_MIN)
var paused_of: Callable = func() -> bool: return false
var day_of: Callable = func() -> int: return 1
var money_of: Callable = func() -> int: return 0
var orders_of: Callable = func() -> Array: return []

var _time_label: Label
var _money_label: Label
var _orders_label: Label
var _wait: float = 0.0


## The HUD on its own layer under `root` (CompanyRoot), reading root.clock and root.net.
static func add_to(root: Node) -> CompanyDayHud:
	var layer := CanvasLayer.new()
	layer.name = "CompanyDayHudLayer"
	root.add_child(layer)
	var hud := CompanyDayHud.new()
	hud.name = "CompanyDayHud"
	var clock: Object = root.get(&"clock")
	var net: Object = root.get(&"net")
	if clock != null:
		hud.minute_of = func() -> float: return clock.minute_now()
		hud.paused_of = func() -> bool: return clock.is_paused()
	if net != null:
		hud.day_of = func() -> int: return int(net.company.day) if net.company != null else 1
		hud.money_of = func() -> int: return int(net.company.money) if net.company != null else 0
		hud.orders_of = func() -> Array: return net.orders.book.open_orders() if net.orders != null else []
	layer.add_child(hud)
	return hud


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = 24.0
	offset_top = 20.0
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_time_label = UiTheme.chip(row, "", UiTheme.WHITE, 18)
	_time_label.name = "Time"
	_money_label = UiTheme.chip(row, "", UiTheme.YELLOW, 18)
	_money_label.name = "Money"
	_orders_label = UiTheme.chip(row, "", UiTheme.WHITE, 18)
	_orders_label.name = "Orders"
	refresh()


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH_SECONDS
		refresh()


## Redraws the three values now.
func refresh() -> void:
	if _time_label == null:
		return
	_time_label.text = time_text(float(minute_of.call()), int(day_of.call()), bool(paused_of.call()))
	var money: int = int(money_of.call())
	_money_label.text = DaySummaryPanel.money(money)
	_money_label.add_theme_color_override(&"font_color", UiTheme.RED if money < 0 else UiTheme.INK)
	var orders: Array = orders_of.call()
	_orders_label.text = tr(KEY_ORDERS) % orders.size()
	var late: bool = late_count(orders, float(minute_of.call())) > 0
	_orders_label.add_theme_color_override(&"font_color", UiTheme.ORANGE if late else UiTheme.INK)


func texts() -> Array[String]:
	return [_time_label.text, _money_label.text, _orders_label.text] if _time_label != null else []


## "Día 3 · 10:45" (the minute wraps past midnight), or "Día 3 · Pausa" while stopped.
func time_text(minute: float, day: int, paused: bool) -> String:
	var shown: String = tr(KEY_PAUSED) if paused else clock_text(minute)
	return tr(KEY_DAY_TIME) % [day, shown]


static func clock_text(minute: float) -> String:
	var whole: int = posmod(floori(minute), CompanyTuning.MINUTES_PER_DAY)
	return "%02d:%02d" % [whole / 60, whole % 60]


## Open orders whose `due_min` is already past `minute` (an order without one is never late).
static func late_count(orders: Array, minute: float) -> int:
	var late: int = 0
	for order: Variant in orders:
		if order is Dictionary and (order as Dictionary).has("due_min") \
				and float((order as Dictionary)["due_min"]) < minute:
			late += 1
	return late

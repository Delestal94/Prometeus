extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_day_hud.gd
##
## The company day's HUD (expansion D-1903, with D-0519), checked on its labels (no screenshot):
## - "Día 3 · 10:45" from the clock's minute (wrapping past midnight) and "Pausa" while the clock is stopped;
## - the money as "$1250", red when the company is in the red;
## - "Pedidos: N" for the open orders, orange when one is past its due_min;
## - it redraws on its own every REFRESH_SECONDS and never takes the mouse;
## - add_to() reads a root's clock and net (company day and money, the order book's open orders), on its layer;
## - CompanyRoot adds it through CompanyUi; both languages have its keys.

const KEYS: Array[String] = ["UI_DAYHUD_DAY_TIME", "UI_DAYHUD_PAUSED", "UI_DAYHUD_ORDERS"]

var _failures: int = 0


class FakeClock:
	extends Node
	var minute: float = 645.0
	var stopped: bool = false

	func minute_now() -> float:
		return minute

	func is_paused() -> bool:
		return stopped


class FakeCompany:
	extends RefCounted
	var day: int = 4
	var money: int = 900


class FakeBook:
	extends RefCounted
	var open: Array[Dictionary] = [{"id": &"a", "due_min": 700}]

	func open_orders() -> Array[Dictionary]:
		return open


class FakeOrders:
	extends RefCounted
	var book := FakeBook.new()


class FakeNet:
	extends Node
	var company: Object = FakeCompany.new()
	var orders: Object = FakeOrders.new()


class FakeRoot:
	extends Node
	var clock: Node = null
	var net: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in KEYS:
			_expect(TranslationServer.translate(key) != key, "%s has %s" % [locale, key])
	TranslationServer.set_locale("es")
	await _test_values()
	await _test_add_to()
	_test_wiring()
	if _failures == 0:
		print("PASS: the day's HUD shows the time, the money and the open orders")
	quit(_failures)


func _test_values() -> void:
	_expect(CompanyDayHud.clock_text(645.0) == "10:45", "10:45")
	_expect(CompanyDayHud.clock_text(1440.0 + 61.5) == "01:01", "the clock wraps past midnight")
	_expect(CompanyDayHud.late_count([{"due_min": 600}, {"due_min": 700}, {}, "x"], 650.0) == 1, "one late order")
	var hud := CompanyDayHud.new()
	var minute: Array[float] = [480.0]
	var stopped: Array[bool] = [false]
	var money: Array[int] = [1250]
	var orders: Array = [{"due_min": 600}, {"due_min": 900}]
	hud.minute_of = func() -> float: return minute[0]
	hud.paused_of = func() -> bool: return stopped[0]
	hud.day_of = func() -> int: return 3
	hud.money_of = func() -> int: return money[0]
	hud.orders_of = func() -> Array: return orders
	root.add_child(hud)
	await process_frame
	_expect(hud.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the HUD lets the mouse through")
	_expect(Array(hud.texts()) == ["Día 3 · 08:00", "$1250", "Pedidos: 2"], "the three values (got %s)" % [hud.texts()])
	var orders_label := hud.find_child("Orders", true, false) as Label
	_expect(orders_label.get_theme_color(&"font_color") == UiTheme.INK, "no late order: ink")
	minute[0] = 610.0
	stopped[0] = true
	money[0] = -40
	hud.refresh()
	_expect(Array(hud.texts()) == ["Día 3 · Pausa", "-$40", "Pedidos: 2"], "paused and in the red (got %s)"
		% [hud.texts()])
	var money_label := hud.find_child("Money", true, false) as Label
	_expect(money_label.get_theme_color(&"font_color") == UiTheme.RED, "the red is red")
	_expect(orders_label.get_theme_color(&"font_color") == UiTheme.ORANGE, "a late order turns the count orange")
	stopped[0] = false
	minute[0] = 615.0
	for i: int in 3:
		await process_frame
	await create_timer(CompanyDayHud.REFRESH_SECONDS + 0.05).timeout
	_expect(hud.texts()[0] == "Día 3 · 10:15", "it redraws on its own (got %s)" % hud.texts()[0])
	TranslationServer.set_locale("en")
	hud.refresh()
	_expect(Array(hud.texts()) == ["Day 3 · 10:15", "-$40", "Orders: 2"], "in English (got %s)" % [hud.texts()])
	TranslationServer.set_locale("es")
	hud.queue_free()
	await process_frame


func _test_add_to() -> void:
	var fake_root := FakeRoot.new()
	fake_root.clock = FakeClock.new()
	fake_root.net = FakeNet.new()
	fake_root.add_child(fake_root.clock)
	fake_root.add_child(fake_root.net)
	root.add_child(fake_root)
	var hud: CompanyDayHud = CompanyDayHud.add_to(fake_root)
	await process_frame
	_expect(hud.get_parent() is CanvasLayer, "the HUD has its own layer")
	_expect(Array(hud.texts()) == ["Día 4 · 10:45", "$900", "Pedidos: 1"], "it reads the root's clock and net (got %s)"
		% [hud.texts()])
	fake_root.queue_free()
	await process_frame


func _test_wiring() -> void:
	var root_source: String = FileAccess.get_file_as_string("res://scripts/gameplay/company_root.gd")
	var ui_source: String = FileAccess.get_file_as_string("res://scripts/ui/company_ui.gd")
	_expect(root_source.contains("CompanyUi.add_to(self)") and ui_source.contains("CompanyDayHud.add_to(root)"),
		"CompanyRoot adds the HUD through CompanyUi")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1

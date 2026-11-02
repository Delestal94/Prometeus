extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_phone.gd
##
## The player's phone in the company world (expansion D-1923, with D-0331), on its nodes (no screenshot):
## - phone_toggle takes it out (mouse free, the player's input off) on the orders app and puts it away again
##   (input back); ui_cancel puts it away too; busy hands (a package) keep it down;
## - Pedidos lists the open orders oldest first with customer, zone and minutes left, "atrasado" (danger colour)
##   past their due_min, and says so when there are none;
## - Q / E (company_clipboard_prev / _next) switch to Mapa and back; the map fits every real zone
##   (data/zones) inside it, puts the player's world spot on the map inside its zone's rectangle, and counts the
##   open orders per zone;
## - it is a hand tool with the clipboard: raising one puts the other away;
## - CompanyUi adds it; both languages have its keys.

const KEYS: Array[String] = ["UI_CPHONE_APP_ORDERS", "UI_CPHONE_APP_MAP", "UI_CPHONE_NO_ORDERS", "UI_CPHONE_ROW",
	"UI_CPHONE_LEFT", "UI_CPHONE_LATE", "UI_CPHONE_HINT"]

var _failures: int = 0


class FakePlayer:
	extends Node3D
	var carried_package: Node = null
	var tended_package: Node = null
	var seat_node_path: NodePath = NodePath()
	var _ragdolled: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in KEYS:
			_expect(TranslationServer.translate(key) != key, "%s has %s" % [locale, key])
	TranslationServer.set_locale("es")
	CompanyClipboard.ensure_actions()
	await _test_phone()
	_test_wiring()
	if _failures == 0:
		print("PASS: the company phone lists the open orders, maps the zones and shares the hands with the clipboard")
	quit(_failures)


func _test_phone() -> void:
	var zones: Array = CompanyRoot.load_zones()
	var centro: ZoneDefinition = null
	for zone: ZoneDefinition in zones:
		if zone.id == &"centro":
			centro = zone
	var player := FakePlayer.new()
	root.add_child(player)
	player.set_process_unhandled_input(true)
	player.global_position = Vector3(centro.bounds.get_center().x, 0.0, centro.bounds.get_center().y)
	var orders: Array = [
		{"id": "d2_o01", "customer": "Rosa", "zone": "centro", "due_min": 700},
		{"id": "d2_o02", "customer": "Tito", "zone": "centro", "due_min": 500},
	]
	var phone := CompanyPhone.new()
	phone.orders_of = func() -> Array: return orders
	phone.minute_of = func() -> float: return 600.0
	phone.zones_of = func() -> Array: return zones
	phone.player_of = func() -> Node3D: return player
	phone.blocked = func() -> bool: return CompanyPhone._hands_busy(player)
	root.add_child(phone)
	await process_frame
	_expect(phone.is_in_group(CompanyPhone.HAND_TOOL_GROUP) and not phone.visible, "a hand tool, down at first")
	_press(CompanyPhone.ACTION_TOGGLE)
	await process_frame
	_expect(phone.is_open() and phone.visible and phone.app == CompanyPhone.APP_ORDERS, "F takes it out on Pedidos")
	_expect(not player.is_processing_unhandled_input(), "the player's input is off while it is up")
	var rosa := phone.find_child("Order_d2_o01", true, false) as Label
	var tito := phone.find_child("Order_d2_o02", true, false) as Label
	_expect(rosa != null and rosa.text.contains("Rosa") and rosa.text.contains("quedan 100 min"),
		"an order with its time left (%s)" % (rosa.text if rosa != null else "none"))
	_expect(tito != null and tito.text.contains("atrasado")
		and tito.get_theme_color(&"font_color") == UiTheme.status(2, phone), "a late order says so, in danger")
	_press(CompanyClipboard.ACTION_NEXT)
	await process_frame
	_expect(phone.app == CompanyPhone.APP_MAP, "E switches to the map")
	var map := phone.find_child("Map", true, false) as CompanyPhoneMap
	await process_frame
	_expect(map != null and map.visible and map.size.x > 0.0, "the map shows")
	if map != null:
		for zone: ZoneDefinition in zones:
			var rect: Rect2 = map.zone_rect(zone)
			_expect(rect.has_area() and Rect2(Vector2.ZERO, map.size).grow(0.5).encloses(rect),
				"%s fits the map (%s in %s)" % [zone.id, rect, map.size])
		var dot: Variant = map.map_point(player.global_position)
		_expect(dot is Vector2 and map.zone_rect(centro).has_point(dot), "the player's dot sits in Centro")
		_expect(map.counts.get(&"centro", 0) == 2, "two open orders go to Centro")
	_press(CompanyClipboard.ACTION_PREV)
	await process_frame
	_expect(phone.app == CompanyPhone.APP_ORDERS, "Q comes back")
	_press(&"ui_cancel")
	await process_frame
	_expect(not phone.is_open() and player.is_processing_unhandled_input(), "Esc puts it away, the input comes back")
	orders.clear()
	player.carried_package = Node.new()
	_expect(not phone.raise(), "a package in the hands keeps it down")
	player.carried_package.free()
	player.carried_package = null
	_expect(phone.raise() and phone.find_child("Empty", true, false) != null, "no orders: it says so")
	var clip := CompanyClipboard.new()
	clip.player_of = func() -> Node: return player
	clip.peer_id = func() -> int: return 1
	root.add_child(clip)
	await process_frame
	clip.frame.add_sheet(CompanyClipboard.SHEET_STOCK, "Stock", Control.new())
	_expect(clip.raise() and not phone.is_open(), "the clipboard puts the phone away")
	_expect(phone.raise() and not clip.is_up(), "the phone puts the clipboard away")
	phone.stow()
	clip.queue_free()
	phone.queue_free()
	player.queue_free()
	await process_frame


func _test_wiring() -> void:
	var ui_source: String = FileAccess.get_file_as_string("res://scripts/ui/company_ui.gd")
	_expect(ui_source.contains("CompanyPhone.add_to(root)"), "CompanyUi adds the phone")


func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1

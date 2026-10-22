extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_stock_board.gd
##
## The stock list in the company's world (expansion D-0612.b), StockBoard:
## - the action (I / gamepad d-pad right) is registered once with both devices;
## - context() marks the products the host's pending orders are short of, and a peer without the
##   order book (a client until D-0813.1) gets the list with no marks;
## - incoming_from() adds up the supplier calendar from a day on; the board counts it as "on the way"
##   only with a real calendar (the stand-in one brings nothing);
## - open() shows the panel, frees the mouse and turns the local player's input off; close() gives both
##   back; an open list is blocked while the build mode is on;
## - a change the net applies redraws the open list from this peer's inventory;
## - CompanyRoot carries the board on every peer.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	_test_action()
	_test_context()
	_test_incoming()
	await _test_open_close()
	await _test_refresh()
	_test_root_has_board()
	if _failures == 0:
		print("PASS: stock board opens the list, frees and returns input, marks shortages and refreshes")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _inventory() -> Inventory:
	var inv := Inventory.new()
	inv.receive(&"hen", 1, &"shelf:a")
	return inv


func _book(qty: int) -> OrderBook:
	var book := OrderBook.new()
	var items: Array = [{"product": &"hen", "qty": qty}]
	var order: Dictionary = Order.make(&"o1", "Ana", &"centro", &"h1", items, 0, {})
	_expect(book.add(order), "the test order goes in the book")
	return book


func _test_action() -> void:
	StockBoard.ensure_action()
	StockBoard.ensure_action()
	var events: Array[InputEvent] = InputMap.action_get_events(StockBoard.ACTION_TOGGLE)
	var key: bool = false
	var pad: bool = false
	for event: InputEvent in events:
		key = key or event is InputEventKey
		pad = pad or event is InputEventJoypadButton
	_expect(events.size() == 2 and key and pad, "the action has one key and one pad button (got %d)" % events.size())


func _test_context() -> void:
	var with_book: Dictionary = StockBoard.context(_inventory(), _book(4), {}, {})
	var list: Array = with_book["shortages"]
	_expect(list.size() == 1 and list[0]["product"] == &"hen" and list[0]["missing"] == 3,
		"the host's book marks the hen as 3 short (got %s)" % [list])
	var no_book: Dictionary = StockBoard.context(_inventory(), null, {}, {})
	_expect(no_book["shortages"].is_empty(), "without the book there are no marks")
	_expect(StockBoard.context(null, null, {}, {})["inventory"] == null, "no inventory yet is passed on as null")


func _test_incoming() -> void:
	var schedule := SupplierSchedule.new()
	_expect(schedule.place(2, [{"product": &"hen", "qty": 2}]), "an order for day 3 is placed")
	_expect(schedule.place(4, [{"product": &"hen", "qty": 5}]), "an order for day 5 is placed")
	var sum: Dictionary = StockBoard.incoming_from(schedule, 4)
	_expect(sum.get(&"hen", 0) == 5, "from day 4 only the later truck counts (got %s)" % [sum])
	_expect(StockBoard.incoming_from(schedule, 0).get(&"hen", 0) == 7, "from day 0 both trucks add up")
	_expect(StockBoard.incoming_from(null, 0).is_empty(), "no calendar, nothing incoming")


class FakePlayer extends Node:
	func input_on() -> bool:
		return is_processing_unhandled_input()


func _make_board(book: OrderBook, player: FakePlayer) -> Array:
	var net := CompanyNet.new()
	net.name = "CompanyNet"
	root.add_child(net)
	net.inventory = _inventory()
	var board := StockBoard.new()
	root.add_child(board)
	board.setup(net)
	board.book_of = func() -> OrderBook:
		return book
	board.player_of = func() -> Node:
		return player
	return [board, net]


func _test_open_close() -> void:
	var player := FakePlayer.new()
	player.set_process_unhandled_input(true)
	root.add_child(player)
	var made: Array = _make_board(_book(4), player)
	var board: StockBoard = made[0]
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_expect(board.open(), "the list opens")
	_expect(board.is_open() and board.panel.visible, "the panel is on screen")
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the mouse is free while it is open")
	_expect(not player.input_on(), "the player's input is off while it is open")
	_expect(not board.open(), "an open list is not opened twice")
	board.close()
	_expect(not board.is_open(), "close hides the panel")
	_expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "the mouse goes back to what it was")
	_expect(player.input_on(), "the player's input is back")
	var building: bool = true
	board.busy = func() -> bool:
		return building
	_expect(not board.open() and not board.is_open(), "the build mode keeps the list closed")
	building = false
	_expect(board.open(), "once the build mode ends it opens")
	board.close()
	(made[1] as Node).queue_free()
	board.queue_free()
	player.queue_free()
	await process_frame


func _test_refresh() -> void:
	var made: Array = _make_board(_book(4), null)
	var board: StockBoard = made[0]
	var net: CompanyNet = made[1]
	await process_frame
	board.open()
	await process_frame
	var before: Button = board.panel.find_child("Row_hen", true, false) as Button
	var shown: String = before.text if before != null else "no row"
	_expect(before != null and "Faltan 3" in before.text, "the hen row says 3 are missing (got %s)" % shown)
	net.inventory.receive(&"hen", 3, &"shelf:a")
	net.event_applied.emit(1, &"units_moved", {})
	await process_frame
	var after: Button = board.panel.find_child("Row_hen", true, false) as Button
	var now: String = after.text if after != null else "no row"
	_expect(after != null and not ("Faltan" in now), "after the move the mark is gone (got %s)" % now)
	_expect(after != null and "Total 4" in now, "the total follows the move (got %s)" % now)
	board.close()
	net.queue_free()
	board.queue_free()
	await process_frame


func _test_root_has_board() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/gameplay/company_root.gd")
	_expect("stock_board = StockBoard.new()" in source and "_add_stock_board()" in source,
		"CompanyRoot builds the board on every peer")

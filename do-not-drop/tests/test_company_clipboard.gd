extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_clipboard.gd
##
## The management clipboard of the company's world (expansion D-1902, diseno/portapapeles.md):
## company_clipboard.gd, clipboard_frame.gd, player_held_tool.gd and the embedded mode of stock_panel.gd and
## supplier_order_panel.gd.
## - the actions: company_clipboard (I, d-pad right), company_clipboard_prev (Q, LB) and _next (E, RB) are
##   registered once with one key and one pad button each, company_clipboard_stow with B only;
## - the embedded panels: no dark backdrop, no title, no Close and no ui_cancel of their own (Esc does not close
##   them); set_embedded() on a built panel rebuilds it and keeps the supplier cart;
## - on the real root, solo, with the keyboard: I raises it on the Stock sheet (the frame shows, the
##   player's input is off, PlayerHeldTool.held_tool is clipboard_up and the 3D board hangs from the hand), E /
##   Q turn the sheets (wrapping) and only the sheet showing draws, Esc stows it without opening the pause (the
##   next Esc does open it) and I stows it too; a click on a tab changes sheet;
## - with the gamepad: d-pad right raises it, RB goes to the Supplier sheet whose first plus takes the focus,
##   d-pad right on the plus (the right edge of the row) keeps the focus there and the clipboard raised,
##   d-pad left goes to the minus and d-pad down to the next row, B stows it;
## - PlayerHeldTool.set_held() leaves a copy of another peer's player alone (only the owner writes);
## - busy hands: units in this peer's hands, a seat, the phone up or the build mode keep it in; raised, units
##   coming into the hands put it away; the build mode does not start while it is raised (ShedBuilder.busy);
## - the shed's supplier board is a shortcut that raises it on the Supplier sheet, and the board's close()
##   stows it; the day's summary and the pause asked for (EventBus.pause_requested) stow it; it remembers
##   the last sheet.
## Expected in the log: the engine's leak notes at exit.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_clipboard"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	_test_actions()
	await _test_embedded_panels()
	await _test_root()
	if _failures == 0:
		print("PASS: clipboard raises and stows, turns sheets with keyboard and gamepad, respects busy hands")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _test_actions() -> void:
	CompanyClipboard.ensure_actions()
	CompanyClipboard.ensure_actions()
	var actions: Array[StringName] = [
		CompanyClipboard.ACTION_TOGGLE, CompanyClipboard.ACTION_PREV, CompanyClipboard.ACTION_NEXT,
	]
	for action: StringName in actions:
		var keys: int = 0
		var pads: int = 0
		for event: InputEvent in InputMap.action_get_events(action):
			keys += 1 if event is InputEventKey else 0
			pads += 1 if event is InputEventJoypadButton else 0
		_expect(keys == 1 and pads == 1, "%s has one key and one pad button (got %d, %d)" % [action, keys, pads])
	var stow: Array[InputEvent] = InputMap.action_get_events(CompanyClipboard.ACTION_STOW)
	_expect(stow.size() == 1 and stow[0] is InputEventJoypadButton, "the stow action is B alone")
	_expect(ClipboardFrame.action_label(CompanyClipboard.ACTION_STOW, true) == "B", "...and the foot names it")
	_expect(ClipboardFrame.action_label(CompanyClipboard.ACTION_NEXT, true) == "RB", "the foot names RB")
	_expect(ClipboardFrame.action_label(CompanyClipboard.ACTION_PREV, true) == "LB", "...and LB")
	_expect(ClipboardFrame.action_label(CompanyClipboard.ACTION_TOGGLE, false) == "I",
		"...and the I key (got %s)" % ClipboardFrame.action_label(CompanyClipboard.ACTION_TOGGLE, false))


func _test_embedded_panels() -> void:
	var stock := StockPanel.new()
	stock.embedded = true
	root.add_child(stock)
	var inv := Inventory.new()
	inv.receive(&"hen", 2, &"shelf:a")
	stock.open({"inventory": inv})
	await process_frame
	_expect(stock.close_button() == null and stock.find_children("*", "ColorRect", true, false).is_empty(),
		"an embedded stock list has no Close and no backdrop")
	_expect(stock.row_count() == 1, "...and lists the stock")
	root.push_input(_key(KEY_ESCAPE))
	_expect(stock.visible, "...and Esc does not close it")
	stock.free()
	var supplier := SupplierOrderPanel.new()
	root.add_child(supplier)
	var cart := SupplierOrderCart.new()
	cart.products = {&"hen": _product(&"hen")}
	_expect(cart.add(&"hen", 3), "the cart takes 3 hens")
	supplier.open({"cart": cart, "wallet": null, "schedule": SupplierSchedule.new(), "day": 1})
	_expect(supplier.close_button() != null, "a standalone supplier screen has Close")
	supplier.set_embedded(true)
	await process_frame
	_expect(supplier.close_button() == null and supplier.qty_of(&"hen") == 3 and supplier.more_button(&"hen") != null,
		"embedding it rebuilds it without Close and keeps the cart")
	root.push_input(_key(KEY_ESCAPE))
	_expect(supplier.visible, "...and Esc does not close it")
	supplier.free()


func _product(id: StringName) -> ProductDefinition:
	var def := ProductDefinition.new()
	def.id = id
	def.buy_price = 10
	return def


func _test_root() -> void:
	_clean()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	await process_frame
	await physics_frame
	var clip: CompanyClipboard = level.get_node_or_null(^"Clipboard") as CompanyClipboard
	_expect(clip != null and level.player != null, "the root has its clipboard and its player")
	if clip == null or level.player == null:
		level.free()
		return
	_expect(clip.frame.sheet_ids() == [CompanyClipboard.SHEET_STOCK, CompanyClipboard.SHEET_SUPPLIER],
		"two sheets, Stock then Supplier (Employees waits for milestone 8) (got %s)" % [clip.frame.sheet_ids()])
	await _test_keyboard(level, clip)
	await _test_gamepad(level, clip)
	await _test_busy(level, clip)
	await _test_shortcuts(level, clip)
	level.free()
	state.call(&"reset")
	_clean()


func _test_keyboard(level: CompanyRoot, clip: CompanyClipboard) -> void:
	var held: Node = level.player.get_node(^"PlayerHeldTool")
	root.push_input(_key(KEY_I))
	await process_frame
	_expect(clip.is_up() and clip.frame.visible and clip.current_sheet() == CompanyClipboard.SHEET_STOCK,
		"I raises it on the Stock sheet")
	_expect(not level.player.is_processing_unhandled_input(), "...the player's input is off")
	_expect(held.get(&"held_tool") == &"clipboard_up", "...the others see it raised (held_tool)")
	var board: Node = held.call(&"board")
	_expect(board == null or board.is_inside_tree(), "...its board hangs from the hand once the rig is up")
	var copy: Node = (load("res://scripts/gameplay/player/player_held_tool.gd") as GDScript).new()
	copy.set_multiplayer_authority(4242)
	root.add_child(copy)
	copy.call(&"set_held", &"clipboard_up")
	_expect(copy.get(&"held_tool") == &"", "a copy of another peer's player is not written here")
	copy.free()
	_expect(level.stock_board.is_open() and not level.supplier_board.is_open(), "...only the Stock sheet draws")
	root.push_input(_key(KEY_E))
	_expect(clip.current_sheet() == CompanyClipboard.SHEET_SUPPLIER and level.supplier_board.is_open()
		and not level.stock_board.is_open(), "E turns to the Supplier sheet")
	root.push_input(_key(KEY_E))
	_expect(clip.current_sheet() == CompanyClipboard.SHEET_STOCK, "...and E again wraps to Stock")
	root.push_input(_key(KEY_Q))
	_expect(clip.current_sheet() == CompanyClipboard.SHEET_SUPPLIER, "Q turns back (wrapping)")
	clip.frame.tab_button(CompanyClipboard.SHEET_STOCK).pressed.emit()
	_expect(clip.current_sheet() == CompanyClipboard.SHEET_STOCK, "a click on a tab changes sheet")
	var pause: CompanySoloPause = _pause(level)
	root.push_input(_key(KEY_ESCAPE))
	await process_frame
	_expect(not clip.is_up() and not clip.frame.visible and not level.stock_board.is_open(), "Esc stows it")
	_expect(pause != null and not pause.is_paused() and not _menu_open(pause), "...without opening the pause")
	_expect(level.player.is_processing_unhandled_input() and held.get(&"held_tool") == &"",
		"...the player's input is back and the hand is empty")
	root.push_input(_key(KEY_ESCAPE))
	_expect(pause.is_paused() or _menu_open(pause), "the next Esc opens the pause")
	root.push_input(_key(KEY_I))
	_expect(not clip.is_up(), "...and the clipboard does not come out over it")
	root.push_input(_key(KEY_ESCAPE))
	await process_frame
	_expect(not pause.is_paused() and not _menu_open(pause), "Esc closes the pause")
	root.push_input(_key(KEY_I))
	await process_frame
	_expect(clip.is_up(), "I raises it again")
	root.push_input(_key(KEY_I))
	_expect(not clip.is_up(), "...and I stows it")


func _test_gamepad(level: CompanyRoot, clip: CompanyClipboard) -> void:
	root.push_input(_pad(JOY_BUTTON_DPAD_RIGHT))
	await process_frame
	_expect(clip.is_up(), "the d-pad right raises it")
	root.push_input(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	await process_frame
	await process_frame
	var panel: SupplierOrderPanel = level.supplier_board.panel
	var ids: Array = panel.call(&"_product_ids", level.supplier_board.cart)
	_expect(clip.current_sheet() == CompanyClipboard.SHEET_SUPPLIER and ids.size() >= 2,
		"RB turns to the Supplier sheet, with products (got %d)" % ids.size())
	if ids.size() < 2:
		clip.stow()
		return
	var plus: Button = panel.more_button(ids[0])
	_expect(_focus() == plus, "the first plus takes the focus")
	root.push_input(_pad(JOY_BUTTON_DPAD_RIGHT))
	await process_frame
	_expect(clip.is_up() and _focus() == plus, "d-pad right on the plus keeps the focus there and the clipboard up")
	root.push_input(_pad(JOY_BUTTON_DPAD_LEFT))
	await process_frame
	_expect(_focus() == panel.less_button(ids[0]), "d-pad left goes to the minus")
	root.push_input(_pad(JOY_BUTTON_DPAD_DOWN))
	await process_frame
	_expect(_focus() == panel.less_button(ids[1]), "d-pad down goes to the next row")
	root.push_input(_pad(JOY_BUTTON_LEFT_SHOULDER))
	_expect(clip.current_sheet() == CompanyClipboard.SHEET_STOCK, "LB turns back to Stock")
	root.push_input(_pad(JOY_BUTTON_B))
	await process_frame
	_expect(not clip.is_up(), "B stows it")
	_expect(not _pause(level).is_paused() and not _menu_open(_pause(level)), "...without the pause")


func _test_busy(level: CompanyRoot, clip: CompanyClipboard) -> void:
	var player: Node3D = level.player
	var hands: StringName = CompanyNet.hands_location(level.multiplayer.get_unique_id())
	level.net.inventory.receive(&"hen", 1, hands)
	_expect(not clip.raise(), "units in the hands keep it in")
	level.net.inventory.discard(&"hen", 1, hands)
	player.set(&"seat_node_path", NodePath("Seat"))
	_expect(not clip.raise(), "a seat keeps it in")
	player.set(&"seat_node_path", NodePath())
	var phone: Node = player.get_node(^"PlayerPhoneProp")
	phone.set(&"phone_raised", true)
	_expect(not clip.raise(), "the phone up keeps it in")
	phone.set(&"phone_raised", false)
	_expect(clip.raise(), "free hands raise it")
	_expect(level.builder.busy.is_valid() and bool(level.builder.busy.call()), "raised, the build mode may not start")
	level.net.inventory.receive(&"hen", 1, hands)
	await process_frame
	_expect(not clip.is_up(), "units coming into the hands put it away")
	level.net.inventory.discard(&"hen", 1, hands)
	_expect(not bool(level.builder.busy.call()), "...and the build mode may start again")


func _test_shortcuts(level: CompanyRoot, clip: CompanyClipboard) -> void:
	_expect(level.supplier_board.open() and clip.is_up() and clip.current_sheet() == CompanyClipboard.SHEET_SUPPLIER,
		"the shed's supplier board raises it on the Supplier sheet")
	level.supplier_board.close()
	_expect(not clip.is_up(), "the board's close() stows it")
	_expect(clip.raise() and clip.current_sheet() == CompanyClipboard.SHEET_SUPPLIER, "it remembers the last sheet")
	var bus: Node = root.get_node(^"/root/EventBus")
	bus.emit_signal(&"company_day_summary", 1, {})
	_expect(not clip.is_up(), "the day's summary stows it")
	await process_frame
	_expect(clip.raise(), "it comes out again")
	var pause: CompanySoloPause = _pause(level)
	bus.emit_signal(&"pause_requested")
	_expect(not clip.is_up(), "the pause asked for stows it")
	if _menu_open(pause):
		pause.call(&"close_menu")
	elif pause.is_paused():
		pause.resume()
	await process_frame


func _pause(level: CompanyRoot) -> CompanySoloPause:
	for child: Node in level.get_children():
		if child is CompanySoloPause:
			return child
	return null


func _menu_open(pause: CompanySoloPause) -> bool:
	return pause != null and pause.has_method(&"menu_open") and bool(pause.call(&"menu_open"))


func _focus() -> Control:
	return root.gui_get_focus_owner()


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))

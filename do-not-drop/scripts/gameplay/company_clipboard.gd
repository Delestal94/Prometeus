class_name CompanyClipboard
extends Node
## The management clipboard of the company's world (expansion D-1902, diseno/portapapeles.md §1-4 and §6):
## an object in the hand, not a menu. F1 has two positions, stowed and raised, toggled with one key.
##
## Raised, ClipboardFrame covers the bottom two thirds of the screen with the shed behind it; the mouse is
## free and the local player's input is off, as the panels of before. Its sheets, at most three and in this
## order, are panels that already exist in their embedded mode: Stock (StockBoard's StockPanel, read only) and
## Supplier (SupplierBoard's SupplierOrderPanel, ± and Order, which asks the host as always). Employees comes
## with milestone 8 (D-1038): until then it has no tab. The sheet last shown is remembered while the world
## lasts (nothing goes to the save or the snapshot).
##
## Controls (§4): `company_clipboard` (I, gamepad d-pad right: only to raise it) raises and stows it;
## `company_clipboard_prev` / `_next` (Q / E, LB / RB) or a click on a tab change sheet; Esc (`ui_cancel`,
## `ui_pause`) or B (`company_clipboard_stow`: this project's ui_cancel has no gamepad button) stows it.
## Raised, it takes those in _input before anything else: LB / RB are also
## phone_toggle, phone_shutter and the gears, Esc is the pause (it stows and does not open it). The d-pad right
## raised is left to the sheet's focus (the right edge of a ± row stays on its plus): with the gamepad one
## leaves with B.
##
## It does not come out with the hands busy: a box carried or tended, units in this peer's hands in
## CompanyNet's inventory, a picking cart gripped (the host knows grips: PickingCartGrip), a seat (driving or
## riding), the phone up, knocked over, or the build mode on. It is stowed on its own when any of those starts,
## when the day reaches SUMMARY, and when the pause is asked for (EventBus.pause_requested) or open. The build
## mode does not start while it is raised (ShedBuilder.busy) and it does not come out while that is on. The
## shed's supplier board is a shortcut: using it raises the clipboard on the Supplier sheet
## (SupplierBoard.open_in). A board's close() (its panel's `closed`) stows it too.
##
## Network (§6): reading is local, as StockBoard always was; deciding goes to the host through the request the
## sheet already had. What the others see is `PlayerHeldTool.held_tool` on this peer's player, written here
## (the owner) and replicated by player.tscn. Autoloads are reached by path (lesson N-919).

const ACTION_TOGGLE: StringName = &"company_clipboard"
const ACTION_PREV: StringName = &"company_clipboard_prev"
const ACTION_NEXT: StringName = &"company_clipboard_next"
## Gamepad only (B): Esc already is ui_cancel / ui_pause.
const ACTION_STOW: StringName = &"company_clipboard_stow"
const SHEET_STOCK: StringName = &"stock"
const SHEET_SUPPLIER: StringName = &"supplier"
const SHEET_EMPLOYEES: StringName = &"employees"
const HELD_TOOL_NODE: NodePath = ^"PlayerHeldTool"
const HELD_UP: StringName = &"clipboard_up"
const HELD_NONE: StringName = &""

var frame: ClipboardFrame
var stock_board: StockBoard
var supplier_board: SupplierBoard
var net: CompanyNet
## Returns this peer's own player (or null).
var player_of: Callable = Callable()
## Returns true while the build mode is on.
var building: Callable = Callable()
## Returns the PickingCartGrip of the world (or null): the host's knowledge of who grips a cart.
var grip_of: Callable = Callable()
## Returns true while the pause (or its menu) is open.
var pause_open: Callable = Callable()
## Returns true while the day is in its SUMMARY (the closing screen owns the screen).
var summary_open: Callable = Callable()
## This peer's id; unset, the multiplayer's (a test drives it).
var peer_id: Callable = Callable()

var _up: bool = false
var _sheet: StringName = SHEET_STOCK
var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player_off: Node = null
var _held_by: Node = null


## Registers the clipboard's actions (once each): keyboard and gamepad.
static func ensure_actions() -> void:
	_ensure(ACTION_TOGGLE, KEY_I, JOY_BUTTON_DPAD_RIGHT)
	_ensure(ACTION_PREV, KEY_Q, JOY_BUTTON_LEFT_SHOULDER)
	_ensure(ACTION_NEXT, KEY_E, JOY_BUTTON_RIGHT_SHOULDER)
	_ensure(ACTION_STOW, KEY_NONE, JOY_BUTTON_B)


static func _ensure(action: StringName, key_code: Key, button: JoyButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.5)
	if key_code != KEY_NONE:
		var key := InputEventKey.new()
		key.physical_keycode = key_code
		InputMap.action_add_event(action, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = button
	pad.device = -1
	InputMap.action_add_event(action, pad)


## The company world's clipboard: adds `stock` (StockBoard.for_company(), not in the tree yet) and the
## clipboard under `root` (CompanyRoot), with the world's supplier board, player, build mode, cart grip and
## pause read from the root when used. The build mode is kept from starting while it is raised.
static func attach(root: Node, stock: StockBoard) -> CompanyClipboard:
	stock.sheet_mode = true
	root.add_child(stock)
	var clip := CompanyClipboard.new()
	clip.name = "Clipboard"
	clip.stock_board = stock
	clip.supplier_board = root.get(&"supplier_board") as SupplierBoard
	clip.net = root.get(&"net") as CompanyNet
	clip.player_of = func() -> Node:
		return root.get(&"player") as Node if is_instance_valid(root) else null
	clip.building = func() -> bool:
		var builder: ShedBuilder = root.get(&"builder") as ShedBuilder if is_instance_valid(root) else null
		return builder != null and is_instance_valid(builder) and builder.is_building()
	clip.grip_of = func() -> Node:
		return _child_of(root, &"PickingCartGrip")
	clip.pause_open = func() -> bool:
		var pause: Node = _child_of(root, &"CompanySoloPause")
		if pause == null:
			return false
		return bool(pause.call(&"is_paused")) or (pause.has_method(&"menu_open") and bool(pause.call(&"menu_open")))
	clip.summary_open = func() -> bool:
		var cycle: DayCycle = root.get(&"day_cycle") as DayCycle if is_instance_valid(root) else null
		return cycle != null and is_instance_valid(cycle) and cycle.phase() == DayCycle.Phase.SUMMARY
	root.add_child(clip)
	var builder: ShedBuilder = root.get(&"builder") as ShedBuilder
	if builder != null:
		var before: Callable = builder.busy
		builder.busy = func() -> bool:
			return (is_instance_valid(clip) and clip.is_up()) or (before.is_valid() and bool(before.call()))
	return clip


## The first child of `root` whose script is the class `class_id` (null when none or the root is gone).
static func _child_of(root: Node, class_id: StringName) -> Node:
	if not is_instance_valid(root):
		return null
	for child: Node in root.get_children():
		var script: Script = child.get_script() as Script
		if script != null and script.get_global_name() == class_id:
			return child
	return null


func _ready() -> void:
	ensure_actions()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	var layer := CanvasLayer.new()
	layer.name = "ClipboardLayer"
	add_child(layer)
	frame = ClipboardFrame.new()
	frame.name = "ClipboardFrame"
	layer.add_child(frame)
	frame.sheet_picked.connect(show_sheet)
	if stock_board != null and stock_board.panel != null:
		stock_board.panel.set_embedded(true)
		frame.add_sheet(SHEET_STOCK, tr("UI_CLIPBOARD_SHEET_STOCK"), stock_board.panel)
		stock_board.panel.closed.connect(stow)
		stock_board.open_in = func() -> bool: return raise(SHEET_STOCK)
	if supplier_board != null and supplier_board.panel != null:
		supplier_board.panel.set_embedded(true)
		frame.add_sheet(SHEET_SUPPLIER, tr("UI_CLIPBOARD_SHEET_SUPPLIER"), supplier_board.panel)
		supplier_board.open_in = func() -> bool: return raise(SHEET_SUPPLIER)
		supplier_board.panel.closed.connect(stow)
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"pause_requested", stow)
		bus.connect(&"company_day_summary", _on_day_summary)


## Leaving the world is always for a menu: the cursor stays free (as CompanySoloPause leaves it).
func _exit_tree() -> void:
	if _up:
		stow()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		if bus.is_connected(&"pause_requested", stow):
			bus.disconnect(&"pause_requested", stow)
		if bus.is_connected(&"company_day_summary", _on_day_summary):
			bus.disconnect(&"company_day_summary", _on_day_summary)


func is_up() -> bool:
	return _up


## The sheet showing (or that shows next time it is raised).
func current_sheet() -> StringName:
	return _sheet


## Raises the clipboard on `sheet` (the last one when ""), or turns to it when already raised. False when the
## hands are busy, the build mode is on, the pause is open or the sheet does not exist.
func raise(sheet: StringName = &"") -> bool:
	var wanted: StringName = sheet if sheet != &"" else _sheet
	if not frame.has_sheet(wanted):
		wanted = frame.neighbour(0)
		if wanted == &"" or sheet != &"":
			return false
	if _up:
		show_sheet(wanted)
		return true
	if hands_busy() or _is_paused() or _screen_taken():
		return false
	_up = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player: Node = _player()
	if player != null:
		player.set_process_unhandled_input(false)
		_player_off = player
	_set_held(player, HELD_UP)
	frame.show()
	show_sheet(wanted)
	_update_hint()
	set_process(true)
	return true


## Puts it away: the sheet stops drawing, the mouse and the player's input come back (the mouse stays free
## when a pause opened over it). Nothing when it is not raised.
func stow() -> void:
	if not _up:
		return
	_up = false
	set_process(false)
	_hide_sheets()
	frame.hide()
	if not _is_paused():
		Input.mouse_mode = _mouse_before
	if _player_off != null and is_instance_valid(_player_off):
		_player_off.set_process_unhandled_input(true)
	_player_off = null
	_set_held(_held_by, HELD_NONE)
	_held_by = null


## Shows `sheet` (raised): its board draws it (its panel takes the focus), the others stop.
func show_sheet(sheet: StringName) -> void:
	if not frame.mark(sheet):
		return
	_sheet = sheet
	if not _up:
		return
	_hide_sheets()
	_update_hint()
	match sheet:
		SHEET_STOCK:
			stock_board.show_sheet()
		SHEET_SUPPLIER:
			supplier_board.show_sheet()


## Turns `step` sheets over (+1 next, -1 previous), wrapping around.
func turn(step: int) -> void:
	if _up:
		show_sheet(frame.neighbour(step))


## True when something holds the hands (see the class doc), so it may not come out.
func hands_busy() -> bool:
	var player: Node = _player()
	if player == null:
		return true
	if is_instance_valid(player.get(&"carried_package")) or is_instance_valid(player.get(&"tended_package")):
		return true
	var seat: NodePath = player.get(&"seat_node_path")
	if not seat.is_empty() or bool(player.get(&"_ragdolled")):
		return true
	var phone: Node = player.get_node_or_null(^"PlayerPhoneProp")
	if phone != null and bool(phone.get(&"phone_raised")):
		return true
	if building.is_valid() and bool(building.call()):
		return true
	var me: int = _peer()
	var hands: StringName = CompanyNet.hands_location(me)
	if net != null and net.inventory != null and not net.inventory.contents_at(hands).is_empty():
		return true
	var grip: Node = grip_of.call() as Node if grip_of.is_valid() else null
	return grip != null and bool(grip.call(&"is_gripping", me))


## Raised: whatever takes the hands (or the pause) puts it away.
func _process(_delta: float) -> void:
	if _up and (hands_busy() or _is_paused()):
		stow()


func _input(event: InputEvent) -> void:
	if not _up:
		return
	var key_toggle: bool = event is InputEventKey and event.is_action_pressed(ACTION_TOGGLE)
	var back: bool = event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"ui_pause")
	if key_toggle or back or event.is_action_pressed(ACTION_STOW):
		stow()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ACTION_PREV):
		turn(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ACTION_NEXT):
		turn(1)
		get_viewport().set_input_as_handled()
	elif event.is_action(ACTION_PREV) or event.is_action(ACTION_NEXT):
		# Their release too: LB / RB are also the phone and the gears.
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _up and event.is_action_pressed(ACTION_TOGGLE) and raise():
		get_viewport().set_input_as_handled()


func _on_day_summary(_day: int, _summary: Dictionary) -> void:
	stow()


func _hide_sheets() -> void:
	if stock_board != null:
		stock_board.hide_sheet()
	if supplier_board != null:
		supplier_board.hide_sheet()


func _update_hint() -> void:
	frame.set_hint(
		["UI_CLIPBOARD_HINT_KEY", [ACTION_PREV, ACTION_NEXT, ACTION_TOGGLE]],
		["UI_CLIPBOARD_HINT_PAD", [ACTION_PREV, ACTION_NEXT, ACTION_STOW]])


func _set_held(player: Node, what: StringName) -> void:
	if player == null or not is_instance_valid(player):
		return
	var held: Node = player.get_node_or_null(HELD_TOOL_NODE)
	if held != null:
		held.call(&"set_held", what)
		_held_by = player if what != HELD_NONE else null


func _player() -> Node:
	var player: Node = player_of.call() as Node if player_of.is_valid() else null
	return player if player != null and is_instance_valid(player) and not player.is_queued_for_deletion() else null


func _peer() -> int:
	if peer_id.is_valid():
		return int(peer_id.call())
	return multiplayer.get_unique_id() if is_inside_tree() and multiplayer != null else 1


## Another screen owns it: the day's summary, or a panel that switched the player's input off (dispatch, shop).
func _screen_taken() -> bool:
	if summary_open.is_valid() and bool(summary_open.call()):
		return true
	var player: Node = _player()
	return player != null and not player.is_processing_unhandled_input()


func _is_paused() -> bool:
	return pause_open.is_valid() and bool(pause_open.call())

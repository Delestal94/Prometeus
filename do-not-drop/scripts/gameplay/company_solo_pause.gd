class_name CompanySoloPause
extends Node
## A real pause for whoever plays the company alone (expansion D-0151.1, roles-tripulacion.md
## section 6.2 row 1).
##
## With the host and nobody else connected (no network, or an open room still empty) the pause
## stops the whole tree and the day's GameClock: the clock is an anchor on the system clock, so a
## paused tree alone would not stop it. Resuming runs the clock again only if this pause stopped
## it (the day summary pauses it too, DayCycle, and stays so). With anyone else in the session
## toggle() does nothing: the coop pause of today (the HUD's soft pause, the world goes on) is the
## HUD's. A peer that enters while paused un-pauses it first: NetworkManager.roster_changed comes
## before peer_level_ready, which is what makes CompanyNet send the snapshot, so the joiner's
## snapshot carries a running clock. No RPC: the clock pause is the clock_anchor event the host
## already sends.
##
## Entry points: Esc (ui_pause) and EventBus.pause_requested, which the HUD emits (HudPause) once
## the company has one. A panel that is open takes Esc first (it handles it).
##
## What shows is the company's pause menu (CompanyPauseMenu, D-1909): Esc opens it as a real pause
## when alone (toggle) or as a soft one when not (open_menu: the world goes on, the mouse is free
## so the player takes no input), and closes it again; inside it Esc goes back from a confirmation
## first. A client opens the soft one too: its "Close the day" is off, the host closes the day.

## The day's clock and phases (CompanyRoot's children). day_cycle may be null.
var clock: GameClock = null
var day_cycle: DayCycle = null
## Other peers connected to this host, as Callable() -> int; unset, NetworkManager's roster
## without the host itself. A test drives it to simulate a joiner.
var peers_other: Callable = Callable()

var _paused: bool = false
## True when this pause stopped the clock (it was running), so only then it runs it again.
var _paused_clock: bool = false
var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _menu: CompanyPauseMenu = null
## World nodes whose keys the open menu switched off (_hold_world_keys).
var _held: Array[Node] = []


## The pause of this world's `clock` and `day_cycle`, ready to add as a child.
static func create(day_clock: GameClock, cycle: DayCycle) -> CompanySoloPause:
	var pause := CompanySoloPause.new()
	pause.name = "SoloPause"
	pause.clock = day_clock
	pause.day_cycle = cycle
	return pause


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"pause_requested", toggle)
		# The day's summary takes the screen: an open menu would sit over it and swallow its Esc / A.
		bus.connect(&"company_day_summary", _on_day_summary)
	var net: Node = get_node_or_null(^"/root/NetworkManager")
	if net != null and not peers_other.is_valid():
		net.connect(&"roster_changed", _on_roster_changed)


## The world stops being paused when it is left (the next scene starts running), and the pause
## unhooks from the roster. (It names no autoload: they are reached by path, lesson N-919.) Leaving is
## always for a menu: the cursor stays free, whatever the world had before the pause.
func _exit_tree() -> void:
	var was_open: bool = _paused or menu_open()
	if _paused:
		resume()
	elif menu_open():
		close_menu()
	if was_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null and bus.is_connected(&"pause_requested", toggle):
		bus.disconnect(&"pause_requested", toggle)
	if bus != null and bus.is_connected(&"company_day_summary", _on_day_summary):
		bus.disconnect(&"company_day_summary", _on_day_summary)
	var net: Node = get_node_or_null(^"/root/NetworkManager")
	if net != null and net.is_connected(&"roster_changed", _on_roster_changed):
		net.disconnect(&"roster_changed", _on_roster_changed)


func _unhandled_input(event: InputEvent) -> void:
	var open: bool = menu_open()
	if not event.is_action_pressed(&"ui_pause") and not (open and event.is_action_pressed(&"ui_cancel")):
		return
	if open and _menu.options_open():
		return
	if open:
		_menu.back()
	else:
		open_menu()
	get_viewport().set_input_as_handled()


## Esc in the world: a real pause when alone, else the menu over a world that goes on.
func open_menu() -> void:
	if menu_open():
		return
	if can_pause():
		toggle()
		return
	_save_mouse()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_menu(true)


## Continue / Esc: resumes a real pause, or just closes the soft menu.
func close_menu() -> void:
	if _paused:
		resume()
	elif menu_open():
		_show_menu(false)
		Input.mouse_mode = _mouse_before


## Esc only reaches the pause from the world (an open panel takes it first), where the mouse is
## captured; a free one there is the ping wheel's, which captures it again on release.
func _save_mouse() -> void:
	var mode: Input.MouseMode = Input.mouse_mode
	_mouse_before = Input.MOUSE_MODE_CAPTURED if mode == Input.MOUSE_MODE_VISIBLE else mode


## The day reached its summary under an open menu (soft: a crew's 20:00): the menu goes so the summary
## gets the screen, its focus and its keys.
func _on_day_summary(_day: int, _summary: Dictionary) -> void:
	if menu_open():
		close_menu()


func menu_open() -> bool:
	return _menu != null and _menu.is_open()


## The menu (built on first use), for the tests.
func menu() -> CompanyPauseMenu:
	_ensure_menu()
	return _menu


## True where the pause is real: this peer decides the clock (host or offline) and nobody else is
## connected.
func can_pause() -> bool:
	return clock != null and is_instance_valid(clock) and clock.is_host() and _others() == 0


func is_paused() -> bool:
	return _paused


## Pauses when running and alone, resumes when paused. True when the world is paused afterwards;
## with other peers (or a client) nothing happens and it stays false.
func toggle() -> bool:
	if _paused:
		resume()
		return false
	if not can_pause():
		return false
	_paused = true
	_paused_clock = clock.pause()
	get_tree().paused = true
	# A soft menu already open (a peer just left) keeps the mouse it saved.
	if not menu_open():
		_save_mouse()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_menu(true)
	return true


## Runs the world again. The clock runs only if this pause stopped it and the day is not in its
## summary. No-op when not paused.
func resume() -> void:
	if not _paused:
		return
	_paused = false
	get_tree().paused = false
	var summary: bool = false
	if day_cycle != null and is_instance_valid(day_cycle):
		summary = day_cycle.phase() == DayCycle.Phase.SUMMARY
	if _paused_clock and not summary and clock != null and is_instance_valid(clock):
		clock.resume()
	_paused_clock = false
	Input.mouse_mode = _mouse_before
	_show_menu(false)


## Host: someone joined (roster_changed comes before the snapshot goes out): the pause ends here
## and then, whoever it was.
func _on_roster_changed(_peer_ids: Array) -> void:
	if _paused and _others() > 0:
		resume()


func _others() -> int:
	if peers_other.is_valid():
		return int(peers_other.call())
	var net: Node = get_node_or_null(^"/root/NetworkManager")
	return maxi((net.get(&"peer_ids") as Array).size() - 1, 0) if net != null else 0


func _show_menu(shown: bool) -> void:
	if _menu == null and not shown:
		return
	_ensure_menu()
	_menu.day_cycle = day_cycle
	if shown:
		_menu.open(_paused)
	else:
		_menu.close()
	_hold_world_keys(shown)


## The world's own keys (the stock list's I, the build mode's B and its actions) run always and sit
## later in the tree than this pause: while the menu is up they are switched off, so nothing opens
## under it, no piece is sold in a pause and B backs out of the menu. Only the ones it switched off
## come back on.
func _hold_world_keys(hold: bool) -> void:
	if hold:
		var parent: Node = get_parent()
		if parent == null:
			return
		for node: Node in parent.get_children():
			if (node is ShedBuilder or node is StockBoard) and node.is_processing_unhandled_input():
				node.set_process_unhandled_input(false)
				_held.append(node)
		return
	for node: Node in _held:
		if is_instance_valid(node):
			node.set_process_unhandled_input(true)
	_held.clear()


func _ensure_menu() -> void:
	if _menu != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "PauseLayer"
	layer.layer = 90
	add_child(layer)
	_menu = CompanyPauseMenu.new()
	_menu.name = "PauseMenu"
	_menu.day_cycle = day_cycle
	layer.add_child(_menu)
	_menu.resume_requested.connect(close_menu)
	# The day goes to CLOSING: the trips have to come back, so the world runs again.
	_menu.day_closed.connect(func(_ok: bool) -> void: close_menu())

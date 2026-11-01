extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_pause_menu.gd
##
## The company's pause menu (expansion D-1909 with D-0253.a, scripts/ui/company_pause_menu.gd, opened
## by scripts/gameplay/company_solo_pause.gd), on a day whose phase and host the test sets:
## - Alone, Esc is a real pause with the menu up ("PAUSED", Continue focused); Esc again resumes.
## - Host in OPERATING: "Close the day" is on; it asks its confirmation first (focus on Back), Esc
##   goes back from it to the menu, and confirming closes the day (CLOSING) and runs the world again.
## - While leaving loses the day the warning is over the exits, and Back to menu / Quit ask before
##   leaving ("Leave anyway"); in SUMMARY they leave at once, with no warning.
## - A day that reaches CLOSING under an open menu turns the button off and drops its confirmation.
## - With another peer the menu is soft (the world goes on, "MENU"); a client sees the button off with
##   "The host closes the day" under it and no warning.
## - EventBus.pause_requested still toggles the real pause and shows the menu.
## - The day's summary closes a soft menu (it would sit over the summary and take its Esc / A).
## - Under the menu the stock list's and build mode's keys are off, and only those it switched off
##   come back; leaving the world from the pause leaves the cursor free for the main menu.

const START_TICK: int = 1_000_000

var _failures: int = 0
var _tick: int = START_TICK
var _others: int = 0
var _exits: Array[StringName] = []


## A day whose phase and host the test sets; close_early() works as the real one's gate does.
class FakeCycle:
	extends DayCycle

	var fake_phase: Phase = Phase.OPERATING
	var fake_host: bool = true

	func phase() -> Phase:
		return fake_phase

	func is_host() -> bool:
		return fake_host

	func close_early() -> bool:
		if not fake_host or fake_phase != Phase.OPERATING:
			return false
		fake_phase = Phase.CLOSING
		return true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_solo_close_day()
	await _test_exits()
	_test_phase_changes_under_menu()
	_test_soft_and_client()
	_test_pause_requested()
	_test_summary_closes_soft_menu()
	_test_world_keys_held()
	_test_leaving_frees_the_mouse()
	paused = false
	if _failures == 0:
		print("PASS: the company pause menu pauses alone, closes the day after asking, warns before the exits"
			+ " and stays soft with a crew")
	quit(_failures)


func _test_solo_close_day() -> void:
	var rig: Dictionary = _rig(DayCycle.Phase.OPERATING, true)
	var pause: CompanySoloPause = rig.pause
	var cycle: FakeCycle = rig.cycle
	var menu: CompanyPauseMenu = pause.menu()
	_esc(pause)
	await process_frame
	_expect(paused and pause.is_paused() and menu.is_open() and menu.is_real(),
		"alone, Esc pauses the world with the menu up")
	_expect(menu.title_text() == tr("HUD_PAUSED"), "the real pause reads PAUSED (got %s)" % menu.title_text())
	_expect(menu.continue_button().has_focus(), "Continue has the focus")
	_expect(not menu.close_day_button().disabled and menu.close_day_hint().is_empty(),
		"host in OPERATING: Close the day is on, with no hint")
	_expect(menu.exit_warning_text() == tr(DayClose.EXIT_WARNING_KEY), "the exits carry the lose-the-day warning")
	menu.close_day_button().pressed.emit()
	await process_frame
	_expect(menu.asking() == &"close" and menu.confirm_text() == tr(DayClose.CONFIRM_KEY)
		and cycle.phase() == DayCycle.Phase.OPERATING,
		"Close the day asks first and closes nothing yet (asking %s)" % menu.asking())
	_expect(menu.confirm_no_button().has_focus(), "the confirmation focuses Back")
	_esc(pause)
	_expect(menu.is_open() and paused and menu.asking() == &"", "Esc in the confirmation goes back to the menu")
	menu.close_day_button().pressed.emit()
	menu.confirm_yes_button().pressed.emit()
	_expect(cycle.phase() == DayCycle.Phase.CLOSING, "confirming closes the day (got %s)" % cycle.phase())
	_expect(not paused and not pause.is_paused() and not menu.is_open() and not rig.clock.is_paused(),
		"...and the world runs again so the trips come back")
	cycle.fake_phase = DayCycle.Phase.OPERATING
	_esc(pause)
	_expect(paused and menu.is_open(), "Esc opens it again")
	_esc(pause)
	_expect(not paused and not menu.is_open(), "and Esc on the menu resumes")
	_free(rig)


func _test_exits() -> void:
	var rig: Dictionary = _rig(DayCycle.Phase.OPERATING, true)
	var pause: CompanySoloPause = rig.pause
	var cycle: FakeCycle = rig.cycle
	var menu: CompanyPauseMenu = pause.menu()
	menu.exit_action = func(kind: StringName) -> void: _exits.append(kind)
	_exits.clear()
	pause.open_menu()
	menu.menu_button().pressed.emit()
	_expect(_exits.is_empty() and menu.asking() == CompanyPauseMenu.EXIT_MENU
		and menu.confirm_text() == tr(DayClose.EXIT_WARNING_KEY)
		and menu.confirm_yes_button().text == tr(CompanyPauseMenu.EXIT_ANYWAY_KEY),
		"Back to menu with the day on asks first, with the warning")
	menu.confirm_yes_button().pressed.emit()
	_expect(_exits == [CompanyPauseMenu.EXIT_MENU], "Leave anyway takes the menu exit (got %s)" % [_exits])
	_exits.clear()
	menu.quit_button().pressed.emit()
	_expect(_exits.is_empty() and menu.asking() == CompanyPauseMenu.EXIT_QUIT, "Quit asks first too")
	menu.confirm_no_button().pressed.emit()
	_expect(_exits.is_empty() and menu.asking() == &"", "Back keeps the game")
	cycle.fake_phase = DayCycle.Phase.SUMMARY
	menu.refresh()
	_expect(menu.exit_warning_text().is_empty() and menu.close_day_button().disabled,
		"in SUMMARY nothing is lost: no warning, and the day can't be closed")
	menu.quit_button().pressed.emit()
	_expect(_exits == [CompanyPauseMenu.EXIT_QUIT] and menu.asking() == &"", "...and Quit leaves at once")
	await process_frame
	_free(rig)


func _test_phase_changes_under_menu() -> void:
	var rig: Dictionary = _rig(DayCycle.Phase.OPERATING, true)
	var pause: CompanySoloPause = rig.pause
	var cycle: FakeCycle = rig.cycle
	var menu: CompanyPauseMenu = pause.menu()
	pause.open_menu()
	menu.close_day_button().grab_focus()
	menu.close_day_button().pressed.emit()
	menu._ask(&"")
	menu.close_day_button().grab_focus()
	cycle.fake_phase = DayCycle.Phase.CLOSING
	menu.refresh()
	_expect(menu.continue_button().has_focus(), "the focus on the button that turns off moves to Continue")
	cycle.fake_phase = DayCycle.Phase.OPERATING
	menu.refresh()
	menu.close_day_button().pressed.emit()
	cycle.fake_phase = DayCycle.Phase.CLOSING
	menu.refresh()
	_expect(menu.close_day_button().disabled and menu.asking() == &"" and not menu.exit_warning_text().is_empty(),
		"20:00 under the menu: the button turns off, its confirmation drops, the warning stays")
	_free(rig)


func _test_soft_and_client() -> void:
	var rig: Dictionary = _rig(DayCycle.Phase.OPERATING, true)
	var pause: CompanySoloPause = rig.pause
	var menu: CompanyPauseMenu = pause.menu()
	_others = 1
	_esc(pause)
	_expect(menu.is_open() and not menu.is_real() and not paused and not rig.clock.is_paused(),
		"with a peer the menu is soft: the world and the clock go on")
	_expect(menu.title_text() == tr("HUD_MENU_TITLE"), "the soft menu reads MENU (got %s)" % menu.title_text())
	_expect(not menu.close_day_button().disabled, "the host still closes the day from the soft menu")
	_esc(pause)
	_expect(not menu.is_open() and not paused, "Esc closes the soft menu")
	var cycle: FakeCycle = rig.cycle
	cycle.fake_host = false
	pause.open_menu()
	_expect(menu.close_day_button().disabled and menu.close_day_hint() == tr(DayClose.HOST_ONLY_KEY),
		"a client: Close the day is off, \"%s\" under it" % menu.close_day_hint())
	_expect(menu.exit_warning_text().is_empty(), "a client loses nothing by leaving: no warning")
	var options: Node = menu.menu_button().get_parent().get_node(^"Options")
	_expect(menu.close_day_button().focus_mode == Control.FOCUS_NONE
		and menu.continue_button().focus_neighbor_bottom == menu.continue_button().get_path_to(options),
		"the gamepad skips the button that is off: Continue goes down to Options")
	menu.close_day_button().pressed.emit()
	_expect(menu.asking() == &"" and cycle.phase() == DayCycle.Phase.OPERATING, "pressing it does nothing")
	menu.continue_button().pressed.emit()
	_expect(not menu.is_open(), "Continue closes it")
	_others = 0
	_free(rig)


func _test_pause_requested() -> void:
	var rig: Dictionary = _rig(DayCycle.Phase.OPERATING, true)
	var pause: CompanySoloPause = rig.pause
	root.get_node(^"EventBus").emit_signal(&"pause_requested")
	_expect(paused and pause.menu_open() and pause.menu().is_real(), "pause_requested pauses with the menu up")
	root.get_node(^"EventBus").emit_signal(&"pause_requested")
	_expect(not paused and not pause.menu_open(), "a second one resumes and hides it")
	_free(rig)


func _test_summary_closes_soft_menu() -> void:
	var rig: Dictionary = _rig(DayCycle.Phase.OPERATING, true)
	var pause: CompanySoloPause = rig.pause
	_others = 1
	pause.open_menu()
	_expect(pause.menu_open() and not paused, "the host's soft menu is up with a crew")
	root.get_node(^"EventBus").emit_signal(&"company_day_summary", 1, {})
	_expect(not pause.menu_open(), "the day's summary closes it, so the summary gets the screen and its keys")
	_others = 0
	_free(rig)


func _test_world_keys_held() -> void:
	var world := Node.new()
	root.add_child(world)
	var board := StockBoard.new()
	var builder := ShedBuilder.new()
	world.add_child(board)
	world.add_child(builder)
	var clock := GameClock.new()
	clock.ticks = func() -> int: return _tick
	world.add_child(clock)
	clock.start()
	var cycle := FakeCycle.new()
	var pause := CompanySoloPause.create(clock, cycle)
	pause.peers_other = func() -> int: return _others
	world.add_child(pause)
	_expect(board.is_processing_unhandled_input() and builder.is_processing_unhandled_input(),
		"the stock list's and the build mode's keys run in the world")
	pause.open_menu()
	_expect(not board.is_processing_unhandled_input() and not builder.is_processing_unhandled_input(),
		"under the menu they are off: nothing opens under it, nothing is sold in a pause")
	pause.close_menu()
	_expect(board.is_processing_unhandled_input() and builder.is_processing_unhandled_input(),
		"closing the menu turns them back on")
	builder.set_process_unhandled_input(false)
	pause.open_menu()
	pause.close_menu()
	_expect(not builder.is_processing_unhandled_input(), "one the menu did not switch off stays off")
	paused = false
	world.free()
	cycle.free()


func _test_leaving_frees_the_mouse() -> void:
	var rig: Dictionary = _rig(DayCycle.Phase.OPERATING, true)
	var pause: CompanySoloPause = rig.pause
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var mouse_sticks: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_esc(pause)
	pause.get_parent().remove_child(pause)
	_expect(not paused, "leaving the world from the pause leaves the tree running")
	_expect(not mouse_sticks or Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"...and the cursor free for the menu, not the world's captured one")
	root.add_child(pause)
	_free(rig)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _esc(pause: CompanySoloPause) -> void:
	var event := InputEventAction.new()
	event.action = &"ui_pause"
	event.pressed = true
	pause._unhandled_input(event)


## A clock on the simulated tick, a fake day and the pause (alone unless _others says) in the tree.
func _rig(phase: DayCycle.Phase, host: bool) -> Dictionary:
	var clock := GameClock.new()
	clock.ticks = func() -> int: return _tick
	root.add_child(clock)
	clock.start()
	var cycle := FakeCycle.new()
	cycle.fake_phase = phase
	cycle.fake_host = host
	var pause := CompanySoloPause.create(clock, cycle)
	pause.peers_other = func() -> int: return _others
	root.add_child(pause)
	return {"clock": clock, "pause": pause, "cycle": cycle}


func _free(rig: Dictionary) -> void:
	paused = false
	(rig.pause as Node).free()
	(rig.clock as Node).free()
	(rig.cycle as Node).free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)
	print("FAIL: ", label)

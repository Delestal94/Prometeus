extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_solo_pause.gd
##
## The real pause of a company played alone (expansion D-0151.1, roles-tripulacion.md section 6.2
## row 1, scripts/gameplay/company_solo_pause.gd), with simulated time (the clock reads a tick the
## test moves):
## - Alone (no other peer) toggle() pauses the tree and the GameClock, and the game minute stays
##   still however many ticks pass; a second toggle runs both again from where they stopped.
## - A clock that was already stopped (the day summary stops it) is not run again on resume: only
##   a pause that stopped the clock runs it; and a day that reached SUMMARY while paused leaves it
##   stopped too.
## - With another peer connected toggle() does nothing (the coop pause is the HUD's soft pause); a
##   client (a clock that is not the host's) neither.
## - A peer that enters while paused un-pauses it (roster_changed, before the snapshot): the tree
##   and the clock run, and a pause nobody asked for is not undone by a joiner.
## - EventBus.pause_requested (the HUD's way in) toggles it; leaving the world while paused leaves
##   the tree running.

const START_TICK: int = 1_000_000

var _failures: int = 0
var _tick: int = START_TICK
var _others: int = 0


## A day that is in its summary, whatever the clock says.
class SummaryCycle:
	extends DayCycle

	func phase() -> Phase:
		return Phase.SUMMARY


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_alone()
	_test_clock_already_stopped()
	_test_summary_reached_while_paused()
	_test_not_alone()
	_test_peer_enters()
	_test_entry_points_and_exit()
	paused = false
	quit(_failures)


func _test_alone() -> void:
	var rig: Dictionary = _rig()
	var pause: CompanySoloPause = rig.pause
	var clock: GameClock = rig.clock
	_expect(not pause.is_paused() and not paused and not clock.is_paused(), "starts running")
	_expect(pause.can_pause(), "alone, the pause is real")
	_expect(pause.toggle() and pause.is_paused(), "toggle alone pauses (returns true)")
	_expect(paused, "the tree is paused")
	_expect(clock.is_paused(), "the clock is paused")
	var frozen: float = clock.minute_now()
	_tick += 120_000
	_expect(is_equal_approx(clock.minute_now(), frozen), "the minute stays still while paused (%f)" % frozen)
	_expect(not pause.toggle() and not pause.is_paused(), "second toggle resumes (returns false)")
	_expect(not paused and not clock.is_paused(), "tree and clock run again")
	_expect(is_equal_approx(clock.minute_now(), frozen), "from where they stopped")
	_tick += 60_000
	_expect(clock.minute_now() > frozen + 0.5, "and the minute moves again")
	_free(rig)


func _test_clock_already_stopped() -> void:
	var rig: Dictionary = _rig()
	var pause: CompanySoloPause = rig.pause
	var clock: GameClock = rig.clock
	clock.pause()
	var stopped_at: float = clock.minute_now()
	_expect(pause.toggle() and paused, "pauses with the clock already stopped")
	pause.toggle()
	_expect(not paused, "the tree runs again")
	_expect(clock.is_paused() and is_equal_approx(clock.minute_now(), stopped_at),
		"the clock the pause did not stop stays stopped")
	_free(rig)


func _test_summary_reached_while_paused() -> void:
	var rig: Dictionary = _rig()
	var pause: CompanySoloPause = rig.pause
	var clock: GameClock = rig.clock
	var cycle := SummaryCycle.new()
	pause.day_cycle = cycle
	_expect(pause.toggle() and clock.is_paused(), "paused, it stopped the running clock")
	pause.toggle()
	_expect(not paused and clock.is_paused(), "in SUMMARY the clock is not run on resume")
	cycle.free()
	_free(rig)


func _test_not_alone() -> void:
	var rig: Dictionary = _rig()
	var pause: CompanySoloPause = rig.pause
	var clock: GameClock = rig.clock
	_others = 1
	_expect(not pause.can_pause(), "with a peer the pause is not real")
	_expect(not pause.toggle() and not pause.is_paused(), "toggle with a peer returns false")
	_expect(not paused and not clock.is_paused(), "and stops neither the tree nor the clock")
	_others = 0
	# A client: a clock attached to a CompanyNet that is not up as the host decides nothing.
	var client_clock := GameClock.new()
	var net := CompanyNet.new()
	_expect(client_clock.attach(net, null) and not client_clock.is_host(), "a clock on a net that is not the host's")
	var client_pause := CompanySoloPause.create(client_clock, null)
	client_pause.peers_other = func() -> int: return 0
	_expect(not client_pause.can_pause() and not client_pause.toggle(), "a client has no real pause")
	client_pause.free()
	client_clock.free()
	net.free()
	_free(rig)


func _test_peer_enters() -> void:
	var rig: Dictionary = _rig()
	var pause: CompanySoloPause = rig.pause
	var clock: GameClock = rig.clock
	pause.toggle()
	_expect(paused and clock.is_paused(), "paused alone")
	# Someone joined: roster_changed (before peer_level_ready, hence before the snapshot).
	_others = 1
	pause._on_roster_changed([1, 2])
	_expect(not paused and not pause.is_paused(), "a peer entering un-pauses the tree")
	_expect(not clock.is_paused(), "and runs the clock, so the snapshot carries it running")
	# Not paused: a joiner changes nothing (and a stopped clock stays so).
	clock.pause()
	pause._on_roster_changed([1, 2, 3])
	_expect(clock.is_paused() and not paused, "a joiner does not run a clock nobody paused")
	_others = 0
	# A roster change with nobody else left leaves a pause alone.
	clock.resume()
	pause.toggle()
	pause._on_roster_changed([1])
	_expect(paused, "a roster with only the host does not end the pause")
	pause.toggle()
	_free(rig)


func _test_entry_points_and_exit() -> void:
	var rig: Dictionary = _rig()
	var pause: CompanySoloPause = rig.pause
	var clock: GameClock = rig.clock
	root.get_node(^"EventBus").emit_signal(&"pause_requested")
	_expect(paused and clock.is_paused() and pause.is_paused(), "pause_requested pauses")
	root.get_node(^"EventBus").emit_signal(&"pause_requested")
	_expect(not paused and not clock.is_paused(), "and a second one resumes")
	root.get_node(^"EventBus").emit_signal(&"pause_requested")
	_expect(paused, "paused again")
	pause.get_parent().remove_child(pause)
	_expect(not paused, "leaving the world while paused leaves the tree running")
	pause.free()
	root.get_node(^"EventBus").emit_signal(&"pause_requested")
	_expect(not paused, "a freed pause no longer answers pause_requested")
	rig.clock.free()


## A clock on the simulated tick and a pause (alone: no other peer) in the tree.
func _rig() -> Dictionary:
	_others = 0
	var clock := GameClock.new()
	clock.ticks = func() -> int: return _tick
	root.add_child(clock)
	clock.start()
	var pause := CompanySoloPause.create(clock, null)
	pause.peers_other = func() -> int: return _others
	root.add_child(pause)
	return {"clock": clock, "pause": pause}


func _free(rig: Dictionary) -> void:
	paused = false
	(rig.pause as Node).free()
	(rig.clock as Node).free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)
	print("FAIL: ", label)

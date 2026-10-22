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
## the company has one. A panel that is open takes Esc first (it handles it). Until the company
## HUD exists a plain "PAUSED" label stands in for its pause card.

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
var _label: Label = null


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
	var net: Node = get_node_or_null(^"/root/NetworkManager")
	if net != null and not peers_other.is_valid():
		net.connect(&"roster_changed", _on_roster_changed)


## The world stops being paused when it is left (the next scene starts running), and the pause
## unhooks from the roster. (It names no autoload: they are reached by path, lesson N-919.)
func _exit_tree() -> void:
	if _paused:
		resume()
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null and bus.is_connected(&"pause_requested", toggle):
		bus.disconnect(&"pause_requested", toggle)
	var net: Node = get_node_or_null(^"/root/NetworkManager")
	if net != null and net.is_connected(&"roster_changed", _on_roster_changed):
		net.disconnect(&"roster_changed", _on_roster_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_pause") and (_paused or can_pause()):
		toggle()
		get_viewport().set_input_as_handled()


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
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_label(true)
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
	_show_label(false)


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


func _show_label(shown: bool) -> void:
	if _label == null:
		if not shown:
			return
		var layer := CanvasLayer.new()
		layer.layer = 90
		add_child(layer)
		_label = Label.new()
		_label.text = tr("HUD_PAUSED")
		_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_label.add_theme_font_size_override(&"font_size", 48)
		layer.add_child(_label)
	_label.visible = shown

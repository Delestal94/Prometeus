class_name PlayerPingInput
extends RefCounted
## The ping button: a tap sends the plain warning, holding it opens the ping
## wheel (aimed with the mouse or the right stick) and releasing sends what
## was picked. Local to the owning player; the ping itself goes through the
## Player's _send_ping().

const PingWheelScene = preload("res://scripts/ui/ping_wheel.gd")
const HOLD_SECONDS: float = 0.28

var wheel_open: bool = false

var _player: Player
var _wheel: PingWheel
var _held: bool = false
var _hold_seconds: float = 0.0


func _init(player: Player) -> void:
	_player = player


## Only the local player's copy needs the wheel on screen.
func build_wheel() -> void:
	_wheel = PingWheelScene.new()
	_player.add_child(_wheel)


## Handles a ping press, release or wheel aim; true when the event was used.
func handle_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_ping"):
		_begin()
	elif event.is_action_released(&"ui_ping"):
		_finish()
	elif wheel_open and event is InputEventMouseMotion:
		_wheel.select_from_pointer(event.position)
	else:
		return false
	_player.get_viewport().set_input_as_handled()
	return true


func update(delta: float) -> void:
	if not _player.is_local() or not _held:
		return
	_hold_seconds += delta
	if not wheel_open and _hold_seconds >= HOLD_SECONDS:
		wheel_open = true
		_wheel.show_wheel()
	if wheel_open:
		var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
		if stick.length() >= 0.35:
			_wheel.select_from_vector(stick * PingWheel.DEAD_ZONE * 2.0)


func close_wheel() -> void:
	if not wheel_open:
		return
	wheel_open = false
	if is_instance_valid(_wheel):
		_wheel.hide_wheel()
	if _player.is_local() and not _player.get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _begin() -> void:
	if _held:
		return
	_held = true
	_hold_seconds = 0.0


func _finish() -> void:
	if not _held:
		return
	var label: String = _wheel.selected_label() if wheel_open else Player.PING_LABEL
	_held = false
	_hold_seconds = 0.0
	close_wheel()
	_player.call(&"_send_ping", label)

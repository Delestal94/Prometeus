extends Control
class_name PhoneFrame
## The phone's body seen from the inside of its screen: a bezel with rounded
## inner corners around the viewfinder, a status bar (camera tag, the status
## line, clock and battery) in the top bezel, a hint line in the bottom one
## and a round shutter button in the right one. The middle is left empty so
## the camera shows through.
##
## It only draws and reports: PhoneCamera decides what the status and hint
## say and what a shot does. The shutter button is the mouse's extra way to
## shoot -- the `phone_shutter` input action (click / RB) keeps working on its
## own -- and just emits `shutter_pressed`.
##
## Clock: there is no continuous world clock (WorldMood only knows DAY / DUSK
## / NIGHT), so the phone shows a plausible hour for the session's time of
## day and lets it tick along while the phone is up (one game minute every
## SECONDS_PER_GAME_MINUTE real seconds). The same world seed gives the same
## starting hour on every peer; nothing is replicated.
## Battery: decorative and deterministic -- it starts at BATTERY_START and
## drains slowly while the phone is up, never below BATTERY_FLOOR.

signal shutter_pressed

## Bezel thickness in pixels; matches the old square bezel so the framing of
## the shot doesn't change.
const BEZEL_TOP: float = 58.0
const BEZEL_BOTTOM: float = 58.0
const BEZEL_SIDE: float = 130.0
## Radius of the rounded corners of the screen opening.
const CORNER_RADIUS: float = 26.0
const CORNER_STEPS: int = 10
## Darker than UiTheme.INK on purpose: this is the phone's body, not a panel.
const INK: Color = Color("0a1418")
const PAPER: Color = UiTheme.PAPER
const MINT: Color = UiTheme.MINT
const MUTED: Color = UiTheme.MUTED
const RED: Color = UiTheme.RED
## Hour shown (minutes since midnight) for WorldMood.TimeOfDay DAY / DUSK / NIGHT.
const START_MINUTES: Array[int] = [14 * 60 + 5, 19 * 60 + 20, 23 * 60 + 40]
const SECONDS_PER_GAME_MINUTE: float = 6.0
const BATTERY_START: float = 0.82
const BATTERY_FLOOR: float = 0.2
const BATTERY_LOW: float = 0.3
## Battery fraction lost per real second while the phone is up.
const BATTERY_DRAIN_PER_SECOND: float = 0.0005
const SHUTTER_SIZE: float = 68.0

## 0..1. Decorative; exposed so a test can read and set it.
var battery: float = BATTERY_START:
	set(value):
		battery = clampf(value, 0.0, 1.0)
		if _battery_icon != null:
			_battery_icon.level = battery
			_battery_icon.queue_redraw()
var shutter_button: Control

var _open_seconds: float = 0.0
var _status_label: Label
var _hint_label: Label
var _clock_label: Label
var _battery_icon: BatteryIcon


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_status_bar()
	_build_hint()
	_build_shutter()
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()
	_refresh_clock()


## The line in the status bar (what the shot would be filed against).
func set_status(text: String, color: Color = MUTED) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


func set_hint(text: String) -> void:
	_hint_label.text = text


func hint_text() -> String:
	return _hint_label.text


func status_text() -> String:
	return _status_label.text


## Minutes since midnight on the phone's clock.
func clock_minutes() -> int:
	var time_of_day: int = clampi(int(WorldMood.active.get("time", 0)), 0, START_MINUTES.size() - 1)
	var elapsed: int = floori(_open_seconds / SECONDS_PER_GAME_MINUTE)
	return (START_MINUTES[time_of_day] + elapsed) % (24 * 60)


## "HH:MM", 24-hour.
func clock_text() -> String:
	var minutes: int = clock_minutes()
	return "%02d:%02d" % [floori(minutes / 60.0), minutes % 60]


## What the shutter button does; public so a test can press it without a mouse.
func press_shutter() -> void:
	shutter_pressed.emit()


func _process(delta: float) -> void:
	_open_seconds += delta
	battery = maxf(BATTERY_FLOOR, battery - BATTERY_DRAIN_PER_SECOND * delta)
	_refresh_clock()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _on_visibility_changed() -> void:
	set_process(is_visible_in_tree())
	if is_visible_in_tree():
		_refresh_clock()


func _refresh_clock() -> void:
	if _clock_label != null:
		_clock_label.text = clock_text()


func _build_status_bar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = 16
	bar.offset_left = BEZEL_SIDE + 20.0
	bar.offset_right = -(BEZEL_SIDE + 20.0)
	bar.add_theme_constant_override("separation", 14)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_make_label(bar, tr("HUD_PHONE_CAMERA"), 15, RED)
	_status_label = _make_label(bar, "", 15, MUTED)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock_label = _make_label(bar, "00:00", 15, PAPER)
	_battery_icon = BatteryIcon.new()
	_battery_icon.level = battery
	bar.add_child(_battery_icon)


func _build_hint() -> void:
	_hint_label = _make_label(self, "", 15, PAPER)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -40
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_shutter() -> void:
	var button := ShutterButton.new()
	button.tooltip_text = tr("HUD_PHONE_SHUTTER")
	# Centred in the right bezel.
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 0.5
	button.anchor_bottom = 0.5
	button.offset_left = -(BEZEL_SIDE + SHUTTER_SIZE) * 0.5
	button.offset_right = button.offset_left + SHUTTER_SIZE
	button.offset_top = -SHUTTER_SIZE * 0.5
	button.offset_bottom = SHUTTER_SIZE * 0.5
	button.pressed.connect(press_shutter)
	add_child(button)
	shutter_button = button


func _make_label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _draw() -> void:
	var body: Color = Color(INK, 0.97)
	var inner := Rect2(
		BEZEL_SIDE, BEZEL_TOP, size.x - BEZEL_SIDE * 2.0, size.y - BEZEL_TOP - BEZEL_BOTTOM
	)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), body)
		return
	# Four straight bars, then a fillet in each corner of the opening: the
	# sliver between the square corner and the quarter circle.
	draw_rect(Rect2(0.0, 0.0, size.x, inner.position.y), body)
	draw_rect(Rect2(0.0, inner.end.y, size.x, size.y - inner.end.y), body)
	draw_rect(Rect2(0.0, inner.position.y, inner.position.x, inner.size.y), body)
	draw_rect(Rect2(inner.end.x, inner.position.y, size.x - inner.end.x, inner.size.y), body)
	var radius: float = minf(CORNER_RADIUS, minf(inner.size.x, inner.size.y) * 0.5)
	_fillet(inner.position, Vector2(radius, radius), PI, body)
	_fillet(Vector2(inner.end.x, inner.position.y), Vector2(-radius, radius), PI * 1.5, body)
	_fillet(inner.end, Vector2(-radius, -radius), 0.0, body)
	_fillet(Vector2(inner.position.x, inner.end.y), Vector2(radius, -radius), PI * 0.5, body)


## One corner of the opening. `corner` is the square corner, `toward_centre`
## the (signed) offset to the arc's centre, `start` the arc's first angle; the
## arc sweeps a quarter turn.
func _fillet(corner: Vector2, toward_centre: Vector2, start: float, color: Color) -> void:
	var centre: Vector2 = corner + toward_centre
	var radius: float = absf(toward_centre.x)
	var points := PackedVector2Array([corner])
	for step: int in range(CORNER_STEPS + 1):
		var angle: float = start + (PI * 0.5) * float(step) / float(CORNER_STEPS)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)


## Battery glyph: outline, terminal nub and a level bar. Low charge turns red
## and the bar shrinks, so it never relies on colour alone.
class BatteryIcon extends Control:
	var level: float = 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(34.0, 16.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var color: Color = RED if level < BATTERY_LOW else PAPER
		var body := Rect2(1.0, 2.0, 28.0, 13.0)
		draw_rect(body, INK, true)
		draw_rect(body, color, false, 2.0)
		draw_rect(Rect2(30.0, 6.0, 3.0, 5.0), color)
		var fill_width: float = (body.size.x - 6.0) * clampf(level, 0.0, 1.0)
		draw_rect(Rect2(body.position.x + 3.0, body.position.y + 3.0, fill_width, 7.0), color)


## Round shutter: a ring with a solid disc inside. Pressing shrinks the disc.
class ShutterButton extends Control:
	signal pressed

	var _hovered: bool = false
	var _down: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		# Gamepad and keyboard shoot through the input action; this button must
		# not steal focus from them.
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(_set_hover.bind(true))
		mouse_exited.connect(_set_hover.bind(false))

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click == null or click.button_index != MOUSE_BUTTON_LEFT:
			return
		_down = click.pressed
		queue_redraw()
		if click.pressed:
			pressed.emit()
		accept_event()

	func _set_hover(value: bool) -> void:
		_hovered = value
		if not value:
			_down = false
		queue_redraw()

	func _draw() -> void:
		var centre: Vector2 = size * 0.5
		var radius: float = minf(size.x, size.y) * 0.5
		draw_circle(centre, radius, Color(INK, 0.9))
		draw_arc(centre, radius - 3.0, 0.0, TAU, 40, PAPER, 3.0, true)
		var disc: float = radius - (13.0 if _down else 9.0)
		draw_circle(centre, disc, PAPER if _hovered or _down else Color(PAPER, 0.85))

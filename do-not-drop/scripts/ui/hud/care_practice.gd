extends PanelContainer
## Practice in the depot, before the first run (playtest 2026-09-28: "I don't
## know whether to pick it up or what to do"): five steps that tick as the
## player actually does them with a real box, each shown by the same
## animated strip the care card uses on the road. Local only -- nothing here
## touches the simulation -- and done once per profile (UnlockManager's
## seen tips); the road card is terse on purpose because this came first.

const CarePromptView = preload("res://scripts/ui/hud/care_prompt_view.gd")
const UiThemeScript = preload("res://scripts/ui/ui_theme.gd")
const WIDTH: float = 360.0
## The profile flag, alongside the per-trap first tips.
const SEEN_ID: StringName = &"care_practice"
## Seconds of holding that count as having done it.
const HOLD_SECONDS: float = 1.0
const PRACTICE_SEQUENCE: Array[StringName] = [&"up", &"left", &"down"]
## Shown after the last tick, then the card goes away for good.
const FAREWELL_SECONDS: float = 2.5
const STEP_TEXTS: Array[String] = ["Agarrá una caja", "Mantené %s: la cuidás", "Mantené %s: usás una herramienta",
	"Con %s mantenido, tocá W, A, S (como la bomba)", "Subila al estante o sentate con ella"]
const STEP_VIEWS: Array[StringName] = [&"grab", &"hold", &"tool", &"sequence", &"load"]

var step: int = 0
var finished: bool = false
## Where "done" is remembered (UnlockManager); set by the owner, left empty
## in tests so they never touch a real profile.
var profile: Node
var prompt_view: CarePromptView
var _rows: Array[Label] = []
var _marks: Array[StepMark] = []
var _hold_time: float = 0.0
var _tool_time: float = 0.0
var _sequence_index: int = 0
var _mistakes: int = 0
var _farewell: float = 0.0
var _title: Label


## Done (mint, ticked), current (orange ring) or still ahead (a dot): drawn,
## since the fonts have no tick glyph.
class StepMark extends Control:
	var state: int = 0
	func _draw() -> void:
		var center := size * 0.5
		match state:
			2:
				draw_circle(center, 9.0, UiTheme.MINT)
				draw_arc(center, 9.0, 0.0, TAU, 24, UiTheme.INK, 2.0, true)
				var tick := PackedVector2Array([center + Vector2(-4, 0), center + Vector2(-1, 3),
					center + Vector2(5, -4)])
				draw_polyline(tick,
					UiTheme.INK, 2.5, true)
			1:
				draw_arc(center, 8.0, 0.0, TAU, 24, UiTheme.ORANGE, 3.0, true)
			_:
				draw_circle(center, 3.0, UiTheme.MUTED)


func _init() -> void:
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiThemeScript.surface_style(16))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	UiThemeScript.tag(column, "PRÁCTICA", UiThemeScript.SKY, -2.0, 16)
	_title = UiThemeScript.title(column, "CÓMO CUIDAR LA CARGA", 24)
	prompt_view = CarePromptView.new()
	prompt_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(prompt_view)
	for i: int in STEP_TEXTS.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		column.add_child(row)
		var mark := StepMark.new()
		mark.custom_minimum_size = Vector2(22, 22)
		row.add_child(mark)
		_marks.append(mark)
		var text: Label = UiThemeScript.label(row, "", 16)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = WIDTH - 32 - 30
		_rows.append(text)
	var note: Label = UiThemeScript.label(column, "Cuando quieras, subite a manejar para salir.", 16,
		UiThemeScript.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = WIDTH - 32


## Whether this profile still has the practice to do.
static func pending(profile: Node) -> bool:
	return profile != null and not bool((profile.get(&"seen_tips") as Dictionary).get(SEEN_ID, false))


## One frame of practice. `player` is the local player; `keys` from
## PlayerCargoCare.control_names(). Returns false once it's over and gone.
func advance(delta: float, player: Node, keys: Dictionary, gamepad: bool) -> bool:
	if finished:
		_farewell -= delta
		prompt_view.show_step(&"load", {"pad": gamepad, "fixes": STEP_TEXTS.size()})
		return _farewell > 0.0
	var carried: Node = player.get(&"carried_package")
	var holding_box: bool = is_instance_valid(carried)
	var primary: bool = Input.is_action_pressed(&"package_action_primary")
	var tool_held: bool = Input.is_action_pressed(&"care_work")
	match step:
		0:
			if holding_box:
				_next()
		1:
			_hold_time = _hold_time + delta if holding_box and primary else maxf(0.0, _hold_time - delta)
			if _hold_time >= HOLD_SECONDS:
				_next()
		2:
			_tool_time = _tool_time + delta if holding_box and tool_held else _tool_time
			if _tool_time >= HOLD_SECONDS:
				_next()
		3:
			# Same rule as on the road: on foot, taps count with the box held.
			if primary or not String(player.get(&"seat_node_path")).is_empty():
				_read_taps()
			if _sequence_index >= PRACTICE_SEQUENCE.size():
				_next()
		4:
			if _any_aboard(player):
				_next()
	_refresh(keys)
	var view_step: StringName = STEP_VIEWS[mini(step, STEP_VIEWS.size() - 1)]
	prompt_view.show_step(view_step, {"pad": gamepad, "primary": primary and holding_box, "tool_held": tool_held,
		"work": _tool_time / HOLD_SECONDS, "fixes": step, "interact": keys.get("interact", "E"),
		"sequence": {"steps": PRACTICE_SEQUENCE, "index": _sequence_index, "mistakes": _mistakes, "solved": 0}})
	return true


func _read_taps() -> void:
	for pair: Array in [[&"walk_forward", &"up"], [&"walk_backward", &"down"], [&"drive_left", &"left"],
			[&"drive_right", &"right"]]:
		if Input.is_action_just_pressed(pair[0]):
			tap(pair[1])


## One direction tapped during the sequence step.
func tap(pressed: StringName) -> void:
	if step != 3 or _sequence_index >= PRACTICE_SEQUENCE.size():
		return
	if pressed == PRACTICE_SEQUENCE[_sequence_index]:
		_sequence_index += 1
	else:
		_sequence_index = 0
		_mistakes += 1


func _next() -> void:
	step += 1
	if step >= STEP_TEXTS.size():
		finished = true
		_farewell = FAREWELL_SECONDS
		_title.text = "¡LISTO! YA SABÉS"
		if profile != null:
			profile.call(&"mark_tip_seen", SEEN_ID)


func _refresh(keys: Dictionary) -> void:
	for i: int in _rows.size():
		var text: String = STEP_TEXTS[i]
		if i == 1 or i == 3:
			text = text % keys.get("primary", "Clic izq.")
		elif i == 2:
			text = text % keys.get("tool", "Clic der.")
		elif i == 0:
			text += " (%s)" % keys.get("interact", "E")
		_rows[i].text = text
		var done: bool = i < step
		var state: int = 2 if done else (1 if i == step else 0)
		if _marks[i].state != state:
			_marks[i].state = state
			_marks[i].queue_redraw()
		var color: Color = UiThemeScript.MUTED if done or i > step else UiThemeScript.INK
		_rows[i].add_theme_color_override("font_color", color)


static func _any_aboard(player: Node) -> bool:
	for node: Node in player.get_tree().get_nodes_in_group(&"cargo"):
		if node.has_method(&"is_aboard") and bool(node.call(&"is_aboard")):
			return true
	return false

extends Control
class_name CompanyOnboardingLine
## The first week's guide line of the company mode (expansion D-1901, diseno/onboarding.md §1 rule 3): one line,
## never two, at the top left, with the control that does it (keyboard or gamepad, the one used last). When an
## objective is done it shows "✓" with that line for TICK_SECONDS, then the next one. It never pauses, opens
## nothing and blocks nothing: CompanyOnboardingTracker decides what it says.
##
## The control's name comes from the input map as the player has it now (ClipboardFrame.action_label: the
## company's actions are not in GameSettings' rebind list); GameSettings is read by path (lesson N-919).

const TICK_SECONDS: float = 1.5
const TICK_MARK: String = "✓ "
const TODO_MARK: String = "▸ "

var _label: Label
var _key_label: Label
var _shown: Dictionary = {}
var _queued: Dictionary = {}
var _tick_left: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(self)
	var column: VBoxContainer = UiTheme.panel(self, Vector2(360, 0), 12)
	(column.get_parent() as Control).position = Vector2(16, 64)
	(column.get_parent() as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiTheme.label(column, "", 18, UiTheme.INK, true)
	_label.name = "Objective"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_key_label = UiTheme.label(column, "", 15, UiTheme.MUTED)
	_key_label.name = "Control"
	set_process(false)
	_draw_line(_queued)


## Shows `line` ({id, key, action}; {} hides it). While a tick is on screen the new line waits for it.
func show_line(line: Dictionary) -> void:
	_queued = line
	if _label != null and _tick_left <= 0.0:
		_draw_line(line)


## `id` was just done: "✓" with its line for a moment.
func tick(id: StringName) -> void:
	if _label == null or not CompanyOnboarding.KEYS.has(id):
		return
	_label.text = TICK_MARK + tr(String(CompanyOnboarding.KEYS[id]))
	_key_label.text = ""
	visible = true
	_tick_left = TICK_SECONDS
	set_process(true)


## The objective's text as shown ("" when hidden).
func objective_text() -> String:
	return _label.text if _label != null and visible else ""


## The control's text as shown.
func control_text() -> String:
	return _key_label.text if _key_label != null and visible else ""


func _process(delta: float) -> void:
	_tick_left -= delta
	if _tick_left <= 0.0:
		set_process(false)
		_draw_line(_queued)


func _draw_line(line: Dictionary) -> void:
	_shown = line
	visible = not line.is_empty()
	if line.is_empty():
		return
	_label.text = TODO_MARK + tr(String(line["key"]))
	var pad: bool = _using_gamepad()
	_key_label.text = tr("UI_ONBOARD_CONTROL") % ClipboardFrame.action_label(StringName(line["action"]), pad)


func _using_gamepad() -> bool:
	var settings: Node = get_node_or_null(^"/root/GameSettings") if is_inside_tree() else null
	return settings != null and bool(settings.get(&"using_gamepad"))

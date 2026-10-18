extends Control
class_name DaySummaryPanel
## Closing screen of a company day (expansion D-0508.2, "Modo Empresa").
##
## Draws what DaySummary.build() returns (the same dictionary DayCycle publishes in its SUMMARY
## phase and EventBus.company_day_summary carries): income and costs by reason, the day's profit
## and the opening and closing balance. It reads the dictionary and nothing else, so a client
## shows what the host closed. Reason names are the translation keys finance_reason_<reason>; a
## reason without a key shows its own id, so a new charge never needs this file.

signal continued

## Rows shown in each list; the rest is folded into one "other" row so the panel keeps its size.
const MAX_ROWS: int = 8
const REASON_KEY: String = "finance_reason_%s"
const OTHER_REASON: String = "other"

var _day_label: Label
var _income_list: VBoxContainer
var _cost_list: VBoxContainer
var _profit_label: Label
var _balance_label: Label
var _truncated_label: Label
var _continue_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	_build()
	hide()


## Shows the closing screen for `summary` (DaySummary.build()'s shape) and takes focus.
func open(summary: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh(summary)
	show()
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)
	_continue_button.grab_focus.call_deferred()


func close() -> void:
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	hide()
	continued.emit()


## Redraws the panel from `summary`. A missing key counts as zero / empty.
func refresh(summary: Dictionary) -> void:
	if _day_label == null:
		return
	_day_label.text = tr("finance_day") % int(summary.get("day", 0))
	_fill(_income_list, summary.get("income_by_reason", {}), int(summary.get("income", 0)), UiTheme.MINT)
	_fill(_cost_list, summary.get("cost_by_reason", {}), int(summary.get("costs", 0)), UiTheme.RED)
	var profit: int = int(summary.get("profit", 0))
	_profit_label.text = tr("finance_profit") % _signed(profit)
	_profit_label.add_theme_color_override(&"font_color", _profit_color(profit))
	_balance_label.text = tr("finance_balance") % [money(int(summary.get("opening", 0))),
			money(int(summary.get("closing", 0)))]
	_truncated_label.visible = bool(summary.get("truncated", false))


## The shown name of a ledger reason: its translation, or the id itself when it has none.
static func reason_name(reason: String) -> String:
	var key: String = REASON_KEY % reason
	var text: String = TranslationServer.translate(key)
	return reason if text == key else text


static func money(amount: int) -> String:
	return "$%d" % amount if amount >= 0 else "-$%d" % -amount


## Rows of one list: the reasons biggest first, at most MAX_ROWS, the rest folded into one
## OTHER_REASON row. Each is [reason, amount].
static func rows(by_reason: Dictionary) -> Array:
	var ordered: Array[String] = DaySummary.sorted_reasons(by_reason)
	var result: Array = []
	var folded: int = 0
	for i: int in ordered.size():
		var amount: int = int(by_reason[ordered[i]])
		if i < MAX_ROWS - 1 or ordered.size() <= MAX_ROWS:
			result.append([ordered[i], amount])
		else:
			folded += amount
	if folded > 0:
		result.append([OTHER_REASON, folded])
	return result


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = UiTheme.panel(center, Vector2(760, 0), 24)
	column.add_theme_constant_override("separation", 10)
	UiTheme.title(column, tr("finance_title"), 38)
	_day_label = UiTheme.label(column, "", 17, UiTheme.MUTED)
	var lists := HBoxContainer.new()
	lists.add_theme_constant_override("separation", 20)
	column.add_child(lists)
	_income_list = _list(lists, tr("finance_income"), UiTheme.MINT)
	_cost_list = _list(lists, tr("finance_costs"), UiTheme.RED)
	_profit_label = UiTheme.label(column, "", 28, UiTheme.INK, true)
	_profit_label.name = "Profit"
	_balance_label = UiTheme.label(column, "", 16, UiTheme.MUTED)
	_balance_label.name = "Balance"
	_truncated_label = UiTheme.label(column, tr("finance_truncated"), 14, UiTheme.ORANGE)
	_truncated_label.name = "Truncated"
	_continue_button = UiTheme.button(column, tr("finance_continue"), true)
	_continue_button.pressed.connect(close)


func _list(parent: Control, heading: String, color: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	UiTheme.tag(box, heading, color, 0.0, 15)
	var rows_box := VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 3)
	box.add_child(rows_box)
	return rows_box


func _fill(list: VBoxContainer, by_reason: Variant, total: int, color: Color) -> void:
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var table: Dictionary = by_reason if by_reason is Dictionary else {}
	if table.is_empty():
		UiTheme.label(list, tr("finance_none"), 15, UiTheme.MUTED).name = "None"
	for entry: Array in rows(table):
		var row := HBoxContainer.new()
		row.name = "Row_%s" % entry[0]
		list.add_child(row)
		var name_label: Label = UiTheme.label(row, reason_name(String(entry[0])), 16)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UiTheme.label(row, money(int(entry[1])), 16, color, true).name = "Amount"
	var total_label: Label = UiTheme.label(list, tr("finance_total") % money(total), 16, color, true)
	total_label.name = "Total"


static func _signed(amount: int) -> String:
	return "+%s" % money(amount) if amount > 0 else money(amount)


static func _profit_color(profit: int) -> Color:
	if profit > 0:
		return UiTheme.MINT
	return UiTheme.RED if profit < 0 else UiTheme.INK


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

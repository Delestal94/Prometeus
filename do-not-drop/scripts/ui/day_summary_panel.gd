extends Control
class_name DaySummaryPanel
## Closing screen of a company day (expansion D-0508.2, "Modo Empresa").
##
## Draws what DaySummary.build() returns (the same dictionary DayCycle publishes in its SUMMARY
## phase and EventBus.company_day_summary carries): income and costs by reason, the day's profit
## and the opening and closing balance. It reads the dictionary and the note lines it is given, so a client
## shows what the host closed. Reason names are the translation keys UI_FINANCE_REASON_<REASON> (REASON_KEYS); a
## reason without a key shows its own id, so a new charge never needs this file.
##
## Below the money, the supplier's delivery note of the day (D-0614.c): one row per product the truck
## left short or brought extra (DeliveryNote.discrepancies(), which every peer keeps through
## CompanyPallets), hidden when the delivery came out even.
##
## And one line when the host sent the supplier order by itself at the close (D-0151.3b), hidden otherwise.
##
## The company's shop (D-0511.2) opens from here: a "Shop" button beside Continue, off until the world that
## hosts the screen turns it on (set_shop_available()); it only emits `shop_requested`, CompanyShopScreen opens
## the shop over this panel.
##
## D-1905: under the money, side by side, the milestones of the day and the wages paid (one row per employee and
## their total), and one "Mañana:" line per day event announced for tomorrow; each part hides when it is empty.
## The rows come from DayCloseReport, which also names the prefixed ledger reasons (`milestone:<id>`,
## `day_event:<id>`). The milestones heard during the day (EventBus.milestone_reached, by path: N-919) join the
## ones the ledger paid, and are forgotten when the screen closes.

signal continued
signal shop_requested

## Space kept free above and below the panel, and the least the scrolling body shrinks to (D-1910).
const FIT_MARGIN: float = 16.0
const MIN_BODY: float = 120.0
## How far ui_up / ui_down scroll the body.
const SCROLL_STEP: int = 60
## Rows shown in each list; the rest is folded into one "other" row so the panel keeps its size.
const MAX_ROWS: int = 8
## Ledger reason -> translation key. Literal keys, so the translation test sees them used.
const REASON_KEYS: Dictionary = {
	"order_paid": "UI_FINANCE_REASON_ORDER_PAID",
	"tip": "UI_FINANCE_REASON_TIP",
	"placeable_sell": "UI_FINANCE_REASON_PLACEABLE_SELL",
	"supplier": "UI_FINANCE_REASON_SUPPLIER",
	"boxes": "UI_FINANCE_REASON_BOXES",
	"packaging": "UI_FINANCE_REASON_PACKAGING",
	"rent": "UI_FINANCE_REASON_RENT",
	"placeable_buy": "UI_FINANCE_REASON_PLACEABLE_BUY",
	"warehouse_expand": "UI_FINANCE_REASON_WAREHOUSE_EXPAND",
	"penalty": "UI_FINANCE_REASON_PENALTY",
	"tow": "UI_FINANCE_REASON_TOW",
	"wages": "UI_FINANCE_REASON_WAGES",
	"other": "UI_FINANCE_REASON_OTHER",
}
const OTHER_REASON: String = "other"

var _day_label: Label
var _income_list: VBoxContainer
var _cost_list: VBoxContainer
var _profit_label: Label
var _balance_label: Label
var _truncated_label: Label
var _note_box: VBoxContainer
var _note_list: VBoxContainer
var _auto_label: Label
var _extras_box: HBoxContainer
var _milestone_box: VBoxContainer
var _milestone_list: VBoxContainer
var _wage_box: VBoxContainer
var _wage_list: VBoxContainer
var _tomorrow_list: VBoxContainer
var _heard_milestones: Array[String] = []
var _body_scroll: ScrollContainer
var _body: VBoxContainer
var _continue_button: Button
var _shop_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	_build()
	hide()
	get_viewport().size_changed.connect(_fit_body)
	var settings: Node = get_node_or_null(^"/root/GameSettings")
	if settings != null and settings.has_signal(&"menu_text_scale_changed"):
		settings.connect(&"menu_text_scale_changed", func(_scale: float) -> void: _fit_body.call_deferred())
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null and bus.has_signal(&"milestone_reached"):
		bus.connect(&"milestone_reached", note_milestone)


## Shows the closing screen for `summary` (DaySummary.build()'s shape) and the day's delivery note
## lines (DeliveryNote.discrepancies(): {product, ordered, received, missing, extra}), and takes focus.
## `auto_units` is what the automatic supplier order of the close brought (0: none); `extras` is
## DayCloseReport.extras() ({employees, tomorrow}).
func open(summary: Dictionary, note_lines: Array = [], auto_units: int = 0, extras: Dictionary = {}) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh(summary, note_lines, auto_units, extras)
	show()
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)
	_continue_button.grab_focus.call_deferred()


func close() -> void:
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	hide()
	_heard_milestones.clear()
	continued.emit()


## A milestone reached during the day: listed on the next closing screen.
func note_milestone(milestone_id: StringName) -> void:
	if milestone_id != &"" and not _heard_milestones.has(String(milestone_id)):
		_heard_milestones.append(String(milestone_id))


## Shows or hides the Shop button (the shop is a screen of the Company world, not of this panel).
func set_shop_available(available: bool) -> void:
	if _shop_button == null:
		return
	_shop_button.visible = available
	# Side moves only when the button is there; alone, Continue keeps the focus.
	var other: Button = _shop_button if available else _continue_button
	_continue_button.focus_neighbor_right = _continue_button.get_path_to(other)
	_shop_button.focus_neighbor_left = _shop_button.get_path_to(_continue_button)


## Puts the focus back where open() left it (after the shop closes).
func focus_default() -> void:
	if _continue_button != null and visible:
		_continue_button.grab_focus()


## Redraws the panel from `summary`, `note_lines` and `auto_units`. A missing key counts as zero / empty.
func refresh(summary: Dictionary, note_lines: Array = [], auto_units: int = 0, extras: Dictionary = {}) -> void:
	if _day_label == null:
		return
	_day_label.text = tr("UI_FINANCE_DAY") % int(summary.get("day", 0))
	_fill(_income_list, summary.get("income_by_reason", {}), int(summary.get("income", 0)), UiTheme.MINT)
	_fill(_cost_list, summary.get("cost_by_reason", {}), int(summary.get("costs", 0)), UiTheme.RED)
	var profit: int = int(summary.get("profit", 0))
	_profit_label.text = tr("UI_FINANCE_PROFIT") % _signed(profit)
	_profit_label.add_theme_color_override(&"font_color", _profit_color(profit))
	_balance_label.text = tr("UI_FINANCE_BALANCE") % [money(int(summary.get("opening", 0))),
			money(int(summary.get("closing", 0)))]
	_truncated_label.visible = bool(summary.get("truncated", false))
	_fill_note(note_lines)
	_auto_label.text = tr("UI_FINANCE_AUTO_ORDER") % auto_units
	_auto_label.visible = auto_units > 0
	_fill_extras(summary, extras)
	_fit_body.call_deferred()


## The shown name of a ledger reason: its translation, or the id itself when it has none.
static func reason_name(reason: String) -> String:
	var prefixed: String = DayCloseReport.reason_name(reason)
	if prefixed != "":
		return prefixed
	var key: String = String(REASON_KEYS.get(reason, ""))
	if key.is_empty():
		return reason
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


## The rows of the delivery note: lines that are short or extra, at most MAX_ROWS, each
## [product, text]; past MAX_ROWS - 1 the rest is one [OTHER_REASON, text] row with how many more.
## A line that is not a dictionary, has no product or comes out even is skipped.
static func note_rows(note_lines: Array) -> Array:
	var shown: Array = []
	for raw: Variant in note_lines:
		if not raw is Dictionary:
			continue
		var line: Dictionary = raw
		var product := StringName(str(line.get("product", "")))
		if product == &"" or (int(line.get("missing", 0)) < 1 and int(line.get("extra", 0)) < 1):
			continue
		shown.append([product, note_text(line)])
	if shown.size() <= MAX_ROWS:
		return shown
	var result: Array = shown.slice(0, MAX_ROWS - 1)
	var more: int = shown.size() - result.size()
	result.append([OTHER_REASON, TranslationServer.translate("UI_FINANCE_NOTE_MORE") % more])
	return result


## One line of the note as read: "<product>: llegaron 4 de 10 (faltan 6)" or "(sobran 2)".
static func note_text(line: Dictionary) -> String:
	var shown_name: String = PickingCartPoint.product_name(StringName(str(line.get("product", ""))))
	var ordered: int = int(line.get("ordered", 0))
	var received: int = int(line.get("received", 0))
	var missing: int = int(line.get("missing", 0))
	if missing > 0:
		return TranslationServer.translate("UI_FINANCE_NOTE_SHORT") % [shown_name, received, ordered, missing]
	var extra: int = int(line.get("extra", 0))
	return TranslationServer.translate("UI_FINANCE_NOTE_EXTRA") % [shown_name, received, ordered, extra]


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
	UiTheme.title(column, tr("UI_FINANCE_TITLE"), 38)
	_day_label = UiTheme.label(column, "", 17, UiTheme.MUTED)
	# Everything between the title and the buttons scrolls when it does not fit the screen (D-1910: a day
	# with every part at 1280x720, the Steam Deck's 1280x800, or bigger menu text).
	_body_scroll = ScrollContainer.new()
	_body_scroll.name = "Body"
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_body_scroll)
	var body := VBoxContainer.new()
	body.name = "Content"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	_body_scroll.add_child(body)
	_body = body
	var lists := HBoxContainer.new()
	lists.add_theme_constant_override("separation", 20)
	body.add_child(lists)
	_income_list = _list(lists, tr("UI_FINANCE_INCOME"), UiTheme.MINT)
	_cost_list = _list(lists, tr("UI_FINANCE_COSTS"), UiTheme.RED)
	_profit_label = UiTheme.label(body, "", 28, UiTheme.INK, true)
	_profit_label.name = "Profit"
	_balance_label = UiTheme.label(body, "", 16, UiTheme.MUTED)
	_balance_label.name = "Balance"
	_truncated_label = UiTheme.label(body, tr("UI_FINANCE_TRUNCATED"), 14, UiTheme.ORANGE)
	_truncated_label.name = "Truncated"
	_note_box = VBoxContainer.new()
	_note_box.name = "Note"
	_note_box.add_theme_constant_override("separation", 3)
	body.add_child(_note_box)
	UiTheme.tag(_note_box, tr("UI_FINANCE_NOTE"), UiTheme.ORANGE, 0.0, 15)
	_note_list = VBoxContainer.new()
	_note_list.add_theme_constant_override("separation", 3)
	_note_box.add_child(_note_list)
	_note_box.hide()
	_auto_label = UiTheme.label(body, "", 15, UiTheme.INK)
	_auto_label.name = "AutoOrder"
	_auto_label.hide()
	_build_extras(body)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_continue_button = UiTheme.button(buttons, tr("UI_FINANCE_CONTINUE"), true)
	_continue_button.name = "Continue"
	_continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue_button.pressed.connect(close)
	_shop_button = UiTheme.button(buttons, tr("UI_FINANCE_SHOP"))
	_shop_button.name = "Shop"
	_shop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_button.pressed.connect(shop_requested.emit)
	_shop_button.hide()


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
		UiTheme.label(list, tr("UI_FINANCE_NONE"), 15, UiTheme.MUTED).name = "None"
	for entry: Array in rows(table):
		var row := HBoxContainer.new()
		row.name = "Row_%s" % entry[0]
		list.add_child(row)
		var name_label: Label = UiTheme.label(row, reason_name(String(entry[0])), 16)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UiTheme.label(row, money(int(entry[1])), 16, color, true).name = "Amount"
	var total_label: Label = UiTheme.label(list, tr("UI_FINANCE_TOTAL") % money(total), 16, color, true)
	total_label.name = "Total"


func _build_extras(column: VBoxContainer) -> void:
	_extras_box = HBoxContainer.new()
	_extras_box.name = "Extras"
	_extras_box.add_theme_constant_override("separation", 20)
	column.add_child(_extras_box)
	_milestone_list = _list(_extras_box, tr("UI_DAYCLOSE_MILESTONES"), UiTheme.YELLOW)
	_milestone_box = _milestone_list.get_parent() as VBoxContainer
	_milestone_box.name = "Milestones"
	_wage_list = _list(_extras_box, tr("UI_DAYCLOSE_WAGES"), UiTheme.ORANGE)
	_wage_box = _wage_list.get_parent() as VBoxContainer
	_wage_box.name = "Wages"
	_tomorrow_list = VBoxContainer.new()
	_tomorrow_list.name = "Tomorrow"
	_tomorrow_list.add_theme_constant_override("separation", 3)
	column.add_child(_tomorrow_list)


func _fill_extras(summary: Dictionary, extras: Dictionary) -> void:
	for list: VBoxContainer in [_milestone_list, _wage_list, _tomorrow_list]:
		for child: Node in list.get_children():
			list.remove_child(child)
			child.queue_free()
	var reached: Array[String] = DayCloseReport.milestones(summary, _heard_milestones)
	for id: String in reached:
		var label: Label = UiTheme.label(_milestone_list, DayCloseReport.milestone_name(id), 16, UiTheme.INK)
		label.name = "Milestone_%s" % id
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var employees: Variant = extras.get("employees", [])
	var wages: Array = DayCloseReport.wage_rows(employees if employees is Array else [])
	for i: int in wages.size():
		var row := HBoxContainer.new()
		row.name = "Wage_%d" % i
		_wage_list.add_child(row)
		var name_label: Label = UiTheme.label(row, String(wages[i][0]), 16)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UiTheme.label(row, money(int(wages[i][1])), 16, UiTheme.ORANGE, true).name = "Amount"
	if not wages.is_empty():
		var total: String = tr("UI_FINANCE_TOTAL") % money(DayCloseReport.wages_total(wages))
		UiTheme.label(_wage_list, total, 16, UiTheme.ORANGE, true).name = "Total"
	_milestone_box.visible = not reached.is_empty()
	_wage_box.visible = not wages.is_empty()
	_extras_box.visible = _milestone_box.visible or _wage_box.visible
	var tomorrow: Variant = extras.get("tomorrow", [])
	for line: String in DayCloseReport.tomorrow_lines(tomorrow if tomorrow is Array else []):
		UiTheme.label(_tomorrow_list, line, 15, UiTheme.INK).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tomorrow_list.visible = _tomorrow_list.get_child_count() > 0


func _fill_note(note_lines: Array) -> void:
	for child: Node in _note_list.get_children():
		_note_list.remove_child(child)
		child.queue_free()
	var rows_shown: Array = note_rows(note_lines)
	for entry: Array in rows_shown:
		var label: Label = UiTheme.label(_note_list, String(entry[1]), 15, UiTheme.INK)
		label.name = "Note_%s" % entry[0]
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_note_box.visible = not rows_shown.is_empty()


static func _signed(amount: int) -> String:
	return "+%s" % money(amount) if amount > 0 else money(amount)


static func _profit_color(profit: int) -> Color:
	if profit > 0:
		return UiTheme.MINT
	return UiTheme.RED if profit < 0 else UiTheme.INK


## Sizes the scrolling body to its content, or to the screen's height left by the title and the buttons when the
## content is taller (D-1910). Public so a test can fit it at once.
func fit_body() -> void:
	_fit_body()


func _fit_body() -> void:
	if _body_scroll == null or not is_inside_tree():
		return
	var panel := _body_scroll.get_parent().get_parent() as Control
	var chrome: float = panel.get_combined_minimum_size().y - _body_scroll.custom_minimum_size.y
	var room: float = get_viewport_rect().size.y - FIT_MARGIN * 2.0 - chrome
	_body_scroll.custom_minimum_size.y = minf(_body.get_combined_minimum_size().y, maxf(room, MIN_BODY))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_down"):
		# The body has nothing to focus: the pad scrolls it.
		_body_scroll.scroll_vertical += SCROLL_STEP if event.is_action_pressed(&"ui_down") else -SCROLL_STEP
		get_viewport().set_input_as_handled()

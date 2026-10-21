extends PanelContainer
class_name OrderBoardPanel
## The order board of the shed (expansion D-0804, "Modo Empresa"): one card per order with its
## state, customer, address, what it holds, the requirements, the time left and the pay.
##
## Draws what OrderBoard.rows() returns and nothing else, so a client shows what the host
## mirrored. Every state has a mark besides its colour ("○" open, "◐" packed, "●" out, "!" late,
## "✓" delivered, "✗" failed, "–" cancelled), so it reads without colour. A wall board: no focus,
## no input.

const MAX_SHOWN: int = 8

var _column: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(self)
	add_theme_stylebox_override(&"panel", UiTheme.surface_style(16))
	custom_minimum_size = Vector2(420, 0)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 6)
	add_child(_column)
	refresh([])


## Redraws the board from `rows` (OrderBoard.rows()'s shape). An empty list shows "no orders".
func refresh(rows: Array) -> void:
	if _column == null:
		return
	for child: Node in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	UiTheme.title(_column, tr("UI_ORDER_BOARD_TITLE"), 24)
	if rows.is_empty():
		UiTheme.label(_column, tr("UI_ORDER_BOARD_EMPTY"), 16, UiTheme.MUTED).name = "Empty"
		return
	for i: int in mini(rows.size(), MAX_SHOWN):
		_card(rows[i])
	if rows.size() > MAX_SHOWN:
		var more: String = tr("UI_ORDER_BOARD_MORE") % (rows.size() - MAX_SHOWN)
		UiTheme.label(_column, more, 15, UiTheme.MUTED).name = "More"


func _card(row: Dictionary) -> void:
	var id: String = String(row["order"])
	var head: String = "%s  %s" % [row["mark"], tr(String(row["state_key"]))]
	UiTheme.label(_column, head, 17, _state_color(row), true).name = "State_%s" % id
	var address: Dictionary = row.get("address", {})
	var who: String = tr("UI_ORDER_SHEET_FOR") % str(row.get("customer", ""))
	if not address.is_empty():
		var street: String = tr(String(address["street_key"]))
		who += " · " + tr("UI_ORDER_SHEET_ADDRESS") % [street, int(address["number"])]
	UiTheme.label(_column, who, 15).name = "Who_%s" % id
	var parts: Array[String] = []
	for item: Dictionary in row.get("items", []):
		parts.append(tr("UI_ORDER_BOARD_ITEM") % [item["name"], int(item["qty"])])
	for key: String in row.get("requirements", []):
		parts.append("[%s]" % tr(key))
	var what: Label = UiTheme.label(_column, ", ".join(parts), 14, UiTheme.MUTED)
	what.name = "What_%s" % id
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not bool(row["closed"]):
		var minutes: int = int(row["minutes_left"])
		var late: bool = bool(row["late"])
		var time_text: String = tr("UI_ORDER_SHEET_LEFT") % minutes
		if late:
			time_text = tr("UI_ORDER_SHEET_LATE") % -minutes
		UiTheme.label(_column, time_text, 14, UiTheme.RED if late else UiTheme.INK).name = "Time_%s" % id
	var pay: String = tr("UI_ORDER_SHEET_PAY") % int(row["pay"])
	UiTheme.label(_column, pay, 15, UiTheme.INK, true).name = "Pay_%s" % id


static func _state_color(row: Dictionary) -> Color:
	match row["state"]:
		Order.STATE_LATE, Order.STATE_FAILED:
			return UiTheme.RED
		Order.STATE_PACKED:
			return UiTheme.ORANGE
		Order.STATE_OUT:
			return UiTheme.SKY
		Order.STATE_DELIVERED:
			return UiTheme.MINT
		Order.STATE_CANCELLED:
			return UiTheme.MUTED
	return UiTheme.INK

extends PanelContainer
class_name OrderSheetPanel
## The order sheet on a packing table (expansion D-0714, "Modo Empresa"): who the box is for,
## what it has to hold with a done / pending mark per line, the stamps, tape and label, the time
## left and the pay.
##
## Draws what OrderSheet.build() returns and nothing else, so a client shows what the host
## sent. Every state has a mark besides its colour ("✓" done, "○" pending, "✗" wrong), so it
## reads without colour. A pure display: no focus, no input.

const DONE: String = "✓"
const PENDING: String = "○"
const WRONG: String = "✗"

var _column: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(self)
	add_theme_stylebox_override(&"panel", UiTheme.surface_style(16))
	custom_minimum_size = Vector2(300, 0)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 4)
	add_child(_column)
	refresh({})


## Redraws the sheet from `sheet` (OrderSheet.build()'s shape). An empty one shows "no order".
func refresh(sheet: Dictionary) -> void:
	if _column == null:
		return
	for child: Node in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	UiTheme.title(_column, tr("UI_ORDER_SHEET_TITLE"), 22)
	if sheet.is_empty():
		UiTheme.label(_column, tr("UI_ORDER_SHEET_EMPTY"), 15, UiTheme.MUTED).name = "Empty"
		return
	UiTheme.label(_column, tr("UI_ORDER_SHEET_FOR") % str(sheet.get("customer", "")), 16).name = "Customer"
	var address: Dictionary = sheet.get("address", {})
	if not address.is_empty():
		var street: String = tr(String(address["street_key"]))
		var line: String = tr("UI_ORDER_SHEET_ADDRESS") % [street, int(address["number"])]
		UiTheme.label(_column, line, 15, UiTheme.MUTED).name = "Address"
	for item: Dictionary in sheet.get("items", []):
		var done: bool = int(item["packed"]) == int(item["qty"]) and bool(item["ok"])
		var wrong: bool = int(item["packed"]) > int(item["qty"])
		var text: String = tr("UI_ORDER_SHEET_ITEM") % [item["name"], int(item["packed"]), int(item["qty"])]
		_mark(text, done, wrong).name = "Item_%s" % item["product"]
	for extra: Dictionary in sheet.get("extra", []):
		var text: String = tr("UI_ORDER_SHEET_EXTRA") % [extra["name"], int(extra["qty"])]
		if int(extra["qty"]) > 0 and not _has_item(sheet, extra["product"]):
			_mark(text, false, true).name = "Extra_%s" % extra["product"]
	for req: Dictionary in sheet.get("requirements", []):
		for seal: Dictionary in req["seals"]:
			var seal_name: String = _seal_name(seal["kind"])
			_mark(tr("UI_ORDER_SHEET_SEAL") % seal_name, bool(seal["done"]), false).name = "Seal_%s" % seal["kind"]
	_mark(tr("UI_ORDER_SHEET_TAPE"), bool(sheet.get("taped", false)), false).name = "Tape"
	_mark(tr("UI_ORDER_SHEET_LABEL"), bool(sheet.get("labeled", false)), false).name = "Label"
	var minutes: int = int(sheet.get("minutes_left", 0))
	var late: bool = bool(sheet.get("late", false))
	var time_text: String = tr("UI_ORDER_SHEET_LATE") % -minutes if late else tr("UI_ORDER_SHEET_LEFT") % minutes
	UiTheme.label(_column, time_text, 15, UiTheme.RED if late else UiTheme.INK).name = "Time"
	UiTheme.label(_column, tr("UI_ORDER_SHEET_PAY") % int(sheet.get("pay", 0)), 16, UiTheme.INK, true).name = "Pay"
	var ready: bool = bool(sheet.get("ready", false))
	var verdict: String = tr("UI_ORDER_SHEET_READY") if ready else tr("UI_ORDER_SHEET_NOT_READY")
	_mark(verdict, ready, false).name = "Verdict"


## A line with its mark in front and the colour that matches it.
func _mark(text: String, done: bool, wrong: bool) -> Label:
	var glyph: String = WRONG if wrong else (DONE if done else PENDING)
	var color: Color = UiTheme.RED if wrong else (UiTheme.MINT if done else UiTheme.INK)
	return UiTheme.label(_column, "%s  %s" % [glyph, text], 16, color)


static func _has_item(sheet: Dictionary, product: StringName) -> bool:
	for item: Dictionary in sheet.get("items", []):
		if item["product"] == product:
			return true
	return false


## Name of a stamp: the requirement it comes from has the same id (BoxSeals.KINDS).
static func _seal_name(kind: StringName) -> String:
	var key: String = String(OrderSheet.REQUIREMENT_KEYS.get(kind, ""))
	return TranslationServer.translate(key) if key != "" else String(kind)

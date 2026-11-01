extends Control
class_name StockPanel
## The stock list of the clipboard (expansion D-0612, "Modo Empresa").
##
## One row per product the shed holds or is short of (StockView.rows()): its name, the units on
## shelves and in reception, the total and, when something is hidden elsewhere (hands, boxes,
## other places), a second line with those. A product the pending orders are waiting on that the
## stock does not cover (StockAlert, D-0613) carries a mark besides its colour: "⚠ missing N",
## or "⟳ on the way" when a supplier order already closes the gap. Read only: it never changes
## the stock, so a client sees the same list from its mirror of the inventory.
##
## Data comes in through open() / refresh() as one dictionary, no autoload is read, so the panel
## runs headless in a test:
##   inventory: Inventory, shortages: Array (StockAlert.shortages(), optional),
##   products: Dictionary id -> ProductDefinition (optional, only for the names).
## The world calls refresh() on every units_moved.
##
## Gamepad first: rows are buttons in one focus column (so a long list scrolls with ui_down)
## ending in Close; with an empty list the focus starts on Close. ui_cancel / ui_pause close it.
##
## Embedded (set_embedded(), D-1902) it is the Stock sheet of the clipboard (ClipboardFrame): no dark
## backdrop, no title (the sheet's tab names it), no Close, no ui_cancel / ui_pause of its own and no open or
## close sound. Opened, it takes the focus as always.
##
## Each row tells what the product is (CompanyTooltips, D-1908): as its tooltip with the mouse and, with the
## focus on it (gamepad, keyboard), on the detail line under the list.

signal closed

## A sheet of the clipboard (see the class doc); set_embedded() changes it.
var embedded: bool = false

var _ctx: Dictionary = {}
var _rows: Dictionary = {}
var _order: Array[StringName] = []

var _rows_box: VBoxContainer
var _scroll: ScrollContainer
var _totals_label: Label
## What the focused row's product is (D-1908).
var _detail: Label
var _close_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	_build()
	hide()


## Shows the list for `ctx` (see the class doc) and takes focus.
func open(ctx: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh(ctx)
	show()
	if not embedded:
		UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)
	_focus_first.call_deferred()


func close() -> void:
	if not embedded:
		UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	hide()
	closed.emit()


## Turns the sheet mode on or off (see the class doc), rebuilding what is drawn when it changes.
func set_embedded(on: bool) -> void:
	if embedded == on:
		return
	embedded = on
	if _rows_box == null:
		return
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_rows.clear()
	_order.clear()
	_close_button = null
	_build()



## Redraws the list from `ctx`. The focus stays on the same product when it is still listed.
func refresh(ctx: Dictionary) -> void:
	_ctx = ctx
	if _rows_box == null:
		return
	var focused: StringName = _focused_product()
	for child: Node in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	_order.clear()
	var inventory: Inventory = ctx.get("inventory")
	var list: Array[Dictionary] = []
	if inventory != null:
		list = StockView.rows(inventory, ctx.get("shortages", []))
	if list.is_empty():
		UiTheme.label(_rows_box, tr("UI_STOCK_EMPTY"), 17, UiTheme.MUTED).name = "Empty"
	for row: Dictionary in list:
		var product: StringName = row["product"]
		var button: Button = UiTheme.button(_rows_box, "", false, Vector2(0, 52))
		button.name = "Row_%s" % product
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiTheme.register_font_size(button, 17)
		button.text = _row_line(row)
		button.tooltip_text = CompanyTooltips.product_text(_ctx.get("products", {}).get(product) as ProductDefinition)
		button.focus_entered.connect(_show_detail.bind(product))
		_rows[product] = button
		_order.append(product)
	_detail.text = ""
	var totals: Dictionary = StockView.totals(list)
	_totals_label.text = tr("UI_STOCK_TOTALS") % [totals["units"], totals["products"]]
	_link_focus()
	if focused != &"" and _rows.has(focused) and visible:
		(_rows[focused] as Button).grab_focus.call_deferred()


## Number of products listed.
func row_count() -> int:
	return _order.size()


## Products listed, in display order (sorted by id).
func products() -> Array[StringName]:
	return _order.duplicate()


## Text of the row of `product` ("" when it is not listed).
func row_text(product: StringName) -> String:
	var button: Button = _rows.get(product)
	return button.text if button != null else ""


func row_button(product: StringName) -> Button:
	return _rows.get(product)


func close_button() -> Button:
	return _close_button


## The detail line under the list: what the focused product is ("" with no row focused).
func detail_text() -> String:
	return _detail.text if _detail != null else ""


## The line under the list: total units and products.
func totals_text() -> String:
	return _totals_label.text if _totals_label != null else ""


func _build() -> void:
	if not embedded:
		var dim := ColorRect.new()
		dim.color = Color(UiTheme.BACKDROP, 0.86)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
	var column: VBoxContainer
	if embedded:
		# The clipboard's frame is the card: the sheet fills it and its list takes what is left (D-1902).
		column = VBoxContainer.new()
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(column)
	else:
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		column = UiTheme.panel(center, Vector2(700, 0), 22)
	column.add_theme_constant_override("separation", 6 if embedded else 8)
	if not embedded:
		UiTheme.title(column, tr("UI_STOCK_TITLE"), 34)
	UiTheme.label(column, tr("UI_STOCK_HINT"), 15, UiTheme.MUTED)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 100 if embedded else 300)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	column.add_child(_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(_rows_box)
	_detail = UiTheme.label(column, "", 15, UiTheme.INK)
	_detail.name = "Detail"
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_totals_label = UiTheme.label(column, "", 16, UiTheme.MUTED)
	_totals_label.name = "Totals"
	if not embedded:
		_close_button = UiTheme.button(column, tr("UI_STOCK_CLOSE"), true)
		_close_button.name = "Close"
		_close_button.pressed.connect(close)
	refresh(_ctx)


func _show_detail(product: StringName) -> void:
	var button: Button = _rows.get(product)
	if _detail != null and button != null:
		_detail.text = button.tooltip_text.replace("\n", " · ")


## Name and units on the first line, the units outside shelves and reception on a second one
## (only when there are any) and the low-stock mark on the last.
func _row_line(row: Dictionary) -> String:
	var defs: Dictionary = _ctx.get("products", {})
	var shown: String = OrderSheet.product_name(row["product"], defs)
	var line: String = tr("UI_STOCK_ROW") % [shown, row["shelves"], row["reception"], row["total"]]
	if int(row["hands"]) + int(row["boxes"]) + int(row["other"]) > 0:
		line += "\n" + tr("UI_STOCK_ROW_MORE") % [row["hands"], row["boxes"], row["other"]]
	var mark: String = _mark(row)
	if mark != "":
		line += "\n" + mark
	return line


## "⚠ missing N" / "⚠ missing N (M coming)" / "⟳ on the way (M)" / "" when not short.
func _mark(row: Dictionary) -> String:
	if not bool(row["short"]):
		return ""
	if bool(row["covered"]):
		return tr("UI_STOCK_COVERED") % row["incoming"]
	if int(row["incoming"]) > 0:
		return tr("UI_STOCK_SHORT_COMING") % [row["missing"], row["incoming"]]
	return tr("UI_STOCK_SHORT") % row["missing"]


## Focus column: rows top to bottom, then Close (none embedded). Horizontal moves stay put.
func _link_focus() -> void:
	var chain: Array[Control] = []
	for product: StringName in _order:
		chain.append(_rows[product])
	if _close_button != null:
		chain.append(_close_button)
	for i: int in chain.size():
		var node: Control = chain[i]
		node.focus_neighbor_top = node.get_path_to(chain[maxi(i - 1, 0)])
		node.focus_neighbor_bottom = node.get_path_to(chain[mini(i + 1, chain.size() - 1)])
		node.focus_neighbor_left = node.get_path_to(node)
		node.focus_neighbor_right = node.get_path_to(node)


func _focus_first() -> void:
	if _order.is_empty():
		if _close_button != null:
			_close_button.grab_focus()
		return
	(_rows[_order[0]] as Button).grab_focus()
	# follow_focus runs before the new rows are laid out and left a long list at its end (D-0612
	# capture): once they are, the list starts at the top with the first row.
	await get_tree().process_frame
	if is_instance_valid(_scroll) and visible:
		_scroll.scroll_vertical = 0


## The scrolling list (tests read its offset).
func list_scroll() -> ScrollContainer:
	return _scroll


func _focused_product() -> StringName:
	var holder: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for product: StringName in _rows:
		if _rows[product] == holder:
			return product
	return &""


func _unhandled_input(event: InputEvent) -> void:
	if visible and not embedded and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

extends Control
class_name CompanyShopPanel
## The company's shop screen (expansion D-0511.2, "Modo Empresa"), opened from the day's closing screen.
##
## One row per enabled item of data/shop/ (CompanyShop.items()): its name, its kind, its price and a
## Buy button. What the company can't buy now says why on the row (the WORLD_SHOP_* key CompanyShop.check()
## answers with, translated here) and its Buy is off. The panel never spends: Buy emits `buy_requested` and
## whoever hosts it asks the host (CompanyNet.request(CompanyShopNet.BUY), D-0518); the host's answer comes
## back through note_bought() (the shop_bought event) or reject() (request_rejected). A client sees the same
## screen and its Buy asks too: the host answers host_only, which reads as a text of its own here, and a
## line says upfront that only the host buys.
##
## Data comes in through open() / refresh() as one dictionary, no autoload is read, so the panel runs
## headless in a test:
##   company: a CompanyState-shaped Object (money, equipment, warehouse_stage...),
##   can_act: bool (false on a client: the panel says only the host buys, but Buy still asks),
##   items: Array of ShopItem (optional; the catalog, CompanyShop.items(), when missing).
##
## Gamepad first: the enabled Buy buttons and Close are one focus column; ui_accept buys, ui_cancel closes.
## Every row has a mark besides its colour: "✓" owned, "○" can buy, "✗" can't now.

## Buy was pressed on a row the company can buy now: ask the host for `item_id`.
signal buy_requested(item_id: StringName)
signal closed

const OWNED: String = "✓"
const FREE: String = "○"
const BLOCKED: String = "✗"
## Item kind -> translation key of its name on the row. Literal keys, so the translation test sees them used.
const KIND_KEYS: Dictionary = {
	&"vehicle": "UI_SHOP_KIND_VEHICLE",
	&"machine": "UI_SHOP_KIND_MACHINE",
	&"expansion": "UI_SHOP_KIND_EXPANSION",
}
## What CompanyNet.request_rejected says that the shop reads as a text of its own.
const HOST_ONLY: StringName = &"host_only"
const BAD_DATA: StringName = &"bad_data"
## Not a CompanyNet reason: the screen could not even ask (no connection to the host).
const NO_LINK: StringName = &"no_link"

var _ctx: Dictionary = {}
var _items: Array[ShopItem] = []
var _buttons: Dictionary = {}
## The item last asked for, so a refusal from the host can be explained with its numbers.
var _asked: StringName = &""

var _money_label: Label
var _host_label: Label
var _rows_box: VBoxContainer
var _scroll: ScrollContainer
var _status_label: Label
var _close_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	_build()
	hide()


## Shows the shop for `ctx` (see the class doc) and takes focus.
func open(ctx: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_status("")
	refresh(ctx)
	show()
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)
	_focus_first.call_deferred()


func close() -> void:
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	hide()
	closed.emit()


## Redraws the rows and the cash from `ctx` (the last one when empty). The focus stays on the same Buy
## when it can, else goes to the first one on.
func refresh(ctx: Dictionary = {}) -> void:
	if not ctx.is_empty():
		_ctx = ctx
	if _rows_box == null:
		return
	var focused: StringName = _focused_item()
	_items = _catalog()
	for child: Node in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_buttons.clear()
	if _items.is_empty():
		UiTheme.label(_rows_box, tr("UI_SHOP_EMPTY"), 17, UiTheme.MUTED).name = "Empty"
	for item: ShopItem in _items:
		_add_row(item)
	_money_label.text = tr("UI_SHOP_MONEY") % money(_money())
	_host_label.visible = not _acts()
	_link_focus()
	if focused != &"" and visible:
		_focus_item(focused)


## Buy on `item_id`: when the company can buy it now, asks for it (`buy_requested`); else says why not
## and asks nothing. Returns CompanyShop.check()'s dictionary.
func buy(item_id: StringName) -> Dictionary:
	var item: ShopItem = _find(item_id)
	var verdict: Dictionary = verdict_of(item)
	if not verdict["ok"]:
		_set_status(reason_text(String(verdict["key"]), _reason_args(verdict)), true)
		return verdict
	_asked = item_id
	_set_status("")
	buy_requested.emit(item_id)
	return verdict


## The host bought `item_id` (the shop_bought event, on every peer): the status line says so.
func note_bought(item_id: StringName) -> void:
	var item: ShopItem = _find(item_id)
	var shown: String = item_name(item) if item != null else String(item_id)
	_set_status("%s %s" % [OWNED, tr("UI_SHOP_BOUGHT") % shown])
	_asked = &""


## The host refused the last ask with `reason` (CompanyNet.request_rejected): host_only and bad_data have
## texts of their own here, a WORLD_SHOP_* key is the world's reason (with the numbers the company shows),
## NO_LINK is the screen's own.
func reject(reason: StringName) -> void:
	var text: String
	match reason:
		HOST_ONLY:
			text = tr("UI_SHOP_HOST_ONLY")
		BAD_DATA:
			text = tr("UI_SHOP_BAD_DATA")
		NO_LINK:
			text = tr("UI_SHOP_NO_LINK")
		_:
			text = reason_text(String(reason), _reason_args(verdict_of(_find(_asked)), reason))
	_asked = &""
	_set_status(text, true)


## CompanyShop.check() of `item` for the company of the context (NO_COMPANY without one).
func verdict_of(item: ShopItem) -> Dictionary:
	return CompanyShop.check(_ctx.get("company"), item)


## The shown name of an item (its translation key's text; an unknown key shows as itself).
static func item_name(item: ShopItem) -> String:
	return TranslationServer.translate(CompanyShop.name_key(item))


static func kind_name(kind: StringName) -> String:
	return TranslationServer.translate(String(KIND_KEYS.get(kind, "UI_SHOP_KIND_MACHINE")))


static func money(amount: int) -> String:
	return "$%d" % amount if amount >= 0 else "-$%d" % -amount


## Translated "key % args", tolerant of a key that takes fewer or more values than it was given.
static func reason_text(key: String, args: Array) -> String:
	var text: String = TranslationServer.translate(key)
	var needed: int = text.count("%")
	if needed == 0:
		return text
	var values: Array = args.duplicate()
	while values.size() < needed:
		values.append("")
	return text % values.slice(0, needed)


func buy_button(item_id: StringName) -> Button:
	return _buttons.get(item_id)


func close_button() -> Button:
	return _close_button


## The shop's items on screen, in order.
func item_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for item: ShopItem in _items:
		ids.append(item.id)
	return ids


## The line under the list: the last refusal, purchase or nothing.
func status_text() -> String:
	return _status_label.text if _status_label != null else ""


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = UiTheme.panel(center, Vector2(680, 0), 22)
	column.add_theme_constant_override("separation", 8)
	UiTheme.title(column, tr("UI_SHOP_TITLE"), 34)
	_money_label = UiTheme.label(column, "", 22, UiTheme.INK, true)
	_money_label.name = "Money"
	_host_label = UiTheme.label(column, "%s %s" % [BLOCKED, tr("UI_SHOP_HOST_ONLY")], 16, UiTheme.ORANGE)
	_host_label.name = "HostOnly"
	_host_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 280)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	column.add_child(_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 8)
	_scroll.add_child(_rows_box)
	_status_label = UiTheme.label(column, "", 16, UiTheme.ORANGE)
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_close_button = UiTheme.button(column, tr("UI_SHOP_CLOSE"), true)
	_close_button.name = "Close"
	_close_button.pressed.connect(close)


func _add_row(item: ShopItem) -> void:
	var verdict: Dictionary = verdict_of(item)
	var mark: String = FREE
	if not verdict["ok"]:
		mark = OWNED if verdict["key"] == CompanyShop.ALREADY_OWNED else BLOCKED
	var row := HBoxContainer.new()
	row.name = "Item_%s" % item.id
	row.add_theme_constant_override("separation", 12)
	_rows_box.add_child(row)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(340, 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	UiTheme.label(info, "%s  %s" % [mark, item_name(item)], 19, UiTheme.INK, true).name = "Name"
	UiTheme.label(info, tr("UI_SHOP_ROW") % [kind_name(item.kind), item.price], 15, UiTheme.MUTED).name = "Detail"
	if not verdict["ok"]:
		var why: Label = UiTheme.label(info, reason_text(String(verdict["key"]), _reason_args(verdict)), 15,
				UiTheme.ORANGE)
		why.name = "Reason"
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var button: Button = UiTheme.button(row, tr("UI_SHOP_BUY"), true, Vector2(150, 52))
	button.name = "Buy_%s" % item.id
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.disabled = not verdict["ok"]
	button.pressed.connect(buy.bind(item.id))
	_buttons[item.id] = button


## The values a reason's text takes: CompanyShop's args, the prices as money, a needed item by its name.
func _reason_args(verdict: Dictionary, key: StringName = &"") -> Array:
	var shown_key: StringName = StringName(verdict.get("key", "")) if key == &"" else key
	if verdict.is_empty() or StringName(verdict.get("key", "")) != shown_key:
		return []
	var args: Array = (verdict.get("args", []) as Array).duplicate()
	if shown_key == CompanyShop.CANNOT_AFFORD:
		return args.map(func(amount: Variant) -> String: return money(int(amount)))
	if shown_key == CompanyShop.NEEDS_ITEM and not args.is_empty():
		for item: ShopItem in _items:
			if item.grant_key == StringName(args[0]):
				return [item_name(item)]
	return args


func _catalog() -> Array[ShopItem]:
	var given: Variant = _ctx.get("items")
	if not given is Array:
		return CompanyShop.items()
	var found: Array[ShopItem] = []
	for raw: Variant in given:
		if raw is ShopItem and (raw as ShopItem).enabled:
			found.append(raw as ShopItem)
	return found


func _find(item_id: StringName) -> ShopItem:
	for item: ShopItem in _items:
		if item.id == item_id:
			return item
	return null


func _money() -> int:
	var company: Object = _ctx.get("company")
	return int(company.get("money")) if company != null else 0


func _acts() -> bool:
	return bool(_ctx.get("can_act", true))


func _set_status(text: String, refusal: bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = ("%s %s" % [BLOCKED, text]) if refusal and text != "" else text
	_status_label.add_theme_color_override(&"font_color", UiTheme.ORANGE if refusal else UiTheme.INK)


## Focus column: the Buy buttons that are on, top to bottom, then Close. Horizontal moves stay put.
func _link_focus() -> void:
	var chain: Array[Control] = []
	for item: ShopItem in _items:
		var button: Button = _buttons[item.id]
		if not button.disabled:
			chain.append(button)
		else:
			button.focus_mode = Control.FOCUS_NONE
	chain.append(_close_button)
	for i: int in chain.size():
		var node: Control = chain[i]
		node.focus_neighbor_top = node.get_path_to(chain[maxi(i - 1, 0)])
		node.focus_neighbor_bottom = node.get_path_to(chain[mini(i + 1, chain.size() - 1)])
		node.focus_neighbor_left = node.get_path_to(node)
		node.focus_neighbor_right = node.get_path_to(node)


func _focused_item() -> StringName:
	var holder: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for id: StringName in _buttons:
		if _buttons[id] == holder:
			return id
	return &""


func _focus_item(item_id: StringName) -> void:
	var button: Button = _buttons.get(item_id)
	if button != null and not button.disabled:
		button.grab_focus()
	else:
		_focus_first()


func _focus_first() -> void:
	for item: ShopItem in _items:
		var button: Button = _buttons.get(item.id)
		if button != null and not button.disabled:
			button.grab_focus()
			return
	_close_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

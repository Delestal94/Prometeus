extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_shop_panel.gd
##
## The company's shop screen (expansion D-0511.2, company_shop_panel.gd), driven by injected data only:
## - it lists every enabled item of the real catalog (CompanyShop.items(), data/shop/) in its order, each
##   row with its translated name, kind and price; what the company can't buy now has its Buy off and the
##   row says why in words (CompanyShop.check()'s WORLD_SHOP_* key translated, the prices as money, the item
##   it needs by name), with a mark besides the colour ("○" can buy, "✗" can't, "✓" owned);
## - the cash is the company's, and it follows a purchase and a change of wallet on refresh();
## - Buy asks, it doesn't spend: it emits buy_requested with the right id and changes nothing; a row that
##   can't be bought asks nothing and says the reason;
## - the gamepad drives it: the focus starts on the first Buy that is on, ui_accept asks for it, ui_down
##   and ui_up walk the Buy buttons that are on (the disabled ones are skipped) then Close, ui_cancel closes;
##   with nothing for sale the focus goes to Close;
## - a client (can_act false) sees the same shop and a line saying only the host buys; its Buy still asks
##   and the host's host_only reads as the panel's own text; bad_data, no connection and a world reason
##   (with its numbers) read too; note_bought() says what was bought, for the host and the clients;
## - both languages have every key the panel and the closing screen's Shop button use, and the screen
##   builds in English.

const KEYS: Array[String] = [
	"UI_FINANCE_SHOP", "UI_SHOP_TITLE", "UI_SHOP_MONEY", "UI_SHOP_ROW", "UI_SHOP_BUY", "UI_SHOP_CLOSE",
	"UI_SHOP_EMPTY", "UI_SHOP_KIND_VEHICLE", "UI_SHOP_KIND_MACHINE", "UI_SHOP_KIND_EXPANSION",
	"UI_SHOP_BOUGHT", "UI_SHOP_HOST_ONLY", "UI_SHOP_BAD_DATA", "UI_SHOP_NO_LINK",
]
const CSVS: Array[String] = ["res://translations/strings_ui.csv", "res://translations/strings_world.csv"]

var _failures: int = 0
var _asked: Array[StringName] = []
var _closed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	TranslationServer.set_locale("es")
	_test_keys()
	await _test_catalog_and_reasons(state)
	await _test_buy_and_cash(state)
	await _test_gamepad(state)
	await _test_client(state)
	await _test_empty_and_needs(state)
	await _test_english(state)
	state.reset()
	if _failures == 0:
		print("PASS: company shop panel lists the catalog, says why a row is off, and asks the host to buy")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _test_keys() -> void:
	var rows: Dictionary = {}
	for csv: String in CSVS:
		var file := FileAccess.open(csv, FileAccess.READ)
		while not file.eof_reached():
			var cols: PackedStringArray = file.get_csv_line()
			if cols.size() >= 3:
				rows[cols[0]] = cols
	for key: String in KEYS:
		var both: bool = rows.has(key) and rows[key][1] != "" and rows[key][2] != ""
		_expect(both, "translation row with both languages: " + key)


func _company(state: Node, money: int) -> Node:
	state.call(&"new_company", "Shop Co")
	state.set(&"money", money)
	return state


func _panel(ctx: Dictionary) -> CompanyShopPanel:
	var panel := CompanyShopPanel.new()
	root.add_child(panel)
	_asked.clear()
	_closed = 0
	panel.buy_requested.connect(func(id: StringName) -> void: _asked.append(id))
	panel.closed.connect(func() -> void: _closed += 1)
	panel.open(ctx)
	await process_frame
	await process_frame
	return panel


func _label(panel: Control, row: String, label: String) -> Label:
	var holder: Node = panel.find_child(row, true, false)
	return holder.find_child(label, true, false) as Label if holder != null else null


func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		root.push_input(event)
	await process_frame


func _focus_name() -> String:
	var holder: Control = root.gui_get_focus_owner()
	return String(holder.name) if holder != null else ""


func _finish(panel: Control) -> void:
	panel.queue_free()
	await process_frame


## The catalog on screen is the real one; the rows the company can't buy say why.
func _test_catalog_and_reasons(state: Node) -> void:
	_company(state, 100)
	var panel: CompanyShopPanel = await _panel({"company": state, "can_act": true})
	var expected: Array[StringName] = []
	for item: ShopItem in CompanyShop.items():
		expected.append(item.id)
	_expect(panel.visible and not expected.is_empty(), "the shop opens over a real catalog (%s)" % [expected])
	_expect(panel.item_ids() == expected, "it lists the enabled catalog items in order (got %s)" % [panel.item_ids()])
	_expect(panel.find_child("Item_vehicle_van", true, false) == null,
		"an item that is switched off (enabled = false) is not listed")
	_expect(panel.status_text() == "", "no status line before anything happened")
	var money_label: Label = panel.find_child("Money", true, false) as Label
	_expect(money_label != null and money_label.text.contains("$100"),
		"the cash is the company's (got %s)" % [money_label.text if money_label else "none"])
	for item: ShopItem in CompanyShop.items():
		var verdict: Dictionary = CompanyShop.check(state, item)
		var button: Button = panel.buy_button(item.id)
		_expect(button != null and button.disabled == (not bool(verdict["ok"])),
			"%s: Buy is off exactly when the company can't buy it (%s)" % [item.id, verdict["key"]])
		var name_label: Label = _label(panel, "Item_%s" % item.id, "Name")
		var name_text: String = CompanyShopPanel.item_name(item)
		_expect(name_label != null and name_label.text.contains(name_text) and name_text != CompanyShop.name_key(item),
			"%s: the row has the item's translated name" % item.id)
		var detail: Label = _label(panel, "Item_%s" % item.id, "Detail")
		_expect(detail != null and detail.text.contains("$%d" % item.price)
			and detail.text.contains(CompanyShopPanel.kind_name(item.kind)),
			"%s: the row has its price and kind (got %s)" % [item.id, detail.text if detail else "none"])
		var reason: Label = _label(panel, "Item_%s" % item.id, "Reason")
		_expect((reason != null) == (not bool(verdict["ok"])),
			"%s: a reason is on the row only when it's off" % item.id)
		_expect(name_label != null and name_label.text.begins_with(
			CompanyShopPanel.BLOCKED if not verdict["ok"] else CompanyShopPanel.FREE),
			"%s: the row has a mark besides the colour" % item.id)
	var broke: Label = _label(panel, "Item_upgrade_1", "Reason")
	_expect(broke != null and broke.text.contains("$450") and broke.text.contains("$100")
		and not broke.text.contains("WORLD_SHOP"),
		"short of money: the reason says the price and what there is (got %s)" % [broke.text if broke else "none"])
	var stage: Label = _label(panel, "Item_expansion_2", "Reason")
	_expect(stage != null and stage.text.contains("2") and not stage.text.contains("WORLD_SHOP"),
		"the second expansion before the first says the previous one is missing (got %s)"
		% [stage.text if stage else "none"])
	var asked_before: int = _asked.size()
	var refused: Dictionary = panel.buy(&"upgrade_1")
	_expect(not bool(refused["ok"]) and _asked.size() == asked_before,
		"Buy on a row that can't be bought asks nothing")
	_expect(panel.status_text().contains("$450"), "...and the status line says why (got %s)" % panel.status_text())
	await _finish(panel)


## Buy emits the request with the item's id and spends nothing; a refresh follows the company's cash.
func _test_buy_and_cash(state: Node) -> void:
	_company(state, 1000)
	var panel: CompanyShopPanel = await _panel({"company": state, "can_act": true})
	var accepted: Dictionary = panel.buy(&"upgrade_1")
	_expect(bool(accepted["ok"]) and _asked == [&"upgrade_1"], "Buy asks for the item's id (got %s)" % [_asked])
	_expect(int(state.get(&"money")) == 1000 and not (state.get(&"equipment") as Array).has(&"upgrade_1"),
		"...and the panel spends and grants nothing: only the host does, through CompanyNet")
	panel.buy_button(&"label_reader").pressed.emit()
	_expect(_asked == [&"upgrade_1", &"label_reader"],
		"pressing a Buy button asks for its row's item (got %s)" % [_asked])
	# What the host's event does to the company, on every peer; the panel follows it.
	var item: ShopItem = CompanyShop.find(&"upgrade_1")
	_expect(bool(CompanyShop.buy(state, item)["ok"]), "the company buys (the host's event does it)")
	panel.note_bought(&"upgrade_1")
	panel.refresh({"company": state, "can_act": true})
	await process_frame
	var money_label: Label = panel.find_child("Money", true, false) as Label
	_expect(money_label.text.contains("$550"), "the cash follows the purchase (got %s)" % money_label.text)
	_expect(panel.buy_button(&"upgrade_1").disabled, "the owned item's Buy is off")
	var owned: Label = _label(panel, "Item_upgrade_1", "Reason")
	_expect(owned != null and owned.text == TranslationServer.translate("WORLD_SHOP_ALREADY_OWNED"),
		"...and its row says it's already owned")
	var owned_name: Label = _label(panel, "Item_upgrade_1", "Name")
	_expect(owned_name.text.begins_with(CompanyShopPanel.OWNED), "...with the owned mark")
	_expect(panel.status_text().contains(CompanyShopPanel.item_name(item)),
		"the status line says what was bought (got %s)" % panel.status_text())
	await _finish(panel)


## Mando: focus on the first Buy that is on, up and down skip the off ones, accept asks, cancel closes.
func _test_gamepad(state: Node) -> void:
	_company(state, 1000)
	var panel: CompanyShopPanel = await _panel({"company": state, "can_act": true})
	var on: Array[StringName] = []
	for item: ShopItem in CompanyShop.items():
		if bool(CompanyShop.check(state, item)["ok"]):
			on.append(item.id)
	_expect(on.size() >= 2, "with 1000 there are at least two items to buy (%s)" % [on])
	_expect(_focus_name() == "Buy_%s" % on[0], "the focus starts on the first Buy that is on (got %s)" % _focus_name())
	await _press(&"ui_accept")
	_expect(_asked == [on[0]], "ui_accept asks for the focused item (got %s)" % [_asked])
	for i: int in range(1, on.size()):
		await _press(&"ui_down")
		_expect(_focus_name() == "Buy_%s" % on[i],
			"ui_down skips the rows that are off (got %s, wanted Buy_%s)" % [_focus_name(), on[i]])
	await _press(&"ui_down")
	_expect(_focus_name() == "Close", "ui_down reaches Close (got %s)" % _focus_name())
	await _press(&"ui_down")
	_expect(_focus_name() == "Close", "...and stops there (got %s)" % _focus_name())
	await _press(&"ui_up")
	_expect(_focus_name() == "Buy_%s" % on.back(), "ui_up walks back (got %s)" % _focus_name())
	await _press(&"ui_left")
	await _press(&"ui_right")
	_expect(_focus_name() == "Buy_%s" % on.back(), "left and right keep the focus where it is")
	_expect(_every_neighbour_lives(panel), "every focus neighbour points at a live node")
	panel.refresh()
	await process_frame
	_expect(_focus_name() == "Buy_%s" % on.back(), "a refresh keeps the focus on the same Buy (got %s)" % _focus_name())
	await _press(&"ui_cancel")
	_expect(not panel.visible and _closed == 1, "ui_cancel closes the shop (closed %d)" % _closed)
	await _finish(panel)


func _every_neighbour_lives(panel: CompanyShopPanel) -> bool:
	for button: Node in panel.find_children("*", "Button", true, false):
		var control: Control = button as Control
		if control.focus_mode == Control.FOCUS_NONE:
			continue
		for path: NodePath in [control.focus_neighbor_top, control.focus_neighbor_bottom,
				control.focus_neighbor_left, control.focus_neighbor_right]:
			if control.get_node_or_null(path) == null:
				return false
	return true


## A client: the same shop, a line that says only the host buys, Buy still asks, host_only reads.
func _test_client(state: Node) -> void:
	_company(state, 1000)
	var panel: CompanyShopPanel = await _panel({"company": state, "can_act": false})
	var host_line: Label = panel.find_child("HostOnly", true, false) as Label
	_expect(host_line != null and host_line.visible
		and host_line.text.contains(TranslationServer.translate("UI_SHOP_HOST_ONLY")),
		"a client sees that only the host buys, before pressing anything")
	_expect(not panel.buy_button(&"upgrade_1").disabled, "...and Buy still asks (the host answers)")
	panel.buy(&"upgrade_1")
	_expect(_asked == [&"upgrade_1"], "a client's Buy asks for the item (got %s)" % [_asked])
	panel.reject(CompanyShopPanel.HOST_ONLY)
	_expect(panel.status_text().contains(TranslationServer.translate("UI_SHOP_HOST_ONLY"))
		and panel.status_text() != TranslationServer.translate("UI_SHOP_HOST_ONLY"),
		"host_only reads as the panel's own text, marked (got %s)" % panel.status_text())
	_expect(int(state.get(&"money")) == 1000, "...and nothing was spent")
	panel.reject(CompanyShopPanel.BAD_DATA)
	_expect(panel.status_text().contains(TranslationServer.translate("UI_SHOP_BAD_DATA")), "bad_data reads")
	panel.reject(CompanyShopPanel.NO_LINK)
	_expect(panel.status_text().contains(TranslationServer.translate("UI_SHOP_NO_LINK")), "no connection reads")
	# The client asked with 1000 and the host's cash had gone down to 200 by then.
	panel.buy(&"upgrade_1")
	state.set(&"money", 200)
	panel.reject(CompanyShop.CANNOT_AFFORD)
	_expect(panel.status_text().contains("$200") and not panel.status_text().contains("WORLD_SHOP"),
		"a world reason from the host reads with the numbers (got %s)" % panel.status_text())
	await _finish(panel)
	var host_panel: CompanyShopPanel = await _panel({"company": state, "can_act": true})
	var host_hidden: Label = host_panel.find_child("HostOnly", true, false) as Label
	_expect(host_hidden != null and not host_hidden.visible, "the host doesn't see the only-the-host line")
	await _finish(host_panel)


## Nothing for sale focuses Close; an item that needs another names it; an injected catalog is respected.
func _test_empty_and_needs(state: Node) -> void:
	_company(state, 1000)
	var empty: CompanyShopPanel = await _panel({"company": state, "items": []})
	_expect(empty.find_child("Empty", true, false) != null and _focus_name() == "Close",
		"with nothing for sale the shop says so and focuses Close (focus %s)" % _focus_name())
	await _finish(empty)
	var upgrade: ShopItem = CompanyShop.find(&"upgrade_1")
	var sorter := ShopItem.new()
	sorter.id = &"test_sorter"
	sorter.display_key = "WORLD_SHOP_PACKER"
	sorter.kind = &"machine"
	sorter.price = 100
	sorter.grant_key = &"test_sorter"
	sorter.requires = &"upgrade_1"
	var hidden := ShopItem.new()
	hidden.id = &"test_hidden"
	hidden.display_key = "WORLD_SHOP_CONVEYOR"
	hidden.price = 100
	hidden.grant_key = &"test_hidden"
	hidden.enabled = false
	var panel: CompanyShopPanel = await _panel({"company": state, "items": [sorter, upgrade, hidden]})
	_expect(panel.item_ids() == [&"test_sorter", &"upgrade_1"],
		"an injected catalog is shown, without the switched off item")
	var reason: Label = _label(panel, "Item_test_sorter", "Reason")
	_expect(reason != null and reason.text.contains(CompanyShopPanel.item_name(upgrade)),
		"an item that needs another names it (got %s)" % [reason.text if reason else "none"])
	_expect(panel.buy_button(&"test_sorter").disabled and not panel.buy_button(&"upgrade_1").disabled,
		"...and its Buy is off until the other is owned")
	await _finish(panel)


func _test_english(state: Node) -> void:
	TranslationServer.set_locale("en")
	_company(state, 1000)
	var panel: CompanyShopPanel = await _panel({"company": state, "can_act": true})
	var name_label: Label = _label(panel, "Item_label_reader", "Name")
	_expect(name_label != null and name_label.text.contains("Label reader"),
		"in English the rows read in English (got %s)" % [name_label.text if name_label else "none"])
	var buy: Button = panel.buy_button(&"label_reader")
	_expect(buy.text == "Buy", "...and so does Buy (got %s)" % buy.text)
	await _finish(panel)
	TranslationServer.set_locale("es")

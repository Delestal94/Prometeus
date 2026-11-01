extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_tooltips.gd
##
## Tooltips of products and order requirements (expansion D-1908, scripts/ui/company_tooltips.gd):
## - a product says its size in cells and weight, fragile, cold, the trap its content carries (by its
##   translated name) and what it costs and earns; nothing it does not have (no trap line without a trap);
## - a requirement says its name, the stamp it asks for, the minimum packing quality, a shorter deadline
##   and the extra pay; "urgent" has no stamp line and says 50 % of the deadline;
## - every product in data/products/ and every requirement in data/order_requirements/ gives a text with
##   no key left untranslated and no placeholder left over, in Spanish and in English; null gives "";
## - the clipboard's Stock sheet (StockPanel) and Supplier sheet (SupplierOrderPanel) put the product's
##   text as the row's tooltip and, with the focus on the row (gamepad), on the detail line under the list;
## - the order sheet (OrderSheetPanel) puts the requirement's text on its stamp line, which takes the mouse.

var _failures: int = 0


class Wallet:
	extends RefCounted
	var money: int = 0

	func can_afford(amount: int) -> bool:
		return amount <= money


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	_test_product()
	_test_requirement()
	_test_all_data("es")
	TranslationServer.set_locale("en")
	_test_all_data("en")
	_expect(CompanyTooltips.product_text(_product(&"hen")).begins_with("Size:"), "English text in English")
	TranslationServer.set_locale("es")
	await _test_stock_panel()
	await _test_supplier_panel()
	await _test_order_sheet()
	if _failures == 0:
		print("PASS: products and requirements explain themselves as tooltips and on the focused row")
	quit(_failures)


func _product(id: StringName) -> ProductDefinition:
	return load("res://data/products/%s.tres" % id) as ProductDefinition


func _test_product() -> void:
	var hen: ProductDefinition = _product(&"hen")
	var lines: PackedStringArray = CompanyTooltips.product_lines(hen)
	_expect(lines[0] == tr("UI_TIP_PRODUCT_SIZE") % [2, 2, 1, "3"], "the hen is 2x2x1 cells, 3 kg (got %s)" % lines[0])
	_expect(lines.has(tr("UI_TIP_PRODUCT_TRAP") % CompanyTooltips.trap_name(&"noisy")), "the hen carries Ruidoso")
	_expect(not CompanyTooltips.trap_name(&"noisy").is_empty() and CompanyTooltips.trap_name(&"noisy") != "noisy",
		"the trap goes by its translated name")
	_expect(lines.has(tr("UI_TIP_PRODUCT_PRICES") % [hen.buy_price, hen.get_sell_price()]), "buy and sell prices")
	_expect(not lines.has(tr("UI_TIP_PRODUCT_FRAGILE")) and not lines.has(tr("UI_TIP_PRODUCT_COLD")),
		"the hen is neither fragile nor cold")
	_expect(CompanyTooltips.product_text(_product(&"milk_canister")).contains(tr("UI_TIP_PRODUCT_COLD")),
		"the milk goes cold")
	var plain := ProductDefinition.new()
	plain.fragile = true
	plain.weight_kg = 0.5
	var plain_lines: PackedStringArray = CompanyTooltips.product_lines(plain)
	_expect(plain_lines.has(tr("UI_TIP_PRODUCT_FRAGILE")), "a fragile product says so")
	_expect(plain_lines[0].contains("0.5"), "half a kilo keeps its decimal")
	for line: String in plain_lines:
		_expect(not line.begins_with(tr("UI_TIP_PRODUCT_TRAP").split(":")[0]), "no trap line without a trap")
	_expect(CompanyTooltips.product_text(null).is_empty(), "no product, no text")


func _test_requirement() -> void:
	var fragile: OrderRequirement = CompanyTooltips.load_requirement(&"fragile")
	var lines: PackedStringArray = CompanyTooltips.requirement_lines(fragile)
	_expect(lines.size() == 4, "fragile: name, stamp, quality, pay (got %s)" % [lines])
	_expect(lines[0] == tr("WORLD_REQ_FRAGILE"), "it starts with its name")
	_expect(lines.has(tr("UI_TIP_REQ_SEAL") % tr("WORLD_REQ_FRAGILE")), "it asks for the Frágil stamp")
	_expect(lines.has(tr("UI_TIP_REQ_QUALITY") % 70), "minimum quality 70")
	_expect(lines.has(tr("UI_TIP_REQ_BONUS") % 15), "pays +15 %")
	var urgent: PackedStringArray = CompanyTooltips.requirement_lines(CompanyTooltips.load_requirement(&"urgent"))
	_expect(urgent.has(tr("UI_TIP_REQ_WINDOW") % 50), "urgent halves the deadline")
	_expect(urgent.has(tr("UI_TIP_REQ_BONUS") % 30), "urgent pays +30 %")
	for line: String in urgent:
		_expect(not line.begins_with(tr("UI_TIP_REQ_SEAL").split(" ")[0]), "urgent asks for no stamp")
	_expect(CompanyTooltips.load_requirement(&"nothing") == null, "an unknown requirement is null")
	_expect(CompanyTooltips.requirement_text(null).is_empty(), "no requirement, no text")


func _test_all_data(locale: String) -> void:
	for file_name: String in CompanyCatalog.tres_files("res://data/products"):
		var product := load("res://data/products".path_join(file_name)) as ProductDefinition
		_check_text(CompanyTooltips.product_text(product), "%s product %s" % [locale, file_name])
	for file_name: String in CompanyCatalog.tres_files(CompanyTooltips.REQUIREMENTS_DIR):
		var req := load(CompanyTooltips.REQUIREMENTS_DIR.path_join(file_name)) as OrderRequirement
		_check_text(CompanyTooltips.requirement_text(req), "%s requirement %s" % [locale, file_name])


func _check_text(text: String, what: String) -> void:
	_expect(not text.is_empty(), "%s has a tooltip" % what)
	_expect(not text.contains("UI_TIP_") and not text.contains("WORLD_REQ_"), "%s has no raw key: %s" % [what, text])
	_expect(not text.contains("%d") and not text.contains("%s"), "%s has no placeholder left: %s" % [what, text])


func _test_stock_panel() -> void:
	var inventory := Inventory.new()
	inventory.receive(&"hen", 3, &"shelf:a")
	inventory.receive(&"milk_canister", 1, &"shelf:b")
	var defs: Dictionary = {&"hen": _product(&"hen"), &"milk_canister": _product(&"milk_canister")}
	var panel := StockPanel.new()
	root.add_child(panel)
	panel.open({"inventory": inventory, "products": defs})
	await process_frame
	await process_frame
	var hen: Button = panel.row_button(&"hen")
	var hen_tip: String = CompanyTooltips.product_text(defs[&"hen"])
	_expect(hen != null and hen.tooltip_text == hen_tip, "the hen's row has its tooltip")
	_expect(hen != null and hen.has_focus(), "the first row has the focus")
	_expect(panel.detail_text() == CompanyTooltips.product_text(defs[&"hen"]).replace("\n", " · "),
		"the focused row's product is on the detail line (got '%s')" % panel.detail_text())
	panel.row_button(&"milk_canister").grab_focus()
	_expect(panel.detail_text().contains(tr("UI_TIP_PRODUCT_COLD")), "the detail line follows the focus")
	panel.refresh({"inventory": inventory, "products": defs})
	_expect(panel.row_button(&"hen").tooltip_text != "", "a refresh keeps the tooltips")
	panel.queue_free()
	await process_frame


func _test_supplier_panel() -> void:
	var seller := SupplierDefinition.new()
	seller.id = &"s"
	seller.products = [&"hen"]
	var cart := SupplierOrderCart.new()
	cart.supplier = seller
	cart.products = {&"hen": _product(&"hen")}
	var wallet := Wallet.new()
	wallet.money = 1000
	var panel := SupplierOrderPanel.new()
	root.add_child(panel)
	panel.open({"cart": cart, "wallet": wallet, "schedule": SupplierSchedule.new(), "day": 3, "can_act": true})
	await process_frame
	await process_frame
	var tip: String = CompanyTooltips.product_text(cart.products[&"hen"])
	var more: Button = panel.more_button(&"hen")
	_expect(more != null and more.tooltip_text == tip and panel.less_button(&"hen").tooltip_text == tip,
		"plus and minus carry the product's tooltip")
	var name_label := more.get_parent().get_node_or_null(^"Name") as Label if more != null else null
	_expect(name_label != null and name_label.tooltip_text == tip
			and name_label.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"the name shows it with the mouse")
	var detail := panel.find_child("Detail", true, false) as Label
	_expect(more != null and more.has_focus() and detail != null and detail.text == tip.replace("\n", " · "),
		"the focused row's product is on the detail line")
	panel.queue_free()
	await process_frame


func _test_order_sheet() -> void:
	var panel := OrderSheetPanel.new()
	root.add_child(panel)
	await process_frame
	panel.refresh({
		"order": &"o1", "customer": "Ana", "items": [], "extra": [],
		"requirements": [
			{"id": &"fragile", "key": "WORLD_REQ_FRAGILE", "seals": [{"kind": &"fragile", "done": false}]},
		],
		"taped": false, "labeled": false, "minutes_left": 30, "late": false, "pay": 100, "ready": false,
	})
	var seal := panel.find_child("Seal_fragile", true, false) as Label
	var tip: String = CompanyTooltips.requirement_text(CompanyTooltips.load_requirement(&"fragile"))
	_expect(seal != null and seal.tooltip_text == tip,
		"the stamp line explains its requirement")
	_expect(seal != null and seal.mouse_filter == Control.MOUSE_FILTER_PASS, "and takes the mouse to show it")
	panel.queue_free()
	await process_frame


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)

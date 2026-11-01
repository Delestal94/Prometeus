extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_slots_menu.gd
##
## The main menu's Modo Empresa page (D-1904, scripts/ui/company_slots_page.gd), as a flow:
## - the list shows one row per saved company (CompanySave.list_slots()) with its name, day, money
##   and a chip per modifier on (D-1919), the full names in the "Jugar" tooltip; a save from a newer
##   build is listed with "Jugar" and "Opciones" disabled; an empty folder says so;
## - "Jugar" on a row asks for that slot, solo or, with "Abrir sala para amigos", hosting, and leaves
##   CompanyState off so the company world loads the slot;
## - "Nueva empresa" -> name and modifiers (off by default) -> "Crear y jugar" asks for a free slot
##   (CompanySave.new_slot_id()) with CompanyState on, named, with those modifiers; an empty name is
##   "Mi empresa";
## - "Opciones" on a row shows that slot's modifiers and "Guardar" writes them to its file
##   (CompanySave.write_options(): only company.options changes); it refuses a newer build's file
##   and a missing slot;
## - "Borrar" asks first ("¿Seguro? Borrar") and removes the slot on the second press;
## - Esc / "Volver" on a form goes back to the list; on the list it is the menu's;
## - in the main menu, "Modo Empresa" on the Play page opens the page (title from the table), Esc
##   goes back to Play, and the card with five companies still fits a 1280x720 screen.

const DIR: String = "user://test_company_slots_menu"
const MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const PAGE_COMPANY: int = 4
const PAGE_PLAY: int = 1

var _failures: int = 0
var _requests: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	_expect(state != null, "CompanyState autoload exists")
	if state == null:
		quit(1)
		return
	_clean()
	_test_empty_folder(state)
	_seed(state)
	var page := CompanySlotsPage.new()
	page.state = state
	page.save_dir = DIR
	page.play_requested.connect(func(slot: String, host: bool) -> void: _requests.append([slot, host]))
	root.add_child(page)
	await process_frame
	_test_list(page)
	_test_play(page, state)
	_test_new_company(page, state)
	_test_options(page)
	_test_delete(page)
	page.queue_free()
	await _test_main_menu(state)
	state.reset()
	_clean()
	if _failures == 0:
		print("PASS: the company page lists, plays, creates, edits and deletes saved companies")
	quit(_failures)


func _test_empty_folder(state: Node) -> void:
	var page := CompanySlotsPage.new()
	page.state = state
	page.save_dir = DIR
	root.add_child(page)
	var empty := page.find_child("ViewList", true, false).find_child("Empty", true, false) as Label
	_expect(page.slots().is_empty(), "an empty folder lists nothing")
	_expect(empty != null and empty.visible and empty.text == tr("UI_COMPANY_SLOTS_EMPTY"),
		"an empty folder says there are no saved companies")
	page.free()


## Alfa (day 3, $1250, assisted packing), Beta (day 7, $90) and a save from a newer build.
func _seed(state: Node) -> void:
	state.new_company("Alfa")
	state.day = 3
	state.money = 1250
	state.options = {"assisted_packing": true, "calm_days": false}
	_expect(CompanySave.save(state, "company", DIR), "Alfa saved")
	state.new_company("Beta")
	state.day = 7
	state.money = 90
	state.options = {"assisted_packing": false, "calm_days": false}
	_expect(CompanySave.save(state, "company_2", DIR), "Beta saved")
	var future := FileAccess.open(CompanySave.path_for("future", DIR), FileAccess.WRITE)
	future.store_string(JSON.stringify({"version": CompanySave.VERSION + 1, "saved_at": 5,
		"company": {"company_name": "Del futuro", "day": 40}}))
	future.close()
	state.reset()


func _test_list(page: CompanySlotsPage) -> void:
	_expect(page.view == CompanySlotsPage.View.LIST, "the page opens on the list")
	_expect(page.slots().size() == 3, "three companies listed (got %d)" % page.slots().size())
	var alfa: Button = page.play_button("company")
	_expect(alfa != null and alfa.text.contains("Alfa"), "Alfa has a row with its name")
	_expect(alfa != null and alfa.text.contains(tr("UI_COMPANY_SLOTS_DETAILS").split(" ")[0])
			and alfa.text.contains("3") and alfa.text.contains("1250"), "Alfa's row says its day and money")
	_expect(alfa != null and alfa.get_parent().find_child("Chip_assisted_packing", true, false) != null,
		"Alfa shows a chip for Armado asistido")
	_expect(alfa != null and alfa.get_parent().find_child("Chip_calm_days", true, false) == null,
		"Alfa shows no chip for a modifier that is off")
	_expect(alfa != null and alfa.tooltip_text == tr("UI_COMPANY_OPT_ASSISTED_PACKING"),
		"Alfa's button names its modifiers in full")
	var beta: Button = page.play_button("company_2")
	_expect(beta != null and beta.get_parent().find_child("Chip_*", true, false) == null, "Beta has no chips")
	var future: Button = page.play_button("future")
	_expect(future != null and future.disabled and future.text.contains(tr("UI_COMPANY_SLOTS_TOO_NEW")),
		"a newer build's save is listed, disabled")
	var future_options := future.get_parent().find_child("Options", true, false) as Button if future else null
	_expect(future_options != null and future_options.disabled, "its Opciones is disabled too")
	var empty := page.find_child("ViewList", true, false).find_child("Empty", true, false) as Label
	_expect(empty != null and not empty.visible, "the empty-folder text hides with companies listed")
	page.open()
	var new_button := page.find_child("NewCompany", true, false) as Button
	_expect(new_button != null and new_button.has_focus(), "the list focuses Nueva empresa (gamepad)")
	for button: Button in _buttons(page):
		_expect(UiTheme.UI_SOUNDS.is_button_bound(button), "'%s' plays the UI sounds" % button.name)


func _test_play(page: CompanySlotsPage, state: Node) -> void:
	state.new_company("Leftover")
	_requests.clear()
	page.play_button("company").pressed.emit()
	_expect(_requests == [["company", false]], "Jugar on Alfa asks for its slot, solo (got %s)" % [_requests])
	_expect(not state.is_active(), "the state is off, so the world loads the slot")
	(page.find_child("HostToggle", true, false) as CheckBox).button_pressed = true
	_requests.clear()
	page.play_button("company_2").pressed.emit()
	_expect(_requests == [["company_2", true]], "with Abrir sala the slot is played hosting a room")
	(page.find_child("HostToggle", true, false) as CheckBox).button_pressed = false


func _test_new_company(page: CompanySlotsPage, state: Node) -> void:
	(page.find_child("NewCompany", true, false) as Button).pressed.emit()
	_expect(page.view == CompanySlotsPage.View.NEW, "Nueva empresa opens the form")
	var field := page.find_child("NameField", true, false) as LineEdit
	_expect(field != null and field.has_focus(), "the form focuses the name")
	var form: Node = page.find_child("ViewNew", true, false)
	var assisted := form.find_child("Option_assisted_packing", true, false) as CheckBox
	var calm := form.find_child("Option_calm_days", true, false) as CheckBox
	_expect(assisted != null and calm != null and not assisted.button_pressed and not calm.button_pressed,
		"both modifiers start off")
	_expect(assisted != null and assisted.text == tr("UI_COMPANY_OPT_ASSISTED_PACKING"), "Armado asistido by key")
	field.text = "  Gamma  "
	calm.button_pressed = true
	_requests.clear()
	(page.find_child("Create", true, false) as Button).pressed.emit()
	_expect(_requests == [["company_3", false]], "Crear asks for a free slot (got %s)" % [_requests])
	_expect(state.is_active() and state.company_name == "Gamma", "the new company is on, with its name trimmed")
	_expect(state.options == {"assisted_packing": false, "calm_days": true}, "with the chosen modifiers")
	_expect(not CompanySave.exists("company_3", DIR), "nothing is written before the world saves day 1")
	# Back, and again with no name.
	_expect(page.back() and page.view == CompanySlotsPage.View.LIST, "Esc on the form goes back to the list")
	_expect(not page.back(), "Esc on the list is the menu's")
	(page.find_child("NewCompany", true, false) as Button).pressed.emit()
	_expect(field.text.is_empty() and not calm.button_pressed, "the form opens clean again")
	page.create_company()
	_expect(state.company_name == tr("UI_COMPANY_SLOTS_DEFAULT_NAME"), "an empty name is Mi empresa")
	page.back()
	state.reset()


func _test_options(page: CompanySlotsPage) -> void:
	var options := page.play_button("company_2").get_parent().find_child("Options", true, false) as Button
	options.pressed.emit()
	_expect(page.view == CompanySlotsPage.View.OPTIONS, "Opciones on Beta opens its modifiers")
	var view: Node = page.find_child("ViewOptions", true, false)
	var assisted := view.find_child("Option_assisted_packing", true, false) as CheckBox
	_expect(assisted != null and not assisted.button_pressed and assisted.has_focus(),
		"they show the file's values, the first one focused")
	var title := view.find_child("OptionsTitle", true, false) as Label
	_expect(title != null and title.text == tr("UI_COMPANY_SLOTS_OPTIONS_TITLE") % "Beta", "titled with its name")
	var before: Dictionary = _company_of("company_2")
	assisted.button_pressed = true
	(view.find_child("Save", true, false) as Button).pressed.emit()
	_expect(page.view == CompanySlotsPage.View.LIST, "Guardar goes back to the list")
	var after: Dictionary = _company_of("company_2")
	_expect(after.get("options") == {"assisted_packing": true, "calm_days": false}, "the file has the new options")
	after.erase("options")
	before.erase("options")
	_expect(after == before, "nothing else in the company changed")
	_expect(page.play_button("company_2").get_parent().find_child("Chip_assisted_packing", true, false) != null,
		"the row shows the new chip")
	_expect(not CompanySave.write_options({"calm_days": true}, "future", DIR), "a newer build's save is not written")
	_expect(not CompanySave.write_options({"calm_days": true}, "nobody", DIR), "a missing slot is not created")
	_expect(not CompanySave.exists("nobody", DIR), "still missing")


func _test_delete(page: CompanySlotsPage) -> void:
	var delete := page.play_button("company_2").get_parent().find_child("Delete", true, false) as Button
	delete.pressed.emit()
	_expect(CompanySave.exists("company_2", DIR), "the first Borrar deletes nothing")
	var armed := page.play_button("company_2").get_parent().find_child("Delete", true, false) as Button
	_expect(armed.text == tr("UI_COMPANY_SLOTS_DELETE_CONFIRM") and armed.has_focus(), "it asks, focused")
	armed.pressed.emit()
	_expect(not CompanySave.exists("company_2", DIR), "the second removes the slot")
	_expect(page.play_button("company_2") == null and page.slots().size() == 2, "and its row")
	_expect((page.find_child("NewCompany", true, false) as Button).has_focus(), "focus goes to Nueva empresa")


func _test_main_menu(state: Node) -> void:
	for i: int in 3:
		state.new_company("Extra %d" % i)
		CompanySave.save(state, "extra_%d" % i, DIR)
	state.reset()
	root.size = Vector2i(1280, 720)
	var network: Node = root.get_node(^"/root/NetworkManager")
	var menu: Control = load(MENU_SCENE).instantiate()
	root.add_child(menu)
	await process_frame
	network.disconnect(&"session_ready", Callable(menu, "_on_session_ready"))
	var slots := menu.find_child("CompanySlots", true, false) as CompanySlotsPage
	_expect(slots != null, "the menu has the company page")
	if slots == null:
		menu.queue_free()
		return
	slots.save_dir = DIR
	_expect(slots.play_requested.is_connected(Callable(menu, "_on_company_play")), "a slot played goes to the menu")
	var pages: Dictionary = menu.get(&"_pages")
	var company_button: Button = null
	for button: Button in _buttons(pages[PAGE_PLAY]):
		if button.text == tr("UI_MENU_COMPANY"):
			company_button = button
	menu.call(&"_show_page", PAGE_PLAY)
	_expect(company_button != null, "the Play page has Modo Empresa")
	company_button.pressed.emit()
	await process_frame
	_expect((pages[PAGE_COMPANY] as Control).visible and not (pages[PAGE_PLAY] as Control).visible,
		"Modo Empresa opens the company page")
	_expect((menu.get(&"_page_title") as Label).text == tr("UI_MENU_PAGE_COMPANY"), "titled by key")
	_expect(slots.slots().size() == 5 and slots.play_button("extra_2") != null, "listing its five companies")
	await process_frame
	var card: Control = menu.get(&"_card")
	var bottom: float = card.get_global_rect().end.y
	_expect(bottom <= 720.0, "the card with five companies fits 720p (bottom at %.0f)" % bottom)
	var back := InputEventAction.new()
	back.action = &"ui_cancel"
	back.pressed = true
	(slots.find_child("NewCompany", true, false) as Button).pressed.emit()
	menu.call(&"_unhandled_input", back)
	_expect(slots.view == CompanySlotsPage.View.LIST and (pages[PAGE_COMPANY] as Control).visible,
		"Esc on the new-company form goes back to the list")
	menu.call(&"_unhandled_input", back)
	_expect((pages[PAGE_PLAY] as Control).visible, "Esc on the list goes back to Play")
	menu.queue_free()
	await process_frame


func _company_of(slot: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CompanySave.path_for(slot, DIR)))
	return (raw as Dictionary).get("company", {}) if raw is Dictionary else {}


func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child: Node in node.get_children():
		if child is Button:
			result.append(child as Button)
		result.append_array(_buttons(child))
	return result


func _clean() -> void:
	var folder: DirAccess = DirAccess.open(DIR)
	if folder == null:
		return
	for file_name: String in folder.get_files():
		folder.remove(file_name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

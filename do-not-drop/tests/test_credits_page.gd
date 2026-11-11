extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_credits_page.gd
##
## The credits (expansion D-1940):
## - Garaje has a "Créditos" button that opens the credits page, titled by key; "Volver" (its focus) and Esc go back
##   to Garaje;
## - the page lists every section of CreditsPage.SECTIONS with its lines, every one a key with Spanish and English;
## - up and down scroll it (the lines take no focus);
## - what it says is what the repository has: each font it names ships with its OFL text, GodotSteam is in addons,
##   and the music's licence file says it was composed in code;
## - the card fits 720p.

const MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const PAGE_GARAGE: int = 3
const PAGE_CREDITS: int = 5

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	_test_keys()
	_test_facts()
	await _test_menu()
	if _failures == 0:
		print("PASS: Garaje opens the credits, every line is translated and true to the repository")
	quit(_failures)


func _test_keys() -> void:
	var keys: Array[String] = ["UI_MENU_CREDITS", "UI_MENU_PAGE_CREDITS"]
	for section: Array in CreditsPage.SECTIONS:
		keys.append(String(section[0]))
		for key: String in section[1]:
			keys.append(key)
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in keys:
			_expect(TranslationServer.translate(key) != key, "%s has %s" % [locale, key])
	TranslationServer.set_locale("es")


func _test_facts() -> void:
	for font: String in ["LilitaOne", "Nunito", "PTSerif"]:
		_expect(FileAccess.file_exists("res://assets/fonts/%s-OFL.txt" % font), "%s ships with its OFL" % font)
	_expect(DirAccess.dir_exists_absolute("res://addons/godotsteam"), "GodotSteam is in addons")
	var music: String = FileAccess.get_file_as_string("res://assets/audio/music/LICENCIA.md")
	_expect(music.contains("Compuesta por código") and music.contains("sin samples"), "the music was composed in code")


func _test_menu() -> void:
	root.size = Vector2i(1280, 720)
	var network: Node = root.get_node(^"/root/NetworkManager")
	var menu: Control = load(MENU_SCENE).instantiate()
	root.add_child(menu)
	await process_frame
	if network.is_connected(&"session_ready", Callable(menu, "_on_session_ready")):
		network.disconnect(&"session_ready", Callable(menu, "_on_session_ready"))
	var pages: Dictionary = menu.get(&"_pages")
	menu.call(&"_show_page", PAGE_GARAGE)
	var button := (pages[PAGE_GARAGE] as Node).find_child("Credits", true, false) as Button
	_expect(button != null and button.text == "Créditos", "Garaje has Créditos")
	if button == null:
		menu.queue_free()
		return
	button.pressed.emit()
	await process_frame
	_expect((pages[PAGE_CREDITS] as Control).visible and (menu.get(&"_page_title") as Label).text == "Créditos",
		"it opens the credits page, titled by key")
	var credits: CreditsPage = null
	for node: Node in (pages[PAGE_CREDITS] as Node).get_children():
		if node is CreditsPage:
			credits = node
	_expect(credits != null, "the page holds CreditsPage")
	if credits != null:
		for section: Array in CreditsPage.SECTIONS:
			for key: String in section[1]:
				var line := credits.find_child(key, true, false) as Label
				_expect(line != null and line.text == TranslationServer.translate(key), "%s is listed" % key)
		var scroll := credits.get_node(^"Scroll") as ScrollContainer
		await process_frame
		var before: int = scroll.scroll_vertical
		var down := InputEventAction.new()
		down.action = &"ui_down"
		down.pressed = true
		credits.call(&"_input", down)
		_expect(scroll.get_v_scroll_bar().max_value <= scroll.size.y or scroll.scroll_vertical > before,
			"down scrolls the lines")
	var focus: Control = (menu.get(&"_page_focus") as Dictionary)[PAGE_CREDITS]
	_expect(focus is Button and (focus as Button).text == tr("UI_BACK"), "its focus is Volver")
	var card: Control = menu.get(&"_card")
	_expect(card.get_global_rect().end.y <= 720.0, "the card fits 720p (%.0f)" % card.get_global_rect().end.y)
	var back := InputEventAction.new()
	back.action = &"ui_cancel"
	back.pressed = true
	menu.call(&"_unhandled_input", back)
	_expect((pages[PAGE_GARAGE] as Control).visible, "Esc goes back to Garaje")
	menu.queue_free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_tr_coverage.gd
##
## Every new text goes through tr() (expansion D-1920, which takes D-0443 milestones, D-0649 delivery
## notes and D-0845 orders): the N-805 check of test_ui_translations caught Spanish literals, and the
## expansion's code is written in English, so this one looks for any literal drawn on screen.
## - No script under scripts/ or modules/ (their tests and scripts/tools/ aside) hands a literal with
##   words to a text: a UiTheme helper (label, title, tag, chip, button, check_box, floating_label,
##   line_edit, slider_row), `.text` / `.tooltip_text` / `.placeholder_text =` (also after an inline
##   "else"), add_item(), set_text(), add_tab() or set_tab_title(). A literal "has words" when it keeps two
##   letters in a row once its %d / %s are out; keys (UI_ / HUD_ / WORLD_) and SAME_IN_BOTH pass. The
##   lines written before this test are in LEGACY, one entry each, so a new one is never let through.
## - tr() / TranslationServer.translate() / tr_n() of a literal only ever take a key.
## - Every text key a data file names (display_key, translation_key and any *_name_key, *_text_key,
##   *_title_key or *_desc_key in data/**/*.tres) is in strings_ui.csv or strings_world.csv with both
##   languages: zones, shop items, placeables, employees, order requirements, traps.
## - The scan reaches the Company's files: core/company, gameplay/business (orders, delivery notes and,
##   once they exist, milestones), districts and fleet, and the company screens.
## - With the locale in English, the company screens (the menu's company page, the clipboard's stock and
##   supplier sheets, the order sheet and the order board) show no text that is the Spanish of a key
##   whose English differs.

const TABLES: Array[String] = ["res://translations/strings_ui.csv", "res://translations/strings_world.csv"]
const SCAN_DIRS: Array[String] = ["res://scripts", "res://modules"]
## Dev tools (renders, concept art): never in the game.
const SKIP_DIRS: Array[String] = ["res://scripts/tools"]
## Written the same in both languages.
const SAME_IN_BOTH: Array[String] = ["Endless", "ENDLESS", "●  ENDLESS", "km/h"]
## "path|literal" drawn as it is before D-1920. Fixing one takes it out of here.
const LEGACY: Array[String] = [
	"res://scripts/core/unlock_manager.gd|None",
	"res://scripts/ui/leaderboard_panel.gd|Entrega",
	"res://scripts/ui/leaderboard_panel.gd|%d pts",
]
## Files of the expansion the scan must reach (D-0649 delivery notes, D-0845 orders).
const MUST_SCAN: Array[String] = [
	"res://scripts/gameplay/business/delivery_note.gd",
	"res://scripts/gameplay/business/order_sheet.gd",
	"res://scripts/gameplay/business/order_board.gd",
	"res://scripts/gameplay/business/order_notice.gd",
	"res://scripts/ui/order_sheet_panel.gd",
	"res://scripts/ui/order_board_panel.gd",
	"res://scripts/ui/stock_panel.gd",
	"res://scripts/ui/supplier_order_panel.gd",
	"res://scripts/ui/clipboard_frame.gd",
	"res://scripts/ui/company_slots_page.gd",
	"res://scripts/ui/company_pause_menu.gd",
	"res://scripts/core/company/company_state.gd",
]
const DATA_DIR: String = "res://data"
const EMPTY_SAVES: String = "user://test_tr_coverage_saves"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var table: Dictionary = {}
	for path: String in TABLES:
		table.merge(_read_csv(path))
	_expect(table.size() > 1000, "both tables read (%d keys)" % table.size())
	_check_scripts()
	_check_data_keys(table)
	await _check_screens_in_english(table)
	if _failures == 0:
		print("PASS: every new text goes through tr(), and the company screens build in English")
	quit(_failures)


func _check_scripts() -> void:
	var drawn: Array[RegEx] = [
		RegEx.create_from_string(
			'UiTheme\\.(?:label|title|tag|chip|button|check_box|floating_label|line_edit|slider_row)'
			+ '\\(\\s*[^,()]+(?:\\([^()]*\\))?,\\s*"([^"\\n]*)"'),
		RegEx.create_from_string('\\.(?:text|tooltip_text|placeholder_text)\\s*=\\s*"([^"\\n]*)"'),
		RegEx.create_from_string('\\.(?:text|tooltip_text)\\s*=.*\\belse\\s+"([^"\\n]*)"'),
		RegEx.create_from_string('\\b(?:add_item|set_text|add_tab|set_tab_title)\\(\\s*"([^"\\n]*)"'),
	]
	var translated := RegEx.create_from_string('\\b(?:tr|translate|tr_n)\\(\\s*"([^"\\n]*)"')
	var scanned: Dictionary = {}
	var legacy_seen: Dictionary = {}
	for dir_path: String in SCAN_DIRS:
		for file_path: String in _scripts(dir_path):
			scanned[file_path] = true
			var line_number: int = 0
			for line: String in FileAccess.get_file_as_string(file_path).split("\n"):
				line_number += 1
				if line.strip_edges().begins_with("#"):
					continue
				for pattern: RegEx in drawn:
					for found: RegExMatch in pattern.search_all(line):
						var text: String = found.get_string(1)
						if not _has_words(text) or _is_key(text) or text in SAME_IN_BOTH:
							continue
						var entry: String = "%s|%s" % [file_path, text]
						if entry in LEGACY:
							legacy_seen[entry] = true
							continue
						_expect(false, "%s:%d draws \"%s\" without tr() (use a key)" % [file_path, line_number, text])
				for found: RegExMatch in translated.search_all(line):
					var asked: String = found.get_string(1)
					var entry: String = "%s|%s" % [file_path, asked]
					if entry in LEGACY:
						legacy_seen[entry] = true
						continue
					_expect(_is_key(asked), "%s:%d translates \"%s\", not a key" % [file_path, line_number, asked])
	_expect(scanned.size() > 300, "the scan reads the game's scripts (%d)" % scanned.size())
	for path: String in MUST_SCAN:
		_expect(scanned.has(path), "the scan reaches %s" % path)
	for entry: String in LEGACY:
		_expect(legacy_seen.has(entry), "LEGACY %s is still there (fixed? take it out of the list)" % entry)


func _check_data_keys(table: Dictionary) -> void:
	var field := RegEx.create_from_string(
		'^(display_key|translation_key|\\w+_(?:name|text|title|desc)_key)\\s*=\\s*"([^"]*)"')
	var checked: int = 0
	for path: String in _files(DATA_DIR, ".tres"):
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			var found: RegExMatch = field.search(line.strip_edges())
			if found == null or found.get_string(2).is_empty():
				continue
			var key: String = found.get_string(2)
			checked += 1
			_expect(_is_key(key), "%s: %s \"%s\" is a key" % [path, found.get_string(1), key])
			_expect(table.has(key), "%s: %s is in a translation table" % [path, key])
	_expect(checked >= 40, "data keys checked: zones, shop, placeables, requirements, traps (%d)" % checked)


func _check_screens_in_english(table: Dictionary) -> void:
	var spanish_only: Dictionary = {}
	for key: String in table:
		var es: String = table[key][0]
		if es != table[key][1] and not es.contains("%"):
			spanish_only[es] = key
	var previous: String = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var screens: Array[Control] = []
	var slots := CompanySlotsPage.new()
	slots.save_dir = EMPTY_SAVES
	screens.append(slots)
	var stock := StockPanel.new()
	screens.append(stock)
	var supplier := SupplierOrderPanel.new()
	screens.append(supplier)
	var sheet := OrderSheetPanel.new()
	screens.append(sheet)
	var board := OrderBoardPanel.new()
	screens.append(board)
	for screen: Control in screens:
		root.add_child(screen)
	await process_frame
	stock.open({})
	supplier.open({})
	sheet.refresh({
		"order": &"o1", "customer": "Ana", "items": [], "extra": [],
		"requirements": [{"id": &"cold", "key": "WORLD_REQ_COLD", "seals": [{"kind": &"cold", "done": true}]}],
		"taped": true, "labeled": false, "minutes_left": 12, "late": false, "pay": 80, "ready": false,
	})
	await process_frame
	var seen: int = 0
	for screen: Control in screens:
		for node: Node in screen.find_children("*", "", true, false):
			var texts: Array[String] = []
			if node is Label:
				texts.append((node as Label).text)
			elif node is Button:
				texts.append((node as Button).text)
			elif node is LineEdit:
				texts.append((node as LineEdit).placeholder_text)
			if node is Control:
				texts.append((node as Control).tooltip_text)
			for text: String in texts:
				if text.strip_edges().is_empty():
					continue
				seen += 1
				for line: String in text.split("\n"):
					_expect(not spanish_only.has(line.strip_edges()),
						"%s shows \"%s\" in Spanish with the game in English (%s)"
							% [screen.get_class(), line, spanish_only.get(line.strip_edges(), "")])
	_expect(seen > 30, "the company screens drew their texts (%d)" % seen)
	var new_company := slots.find_child("NewCompany", true, false) as Button
	_expect(new_company.text == "New company", "the company page is in English")
	for screen: Control in screens:
		screen.queue_free()
	await process_frame
	TranslationServer.set_locale(previous)


func _has_words(text: String) -> bool:
	var stripped: String = RegEx.create_from_string("%[-+0-9.]*[dsf%]").sub(text, "", true)
	return RegEx.create_from_string("[A-Za-z]{2,}").search(stripped) != null


func _is_key(text: String) -> bool:
	return RegEx.create_from_string("^(UI|HUD|WORLD)_[A-Z0-9_]+$").search(text) != null


func _scripts(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	if dir_path in SKIP_DIRS or dir_path.get_file() == "tests":
		return found
	return _files(dir_path, ".gd")


func _files(dir_path: String, extension: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file_name: String in dir.get_files():
		if file_name.ends_with(extension):
			found.append(dir_path.path_join(file_name))
	for sub: String in dir.get_directories():
		var sub_path: String = dir_path.path_join(sub)
		if extension == ".gd" and (sub_path in SKIP_DIRS or sub == "tests"):
			continue
		found.append_array(_files(sub_path, extension))
	return found


func _read_csv(path: String) -> Dictionary:
	var table: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	_expect(file != null, "%s opens" % path)
	if file == null:
		return table
	file.get_csv_line()
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() >= 3 and not line[0].is_empty():
			table[line[0]] = [line[1], line[2]]
	return table


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

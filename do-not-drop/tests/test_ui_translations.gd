extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_ui_translations.gd
##
## The menus' and the HUD's texts are translatable (translations/strings_ui.csv),
## the same way the world's are (test_world_translations):
## - every key has a Spanish and an English text, with the same placeholders
##   (a "%d" missing in one language breaks the string at runtime);
## - every UI_* / HUD_* key the code asks for is in the table, and every key
##   in the table is used somewhere (no dead rows);
## - Spanish stays the text the game always showed, and switching the locale
##   builds a panel in English.

const CSV_PATH: String = "res://translations/strings_ui.csv"
const SCAN_DIRS: Array[String] = ["res://scripts"]
## These two tables match already-translated prompts/trap names to icons.
## Their Spanish literals are lookup data, never text drawn directly.
const ACCENTED_LOOKUP_FILES: Array[String] = [
	"res://scripts/ui/hud/hud_prompts.gd",
	"res://scripts/ui/ui_theme.gd",
	# Quick callouts travel as their Spanish phrase (a stable network id that
	# also sets the voice's syllables); display_text() translates its "key".
	"res://scripts/ui/ping_catalog.gd",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var table: Dictionary = _read_csv()
	_expect(table.size() > 500, "The UI table holds the menus' and HUD's texts (%d keys)" % table.size())
	var placeholder := RegEx.create_from_string("%[-+0-9.]*[dsf%]")
	for key: String in table:
		var es: String = table[key][0]
		var en: String = table[key][1]
		_expect(key.begins_with("UI_") or key.begins_with("HUD_"), "%s is a UI_* or HUD_* key" % key)
		_expect(not es.is_empty() and not en.is_empty(), "%s has both texts" % key)
		var es_marks: Array = placeholder.search_all(es).map(func(m: RegExMatch) -> String: return m.get_string())
		var en_marks: Array = placeholder.search_all(en).map(func(m: RegExMatch) -> String: return m.get_string())
		_expect(es_marks == en_marks,
				"%s has the same placeholders in both languages (%s vs %s)" % [key, es_marks, en_marks])

	var used: Dictionary = {}
	var key_pattern := RegEx.create_from_string("\"((?:UI|HUD)_[A-Z0-9_]+)\"")
	# A key in the CSV counts once it appears quoted in any script.
	for dir_path: String in SCAN_DIRS:
		for file_path: String in _scripts(dir_path):
			for found: RegExMatch in key_pattern.search_all(FileAccess.get_file_as_string(file_path)):
				used[found.get_string(1)] = file_path
	for key: String in used:
		_expect(table.has(key), "%s (asked for in %s) is in the table" % [key, used[key]])
	for key: String in table:
		_expect(used.has(key), "%s is used somewhere (no dead rows)" % key)
	_check_no_spanish_ui_literals()

	var locale: String = TranslationServer.get_locale()
	_expect(locale.begins_with("es"), "The game starts in Spanish (locale %s)" % locale)
	_expect(tr("UI_MENU_PLAY") == "¡JUGAR!", "Spanish: the play button says '¡JUGAR!' (%s)" % tr("UI_MENU_PLAY"))
	var settings: Node = root.get_node(^"/root/GameSettings")
	settings.call(&"set_language", "en")
	# Loaded, not named: naming the class compiles it before the autoloads exist.
	var options: Control = load("res://scripts/ui/options_panel.gd").new()
	root.add_child(options)
	await process_frame
	var texts: Array = options.find_children("*", "Label", true, false).map(func(label: Node) -> String:
		return (label as Label).text)
	_expect("Options" in texts and "Master volume" in texts,
		"English: the options panel is built in English (%s)" % ", ".join(texts.slice(0, 6)))
	var language_option: OptionButton = options.find_child("LanguageOption", true, false) as OptionButton
	_expect(language_option != null and language_option.selected == 1,
		"The options panel selects the saved English language")
	language_option.select(0)
	language_option.item_selected.emit(0)
	await process_frame
	await process_frame
	texts = options.find_children("*", "Label", true, false).map(func(label: Node) -> String:
		return (label as Label).text)
	_expect("Opciones" in texts and "Volumen general" in texts,
		"Changing language rebuilds the open options panel in Spanish")
	_expect(String(settings.get(&"language")) == "es", "The language selector updates GameSettings")
	options.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: the menus' and HUD's texts are all in the table, in both languages, and follow the locale")
	quit(_failures)


func _check_no_spanish_ui_literals() -> void:
	var accented := RegEx.create_from_string('"[^"\\n]*[áéíóúñÁÉÍÓÚÑ¿¡][^"\\n]*"')
	for file_path: String in _scripts("res://scripts/ui"):
		if file_path in ACCENTED_LOOKUP_FILES:
			continue
		var line_number: int = 0
		for line: String in FileAccess.get_file_as_string(file_path).split("\n"):
			line_number += 1
			if line.strip_edges().begins_with("#"):
				continue
			_expect(accented.search(line) == null,
				"%s:%d has no untranslated Spanish UI literal" % [file_path, line_number])


## key -> [es, en]
func _read_csv() -> Dictionary:
	var table: Dictionary = {}
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	_expect(file != null, "The CSV exists")
	if file == null:
		return table
	var header: PackedStringArray = file.get_csv_line()
	_expect(header == PackedStringArray(["keys", "es", "en"]), "Columns are keys,es,en (%s)" % header)
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() < 3 or line[0].is_empty():
			continue
		_expect(not table.has(line[0]), "%s appears once" % line[0])
		table[line[0]] = [line[1], line[2]]
	return table


func _scripts(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file_name: String in dir.get_files():
		if file_name.ends_with(".gd"):
			found.append(dir_path.path_join(file_name))
	for sub: String in dir.get_directories():
		found.append_array(_scripts(dir_path.path_join(sub)))
	return found


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

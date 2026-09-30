extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_ui_translations.gd
##
## The menus', the HUD's and the gameplay's texts are translatable
## (translations/strings_ui.csv), the same way the world's are
## (test_world_translations):
## - every key has a Spanish and an English text, with the same placeholders
##   (a "%d" missing in one language breaks the string at runtime);
## - every UI_* / HUD_* key the code asks for is in the table, and every key
##   in the table is used somewhere (no dead rows);
## - no script under ui/, gameplay/, core/ or presentation/ draws a Spanish
##   literal straight on screen (N-805: in English the player read Spanish
##   care messages, run-end reasons and connection errors), except the files
##   in SPANISH_LITERAL_FILES and debug output (print/push_warning/push_error);
##   nor sets a .text to a plain word ("PAUSA", "GARAJE") that is not in
##   SAME_IN_BOTH (a literal assigned on the same line, or after an inline
##   "else"; constants and helper arguments aren't seen), and the main menu's
##   page titles are all keys;
## - trap names travel as keys (TrapDefinition.name_key()), each one in the
##   table with the .tres display_name as its Spanish text, and no script
##   draws a .tres display_name straight on screen: each peer translates the
##   name into its own language, not the host's.
## - S-605: the warnings read while driving are short: every trap hint
##   (HUD_HINT_<TRAP>_*) and every route-event prompt (HUD_EVENT_*_PROMPT,
##   *_HOUSE, *_REVEALED, *_SWAPPED) has at most 6 words, in Spanish and in
##   English, not counting the values inserted at runtime (%d, %s, %.0f);
## - Spanish stays the text the game always showed, and switching the locale
##   builds a panel in English.

const CSV_PATH: String = "res://translations/strings_ui.csv"
const SCAN_DIRS: Array[String] = ["res://scripts", "res://modules"]
## Where a quoted accented literal means text shown untranslated.
const LITERAL_SCAN_DIRS: Array[String] = [
	"res://scripts/ui",
	"res://scripts/gameplay",
	"res://scripts/core",
	"res://scripts/presentation",
]
## Files whose Spanish literals are legitimately never drawn as they are.
const SPANISH_LITERAL_FILES: Array[String] = [
	# Matches already-translated trap names to icons: lookup data, never text
	# drawn directly.
	"res://scripts/ui/ui_theme.gd",
	# Quick callouts travel as their Spanish phrase (a stable network id that
	# also sets the voice's syllables); display_text() translates its "key".
	"res://scripts/ui/ping_catalog.gd",
	# @export defaults of resource data; the screen gets TEXT_KEYS / NAME_KEYS
	# through localized_name() and friends (.tres display names: separate task).
	"res://scripts/gameplay/package/package_content.gd",
	"res://modules/hazards/trap_definition.gd",
	# Made-up town names on road signs: proper nouns, the same in any language.
	"res://scripts/gameplay/route/town_sign.gd",
	# Developer tool that lists every sound by a Spanish label; never in the game.
	"res://scripts/presentation/sound_audit.gd",
]
## Words written the same in Spanish and English, allowed as a plain .text.
const SAME_IN_BOTH: Array[String] = ["ENDLESS", "Endless", "PING"]
## The only scripts that read a resource's display_name: they turn it into a key.
const DISPLAY_NAME_FILES: Array[String] = [
	"res://scripts/gameplay/package/package_content.gd",
	"res://modules/hazards/trap_definition.gd",
]
## Debug output is for us, not the player.
const DEBUG_CALLS: Array[String] = ["print(", "push_warning(", "push_error("]

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
	_check_no_plain_word_texts()
	_check_trap_name_keys(table)
	_check_short_warnings(table)
	var menu_constants: Dictionary = load("res://scripts/ui/main_menu.gd").get_script_constant_map()
	var page_titles: Dictionary = menu_constants.get("PAGE_TITLES", {})
	_expect(not page_titles.is_empty(), "The main menu has page titles")
	for page: int in page_titles:
		var title: String = String(page_titles[page])
		_expect(table.has(title), "Main menu page %d's title is a key (%s)" % [page, title])

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
	var files: Array[String] = []
	for dir_path: String in LITERAL_SCAN_DIRS:
		files.append_array(_scripts(dir_path))
	_expect(files.size() > 100, "The literal scan reads ui, gameplay, core and presentation (%d files)" % files.size())
	for file_path: String in files:
		if file_path in SPANISH_LITERAL_FILES:
			continue
		var line_number: int = 0
		for line: String in FileAccess.get_file_as_string(file_path).split("\n"):
			line_number += 1
			var code: String = line.strip_edges()
			if code.begins_with("#") or DEBUG_CALLS.any(func(debug: String) -> bool: return code.begins_with(debug)):
				continue
			_expect(accented.search(line) == null,
				"%s:%d has no untranslated Spanish literal" % [file_path, line_number])


func _check_no_plain_word_texts() -> void:
	var assignment := RegEx.create_from_string('(\\.text|tooltip_text) = ')
	# The literal assigned straight away, or the one after an inline "else".
	var literal := RegEx.create_from_string('(?:(?:\\.text|tooltip_text) = |\\belse )"([^"\\n]*)"')
	var letters := RegEx.create_from_string("[A-Za-z]{3,}")
	var key := RegEx.create_from_string("^(UI|HUD|WORLD)_[A-Z0-9_]+$")
	for dir_path: String in LITERAL_SCAN_DIRS:
		for file_path: String in _scripts(dir_path):
			var line_number: int = 0
			for line: String in FileAccess.get_file_as_string(file_path).split("\n"):
				line_number += 1
				if line.strip_edges().begins_with("#") or assignment.search(line) == null:
					continue
				for found: RegExMatch in literal.search_all(line):
					var text: String = found.get_string(1)
					if letters.search(text) == null or text.contains("%") or key.search(text) != null:
						continue
					var word: String = text.replace("●", "").strip_edges()
					_expect(word in SAME_IN_BOTH,
						"%s:%d draws the plain word \"%s\" (use a key)" % [file_path, line_number, text])


func _check_trap_name_keys(table: Dictionary) -> void:
	var dir := DirAccess.open("res://data/traps")
	_expect(dir != null, "The trap definitions folder opens")
	var checked: int = 0
	for file_name: String in dir.get_files() if dir != null else PackedStringArray():
		if not file_name.ends_with(".tres"):
			continue
		var definition: Resource = load("res://data/traps/" + file_name)
		var key: String = String(definition.call(&"name_key"))
		checked += 1
		_expect(table.has(key), "%s's name travels as a key in the table (%s)" % [file_name, key])
		if table.has(key):
			var spanish: String = table[key][0]
			var display_name: String = String(definition.get(&"display_name"))
			_expect(spanish == display_name,
				"%s: the key's Spanish text is its display_name (%s vs %s)" % [file_name, spanish, display_name])
			_expect(String(definition.call(&"localized_name")) == spanish, "%s reads in Spanish by default" % file_name)
	_expect(checked >= DirAccess.get_files_at("res://data/traps").size(), "Every trap is checked (%d)" % checked)
	var reads := RegEx.create_from_string('\\.display_name\\b|&"display_name"')
	for dir_path: String in LITERAL_SCAN_DIRS:
		for file_path: String in _scripts(dir_path):
			if file_path in DISPLAY_NAME_FILES:
				continue
			_expect(reads.search(FileAccess.get_file_as_string(file_path)) == null,
				"%s doesn't draw a .tres display_name (localized_name() / name_key())" % file_path)


## S-605: trap hints and route-event prompts are read while driving: 6 words
## at most. The runtime values (%d, %s, %.0f, with a trailing "s" or "°") and
## bare symbols (·, /) are not words; a literal number or a word like "A/D" is.
func _check_short_warnings(table: Dictionary) -> void:
	var trap_hint := RegEx.create_from_string("^HUD_HINT_(FRAGILE|BALANCE|EXPLOSIVE|WEIGHT|HOSTILE|LIQUID|NOISY)(_|$)")
	var event_text := RegEx.create_from_string("^HUD_EVENT_[A-Z_]+_(PROMPT|HOUSE|REVEALED|SWAPPED)$")
	var inserted := RegEx.create_from_string("%[-+0-9.]*[dsf][s°]?")
	var has_letters := RegEx.create_from_string("[A-Za-zÀ-ÿ0-9]")
	var hints: int = 0
	var prompts: int = 0
	for key: String in table:
		var is_hint: bool = trap_hint.search(key) != null
		var is_prompt: bool = event_text.search(key) != null
		if not is_hint and not is_prompt:
			continue
		hints += 1 if is_hint else 0
		prompts += 1 if is_prompt else 0
		for language: int in 2:
			var words: int = 0
			for token: String in inserted.sub(table[key][language], " ", true).split(" ", false):
				words += 1 if has_letters.search(token) != null else 0
			_expect(words <= 6, "%s (%s) has at most 6 words (%d)" % [key, ["es", "en"][language], words])
	_expect(hints >= 20, "The 7 traps' hints are all checked (%d keys)" % hints)
	_expect(prompts >= 10, "The route events' prompts are all checked (%d keys)" % prompts)


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

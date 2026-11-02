extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_expansion_english.gd
##
## The English of the expansion is complete (expansion D-1917, the `loc_text` done-when of group 19):
## - both tables (strings_ui.csv, strings_world.csv) are read row by row as Godot imports them: every row has
##   exactly three fields (key, es, en; a comma in an unquoted text splits the row and Godot drops the English),
##   no key twice, no empty Spanish or English;
## - every row's English has the same placeholders as its Spanish (%s, %d, %.1f...), so no LocText line or
##   tr() % args fails in one language only;
## - the expansion's keys (named in the company's scripts and in its data/*.tres) have an English with no
##   Spanish letters (á é í ó ú ñ ¿ ¡), translated in both languages;
## - those keys keep the glossary (docs/expansion-distritos/diseno/glosario.md) for the terms
##   test_ui_translations does not check: a Spanish text with "sueldo", "sello", "estante", "alquiler", "flota",
##   "zona", "cliente", "mercadería", "turno", "día" or "cinta" says wage, stamp, shelf, rent, fleet, zone,
##   customer, goods, shift, day or tape in English (TERM_EXCEPTIONS: another concept with the same word).

const TABLES: Array[String] = ["res://translations/strings_ui.csv", "res://translations/strings_world.csv"]
## Where the expansion's texts are named: folders read whole and single files.
const SCRIPT_DIRS: Array[String] = [
	"res://scripts/core/company", "res://scripts/gameplay/business", "res://scripts/gameplay/districts",
	"res://scripts/gameplay/fleet",
]
const SCRIPT_PREFIXES: Dictionary = {
	"res://scripts/gameplay": ["company_"],
	"res://scripts/ui": ["company_", "clipboard", "day_summary", "day_close", "shed_event", "stock_panel",
		"supplier_order", "order_sheet"],
}
const DATA_DIRS: Array[String] = [
	"res://data/boxes", "res://data/employees", "res://data/gates", "res://data/order_requirements",
	"res://data/order_templates", "res://data/placeables", "res://data/products", "res://data/shed",
	"res://data/shop", "res://data/suppliers", "res://data/zones",
]
## Glossary: Spanish word (with its plural) -> what the English says (a regular expression).
const TERMS: Dictionary = {
	"sueldo": "wage", "sello": "stamp", "estante": "shel", "alquiler": "rent", "flota": "fleet", "zona": "zone",
	"cliente": "customer", "mercadería": "goods", "turno": "shift", "día": "day|daily", "cinta": "tape|taping",
}
## Keys where the word is another concept: the conveyor belt is a "cinta" too.
const TERM_EXCEPTIONS: Array[String] = ["WORLD_SHOP_CONVEYOR"]
## Spanish letters that an English text never has.
const SPANISH_LETTERS: String = "áéíóúñ¿¡ÁÉÍÓÚÑ"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var table: Dictionary = {}
	for path: String in TABLES:
		_read(path, table)
	_expect(table.size() > 1000, "both tables read (%d keys)" % table.size())
	for key: String in table:
		_check_placeholders(key, table[key])
	var keys: Array[String] = _expansion_keys(table)
	_expect(keys.size() > 300, "the expansion's keys are found (%d)" % keys.size())
	for key: String in keys:
		_check_english(key, table[key])
	_check_translated(keys)
	if _failures == 0:
		print("PASS: the expansion's English is complete: %d keys, whole rows, same placeholders" % keys.size())
	quit(_failures)


func _read(path: String, table: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_expect(false, "%s opens" % path)
		return
	var header: PackedStringArray = file.get_csv_line()
	_expect(header == PackedStringArray(["keys", "es", "en"]), "%s has keys,es,en" % path)
	var row: int = 1
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		row += 1
		if line.size() == 1 and line[0].strip_edges() == "":
			continue
		_expect(line.size() == 3, "%s row %d (%s) should have 3 fields but has %d: quote a text with a comma"
			% [path.get_file(), row, line[0], line.size()])
		if line.size() < 3:
			continue
		_expect(not table.has(line[0]), "%s is only once" % line[0])
		_expect(line[1].strip_edges() != "" and line[2].strip_edges() != "", "%s has Spanish and English" % line[0])
		table[line[0]] = [line[1], line[2]]


func _check_placeholders(key: String, texts: Array) -> void:
	var spanish: Array[String] = _placeholders(String(texts[0]))
	var english: Array[String] = _placeholders(String(texts[1]))
	_expect(spanish == english, "%s has the same placeholders in both languages (%s / %s)" % [key, spanish, english])


func _check_english(key: String, texts: Array) -> void:
	var english: String = String(texts[1])
	for letter: String in SPANISH_LETTERS:
		if english.contains(letter):
			_expect(false, "%s's English has no Spanish letter %s: %s" % [key, letter, english])
			break
	if TERM_EXCEPTIONS.has(key):
		return
	var spanish: String = String(texts[0]).to_lower()
	for term: String in TERMS:
		var said := RegEx.create_from_string("(?<![\\wáéíóúñ])%s(s|es)?(?![\\wáéíóúñ])" % term)
		if said.search(spanish) == null:
			continue
		var wanted := RegEx.create_from_string(String(TERMS[term]))
		_expect(wanted.search(english.to_lower()) != null,
			"%s says \"%s\" in English as the glossary does (%s): %s" % [key, term, TERMS[term], english])


## Godot's own lookup gives the same English for the expansion's keys (the import read the rows whole).
func _check_translated(keys: Array[String]) -> void:
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in keys:
			_expect(TranslationServer.translate(key) != key, "%s is translated in %s" % [key, locale])
	TranslationServer.set_locale("es")


func _expansion_keys(table: Dictionary) -> Array[String]:
	var files: Array[String] = []
	for dir: String in SCRIPT_DIRS:
		_collect(dir, ".gd", files)
	for dir: String in SCRIPT_PREFIXES:
		for file_name: String in DirAccess.get_files_at(dir):
			if file_name.ends_with(".gd") and (SCRIPT_PREFIXES[dir] as Array).any(
					func(prefix: String) -> bool: return file_name.begins_with(prefix)):
				files.append(dir.path_join(file_name))
	for dir: String in DATA_DIRS:
		_collect(dir, ".tres", files)
	var found: Dictionary = {}
	var literal := RegEx.create_from_string("\"((?:UI|WORLD|HUD)_[A-Z0-9_]+)\"")
	for path: String in files:
		for match_: RegExMatch in literal.search_all(FileAccess.get_file_as_string(path)):
			if table.has(match_.get_string(1)):
				found[match_.get_string(1)] = true
	var keys: Array[String] = []
	keys.assign(found.keys())
	keys.sort()
	return keys


func _collect(dir: String, extension: String, into: Array[String]) -> void:
	for file_name: String in DirAccess.get_files_at(dir):
		if file_name.ends_with(extension):
			into.append(dir.path_join(file_name))
	for sub: String in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), extension, into)


static func _placeholders(text: String) -> Array[String]:
	var found: Array[String] = []
	for match_: RegExMatch in RegEx.create_from_string("%[-+ 0#]*\\d*(?:\\.\\d+)?[sdfxXc%]").search_all(text):
		found.append(match_.get_string())
	found.sort()
	return found


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1

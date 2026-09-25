extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_world_translations.gd
##
## The world's texts are translatable (N-605, translations/strings_world.csv):
## - every key has a Spanish and an English text, with the same placeholders
##   (a "%d" missing in one language breaks the string at runtime);
## - every WORLD_* key the code asks for is in the table, and every key in
##   the table is used somewhere (no dead rows);
## - the game runs in Spanish until the language option exists (S-509), and
##   switching the locale really switches what the world shows.

const CSV_PATH: String = "res://translations/strings_world.csv"
const SCAN_DIRS: Array[String] = ["res://scripts"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var table: Dictionary = _read_csv()
	_expect(table.size() > 100, "The world's table holds the world's texts (%d keys)" % table.size())
	var placeholder := RegEx.create_from_string("%[-+0-9.]*[dsf]")
	for key: String in table:
		var es: String = table[key][0]
		var en: String = table[key][1]
		_expect(key.begins_with("WORLD_"), "%s is a WORLD_* key" % key)
		_expect(not es.is_empty() and not en.is_empty(), "%s has both texts" % key)
		var es_marks: Array = placeholder.search_all(es).map(func(m: RegExMatch) -> String: return m.get_string())
		var en_marks: Array = placeholder.search_all(en).map(func(m: RegExMatch) -> String: return m.get_string())
		_expect(es_marks == en_marks, "%s has the same placeholders in both languages (%s vs %s)" % [key, es_marks, en_marks])

	var used: Dictionary = {}
	# Quoted keys only: WORLD_QUALITY and the like are script constants.
	var key_pattern := RegEx.create_from_string("\"(WORLD_[A-Z0-9_]+)\"")
	for dir_path: String in SCAN_DIRS:
		for file_path: String in _scripts(dir_path):
			for found: RegExMatch in key_pattern.search_all(FileAccess.get_file_as_string(file_path)):
				used[found.get_string(1)] = file_path
	for key: String in used:
		_expect(table.has(key), "%s (asked for in %s) is in the table" % [key, used[key]])
	for key: String in table:
		_expect(used.has(key), "%s is used somewhere (no dead rows)" % key)

	_expect(TranslationServer.get_locale().begins_with("es"), "The game starts in Spanish until S-509 (locale %s)" % TranslationServer.get_locale())
	_expect(tr("WORLD_TOWN_WELCOME") == "Bienvenidos a", "Spanish: the town sign says 'Bienvenidos a' (%s)" % tr("WORLD_TOWN_WELCOME"))
	TranslationServer.set_locale("en")
	var town := TownSign.new()
	town.town_name = "Villa Frágil"
	root.add_child(town)
	await process_frame
	var welcome := town.get_node(^"Welcome") as Label3D
	_expect(welcome != null and welcome.text == "Welcome to", "English: the town sign says 'Welcome to' (%s)" % (welcome.text if welcome != null else "none"))
	var house := DeliveryHouse.new()
	root.add_child(house)
	await process_frame
	root.get_node(^"/root/EventBus").emit_signal(&"house_delivery_recorded", 0, &"delivered_ok", &"")
	var said: String = house.reaction.bubble.text
	var english_lines: Array = []
	for line_key: String in DeliveryHouse.REACTION_LINES[&"delivered_ok"]:
		english_lines.append(table[line_key][1])
	_expect(said in english_lines, "English: the neighbour speaks English ('%s')" % said)
	town.queue_free()
	house.queue_free()
	TranslationServer.set_locale("es")
	await process_frame
	if _failures == 0:
		print("PASS: the world's texts are all in the table, in both languages, and follow the locale")
	quit(_failures)


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

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_news_desk.gd
##
## The next-day newspaper's newsroom (N-606.2, news_desk.gd + data/newspaper/stories.json):
## - the catalogue: every fact has 3+ generic variants and its headline and
##   body in both languages (strings_ui.csv), using the same {slots} in each;
## - determinism: the same facts and the same seed make the same paper, another
##   seed another one; the front page is the heaviest fact; the stories under it
##   come from different sections, one per topic, never more than three;
## - a clean run is the "scandal" story; Endless never is; a filler is always
##   there and is not the one the last paper ran; the variant of the last paper
##   isn't repeated;
## - a fact for a kind of box (hen, cake...) only ever gets variants for it or
##   generic ones;
## - what travels is ids and slots, never text; a paper that can't be read is
##   refused; a nickname is a typed name or a funny one that each peer translates.

const DESK = preload("res://scripts/presentation/newspaper/news_desk.gd")
const NICK = preload("res://scripts/core/nickname.gd")
const CSV_PATH: String = "res://translations/strings_ui.csv"
var _failures: int = 0
var _table: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_read_csv()
	_check_catalog()
	_check_determinism()
	_check_selection()
	_check_clean_run_and_fillers()
	_check_previous_variants()
	_check_tags()
	_check_reading()
	_check_payload()
	if _failures == 0:
		print("PASS: the newsroom writes a deterministic paper from the facts, in both languages, sending ids")
	quit(_failures)


func _fact(kind: String, house: int = -1, tags: Array = [], peer: int = 0) -> Dictionary:
	return {"kind": kind, "house": house, "tags": tags, "peer": peer}


func _context(seed_value: int = 7, extra: Dictionary = {}) -> Dictionary:
	var context: Dictionary = {"seed": seed_value, "town": "Villa Frágil", "km": 2.4, "minutes": 3,
			"crew": [{"peer": 1, "nick": "Turbo"}, {"peer": 2, "nick": ""}, {"peer": 3, "nick": "Ana"}]}
	context.merge(extra, true)
	return context


func _check_catalog() -> void:
	var catalog: Dictionary = DESK.catalog()
	var stories: Dictionary = catalog.get("stories", {})
	_expect(stories.size() >= 20, "The catalogue has the facts' stories (%d)" % stories.size())
	_expect((catalog.get("neighbors", []) as Array).size() >= 8, "There are invented neighbors to name")
	var slot_pattern := RegEx.create_from_string("\\{([a-z_]+)\\}")
	var fillers: int = 0
	for kind: String in stories:
		var story: Dictionary = stories[kind]
		var variants: Array = story["variants"]
		var generic: int = 0
		_expect(variants.size() >= 3, "%s has 3+ variants (%d)" % [kind, variants.size()])
		_expect((catalog["sections"] as Dictionary).has(story["section"]), "%s is in a known section" % kind)
		_expect(float(story["weight"]) >= 0.0 and not String(story["topic"]).is_empty(),
				"%s has a weight and a topic" % kind)
		fillers += 1 if bool(story.get("filler", false)) else 0
		for variant: Dictionary in variants:
			generic += 1 if not variant.has("tags") else 0
			for key: String in [variant["h"], variant["b"]]:
				_expect(_table.has(key), "%s is in the table" % key)
				if not _table.has(key):
					continue
				var marks: Array = []
				for language: int in 2:
					var found: Array = []
					for slot: RegExMatch in slot_pattern.search_all(_table[key][language]):
						found.append(slot.get_string(1))
						_expect(slot.get_string(1) in DESK.SLOT_NAMES,
								"%s uses a known slot {%s}" % [key, slot.get_string(1)])
					found.sort()
					marks.append(found)
				_expect(marks[0] == marks[1],
						"%s has the same slots in Spanish and English (%s vs %s)" % [key, marks[0], marks[1]])
		_expect(generic >= 3, "%s has 3+ generic variants (%d)" % [kind, generic])
	_expect(fillers >= 3, "There are 3+ kinds of filler (%d)" % fillers)
	for section_key: String in (catalog["sections"] as Dictionary).values():
		_expect(_table.has(section_key), "%s is in the table" % section_key)


func _check_determinism() -> void:
	var facts: Array = [_fact("missed", 1, ["cake"]), _fact("deer_hit"), _fact("fault_mirror"), _fact("complaint", 0)]
	var first: Dictionary = DESK.compose(facts, _context(11))
	var again: Dictionary = DESK.compose(facts.duplicate(true), _context(11))
	_expect(first == again, "The same facts and seed make the same paper")
	var distinct: Dictionary = {}
	for seed_value: int in range(1, 25):
		distinct[str(DESK.compose(facts, _context(seed_value)))] = true
	_expect(distinct.size() > 10, "Other seeds write other papers (%d of 24 differ)" % distinct.size())
	_expect(first["town"] == "Villa Frágil" and first["v"] == DESK.FORMAT_VERSION,
			"The paper names the town and its format")


func _check_selection() -> void:
	var facts: Array = [_fact("photo", 0), _fact("missed", 1), _fact("deer_hit"), _fact("abandoned", 2),
			_fact("delivered_ruined", 0), _fact("fault_mirror"), _fact("fault_police"), _fact("fault_rear_door")]
	for seed_value: int in range(1, 12):
		var paper: Dictionary = DESK.compose(facts, _context(seed_value))
		_expect(paper["front"]["id"] == "deer_hit",
				"The front page is the heaviest fact (got %s)" % paper["front"]["id"])
		var secondary: Array = paper["stories"]
		_expect(secondary.size() >= 2 and secondary.size() <= 3,
				"Two or three stories under it (got %d)" % secondary.size())
		var sections: Dictionary = {}
		var topics: Dictionary = {}
		for entry: Dictionary in secondary:
			var story: Dictionary = DESK.stories()[entry["id"]]
			sections[story["section"]] = true
			topics[story["topic"]] = true
		_expect(sections.size() == secondary.size(),
				"The stories come from different sections (%s)" % str(sections.keys()))
		_expect(topics.size() == secondary.size() and not topics.has("deer"), "One story per topic, none twice")
		var faults: int = 0
		for entry: Dictionary in DESK.entries(paper):
			faults += 1 if String(DESK.stories()[entry["id"]]["topic"]) == "fault" else 0
		_expect(faults <= 1, "A mirror, a door and a repair make one story, not three (got %d)" % faults)
	# Only one kind of news: the front page, and what news there is left goes under it.
	var small: Dictionary = DESK.compose([_fact("missed", 0), _fact("missed", 1)], _context())
	_expect(small["front"]["id"] == "missed" and (small["stories"] as Array).is_empty(),
			"Two missed doors are one story")
	_expect(int(small["front"]["slots"]["count"]) == 2, "The story knows how many there were")


func _check_clean_run_and_fillers() -> void:
	var clean: Dictionary = DESK.compose([_fact("delivered_ok", 0), _fact("photo", 0)], _context())
	_expect(clean["front"]["id"] == "clean_run",
			"A run with nothing wrong is the scandal (got %s)" % clean["front"]["id"])
	var empty: Dictionary = DESK.compose([], _context())
	_expect(empty["front"]["id"] == "clean_run", "A run with no facts is the scandal too")
	var endless: Dictionary = DESK.compose([_fact("endless_end")], _context(7, {"endless": true}))
	_expect(endless["front"]["id"] == "endless_end" and (endless["stories"] as Array).is_empty(),
			"Endless is the truck last seen, alone")
	var endless_clean: Dictionary = DESK.compose([], _context(7, {"endless": true}))
	_expect(endless_clean["front"].is_empty(), "Endless with no facts doesn't invent a scandal")
	var failed: Dictionary = DESK.compose([_fact("run_failed")], _context())
	_expect(failed["front"]["id"] == "run_failed", "A failed run is the truck last seen")
	var seen: Dictionary = {}
	for seed_value: int in range(1, 40):
		var paper: Dictionary = DESK.compose([_fact("missed", 0)], _context(seed_value))
		var filler: String = String(paper["filler"]["id"])
		_expect(DESK.stories()[filler].get("filler", false), "A filler is always there (%s)" % filler)
		seen[filler] = true
		var next: Dictionary = DESK.compose([_fact("missed", 0)],
				_context(seed_value, {"previous": DESK.variants_used(paper)}))
		_expect(next["filler"]["id"] != filler, "The filler isn't the one the last paper ran (%s)" % filler)
	_expect(seen.size() == 3, "All three kinds of filler turn up (%d)" % seen.size())


func _check_previous_variants() -> void:
	for kind: String in DESK.stories():
		var story: Dictionary = DESK.stories()[kind]
		for last: int in (story["variants"] as Array).size():
			for seed_value: int in range(1, 6):
				var picked: int = DESK.pick_variant(story, [], seed_value, kind, last)
				if picked == last:
					_expect(false, "%s doesn't repeat variant %d (seed %d)" % [kind, last, seed_value])
					return
	_expect(true, "No kind repeats the last paper's variant")


func _check_tags() -> void:
	var story: Dictionary = DESK.stories()["missed"]
	var variants: Array = story["variants"]
	var used: Dictionary = {}
	for seed_value: int in range(1, 80):
		var index: int = DESK.pick_variant(story, ["hen", "noisy"], seed_value, "missed", -1)
		used[index] = true
		var tags: Array = (variants[index] as Dictionary).get("tags", [])
		_expect(tags.is_empty() or "hen" in tags,
				"A missed hen only gets generic or hen variants (variant %d has %s)" % [index, tags])
	var hen_variant: int = -1
	for index: int in variants.size():
		if "hen" in (variants[index] as Dictionary).get("tags", []):
			hen_variant = index
	_expect(used.has(hen_variant), "The hen's own variant does turn up")
	var plain: Dictionary = {}
	for seed_value: int in range(1, 40):
		plain[DESK.pick_variant(story, [], seed_value, "missed", -1)] = true
	for index: int in plain:
		_expect((variants[index] as Dictionary).get("tags", []).is_empty(),
				"A fact with no kind of box only gets generic variants")


func _check_reading() -> void:
	var settings: Node = root.get_node(^"/root/GameSettings")
	var slots: Dictionary = {"town": "Villa Frágil", "house": 3, "neighbor": "Don Rufino", "player": ["UI_NICK_02"],
			"km": 3.2, "minutes": 4, "count": 2}
	for locale: String in ["es", "en"]:
		settings.call(&"set_language", locale)
		for kind: String in DESK.stories():
			for index: int in (DESK.stories()[kind]["variants"] as Array).size():
				var read: Dictionary = DESK.read({"id": kind, "variant": index, "slots": slots})
				var text: String = String(read["headline"]) + " " + String(read["body"])
				_expect(not String(read["headline"]).is_empty() and not String(read["body"]).is_empty(),
						"%s/%d reads in %s" % [kind, index, locale])
				_expect(not text.contains("{") and not text.contains("HUD_NEWS"),
						"%s/%d has every slot filled and is translated in %s (%s)" % [kind, index, locale, text])
				var section_text: String = String(read["section_text"])
				_expect(not section_text.is_empty() and not section_text.begins_with("HUD_"),
						"%s has its section in %s" % [kind, locale])
	settings.call(&"set_language", "es")
	var spanish: String = DESK.read({"id": "missed", "variant": 0, "slots": slots})["headline"]
	_expect(spanish.contains("3"), "The house number is in the headline (%s)" % spanish)
	var named: String = DESK.read({"id": "endless_end", "variant": 1, "slots": slots})["body"]
	_expect(named.contains(tr("UI_NICK_02")), "A funny nickname is translated by whoever reads it (%s)" % named)
	var km: String = DESK.read({"id": "endless_end", "variant": 0, "slots": slots})["headline"]
	_expect(km.contains("3.2"), "Kilometres come with one decimal (%s)" % km)
	var typed: Dictionary = DESK.compose([_fact("deer_hit", -1, [], 3)], _context(5))
	_expect(str(typed["front"]["slots"]["player"]) == "Ana",
			"The player behind a fact is the one named (got %s)" % str(typed["front"]["slots"]["player"]))
	var hostile: Dictionary = DESK.compose([_fact("deer_hit", -1, [], 9)],
			_context(5, {"crew": [{"peer": 9, "nick": "{town} [b]x%s"}]}))
	var hostile_text: String = DESK.fill("{player}", hostile["front"]["slots"])
	_expect(not hostile_text.contains("{") and not hostile_text.contains("[") and not hostile_text.contains("%"),
			"A nickname can't smuggle slots or markup into the paper (%s)" % hostile_text)
	var auto: Variant = DESK.compose([_fact("deer_hit", -1, [], 2)], _context(5))["front"]["slots"]["player"]
	_expect(auto is Array and NICK.AUTO_KEYS.has(String((auto as Array)[0])),
			"No nickname gets a funny one as a line to translate (got %s)" % str(auto))


func _check_payload() -> void:
	var paper: Dictionary = DESK.compose([_fact("missed", 1, ["cake"]), _fact("deer_hit", -1, [], 1)], _context(3))
	_expect(DESK.is_valid(paper), "A paper from the desk can be read")
	var flat: String = str(paper)
	for entry: Dictionary in DESK.entries(paper):
		var read: Dictionary = DESK.read(entry)
		_expect(not flat.contains(String(read["headline"])) and not flat.contains(String(read["body"])),
				"What travels has ids and slots, not the text of %s" % entry["id"])
		_expect(entry.keys().size() == 3 and entry.has("id") and entry.has("variant") and entry.has("slots"),
				"An entry is id, variant and slots")
	var broken: Dictionary = paper.duplicate(true)
	broken["front"]["id"] = "nope"
	_expect(not DESK.is_valid(broken), "An unknown story is refused")
	broken = paper.duplicate(true)
	broken["front"]["variant"] = 99
	_expect(not DESK.is_valid(broken), "A variant that doesn't exist is refused")
	_expect(not DESK.is_valid({}) and not DESK.is_valid(null) and not DESK.is_valid({"front": {}}),
			"Nothing, or an empty paper, is refused")
	_expect(DESK.variants_used(paper).size() == DESK.entries(paper).size(), "The paper remembers the variants it used")


func _read_csv() -> void:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() >= 3 and not line[0].is_empty():
			_table[line[0]] = [line[1], line[2]]


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_package_notes.gd
##
## S-602: every box has a sender, a recipient, a note and a marker scribble.
## - each data/contents/*.tres has a sender, a recipient and 3-5 notes, and its
##   texts (recipient, notes) are translation keys (NOTE_KEYS) whose Spanish is
##   the .tres text; every new key (recipient, note, scribble, label, note
##   format) is in translations/strings_ui.csv with es and en (package_content.gd);
## - the note and the scribble come from the package_id alone: the same id gives
##   the same pick, different ids give different ones (so every peer agrees with
##   no network) (PackageContent.pick_index());
## - the shipping label text carries the sender and the recipient
##   (PackageContent.shipping_text()) and the label draws them on the paper
##   (package_feedback.gd), including the label swapped in the "mixed labels" event;
## - the box shows a scribble (package_scribble.gd) on the face opposite the label;
## - opening the box adds the note to the "inside" line, a spilled box does not
##   (package_contents_view.gd describe()).
## test_ui_translations keeps checking that every HUD_* key is quoted in a script.

const CSV_PATH: String = "res://translations/strings_ui.csv"
const CONTENTS_DIR: String = "res://data/contents"

var _failures: int = 0
var _table: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_table = _read_csv()
	var contents: Array[Resource] = _load_contents()
	_expect(contents.size() == 10, "There are ten contents (got %d)" % contents.size())
	for content: Resource in contents:
		_check_content(content)
	_check_keys_all_used_by_contents(contents)
	_check_picks(contents)
	await _check_boxes()
	if _failures == 0:
		print("PASS: every box has a sender, recipient, note and scribble, picked the same on every peer")
	quit(_failures)


func _check_content(content: Resource) -> void:
	var id: StringName = content.get(&"id")
	_expect(not String(content.get(&"sender")).is_empty(), "%s has a sender" % id)
	_expect(not String(content.get(&"recipient")).is_empty(), "%s has a recipient" % id)
	var notes: PackedStringArray = content.get(&"notes")
	_expect(notes.size() >= 3 and notes.size() <= 5, "%s has 3-5 notes (got %d)" % [id, notes.size()])
	var constants: Dictionary = (content.get_script() as Script).get_script_constant_map()
	var keys: Array = (constants["NOTE_KEYS"] as Dictionary).get(id, [])
	_expect(keys.size() == notes.size() + 1,
		"%s has a key for the recipient and one per note (got %d keys, %d notes)" % [id, keys.size(), notes.size()])
	if keys.size() == notes.size() + 1:
		_expect_key(String(keys[0]), String(content.get(&"recipient")))
		for index: int in notes.size():
			_expect(not notes[index].is_empty(), "%s note %d is not empty" % [id, index])
			_expect_key(String(keys[index + 1]), notes[index])
	var scribbles: Array = content.call(&"_scribble_keys")
	_expect(scribbles.size() >= 3, "%s has a pool of scribbles (got %d)" % [id, scribbles.size()])
	for key: Variant in scribbles:
		_expect_key(String(key), "")
	# Each scribble reads as marker: short enough for a box face, and all caps.
	for key: Variant in scribbles:
		if _table.has(String(key)):
			var spanish: String = _table[String(key)][0]
			_expect(spanish == spanish.to_upper() and spanish.length() <= 30,
				"%s is shouted in capitals and short (got '%s')" % [key, spanish])
	var shipping: String = content.call(&"shipping_text")
	_expect(shipping.contains(String(content.get(&"sender"))), "%s's shipping text names the sender" % id)
	_expect(shipping.contains(String(content.call(&"localized_recipient"))),
		"%s's shipping text names the recipient" % id)
	_expect(shipping.contains(String(content.call(&"localized_name"))),
		"%s's shipping text still declares the contents" % id)
	_expect(String(content.call(&"shipping_text")).ends_with(String(content.call(&"shipping_contents"))),
		"%s's shipping text ends with the declared contents" % id)


## `spanish` empty: only that the key is there with both languages; otherwise
## the Spanish must be the .tres text.
func _expect_key(key: String, spanish: String) -> void:
	_expect(_table.has(key), "%s is in strings_ui.csv" % key)
	if not _table.has(key):
		return
	_expect(key.begins_with("HUD_"), "%s is a HUD_* key" % key)
	_expect(not String(_table[key][0]).is_empty() and not String(_table[key][1]).is_empty(),
		"%s has Spanish and English" % key)
	_expect(String(_table[key][0]) != String(_table[key][1]) or key.contains("RECIPIENT_") or key == "HUD_CONTENT_NOTE",
		"%s is actually translated (es != en)" % key)
	if not spanish.is_empty():
		_expect(String(_table[key][0]) == spanish, "%s: Spanish is the .tres text (got '%s')" % [key, _table[key][0]])


func _check_keys_all_used_by_contents(contents: Array[Resource]) -> void:
	for key: String in ["HUD_SHIPPING_FROM", "HUD_CONTENT_NOTE"]:
		_expect_key(key, "")
		_expect(String(_table.get(key, ["", ""])[0]).contains("%s"), "%s takes its text as %%s" % key)
	# Every scribble family in the table is reachable from some content.
	var reachable: Dictionary = {}
	for content: Resource in contents:
		for key: Variant in content.call(&"_scribble_keys"):
			reachable[String(key)] = true
	for key: String in _table:
		if key.begins_with("HUD_SCRIBBLE_") or key.begins_with("HUD_NOTE_") or key.begins_with("HUD_RECIPIENT_"):
			var used: bool = reachable.has(key)
			for content: Resource in contents:
				var constants: Dictionary = (content.get_script() as Script).get_script_constant_map()
				used = used or key in (constants["NOTE_KEYS"] as Dictionary).get(content.get(&"id"), [])
			_expect(used, "%s belongs to some content" % key)


func _check_picks(contents: Array[Resource]) -> void:
	for content: Resource in contents:
		var id: StringName = content.get(&"id")
		var note_seen: Dictionary = {}
		var scribble_seen: Dictionary = {}
		for n: int in 60:
			var package_id := StringName("pkg_%d" % n)
			var note: String = content.call(&"pick_note", package_id)
			var scribble: String = content.call(&"pick_scribble", package_id)
			_expect(not note.is_empty() and not scribble.is_empty(), "%s picks a note and a scribble" % id)
			_expect(note == content.call(&"pick_note", package_id), "%s: the same id picks the same note" % id)
			_expect(scribble == content.call(&"pick_scribble", package_id),
				"%s: the same id picks the same scribble" % id)
			_expect(int(content.call(&"note_index", package_id)) < (content.get(&"notes") as PackedStringArray).size(),
				"%s: the note index is within the notes" % id)
			note_seen[note] = true
			scribble_seen[scribble] = true
		var note_count: int = (content.get(&"notes") as PackedStringArray).size()
		_expect(note_seen.size() == note_count,
			"%s: 60 ids reach all %d notes (got %d)" % [id, note_count, note_seen.size()])
		_expect(scribble_seen.size() > 1, "%s: scribbles vary between ids (got %d)" % [id, scribble_seen.size()])
	var scribble_script: Script = load("res://scripts/gameplay/package/package_scribble.gd")
	_expect(is_equal_approx(scribble_script.tilt(&"a"), scribble_script.tilt(&"a")),
		"The tilt is the same for the same id")
	var tilts: Dictionary = {}
	for n: int in 20:
		var tilt: float = scribble_script.tilt(StringName("pkg_%d" % n))
		_expect(absf(tilt) >= deg_to_rad(2.0) - 0.0001 and absf(tilt) <= deg_to_rad(5.0) + 0.0001,
			"The tilt stays between 2 and 5 degrees (got %f)" % rad_to_deg(tilt))
		tilts[snappedf(tilt, 0.001)] = true
	_expect(tilts.size() > 3, "The tilt varies between ids (got %d values)" % tilts.size())


func _check_boxes() -> void:
	var cake: Resource = load(CONTENTS_DIR + "/wedding_cake.tres")
	var vase: Resource = load(CONTENTS_DIR + "/porcelain_vase.tres")
	var boxes: Array[Node] = []
	for fixture: Array in [["notes_a", cake, "balance"], ["notes_b", vase, "fragile"]]:
		var package: Node = load("res://scenes/gameplay/package/package.tscn").instantiate()
		package.name = String(fixture[0]).to_pascal_case()
		package.set(&"package_id", StringName(fixture[0]))
		package.set(&"trap_definition", load("res://data/traps/%s.tres" % fixture[2]))
		package.set(&"content", fixture[1])
		package.set(&"freeze", true)
		root.add_child(package)
		boxes.append(package)
	await process_frame
	await process_frame
	await process_frame
	for index: int in boxes.size():
		var package: Node = boxes[index]
		var content: Resource = package.call(&"content_definition")
		var feedback: Node = package.get_node("PackageFeedbackComponent")
		var label: Node3D = feedback._shipping_label
		var texts: Array[String] = []
		for label3d: Node in label.find_children("*", "Label3D", false, false):
			texts.append((label3d as Label3D).text)
		var all_text: String = "\n".join(texts)
		_expect(all_text.contains(String(content.get(&"sender"))),
			"%s: the paper names the sender (got %s)" % [package.name, texts])
		_expect(all_text.contains(String(content.call(&"localized_recipient"))),
			"%s: the paper names the recipient" % package.name)
		_expect(all_text.contains(String(content.call(&"localized_name"))),
			"%s: the paper still names the contents" % package.name)
		var parties: Label3D = label.get_node_or_null(^"ShippingParties") as Label3D
		_expect(parties != null and parties.font_size >= 14 and parties.font_size <= 28,
			"%s: the recipient lines fit the paper" % package.name)
		# The scribble: on the face opposite the label, out of the cardboard, tilted.
		var scribble: Label3D = package.get_node_or_null(^"Box/Scribble") as Label3D
		_expect(scribble != null, "%s carries a scribble" % package.name)
		if scribble != null:
			_expect(scribble.text == content.call(&"pick_scribble", package.get("package_id")),
				"%s: the scribble is the one picked from its id" % package.name)
			_expect(scribble.position.z > 0.0 and label.position.z < 0.0,
				"%s: the scribble and the label are on opposite faces" % package.name)
			_expect(scribble.outline_size == 0 and absf(scribble.rotation.z) > 0.0,
				"%s: the scribble is plain marker, tilted" % package.name)
		# Opening the box adds the note to the inside line.
		var view: Node = package.get_node("PackageContentsView")
		_expect(String(view.call(&"describe")).is_empty(), "%s: a closed box tells nothing" % package.name)
		var note: String = content.call(&"pick_note", package.get("package_id"))
		package.call(&"set_open", true)
		var inside: String = view.call(&"describe")
		_expect(inside.contains(String(content.call(&"localized_name"))),
			"%s: looking in names the contents" % package.name)
		_expect(inside.contains(note), "%s: looking in reads the note (got '%s')" % [package.name, inside])
		# A spilled box has nothing left to read.
		view.set(&"_spilled", true)
		_expect(not String(view.call(&"describe")).contains(note), "%s: a spilled box shows no note" % package.name)
		view.set(&"_spilled", false)

	# The "mixed labels" event: box 0 wears box 1's label, parties included.
	var first: Node = boxes[0]
	var second: Node = boxes[1]
	first.set(&"label_swapped_with", second.get("package_id"))
	first.add_to_group(&"cargo")
	second.add_to_group(&"cargo")
	await process_frame
	await process_frame
	var swapped: Label3D = first.get_node("PackageFeedbackComponent")._shipping_label.get_node("ShippingParties")
	var other: Resource = second.call(&"content_definition")
	_expect(swapped.text == other.call(&"shipping_parties"),
		"A swapped label names the other box's sender and recipient (got %s)" % swapped.text)
	first.set(&"label_swapped_with", &"")
	await process_frame
	await process_frame
	_expect(swapped.text == first.call(&"content_definition").call(&"shipping_parties"),
		"When the labels go back, so do the sender and recipient (got %s)" % swapped.text)

	for package: Node in boxes:
		package.queue_free()
	await process_frame


func _load_contents() -> Array[Resource]:
	var found: Array[Resource] = []
	var dir := DirAccess.open(CONTENTS_DIR)
	_expect(dir != null, "The contents folder opens")
	if dir == null:
		return found
	for file_name: String in dir.get_files():
		if file_name.ends_with(".tres"):
			found.append(load(CONTENTS_DIR.path_join(file_name)))
	return found


## key -> [es, en]
func _read_csv() -> Dictionary:
	var table: Dictionary = {}
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	_expect(file != null, "The CSV exists")
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

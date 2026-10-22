extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_customer_note.gd
##
## Customer's handwritten note (expansion D-0731, customer_note.gd and PackedBox.note_key):
## - an order's note is repeatable (same id, same note) and an order without id has none;
## - a gift order gets a gift note, any other order a plain one, and every key has a translation;
## - attach() writes the note once and refuses a null box, no note or a box that already has one;
## - the note survives a JSON round trip; unknown keys and old snapshots come back without a note.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var plain: Dictionary = {"id": "order_7", "requirements": ["fragile"]}
	var gift: Dictionary = {"id": "order_7", "requirements": ["gift"]}
	_expect(CustomerNote.key_for(plain) == CustomerNote.key_for(plain.duplicate()), "same id, same note")
	_expect(CustomerNote.key_for({}) == &"", "an order without id has no note")
	_expect(CustomerNote.key_for(gift) in CustomerNote.GIFT_KEYS, "a gift order gets a gift note")
	_expect(CustomerNote.key_for(plain) in CustomerNote.PLAIN_KEYS, "a plain order gets a plain note")

	var seen: Dictionary = {}
	for i in 40:
		seen[CustomerNote.key_for({"id": "order_%d" % i})] = true
	_expect(seen.size() == CustomerNote.PLAIN_KEYS.size(), "40 orders use every plain note")

	var csv: String = FileAccess.get_file_as_string("res://translations/strings_ui.csv")
	for key: StringName in CustomerNote.KEYS:
		_expect(csv.contains("\n%s," % key), "%s is in strings_ui.csv" % key)
	_expect(CustomerNote.KEYS.size() == CustomerNote.PLAIN_KEYS.size() + CustomerNote.GIFT_KEYS.size(), "KEYS lists both pools")

	var box := PackedBox.new(&"M")
	_expect(CustomerNote.text(box) == "", "a new box carries no note")
	_expect(not CustomerNote.attach(null, plain), "null box refuses")
	_expect(not CustomerNote.attach(box, {}), "an order without id writes nothing")
	_expect(CustomerNote.attach(box, plain), "the note is written")
	_expect(box.note_key == CustomerNote.key_for(plain), "the box carries the order's note")
	_expect(not CustomerNote.attach(box, gift), "the note is written once")
	_expect(box.note_key == CustomerNote.key_for(plain), "the first note stays")
	_expect(CustomerNote.text(null) == "", "null box has no text")

	var back: PackedBox = PackedBox.from_dict(JSON.parse_string(JSON.stringify(box.to_dict())))
	_expect(back.note_key == box.note_key, "note survives a JSON round trip")
	var forged: Dictionary = box.to_dict()
	forged["note_key"] = "SOMETHING_ELSE"
	_expect(PackedBox.from_dict(forged).note_key == &"", "an unknown key is dropped")
	_expect(PackedBox.from_dict({"box_size": "M"}).note_key == &"", "old snapshots have no note")

	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)

class_name CustomerNote
extends RefCounted
## The customer's handwritten note on the box (expansion D-0731, "Modo Empresa").
##
## Static and stateless. Each order carries one short note picked by its id from a fixed list, so every
## peer gets the same one with no network; a gift order picks from the gift notes. attach() copies the
## note's translation key onto the box (PackedBox.note_key), once. Drawing it on the box face (reusing
## the marker look of PackageScribble) is D-0731.b; this class only decides which note a box carries.

## Notes for any order (strings_ui.csv).
const PLAIN_KEYS: Array[StringName] = [
	&"UI_COMPANY_NOTE_1",
	&"UI_COMPANY_NOTE_2",
	&"UI_COMPANY_NOTE_3",
	&"UI_COMPANY_NOTE_4",
]
## Notes for a gift order.
const GIFT_KEYS: Array[StringName] = [
	&"UI_COMPANY_NOTE_GIFT_1",
	&"UI_COMPANY_NOTE_GIFT_2",
]
## Every key a box may carry (PackedBox.from_dict drops anything else).
const KEYS: Array[StringName] = [
	&"UI_COMPANY_NOTE_1",
	&"UI_COMPANY_NOTE_2",
	&"UI_COMPANY_NOTE_3",
	&"UI_COMPANY_NOTE_4",
	&"UI_COMPANY_NOTE_GIFT_1",
	&"UI_COMPANY_NOTE_GIFT_2",
]


## The note an order carries; "" for an order without id. Same id, same note, on every peer.
static func key_for(order: Dictionary) -> StringName:
	var id: String = str(order.get("id", ""))
	if id.is_empty():
		return &""
	var pool: Array[StringName] = GIFT_KEYS if GiftWrap.is_gift(order) else PLAIN_KEYS
	return pool[id.hash() % pool.size()]


## Puts the order's note on the box. False, changing nothing, with no box, no note or a box that
## already carries one.
static func attach(box: PackedBox, order: Dictionary) -> bool:
	if box == null or box.note_key != &"":
		return false
	var key: StringName = key_for(order)
	if key == &"":
		return false
	box.note_key = key
	return true


## The note's text in the current language; "" when the box carries none.
static func text(box: PackedBox) -> String:
	if box == null or box.note_key == &"":
		return ""
	return TranslationServer.translate(box.note_key)

class_name CustomerNote
extends RefCounted
## The customer's handwritten note on the box (expansion D-0731, "Modo Empresa").
##
## Static and stateless. Each order carries one short note picked by its id from a fixed list, so every
## peer gets the same one with no network; a gift order picks from the gift notes. attach() copies the
## note's translation key onto the box (PackedBox.note_key), once. Drawing it on the box face (reusing
## the marker look of PackageScribble) is D-0731.b; this class only decides which note a box carries.

## Notes for any order (strings_ui.csv). 48 plain + 12 gift = the 60 texts of D-0822.
const PLAIN_KEYS: Array[StringName] = [
	&"UI_COMPANY_NOTE_1",
	&"UI_COMPANY_NOTE_2",
	&"UI_COMPANY_NOTE_3",
	&"UI_COMPANY_NOTE_4",
	&"UI_COMPANY_NOTE_5",
	&"UI_COMPANY_NOTE_6",
	&"UI_COMPANY_NOTE_7",
	&"UI_COMPANY_NOTE_8",
	&"UI_COMPANY_NOTE_9",
	&"UI_COMPANY_NOTE_10",
	&"UI_COMPANY_NOTE_11",
	&"UI_COMPANY_NOTE_12",
	&"UI_COMPANY_NOTE_13",
	&"UI_COMPANY_NOTE_14",
	&"UI_COMPANY_NOTE_15",
	&"UI_COMPANY_NOTE_16",
	&"UI_COMPANY_NOTE_17",
	&"UI_COMPANY_NOTE_18",
	&"UI_COMPANY_NOTE_19",
	&"UI_COMPANY_NOTE_20",
	&"UI_COMPANY_NOTE_21",
	&"UI_COMPANY_NOTE_22",
	&"UI_COMPANY_NOTE_23",
	&"UI_COMPANY_NOTE_24",
	&"UI_COMPANY_NOTE_25",
	&"UI_COMPANY_NOTE_26",
	&"UI_COMPANY_NOTE_27",
	&"UI_COMPANY_NOTE_28",
	&"UI_COMPANY_NOTE_29",
	&"UI_COMPANY_NOTE_30",
	&"UI_COMPANY_NOTE_31",
	&"UI_COMPANY_NOTE_32",
	&"UI_COMPANY_NOTE_33",
	&"UI_COMPANY_NOTE_34",
	&"UI_COMPANY_NOTE_35",
	&"UI_COMPANY_NOTE_36",
	&"UI_COMPANY_NOTE_37",
	&"UI_COMPANY_NOTE_38",
	&"UI_COMPANY_NOTE_39",
	&"UI_COMPANY_NOTE_40",
	&"UI_COMPANY_NOTE_41",
	&"UI_COMPANY_NOTE_42",
	&"UI_COMPANY_NOTE_43",
	&"UI_COMPANY_NOTE_44",
	&"UI_COMPANY_NOTE_45",
	&"UI_COMPANY_NOTE_46",
	&"UI_COMPANY_NOTE_47",
	&"UI_COMPANY_NOTE_48",
]
## Notes for a gift order.
const GIFT_KEYS: Array[StringName] = [
	&"UI_COMPANY_NOTE_GIFT_1",
	&"UI_COMPANY_NOTE_GIFT_2",
	&"UI_COMPANY_NOTE_GIFT_3",
	&"UI_COMPANY_NOTE_GIFT_4",
	&"UI_COMPANY_NOTE_GIFT_5",
	&"UI_COMPANY_NOTE_GIFT_6",
	&"UI_COMPANY_NOTE_GIFT_7",
	&"UI_COMPANY_NOTE_GIFT_8",
	&"UI_COMPANY_NOTE_GIFT_9",
	&"UI_COMPANY_NOTE_GIFT_10",
	&"UI_COMPANY_NOTE_GIFT_11",
	&"UI_COMPANY_NOTE_GIFT_12",
]
## Every key a box may carry (PackedBox.from_dict drops anything else).
const KEYS: Array[StringName] = PLAIN_KEYS + GIFT_KEYS


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

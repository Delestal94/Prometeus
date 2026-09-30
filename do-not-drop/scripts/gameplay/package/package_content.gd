class_name PackageContent
extends Resource
## What is actually inside a delivery box, and the box it ships in.
##
## Data only, like TrapDefinition: the trap decides how a package fails, the
## content decides what the players see when they open it (and what falls out
## when an open box tips over). A trap lists the contents it can carry
## (TrapDefinition.contents); DeliveryPackage picks one per package.

@export var id: StringName = &"porcelain_vase"
@export var display_name: String = "Jarrón de porcelana"
## Printed on the shipping label under "CONTENIDO DECLARADO".
@export var declared_weight: String = "4 kg"
@export var handling: String = "FRÁGIL"
## Who sends it (a client from docs/narrativa.md: a proper name, never
## translated) and who gets it. Both go on the shipping label (S-602).
@export var sender: String = ""
@export var recipient: String = ""
## Three to five short notes in the sender's voice; the box shows one of them
## when it is opened (pick_note()). Spanish defaults, like display_name: the
## screen reads NOTE_KEYS through localized_notes().
@export var notes: PackedStringArray = []
## How the item is doing at each trap state (OK, AT_RISK, RUINED) -- what the
## player reads when they look inside.
@export var condition_texts: PackedStringArray = ["intacto", "con fisuras", "hecho añicos"]
## Content GLB: Filler (optional), Intact, Damage and Ruined (an empty whose
## children are the loose pieces). See assets/tools/build_cargo_packages.py.
@export var model: PackedScene
## Openable box GLB: Body plus FlapFront/FlapBack/FlapRight/FlapLeft, each
## pivoted on its hinge.
@export var box_model: PackedScene
## Outer size of that box, which is also the package's collider.
@export var box_size: Vector3 = Vector3(0.65, 0.65, 0.65)

const TEXT_KEYS: Dictionary = {
	&"porcelain_vase": ["HUD_CONTENT_VASE", "HUD_HANDLING_FRAGILE",
		"HUD_CONDITION_VASE_OK", "HUD_CONDITION_VASE_RISK", "HUD_CONDITION_VASE_RUINED"],
	&"antique_lamp": ["HUD_CONTENT_LAMP", "HUD_HANDLING_FRAGILE",
		"HUD_CONDITION_LAMP_OK", "HUD_CONDITION_LAMP_RISK", "HUD_CONDITION_LAMP_RUINED"],
	&"hen": ["HUD_CONTENT_HEN", "HUD_HANDLING_LIVE",
		"HUD_CONDITION_HEN_OK", "HUD_CONDITION_HEN_RISK", "HUD_CONDITION_HEN_RUINED"],
	&"puppy": ["HUD_CONTENT_PUPPY", "HUD_HANDLING_LIVE",
		"HUD_CONDITION_PUPPY_OK", "HUD_CONDITION_PUPPY_RISK", "HUD_CONDITION_PUPPY_RUINED"],
	&"glass_tower": ["HUD_CONTENT_GLASS_TOWER", "HUD_HANDLING_UPRIGHT",
		"HUD_CONDITION_GLASS_OK", "HUD_CONDITION_GLASS_RISK", "HUD_CONDITION_GLASS_RUINED"],
	&"wedding_cake": ["HUD_CONTENT_CAKE", "HUD_HANDLING_UPRIGHT",
		"HUD_CONDITION_CAKE_OK", "HUD_CONDITION_CAKE_RISK", "HUD_CONDITION_CAKE_RUINED"],
	&"sourdough": ["HUD_CONTENT_SOURDOUGH", "HUD_HANDLING_HEAVY",
		"HUD_CONDITION_SOURDOUGH_OK", "HUD_CONDITION_SOURDOUGH_RISK", "HUD_CONDITION_SOURDOUGH_RUINED"],
	&"milk_canister": ["HUD_CONTENT_MILK", "HUD_HANDLING_UPRIGHT",
		"HUD_CONDITION_MILK_OK", "HUD_CONDITION_MILK_RISK", "HUD_CONDITION_MILK_RUINED"],
	&"fireworks_crate": ["HUD_CONTENT_FIREWORKS", "HUD_HANDLING_NO_IMPACTS",
		"HUD_CONDITION_FIREWORKS_OK", "HUD_CONDITION_FIREWORKS_RISK", "HUD_CONDITION_FIREWORKS_RUINED"],
	&"raccoon_cage": ["HUD_CONTENT_RACCOON", "HUD_HANDLING_HOSTILE",
		"HUD_CONDITION_RACCOON_OK", "HUD_CONDITION_RACCOON_RISK", "HUD_CONDITION_RACCOON_RUINED"],
}

## Per content: the recipient's key first, then one key per entry of `notes`
## (same order). Keys are written out in full so test_ui_translations sees them.
const NOTE_KEYS: Dictionary = {
	&"porcelain_vase": ["HUD_RECIPIENT_VASE", "HUD_NOTE_VASE_1", "HUD_NOTE_VASE_2",
		"HUD_NOTE_VASE_3", "HUD_NOTE_VASE_4"],
	&"antique_lamp": ["HUD_RECIPIENT_LAMP", "HUD_NOTE_LAMP_1", "HUD_NOTE_LAMP_2",
		"HUD_NOTE_LAMP_3", "HUD_NOTE_LAMP_4"],
	&"hen": ["HUD_RECIPIENT_HEN", "HUD_NOTE_HEN_1", "HUD_NOTE_HEN_2",
		"HUD_NOTE_HEN_3", "HUD_NOTE_HEN_4"],
	&"puppy": ["HUD_RECIPIENT_PUPPY", "HUD_NOTE_PUPPY_1", "HUD_NOTE_PUPPY_2",
		"HUD_NOTE_PUPPY_3", "HUD_NOTE_PUPPY_4"],
	&"glass_tower": ["HUD_RECIPIENT_GLASS_TOWER", "HUD_NOTE_GLASS_TOWER_1", "HUD_NOTE_GLASS_TOWER_2",
		"HUD_NOTE_GLASS_TOWER_3", "HUD_NOTE_GLASS_TOWER_4"],
	&"wedding_cake": ["HUD_RECIPIENT_CAKE", "HUD_NOTE_CAKE_1", "HUD_NOTE_CAKE_2",
		"HUD_NOTE_CAKE_3", "HUD_NOTE_CAKE_4"],
	&"sourdough": ["HUD_RECIPIENT_SOURDOUGH", "HUD_NOTE_SOURDOUGH_1", "HUD_NOTE_SOURDOUGH_2",
		"HUD_NOTE_SOURDOUGH_3", "HUD_NOTE_SOURDOUGH_4"],
	&"milk_canister": ["HUD_RECIPIENT_MILK", "HUD_NOTE_MILK_1", "HUD_NOTE_MILK_2",
		"HUD_NOTE_MILK_3", "HUD_NOTE_MILK_4"],
	&"fireworks_crate": ["HUD_RECIPIENT_FIREWORKS", "HUD_NOTE_FIREWORKS_1", "HUD_NOTE_FIREWORKS_2",
		"HUD_NOTE_FIREWORKS_3", "HUD_NOTE_FIREWORKS_4"],
	&"raccoon_cage": ["HUD_RECIPIENT_RACCOON", "HUD_NOTE_RACCOON_1", "HUD_NOTE_RACCOON_2",
		"HUD_NOTE_RACCOON_3", "HUD_NOTE_RACCOON_4"],
}

## The marker scribble on the box (PackageScribble), by handling key (the second
## entry of TEXT_KEYS): a box that says FRÁGIL scribbles about fragility.
const SCRIBBLE_KEYS: Dictionary = {
	"HUD_HANDLING_FRAGILE": ["HUD_SCRIBBLE_FRAGILE_1", "HUD_SCRIBBLE_FRAGILE_2",
		"HUD_SCRIBBLE_FRAGILE_3", "HUD_SCRIBBLE_FRAGILE_4"],
	"HUD_HANDLING_UPRIGHT": ["HUD_SCRIBBLE_UPRIGHT_1", "HUD_SCRIBBLE_UPRIGHT_2",
		"HUD_SCRIBBLE_UPRIGHT_3", "HUD_SCRIBBLE_UPRIGHT_4"],
	"HUD_HANDLING_LIVE": ["HUD_SCRIBBLE_LIVE_1", "HUD_SCRIBBLE_LIVE_2",
		"HUD_SCRIBBLE_LIVE_3", "HUD_SCRIBBLE_LIVE_4"],
	"HUD_HANDLING_HEAVY": ["HUD_SCRIBBLE_HEAVY_1", "HUD_SCRIBBLE_HEAVY_2",
		"HUD_SCRIBBLE_HEAVY_3", "HUD_SCRIBBLE_HEAVY_4"],
	"HUD_HANDLING_NO_IMPACTS": ["HUD_SCRIBBLE_NO_IMPACTS_1", "HUD_SCRIBBLE_NO_IMPACTS_2",
		"HUD_SCRIBBLE_NO_IMPACTS_3", "HUD_SCRIBBLE_NO_IMPACTS_4"],
	"HUD_HANDLING_HOSTILE": ["HUD_SCRIBBLE_HOSTILE_1", "HUD_SCRIBBLE_HOSTILE_2",
		"HUD_SCRIBBLE_HOSTILE_3", "HUD_SCRIBBLE_HOSTILE_4"],
}
## Handlings the sender underlines in red marker; the rest are black.
const RED_INK_HANDLINGS: Array[String] = ["HUD_HANDLING_NO_IMPACTS", "HUD_HANDLING_HOSTILE", "HUD_HANDLING_LIVE"]


func localized_name() -> String:
	var keys: Array = TEXT_KEYS.get(id, [])
	return tr(String(keys[0])) if not keys.is_empty() else display_name


func localized_handling() -> String:
	var keys: Array = TEXT_KEYS.get(id, [])
	return tr(String(keys[1])) if keys.size() > 1 else handling


func condition_text(state: int) -> String:
	if condition_texts.is_empty():
		return ""
	var index: int = clampi(state, 0, condition_texts.size() - 1)
	var keys: Array = TEXT_KEYS.get(id, [])
	return tr(String(keys[index + 2])) if keys.size() > index + 2 else condition_texts[index]


## The recipient, in the player's language.
func localized_recipient() -> String:
	var keys: Array = NOTE_KEYS.get(id, [])
	return tr(String(keys[0])) if not keys.is_empty() else recipient


func localized_notes() -> PackedStringArray:
	var keys: Array = NOTE_KEYS.get(id, [])
	var result := PackedStringArray()
	for index: int in notes.size():
		result.append(tr(String(keys[index + 1])) if keys.size() > index + 1 else notes[index])
	return result


## The same number on every peer for the same package_id (String.hash() is
## deterministic and a package_id is the same everywhere), so the note and the
## scribble need no network: it is presentation only. `salt` keeps the two
## picks of one box from moving together.
static func pick_index(package_id: StringName, salt: String, count: int) -> int:
	if count <= 0:
		return -1
	return ("%s|%s" % [package_id, salt]).hash() % count


func note_index(package_id: StringName) -> int:
	return pick_index(package_id, "note", notes.size())


## The note this box carries, translated; empty if the content has none.
func pick_note(package_id: StringName) -> String:
	var index: int = note_index(package_id)
	if index < 0:
		return ""
	# Only the picked note is translated: describe() runs every frame the box is aimed at.
	var keys: Array = NOTE_KEYS.get(id, [])
	return tr(String(keys[index + 1])) if keys.size() > index + 1 else notes[index]


func _scribble_keys() -> Array:
	var keys: Array = TEXT_KEYS.get(id, [])
	return SCRIBBLE_KEYS.get(String(keys[1]), []) if keys.size() > 1 else []


func scribble_index(package_id: StringName) -> int:
	return pick_index(package_id, "scribble", _scribble_keys().size())


## The phrase scribbled on this box in marker, translated; empty if none.
func pick_scribble(package_id: StringName) -> String:
	var index: int = scribble_index(package_id)
	return tr(String(_scribble_keys()[index])) if index >= 0 else ""


func scribble_is_red() -> bool:
	var keys: Array = TEXT_KEYS.get(id, [])
	return keys.size() > 1 and String(keys[1]) in RED_INK_HANDLINGS


## The two lines printed on the "PARA:" rules of the shipping label:
## recipient, then "De: sender". Either one is left out when empty.
func shipping_parties() -> String:
	var lines := PackedStringArray()
	var to: String = localized_recipient()
	if not to.is_empty():
		lines.append(to)
	if not sender.is_empty():
		lines.append(tr("HUD_SHIPPING_FROM") % sender)
	return "\n".join(lines)


## Under "CONTENIDO DECLARADO": name, then weight and handling.
func shipping_contents() -> String:
	return "%s\n%s · %s" % [localized_name(), declared_weight, localized_handling()]


## Everything the shipping label says, in one string (the label draws the two
## halves apart to match its printed layout).
func shipping_text() -> String:
	var parties: String = shipping_parties()
	return shipping_contents() if parties.is_empty() else parties + "\n" + shipping_contents()

extends RefCounted
## The phrase somebody scribbled on the box in marker ("NO AGITAR!!!", "ESTE LADO
## ARRIBA (EN SERIO)"): ambient story, no cutscene (S-602, docs/narrativa.md).
##
## Presentation only. Which phrase, how it tilts and where it sits all come from
## the package_id (PackageContent.pick_scribble()), so every peer draws the same
## scribble with no network. It sits on the box's +Z face, clear of the shipping
## label (-Z face), the tape and flaps (lid) and the straps (-Z face).
##
## There is no handwriting font in assets/: LilitaOne (the game's chunky display
## face) stands in for the marker, all caps as written in strings_ui.csv.

const FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const INK_BLACK: Color = Color("15151a")
const INK_RED: Color = Color("b3261e")
## Label3D pixel size and font size at the reference box (0.65 m wide): a letter
## is ~5 cm tall, readable from 2-3 m and small enough to fit under the stamp.
const PIXEL_SIZE: float = 0.0013
const BASE_FONT_SIZE: int = 36
const MIN_FONT_SIZE: int = 20
## Width of an average LilitaOne capital, in font sizes: the phrase is shrunk
## to fit one line, since a second line climbs into the printed stamp.
const CHAR_EM: float = 0.7
## Share of the face's width the text may fill.
const FACE_FILL: float = 0.9
## Proud of the face like the shipping label (closer and the depth buffer makes
## box and ink flicker), and past the damage dents on this face (they stick out
## 10 mm, package_feedback.gd _add_dent_pieces) so they never cover the ink.
const OFFSET_OUT: float = 0.012
## The box GLBs print the logo (upper 60-80 %) and a big stamp (15-60 %) on this
## face, so the marker grows up from the free strip below the stamp, this far
## above the bottom edge.
const BOTTOM_MARGIN: float = 0.03
const TILT_MIN_DEGREES: float = 2.0
const TILT_MAX_DEGREES: float = 5.0


## Null when the package has no content (nothing to write) or it has no phrase.
static func build(content: Resource, package_id: StringName, box_size: Vector3) -> Label3D:
	if content == null or not content.has_method(&"pick_scribble"):
		return null
	var phrase: String = String(content.call(&"pick_scribble", package_id))
	if phrase.is_empty():
		return null
	var label := Label3D.new()
	label.name = "Scribble"
	label.text = phrase
	label.font = FONT
	var width_px: float = box_size.x * FACE_FILL / PIXEL_SIZE
	label.font_size = clampi(floori(width_px / (float(maxi(phrase.length(), 1)) * CHAR_EM)),
		MIN_FONT_SIZE, BASE_FONT_SIZE)
	label.pixel_size = PIXEL_SIZE
	label.outline_size = 0
	label.modulate = INK_RED if bool(content.call(&"scribble_is_red")) else INK_BLACK
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Wraps only if even the smallest size doesn't fit (narrow boxes, long phrases).
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = width_px
	label.line_spacing = -6.0
	label.rotation.z = tilt(package_id)
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.position = Vector3(0.0, -box_size.y * 0.5 + BOTTOM_MARGIN, box_size.z * 0.5 + OFFSET_OUT)
	return label


## Radians, 2 to 5 degrees either way (more and a corner of the text dips off
## the bottom edge); the same for the same id.
static func tilt(package_id: StringName) -> float:
	var hashed: int = ("%s|tilt" % package_id).hash()
	var amount: float = lerpf(TILT_MIN_DEGREES, TILT_MAX_DEGREES, float(hashed % 100) / 99.0)
	return deg_to_rad(amount) * (1.0 if (hashed >> 7) % 2 == 0 else -1.0)

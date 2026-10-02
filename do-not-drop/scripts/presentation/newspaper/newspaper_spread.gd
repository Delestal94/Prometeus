class_name NewspaperSpread
extends Node
## The printed paper the Boss reads in the next-day scene (N-606.3): two
## pages of newsprint drawn as UI in SubViewports, used as the 3D sheet's
## textures (NewspaperSet). `inner` is the spread he reads (page 2: the front
## story; page 3: the stories under it and the classified); `outer` is what
## the office sees (right half: the front page with the masthead; left half:
## the back page of town ads).
##
## Laid out as a real paper (the N-606.6 study): running heads, section tags,
## rules, columns of small filler copy around the crew's stories. The stories
## are what NewsDesk.read() says in this peer's language; each fills a fixed
## box, trying the sizes in its list from the biggest down until it fits
## (test_newspaper_scene checks that every story of the catalogue fits in
## both languages). `blocks` says where each story sits on `inner`, for the
## director's close-ups.
##
## A photo of the run (N-606.5, NewsPhotographer: this peer's own stills)
## goes under the front story with a halftone screen and its caption, over two
## of the three filler columns: the front story's photo if there is one, else
## the first story under it that has one; the same picture goes on the front
## page the office sees. It gets its own close-up block ("photo") after the
## front story's. The small copy and the captions are PT Serif (OFL, bundled).

const NEWS_DESK = preload("res://scripts/presentation/newspaper/news_desk.gd")
const SERIF_REGULAR: FontFile = preload("res://assets/fonts/PTSerif-Regular.ttf")
const SERIF_ITALIC: FontFile = preload("res://assets/fonts/PTSerif-Italic.ttf")
const PAGE_SIZE: Vector2i = Vector2i(2048, 1448)
## Newsprint, not UI: warm grey stock and near-black ink.
const STOCK: Color = Color("e6dcc6")
const INK: Color = Color("2b2824")
const LEFT_X: float = 64.0
const RIGHT_X: float = 1080.0
const COLUMN_WIDTH: float = 904.0
## Line breaking as Label's AUTOWRAP_WORD_SMART does it, so measuring agrees with drawing.
const BREAKS: int = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
## Font sizes tried for each kind of text, biggest first.
const FRONT_HEADLINE: Array[int] = [84, 76, 68, 60, 54, 48]
const FRONT_BODY: Array[int] = [46, 42, 38, 34, 30]
const STORY_HEADLINE: Array[int] = [46, 42, 38, 34, 30]
const STORY_BODY: Array[int] = [32, 30, 28, 26, 24]
const COVER_HEADLINE: Array[int] = [86, 76, 66, 58, 50]
## The smallest a story's own text may get: at the close-up that still reads
## at 24 px on a 720p screen.
const MIN_STORY_SIZE: int = 24
## Body copy around the stories: texture, not news.
const FILLER_KEYS: Array[String] = [
	"HUD_NEWS_FILLER_1", "HUD_NEWS_FILLER_2", "HUD_NEWS_FILLER_3", "HUD_NEWS_FILLER_4", "HUD_NEWS_FILLER_5",
	"HUD_NEWS_FILLER_6", "HUD_NEWS_FILLER_7", "HUD_NEWS_FILLER_8", "HUD_NEWS_FILLER_9", "HUD_NEWS_FILLER_10",
]
const AD_KEYS: Array[Array] = [
	["HUD_NEWS_AD_1_T", "HUD_NEWS_AD_1_B"], ["HUD_NEWS_AD_2_T", "HUD_NEWS_AD_2_B"],
	["HUD_NEWS_AD_3_T", "HUD_NEWS_AD_3_B"], ["HUD_NEWS_AD_4_T", "HUD_NEWS_AD_4_B"],
]
const SMALL_AD_KEYS: Array[String] = ["HUD_NEWS_SMALL_AD_1", "HUD_NEWS_SMALL_AD_2"]
const FILLER_SIZE: int = 21
const FILLER_SPACING: int = -3
## A photo across two columns, 16:9 like the capture, and its caption under it.
const PHOTO_SIZE: Vector2 = Vector2(598, 336)
const CAPTION_SIZES: Array[int] = [28, 26, 24]
const CAPTION_HEIGHT: float = 72.0
## The caption under each story's photo.
const PHOTO_CAPTIONS: Dictionary = {
	"deer_hit": "HUD_NEWS_PHOTO_CAPTION_DEER", "sheep_hit": "HUD_NEWS_PHOTO_CAPTION_SHEEP",
	"fault_rear_door": "HUD_NEWS_PHOTO_CAPTION_DOOR", "fault_mirror": "HUD_NEWS_PHOTO_CAPTION_MIRROR",
	"cargo_fell": "HUD_NEWS_PHOTO_CAPTION_CARGO", "cargo_recovered": "HUD_NEWS_PHOTO_CAPTION_CARGO",
	"photo": "HUD_NEWS_PHOTO_CAPTION_DELIVERY", "delivered_ok": "HUD_NEWS_PHOTO_CAPTION_DELIVERY",
	"complaint": "HUD_NEWS_PHOTO_CAPTION_DELIVERY", "delivered_ruined": "HUD_NEWS_PHOTO_CAPTION_DELIVERY",
}
## Halftone dots every this many page pixels.
const PHOTO_PITCH: float = 6.0
## Where the columns under a story end.
const COLUMN_BOTTOM: float = 1400.0

var paper: Dictionary = {}
var inner: SubViewport
var outer: SubViewport
## The crew's stories on `inner`: [{id, rect (page pixels), labels}], front first.
var blocks: Array[Dictionary] = []
## Every story label that didn't fit its box even at its smallest size.
var overflowing: Array[Label] = []
## The run's photos this peer has: story id -> Texture2D.
var photos: Dictionary = {}
## The story whose photo is printed ("" none).
var photo_story: String = ""
var _serif: Font
var _serif_italic: Font


func _init() -> void:
	name = "NewspaperSpread"


## Prints `new_paper`, with `new_photos` (story id -> Texture2D) where they
## fit; false (and nothing printed) when it can't be read.
func print_paper(new_paper: Dictionary, new_photos: Dictionary = {}) -> bool:
	if not NEWS_DESK.is_valid(new_paper):
		return false
	paper = new_paper
	photos = new_photos
	photo_story = chosen_photo(paper, photos)
	blocks.clear()
	overflowing.clear()
	for page: SubViewport in [inner, outer]:
		if page != null:
			page.free()
	inner = _page("Inner")
	outer = _page("Outer")
	_print_inner()
	_print_outer()
	return true


## A copy of a page with mipmaps, once it has been drawn: viewport textures
## have none, so small type shimmers into dark noise on a sheet seen from
## afar. The live viewport texture where nothing is drawn (headless).
func baked(page: SubViewport) -> Texture2D:
	var image: Image = page.get_texture().get_image() if page != null else null
	if image == null or image.is_empty():
		return page.get_texture() if page != null else null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Whether `text` at `font_size` wraps into `box`.
static func fits(font: Font, text: String, box: Vector2, font_size: int) -> bool:
	return text_height(font, text, box.x, font_size) <= box.y


static func text_height(font: Font, text: String, width: float, font_size: int) -> float:
	return font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, BREAKS).y


## The biggest of `sizes` at which `text` fits in `box` (the smallest if none does).
static func fitted_size(font: Font, text: String, box: Vector2, sizes: Array[int]) -> int:
	for size: int in sizes:
		if fits(font, text, box, size):
			return size
	return sizes[-1]


## The caption key of a story's photo.
static func caption_of(story_id: String) -> String:
	return String(PHOTO_CAPTIONS.get(story_id, "HUD_NEWS_PHOTO_CAPTION_DELIVERY"))


## Which story's photo to print: the front story's, else the first one under it
## with a photo ("" when none has one).
static func chosen_photo(for_paper: Dictionary, with_photos: Dictionary) -> String:
	for entry: Variant in [for_paper.get("front", {})] + Array(for_paper.get("stories", [])):
		var id: String = String((entry as Dictionary).get("id", "")) if entry is Dictionary else ""
		if not id.is_empty() and with_photos.get(id) is Texture2D:
			return id
	return ""


func _page(page_name: String) -> SubViewport:
	var page := SubViewport.new()
	page.name = page_name
	page.size = PAGE_SIZE
	page.disable_3d = true
	page.transparent_bg = false
	page.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(page)
	var stock := ColorRect.new()
	stock.size = Vector2(PAGE_SIZE)
	stock.color = STOCK
	page.add_child(stock)
	return page


# --- Inner spread: pages 2 and 3 ---------------------------------------------

func _print_inner() -> void:
	var masthead: String = tr("HUD_NEWS_MASTHEAD") % String(paper.get("town", ""))
	_folio(inner, tr("HUD_NEWS_FOLIO") % [2, masthead], LEFT_X, HORIZONTAL_ALIGNMENT_LEFT)
	_folio(inner, tr("HUD_NEWS_FOLIO") % [3, masthead], RIGHT_X, HORIZONTAL_ALIGNMENT_RIGHT)
	# Page 2: the front story, big, over three columns of town news.
	var front: Dictionary = NEWS_DESK.read(paper["front"])
	var labels: Array[Label] = []
	_section_tag(inner, String(front.get("section_text", "")), Vector2(LEFT_X, 112))
	labels.append(_story_text(inner, String(front.get("headline", "")), Rect2(LEFT_X, 168, COLUMN_WIDTH, 272),
			FRONT_HEADLINE, true))
	var body_top: float = _below(labels[0], 12.0)
	var body_box := Rect2(LEFT_X, body_top, COLUMN_WIDTH, 748 - body_top)
	labels.append(_story_text(inner, String(front.get("body", "")), body_box, FRONT_BODY, false))
	blocks.append({"id": "front", "rect": Rect2(LEFT_X, 112, COLUMN_WIDTH, 640), "labels": labels})
	_rule(inner, Vector2(LEFT_X, 764), Vector2(COLUMN_WIDTH, 3))
	if photo_story.is_empty():
		_columns(inner, LEFT_X, 780, 0)
	else:
		var photo: Dictionary = _photo(inner, LEFT_X, 780, 0)
		var caption: Array[Label] = [photo["caption"]]
		blocks.append({"id": "photo", "rect": photo["rect"], "labels": caption})
	# Page 3: the stories under it, one per band, then the classified.
	var stories: Array = paper.get("stories", [])
	for index: int in 3:
		var top: float = 112.0 + index * 292.0
		if index < stories.size():
			_secondary(NEWS_DESK.read(stories[index]), index, top)
		else:
			_filler(inner, Rect2(RIGHT_X, top, 440, 270), 4 + index)
			_filler(inner, Rect2(RIGHT_X + 464, top, 440, 270), 6 + index)
		if index < 2:
			_rule(inner, Vector2(RIGHT_X, top + 282), Vector2(COLUMN_WIDTH, 1))
	_classifieds()


func _secondary(story: Dictionary, index: int, top: float) -> void:
	var labels: Array[Label] = []
	_section_tag(inner, String(story.get("section_text", "")), Vector2(RIGHT_X, top))
	labels.append(_story_text(inner, String(story.get("headline", "")), Rect2(RIGHT_X, top + 50, COLUMN_WIDTH, 112),
			STORY_HEADLINE, true))
	var body_top: float = _below(labels[0], 6.0)
	var body_box := Rect2(RIGHT_X, body_top, COLUMN_WIDTH, top + 276 - body_top)
	labels.append(_story_text(inner, String(story.get("body", "")), body_box, STORY_BODY, false))
	blocks.append({"id": "story_%d" % index, "rect": Rect2(RIGHT_X, top, COLUMN_WIDTH, 278), "labels": labels})


func _classifieds() -> void:
	const TOP: float = 990.0
	_rule(inner, Vector2(RIGHT_X, TOP - 10), Vector2(COLUMN_WIDTH, 3))
	var filler_entry: Dictionary = paper.get("filler", {})
	var filler: Dictionary = NEWS_DESK.read(filler_entry) if not filler_entry.is_empty() else {}
	var strip := ColorRect.new()
	strip.position = Vector2(RIGHT_X, TOP)
	strip.size = Vector2(COLUMN_WIDTH, 52)
	strip.color = INK
	inner.add_child(strip)
	var title: String = tr("HUD_NEWS_SECTION_CLASSIFIED")
	if not filler.is_empty():
		title = String(filler.get("section_text", ""))
	var strip_label: Label = _text(inner, title.to_upper(), Rect2(RIGHT_X, TOP + 4, COLUMN_WIDTH, 48), 36, true)
	strip_label.add_theme_color_override("font_color", STOCK)
	strip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not filler.is_empty():
		var box := Rect2(RIGHT_X, TOP + 66, 600, 330)
		_box(inner, box)
		var labels: Array[Label] = []
		labels.append(_story_text(inner, String(filler.get("headline", "")),
				Rect2(box.position + Vector2(20, 12), Vector2(560, 104)), STORY_HEADLINE, true))
		labels.append(_story_text(inner, String(filler.get("body", "")),
				Rect2(box.position + Vector2(20, 124), Vector2(560, 196)), STORY_BODY, false))
		blocks.append({"id": "filler", "rect": Rect2(RIGHT_X, TOP, 600, 396), "labels": labels})
	for index: int in SMALL_AD_KEYS.size():
		var box := Rect2(RIGHT_X + 624, TOP + 66 + index * 172, 280, 158)
		_box(inner, box)
		var text_box := Rect2(box.position + Vector2(12, 8), box.size - Vector2(24, 16))
		_text(inner, tr(SMALL_AD_KEYS[index]), text_box, 22, false)


# --- Outer sheet: front page (right) and back page (left) ---------------------

func _print_outer() -> void:
	var masthead: Label = _text(outer, tr("HUD_NEWS_MASTHEAD") % String(paper.get("town", "")),
			Rect2(RIGHT_X, 44, COLUMN_WIDTH, 130), 0, true)
	masthead.add_theme_font_size_override("font_size",
			fitted_size(UiTheme.display_font(), masthead.text, Vector2(COLUMN_WIDTH, 130), [84, 72, 62, 54]))
	masthead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	masthead.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var motto: Label = _text(outer, tr("HUD_NEWS_MOTTO"), Rect2(RIGHT_X, 174, COLUMN_WIDTH, 36), 24, false)
	motto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rule(outer, Vector2(RIGHT_X, 214), Vector2(COLUMN_WIDTH, 4))
	_rule(outer, Vector2(RIGHT_X, 224), Vector2(COLUMN_WIDTH, 1))
	var dateline: Label = _text(outer, tr("HUD_NEWS_EDITION") + "   ·   " + tr("HUD_NEWS_ISSUE"),
			Rect2(RIGHT_X, 232, COLUMN_WIDTH, 36), 22, false)
	dateline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rule(outer, Vector2(RIGHT_X, 274), Vector2(COLUMN_WIDTH, 1))
	var front: Dictionary = NEWS_DESK.read(paper["front"])
	var extra := ColorRect.new()
	extra.position = Vector2(RIGHT_X, 292)
	extra.size = Vector2(200, 50)
	extra.color = INK
	outer.add_child(extra)
	var extra_label: Label = _text(outer, tr("HUD_NEWS_EXTRA"), Rect2(RIGHT_X, 294, 200, 46), 34, true)
	extra_label.add_theme_color_override("font_color", STOCK)
	extra_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var headline: String = String(front.get("headline", "")).to_upper()
	var cover: Label = _text(outer, headline, Rect2(RIGHT_X, 356, COLUMN_WIDTH, 360), 0, true)
	cover.add_theme_font_size_override("font_size",
			fitted_size(UiTheme.display_font(), headline, Vector2(COLUMN_WIDTH, 360), COVER_HEADLINE))
	cover.clip_text = true
	_rule(outer, Vector2(RIGHT_X, 730), Vector2(COLUMN_WIDTH, 2))
	if photo_story.is_empty():
		_columns(outer, RIGHT_X, 748, 2)
	else:
		_photo(outer, RIGHT_X, 748, 2)
	# The back page: the town's ads.
	_text(outer, tr("HUD_NEWS_ADS_TITLE"), Rect2(LEFT_X, 44, COLUMN_WIDTH, 90), 64, true)
	_rule(outer, Vector2(LEFT_X, 146), Vector2(COLUMN_WIDTH, 4))
	for index: int in AD_KEYS.size():
		var box := Rect2(LEFT_X + (index % 2) * 462, 176 + int(index / 2.0) * 612, 442, 590)
		_box(outer, box)
		_text(outer, tr(AD_KEYS[index][0]), Rect2(box.position + Vector2(16, 14), Vector2(410, 96)), 34, true)
		_text(outer, tr(AD_KEYS[index][1]), Rect2(box.position + Vector2(16, 116), Vector2(410, 120)), 28, false)
		_filler(outer, Rect2(box.position + Vector2(16, 250), Vector2(410, 320)), index * 2)


# --- Pieces --------------------------------------------------------------------

func _folio(page: SubViewport, text: String, x: float, alignment: HorizontalAlignment) -> void:
	var label: Label = _text(page, text, Rect2(x, 36, COLUMN_WIDTH, 40), 24, false)
	label.horizontal_alignment = alignment
	_rule(page, Vector2(x, 84), Vector2(COLUMN_WIDTH, 3))
	_rule(page, Vector2(x, 92), Vector2(COLUMN_WIDTH, 1))


func _section_tag(page: SubViewport, text: String, at: Vector2) -> void:
	var font: Font = UiTheme.display_font()
	var width: float = clampf(font.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 40, 160, 420)
	var tag := ColorRect.new()
	tag.position = at
	tag.size = Vector2(width, 44)
	tag.color = INK
	page.add_child(tag)
	var label: Label = _text(page, text.to_upper(), Rect2(at + Vector2(0, 2), Vector2(width, 40)), 28, true)
	label.add_theme_color_override("font_color", STOCK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## A story's own text: the biggest size that fits its box.
func _story_text(page: SubViewport, text: String, box: Rect2, sizes: Array[int], display: bool) -> Label:
	var font: Font = UiTheme.display_font() if display else UiTheme.body_font(600)
	var size: int = fitted_size(font, text, box.size, sizes)
	var label: Label = _text(page, text, box, size, display)
	label.set_meta(&"story", true)
	if not fits(font, text, box.size, size):
		overflowing.append(label)
		label.clip_text = true
	return label


## The body goes right under its headline, however many lines that took: the
## box a headline doesn't use is the body's.
func _below(headline: Label, gap: float) -> float:
	var font: Font = headline.get_theme_font("font")
	var used: float = text_height(font, headline.text, headline.size.x, headline.get_theme_font_size("font_size"))
	return headline.position.y + minf(used, headline.size.y) + gap


func _text(page: SubViewport, text: String, box: Rect2, font_size: int, display: bool) -> Label:
	var label := Label.new()
	label.position = box.position
	# Wrap, font and size before the text: with the text first, the label grows
	# to its unwrapped width at the default font and spills out of its column.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", UiTheme.display_font() if display else UiTheme.body_font(600))
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_constant_override("line_spacing", 0)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.size = box.size
	label.text = text
	label.set_meta(&"box", box.size)
	page.add_child(label)
	return label


## Three columns of filler from `top` down to the foot of the page.
func _columns(page: SubViewport, x: float, top: float, first: int) -> void:
	for column: int in 3:
		var left: float = x + column * 307.0
		_filler(page, Rect2(left, top, 290, COLUMN_BOTTOM - top), first + column * 3)
		if column > 0:
			_rule(page, Vector2(left - 9, top), Vector2(1, COLUMN_BOTTOM - top))


## The chosen photo over the first two columns at `top`, halftoned, with its
## caption; filler under it and in the third column. {rect, caption}.
func _photo(page: SubViewport, x: float, top: float, first: int) -> Dictionary:
	var picture := TextureRect.new()
	picture.name = "Photo"
	picture.position = Vector2(x, top)
	picture.size = PHOTO_SIZE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.texture = photos[photo_story]
	picture.material = PressPhoto.halftone_material(STOCK, INK, PHOTO_PITCH)
	page.add_child(picture)
	_box(page, Rect2(picture.position - Vector2(2, 2), PHOTO_SIZE + Vector2(4, 4)))
	var text: String = tr(caption_of(photo_story))
	var box := Rect2(x, top + PHOTO_SIZE.y + 8, PHOTO_SIZE.x, CAPTION_HEIGHT)
	var caption: Label = _text(page, text, box, fitted_size(serif_italic(), text, box.size, CAPTION_SIZES), false)
	caption.name = "Caption"
	caption.add_theme_font_override("font", serif_italic())
	caption.set_meta(&"story", true)
	if not fits(serif_italic(), text, box.size, caption.get_theme_font_size("font_size")):
		overflowing.append(caption)
		caption.clip_text = true
	var under: float = box.end.y + 12.0
	_rule(page, Vector2(x, under - 6), Vector2(PHOTO_SIZE.x, 1))
	_filler(page, Rect2(x, under, 290, COLUMN_BOTTOM - under), first)
	_filler(page, Rect2(x + 307, under, 290, COLUMN_BOTTOM - under), first + 3)
	_rule(page, Vector2(x + 298, under), Vector2(1, COLUMN_BOTTOM - under))
	_filler(page, Rect2(x + 614, top, 290, COLUMN_BOTTOM - top), first + 6)
	_rule(page, Vector2(x + 605, top), Vector2(1, COLUMN_BOTTOM - top))
	return {"rect": Rect2(x, top, PHOTO_SIZE.x, box.end.y - top), "caption": caption}


func _rule(page: SubViewport, at: Vector2, size: Vector2) -> void:
	var line := ColorRect.new()
	line.position = at
	line.size = size
	line.color = INK
	page.add_child(line)


func _box(page: SubViewport, area: Rect2) -> void:
	_rule(page, area.position, Vector2(area.size.x, 2))
	_rule(page, area.position + Vector2(0, area.size.y - 2), Vector2(area.size.x, 2))
	_rule(page, area.position, Vector2(2, area.size.y))
	_rule(page, area.position + Vector2(area.size.x - 2, 0), Vector2(2, area.size.y))


## Small justified serif copy, cut at the last whole line that fits.
func _filler(page: SubViewport, area: Rect2, first: int) -> void:
	var text: String = ""
	var index: int = first
	while text.length() < int(area.size.x * area.size.y / 170.0):
		text += tr(FILLER_KEYS[index % FILLER_KEYS.size()]) + " "
		index += 1
	var label := Label.new()
	label.position = area.position
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_FILL
	label.clip_text = true
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var font: Font = serif()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", FILLER_SIZE)
	label.add_theme_constant_override("line_spacing", FILLER_SPACING)
	label.add_theme_color_override("font_color", Color(INK, 0.82))
	label.max_lines_visible = maxi(1, int(area.size.y / (font.get_height(FILLER_SIZE) + FILLER_SPACING)))
	label.size = area.size
	label.text = text
	page.add_child(label)


## PT Serif for the small copy (bundled, OFL: assets/fonts/PTSerif-OFL.txt),
## Nunito for any glyph it lacks.
func serif() -> Font:
	if _serif == null:
		_serif = _with_fallback(SERIF_REGULAR)
	return _serif


## PT Serif Italic, for the photo captions.
func serif_italic() -> Font:
	if _serif_italic == null:
		_serif_italic = _with_fallback(SERIF_ITALIC)
	return _serif_italic


static func _with_fallback(base: FontFile) -> Font:
	var font := FontVariation.new()
	font.base_font = base
	font.fallbacks = [UiTheme.body_font(600)]
	return font

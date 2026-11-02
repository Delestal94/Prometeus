extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_label_textures.gd
##
## The textures of the company's boxes and products (expansion group 18, drawn in code by
## assets/tools/build_label_textures.py with Pillow):
## - the decals (D-1808): one per seal of BoxSeals.KINDS plus "this side up", the shipping and the express label,
##   256 x 256, a sticker on a transparent ground (corners clear, centre solid), no two alike;
## - the brand labels (D-1833): thirty made-up brands, 512 x 256, no two alike.
## Their look still needs a person.

const DECAL_DIR: String = "res://assets/textures/decals/"
const BRAND_DIR: String = "res://assets/textures/brands/"
const DECALS: Array[String] = [
	"seal_fragile", "seal_no_bend", "seal_cold", "seal_gift", "seal_heavy", "seal_this_side_up", "label_shipping",
	"label_express",
]
const BRANDS: Array[String] = [
	"ancla_marinera", "burbujin", "cactus_abrazo", "chispazo", "cinta_pegote", "coco_loco", "conejo_saltarin",
	"dona_gallina", "el_tano_lacteos", "esqui_patinazo", "fragil_y_feliz", "fuegos_chispita", "galpon_gourmet",
	"garrafa_tranquila", "helados_glaciar", "libros_bostezo", "loro_charlatan", "mate_mareado",
	"miel_de_la_siesta", "mochila_andariega", "pan_de_ayer", "pez_distraido", "queso_agujerito", "quimica_ups",
	"tazon_gigante", "torta_tembleque", "tostadas_tio_rulo", "vaquita_feliz", "volcan_souvenir", "zapatilla_veloz"
]

var _failures: int = 0


func _initialize() -> void:
	for kind: StringName in BoxSeals.KINDS:
		_expect(DECALS.has("seal_%s" % kind), "seal %s has its decal" % kind)
	_expect(BRANDS.size() == 30, "thirty brand labels (%d)" % BRANDS.size())
	var seen: Dictionary = {}
	for decal: String in DECALS:
		var image: Image = _image(DECAL_DIR + "tx_decal_%s_256.png" % decal)
		if image == null:
			continue
		_expect(image.get_size() == Vector2i(256, 256), "%s is 256 x 256" % decal)
		_expect(image.get_pixel(1, 1).a < 0.05 and image.get_pixel(254, 254).a < 0.05, "%s's corners are clear" % decal)
		_expect(image.get_pixel(128, 128).a > 0.95, "%s's centre is solid" % decal)
		seen[hash(image.get_data())] = decal
	_expect(seen.size() == DECALS.size(), "no two decals alike")
	seen.clear()
	for brand: String in BRANDS:
		var image: Image = _image(BRAND_DIR + "tx_brand_%s_512.png" % brand)
		if image == null:
			continue
		_expect(image.get_size() == Vector2i(512, 256), "%s is 512 x 256" % brand)
		seen[hash(image.get_data())] = brand
	_expect(seen.size() == BRANDS.size(), "no two brand labels alike")
	if _failures == 0:
		print("PASS: the box decals and brand labels are there, at size, clear around and all different")
	quit(_failures)


func _image(path: String) -> Image:
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	_expect(texture != null, "%s loads" % path)
	return texture.get_image() if texture != null else null


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1

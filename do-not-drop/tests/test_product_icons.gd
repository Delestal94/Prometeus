extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_product_icons.gd
##
## The product icons for the UI (expansion D-1845, rendered by assets/tools/render_product_icons.py in Blender's
## background mode from the product models): every model in assets/models/products has its icon in
## assets/ui/icons/products, SIZE x SIZE on a transparent ground (corners clear), the product filling a sensible
## share of it (MIN_COVER to MAX_COVER of the pixels) and roughly centred. Their look still needs a person.

const MODELS: String = "res://assets/models/products/"
const ICONS: String = "res://assets/ui/icons/products/"
const SIZE: int = 128
const MIN_COVER: float = 0.04
const MAX_COVER: float = 0.85
const CENTRE_SLACK: float = 24.0

var _failures: int = 0


func _initialize() -> void:
	var count: int = 0
	for file: String in DirAccess.get_files_at(MODELS):
		if not file.begins_with("sm_product_") or not file.ends_with(".glb"):
			continue
		count += 1
		var id: String = file.trim_prefix("sm_product_").trim_suffix(".glb")
		var path: String = ICONS + "icon_product_%s.png" % id
		var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
		_expect(texture != null, "%s has its icon" % id)
		if texture == null:
			continue
		var image: Image = texture.get_image()
		if image.is_compressed():
			image.decompress()
		_expect(image.get_size() == Vector2i(SIZE, SIZE), "%s's icon is %d x %d" % [id, SIZE, SIZE])
		_expect(image.get_pixel(0, 0).a < 0.05 and image.get_pixel(SIZE - 1, SIZE - 1).a < 0.05,
			"%s's icon has a clear ground" % id)
		var solid: int = 0
		var centre := Vector2.ZERO
		for y: int in SIZE:
			for x: int in SIZE:
				if image.get_pixel(x, y).a > 0.5:
					solid += 1
					centre += Vector2(x, y)
		var cover: float = float(solid) / (SIZE * SIZE)
		_expect(cover >= MIN_COVER and cover <= MAX_COVER, "%s fills %.0f%% of its icon" % [id, cover * 100.0])
		if solid > 0:
			centre /= solid
			_expect(centre.distance_to(Vector2(SIZE, SIZE) * 0.5) < CENTRE_SLACK, "%s is centred (%s)" % [id, centre])
	_expect(count >= 10, "the product models are there (%d)" % count)
	if _failures == 0:
		print("PASS: every product model has its icon, clear around, centred and filling it sensibly")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1

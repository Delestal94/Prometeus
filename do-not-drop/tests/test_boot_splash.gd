extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_boot_splash.gd
## Boot splash (N-328): project.godot's application/boot_splash/image is
## tx_ui_boot_splash_1920.png, built by art/tools/make_boot_splash.py as the
## menu backdrop plus the real wordmark. This test guards against:
## - the setting pointing at a missing/other file, or the image not being 1920x1080;
## - the splash going back to a baked title in another font (the splash -> menu
##   jump N-328 removed): inside the logo box the splash must differ from
##   tx_ui_menu_background_1920.png wherever the wordmark is opaque, and
##   outside the box it must be the same picture as the menu backdrop (no dark
##   tint, no baked subtitle);
## - someone moving the logo in main_menu.gd _build_brand() (position (64, 48),
##   box 420x210, menu base 1280x720) without regenerating the splash: the box
##   below is derived from those numbers, so the test fails until the script is
##   rerun (python art/tools/make_boot_splash.py).
## Images are read from the PNG files, not from the import, so VRAM compression
## cannot blur the comparison.

const SPLASH_PATH := "res://assets/ui/backgrounds/tx_ui_boot_splash_1920.png"
const MENU_BG_PATH := "res://assets/ui/backgrounds/tx_ui_menu_background_1920.png"
const WORDMARK_PATH := "res://assets/ui/logo/tx_ui_logo_wordmark_2048.png"

const SPLASH_SIZE := Vector2i(1920, 1080)
## DERIVED FROM main_menu.gd _build_brand() (menu base 1280x720, brand.position
## (64, 48), logo TextureRect 420x210) times 1920 / 1280 = 1.5. If the menu logo
## moves or changes size, update these and regenerate the splash with
## art/tools/make_boot_splash.py (LOGO_POS / LOGO_BOX there).
const MENU_SCALE := 1.5
const LOGO_POS := Vector2i(96, 72)  # (64, 48) * MENU_SCALE
const LOGO_SIZE := Vector2i(630, 315)  # (420, 210) * MENU_SCALE
## Tolerances: sum of |dR|+|dG|+|dB| per pixel, in 0..3.
const SAME_MAX_MEAN := 0.01
const DIFFERENT_MIN_MEAN := 0.3

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var setting: String = str(ProjectSettings.get_setting("application/boot_splash/image", ""))
	_expect(setting == SPLASH_PATH, "boot_splash/image points at %s (got %s)" % [SPLASH_PATH, setting])
	_expect(load(setting) is Texture2D, "boot splash resource loads as a Texture2D (got %s)" % setting)

	var splash := _load_png(SPLASH_PATH)
	var menu_bg := _load_png(MENU_BG_PATH)
	var wordmark := _load_png(WORDMARK_PATH)
	if splash == null or menu_bg == null or wordmark == null:
		_expect(false, "splash, menu background and wordmark PNGs load (got %s / %s / %s)" % [
				splash, menu_bg, wordmark])
		_finish()
		return
	_expect(splash.get_size() == SPLASH_SIZE, "splash is 1920x1080 (got %s)" % splash.get_size())
	_expect(menu_bg.get_size() == SPLASH_SIZE, "menu background is 1920x1080 (got %s)" % menu_bg.get_size())
	if splash.get_size() != SPLASH_SIZE or menu_bg.get_size() != SPLASH_SIZE:
		_finish()
		return

	# The menu fits the whole 2048x1024 texture in the box (KEEP_ASPECT_CENTERED);
	# the opaque mask comes from the scaled wordmark alpha.
	wordmark.convert(Image.FORMAT_RGBA8)
	wordmark.resize(LOGO_SIZE.x, LOGO_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var inside := _diff_mean(splash, menu_bg, wordmark)
	_expect(inside.count > 1000, "wordmark has opaque pixels inside the box (got %d)" % inside.count)
	_expect(inside.mean > DIFFERENT_MIN_MEAN,
			"splash differs from the menu backdrop under the wordmark (mean diff %.3f)" % inside.mean)

	var outside := _diff_outside(splash, menu_bg)
	_expect(outside.mean < SAME_MAX_MEAN,
			"splash equals the menu backdrop outside the logo box (mean diff %.4f)" % outside.mean)
	# Right half and bottom strip on their own, so a tint on one cannot hide in the average.
	var right := _diff_region(splash, menu_bg, Rect2i(960, 0, 960, 1080))
	var bottom := _diff_region(splash, menu_bg, Rect2i(0, 800, 1920, 280))
	_expect(right < SAME_MAX_MEAN, "right half equals the menu backdrop (mean diff %.4f)" % right)
	_expect(bottom < SAME_MAX_MEAN, "bottom strip equals the menu backdrop (mean diff %.4f)" % bottom)
	_finish()


func _finish() -> void:
	if _failures == 0:
		print("PASS: boot splash is 1920x1080, wired in project.godot, logo in the menu's box")
	quit(_failures)


func _load_png(res_path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(res_path))


## Mean colour difference over the pixels of the logo box where the (scaled)
## wordmark alpha is nearly opaque. Returns {mean, count}.
func _diff_mean(a: Image, b: Image, mask: Image) -> Dictionary:
	var total := 0.0
	var count := 0
	for y in range(0, LOGO_SIZE.y, 2):
		for x in range(0, LOGO_SIZE.x, 2):
			if mask.get_pixel(x, y).a < 0.98:
				continue
			var p := Vector2i(LOGO_POS.x + x, LOGO_POS.y + y)
			total += _pixel_diff(a.get_pixelv(p), b.get_pixelv(p))
			count += 1
	return {"mean": total / maxf(count, 1.0), "count": count}


## Mean difference over every sampled pixel outside the logo box (with a
## 4 px margin for resampling at the edge).
func _diff_outside(a: Image, b: Image) -> Dictionary:
	var box := Rect2i(LOGO_POS, LOGO_SIZE).grow(4)
	var total := 0.0
	var count := 0
	for y in range(0, SPLASH_SIZE.y, 3):
		for x in range(0, SPLASH_SIZE.x, 3):
			if box.has_point(Vector2i(x, y)):
				continue
			total += _pixel_diff(a.get_pixel(x, y), b.get_pixel(x, y))
			count += 1
	return {"mean": total / maxf(count, 1.0), "count": count}


func _diff_region(a: Image, b: Image, rect: Rect2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(rect.position.y, rect.end.y, 3):
		for x in range(rect.position.x, rect.end.x, 3):
			total += _pixel_diff(a.get_pixel(x, y), b.get_pixel(x, y))
			count += 1
	return total / maxf(count, 1.0)


func _pixel_diff(c1: Color, c2: Color) -> float:
	return absf(c1.r - c2.r) + absf(c1.g - c2.g) + absf(c1.b - c2.b)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

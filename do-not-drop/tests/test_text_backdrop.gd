extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_text_backdrop.gd
##
## The "text backdrop" setting (N-969), the plate behind subtitles and
## interaction prompts:
## - GameSettings.text_backdrop_opacity defaults to the plate the HUD always
##   had (0.88), clamps to 0..1, announces changes and is a saved key;
## - Hud.apply_text_backdrop() fades the interaction label's plate with it: fill,
##   border and shadow; at 0 nothing is drawn behind the text, at 1 it is solid;
## - the plate never covers the crosshair (the centre of the screen);
## - Options has the slider, in sync with the setting.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: Node = root.get_node("GameSettings")
	var original: float = settings.text_backdrop_opacity
	_expect(is_equal_approx(settings.TEXT_BACKDROP_DEFAULT, 0.88), "Default keeps the plate the HUD had")
	_expect(&"text_backdrop_opacity" in settings.SAVED_KEYS, "The opacity is a saved setting")
	settings.text_backdrop_opacity = 7.0
	_expect(is_equal_approx(settings.text_backdrop_opacity, 1.0), "Opacity clamps to 1")
	settings.text_backdrop_opacity = -1.0
	_expect(is_equal_approx(settings.text_backdrop_opacity, settings.TEXT_BACKDROP_MIN),
		"Opacity never goes below the 0.3 floor (N-977.3)")

	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	var heard: Array[float] = []
	settings.text_backdrop_opacity_changed.connect(func(opacity: float) -> void: heard.append(opacity))
	settings.text_backdrop_opacity = 0.3
	var plate := hud.interaction_label.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(heard == [0.3], "The change is announced (got %s)" % [heard])
	_expect(is_equal_approx(plate.bg_color.a, 0.3) and is_equal_approx(plate.shadow_color.a, 0.15),
		"At the floor the plate is still drawn")
	settings.text_backdrop_opacity = 1.0
	_expect(is_equal_approx(plate.bg_color.a, 1.0) and is_equal_approx(plate.border_color.a, 1.0),
		"At 1 the plate is solid")
	settings.text_backdrop_opacity = 0.5
	_expect(is_equal_approx(plate.bg_color.a, 0.5) and is_equal_approx(plate.shadow_color.a, 0.25),
		"At 0.5 fill and shadow follow")

	# Not over the crosshair: the plate lives in the bottom bar.
	hud.interaction_label.text = "[ E ]  Probar el prompt"
	hud.interaction_label.visible = true
	await process_frame
	await process_frame
	var centre: Vector2 = hud.hud_layer.get_global_rect().get_center()
	_expect(not hud.interaction_label.get_global_rect().has_point(centre),
		"The plate does not cover the centre of the screen")

	# Options: the slider follows the setting.
	var options: Control = load("res://scripts/ui/options_panel.gd").new()
	root.add_child(options)
	await process_frame
	var slider: HSlider = options._text_backdrop_slider
	_expect(slider != null and is_equal_approx(slider.value, 0.5), "Options slider shows the setting")
	slider.value = 0.25
	_expect(is_equal_approx(settings.text_backdrop_opacity, 0.25), "Moving the slider sets the opacity")
	options.queue_free()

	settings.text_backdrop_opacity = original
	hud.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: the text backdrop follows its setting and stays off the crosshair")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

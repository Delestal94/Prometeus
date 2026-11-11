extends SceneTree
## S-311.100 editor video. Run with MovieWriter and a rendering display:
## Godot --path do-not-drop --rendering-method gl_compatibility --fixed-fps 24 \
##   --write-movie ../art/gel_character/review/s311_100_editor_sliders.avi \
##   --script res://tests/record_gel_editor.gd

const SCREEN_PATH: String = "res://scripts/ui/cosmetics_panel.gd"
const TEMP_PROFILE: String = "res://tests/.s311_100_capture_profile.json"
const PREVIEW_PATH: String = "res://../art/gel_character/review/s311_100_editor_preview.png"
const MOVE_FRAMES: int = 24

var _caption: Label


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Gel editor recording needs a rendering display; omit --headless")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var profile: Node = root.get_node(^"/root/UnlockManager")
	profile.set(&"storage_path", TEMP_PROFILE)
	profile.call(&"reset_profile")
	var settings: Node = root.get_node(^"/root/GameSettings")
	settings.set(&"opaque_gel", false)
	settings.set(&"graphics_quality", WorldQuality.Level.HIGH)
	var panel: Control = load(SCREEN_PATH).new()
	root.add_child(panel)
	_build_caption()
	await _hold(24, "Personalización · cuerpo gelatinoso")
	var body_tab := panel.find_child("Tab_body", true, false) as Button
	if body_tab == null:
		_fail("The customization screen has no Body tab")
		return
	body_tab.pressed.emit()
	await _hold(18, "Seis presets editables")
	var editor: Control = panel.find_child("GelProportionEditor", true, false)
	if editor == null:
		_fail("The Body tab has no proportion editor")
		return
	var picker := editor.find_child("ProportionPreset", true, false) as OptionButton
	if picker == null or picker.item_count != 6:
		_fail("The editor does not expose all six presets")
		return
	for index: int in [0, 2, 4, 5]:
		picker.select(index)
		picker.item_selected.emit(index)
		await _hold(18, "Preset · %s" % picker.get_item_text(index))
	var moves: Array[Dictionary] = [
		{&"node": "Proportion_total_height", &"value": 0.94, &"label": "Altura total"},
		{&"node": "Proportion_general_thickness", &"value": 0.42, &"label": "Grosor general"},
		{&"node": "Proportion_head_size", &"value": 1.12, &"label": "Tamaño de cabeza"},
		{&"node": "Proportion_shoulders", &"value": 0.38, &"label": "Hombros"},
		{&"node": "Proportion_hips", &"value": 0.46, &"label": "Caderas"},
	]
	for move: Dictionary in moves:
		var slider := editor.find_child(String(move.node), true, false) as HSlider
		if slider == null:
			_fail("Missing editor slider %s" % move.node)
			return
		await _move_slider(slider, float(move.value), String(move.label))
	await _hold(36, "Vista previa final · guardado automático")
	if root.get_texture().get_image().save_png(PREVIEW_PATH) != OK:
		_fail("Cannot save the final editor preview")
		return
	_cleanup_profile()
	print("PASS: S-311.100 editor slider recording completed")
	quit(0)


func _build_caption() -> void:
	_caption = Label.new()
	_caption.position = Vector2(28.0, 674.0)
	_caption.add_theme_font_size_override(&"font_size", 20)
	_caption.add_theme_color_override(&"font_color", Color.WHITE)
	_caption.add_theme_color_override(&"font_outline_color", Color("111827"))
	_caption.add_theme_constant_override(&"outline_size", 7)
	root.add_child(_caption)


func _move_slider(slider: HSlider, target: float, label: String) -> void:
	_caption.text = "%s · %.2f" % [label, target]
	slider.grab_focus()
	var start: float = slider.value
	for frame: int in range(MOVE_FRAMES):
		var weight: float = ease(float(frame + 1) / float(MOVE_FRAMES), -2.0)
		slider.value = lerpf(start, target, weight)
		await process_frame
	await _hold(8, "%s · %.2f" % [label, target])


func _hold(frames: int, caption: String) -> void:
	_caption.text = caption
	for _frame: int in range(frames):
		await process_frame


func _cleanup_profile() -> void:
	var path: String = ProjectSettings.globalize_path(TEMP_PROFILE)
	if FileAccess.file_exists(TEMP_PROFILE):
		DirAccess.remove_absolute(path)


func _fail(message: String) -> void:
	push_error(message)
	_cleanup_profile()
	quit(1)

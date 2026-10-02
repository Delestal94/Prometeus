extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_loading_screen.gd
##
## The loading screen between the menu and a level (N-407): the cover has the
## menu's logo (at the menu's size) and art, the mode on the tape in caps, a stage line, a bar and
## a tip, all translated (no key on screen, in Spanish or in English), and no
## tip twice in a row. The menu goes through it: "¡JUGAR!" adds one loader
## and doesn't change the scene on the spot, a second press doesn't add
## another, a connection that fails while loading cancels it and the menu
## stays with the error, and a load that completes lands on the new scene.

const DIR: String = "user://test_loading_screen"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var tiny_path: String = _save_scene("Tiny")

	_check_tips()
	await _check_cover()

	var network: Node = root.get_node(^"/root/NetworkManager")
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	network.disconnect(&"session_ready", Callable(menu, "_on_session_ready"))
	await process_frame

	# A connection that fails the same frame its level starts loading.
	menu.call(&"_go_to_level", tiny_path, "Unirse a la sala")
	var first: LoadingScreen = menu.get(&"_loading")
	_expect(first != null and bool(menu.get(&"_busy")), "Going to a level starts a loading screen and locks the menu")
	menu.call(&"_go_to_level", tiny_path, "Unirse a la sala")
	_expect(menu.get(&"_loading") == first, "A second press doesn't start a second load")
	_expect(current_scene == menu, "The scene doesn't change on the spot")
	menu.call(&"_on_session_failed", "timeout")
	for frame: int in 20:
		await process_frame
	_expect(current_scene == menu and not is_instance_valid(first),
		"A connection that fails while loading cancels it; the menu stays")
	var status: Label = menu.get(&"_status_label")
	_expect(not bool(menu.get(&"_busy")) and status.visible and not status.text.begins_with("UI_"),
		"The menu is usable again and says why (%s)" % status.text)

	# A load that completes lands on the new scene.
	menu.call(&"_go_to_level", tiny_path, "Jugar solo")
	var loader: LoadingScreen = menu.get(&"_loading")
	loader.minimum_seconds = 0.0
	loader.fade_seconds = 0.05
	var frames: int = 0
	while is_instance_valid(loader) and frames < 2000:
		await process_frame
		frames += 1
	_expect(current_scene != null and current_scene.name == "Tiny" and not is_instance_valid(menu),
		"The finished load replaces the menu with the level")
	_expect(not is_instance_valid(loader), "The loading screen is gone once the level is up")

	for file_name: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR).path_join(file_name))
	if _failures == 0:
		print("PASS: the menu reaches a level through a translated loading screen")
	quit(_failures)


func _check_tips() -> void:
	var previous: String = ""
	var seen: Dictionary = {}
	for pick: int in 40:
		var tip: String = LoadingScreen.pick_tip()
		_expect(tip != previous, "No tip twice in a row (%s)" % tip)
		previous = tip
		seen[tip] = true
	_expect(seen.size() >= 4, "The tips rotate (%d different in 40)" % seen.size())
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in LoadingScreen.TIPS:
			_expect(TranslationServer.translate(key) != key, "%s has a %s text" % [key, locale])
	TranslationServer.set_locale("es")


func _check_cover() -> void:
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		var screen := LoadingScreen.new()
		screen.mode_text = "Jugar solo"
		var layer := CanvasLayer.new()
		root.add_child(layer)
		var cover := Control.new()
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(cover)
		screen.call(&"_build_cover", cover)
		screen.call(&"_show_progress", 0.4, SceneLoader.Stage.BUILDING)
		await process_frame
		var logo := cover.find_child("BrandLogo", true, false) as TextureRect
		_expect(logo != null and logo.texture != null, "[%s] The cover shows the logo" % locale)
		_expect(logo != null and logo.size.x <= 421.0 and logo.size.y <= 211.0,
			"[%s] The logo keeps the menu's 420x210, not the texture's 2048 px (got %s)"
				% [locale, logo.size if logo else Vector2.ZERO])
		var bar := cover.find_child("LoadingBar", true, false) as ProgressBar
		_expect(bar != null and is_equal_approx(bar.value, 0.4), "[%s] The bar shows the progress" % locale)
		var stage := cover.find_child("StageLabel", true, false) as Label
		_expect(stage != null and stage.text == TranslationServer.translate("UI_LOADING_STAGE_BUILD")
				and not stage.text.begins_with("UI_"),
			"[%s] The stage line follows the stage, translated (%s)" % [locale, stage.text if stage else ""])
		var tip := cover.find_child("TipLabel", true, false) as Label
		_expect(tip != null and not tip.text.is_empty() and not tip.text.begins_with("UI_"),
			"[%s] A translated tip is shown (%s)" % [locale, tip.text if tip else ""])
		var tape_found: bool = false
		for label: Node in cover.find_children("*", "Label", true, false):
			tape_found = tape_found or (label as Label).text == "JUGAR SOLO"
		_expect(tape_found, "[%s] The mode is on the tape, in caps" % locale)
		_expect(cover.find_child("BumpyBox", true, false) != null, "[%s] The box rides the bar card" % locale)
		screen.free()
		layer.free()
	TranslationServer.set_locale("es")


func _save_scene(scene_name: String) -> String:
	var node := Node3D.new()
	node.name = scene_name
	var packed := PackedScene.new()
	packed.pack(node)
	node.free()
	var path: String = DIR + "/" + scene_name.to_lower() + ".tscn"
	ResourceSaver.save(packed, path)
	return path


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

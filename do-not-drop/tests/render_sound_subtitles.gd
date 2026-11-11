extends SceneTree
## Run with a display (no --headless): Godot --path do-not-drop --script res://tests/render_sound_subtitles.gd
##
## N-965.3: the sound subtitles (N-965) with the queue full, the most the bottom
## of the HUD has to hold at once: an interaction prompt, the at-risk trap's
## standing subtitle and MAX_VISIBLE queued ones (a dog going for a box, another
## player's horn with its arrow, a doorbell). Over three stand-ins for the 3D
## view: light (snow/sky), grass (the road by day, the mid-tone) and dark
## (night); with the text backdrop (N-969) at its default and, in Spanish, also
## at its minimum (N-977.3). Saves user://sound_subtitles_<scene>_<locale>_<pct>.png
## at 1280x720. The stand-ins are gradients with a few bands, not the real scene.

const SCENES: Dictionary = {
	"claro": [Color("f2f6fa"), Color("c9d6e2"), Color("ffffff")],
	"pasto": [Color("9fc3e0"), Color("d9e4ea"), Color("8c9a52")],
	"oscuro": [Color("0a0f1c"), Color("1c2438"), Color("05070d")],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var settings: Node = root.get_node("GameSettings")
	var bus: Node = root.get_node("EventBus")
	var run_manager: Node = root.get_node("RunManager")
	var original_opacity: float = settings.text_backdrop_opacity
	var original_subtitles: bool = settings.sound_subtitles
	var original_locale: String = TranslationServer.get_locale()
	var layer := CanvasLayer.new()
	layer.layer = -10
	root.add_child(layer)
	var sky := TextureRect.new()
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.add_child(sky)
	var ground := ColorRect.new()
	ground.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	ground.offset_top = -260
	layer.add_child(ground)
	# The horn's arrow points at the truck: put one to the right of the camera.
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var truck := Node3D.new()
	truck.add_to_group(&"vehicle")
	root.add_child(truck)
	truck.global_position = Vector3(12.0, 0.0, 0.0)
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	hud.get(&"pause").primary_action()  # leaves the start card: the dashboard shows
	await process_frame
	run_manager.cargo[&"sub_box"] = {"integrity": 35.0, "maximum": 100.0, "state": 1}
	bus.cargo_registered.emit(&"sub_box", "HUD_TRAP_FRAGILE")
	bus.package_state_changed.emit(&"sub_box", 1)
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for scene_name: String in SCENES:
			var cols: Array = SCENES[scene_name]
			var grad := Gradient.new()
			grad.colors = PackedColorArray([cols[0], cols[1]])
			var tex := GradientTexture2D.new()
			tex.gradient = grad
			tex.fill_from = Vector2(0, 0)
			tex.fill_to = Vector2(0, 1)
			sky.texture = tex
			ground.color = cols[2]
			var levels: Array[int] = [roundi(settings.TEXT_BACKDROP_DEFAULT * 100.0)]
			if locale == "es":
				levels.append(roundi(settings.TEXT_BACKDROP_MIN * 100.0))
			for pct: int in levels:
				settings.text_backdrop_opacity = pct / 100.0
				_fill_queue(hud, settings, bus)
				for i: int in 4:
					await process_frame
				await RenderingServer.frame_post_draw
				var path: String = "user://sound_subtitles_%s_%s_%d.png" % [scene_name, locale, pct]
				root.get_texture().get_image().save_png(path)
				print("Saved ", ProjectSettings.globalize_path(path), " lines=",
					String(hud.subtitle_label.text).split("\n").size())
	run_manager.cargo.erase(&"sub_box")
	settings.text_backdrop_opacity = original_opacity
	settings.sound_subtitles = original_subtitles
	TranslationServer.set_locale(original_locale)
	quit(0)


## Empties the queue and fills it again in the current language: the queue keeps
## the text it was pushed with, so a language change needs fresh events. The
## same events every time keep each capture at the full MAX_VISIBLE lines (the
## horn lasts only 1.5 s).
func _fill_queue(hud: CanvasLayer, settings: Node, bus: Node) -> void:
	settings.sound_subtitles = false
	hud.prompts.refresh_sound_subtitle(0.0)
	settings.sound_subtitles = true
	bus.interaction_prompt_changed.emit(TranslationServer.translate("HUD_PROMPT_PICK_UP_PACKAGE"))
	bus.cargo_animal_alert.emit(&"dog", &"box", 3.0, 4.0)
	bus.horn_honked.emit(root.get_node("NetworkManager").local_id() + 6)
	bus.house_delivery_recorded.emit(2, &"delivered_ok", &"p1")
	hud.prompts.refresh_sound_subtitle(0.0)

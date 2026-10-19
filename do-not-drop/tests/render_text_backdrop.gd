extends SceneTree
## Run with a display (no --headless): Godot --path do-not-drop --script res://tests/render_text_backdrop.gd
##
## N-969.3: the HUD's interaction prompt (bottom bar) with the "text backdrop"
## setting at 0, 0.5 and 1.0, over a light stand-in for the 3D view (snow/sky)
## and a dark one (night). Saves user://text_backdrop_<claro|oscuro>_<0|50|100>.png
## at 1280x720. The stand-ins are gradients with a few bands, not the real scene.

const SCENES: Dictionary = {
	"claro": [Color("f2f6fa"), Color("c9d6e2"), Color("ffffff")],
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
	var original: float = settings.text_backdrop_opacity
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
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	hud.get(&"pause").primary_action()  # leaves the start card: the dashboard shows
	await process_frame
	root.get_node("EventBus").interaction_prompt_changed.emit("Agarrar la caja de amarillo")
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
		for pct: int in [0, 50, 100]:
			settings.text_backdrop_opacity = pct / 100.0
			for i: int in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var path: String = "user://text_backdrop_%s_%d.png" % [scene_name, pct]
			root.get_texture().get_image().save_png(path)
			print("Saved ", ProjectSettings.globalize_path(path))
	settings.text_backdrop_opacity = original
	quit(0)

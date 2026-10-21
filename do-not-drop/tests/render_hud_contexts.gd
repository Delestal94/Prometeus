extends SceneTree
## Run with a display (no --headless): Godot --path do-not-drop --script res://tests/render_hud_contexts.gd
##
## N-977.4: the HUD's bottom bar (interaction prompt, controls pill, shortcuts
## pill) in each context -- on foot, carrying a box, at the wheel -- over a light
## stand-in for the 3D view (snow/sky) and a dark one (night), at 1280x720 and
## the default HUD scale. Saves
## user://hud_context_<a_pie|con_caja|al_volante>_<claro|oscuro>.png.
## What to check: at most four shortcuts in the lower pill, every text at about
## 12 px (N-977.2), and the long driver line clear of the cargo card on the left.
## The stand-ins are gradients with a few bands, not the real scene.
##
## The role comes from a stand-in "level" (the HUD reads `local_player.seat_node_path`
## from its parent, HudPrompts._local_role()): a seat path with "DriverEyePoint"
## is the driver's, an empty one is on foot. Nothing in the HUD is set by hand.

const SCENES: Dictionary = {
	"claro": [Color("f2f6fa"), Color("c9d6e2"), Color("ffffff")],
	"oscuro": [Color("0a0f1c"), Color("1c2438"), Color("05070d")],
}
const CONTEXTS: Array[String] = ["a_pie", "con_caja", "al_volante"]
const CARGO_ID: StringName = &"context_box"


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
	var original_scale: float = settings.hud_scale
	var original_help: int = settings.control_help_mode
	settings.hud_scale = settings.HUD_SCALE_DEFAULT
	settings.control_help_mode = settings.ControlHelp.ALWAYS

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

	var level := Node.new()
	level.set_script(_script("extends Node\nvar local_player: Node = null\n"))
	var player := Node.new()
	player.set_script(_script("extends Node\nvar seat_node_path: String = \"\"\n"))
	level.add_child(player)
	level.set(&"local_player", player)
	root.add_child(level)
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	level.add_child(hud)
	await process_frame
	hud.get(&"pause").primary_action()  # leaves the start card: the dashboard shows
	await process_frame
	# One cargo row in the bottom-left card, so the pills are checked against it.
	run_manager.cargo[CARGO_ID] = {"integrity": 100.0, "maximum": 100.0, "state": 0}
	bus.cargo_registered.emit(CARGO_ID, "HUD_TRAP_FRAGILE")
	# The driver's line only shows once there is cargo on the road ("no cargo yet" otherwise).
	var was_running: bool = run_manager.is_running
	run_manager.is_running = true

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
		for context: String in CONTEXTS:
			player.set(&"seat_node_path", "Truck/DriverEyePoint" if context == "al_volante" else "")
			bus.carry_changed.emit(context == "con_caja")
			for i: int in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var path: String = "user://hud_context_%s_%s.png" % [context, scene_name]
			root.get_texture().get_image().save_png(path)
			print("Saved ", ProjectSettings.globalize_path(path))

	bus.carry_changed.emit(false)
	run_manager.is_running = was_running
	run_manager.cargo.erase(CARGO_ID)
	settings.hud_scale = original_scale
	settings.control_help_mode = original_help
	quit(0)


func _script(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	return script

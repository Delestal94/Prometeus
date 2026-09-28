extends SceneTree
## Run without --headless. Saves the care panel's animated "what do I press"
## card (ui/hud/care_prompt_view.gd) under user://, on a dark backdrop like
## the panel's: hold-to-work with the mouse and with a gamepad, idle and
## mid-job, and the bomb's tap sequence pending (keyboard and gamepad),
## after a mistake and solved. Captured at the project's 1280x720 base size.

const CarePromptView = preload("res://scripts/ui/hud/care_prompt_view.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var backdrop := ColorRect.new()
	backdrop.color = Color("26303d")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var views: Array[CarePromptView] = []
	for i: int in 7:
		var view: CarePromptView = CarePromptView.new()
		view.position = Vector2(20 + (i % 3) * 410, 20 + (i / 3) * 200)
		view.size = CarePromptView.CARD_SIZE
		root.add_child(view)
		views.append(view)
	await process_frame
	views[0].show_work(Vector2.LEFT, 0.0, false, false, 0, true, false, "Encintar: mantené clic der. + A (←)")
	views[1].show_work(Vector2.UP, 0.62, true, true, 0, true, false, "Encintar: mantené clic der. + W (↑)")
	views[2].show_work(Vector2.RIGHT, 0.3, false, false, 0, true, true, "Encintar: mantené LT + stick →")
	var sequence: Dictionary = {"steps": [&"up", &"left", &"down"], "index": 0, "mistakes": 0, "solved": 0,
		"seconds": 11.0, "verb": "Desactivar"}
	views[3].show_sequence(sequence, false, "")
	sequence["index"] = 1
	views[3].show_sequence(sequence, false, "Desactivar: tocá A (←), sin clic")
	var mistaken: Dictionary = sequence.duplicate()
	views[4].show_sequence(mistaken, false, "")
	mistaken["index"] = 0
	mistaken["mistakes"] = 1
	mistaken["seconds"] = 4.0
	views[4].show_sequence(mistaken, false, "Desactivar: tocá W (↑), sin clic")
	var solved: Dictionary = sequence.duplicate()
	views[5].show_sequence(solved, false, "")
	solved["index"] = 3
	solved["solved"] = 1
	views[5].show_sequence(solved, false, "")
	var pad_sequence: Dictionary = sequence.duplicate()
	views[6].show_sequence(pad_sequence, true, "")
	pad_sequence["index"] = 2
	views[6].show_sequence(pad_sequence, true, "Desactivar: tocá stick ↓, sin clic")
	for frame: int in 30:
		await process_frame
		if frame in [4, 18, 29]:
			await _shot("render_care_prompt_%02d.png" % frame)
	backdrop.free()
	for view: CarePromptView in views:
		view.free()
	quit(0)


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "user://" + file_name
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))

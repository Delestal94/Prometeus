extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_depot_campaign_board.gd
##
## The depot tells the campaign (N-603, depot_campaign_board.gd):
## - "DÍAS SIN ACCIDENTES" counts runs that end with no ruined box, drops to
##   0 when one comes back broken, and remembers the best streak;
## - the run's delivery photos are saved and pinned up, newest first, never
##   more than MAX_PHOTOS (the oldest files are deleted, not just hidden);
## - the depot builds both boards, they read what's saved, and they update
##   the moment a run ends (EventBus.run_ended).

const Board = preload("res://scripts/gameplay/depot/depot_campaign_board.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clear()
	var log: Dictionary = Board.record_run({"cargo_ruined": 0}, {})
	_expect(int(log.days) == 1 and int(log.best) == 1, "A clean run is one day without accidents (got %s)" % log)
	log = Board.record_run({"cargo_ruined": 0}, {})
	_expect(int(log.days) == 2 and int(log.best) == 2, "Another clean run makes two (got %s)" % log)
	log = Board.record_run({"cargo_ruined": 1}, {})
	_expect(int(log.days) == 0 and int(log.best) == 2, "A ruined box resets the count, the record stays (got %s)" % log)

	var photo := Image.create(64, 40, false, Image.FORMAT_RGB8)
	log = Board.record_run({"cargo_ruined": 0}, {0: photo, 2: photo, 3: null})
	_expect((log.photos as Array).size() == 2, "Each real photo of the run is saved (got %d)" % (log.photos as Array).size())
	var first_batch: Array = (log.photos as Array).duplicate()
	for run: int in range(4):
		log = Board.record_run({"cargo_ruined": 0}, {0: photo, 1: photo})
	var names: Array = log.photos
	_expect(names.size() == Board.MAX_PHOTOS, "The wall keeps the last %d photos (got %d)" % [Board.MAX_PHOTOS, names.size()])
	for gone: String in first_batch:
		_expect(not names.has(gone) and not FileAccess.file_exists(Board.PHOTO_DIR.path_join(gone)),
			"The oldest photos come down and their files are deleted (%s)" % gone)
	for kept: String in names:
		_expect(FileAccess.file_exists(Board.PHOTO_DIR.path_join(kept)), "Every photo on the wall is on disk (%s)" % kept)

	# In the depot.
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	var board: Node = level.find_child("CampaignBoard", true, false)
	_expect(board != null, "The depot puts up the campaign board")
	if board != null:
		var days: Label3D = board.get(&"days_label")
		_expect(days.text == str(int(log.days)), "The sign shows the saved count (%s, saved %d)" % [days.text, int(log.days)])
		var shown: int = 0
		for frame: Sprite3D in board.get(&"photo_frames"):
			if frame.visible and frame.texture != null:
				shown += 1
		_expect(shown == Board.MAX_PHOTOS, "The wall pins up every saved photo (%d)" % shown)
		var sign_node := board.get_node(^"AccidentSign") as Node3D
		_expect((sign_node.global_basis * Vector3.BACK).z > 0.9, "The sign faces into the depot")
		root.get_node(^"/root/EventBus").emit_signal(&"run_ended", 10, {"cargo_ruined": 2})
		_expect(days.text == "0", "The sign updates as a run ends with a ruined box (%s)" % days.text)
	level.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")
	_clear()
	if _failures == 0:
		print("PASS: the depot counts days without accidents and pins up the latest delivery photos")
	quit(_failures)


func _clear() -> void:
	if FileAccess.file_exists(Board.LOG_PATH):
		DirAccess.remove_absolute(Board.LOG_PATH)
	var dir := DirAccess.open(Board.PHOTO_DIR)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

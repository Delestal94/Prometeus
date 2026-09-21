extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_leaderboard.gd
## Covers RunManager's local top-N leaderboard: ranking, capping, the
## new-best flag, and that it actually survives a save/load round trip --
## the point of a leaderboard is that it's still there next time you play.

const TEST_SAVE_PATH: String = "user://test_leaderboard.json"

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var manager: Node = root.get_node(^"/root/RunManager")
	manager.set(&"save_path", TEST_SAVE_PATH)
	_cleanup()
	manager.call(&"_load_leaderboard")

	_expect((manager.get(&"leaderboard") as Array).is_empty(),
		"Starts empty when there's no save file yet")
	_expect(int(manager.call(&"best_score")) == 0, "best_score() is 0 with an empty board")

	var first_best: bool = bool(manager.call(&"_record_score", 100))
	_expect(first_best, "The very first score recorded is trivially a new best")
	_expect(int(manager.call(&"best_score")) == 100, "Board tracks the score just recorded")

	var second_best: bool = bool(manager.call(&"_record_score", 60))
	_expect(not second_best, "A lower score than the current best isn't a new best")
	_expect(int(manager.call(&"best_score")) == 100, "Best score doesn't drop for a worse run")

	var third_best: bool = bool(manager.call(&"_record_score", 250))
	_expect(third_best, "A higher score than the current best is flagged as a new best")

	var board: Array = manager.get(&"leaderboard")
	_expect(board.size() == 3 and int(board[0]["score"]) == 250 and int(board[1]["score"]) == 100 and int(board[2]["score"]) == 60,
		"Sorted best-first regardless of the order scores came in")

	for extra: int in range(15):
		manager.call(&"_record_score", 10 + extra)
	var capped: Array = manager.get(&"leaderboard")
	_expect(capped.size() == int(manager.get(&"MAX_LEADERBOARD_ENTRIES")),
		"Never grows past MAX_LEADERBOARD_ENTRIES, even after many runs")
	_expect(int(capped[0]["score"]) == 250, "The all-time best survives the cap")

	# A fresh RunManager-shaped read (via _load_leaderboard, not the in-memory
	# array) is the only way to actually prove this persists across sessions.
	manager.set(&"leaderboard", [])
	manager.call(&"_load_leaderboard")
	var reloaded: Array = manager.get(&"leaderboard")
	_expect(reloaded.size() == capped.size() and int(reloaded[0]["score"]) == 250,
		"Reloading from disk restores the same ranked board")

	_cleanup()
	if _failures == 0:
		print("PASS: local leaderboard ranks, caps, flags new bests, and persists to disk")
	quit(_failures)


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

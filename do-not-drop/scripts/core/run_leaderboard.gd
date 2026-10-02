extends RefCounted
## The local high scores (N-225.5), split out of run_manager.gd: the board, which stays on the autoload next to
## its save path, goes in and out of these static helpers. Local-only for now (no accounts/backend yet).

const SAFE_JSON = preload("res://modules/persistence/safe_json.gd")
const MODE_DELIVERY: StringName = &"delivery"
const MAX_LEADERBOARD_ENTRIES: int = 10


## Local top-N high scores, kept across runs and across app restarts. Every
## finished run gets recorded (even a 0-point failure) -- sorting keeps the
## list meaningful on its own, no need to filter before inserting.
## Entries written before endless existed have no "mode" key -- treated as
## MODE_DELIVERY so old saves keep working instead of vanishing from the board.
static func best_score(board: Array, mode: StringName) -> int:
	for entry: Dictionary in board:
		if StringName(entry.get("mode", MODE_DELIVERY)) == mode:
			return int(entry["score"])
	return 0


## Adds a finished run to the board (in place), sorted best-first, and returns the trimmed board.
static func add(board: Array, score: int, mode: StringName, crew_size: int) -> Array:
	board.append({
		"score": score,
		"date": Time.get_date_string_from_system(),
		"mode": mode,
		"crew_size": crew_size,
	})
	board.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	return trim(board)


## Caps MAX_LEADERBOARD_ENTRIES per mode, not across the whole array -- a
## flat global cap would let endless's distance-based scores (a completely
## different scale from delivery's ~0-360) crowd delivery runs out of the
## saved board entirely, or vice versa. Relies on the array already being
## score-sorted (always true here, called right after sort_custom above),
## so each mode's kept slice is naturally its own top N.
static func trim(board: Array) -> Array:
	var kept: Array = []
	var counts: Dictionary = {}
	for entry: Dictionary in board:
		var mode: StringName = StringName(entry.get("mode", MODE_DELIVERY))
		var count: int = int(counts.get(mode, 0))
		if count < MAX_LEADERBOARD_ENTRIES:
			kept.append(entry)
			counts[mode] = count + 1
	return kept


## The saved board (after bringing over the one from before the game was renamed); [] when there is none.
static func load_board(save_path: String) -> Array:
	LegacyUserData.migrate()
	return SAFE_JSON.read(save_path, [])


static func save_board(save_path: String, board: Array) -> void:
	if not SAFE_JSON.write(save_path, board):
		push_warning("No se pudo guardar el leaderboard: " + save_path)

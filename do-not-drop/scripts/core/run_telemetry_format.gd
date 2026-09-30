extends RefCounted
## Pure helpers for the run log (run_telemetry.gd): no state, no autoloads, so
## tests and the file format can lean on them directly.

## Bump when a field changes meaning, so tools/telemetry-summary.py can tell
## old files from new ones.
const FORMAT_VERSION: int = 1


## "HUD_TRAP_GROWING_WEIGHT" -> "growing_weight": the trap's id, which is the
## same in every language (the name key is what travels over the network).
static func trap_id(name_key: String) -> String:
	if name_key.is_empty():
		return "unknown"
	# Two trims rather than one "HUD_..." literal: the translation test reads any
	# such string in scripts as a key that must exist in the table.
	return name_key.trim_prefix("HUD_").trim_prefix("TRAP_").to_lower()


## "2026-09-30_15-42-10": date and time, sortable, and free of the characters
## Windows refuses in a file name (":" above all).
static func file_stem(datetime: Dictionary) -> String:
	return "%04d-%02d-%02d_%02d-%02d-%02d" % [int(datetime.get("year", 0)), int(datetime.get("month", 0)),
			int(datetime.get("day", 0)), int(datetime.get("hour", 0)), int(datetime.get("minute", 0)),
			int(datetime.get("second", 0))]

class_name RunTally
extends RefCounted
## What a run got done so far, from the state every peer already keeps
## (RunManager's delivery record and cargo, the distance the level tracks),
## handed in by whoever reads RunManager (hud_pause.gd): run_manager.gd names
## autoloads, so this file can't preload it as a type (a --script would
## compile it before they exist).
## A client whose host drops mid-run has no results from the host coming:
## this is what its disconnect screen shows instead (N-222).


const RUN_DELIVERIES = preload("res://scripts/core/run_deliveries.gd")


## Whether a run is on the go or cut short: started (`elapsed_seconds` > 0),
## and no `results` from anyone. Read-only, so the disconnect screen can ask
## this whether or not the level already stopped the run (level_common.gd).
static func unfinished(results: Dictionary, elapsed_seconds: float) -> bool:
	return results.is_empty() and elapsed_seconds > 0.0


## The tally of a run as it stands, from RunManager's record. Houses count
## the doors that got their box; boxes, the ones still in one piece, handed
## over or aboard.
static func count(deliveries: Array, cargo: Dictionary, endless: bool, expected_houses: int,
		distance: float, elapsed_seconds: float) -> Dictionary:
	var delivered: int = 0
	for entry: Dictionary in deliveries:
		if RUN_DELIVERIES.handed_over(StringName(entry.get("outcome", &""))):
			delivered += 1
	var intact: int = 0
	for entry: Dictionary in cargo.values():
		if int(entry.get("state", 0)) == ITrapBehavior.TrapState.OK:
			intact += 1
	return {
		"endless": endless,
		"houses_delivered": delivered,
		"houses_expected": maxi(expected_houses, delivered),
		"cargo_intact": intact,
		"cargo_total": cargo.size(),
		"distance": distance,
		"elapsed_seconds": elapsed_seconds,
	}


## One line for the disconnect screen, in this peer's language.
static func describe(tally: Dictionary) -> String:
	var seconds: int = roundi(float(tally.get("elapsed_seconds", 0.0)))
	var clock: String = "%d:%02d" % [floori(seconds / 60.0), seconds % 60]
	if bool(tally.get("endless", false)):
		return TranslationServer.translate("HUD_HOST_GONE_TALLY_ENDLESS") % [
				roundi(float(tally["distance"])), clock, int(tally["cargo_intact"]), int(tally["cargo_total"])]
	return TranslationServer.translate("HUD_HOST_GONE_TALLY") % [
			int(tally["houses_delivered"]), int(tally["houses_expected"]), int(tally["cargo_intact"]),
			int(tally["cargo_total"]), roundi(float(tally["distance"])), clock]

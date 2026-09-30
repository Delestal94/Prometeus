class_name RunTally
extends RefCounted
## What a run got done so far, from the state every peer already keeps
## (RunManager's delivery record and cargo, the distance the level tracks).
## A client whose host drops mid-run has no results from the host coming:
## this is what its disconnect screen shows instead (N-222).


## Stops the local copy of a run cut short by losing the host and returns its
## tally, or {} when no run was going. Stopping matters: once the session is
## gone this peer is "offline, host" and would otherwise start scoring and
## ending the run on its own, putting a results screen over the disconnect one.
static func interrupt() -> Dictionary:
	var run: Node = Engine.get_main_loop().root.get_node_or_null(^"/root/RunManager")
	if run == null or not bool(run.get(&"is_running")):
		return {}
	run.set(&"is_running", false)
	return of(run)


## The tally of `run` (RunManager, or anything with its fields) as it stands.
## Houses count the doors that got their box; boxes, the ones still in one
## piece, handed over or aboard.
static func of(run: Object) -> Dictionary:
	var delivered: int = 0
	for entry: Dictionary in run.get(&"deliveries"):
		var outcome := StringName(entry.get("outcome", &""))
		if outcome != &"missed" and outcome != &"lost":
			delivered += 1
	var cargo: Dictionary = run.get(&"cargo")
	var intact: int = 0
	for entry: Dictionary in cargo.values():
		if int(entry.get("state", 0)) == ITrapBehavior.TrapState.OK:
			intact += 1
	return {
		"endless": StringName(run.get(&"current_mode")) == &"endless",
		"houses_delivered": delivered,
		"houses_expected": maxi(int(run.get(&"expected_houses")), delivered),
		"cargo_intact": intact,
		"cargo_total": cargo.size(),
		"distance": float(run.get(&"current_distance")),
		"elapsed_seconds": float(run.get(&"elapsed_seconds")),
	}


## One line for the disconnect screen, in this peer's language.
static func describe(tally: Dictionary) -> String:
	var seconds: int = roundi(float(tally.get("elapsed_seconds", 0.0)))
	var clock: String = "%d:%02d" % [seconds / 60, seconds % 60]
	if bool(tally.get("endless", false)):
		return TranslationServer.translate("HUD_HOST_GONE_TALLY_ENDLESS") % [roundi(float(tally["distance"])), clock,
				int(tally["cargo_intact"]), int(tally["cargo_total"])]
	return TranslationServer.translate("HUD_HOST_GONE_TALLY") % [int(tally["houses_delivered"]), int(tally["houses_expected"]),
			int(tally["cargo_intact"]), int(tally["cargo_total"]), roundi(float(tally["distance"])), clock]

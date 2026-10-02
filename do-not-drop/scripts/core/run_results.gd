extends RefCounted
## What the results screen is told besides the score (N-225.5), split out of run_manager.gd: one row per promised
## stop, the route event of the run and the stories of what happened. Static and pure over the autoload's state,
## which stays there; nothing here names an autoload.

## What the results' rescue stories call each content (strings_ui.csv keys).
const RESCUE_NAMES: Dictionary = {&"fragile": "HUD_RESCUE_VASE", &"balance": "HUD_RESCUE_CAKE",
	&"noisy": "HUD_RESCUE_HEN", &"growing_weight": "HUD_RESCUE_HEAVY", &"liquid": "HUD_RESCUE_LIQUID",
	&"explosive": "HUD_RESCUE_EXPLOSIVE", &"hostile": "HUD_RESCUE_CREATURE"}


## One stable row per promised stop. A missing record is still useful result
## data: it means that house never received its order.
static func delivery_rows(expected_houses: int, house_assignments: Array, cargo_names: Dictionary,
		deliveries: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for house: int in range(expected_houses):
		var package_id: StringName = &""
		# Translation keys: the results travel to clients, and hud_results
		# translates them on each peer.
		var trap_name: String = "HUD_RESULT_PACKAGE_FALLBACK"
		if house < house_assignments.size():
			var assignment: Array = house_assignments[house]
			if not assignment.is_empty():
				package_id = StringName(assignment[0])
			if assignment.size() > 1:
				trap_name = String(assignment[1])
		trap_name = String(cargo_names.get(package_id, trap_name))
		var outcome: StringName = &"missed"
		var has_photo: bool = false
		for delivery: Dictionary in deliveries:
			if int(delivery["house"]) == house:
				outcome = StringName(delivery["outcome"])
				has_photo = bool(delivery["photo"])
				if package_id.is_empty():
					package_id = StringName(delivery["package_id"])
				break
		rows.append({
			"house": house,
			"package_id": package_id,
			"trap": trap_name,
			"outcome": outcome,
			"photo": has_photo,
		})
	return rows


## The route event drawn for the run, for the results: {} when none was. `definition` is its entry in the
## route events' catalog and `success` whether it was resolved well.
static func route_event(event_id: StringName, definition: Dictionary, success: bool) -> Dictionary:
	if event_id.is_empty():
		return {}
	return {
		"id": event_id,
		"title": String(definition.get("title", String(event_id))),
		"success": success,
	}


## One line per box that needed rescuing, for the results screen to tell
## the run's story ("Jarrón recompuesto", "Gallina sustituida por un juguete").
static func rescue_stories(cargo: Dictionary) -> Array[String]:
	var stories: Array[String] = []
	for entry: Dictionary in cargo.values():
		var care: Dictionary = entry.get("care", {})
		var kind := StringName(care.get("kind", ""))
		var label: String = _text(String(RESCUE_NAMES.get(kind, "HUD_RESCUE_PACKAGE")))
		if bool(care.get("substituted", false)):
			stories.append(_text("HUD_STORY_SUBSTITUTED_TOY" if kind == &"noisy" else "HUD_STORY_SUBSTITUTED") % label)
		elif int(care.get("repairs", 0)) > 0:
			stories.append(_text("HUD_STORY_REPAIRED") % [label, int(care.get("repairs", 0))])
		elif int(entry.get("state", 0)) == ITrapBehavior.TrapState.RUINED and not care.is_empty():
			stories.append(_text("HUD_STORY_LOST") % label)
	return stories


## Lines other systems add to the run's story, from every node in the
## "run_stories" group with result_stories() (N-214.4: the van's faults).
static func world_stories(tree: SceneTree) -> Array[String]:
	var stories: Array[String] = []
	for source: Node in tree.get_nodes_in_group(&"run_stories"):
		if source.has_method(&"result_stories"):
			stories.append_array(source.call(&"result_stories"))
	return stories


## The player's language for a strings_ui.csv key (what tr() does on a node; statics have no tr()).
static func _text(key: String) -> String:
	return String(TranslationServer.translate(key))

extends RefCounted
## The scene-side pieces of bringing a late joiner up to date (N-225.5), split out of run_manager.gd: the host's
## session snapshot (send_session_state) and the joiner's application of it (_receive_session_state) stay on the
## autoload, which owns the state and the RPC; these static helpers read and change the depot and the boxes in
## the loaded level, which is all that is not the autoload's own state.


## Each box's name key, even delivered or lost ones; the joiner translates it (N-805).
static func names(cargo: Dictionary, cargo_names: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: StringName in cargo:
		result[id] = String(cargo_names.get(id, "HUD_RESULT_PACKAGE_FALLBACK"))
	return result


## Whether the depot's door is open in this level (true when there is no depot to ask).
static func depot_door_open(scene: Node) -> bool:
	var depot: Node = scene.get(&"depot") as Node if scene != null else null
	if depot != null and depot.get(&"door") != null:
		return bool(depot.get(&"door").get(&"is_open"))
	return true


## The host's door was already closed when this peer arrived: close it here too, without the sound.
static func close_depot_door(scene: Node) -> void:
	var depot: Node = scene.get(&"depot") as Node if scene != null else null
	if depot != null and depot.get(&"door") != null:
		depot.get(&"door").call(&"set_open", false, false)


## Frees the boxes already handed over at a door this run (paths relative to `from`): they're scene nodes, not
## spawned ones, so a joiner's freshly loaded level still has them.
static func free_consumed(from: Node, paths: Array) -> void:
	for path: String in paths:
		var package: Node = from.get_node_or_null(NodePath(path))
		if package != null:
			package.remove_from_group(&"cargo")
			package.queue_free()

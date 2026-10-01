extends Node
## What the mud did to this run, for the results screen (N-108). MudSegments
## come and go (Endless frees the ones behind), so the lines they leave live
## here, on the route or streamer that owns them, and RunManager reads them
## through the "run_stories" group like the van's faults (N-214.4). Host-only
## in practice: the host builds the results and sends them to everyone.

var stories: Array[String] = []


func _ready() -> void:
	add_to_group(&"run_stories")
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null and bus.has_signal(&"run_started"):
		bus.connect(&"run_started", _on_run_started)


func _on_run_started(_route_id: StringName, _players: Array) -> void:
	stories.clear()


func add_story(line: String) -> void:
	stories.append(line)


func result_stories() -> Array[String]:
	return stories.duplicate()

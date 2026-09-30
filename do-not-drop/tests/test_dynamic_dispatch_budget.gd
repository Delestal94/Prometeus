extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_dynamic_dispatch_budget.gd
##
## N-224: calls by name (`.call(&"…")`, `.callv(`, `.get(&"…")`) and
## `/root/` paths only break at runtime when something is renamed. The files
## already moved to typed references keep them low:
## - each file in BUDGETS has at most its budget of each kind (a ratchet:
##   lower the number when a file drops more, never raise it);
## - the typed autoload handles in crew_progression.gd (NETWORK_MANAGER,
##   RUN_MANAGER, ROUTE_EVENT_MANAGER) are the scripts the autoloads really
##   run: `get_node_or_null(...) as <handle>` would quietly give null if an
##   autoload moved to another script, and the crew would stop seeing the
##   network, the route events and the delivery photos.

## path -> {kind: max}. Kinds: "call", "callv", "get", "root".
const BUDGETS: Dictionary = {
	# The one .call left relays merit/card changes through EventBus, which a
	# test may replace with a plain Node (event_bus); the .callv emits a
	# signal chosen by name. The /root/ lookups are the null-safe autoload
	# handles (EventBus x3, NetworkManager, RunManager, RouteEventManager).
	"res://scripts/core/crew_progression.gd": {"call": 1, "callv": 1, "get": 0, "root": 6},
}
const PATTERNS: Dictionary = {
	"call": "\\.call\\(&?\"",
	"callv": "\\.callv\\(",
	"get": "\\.get\\(&\"",
	"root": "\"/root/",
}
## crew_progression.gd constant -> autoload node it stands for.
const CREW_HANDLES: Dictionary = {
	"NETWORK_MANAGER": "/root/NetworkManager",
	"RUN_MANAGER": "/root/RunManager",
	"ROUTE_EVENT_MANAGER": "/root/RouteEventManager",
}

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path: String in BUDGETS:
		var source: String = FileAccess.get_file_as_string(path)
		_expect(not source.is_empty(), "%s can be read" % path)
		var budget: Dictionary = BUDGETS[path]
		for kind: String in budget:
			var found: int = RegEx.create_from_string(PATTERNS[kind]).search_all(source).size()
			_expect(found <= int(budget[kind]),
					"%s has %d %s by name (budget %d): use a typed reference" % [path, found, kind, budget[kind]])

	var crew: Node = root.get_node_or_null(^"/root/CrewProgression")
	_expect(crew != null, "The CrewProgression autoload is loaded")
	if crew != null:
		var constants: Dictionary = (crew.get_script() as Script).get_script_constant_map()
		for handle: String in CREW_HANDLES:
			var autoload: Node = root.get_node_or_null(NodePath(CREW_HANDLES[handle]))
			_expect(autoload != null, "%s is loaded" % CREW_HANDLES[handle])
			_expect(autoload != null and constants.get(handle) == autoload.get_script(),
					"CrewProgression.%s is the script %s runs" % [handle, CREW_HANDLES[handle]])

	if _failures == 0:
		print("PASS: files moved to typed references stay within their by-name budget")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

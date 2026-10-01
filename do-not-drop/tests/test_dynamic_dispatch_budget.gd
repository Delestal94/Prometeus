extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_dynamic_dispatch_budget.gd
##
## N-224: calls by name (`.call(&"…")`, `.callv(`, `.get(&"…")`) and
## `/root/` paths only break at runtime when something is renamed. The files
## already moved to typed references keep them low:
## - each file in BUDGETS has at most its budget of each kind (a ratchet:
##   lower the number when a file drops more, never raise it);
## - the typed autoload handles (HANDLES: crew_progression.gd's NETWORK_MANAGER,
##   RUN_MANAGER, ROUTE_EVENT_MANAGER; route_event_manager.gd's
##   CREW_PROGRESSION, NETWORK_MANAGER, RUN_MANAGER) are the scripts the
##   autoloads really run: `get_node_or_null(...) as <handle>` would quietly
##   give null if an autoload moved to another script, and the crew would stop
##   seeing the network, the route events and the delivery photos, or the route
##   events would stop paying and fining;
## - depot.gd is no autoload, so its handles (SCRIPT_HANDLES: NETWORK_MANAGER,
##   RUN_MANAGER, CREW_PROGRESSION, UNLOCK_MANAGER) are checked against the
##   script loaded from its path: each must be the script its autoload runs, or
##   `as <handle>` would give null and the depot would stop seeing the
##   network (host, seed), the crew's money and supplies, and the unlocks.

## path -> {kind: max}. Kinds: "call", "callv", "get", "root".
const BUDGETS: Dictionary = {
	# Two .call left: one relays merit/card changes through EventBus, which a
	# test may replace with a plain Node (event_bus); the other asks the truck
	# for its pay_multiplier (N-114): vehicle.gd names the autoloads, so this
	# autoload cannot preload it as a typed reference. The .callv emits a
	# signal chosen by name. The /root/ lookups are the null-safe autoload
	# handles (EventBus x3, NetworkManager, RunManager, RouteEventManager).
	"res://scripts/core/crew_progression.gd": {"call": 2, "callv": 1, "get": 0, "root": 6},
	# The two .call left are the EventBus relays (team money and route events),
	# by name for the same reason. The /root/ lookups are the null-safe handles
	# (EventBus, NetworkManager, RunManager, CrewProgression).
	"res://scripts/core/route_event_manager.gd": {"call": 2, "callv": 0, "get": 0, "root": 4},
	# One .call left: the EventBus relay of the depot notices, by name because
	# a test may replace EventBus with a plain Node (_bus()). One .get left: the
	# seat_node_path of the players in the "player" group, because tests put
	# Node3D fakes there and `as Player` would drop them. The /root/ lookups
	# are the null-safe autoload accessors (NetworkManager, CrewProgression,
	# UnlockManager, RunManager, EventBus).
	"res://scripts/gameplay/depot/depot.gd": {"call": 1, "callv": 0, "get": 1, "root": 5},
}
const PATTERNS: Dictionary = {
	"call": "\\.call\\(&?\"",
	"callv": "\\.callv\\(",
	"get": "\\.get\\(&\"",
	"root": "\"/root/",
}
## autoload node -> {constant in the script it runs: autoload it stands for}.
const HANDLES: Dictionary = {
	"/root/CrewProgression": {
		"NETWORK_MANAGER": "/root/NetworkManager",
		"RUN_MANAGER": "/root/RunManager",
		"ROUTE_EVENT_MANAGER": "/root/RouteEventManager",
	},
	"/root/RouteEventManager": {
		"CREW_PROGRESSION": "/root/CrewProgression",
		"NETWORK_MANAGER": "/root/NetworkManager",
		"RUN_MANAGER": "/root/RunManager",
	},
}
## script that is no autoload -> {constant: autoload it stands for}.
const SCRIPT_HANDLES: Dictionary = {
	"res://scripts/gameplay/depot/depot.gd": {
		"NETWORK_MANAGER": "/root/NetworkManager",
		"RUN_MANAGER": "/root/RunManager",
		"CREW_PROGRESSION": "/root/CrewProgression",
		"UNLOCK_MANAGER": "/root/UnlockManager",
	},
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

	for owner_path: String in HANDLES:
		var owner_node: Node = root.get_node_or_null(NodePath(owner_path))
		_expect(owner_node != null, "The %s autoload is loaded" % owner_path)
		if owner_node == null:
			continue
		_check_handles(owner_path, owner_node.get_script() as Script, HANDLES[owner_path])

	for script_path: String in SCRIPT_HANDLES:
		var script: Script = load(script_path) as Script
		_expect(script != null, "%s loads" % script_path)
		if script != null:
			_check_handles(script_path, script, SCRIPT_HANDLES[script_path])

	if _failures == 0:
		print("PASS: files moved to typed references stay within their by-name budget")
	quit(_failures)


func _check_handles(owner_name: String, script: Script, handles: Dictionary) -> void:
	var constants: Dictionary = script.get_script_constant_map()
	for handle: String in handles:
		var target_path: String = handles[handle]
		var autoload: Node = root.get_node_or_null(NodePath(target_path))
		_expect(autoload != null, "%s is loaded" % target_path)
		_expect(autoload != null and constants.get(handle) == autoload.get_script(),
				"%s.%s is the script %s runs" % [owner_name, handle, target_path])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

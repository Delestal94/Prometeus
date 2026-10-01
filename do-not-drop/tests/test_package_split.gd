extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_package_split.gd
##
## package.gd was split by responsibility (N-225.4: package_handling.gd, package_tending.gd, package_impacts.gd,
## next to package_rescue.gd) and must stay split without changing what the rest of the project, or the network,
## sees of the box:
## - the RPC surface of DeliveryPackage is exactly the table below (name, rpc mode, transfer mode, call_local,
##   channel), taken from the file before the split. Godot numbers RPCs by name, so a renamed or re-moded one
##   would make peers disagree on the wire; an @rpc has to stay in the node's own script;
## - every method the rest of the code (scripts/, tests/, modules/) calls on a box still exists, split-out
##   helpers or not (the wrappers in package.gd), the static ones included;
## - the helper classes exist and package.gd stays under MAX_PACKAGE_LINES lines, far from the lint limit
##   (1000), so it doesn't grow back to the edge.

## The script is loaded when the test runs: with --script this file compiles before the autoloads exist, and
## naming DeliveryPackage here would pull them in too early (see test_assist.gd).
const PACKAGE_SCENE: String = "res://scenes/gameplay/package/package.tscn"
const PACKAGE_SCRIPT: String = "res://scripts/gameplay/package/package.gd"
const MAX_PACKAGE_LINES: int = 700

## name -> [rpc_mode, call_local, transfer_mode, channel]. rpc_mode: 1 any_peer, 2 authority. transfer_mode:
## 1 unreliable_ordered, 2 reliable.
const RPCS: Dictionary = {
	"request_set_open": [1, true, 2, 0],
	"submit_tender_input": [1, true, 1, 0],
	"request_assist": [1, true, 2, 0],
	"request_stop_assist": [1, true, 2, 0],
	"submit_carry_transform": [1, true, 1, 0],
	"request_transfer": [1, true, 2, 0],
	"request_drop": [1, true, 2, 0],
	"request_lap_toggle": [1, true, 2, 0],
	"_remote_consume": [2, false, 2, 0],
	"submit_care_input": [1, true, 1, 0],
}
## Methods the project calls on a box from outside package.gd (instance methods).
const INSTANCE_METHODS: Array[String] = [
	"_accept_tender_input", "set_tender", "set_assistant", "can_assist", "assist_available", "run_state",
	"assist_prompt", "_has_fresh_input", "_player_for_peer", "_refresh_combined_input", "_reach_origin",
	"_award_milestone", "_award_pending_trap_milestones", "_report_change", "_release_carrier",
	"_ride_along_if_aboard", "_is_run_active", "_trap_kind", "_find_vehicle", "_publish_net_state",
	"_publish_care", "_on_body_entered", "_integrate_forces", "_emit_event", "apply_impact", "set_held",
	"take_by", "is_aboard", "drop_loose", "place_at", "consume", "release_mount", "initialize_trap",
	"predict_carry", "set_open", "spill_contents", "report_to_run", "mark_lost", "content_definition",
	"hint_text", "get_hint", "get_half_extents", "apply_external_damage", "apply_parasite_damage",
	"collect_salvage", "delivery_assessment", "peer_left", "request_lap_toggle",
]
## Static ones: the tests call them on the class.
const STATIC_METHODS: Array[String] = ["_reach_origin", "_has_useful_input"]
## The split-out helpers.
const HELPERS: Array[String] = [
	"package_handling", "package_tending", "package_impacts", "package_rescue",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var script: GDScript = load(PACKAGE_SCRIPT) as GDScript
	_expect(script != null, "package.gd loads")
	var scene: PackedScene = load(PACKAGE_SCENE) as PackedScene
	_expect(scene != null, "package.tscn loads")
	if script == null or scene == null:
		quit(1)
		return
	var box: Node = scene.instantiate()
	_check_rpcs(script)
	_check_methods(box, script)
	_check_size()
	box.free()
	if _failures == 0:
		print("PASS: package.gd keeps its RPCs and the methods the project uses, and stays under %d lines"
				% MAX_PACKAGE_LINES)
	quit(_failures)


func _check_rpcs(script: GDScript) -> void:
	var config: Dictionary = script.get_rpc_config()
	for rpc_name: String in RPCS:
		_expect(config.has(StringName(rpc_name)), "%s is still an @rpc of the box" % rpc_name)
		if not config.has(StringName(rpc_name)):
			continue
		var found: Dictionary = config[StringName(rpc_name)]
		var expected: Array = RPCS[rpc_name]
		var actual: Array = [int(found.get("rpc_mode", -1)), bool(found.get("call_local", false)),
				int(found.get("transfer_mode", -1)), int(found.get("channel", 0))]
		_expect(actual == expected, "%s has rpc_mode, call_local, transfer_mode, channel %s (got %s)"
				% [rpc_name, expected, actual])
	_expect(config.size() == RPCS.size(), "The box has exactly %d RPCs (got %d: %s)"
			% [RPCS.size(), config.size(), config.keys()])


func _check_methods(box: Node, script: GDScript) -> void:
	for method: String in INSTANCE_METHODS:
		_expect(box.has_method(StringName(method)), "The box still has %s()" % method)
	for method: String in STATIC_METHODS:
		var found: bool = false
		for entry: Dictionary in script.get_script_method_list():
			if entry.name == method and (int(entry.flags) & METHOD_FLAG_STATIC) != 0:
				found = true
		_expect(found, "The box still has the static %s()" % method)
	for helper: String in HELPERS:
		var path: String = "res://scripts/gameplay/package/%s.gd" % helper
		_expect(load(path) is GDScript, "%s loads" % path)


func _check_size() -> void:
	var lines: int = FileAccess.get_file_as_string(PACKAGE_SCRIPT).split("\n").size()
	_expect(lines <= MAX_PACKAGE_LINES, "package.gd has %d lines, at most %d: a new responsibility goes in its own file"
			% [lines, MAX_PACKAGE_LINES])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

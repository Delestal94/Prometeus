extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_package_feedback_split.gd
##
## package_feedback.gd (the box's presentation component, PackageFeedback) was split by responsibility
## (N-225.5: package_trap_visuals.gd, package_box_dressing.gd and package_box_motion.gd, static helpers over
## the component's state like package_rescue.gd is over the box's) and must stay split without changing what
## the rest of the project sees of it:
## - every method, variable and constant that other scripts or tests read on the component still exists with
##   the same name in package_feedback.gd (the state of the helpers lives there; tests read it by name);
## - the pieces each trap builds on the Box keep their names and their order (tests look them up by name);
## - the helper classes exist and package_feedback.gd stays under MAX_FEEDBACK_LINES lines, far from the lint
##   limit (1000), so it doesn't grow back to the edge.

const PACKAGE_SCENE: String = "res://scenes/gameplay/package/package.tscn"
const FEEDBACK_SCRIPT: String = "res://scripts/gameplay/package/package_feedback.gd"
const MAX_FEEDBACK_LINES: int = 700

## Methods other code calls on the component (by name).
const METHODS: Array[String] = [
	"_ready", "_process", "_apply_identity", "highlight", "set_local_grip", "grip_glow", "_set_state",
	"_update_box_scale", "_on_package_state_changed", "_on_package_ruined", "_on_integrity_changed",
	"_on_package_damaged", "_on_package_collision", "_on_package_placed",
]
## Variables tests read or write on the component.
const VARIABLES: Array[String] = [
	"_material", "_outline", "_package", "_bounce_time", "_impact_shake_strength", "_growth_scale",
	"_wobble_nodes", "_dent_pieces", "_shipping_label", "_chime_player", "_groan_player", "_creak_player",
	"_creak_countdown", "_liquid_slosh_player", "_liquid_puddle", "_explosive_tick_player",
	"_explosive_display", "_hostile_hiss_player", "_hostile_eyes", "_cushion_ring", "_ruin_player",
]
## Constants read from the script.
const CONSTANTS: Array[String] = ["CONFETTI_COLORS", "CONFETTI_LIFETIME", "CREAK_INTERVAL_MAX", "TRAP_SOUND_LEVELS_DB"]
## The split-out helpers.
const HELPERS: Array[String] = ["package_trap_visuals", "package_box_dressing", "package_box_motion"]
## trap id -> the node its pieces add to the Box (see _check_box_pieces()).
const TRAP_NODES: Dictionary = {
	&"hostile": "HostileEyes",
	&"fragile": "CushionRing",
	&"liquid": "LiquidPuddle",
	&"explosive": "ExplosiveCountdown",
}
## The Box's named children of a Frágil package, in the order the identity adds them (the unnamed ones, the
## flaps' and the disguise's, are left out).
const FRAGILE_BOX_ORDER: Array[String] = [
	"Model", "PackingTape", "CardboardFlap", "ShelfStrap", "ShippingLabel", "Scribble", "AccessibleState",
	"VerbIcon", "CushionRing", "DamageDents", "HighlightOutline", "Contents",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var script: GDScript = load(FEEDBACK_SCRIPT) as GDScript
	_expect(script != null, "package_feedback.gd loads")
	if script == null:
		quit(1)
		return
	_check_members(script)
	_check_helpers()
	_check_size()
	await _check_box_pieces()
	if _failures == 0:
		print("PASS: package_feedback.gd keeps what the project reads of it, builds the same pieces and stays under "
				+ "%d lines" % MAX_FEEDBACK_LINES)
	quit(_failures)


func _check_members(script: GDScript) -> void:
	var methods: Array[String] = []
	for entry: Dictionary in script.get_script_method_list():
		methods.append(String(entry.name))
	for method: String in METHODS:
		_expect(methods.has(method), "PackageFeedback still has %s()" % method)
	var variables: Array[String] = []
	for entry: Dictionary in script.get_script_property_list():
		variables.append(String(entry.name))
	for variable: String in VARIABLES:
		_expect(variables.has(variable), "PackageFeedback still has the variable %s" % variable)
	var constants: Dictionary = script.get_script_constant_map()
	for constant: String in CONSTANTS:
		_expect(constants.has(constant), "PackageFeedback still has the constant %s" % constant)


func _check_helpers() -> void:
	for helper: String in HELPERS:
		var path: String = "res://scripts/gameplay/package/%s.gd" % helper
		_expect(load(path) is GDScript, "%s loads" % path)


func _check_size() -> void:
	var lines: int = FileAccess.get_file_as_string(FEEDBACK_SCRIPT).split("\n").size()
	_expect(lines <= MAX_FEEDBACK_LINES, "package_feedback.gd has %d lines, at most %d: a new responsibility goes in "
			% [lines, MAX_FEEDBACK_LINES] + "its own file")


func _check_box_pieces() -> void:
	for trap_id: StringName in TRAP_NODES:
		var package: RigidBody3D = load(PACKAGE_SCENE).instantiate()
		package.set(&"trap_definition", load("res://data/traps/%s.tres" % trap_id))
		root.add_child(package)
		await process_frame
		await process_frame
		var box: Node = package.get_node(^"Box")
		_expect(box.get_node_or_null(NodePath(TRAP_NODES[trap_id])) != null,
				"A %s box builds its %s" % [trap_id, TRAP_NODES[trap_id]])
		if trap_id == &"fragile":
			var names: Array[String] = []
			for child: Node in box.get_children():
				var child_name: String = String(child.name)
				if not child_name.begins_with("@") and not names.has(child_name):
					names.append(child_name)
			_expect(names == FRAGILE_BOX_ORDER, "The Frágil box adds its pieces in the usual order (got %s)" % [names])
		package.free()
		await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

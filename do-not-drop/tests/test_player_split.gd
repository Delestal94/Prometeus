extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_player_split.gd
##
## player.gd was split by responsibility (N-225.5: player_ride.gd, player_movement.gd, player_input.gd and
## player_net_visibility.gd, next to the components that were already there) and must stay split without
## changing what the rest of the project, or the network, sees of the player:
## - the RPC surface of Player is exactly the table below (name, rpc mode, transfer mode, call_local, channel)
##   and the @rpc functions keep their order and annotations in the file, as before the split (taken from the
##   file before it). Godot numbers RPCs by name, so a renamed or re-moded one would make peers disagree on the
##   wire; an @rpc has to stay in the node's own script, and so does its RpcGuard / _from_host() check;
## - every method, variable and constant that the rest of the code (scripts/, tests/, modules/) reaches on a
##   player still exists, the moved ones (look, view and bob numbers, ride and net-state helpers) with the same
##   values, and the helpers load and are static;
## - what the helpers compute is what the single-file version computed: the collision masks, the pickup blend,
##   the drawn pose of a node, the rescue after a fall out of the world and the look clamp, on small inputs;
## - player.gd stays under MAX_LINES lines, far from the lint limit (1000), so it doesn't grow back to the edge.

## The script is loaded when the test runs: with --script this file compiles before the autoloads exist, and
## naming Player here would pull them in too early (see test_assist.gd).
const PLAYER_SCENE: String = "res://scenes/gameplay/player/player.tscn"
const PLAYER_SCRIPT: String = "res://scripts/gameplay/player/player.gd"
const MAX_LINES: int = 700
const HELPERS: Array[String] = ["player_ride", "player_movement", "player_input", "player_net_visibility"]

## Order of the @rpc functions in player.gd, with the annotation of each.
const RPC_ORDER: Array = [
	["receive_package_hit", "any_peer", "call_local", "unreliable"],
	["pick_up", "any_peer", "call_local", "reliable"],
	["drop_carried", "any_peer", "call_local", "reliable"],
	["tend_package", "any_peer", "call_local", "reliable"],
	["assist_package", "any_peer", "call_local", "reliable"],
	["stop_assisting", "any_peer", "call_local", "reliable"],
	["board_seat", "any_peer", "call_local", "reliable"],
]
## name -> [rpc_mode, call_local, transfer_mode, channel]. rpc_mode: 1 any_peer, 2 authority. transfer_mode:
## 0 unreliable, 2 reliable.
const RPCS: Dictionary = {
	"receive_package_hit": [1, true, 0, 0],
	"pick_up": [1, true, 2, 0],
	"drop_carried": [1, true, 2, 0],
	"tend_package": [1, true, 2, 0],
	"assist_package": [1, true, 2, 0],
	"stop_assisting": [1, true, 2, 0],
	"board_seat": [1, true, 2, 0],
}
## Methods the project calls on a player from outside player.gd (the player components, the box, the tests).
const METHODS: Array[String] = [
	"is_local", "leave_seat", "pick_up", "drop_carried", "board_seat", "tend_package", "assist_package",
	"stop_assisting", "receive_package_hit", "reach_origin", "reach_slack", "pickup_high_weight_for_package",
	"_find_vehicle", "_on_foot_mask", "_apply_look", "_update_ground_safety", "_on_peer_level_ready",
	"_send_ping", "_show_first_trap_tip", "_gather_package_input", "_drop_carried", "_try_interact",
	"_toggle_package_lid", "_update_carried_package", "_closest_interactable", "_lid_target",
	"_carry_position", "_drop_position", "_raycast", "_transfer_target", "_within_reach",
	"_seat_exit_position", "_seat_body_offset", "_apply_cosmetic", "_from_host", "_activate_ragdoll",
	"_apply_face", "_sync_profile_appearance", "_build_body", "_publish_carry", "_unhandled_input",
	"_process", "_physics_process", "_enter_tree", "_exit_tree", "_ready",
]
const STATIC_METHODS: Array[String] = ["pickup_high_weight_for", "_drawn_transform"]
## Variables other scripts read or write on a player.
const VARS: Array[String] = [
	"carried_package", "tended_package", "assisted_package", "seat_node_path", "net_position", "net_in_vehicle",
	"anim_state", "locomotion_speed", "turn_rate", "jump_anim_time", "pickup_high_weight", "cosmetic_id",
	"face_eyes", "face_mouth", "animator", "stick_sensitivity", "_seated", "_camera", "_head", "_pitch",
	"_riding", "_ride_last_transform", "_vehicle", "_has_net_state", "_bob_time", "_bob_amount",
	"_highlighted", "_carry_pose", "_pickup_elapsed", "_flinch_time", "_ragdolled", "_body_visual", "_nearby",
	"_last_prompt", "_hold_point", "_seat_pose_blend", "_cargo_care", "_sprint", "_ping_input", "_last_safe_ground",
	"_interact_was_down", "_package_hit_cooldown", "_seat_camera_path", "_probe",
]
## Constants (with their values: the moved ones are tuning) that other scripts or tests read.
const CONSTANTS: Dictionary = {
	"WALK_SPEED": 3.6, "GRAVITY": 18.0, "JUMP_VELOCITY": 6.7, "MOUSE_SENSITIVITY": 0.0028, "PITCH_LIMIT": 1.4,
	"WALK_FOV": 78.0, "CARRY_FOV": 70.0, "FOV_SMOOTH_SPEED": 6.0, "BOB_AMPLITUDE": 0.008, "BOB_FREQUENCY": 3.2,
	"BOB_SMOOTH_SPEED": 3.0, "VEHICLE_LAYER": 2, "SHELL_LAYER": 64, "RIDE_MARGIN": 0.4, "ON_FOOT_MASK": 69,
	"RIDING_MASK": 65, "RIDING_SPEED": 1.0, "JUMP_ANIM_LOCK_MS": 1500, "PICKUP_ANIM_LOCK_MS": 1550,
	"PICKUP_LOW_GRIP": 0.51, "PICKUP_HIGH_GRIP": 0.925, "CARRY_MIN_DISTANCE": 0.3, "CARRY_FACE_CLEARANCE": 0.12,
	"WORLD_BLOCKING_MASK": 7, "BODY_RADIUS": 0.35, "DROP_GAP": 0.1, "DROP_CHEST_HEIGHT": 1.0,
	"DROP_GROUND_PROBE": 2.5, "DROP_SETTLE_MARGIN": 0.02, "AIM_DISTANCE_WEIGHT": 0.3, "SEAT_EXIT_STEP": 0.55,
	"REACH_SURFACE_TOLERANCE": 0.3,
	"ANIM_IDLE": &"Idle", "ANIM_WALK": &"Walk", "ANIM_RUN": &"Run", "ANIM_JUMP": &"Jump",
	"ANIM_PICKUP": &"PickUpPackage", "ANIM_PICKUP_HIGH": &"PickUpHigh", "ANIM_SIT": &"Sit",
	"ANIM_STROLL": &"Stroll", "ANIM_TURN": &"TurnInPlace",
}

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var script: GDScript = load(PLAYER_SCRIPT) as GDScript
	var scene: PackedScene = load(PLAYER_SCENE) as PackedScene
	_expect(script != null, "player.gd loads")
	_expect(scene != null, "player.tscn loads")
	if script == null or scene == null:
		quit(1)
		return
	_check_source()
	_check_rpcs(script)
	var probe: Node = scene.instantiate()
	_check_api(probe, script)
	probe.free()
	_check_helpers()
	await _check_behavior(scene, script)
	if _failures == 0:
		print("PASS: player.gd keeps its RPCs and the API the project uses, and stays under %d lines" % MAX_LINES)
	quit(_failures)


func _check_source() -> void:
	var source: String = FileAccess.get_file_as_string(PLAYER_SCRIPT)
	var lines: int = source.split("\n").size()
	_expect(lines <= MAX_LINES, "player.gd has %d lines, at most %d: a new responsibility goes in its own file"
			% [lines, MAX_LINES])
	var order: Array = []
	var all_lines: PackedStringArray = source.split("\n")
	for index: int in all_lines.size():
		if not all_lines[index].begins_with("@rpc("):
			continue
		var annotation: PackedStringArray = all_lines[index].trim_prefix("@rpc(").trim_suffix(")").replace("\"", "") \
				.replace(" ", "").split(",")
		var function_name: String = all_lines[index + 1].trim_prefix("func ").get_slice("(", 0)
		order.append([function_name] + Array(annotation))
		# The sender check is in the @rpc function itself (test_rpc_guard.gd reads it from here).
		var body: String = "\n".join(all_lines.slice(index + 2, index + 5))
		_expect(body.contains("_from_host()"), "%s checks _from_host() in its own body" % function_name)
	_expect(order == RPC_ORDER, "The @rpc functions keep their order and annotations (got %s)" % str(order))


func _check_rpcs(script: GDScript) -> void:
	var config: Dictionary = script.get_rpc_config()
	for rpc_name: String in RPCS:
		_expect(config.has(StringName(rpc_name)), "%s is still an @rpc of the player" % rpc_name)
		if not config.has(StringName(rpc_name)):
			continue
		var found: Dictionary = config[StringName(rpc_name)]
		var actual: Array = [int(found.get("rpc_mode", -1)), bool(found.get("call_local", false)),
				int(found.get("transfer_mode", -1)), int(found.get("channel", 0))]
		_expect(actual == RPCS[rpc_name], "%s has rpc_mode, call_local, transfer_mode, channel %s (got %s)"
				% [rpc_name, RPCS[rpc_name], actual])
	_expect(config.size() == RPCS.size(), "The player has exactly %d RPCs (got %d: %s)"
			% [RPCS.size(), config.size(), config.keys()])


func _check_api(probe: Node, script: GDScript) -> void:
	for method: String in METHODS:
		_expect(probe.has_method(StringName(method)), "The player still has %s()" % method)
	for method: String in STATIC_METHODS:
		var found: bool = false
		for entry: Dictionary in script.get_script_method_list():
			if entry.name == method and (int(entry.flags) & METHOD_FLAG_STATIC) != 0:
				found = true
		_expect(found, "The player still has the static %s()" % method)
	var properties: PackedStringArray = []
	for property: Dictionary in probe.get_property_list():
		properties.append(String(property.name))
	for variable: String in VARS:
		_expect(properties.has(variable), "The player still has the variable %s" % variable)
	var constants: Dictionary = script.get_script_constant_map()
	for constant: String in CONSTANTS:
		_expect(constants.has(constant) and constants[constant] == CONSTANTS[constant],
				"Player.%s is still %s (got %s)" % [constant, CONSTANTS[constant], constants.get(constant)])
	_expect((constants.get("PLAYER_COLORS", []) as Array).size() == 8, "Player.PLAYER_COLORS keeps its 8 colours")


func _check_helpers() -> void:
	for helper: String in HELPERS:
		var path: String = "res://scripts/gameplay/player/%s.gd" % helper
		var helper_script: GDScript = load(path) as GDScript
		_expect(helper_script != null, "%s loads" % path)
		if helper_script == null:
			continue
		for entry: Dictionary in helper_script.get_script_method_list():
			_expect((int(entry.flags) & METHOD_FLAG_STATIC) != 0, "%s.%s() is static: it keeps no state of its own"
					% [helper, entry.name])


## What the helpers compute, through the player's own wrappers.
func _check_behavior(scene: PackedScene, script: GDScript) -> void:
	# The pickup blend: 0 at the floor clip's grip, 1 at the high one's, linear and clamped between.
	_expect(is_equal_approx(script.call(&"pickup_high_weight_for", 0.0), 0.0), "Below the low grip: floor pickup")
	_expect(is_equal_approx(script.call(&"pickup_high_weight_for", 0.51), 0.0), "At the low grip: 0")
	_expect(is_equal_approx(script.call(&"pickup_high_weight_for", 0.925), 1.0), "At the high grip: 1")
	_expect(is_equal_approx(script.call(&"pickup_high_weight_for", 1.5), 1.0), "Above the high grip: 1")
	_expect(is_equal_approx(script.call(&"pickup_high_weight_for", 0.7175), 0.5), "Halfway between: 0.5")

	# A node's drawn pose: its own when it isn't interpolated (a node out of the tree has no interpolation).
	var node := Node3D.new()
	node.transform = Transform3D(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0))
	_expect(script.call(&"_drawn_transform", node) == node.global_transform, "A plain node is drawn where it is")
	node.free()

	var player: Node = scene.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	await process_frame
	# No truck in the tree: collisions are the on-foot ones whether or not the player counts as riding.
	_expect(int(player.call(&"_on_foot_mask", false)) == 69, "On foot: world, shell and boxes")
	_expect(int(player.call(&"_on_foot_mask", true)) == 69, "Riding a truck that isn't there: as on foot")
	_expect(player.call(&"_find_vehicle") == null, "No truck, none found")
	# Falling out of the world puts the player back on the last ground, 0.5 m above it, still.
	player.set(&"_last_safe_ground", Vector3(0.0, 100.0, 0.0))
	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.velocity = Vector3(1.0, -30.0, 2.0)
	player.call(&"_update_ground_safety")
	_expect(player.global_position.is_equal_approx(Vector3(0.0, 100.5, 0.0)), "Rescued above the last safe ground")
	_expect(player.velocity == Vector3.ZERO, "The rescue stops the fall")
	# The look clamp: however far the mouse goes, the head stops at PITCH_LIMIT.
	player.call(&"_apply_look", Vector2(0.0, 100000.0))
	_expect(is_equal_approx(absf(float(player.get(&"_pitch"))), 1.4), "The pitch is clamped to PITCH_LIMIT")
	_expect(is_equal_approx(absf((player.get(&"_head") as Node3D).rotation.x), 1.4), "The head follows the pitch")
	root.remove_child(player)
	player.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

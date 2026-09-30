extends Node
## Local input and the care card for the box in your hands or at your seat.
## All actual work happens on the host.
##
## Controls, kept to one each (playtest 2026-09-28):
##   primary (left click / RT), held  -- look after the box: steady, calm, mop
##   tool (right click / LT), held    -- use the tool the card offers, until
##                                        its ring fills
##   taps (WASD / stick)              -- only when a box asks for a sequence
##   care_tool_next (X / D-pad right) -- pick another tool by hand
##   drop (Q / B), seated             -- lap <-> rack
const Care = preload("res://scripts/gameplay/package/package_care.gd")
const CareCard = preload("res://scripts/ui/hud/care_card.gd")
const CareGuide = preload("res://scripts/ui/hud/care_guide.gd")
const CarePractice = preload("res://scripts/ui/hud/care_practice.gd")
## The logical height the card lays out for, like Hud.BASE_HEIGHT.
const BASE_HEIGHT: float = 720.0
var player: Node
var card: CareCard
## The depot's practice card (CarePractice), until this profile has done it.
var practice: CarePractice
var target: Node
## A tool picked by hand with care_tool_next; cleared when the box's needs
## change, so the card goes back to suggesting.
var manual_tool: StringName = &""
## On foot with a box that asks for a tap sequence and the primary action
## held: WASD taps the sequence instead of walking (player.gd reads this).
var tapping: bool = false
var _suggested: StringName = &""
var _card_target: Node
var _layer: CanvasLayer
var _root: Control


func _ready() -> void:
	player = get_parent()
	if not bool(player.call(&"is_local")):
		set_physics_process(false)
		return
	_layer = CanvasLayer.new()
	_layer.layer = 7
	add_child(_layer)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)
	card = CareCard.new()
	card.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	# The HUD's own margin (Hud.EDGE_MARGIN), so the right column lines up.
	card.offset_right = -Hud.EDGE_MARGIN
	card.offset_left = -Hud.EDGE_MARGIN - CareCard.WIDTH
	_root.add_child(card)
	card.visible = false
	if CarePractice.pending(get_node_or_null(^"/root/UnlockManager")):
		practice = CarePractice.new()
		practice.profile = get_node_or_null(^"/root/UnlockManager")
		practice.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		practice.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		practice.grow_vertical = Control.GROW_DIRECTION_BOTH
		practice.offset_right = -Hud.EDGE_MARGIN
		practice.offset_left = -Hud.EDGE_MARGIN - CarePractice.WIDTH
		_root.add_child(practice)
		practice.visible = false


func _physics_process(delta: float) -> void:
	if card == null:
		return
	_fit_to_screen()
	var run: Node = get_node_or_null(^"/root/RunManager")
	tapping = false
	_update_practice(delta, run)
	target = null
	if not bool(run.get(&"is_running")) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			or String(player.get(&"seat_node_path")).contains("DriverEyePoint"):
		card.visible = false
		return
	var handling: bool = false
	for key: StringName in [&"carried_package", &"tended_package"]:
		var candidate: Variant = player.get(key)
		if is_instance_valid(candidate):
			target = candidate
			handling = true
			break
	if target == null:
		target = player.call(&"_lid_target")
	card.visible = target != null
	if target != _card_target:
		_card_target = target
		card.reset()
		manual_tool = &""
	if target == null:
		return
	var care = target.care
	var kind: StringName = target._trap_kind()
	var supplies: Dictionary = {}
	for tool_id: StringName in Care.TOOLS:
		supplies[tool_id] = int(run.call(&"care_supply_count", tool_id))
	var suggested: StringName = care.suggested_tool(kind, supplies)
	if suggested != _suggested:
		_suggested = suggested
		manual_tool = &""
	if handling and Input.is_action_just_pressed(&"care_tool_next"):
		manual_tool = next_tool(manual_tool if manual_tool != &"" else suggested)
		card.prompt_view.play_cue(&"whoosh")
	var tool: StringName = manual_tool if manual_tool != &"" else suggested
	var input: Dictionary = player.call(&"_gather_package_input")
	input["work"] = handling and tool != &"" and Input.is_action_pressed(&"care_work")
	input["tool"] = tool if tool != &"" else &"tape"
	if handling:
		target.rpc_id(1, &"submit_care_input", input)
	_refresh_card(run, care, kind, tool, int(supplies.get(tool, 0)), input, handling)


func _refresh_card(run: Node, care, kind: StringName, tool: StringName, stock: int, input: Dictionary,
		handling: bool) -> void:
	var gamepad: bool = _using_gamepad()
	var keys: Dictionary = control_names(gamepad, _interact_label(gamepad))
	var state: Dictionary = (target.get(&"care_state") if target.get(&"care_state") is Dictionary else {}).duplicate()
	var cargo_entry: Dictionary = (run.get(&"cargo") as Dictionary).get(target.get(&"package_id"), {})
	var entry_state: int = int(cargo_entry.get("state", 0))
	state["need_hands"] = needs_hands(care, entry_state)
	var seated: bool = not String(player.get(&"seat_node_path")).is_empty()
	state["on_foot"] = not seated
	var sequence: Dictionary = state.get("sequence", {})
	# On foot, holding the primary also locks the walk for what needs A/D or
	# the stick: a code to tap, Balance's lean, Liquid's scrub.
	var gesture: Dictionary = state.get("gesture", {})
	var code_pending: bool = int(sequence.get("index", 0)) < (sequence.get("steps", []) as Array).size() \
		and bool(sequence.get("pending", true))
	tapping = handling and not seated and bool(input.get("steady", false)) \
		and (code_pending or not gesture.is_empty())
	var tool_name: String = care.tool_name(tool, kind) if tool != &"" else ""
	var step: Dictionary = CareGuide.next_step(state, kind, tool, tool_name, keys) if handling \
		else reach_step(keys, bool(player.get(&"_seated")))
	var entry: Dictionary = (run.get(&"cargo") as Dictionary).get(target.get(&"package_id"), {})
	var integrity: float = float(entry.get("integrity", 100.0)) / maxf(float(entry.get("maximum", 100.0)), 0.01) * 100.0
	var view_data: Dictionary = {"pad": gamepad, "primary": bool(input.get("steady", false)),
		"tool_held": Input.is_action_pressed(&"care_work"), "work": care.work if care.work_tool == tool else 0.0,
		"fixes": fix_count(care), "sequence": state.get("sequence", {}), "cushion": state.get("cushion", {}),
		"gesture": gesture, "axis": Input.get_axis(&"drive_left", &"drive_right"),
		"axis_fwd": Input.get_axis(&"walk_backward", &"walk_forward"), "screen_tilt": _screen_tilt(gesture),
		"missing": care.missing_parts,
		"sway": care.balance_target, "interact": keys["interact"]}
	card.update(target.trap_definition.localized_name(), int(entry.get("state", 0)), integrity, step,
		view_data, footer_items(keys, tool_name, stock, handling, bool(player.get(&"_seated")), care.in_lap))


## The tilt the box's gesture reports (in the truck's frame) as this player's
## screen sees it: x to the right of their view, y forward. What the card lights.
func _screen_tilt(gesture: Dictionary) -> Vector2:
	var truck: Node3D = player.get_tree().get_first_node_in_group(&"vehicle") as Node3D
	var direction: Variant = gesture.get("dir", Vector2.ZERO)
	if truck == null or not direction is Vector2:
		return Vector2.ZERO
	return screen_frame(direction, truck.global_basis, PackageRescue.view_basis_of(player))


## `direction` (x to the truck's right, y forward) in the frame of `view`:
## x to the right of what that view sees, y forward.
static func screen_frame(direction: Vector2, truck: Basis, view: Basis) -> Vector2:
	var world: Vector3 = truck.x * direction.x + -truck.z * direction.y
	return Vector2(world.dot(view.x), world.dot(-view.z))


## Before the first run: the practice card, while the crew is loading up in
## the depot and nothing covers the screen.
func _update_practice(delta: float, run: Node) -> void:
	if practice == null:
		return
	var preparing: bool = not bool(run.get(&"is_running")) and (run.get(&"results") as Dictionary).is_empty()
	practice.visible = preparing and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and not String(player.get(&"seat_node_path")).contains("DriverEyePoint")
	if not practice.visible:
		return
	var gamepad: bool = _using_gamepad()
	var advancing: bool = practice.advance(delta, player, control_names(gamepad, _interact_label(gamepad)), gamepad)
	tapping = advancing and practice.step == 3 and Input.is_action_pressed(&"package_action_primary") \
		and is_instance_valid(player.get(&"carried_package"))
	if not advancing:
		practice.queue_free()
		practice = null


## Whether the box needs hands on it right now: at risk, straining, or the
## truck throwing it about. Otherwise the card says it's fine to let go.
static func needs_hands(care, trap_state: int) -> bool:
	return trap_state >= 1 or care.strain > 0.2 or care.balance_target.length() > 0.35


## The card for a box within reach but not in your hands: how to take charge.
static func reach_step(keys: Dictionary, seated: bool) -> Dictionary:
	if seated:
		return {"step": &"collect", "title": TranslationServer.translate("HUD_CARE_NOT_YOURS"),
			"detail": TranslationServer.translate("HUD_CARE_NOT_YOURS_DETAIL")}
	return {"step": &"collect", "title": TranslationServer.translate("HUD_CARE_GRAB"),
		"detail": TranslationServer.translate("HUD_CARE_GRAB_DETAIL") % keys["interact"]}


## The secondary keys under the card, as UiTheme.keycaps() items.
static func footer_items(keys: Dictionary, tool_name: String, stock: int, handling: bool, seated: bool,
		in_lap: bool) -> PackedStringArray:
	var items: PackedStringArray = []
	if not handling:
		return items
	if not tool_name.is_empty():
		items.append(TranslationServer.translate("HUD_CARE_FOOTER_TOOL") % [keys["tool"], tool_name, stock])
	items.append(TranslationServer.translate("HUD_CARE_FOOTER_NEXT_TOOL") % keys["tool_next"])
	if seated:
		var place: String = "HUD_CARE_FOOTER_TO_RACK" if in_lap else "HUD_CARE_FOOTER_TO_LAP"
		items.append(TranslationServer.translate(place) % keys["drop"])
	else:
		items.append(TranslationServer.translate("HUD_CARE_FOOTER_DROP") % keys["drop"])
	return items


## What each control is called on the device in use.
static func control_names(gamepad: bool, interact: String) -> Dictionary:
	if gamepad:
		return {"primary": "RT", "tool": "LT", "interact": interact, "tool_next": "D-pad →", "drop": "B",
			"sides": TranslationServer.translate("HUD_CARE_KEY_STICK"),
			"swing": TranslationServer.translate("HUD_CARE_KEY_STICK")}
	return {"primary": TranslationServer.translate("HUD_CARE_KEY_LEFT_CLICK"),
		"tool": TranslationServer.translate("HUD_CARE_KEY_RIGHT_CLICK"), "interact": interact, "tool_next": "X",
		"drop": "Q", "sides": "WASD", "swing": "A / D"}


## The tool after `current` in the kit's order, wrapping around.
static func next_tool(current: StringName) -> StringName:
	var index: int = Care.TOOLS.find(current)
	return Care.TOOLS[(index + 1) % Care.TOOLS.size()]


## Grows each time a tool job completes (tape can also tear off on a hit,
## which only makes it smaller): the card celebrates when it goes up.
static func fix_count(care) -> int:
	return int(care.tape) + int(care.repairs) + int(care.padded) + int(care.strapped) + int(care.substituted)


## Same scaling as the HUD (Hud.layout_scale()): the card follows the HUD
## size setting and keeps its size on screens taller than 16:9.
func _fit_to_screen() -> void:
	var settings: Node = get_node_or_null(^"/root/GameSettings")
	var user_scale: float = float(settings.get(&"hud_scale")) if settings != null else 1.0
	var screen: Vector2 = _layer.get_viewport().get_visible_rect().size
	var fit: float = user_scale * maxf(1.0, screen.y / BASE_HEIGHT)
	_root.scale = Vector2(fit, fit)
	_root.size = screen / fit


func _interact_label(gamepad: bool) -> String:
	if gamepad:
		return "A"
	var settings: Node = get_node_or_null(^"/root/GameSettings")
	return String(settings.call(&"binding_label", &"interact")) if settings != null else "E"


## Looked up by path: tests run with --script, where autoload names don't
## resolve at compile time.
func _using_gamepad() -> bool:
	var settings: Node = get_node_or_null(^"/root/GameSettings")
	return settings != null and bool(settings.get(&"using_gamepad"))


## The nearest box someone else tends that this player could steady.
func assist_candidate() -> DeliveryPackage:
	var best: DeliveryPackage = null
	var best_distance: float = DeliveryPackage.ASSIST_REACH
	for node: Node in player.get_tree().get_nodes_in_group(&"cargo"):
		var package := node as DeliveryPackage
		if (package == null or package == player.tended_package
				or not package.can_assist(player.get_multiplayer_authority())):
			continue
		var distance: float = player.reach_origin().distance_to(package.global_position)
		if distance <= best_distance:
			best = package
			best_distance = distance
	return best


func update_assisting() -> void:
	if not is_instance_valid(player.assisted_package):
		player.assisted_package = null
		return
	if player.reach_origin().distance_to(player.assisted_package.global_position) > DeliveryPackage.ASSIST_REACH:
		player.assisted_package.rpc_id(1, &"request_stop_assist")
		player.assisted_package = null
		return
	player.assisted_package.rpc_id(1, &"submit_tender_input", player._gather_package_input())

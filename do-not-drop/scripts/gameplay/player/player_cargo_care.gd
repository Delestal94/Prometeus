extends Node
## Local input and a compact workbench HUD. All actual work happens on the host.
const Care = preload("res://scripts/gameplay/package/package_care.gd")
const PHASE_NAMES: Dictionary = {&"intact": "INTACTO", &"damaged": "DAÑADO", &"crisis": "¡RESCATE!",
	&"rescued": "RESCATADO", &"lost": "PERDIDO"}
const HELP_GAMEPAD: String = "RT + stick: equilibrar\n" \
	+ "LT + stick hacia la flecha: trabajar · D-pad der.: herramienta · soltar: regazo/soporte"
const HELP_KEYBOARD: String = "Clic izq. + WASD: equilibrar\n" \
	+ "Clic der. + tecla de la flecha: trabajar · X: herramienta · Q: regazo/soporte"
const DIRECTION_ARROWS: Dictionary = {Vector2.LEFT: "←", Vector2.UP: "↑", Vector2.RIGHT: "→", Vector2.DOWN: "↓"}
const DIRECTION_KEYS: Dictionary = {Vector2.LEFT: "A", Vector2.UP: "W", Vector2.RIGHT: "D", Vector2.DOWN: "S"}
const SEQUENCE_VECTORS: Dictionary = {&"left": Vector2.LEFT, &"up": Vector2.UP, &"right": Vector2.RIGHT,
	&"down": Vector2.DOWN}
var player: Node
var tool_index: int = 0
var panel: PanelContainer
var title: Label
var details: Label
var instructions: Label
var progress: ProgressBar
var balance_view: Control
var target: Node
var _layer: CanvasLayer

class BalanceView extends Control:
	var care
	func _draw() -> void:
		var center := Vector2(95, 50)
		draw_circle(center, 43, Color("34465b"))
		draw_line(center - Vector2(43, 0), center + Vector2(43, 0), Color("7a8999"))
		draw_line(center - Vector2(0, 43), center + Vector2(0, 43), Color("7a8999"))
		if care != null:
			draw_circle(center + care.balance_target * 32.0, 13, Color("83e2ba"))
			draw_circle(center + care.balance_cursor * 32.0, 5, Color.WHITE)


func _ready() -> void:
	player = get_parent()
	if not bool(player.call(&"is_local")):
		set_physics_process(false)
		return
	_layer = CanvasLayer.new()
	_layer.layer = 7
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_left = -370
	panel.offset_right = -20
	panel.offset_top = -140
	panel.offset_bottom = 140
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	title = _label(column, 20)
	var view := BalanceView.new()
	view.custom_minimum_size = Vector2(190, 100)
	column.add_child(view)
	balance_view = view
	progress = ProgressBar.new()
	progress.show_percentage = true
	column.add_child(progress)
	details = _label(column, 16)
	instructions = _label(column, 15)
	panel.visible = false


func _label(parent: Node, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 330
	parent.add_child(label)
	return label


func _physics_process(_delta: float) -> void:
	if panel == null:
		return
	var run: Node = get_node_or_null(^"/root/RunManager")
	target = null
	if not bool(run.get(&"is_running")) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		panel.visible = false
		return
	if String(player.get(&"seat_node_path")).contains("DriverEyePoint"):
		panel.visible = false
		return
	for key: StringName in [&"carried_package", &"tended_package"]:
		var candidate: Variant = player.get(key)
		if is_instance_valid(candidate):
			target = candidate
			break
	if target == null:
		target = player.call(&"_lid_target")
	panel.visible = target != null
	if target == null:
		return
	if Input.is_action_just_pressed(&"care_tool_next"):
		tool_index = (tool_index + 1) % Care.TOOLS.size()
	var input: Dictionary = player.call(&"_gather_package_input")
	input["balance"] = Input.get_vector(&"drive_left", &"drive_right", &"walk_forward", &"walk_backward")
	input["work"] = Input.is_action_pressed(&"care_work")
	input["tool"] = Care.TOOLS[tool_index]
	target.rpc_id(1, &"submit_care_input", input)
	var care = target.care
	title.text = "%s · %s" % [String(target.trap_definition.display_name), PHASE_NAMES.get(care.phase, "")]
	balance_view.care = care
	balance_view.queue_redraw()
	progress.value = care.work * 100.0
	var gamepad: bool = _using_gamepad()
	var stock: int = int(run.call(&"care_supply_count", Care.TOOLS[tool_index]))
	var tool_label: String = care.tool_name(Care.TOOLS[tool_index], target._trap_kind())
	var status: String = target.get_hint() if care.message.is_empty() else care.message
	# A bare arrow read as decoration: spell out the button and the key.
	details.text = "%s (%d): %s\n%s" % [tool_label, stock, work_prompt(care.work_direction(), gamepad), status]
	var sequence: String = sequence_prompt(target, gamepad)
	if not sequence.is_empty():
		details.text += "\n" + sequence
	if care.phase == &"crisis":
		details.text += "\nRescate: %ds · quedan %d piezas" % [ceili(care.crisis_left), care.missing_parts]
	instructions.text = HELP_GAMEPAD if gamepad else HELP_KEYBOARD


## "Hold right click + A (←)": the tool only works while both are held.
static func work_prompt(direction: Vector2, gamepad: bool) -> String:
	if gamepad:
		return "mantené LT + stick %s" % direction_arrow(direction)
	return "mantené clic der. + %s (%s)" % [direction_key(direction), direction_arrow(direction)]


## A trap solved by tapping directions one at a time (the bomb's module):
## the next one to tap, spelled out, or "" when none is pending.
static func sequence_prompt(package: Node, gamepad: bool) -> String:
	var behavior: Object = package.get(&"trap_behavior") as Object
	if behavior == null or not behavior.has_method(&"next_direction"):
		return ""
	var next: StringName = StringName(behavior.call(&"next_direction"))
	if not SEQUENCE_VECTORS.has(next):
		return ""
	var direction: Vector2 = SEQUENCE_VECTORS[next]
	var key: String = "stick %s" % direction_arrow(direction) if gamepad \
		else "%s (%s)" % [direction_key(direction), direction_arrow(direction)]
	return "Desactivar: tocá %s (un toque, sin clic)" % key


static func direction_arrow(direction: Vector2) -> String:
	return String(DIRECTION_ARROWS.get(direction, "?"))


## Movement keys aren't rebindable (game_settings.gd): WASD is what they are.
static func direction_key(direction: Vector2) -> String:
	return String(DIRECTION_KEYS.get(direction, "?"))


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

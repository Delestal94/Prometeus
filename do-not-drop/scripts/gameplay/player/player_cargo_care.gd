extends Node
## Local input and a compact workbench HUD. All actual work happens on the host.
const Care = preload("res://scripts/gameplay/package/package_care.gd")
const PHASE_NAMES: Dictionary = {&"intact": "INTACTO", &"damaged": "DAÑADO", &"crisis": "¡RESCATE!",
	&"rescued": "RESCATADO", &"lost": "PERDIDO"}
const HELP_GAMEPAD: String = "RT + stick: equilibrar\n" \
	+ "LT + flecha: trabajar · D-pad der.: herramienta · soltar: regazo/soporte"
const HELP_KEYBOARD: String = "Clic izq. + WASD: equilibrar\n" \
	+ "Clic der. + flecha: trabajar · X: herramienta · Q: regazo/soporte"
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
	var arrows: Array[String] = ["←", "↑", "→", "↓"]
	var stock: int = int(run.call(&"care_supply_count", Care.TOOLS[tool_index]))
	var tool_label: String = care.tool_name(Care.TOOLS[tool_index], target._trap_kind())
	var status: String = target.get_hint() if care.message.is_empty() else care.message
	details.text = "%s (%d) · %s\n%s" % [tool_label, stock, arrows[care.work_step % 4], status]
	if care.phase == &"crisis":
		details.text += "\nRescate: %ds · quedan %d piezas" % [ceili(care.crisis_left), care.missing_parts]
	instructions.text = HELP_GAMEPAD if _using_gamepad() else HELP_KEYBOARD


## Looked up by path: tests run with --script, where autoload names don't
## resolve at compile time.
func _using_gamepad() -> bool:
	var settings: Node = get_node_or_null(^"/root/GameSettings")
	return settings != null and bool(settings.get(&"using_gamepad"))

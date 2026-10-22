class_name ShedBuilder
extends Node3D
## Build mode of the company shed, with nodes (expansion D-0917): keyboard, mouse and gamepad
## drive a `BuildCursor`; the raised camera, the grid lines, the green/red ghost and a one-line
## hint are drawn here (gray placeholders; the hologram is D-0944). It only asks: placing, moving,
## turning and selling are CompanyNet requests that the host checks (D-0910), and `CompanyShed`
## redraws when the event comes back. A refusal (`request_rejected`) shows its reason in the hint.
##
## Actions are registered in code (`ensure_actions()`), not in project.godot, so they stay out of
## the options screen's rebind list; the cursor reuses the walk and strafe actions
## (WASD, left stick, d-pad: walk_forward/backward, drive_left/right).

signal entered
signal exited

const ACTION_TOGGLE: StringName = &"build_toggle"
const ACTION_CONFIRM: StringName = &"build_confirm"
const ACTION_CANCEL: StringName = &"build_cancel"
const ACTION_ROTATE: StringName = &"build_rotate"
const ACTION_NEXT: StringName = &"build_next"
const ACTION_PREVIOUS: StringName = &"build_prev"
const ACTION_SELL: StringName = &"build_sell"
const ACTION_ZOOM_IN: StringName = &"build_zoom_in"
const ACTION_ZOOM_OUT: StringName = &"build_zoom_out"
## Cursor steps by action; walk_forward is north (-Z), like the stick pushed up.
const MOVES: Dictionary = {
	&"walk_forward": Vector2i(0, -1), &"walk_backward": Vector2i(0, 1),
	&"drive_left": Vector2i(-1, 0), &"drive_right": Vector2i(1, 0),
}
## Seconds before a held direction repeats, and between repeats.
const REPEAT_DELAY: float = 0.35
const REPEAT_EVERY: float = 0.12
const ZOOM_STEP: float = 0.1
## Display names of the placeables; the hint resolves them through def.display_key.
const PLACEABLE_NAME_KEYS: Array[String] = [
	"WORLD_PLACEABLE_ASSEMBLY_TABLE",
	"WORLD_PLACEABLE_SHELF",
	"WORLD_PLACEABLE_FRIDGE",
	"WORLD_PLACEABLE_DISPATCH_ZONE",
]
const HINT_REASON_KEYS: Dictionary = {
	&"host_only": "UI_BUILD_REASON_HOST_ONLY",
	&"overlap": "UI_BUILD_REASON_OVERLAP",
	&"out_of_bounds": "UI_BUILD_REASON_OUT",
	&"fixed_area": "UI_BUILD_REASON_FIXED",
	&"blocks_path": "UI_BUILD_REASON_PATH",
	&"no_money": "UI_BUILD_REASON_MONEY",
	&"piece_limit": "UI_BUILD_REASON_LIMIT",
	&"not_empty": "UI_BUILD_REASON_NOT_EMPTY",
}

var mode: BuildMode = BuildMode.new()
var cursor: BuildCursor
var shed: CompanyShed
var net: CompanyNet
## The player kept still while building (its input is off until the mode ends).
var player: Node3D
## Returns true while another screen owns the input (the supplier order screen, D-0603.b.2): the mode does not
## start then. Unset, nothing blocks it.
var busy: Callable = Callable()
var camera: Camera3D
var hint: Label

var _previous_camera: Camera3D
var _grid: MeshInstance3D
var _ghost: MeshInstance3D
var _held_action: StringName = &""
var _held_for: float = 0.0
var _pending: Dictionary = {}
var _last_refusal: StringName = &""


## Registers the build actions (once): keyboard and gamepad for every one.
static func ensure_actions() -> void:
	var table: Dictionary = {
		ACTION_TOGGLE: [KEY_B, JOY_BUTTON_BACK],
		ACTION_CONFIRM: [KEY_ENTER, JOY_BUTTON_A],
		ACTION_CANCEL: [KEY_BACKSPACE, JOY_BUTTON_B],
		ACTION_ROTATE: [KEY_F, JOY_BUTTON_X],
		ACTION_NEXT: [KEY_E, JOY_BUTTON_RIGHT_SHOULDER],
		ACTION_PREVIOUS: [KEY_Q, JOY_BUTTON_LEFT_SHOULDER],
		ACTION_SELL: [KEY_DELETE, JOY_BUTTON_RIGHT_STICK],
		ACTION_ZOOM_IN: [KEY_PAGEUP, JOY_AXIS_TRIGGER_RIGHT],
		ACTION_ZOOM_OUT: [KEY_PAGEDOWN, JOY_AXIS_TRIGGER_LEFT],
	}
	for action: StringName in table:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		var key := InputEventKey.new()
		key.physical_keycode = table[action][0]
		InputMap.action_add_event(action, key)
		if action == ACTION_ZOOM_IN or action == ACTION_ZOOM_OUT:
			var trigger := InputEventJoypadMotion.new()
			trigger.axis = table[action][1]
			trigger.axis_value = 1.0
			InputMap.action_add_event(action, trigger)
		else:
			var pad := InputEventJoypadButton.new()
			pad.button_index = table[action][1]
			InputMap.action_add_event(action, pad)


func _ready() -> void:
	ensure_actions()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_process_unhandled_input(true)


## Wires the builder to the shed it edits, the company net it asks and the local player.
func setup(company_shed: CompanyShed, company_net: CompanyNet, local_player: Node3D = null) -> void:
	shed = company_shed
	net = company_net
	player = local_player
	if net != null and not net.request_rejected.is_connected(_on_request_rejected):
		net.request_rejected.connect(_on_request_rejected)
		net.event_applied.connect(_on_event_applied)


func is_building() -> bool:
	return mode.active


## Starts the mode on the shed's current floor. False when it was refused (BuildMode.last_refusal) or
## `busy` says another screen owns the input.
func enter() -> bool:
	if shed == null or net == null or net.company == null:
		return false
	if busy.is_valid() and bool(busy.call()):
		return false
	if not mode.enter(shed.grid, true):
		return false
	var checker: BuildPlacement = net.build.placement_for(net.company)
	cursor = BuildCursor.new(mode, checker, net.company)
	_previous_camera = get_viewport().get_camera_3d() if is_inside_tree() else null
	if player != null and is_instance_valid(player):
		player.set_process_unhandled_input(false)
	_make_view()
	set_process(true)
	_refresh()
	entered.emit()
	return true


func exit() -> void:
	if not mode.exit():
		return
	set_process(false)
	_held_action = &""
	if player != null and is_instance_valid(player):
		player.set_process_unhandled_input(true)
	if camera != null:
		camera.queue_free()
		camera = null
	if _previous_camera != null and is_instance_valid(_previous_camera):
		_previous_camera.make_current()
	for node: Node in [_grid, _ghost, hint.get_parent() if hint != null else null]:
		if node != null:
			node.queue_free()
	_grid = null
	_ghost = null
	hint = null
	cursor = null
	exited.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE):
		if mode.active:
			exit()
		else:
			enter()
		get_viewport().set_input_as_handled()
		return
	if not mode.active:
		return
	if event is InputEventMouseMotion:
		_aim_with_mouse((event as InputEventMouseMotion).position)
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button: InputEventMouseButton = event
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				_aim_with_mouse(button.position)
				handle_action(ACTION_CONFIRM)
			MOUSE_BUTTON_RIGHT:
				handle_action(ACTION_CANCEL)
			MOUSE_BUTTON_WHEEL_UP:
				handle_action(ACTION_ZOOM_IN)
			MOUSE_BUTTON_WHEEL_DOWN:
				handle_action(ACTION_ZOOM_OUT)
		get_viewport().set_input_as_handled()
		return
	for action: StringName in _handled_actions():
		if event.is_action_pressed(action, false, true):
			handle_action(action)
			_held_action = action if MOVES.has(action) else &""
			_held_for = 0.0
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released(action) and action == _held_action:
			_held_action = &""


func _process(delta: float) -> void:
	if not mode.active:
		return
	if _held_action != &"":
		if not Input.is_action_pressed(_held_action):
			_held_action = &""
		else:
			_held_for += delta
			if _held_for >= REPEAT_DELAY:
				_held_for -= REPEAT_EVERY
				handle_action(_held_action)


func _handled_actions() -> Array[StringName]:
	var found: Array[StringName] = [ACTION_CONFIRM, ACTION_CANCEL, ACTION_ROTATE, ACTION_NEXT,
		ACTION_PREVIOUS, ACTION_SELL, ACTION_ZOOM_IN, ACTION_ZOOM_OUT]
	for action: StringName in MOVES:
		found.append(action)
	return found


## One press of a build action, whatever the device. The tests call it directly.
func handle_action(action: StringName) -> void:
	if not mode.active or cursor == null:
		return
	_last_refusal = &""
	if MOVES.has(action):
		cursor.move(MOVES[action])
		_pan_to_cursor()
	elif action == ACTION_NEXT:
		cursor.cycle(1)
	elif action == ACTION_PREVIOUS:
		cursor.cycle(-1)
	elif action == ACTION_ZOOM_IN:
		mode.zoom_by(-ZOOM_STEP)
	elif action == ACTION_ZOOM_OUT:
		mode.zoom_by(ZOOM_STEP)
	elif action == ACTION_ROTATE:
		_send(cursor.rotate())
	elif action == ACTION_SELL:
		_send(cursor.sell())
	elif action == ACTION_CONFIRM:
		_send(cursor.confirm())
	elif action == ACTION_CANCEL:
		if not cursor.cancel():
			exit()
			return
	_refresh()


func _send(request: Dictionary) -> void:
	if request.is_empty() or net == null:
		return
	net.request(request["kind"], request["data"])


func _on_request_rejected(rid: int, reason: StringName) -> void:
	if rid == 0:
		return  # a refusal the host made for something else (a shelf used, D-0609), not ours
	_last_refusal = reason
	_refresh()


## A layout event arrived (ours or anyone's): the ghost and hint follow the new layout.
func _on_event_applied(_seq: int, kind: StringName, _data: Dictionary) -> void:
	if mode.active and CompanyLayoutNet.EVENT_KINDS.has(kind):
		_refresh()


func _pan_to_cursor() -> void:
	mode.focus = Vector2(cursor.cell) * CompanyTuning.WAREHOUSE_GRID_M \
		+ Vector2.ONE * CompanyTuning.WAREHOUSE_GRID_M * 0.5


## The mouse points at a cell of the floor: ray from the build camera down to the floor plane.
func _aim_with_mouse(screen: Vector2) -> void:
	if camera == null or cursor == null or shed == null:
		return
	var from: Vector3 = camera.project_ray_origin(screen)
	var dir: Vector3 = camera.project_ray_normal(screen)
	if absf(dir.y) < 0.001:
		return
	var at: Vector2 = shed.local_to_cell(shed.to_local(_floor_hit(from, dir)))
	cursor.set_cell(Vector2i(floori(at.x), floori(at.y)))
	_refresh()


func _floor_hit(from: Vector3, dir: Vector3) -> Vector3:
	var floor_y: float = shed.global_position.y
	return from + dir * ((floor_y - from.y) / dir.y)


func _make_view() -> void:
	camera = Camera3D.new()
	camera.name = "BuildCamera"
	shed.add_child(camera)
	_grid = MeshInstance3D.new()
	_grid.name = "BuildGrid"
	shed.add_child(_grid)
	_ghost = MeshInstance3D.new()
	_ghost.name = "BuildGhost"
	shed.add_child(_ghost)
	var layer := CanvasLayer.new()
	layer.name = "BuildHud"
	add_child(layer)
	hint = Label.new()
	hint.position = Vector2(24, 24)
	layer.add_child(hint)
	camera.make_current()
	mode.focus = mode.floor_size_m() * 0.5
	_pan_to_cursor()


## Redraws what depends on the cursor: camera pose, grid lines, ghost box and hint text.
func _refresh() -> void:
	if not mode.active or cursor == null or camera == null:
		return
	var pose: Dictionary = mode.camera_pose()
	var at: Vector3 = pose["position"]
	camera.position = shed.cell_to_local(Vector2(at.x, at.z) / CompanyTuning.WAREHOUSE_GRID_M, at.y)
	camera.rotation_degrees = Vector3(-float(pose["pitch_deg"]), 0.0, 0.0)
	_draw_grid()
	var ghost: Dictionary = cursor.ghost()
	_draw_ghost(ghost)
	hint.text = _hint_text(ghost)


func _draw_grid() -> void:
	var lines: Array[Vector2] = mode.grid_lines()
	var mesh := ImmediateMesh.new()
	if not lines.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for point: Vector2 in lines:
			mesh.surface_add_vertex(shed.cell_to_local(point / CompanyTuning.WAREHOUSE_GRID_M, 0.03))
		mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 1, 1, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid.mesh = mesh
	_grid.material_override = material


func _draw_ghost(ghost: Dictionary) -> void:
	var def: PlaceableDefinition = ghost.get("def")
	if def == null:
		_ghost.visible = false
		return
	var rect: Rect2i = ghost["rect"]
	var metres: float = CompanyTuning.WAREHOUSE_GRID_M
	var box := BoxMesh.new()
	box.size = Vector3(rect.size.x * metres, maxf(def.height_m, 0.1), rect.size.y * metres)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = cursor.placement.preview_color(ghost)
	_ghost.mesh = box
	_ghost.material_override = material
	var middle := Vector2(rect.position) + Vector2(rect.size) * 0.5
	_ghost.position = shed.cell_to_local(middle, box.size.y * 0.5)
	_ghost.visible = true


func _hint_text(ghost: Dictionary) -> String:
	var def: PlaceableDefinition = ghost.get("def")
	var name: String = tr(def.display_key) if def != null else ""
	var line: String = tr("UI_BUILD_HINT") % [name, def.price if def != null else 0]
	var reason: StringName = _last_refusal if _last_refusal != &"" else StringName(ghost.get("reason", &""))
	if cursor.held != &"":
		line += "\n" + tr("UI_BUILD_HELD")
	if reason != &"":
		line += "\n" + tr(HINT_REASON_KEYS.get(reason, "UI_BUILD_REASON_OTHER"))
	return line

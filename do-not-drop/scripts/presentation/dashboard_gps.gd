extends Node3D
class_name DashboardGps
## The GPS on the truck's dashboard (tareas de Nacho N-502): the driver's own
## guide, inside the world instead of on the HUD. On a delivery it shows how
## far along the road the next house still waiting is, an arrow toward it and
## the code of the box it ordered; once every house is done, the way to the
## goal. In Endless, the distance driven and the record.
##
## It also carries the bomb code (N-117, Explosivo's "Pedí el código"): the
## steps still to say aloud for the box about to go off, so the driver can
## read them out to whoever holds it, who never sees them on their own card.
## The screen is small from the driver's seat, so this is the diegetic backup:
## the HUD's own line (HudNotices.refresh_bomb_code()) is what gets read.
## While it shows, it takes the whole screen.
##
## Presentation only: every peer works it out from its own copy of the truck
## and the route, and hears about finished houses through
## EventBus.house_delivery_recorded (relayed by the host to everyone).
##
## Space: a screen facing its own -Z (the driver), X to the right, Y up.

const SCREEN_SIZE := Vector2(0.26, 0.15)
const REFRESH_SECONDS: float = 0.2
const INK := Color("1d6f78")
const GLOW := Color("39c4c9")
const TEXT := Color("e8fbff")
const WARN := Color("ffc93c")
const ALERT := Color("ff6b5b")
## Codes shown at once (the soonest to go off first); the rest is a "+N".
const MAX_CODE_LINES: int = 1
const ARROWS: Dictionary = {&"up": "↑", &"down": "↓", &"left": "←", &"right": "→"}
const FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")

var distance_label: Label3D
var detail_label: Label3D
## The bomb code line, over the whole screen while there is one.
var code_label: Label3D
var arrow: MeshInstance3D
## Which house the screen points at (-1 once it points at the goal, or in
## Endless).
var target_house: int = 0
var _done: Dictionary = {}
var _refresh: float = 0.0


func _ready() -> void:
	_build_screen()
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"house_delivery_recorded", func(index: int, _outcome: StringName, _package: StringName) -> void:
			_done[index] = true
			refresh())
	refresh.call_deferred()


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_SECONDS
		refresh()


## Reads the truck and the road and redraws. Public so tests needn't wait.
func refresh() -> void:
	var truck := _truck()
	var route := _route()
	if truck == null:
		return
	if route == null:
		_show_endless()
		_show_bomb_code()
		return
	var houses: Array = route.get(&"houses")
	target_house = -1
	for index: int in range(houses.size()):
		if not _done.has(index):
			target_house = index
			break
	var stop: int = target_house if target_house >= 0 else houses.size()
	var left: float = maxf(0.0, float(route.call(&"stop_road_distance", stop)) - float(route.call(&"road_distance", truck.global_position)))
	distance_label.text = _metres(left)
	var toward: Vector3
	if target_house >= 0:
		var house: DeliveryHouse = houses[target_house]
		var code: String = house.assigned_label.strip_edges().get_slice(" ", house.assigned_label.strip_edges().get_slice_count(" ") - 1) if not house.assigned_label.is_empty() else ""
		detail_label.text = (tr("WORLD_GPS_HOUSE_CODE") % [target_house + 1, code.to_upper()]) if code != "" else tr("WORLD_HOUSE_NUMBER") % (target_house + 1)
		toward = house.global_position
	else:
		detail_label.text = tr("WORLD_GPS_ARRIVAL")
		toward = route.to_global((route.get(&"goal_transform") as Transform3D).origin)
	_point_arrow(truck, toward)
	_show_bomb_code()


## The code of the box about to go off (and a "+N" for the rest) fills the
## screen, big, in the alert colour when it is close; the distance, the detail
## and the arrow step aside while it shows.
func _show_bomb_code() -> void:
	var codes: Array[Dictionary] = bomb_codes(get_tree().get_nodes_in_group(&"cargo"))
	var shown: bool = not codes.is_empty()
	code_label.visible = shown
	distance_label.visible = not shown
	detail_label.visible = not shown
	if not shown:
		return
	arrow.visible = false
	code_label.text = ", ".join(code_lines(codes, MAX_CODE_LINES, tr("WORLD_GPS_CODE"), tr("WORLD_GPS_CODE_MORE")))
	code_label.modulate = ALERT if float(codes[0]["seconds"]) <= 6.0 else WARN


## `codes` (bomb_codes()) as text, at most `max_lines` of them, the soonest
## first: each `format` % [arrows still to say, seconds]; what does not fit is
## `more_format` % how many, on the last line. Shared with the driver's HUD.
static func code_lines(codes: Array[Dictionary], max_lines: int, format: String,
		more_format: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	for index: int in range(mini(codes.size(), max_lines)):
		var entry: Dictionary = codes[index]
		lines.append(format % [code_text(entry["steps"] as Array, int(entry["index"])),
				ceili(float(entry["seconds"]))])
	if codes.size() > max_lines and not lines.is_empty():
		lines[lines.size() - 1] += " " + more_format % (codes.size() - max_lines)
	return lines


## The bomb codes the driver has to read out, from the boxes' replicated care
## state (so every peer builds the same list): [{steps, index, seconds}],
## the soonest to go off first. A box whose owner reads its own code (no other
## human at the wheel), one already defused and one already blown are left out.
static func bomb_codes(boxes: Array) -> Array[Dictionary]:
	var codes: Array[Dictionary] = []
	for box: Variant in boxes:
		if not is_instance_valid(box):
			continue
		var state: Variant = (box as Object).get(&"care_state")
		var sequence: Dictionary = (state as Dictionary).get("sequence", {}) if state is Dictionary else {}
		var steps: Array = sequence.get("steps", [])
		if steps.is_empty() or StringName(sequence.get("reader", &"owner")) != &"driver" \
				or int(sequence.get("index", 0)) >= steps.size() or float(sequence.get("seconds", 0.0)) <= 0.0:
			continue
		codes.append({"steps": steps, "index": int(sequence.get("index", 0)), "seconds": float(sequence["seconds"])})
	codes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["seconds"]) < float(b["seconds"]))
	return codes


## The steps from `from` on, as arrows: what is still left to say.
static func code_text(steps: Array, from: int) -> String:
	var parts: PackedStringArray = []
	for index: int in range(clampi(from, 0, steps.size()), steps.size()):
		parts.append(String(ARROWS.get(StringName(steps[index]), "?")))
	return " ".join(parts)


func _show_endless() -> void:
	var manager: Node = get_node_or_null(^"/root/RunManager")
	var driven: float = float(manager.get(&"current_distance")) if manager != null else 0.0
	var best: int = int(manager.call(&"best_score", &"endless")) if manager != null else 0
	distance_label.text = _metres(driven)
	detail_label.text = tr("WORLD_GPS_BEST") % _metres(best) if best > 0 else tr("WORLD_GPS_NO_BEST")
	arrow.visible = false


## Turns the arrow on the screen toward `world_target`, seen from above: up
## on the screen is straight ahead.
func _point_arrow(truck: Node3D, world_target: Vector3) -> void:
	arrow.visible = true
	var to_target: Vector3 = world_target - truck.global_position
	# Positive: to the truck's right.
	var angle: float = atan2(to_target.dot(truck.global_basis.x), to_target.dot(-truck.global_basis.z))
	# The driver looks at the screen from its -Z side, where turning about +Z
	# reads as clockwise: a target to the right turns the arrow right.
	arrow.rotation.z = angle


static func _metres(value: float) -> String:
	if value >= 1000.0:
		return "%.1f km" % (value / 1000.0)
	return "%d m" % (roundi(value / 10.0) * 10)


func _truck() -> Node3D:
	var node: Node = get_parent()
	while node != null and not node is VehicleBody3D:
		node = node.get_parent()
	return node as Node3D


func _route() -> Node3D:
	var house: Node = get_tree().get_first_node_in_group(&"delivery_house")
	return house.get_parent() as Node3D if house != null else null


func _build_screen() -> void:
	var bezel := MeshInstance3D.new()
	bezel.name = "Bezel"
	var bezel_mesh := BoxMesh.new()
	# Deep enough to fill the dash's bevels behind it: flush, no gap.
	bezel_mesh.size = Vector3(SCREEN_SIZE.x + 0.03, SCREEN_SIZE.y + 0.03, 0.085)
	bezel.mesh = bezel_mesh
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("20262c")
	bezel.material_override = dark
	bezel.position = Vector3(0.0, 0.0, 0.0435)
	add_child(bezel)
	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	var quad := QuadMesh.new()
	quad.size = SCREEN_SIZE
	screen.mesh = quad
	var lit := StandardMaterial3D.new()
	lit.albedo_color = INK
	lit.emission_enabled = true
	lit.emission = GLOW
	lit.emission_energy_multiplier = 0.35
	screen.material_override = lit
	# QuadMesh faces +Z; the driver is on -Z.
	screen.rotation.y = PI
	add_child(screen)
	arrow = MeshInstance3D.new()
	arrow.name = "Arrow"
	var prism := PrismMesh.new()
	prism.size = Vector3(0.05, 0.06, 0.004)
	arrow.mesh = prism
	var arrow_material := StandardMaterial3D.new()
	arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_material.albedo_color = WARN
	arrow.material_override = arrow_material
	arrow.position = Vector3(-SCREEN_SIZE.x * 0.5 + 0.045, 0.0, -0.004)
	add_child(arrow)
	distance_label = _label("—", Vector3(0.03, 0.022, -0.003), 64, TEXT)
	distance_label.name = "Distance"
	detail_label = _label("", Vector3(0.03, -0.035, -0.003), 40, WARN)
	detail_label.name = "Detail"
	code_label = _label("", Vector3(0.015, 0.0, -0.003), 46, WARN)
	code_label.name = "BombCode"
	code_label.outline_size = 6
	code_label.outline_modulate = Color("10161a")
	# The arrows are not in the dashboard's display font: the engine's own.
	code_label.font = null
	code_label.visible = false


func _label(text: String, at: Vector3, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = FONT
	label.font_size = size
	label.pixel_size = 0.0006
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.position = at
	# Label3D reads from +Z: turned to read from the driver's side.
	label.rotation.y = PI
	add_child(label)
	return label

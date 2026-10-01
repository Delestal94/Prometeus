extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_driver_bomb_code.gd
## The bomb's code on the driver's HUD (N-117, "Pedí el código"), the line
## that actually gets read from the driver's seat:
## - only the one at the wheel sees it, only during a run, and only for a code
##   the driver reads (the box's owner has to ask, so nobody else's HUD shows it);
## - it lists the arrows still to say and the seconds, the soonest bomb first
##   with a "+N" for the rest, yellow and then red in the last six seconds;
## - it goes away when the wheel changes hands or the code is solved;
## - the dashboard's screen backs it up with a single line, big and outlined,
##   and steps its distance, detail and arrow aside while it shows.

## Loaded at run time, and no DeliveryPackage or DashboardGps type: naming them
## would compile the HUD before the autoloads exist (it reads NetworkManager;
## the GPS reaches it through DeliveryHouse, which reads the box as a package).
const PACKAGE_PATH: String = "res://scenes/gameplay/package/package.tscn"
const GPS_PATH: String = "res://scripts/presentation/dashboard_gps.gd"
const VEHICLE_SOURCE: String = "extends Node3D\nvar driver_peer_id: int = 0\n"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run: Node = root.get_node(^"/root/RunManager")
	var network: Node = root.get_node(^"/root/NetworkManager")
	var me: int = int(network.call(&"local_id"))
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	var script := GDScript.new()
	script.source_code = VEHICLE_SOURCE
	script.reload()
	var vehicle := Node3D.new()
	vehicle.set_script(script)
	vehicle.add_to_group(&"vehicle")
	root.add_child(vehicle)
	await process_frame
	var boxes: Array[Node] = []
	for seconds: float in [11.0, 4.0]:
		var box: Node = (load(PACKAGE_PATH) as PackedScene).instantiate()
		box.set(&"freeze", true)
		root.add_child(box)
		box.add_to_group(&"cargo")
		box.care_state = _state([&"up", &"left", &"down"], 1, seconds, &"driver")
		boxes.append(box)
	var label: Label = hud.code_label
	_expect(label != null, "The HUD has a line for the code")

	run.set(&"is_running", true)
	vehicle.set(&"driver_peer_id", me)
	hud.notices.refresh_bomb_code()
	_expect("← ↓" in label.text and not "↑" in label.text, "The driver reads the steps still to say (%s)" % label.text)
	_expect("4" in label.text and "+1" in label.text, "The soonest bomb first, the rest counted (%s)" % label.text)
	_expect(label.get_theme_color(&"font_color") == UiTheme.RED, "Under six seconds it is red")
	await process_frame
	_expect(label.visible, "The plate shows while there is a code")
	boxes[1].care_state = _state([&"up"], 0, 10.0, &"driver")
	hud.notices.refresh_bomb_code()
	_expect(label.get_theme_color(&"font_color") == UiTheme.YELLOW, "With time left it is yellow")

	vehicle.set(&"driver_peer_id", me + 1)
	hud.notices.refresh_bomb_code()
	_expect(label.text.is_empty(), "A passenger's HUD never shows the code")
	vehicle.set(&"driver_peer_id", 0)
	hud.notices.refresh_bomb_code()
	_expect(label.text.is_empty(), "With nobody at the wheel there is no line either")
	vehicle.set(&"driver_peer_id", me)
	hud.notices.refresh_bomb_code()
	_expect(not label.text.is_empty(), "Taking the wheel shows it")
	run.set(&"is_running", false)
	hud.notices.refresh_bomb_code()
	_expect(label.text.is_empty(), "Outside a run there is nothing to read")
	run.set(&"is_running", true)
	for box: Node in boxes:
		box.care_state = _state([&"up"], 0, 9.0, &"owner")
	hud.notices.refresh_bomb_code()
	_expect(label.text.is_empty(), "A code its owner reads is not on the driver's HUD")
	for box: Node in boxes:
		box.care_state = _state([&"up"], 1, 9.0, &"driver")
	hud.notices.refresh_bomb_code()
	_expect(label.text.is_empty(), "A solved code goes away")
	run.set(&"is_running", false)

	# The dashboard's screen: one line, the rest steps aside.
	var truck := VehicleBody3D.new()
	root.add_child(truck)
	var gps_script: GDScript = load(GPS_PATH)
	var gps: Node3D = gps_script.new()
	var alert: Color = gps_script.get_script_constant_map()[&"ALERT"]
	truck.add_child(gps)
	await process_frame
	boxes[0].care_state = _state([&"up", &"left", &"down"], 0, 9.0, &"driver")
	boxes[1].care_state = _state([&"right", &"down"], 0, 5.0, &"driver")
	gps.refresh()
	_expect(gps.code_label.visible and not "\n" in gps.code_label.text,
		"One line on the screen (%s)" % gps.code_label.text)
	_expect("→ ↓" in gps.code_label.text and "+1" in gps.code_label.text, "The soonest, the rest counted")
	_expect(gps.code_label.font_size >= 44 and gps.code_label.outline_size >= 6, "Big and outlined")
	_expect(gps.code_label.modulate == alert, "The colour follows the code shown")
	_expect(not gps.distance_label.visible and not gps.detail_label.visible and not gps.arrow.visible,
		"The other readouts step aside while it shows")
	for box: Node in boxes:
		box.care_state = {}
	gps.refresh()
	_expect(gps.distance_label.visible and gps.detail_label.visible and not gps.code_label.visible,
		"Without a code the screen is back to distance and detail")
	if _failures == 0:
		print("PASS: the bomb's code is on the driver's HUD only, and on the dashboard as one big line")
	quit(_failures)


func _state(steps: Array, index: int, seconds: float, reader: StringName) -> Dictionary:
	return {"sequence": {"steps": steps, "index": index, "seconds": seconds, "reader": reader}}


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

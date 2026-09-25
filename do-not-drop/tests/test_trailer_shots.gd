extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_trailer_shots.gd
##
## The trailer's camera and its six shots (N-902, trailer_camera.gd,
## trailer_shot.gd, data/trailer_shots.json):
## - the six planned shots are there (depot exit, forest bend, rail crossing,
##   narrow bridge in the rain, a house at night, a roll with boxes flying),
##   each with a rail of increasing times, and the world each asks for exists
##   (a seed whose route has that segment);
## - a rail is smooth: the camera never jumps between frames, and it ends
##   where its last point says;
## - set up for real, a shot puts the truck on the road before its segment,
##   under the shot's weather, and the roll really rolls it;
## - recording a point takes the current view relative to the truck.

const EXPECTED: Array[String] = ["salida_deposito", "curva_bosque", "cruce_tren", "puente_lluvia", "casa_noche", "vuelco"]
const ShotScript = preload("res://scripts/tools/trailer_shot.gd")
const CameraScript = preload("res://scripts/tools/trailer_camera.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var shots: Dictionary = ShotScript.load_shots()
	for name: String in EXPECTED:
		_expect(shots.has(name), "The shot '%s' is saved" % name)
		if not shots.has(name):
			continue
		var rail: Array = shots[name].get("rail", [])
		_expect(rail.size() >= 2, "%s has a rail" % name)
		for index: int in range(1, rail.size()):
			_expect(float(rail[index].t) > float(rail[index - 1].t), "%s's rail runs forward in time" % name)
		var start: Dictionary = shots[name].get("start", {})
		if String(start.get("at", "")) == "segment":
			var houses: int = int(shots[name].get("houses", 2))
			var seed_value: int = ShotScript.find_seed(String(start.segment), houses)
			var plan: Dictionary = (load("res://scripts/gameplay/route/route.gd") as Script).call(&"plan_spine", seed_value, houses, true)
			var found: bool = false
			for entry: Dictionary in plan.segments:
				found = found or (entry.script as Script).get_global_name() == String(start.segment)
			_expect(found, "%s finds a world with a %s (seed %d)" % [name, start.segment, seed_value])

	# Smooth rails: no frame-to-frame jump bigger than a fast dolly's.
	var camera: Camera3D = CameraScript.new()
	root.add_child(camera)
	camera.call(&"play", shots["curva_bosque"].rail, Transform3D.IDENTITY)
	camera.set(&"target", null)
	var worst: float = 0.0
	var previous: Vector3 = (camera.call(&"pose_at", 0.0) as Array)[0]
	var t: float = 0.0
	while t < float(camera.call(&"rail_length")):
		t += 1.0 / 60.0
		var at: Vector3 = (camera.call(&"pose_at", t) as Array)[0]
		worst = maxf(worst, at.distance_to(previous))
		previous = at
	_expect(worst < 0.25, "The camera glides: never more than 25 cm a frame (%.2f)" % worst)
	var last: Array = shots["curva_bosque"].rail[-1].at
	_expect(((camera.call(&"pose_at", 99.0) as Array)[0] as Vector3).is_equal_approx(Vector3(last[0], last[1], last[2])), "It ends on the last point")
	camera.queue_free()

	# A real shot: the roll.
	var runner: Node = ShotScript.new()
	runner.set(&"autoplay", false)
	root.add_child(runner)
	await runner.call(&"setup", shots["vuelco"])
	runner.set_process(false)
	var van: VehicleBody3D = runner.get(&"van")
	var route: Node3D = runner.get(&"route")
	_expect(van != null and float(route.call(&"road_distance", van.global_position)) > 30.0, "The truck starts out on the road, not in the depot")
	_expect(runner.get_node_or_null(^"TrailerCamera") != null and (runner.get_node(^"TrailerCamera") as Camera3D).current, "The trailer camera has the view")
	var hud_hidden: bool = true
	for layer: Node in (runner.get(&"level") as Node).find_children("*", "CanvasLayer", false, false):
		hud_hidden = hud_hidden and not (layer as CanvasLayer).visible
	_expect(hud_hidden, "No HUD in the shot")
	var lowest_up: float = 1.0
	for tick: int in range(60 * 5):
		runner.set(&"_time", float(tick) / 60.0)
		await physics_frame
		lowest_up = minf(lowest_up, van.global_basis.y.dot(Vector3.UP))
	_expect(lowest_up < 0.3, "The roll tips the truck over during the shot (lowest up·Y %.2f)" % lowest_up)
	var recorded: Dictionary = (runner.get_node(^"TrailerCamera") as Node).call(&"record_point")
	_expect(recorded.get("space", "") == "truck" and (recorded.at as Array).size() == 3, "Recording a point takes the view relative to the truck")
	runner.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")
	WorldMood.forced_label = ""
	root.get_node(^"/root/NetworkManager").set(&"world_seed", 0)
	root.get_node(^"/root/NetworkManager").set(&"world_house_count", 0)
	if _failures == 0:
		print("PASS: six trailer shots saved, their worlds found, the rails smooth, and a shot plays out for real")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

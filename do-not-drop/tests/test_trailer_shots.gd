extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_trailer_shots.gd
##
## The trailer's camera and its shots (N-902, N-905, N-906, trailer_camera.gd,
## trailer_shot.gd, data/trailer_shots.json):
## - the planned shots are there (depot exit, forest bend, rail crossing,
##   narrow bridge in the rain, a house at night, a roll with boxes flying,
##   and the devlog's deer),
##   each with a rail of increasing times, and the world each asks for exists
##   (a seed whose route has that segment);
## - a rail is smooth: the camera never jumps between frames, and it ends
##   where its last point says;
## - a segment shot's world has that segment well out on the road (the first
##   captures started the bend and the roll at the depot's door);
## - set up for real, a shot puts the truck on the road before its segment,
##   doors shut, with no HUD or floating labels, and the roll really rolls
##   it -- and it stays over (the autopilot used to drive it back upright)
##   while its boxes fly out;
## - played out (the capture review found the truck, the train and the deer
##   out of frame): casa_noche stops the truck at the house, in the camera's
##   view; cruce_tren stops it at the barrier with the train going by in
##   view; ciervo's deer crosses in view and the truck doesn't hit it;
## - recording a point takes the current view relative to the truck.

const EXPECTED: Array[String] = ["salida_deposito", "curva_bosque", "cruce_tren", "puente_lluvia", "casa_noche", "vuelco", "ciervo"]
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
			var min_start: float = float(start.get("lead", 60.0)) + ShotScript.RUN_UP_MARGIN
			var seed_value: int = ShotScript.find_seed(String(start.segment), houses, 1, min_start)
			var plan: Dictionary = (load("res://scripts/gameplay/route/route.gd") as Script).call(&"plan_spine", seed_value, houses, true)
			var found: bool = false
			for entry: Dictionary in plan.segments:
				found = found or ((entry.script as Script).get_global_name() == String(start.segment) and float(entry.start) >= min_start)
			_expect(found, "%s finds a world with a %s at least %.0f m out (seed %d)" % [name, start.segment, min_start, seed_value])

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
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		hud_hidden = hud_hidden and not (layer as CanvasLayer).visible
	_expect(hud_hidden, "No HUD in the shot, the autoloads' included")
	var labels_hidden: bool = true
	for label: Node in (runner.get(&"level") as Node).find_children("*", "Label3D", true, false):
		if (label as Label3D).billboard != BaseMaterial3D.BILLBOARD_DISABLED:
			labels_hidden = labels_hidden and not (label as Label3D).visible
	_expect(labels_hidden, "No floating in-world labels in the shot")
	_expect(not van.call(&"is_door_open", &"rear") and not van.call(&"is_door_open", &"cab_left"), "The truck's doors are shut for the shot")
	var aboard: int = 0
	for package: Node in (runner.get(&"level") as Node).get(&"packages"):
		if is_instance_valid(package) and bool(package.get(&"is_loaded")):
			aboard += 1
	_expect(aboard >= int(shots["vuelco"].get("cargo", 1)), "The roll carries its %d boxes (%d aboard)" % [int(shots["vuelco"].get("cargo", 1)), aboard])
	var lowest_up: float = 1.0
	var packages: Array = (runner.get(&"level") as Node).get(&"packages")
	for tick: int in range(60 * 5):
		runner.set(&"_time", float(tick) / 60.0)
		await physics_frame
		lowest_up = minf(lowest_up, van.global_basis.y.dot(Vector3.UP))
	_expect(lowest_up < 0.3, "The roll tips the truck over during the shot (lowest up·Y %.2f)" % lowest_up)
	_expect(bool(root.get_node(^"/root/RunManager").get(&"is_running")), "The level doesn't call the run over mid-shot (its results camera cut into the roll)")
	_expect(van.global_basis.y.dot(Vector3.UP) < 0.5, "...and it stays over, nobody drives it back upright (up·Y %.2f)" % van.global_basis.y.dot(Vector3.UP))
	# Out of the truck, not just left behind where the truck slid away from
	# them (the cargo box is closed: the roll opens its back).
	var thrown: int = 0
	for package: Node in packages:
		if is_instance_valid(package) and not bool(van.call(&"carries", (package as Node3D).global_position)) \
				and (package as Node3D).global_position.distance_to(van.global_position) > 3.0:
			thrown += 1
	_expect(thrown >= 3, "...and its boxes fly out of it (%d out of the truck)" % thrown)
	_expect(van.call(&"is_door_open", &"rear"), "...through its back, burst open")
	_expect(not bool((runner.get(&"level") as Node).get(&"packages")[0].get(&"is_loaded")), "The thrown boxes aren't still counted as loaded on a rack")
	var recorded: Dictionary = (runner.get_node(^"TrailerCamera") as Node).call(&"record_point")
	_expect(recorded.get("space", "") == "truck" and (recorded.at as Array).size() == 3, "Recording a point takes the view relative to the truck")
	runner.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")

	# Mirrored anchors: the rail's +x side is where the thing is.
	var mirror: Node = ShotScript.new()
	var flipped: Transform3D = mirror.call(&"_mirrored_toward", Transform3D.IDENTITY, Vector3(-4.0, 0.0, 0.0))
	_expect((flipped.affine_inverse() * Vector3(-4.0, 0.0, 0.0)).x > 0.0, "A mirrored anchor puts the house or the deer on +x")
	_expect((mirror.call(&"_mirrored_toward", Transform3D.IDENTITY, Vector3(4.0, 0.0, 0.0)) as Transform3D) == Transform3D.IDENTITY, "...and leaves it alone when it already is")
	mirror.free()

	# Played out, fast-forwarded (same physics step, four times the pace).
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	var house_shot: Dictionary = await _play(shots["casa_noche"])
	_expect(house_shot.in_view_at_end, "casa_noche: the truck is in the camera's view as it arrives")
	_expect(house_shot.end_speed_kmh < 2.0 and house_shot.to_stop < 6.0, "casa_noche: it stops at the house (%.1f km/h, %.1f m from the stop)" % [house_shot.end_speed_kmh, house_shot.to_stop])
	var train_shot: Dictionary = await _play(shots["cruce_tren"])
	_expect(train_shot.train_in_view, "cruce_tren: the train goes by in view")
	_expect(train_shot.end_speed_kmh < 2.0 and train_shot.in_view_at_end, "cruce_tren: the truck waits at the barrier, in view (%.1f km/h)" % train_shot.end_speed_kmh)
	_expect(not train_shot.hit_train, "cruce_tren: ...short of the barrier and the train")
	var deer_shot: Dictionary = await _play(shots["ciervo"])
	_expect(deer_shot.deer_crossed, "ciervo: the deer runs across the road")
	_expect(deer_shot.deer_in_view, "ciervo: in the camera's view")
	_expect(not deer_shot.deer_hit, "ciervo: and the truck doesn't hit it")
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	WorldMood.forced_label = ""
	root.get_node(^"/root/NetworkManager").set(&"world_seed", 0)
	root.get_node(^"/root/NetworkManager").set(&"world_house_count", 0)
	if _failures == 0:
		print("PASS: the trailer shots are saved, their worlds found, the rails smooth, and they play out in view")
	quit(_failures)


## Plays `definition` for its duration and reports what the camera saw.
func _play(definition: Dictionary) -> Dictionary:
	var result := {"in_view_at_end": false, "end_speed_kmh": INF, "to_stop": INF, "train_in_view": false, "hit_train": false,
		"deer_crossed": false, "deer_in_view": false, "deer_hit": false}
	var runner: Node = ShotScript.new()
	runner.set(&"autoplay", false)
	root.add_child(runner)
	await runner.call(&"setup", definition)
	var van: VehicleBody3D = runner.get(&"van")
	var route: Node3D = runner.get(&"route")
	var camera := runner.get_node(^"TrailerCamera") as Camera3D
	var focus: Node = runner.get(&"focus")
	var crossing: Node = focus if focus is WildlifeCrossing else null
	var rail_crossing: Node = focus if focus != null and &"will_close" in focus else null
	var started: int = Time.get_ticks_msec()
	while float(runner.get(&"_time")) < float(definition.get("duration", 8.0)):
		await process_frame
		if rail_crossing != null and int(rail_crossing.get(&"state")) == 3:  # TRAIN
			for car: Node in rail_crossing.find_children("*", "AnimatableBody3D", true, false):
				if (car as Node3D).visible and camera.is_position_in_frustum((car as Node3D).global_position + Vector3.UP * 2.0):
					result.train_in_view = true
				if (car as Node3D).visible and (car as Node3D).global_position.distance_to(van.global_position) < 4.5:
					result.hit_train = true
		if crossing != null:
			var deer := crossing.get_node(^"Deer") as Node3D
			# BOLTING (3) on: it ran in, froze in the lights and is crossing.
			if int(crossing.get(&"state")) >= 3:
				result.deer_crossed = true
			if deer.visible and absf(crossing.to_local(deer.global_position).x) < 4.0 and camera.is_position_in_frustum(deer.global_position + Vector3.UP):
				result.deer_in_view = true
			if int(crossing.get(&"state")) == 4:  # TUMBLING: the truck hit it
				result.deer_hit = true
		if Time.get_ticks_msec() - started > 120000:
			break
	result.in_view_at_end = camera.is_position_in_frustum(van.global_position + Vector3.UP)
	result.end_speed_kmh = float(van.get(&"speed_kmh"))
	if bool(runner.get(&"_stopping")):
		result.to_stop = van.global_position.distance_to(runner.get(&"stop_point"))
	runner.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")
	return result


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

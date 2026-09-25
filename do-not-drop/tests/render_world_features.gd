extends SceneTree
## Run without --headless (revisor-visual). A look at the batch of 2026-09-25,
## one PNG per view under user:// (render_wf_<part>_<view>.png):
##   <godot> --path do-not-drop --resolution 1280x720 --script res://tests/render_world_features.gd -- --part=towns
## Parts (default: all of them, one after the other):
##   towns     N-601 a town's entry sign from the driver's seat, 35 m and 12 m out, and its exit sign
##   stories   N-602 each roadside story, from the road
##   vehicles  N-306 the tractor out in a field, the competition's van parked in a village
##   seasons   N-305 the same stretch of forest in summer and in autumn
##   night     N-304 a village at night: street lamps, parked cars' lamps, lit windows
##   truck     N-301 the truck's seams from the side, the back and the front
##   rain      N-303 drops and a wiper from the driver's seat, in the rain
##   door      N-604 the neighbour's reaction to a ruined box, and the note left when nobody rang
##   depot     N-603 "Días sin accidentes" and the photo wall
##   look      N-504 the driver's view at its highest and its most turned

const EYE_HEIGHT: float = 2.3

var camera: Camera3D
var _part: String = "all"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--part="):
			_part = arg.get_slice("=", 1)
	for part: String in ["towns", "stories", "vehicles", "seasons", "night", "truck", "rain", "door", "depot", "look"]:
		if _part == "all" or _part == part:
			await call(StringName("_part_" + part))
	quit()


# --- Parts --------------------------------------------------------------------

func _part_towns() -> void:
	var level: Node3D = await _level(4242, 3, "soleado_dia_verano")
	var route: Node3D = level.get_node(^"World/Route")
	var signs: Array = route.find_children("*", "TownSign", true, false)
	for sign_node: Node3D in signs.slice(0, 2):
		var kind: String = "exit" if bool(sign_node.get(&"is_exit")) else "entry"
		for distance: float in [35.0, 12.0]:
			await _from_road_before(route, sign_node, distance, "towns_%s_%dm" % [kind, int(distance)])
	await _free(level)


func _part_stories() -> void:
	var seen: Dictionary = {}
	for seed_value: int in [4242, 777, 11, 90210, 31337, 5, 606, 2024]:
		if seen.size() == 3:
			break
		var level: Node3D = await _level(seed_value, 4, "soleado_dia_verano")
		var route: Node3D = level.get_node(^"World/Route")
		for story: Node3D in route.find_children("*", "RoadsideStory", true, false):
			var kind: int = int(story.get(&"kind"))
			if seen.has(kind):
				continue
			seen[kind] = true
			await _from_road_before(route, story, 25.0, "stories_%s" % ["van_spill", "hen", "billboard"][kind])
			await _shot(story.global_position + Vector3(6.0, 3.0, 6.0), story.global_position + Vector3.UP * 0.8, "stories_%s_close" % ["van_spill", "hen", "billboard"][kind])
		await _free(level)


func _part_vehicles() -> void:
	var found: Dictionary = {}
	for seed_value: int in [777, 11, 4242, 90210, 31337, 2024, 5, 606]:
		if found.size() == 2:
			break
		var level: Node3D = await _level(seed_value, 5, "soleado_dia_verano")
		var route: Node3D = level.get_node(^"World/Route")
		for node: Node in route.find_children("*", "Node3D", true, false):
			var rule: StringName = node.get_meta(&"rule", &"")
			if (rule == &"tractor" or rule == &"competitor_van") and not found.has(rule):
				found[rule] = true
				await _from_road_before(route, node, 20.0, "vehicles_%s" % rule)
				await _shot((node as Node3D).global_position + Vector3(5.0, 2.5, 5.0), (node as Node3D).global_position + Vector3.UP, "vehicles_%s_close" % rule)
		await _free(level)


func _part_seasons() -> void:
	for mood: String in ["soleado_dia_verano", "soleado_dia_otono"]:
		var level: Node3D = await _level(4242, 2, mood)
		var route: Node3D = level.get_node(^"World/Route")
		var path: Array = route.get(&"_path_points")
		var index: int = mini(24, path.size() - 2)
		var at: Vector3 = route.to_global(path[index])
		var ahead: Vector3 = route.to_global(path[index + 3])
		await _shot(at + Vector3.UP * EYE_HEIGHT, ahead + Vector3.UP * 1.5, "seasons_%s" % mood.get_slice("_", 2))
		await _free(level)


func _part_night() -> void:
	var level: Node3D = await _level(4242, 3, "soleado_noche")
	var route: Node3D = level.get_node(^"World/Route")
	var house: Node3D = (route.get(&"houses") as Array)[0]
	await _from_road_before(route, house, 60.0, "night_village_60m")
	await _from_road_before(route, house, 25.0, "night_village_25m")
	for node: Node in route.find_children("*", "Node3D", true, false):
		if node.get_meta(&"rule", &"") == &"parked_vehicle":
			await _shot((node as Node3D).global_position + (node as Node3D).global_basis.x * 7.0 + Vector3.UP * 2.0, (node as Node3D).global_position + Vector3.UP * 0.7, "night_parked_car")
			break
	await _free(level)


func _part_truck() -> void:
	var level: Node3D = await _level(4242, 1, "soleado_dia_verano")
	var van: VehicleBody3D = level.get(&"vehicle")
	for view: Array in [["side", Vector3(-6.5, 1.6, 0.8)], ["rear", Vector3(-2.0, 1.8, 8.0)], ["front", Vector3(2.5, 1.8, -7.0)]]:
		await _shot(van.to_global(view[1]), van.to_global(Vector3(0.0, 1.2, 0.8)), "truck_%s" % view[0])
	await _free(level)


func _part_rain() -> void:
	var level: Node3D = await _level(4242, 1, "lluvia_dia")
	level.call(&"start_debug_delivery")
	for i: int in range(90):
		await process_frame
	var van: VehicleBody3D = level.get(&"vehicle")
	var seat := van.get_node(^"CabinInterior/DriverEyePoint/FirstPersonCamera") as Camera3D
	seat.make_current()
	for i: int in range(20):
		await process_frame
	await _grab("rain_driver_view")
	for i: int in range(30):
		await process_frame
	await _grab("rain_driver_view_later")
	camera.make_current()
	await _free(level)


func _part_door() -> void:
	var level: Node3D = await _level(4242, 2, "soleado_dia_verano")
	var route: Node3D = level.get_node(^"World/Route")
	var houses: Array = route.get(&"houses")
	var bus: Node = root.get_node(^"/root/EventBus")
	bus.emit_signal(&"house_delivery_recorded", 0, &"delivered_ruined", &"")
	for i: int in range(20):
		await process_frame
	var house: Node3D = houses[0]
	var front: Vector3 = -house.global_basis.z
	await _shot(house.global_position + front * 7.0 + Vector3.UP * 2.0, house.global_position + front * 2.7 + Vector3.UP * 1.4, "door_ruined")
	bus.emit_signal(&"house_delivery_recorded", 1, &"missed", &"")
	var other: Node3D = houses[1]
	var other_front: Vector3 = -other.global_basis.z
	await _shot(other.global_position + other_front * 4.0 + Vector3.UP * 1.6, other.global_position + other_front * 2.2 + Vector3.UP * 1.25, "door_note")
	await _free(level)


func _part_depot() -> void:
	var Board = load("res://scripts/gameplay/depot/depot_campaign_board.gd")
	var photo := Image.create(160, 110, false, Image.FORMAT_RGB8)
	photo.fill(Color(0.45, 0.6, 0.35))
	for run: int in range(3):
		Board.record_run({"cargo_ruined": 0}, {0: photo, 1: photo})
	var level: Node3D = await _level(4242, 1, "soleado_dia_verano")
	var depot: Node3D = level.get(&"depot")
	var board: Node3D = level.find_child("CampaignBoard", true, false)
	var sign_node: Node3D = board.get_node(^"AccidentSign")
	await _shot(sign_node.global_position + Vector3(0.0, 0.0, 5.0), sign_node.global_position, "depot_days_sign")
	await _shot(depot.to_global(Vector3(0.0, 1.7, 14.0)), sign_node.global_position, "depot_days_sign_from_floor")
	var wall: Node3D = board.get_node(^"PhotoWall")
	await _shot(wall.global_position + Vector3(-3.0, -0.4, 0.0), wall.global_position, "depot_photo_wall")
	await _free(level)


func _part_look() -> void:
	var level: Node3D = await _level(4242, 1, "soleado_dia_verano")
	level.call(&"start_debug_delivery")
	for i: int in range(30):
		await process_frame
	var van: VehicleBody3D = level.get(&"vehicle")
	var seat := van.get_node(^"CabinInterior/DriverEyePoint/FirstPersonCamera") as Camera3D
	seat.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	seat.call(&"_apply_look", Vector2(0.0, -100000.0))
	seat.call(&"_process", 0.0)
	await _grab("look_up_max")
	seat.call(&"reset_look")
	seat.call(&"_apply_look", Vector2(-100000.0, 0.0))
	seat.call(&"_process", 0.0)
	await _grab("look_turned_max")
	camera.make_current()
	await _free(level)


# --- Helpers ------------------------------------------------------------------

func _level(seed_value: int, houses: int, mood: String) -> Node3D:
	root.get_node(^"/root/NetworkManager").set(&"world_seed", seed_value)
	root.get_node(^"/root/NetworkManager").set(&"world_house_count", houses)
	WorldMood.forced_label = mood
	var level: Node3D = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	for layer: Node in level.find_children("*", "CanvasLayer", false, false):
		(layer as CanvasLayer).hide()
	for child: Node in level.get_node(^"World").get_children():
		if child.is_in_group(&"player"):
			(child as Node3D).hide()
	camera = Camera3D.new()
	camera.far = 600.0
	camera.fov = 70.0
	level.add_child(camera)
	camera.make_current()
	for _i in range(6):
		await process_frame
	return level


func _free(level: Node) -> void:
	level.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")
	WorldMood.forced_label = ""


## From the road, at the driver's eye height, `distance` metres before the
## point of the road nearest `target`, looking at it.
func _from_road_before(route: Node3D, target: Node3D, distance: float, name: String) -> void:
	var path: Array = route.get(&"_path_points")
	var local: Vector3 = route.to_local(target.global_position)
	var nearest: int = 0
	for index: int in range(path.size()):
		if Vector2((path[index] as Vector3).x - local.x, (path[index] as Vector3).z - local.z).length() < Vector2((path[nearest] as Vector3).x - local.x, (path[nearest] as Vector3).z - local.z).length():
			nearest = index
	var left: float = distance
	var i: int = nearest
	var at: Vector3 = path[nearest]
	while i > 0 and left > 0.0:
		var step: float = (path[i] as Vector3).distance_to(path[i - 1])
		if step >= left:
			at = (path[i] as Vector3).lerp(path[i - 1], left / step)
			left = 0.0
		else:
			left -= step
			i -= 1
			at = path[i]
	await _shot(route.to_global(at) + Vector3.UP * EYE_HEIGHT, target.global_position + Vector3.UP * 1.5, name)


func _shot(from: Vector3, at: Vector3, name: String) -> void:
	camera.make_current()
	camera.global_position = from
	if not from.is_equal_approx(at):
		camera.look_at(at, Vector3.UP)
	for _i in range(8):
		await process_frame
	await _grab(name)


func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "user://render_wf_%s.png" % name
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_depot.gd
##
## The depot every delivery starts from (depot.gd):
##   - every package is on a dispatch shelf with its own bin code, resting on
##     the shelf, and the crew spawns inside, under the roof (no rain);
##   - the board posts one order per house, each a different kind of box, and
##     the pickup prompt names the bin so the right one can be found;
##   - the stations open their screen on the player who used them;
##   - supplies cost team money, once each, and the padding softens every
##     loaded box for the run that takes it;
##   - leaving without an ordered box is called out;
##   - the door stays open while anyone is inside on foot, and rolls down once
##     the truck is out;
##   - in Endless the board shows the goal and the distance record, not an
##     empty order list;
##   - signage (N-503): every place has a hanging sign, arrows on the floor
##     by the spawn point at each station and chevrons beside the truck at
##     the door, and at least four signs read from where the crew appears.

## Where the crew appears, looking at the truck: render_depot.gd's spawn_view
## (72°), and each of the first four spawn points at the game's default 82°.
const SPAWN_EYE := Vector3(0.0, 1.65, 17.4)
const SPAWN_LOOK := Vector3(0.0, 1.5, 5.0)
const SCREEN := Vector2(1920.0, 1080.0)
## Smallest letter (the font's em, on a 1080p screen) that counts as readable.
const READABLE_PX: float = 20.0

var _failures: int = 0
var _opened: Array[StringName] = []
var _notices: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var crew: Node = root.get_node(^"/root/CrewProgression")
	crew.call(&"reset_campaign")
	# Every trap unlocked: locked ones stay off the depot's shelves
	# (depot.gd withhold_locked), and the test profile's unlocks depend on
	# whichever tests ran before this one.
	for unlock_id: StringName in (root.get_node(^"/root/UnlockManager").get(&"TRAP_UNLOCKS") as Dictionary).values():
		root.get_node(^"/root/UnlockManager").unlocked[unlock_id] = true
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	await physics_frame
	var depot: Node3D = level.get_node(^"World/Depot")
	var bus: Node = root.get_node(^"/root/EventBus")
	bus.connect(&"depot_station_opened", func(station: StringName) -> void: _opened.append(station))
	bus.connect(&"depot_notice", func(text: String) -> void: _notices.append(text))

	# Stock: every box shelved, each in its own bin, standing on the deck.
	var packages: Array = level.get(&"packages")
	_expect(packages.size() == 14, "Two boxes of every kind in the depot (got %d)" % packages.size())
	var codes: Dictionary = {}
	for package: Node3D in packages:
		var code: String = String(package.get_meta(&"dispatch_code", ""))
		_expect(not code.is_empty(), "%s has a bin code" % package.get(&"package_id"))
		codes[code] = true
		var local: Vector3 = depot.to_local(package.global_position)
		_expect(local.z > 14.0 and local.z < 24.0 and local.x < -5.0, "%s sits on the dispatch shelves (at %s)" % [package.get(&"package_id"), local])
		var content: Resource = package.call(&"content_definition")
		var bottom: float = local.y - float((content.get(&"box_size") as Vector3).y) * 0.5
		_expect(bottom > 0.3 and (absf(bottom - 0.36) < 0.03 or absf(bottom - 1.51) < 0.03), "%s rests on its deck (bottom at %.2f)" % [package.get(&"package_id"), bottom])
	_expect(codes.size() == packages.size(), "No two boxes share a bin (%d codes)" % codes.size())
	var prompt: String = packages[0].get_node(^"InteractionArea").call(&"get_prompt")
	_expect(prompt.contains(String(packages[0].get_meta(&"dispatch_code"))), "The pickup prompt names the bin (%s)" % prompt)

	# Spawn and roof.
	var player: Node3D = level.local_player
	_expect(bool(depot.call(&"covers", player.global_position)), "The crew spawns inside the depot")
	_expect(not bool(depot.call(&"covers", depot.to_global(Vector3(0.0, 1.0, -5.0)))), "The forecourt isn't under the roof")
	_test_signage(depot)

	# Orders: one per house, all different kinds, written on the board.
	var orders: Array = depot.get(&"orders")
	var houses: Array = level.get_node(^"World/Route").get(&"houses")
	_expect(orders.size() == houses.size(), "One order per house (%d for %d)" % [orders.size(), houses.size()])
	var row: Label3D = depot.get_node(^"OrderBoard/Row0")
	_expect(row.text.contains(String(orders[0].code)), "The board shows the first order's bin (%s)" % row.text)

	# Stations: the screen opens on whoever used it.
	for station: StringName in [&"orders", &"garage", &"wardrobe", &"shop", &"records"]:
		var node: Node = depot.get_node(NodePath("Station_%s" % station))
		_expect(bool(node.call(&"can_interact", player)), "The %s station can be used before the run" % station)
		node.call(&"interact", player)
	_expect(_opened == [&"orders", &"garage", &"wardrobe", &"shop", &"records"], "Each station opens its screen (got %s)" % str(_opened))

	# Supplies: paid from team money, one of each.
	var start_money: int = int(crew.get(&"team_money"))
	depot.call(&"buy_supply", &"padding")
	depot.call(&"buy_supply", &"padding")
	var padding_cost: int = int(crew.get(&"SUPPLIES")[&"padding"]["cost"])
	_expect(int(crew.get(&"team_money")) == start_money - padding_cost, "Padding is paid once (money %d)" % int(crew.get(&"team_money")))
	_expect((depot.get(&"supplies") as Array).has(&"padding"), "The depot shows the padding waiting")
	_expect((depot.get_node(^"Supply_padding") as Node3D).visible, "The bought padding sits on the counter")

	# Leave with a box that isn't on the order: padding applies, and the
	# forgotten order is called out.
	var ordered_id: StringName = orders[0].package_id
	var other: Node = null
	for package: Node in packages:
		if package.get(&"package_id") != ordered_id:
			other = package
			break
	player.call(&"pick_up", other.get_path())
	level.vehicle.get_node(^"CargoBay/LeftSeat1PackageMount/InteractionArea").call(&"interact", player)
	_expect(bool(depot.call(&"_anyone_on_foot_inside")), "Someone on foot inside counts as inside")
	level.vehicle.call(&"set_door_open", &"cab_left", true)
	level.vehicle.get_node(^"CabinInterior/DriverEyePoint/InteractionArea").call(&"interact", player)
	await process_frame
	_expect(bool(root.get_node(^"/root/RunManager").get(&"is_running")), "Taking the wheel with cargo starts the run")
	_expect(is_equal_approx(float(other.get(&"impact_absorption")), 0.75), "Padding softens the loaded box")
	_expect((crew.get(&"supplies") as Dictionary).is_empty(), "The run used the supplies up")
	_expect(_notices.any(func(text: String) -> bool: return text.contains("sin el pedido")), "Leaving without the ordered box is called out (%s)" % str(_notices))
	_expect(not bool(depot.call(&"_anyone_on_foot_inside")), "The driver is aboard, not on foot")
	for station: StringName in [&"orders", &"shop"]:
		_expect(not bool(depot.get_node(NodePath("Station_%s" % station)).call(&"can_interact", player)), "The %s station closes once the run is on" % station)

	# The door: open while the truck is inside, down once it's out.
	var door: Node = depot.get(&"door")
	await physics_frame
	_expect(bool(door.get(&"is_open")), "The door stays open while the truck is inside")
	var vehicle: RigidBody3D = level.vehicle
	vehicle.global_position = depot.to_global(Vector3(0.0, 1.2, -12.0))
	vehicle.linear_velocity = Vector3.ZERO
	for tick: int in range(4):
		await physics_frame
	_expect(not bool(door.get(&"is_open")), "The door closes behind the truck")
	_expect(_notices.any(func(text: String) -> bool: return text.contains("portón")), "The crew is told the door closed")

	level.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")
	crew.call(&"reset_campaign")
	await create_timer(0.1).timeout
	await _test_endless_board()
	if _failures == 0:
		print("PASS: depot stocks every box in its bin, posts the orders, sells supplies and closes behind the truck")
	quit(_failures)


## Signage (tareas de Nacho N-503), with the truck parked in its bay.
func _test_signage(depot: Node3D) -> void:
	var captions: Array = []
	for label: Node in get_nodes_in_group(&"depot_sign"):
		if not captions.has(String(label.get_meta(&"sign"))):
			captions.append(String(label.get_meta(&"sign")))
	for place: String in ["PIZARRA", "ESTANTE", "CAMIÓN", "PORTÓN", "TALLER", "VESTUARIO", "SUMINISTROS"]:
		_expect(captions.any(func(caption: String) -> bool: return caption.contains(place)), "A hanging sign names %s (signs: %s)" % [place, captions])

	# Floor arrows: from around the spawn to each station, and to the door.
	# The depot's constants through its script: naming the class here would
	# compile depot.gd before the autoloads exist (depot.gd _autoload()).
	var layout: Dictionary = (depot.get_script() as Script).get_script_constant_map()
	var spawn_centre := Vector3.ZERO
	for point: Vector3 in layout.SPAWN_POINTS:
		spawn_centre += Vector3(point.x, 0.0, point.z) / (layout.SPAWN_POINTS as Array).size()
	var shelf_face_x: float = float(layout.SHELF_UNITS[0].x) + float(layout.SHELF_DEPTH) * 0.5
	var shelf_end_z: float = float(layout.SHELF_START_Z) + float(layout.BAY_LENGTH) * int(layout.BAYS)
	var targets := {
		"PIZARRA": (depot.get_node(^"Station_orders") as Node3D).position,
		"TALLER": (depot.get_node(^"Station_garage") as Node3D).position,
		"VESTUARIO": (depot.get_node(^"Station_wardrobe") as Node3D).position,
		"SUMINISTROS": (depot.get_node(^"Station_shop") as Node3D).position,
	}
	var guides: Array = depot.get(&"guides")
	for caption: String in ["PIZARRA", "ESTANTES", "TALLER", "VESTUARIO", "SUMINISTROS", "PORTÓN"]:
		var mine: Array = guides.filter(func(guide: Dictionary) -> bool: return guide.caption == caption)
		_expect(not mine.is_empty(), "An arrow on the floor leads to %s" % caption)
		for guide: Dictionary in mine:
			var at: Vector3 = guide.at
			var target: Vector3 = targets.get(caption, Vector3.ZERO)
			if caption == "ESTANTES":
				target = Vector3(shelf_face_x, 0.0, clampf(at.z, float(layout.SHELF_START_Z), shelf_end_z))
			elif caption == "PORTÓN":
				# Anywhere through the opening, half a metre clear of the jambs.
				var half_door: float = float(layout.DOOR_WIDTH) * 0.5 - 0.5
				target = Vector3(clampf(at.x, -half_door, half_door), 0.0, 0.0)
			var off: float = rad_to_deg((Vector3(target.x, 0.0, target.z) - at).angle_to(guide.direction))
			_expect(off < 25.0, "The %s arrow at %s points at it (%.0f° off)" % [caption, at, off])
			if caption != "PORTÓN":
				_expect(at.distance_to(spawn_centre) < 7.0, "The %s arrow starts by the spawn (%.1f m away)" % [caption, at.distance_to(spawn_centre)])

	# Readable from where the crew appears.
	var views: Array = [[Transform3D(Basis.IDENTITY, SPAWN_EYE).looking_at(SPAWN_LOOK), 72.0, "the spawn view"]]
	for index: int in range(4):
		var point: Vector3 = layout.SPAWN_POINTS[index]
		views.append([Transform3D(Basis.IDENTITY, Vector3(point.x, SPAWN_EYE.y, point.z)), 82.0, "spawn point %d" % index])
	for view: Array in views:
		var readable: Array = _readable_signs(depot, depot.global_transform * (view[0] as Transform3D), float(view[1]))
		_expect(readable.size() >= 4, "At least four signs read from %s (got %s)" % [view[2], readable])


## Captions of the hanging signs readable from `eye`: every word on the front
## face inside the picture, facing the camera, at least READABLE_PX tall,
## with nothing solid in the way and not behind a nearer sign.
func _readable_signs(depot: Node3D, eye: Transform3D, fov: float) -> Array:
	var focal: float = SCREEN.y * 0.5 / tan(deg_to_rad(fov * 0.5))
	var space := depot.get_world_3d().direct_space_state
	var rects: Dictionary = {}  # caption -> Rect2 on screen
	var depths: Dictionary = {}  # caption -> nearest depth
	var failed: Dictionary = {}  # caption -> true
	for node: Node in get_nodes_in_group(&"depot_sign"):
		var label := node as Label3D
		if not bool(label.get_meta(&"front")):
			continue
		var caption: String = label.get_meta(&"sign")
		var centre: Vector3 = label.global_position
		var em: float = label.font_size * label.pixel_size
		var half_width: float = label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size * 0.5
		var across: Vector3 = label.global_basis.x.normalized() * half_width
		var up: Vector3 = label.global_basis.y.normalized() * em * 0.5
		var depth: float = -(eye.affine_inverse() * centre).z
		var ok: bool = depth > 0.3
		ok = ok and label.global_basis.z.normalized().dot((eye.origin - centre).normalized()) > 0.35
		ok = ok and focal * em / depth >= READABLE_PX
		var pixels: Array[Vector2] = []
		for corner: Vector3 in [centre - across - up, centre + across - up, centre - across + up, centre + across + up]:
			var local: Vector3 = eye.affine_inverse() * corner
			if local.z > -0.1:
				ok = false
				continue
			pixels.append(Vector2(SCREEN.x * 0.5 + focal * local.x / -local.z, SCREEN.y * 0.5 - focal * local.y / -local.z))
		var rect := Rect2(pixels[0], Vector2.ZERO) if not pixels.is_empty() else Rect2()
		for pixel: Vector2 in pixels:
			ok = ok and Rect2(Vector2.ZERO, SCREEN).has_point(pixel)
			rect = rect.expand(pixel)
		for probe: Vector3 in [centre, centre - across * 0.9, centre + across * 0.9]:
			ok = ok and space.intersect_ray(PhysicsRayQueryParameters3D.create(eye.origin, probe, 3)).is_empty()
		if not ok:
			failed[caption] = true
		rects[caption] = (rects[caption] as Rect2).merge(rect) if rects.has(caption) else rect
		depths[caption] = minf(float(depths.get(caption, INF)), depth)
	var readable: Array = []
	for caption: String in rects:
		if failed.has(caption):
			continue
		var covered: bool = false
		for other: String in rects:
			if other != caption and float(depths[other]) < float(depths[caption]) and (rects[other] as Rect2).intersects(rects[caption]):
				covered = true
		if not covered:
			readable.append(caption)
	return readable


## Endless (tareas de Nacho N-101): the same depot, no houses and so no
## orders; the board sets the goal and shows the distance record instead of
## an empty list, and the door is already open for the truck.
func _test_endless_board() -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	var record := {"score": 1234, "date": "2026-09-24", "mode": manager.get(&"MODE_ENDLESS")}
	# First in the list: best_score() takes the first entry of the mode.
	(manager.get(&"leaderboard") as Array).insert(0, record)
	var posted: Array = []
	var on_posted := func(list: Array) -> void: posted.append(list)
	root.get_node(^"/root/EventBus").connect(&"depot_orders_posted", on_posted)
	var level: Node = load("res://scenes/gameplay/level_endless.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var depot: Node3D = level.get_node(^"World/Depot")
	_expect((depot.get(&"orders") as Array).is_empty(), "Endless posts no orders")
	_expect(posted.all(func(list: Array) -> bool: return list.is_empty()), "Nobody is told about orders in Endless (%s)" % str(posted))
	var title: String = (depot.get_node(^"OrderBoard/Title") as Label3D).text
	var rule: String = (depot.get_node(^"OrderBoard/Rule") as Label3D).text
	var rows: String = (depot.get_node(^"OrderBoard/Row0") as Label3D).text + "
" + (depot.get_node(^"OrderBoard/Row1") as Label3D).text
	_expect(title == "RUTA SIN FIN", "The board is headed for Endless, not today's orders (%s)" % title)
	_expect(rule.contains("lejos"), "The board says the goal: as far as possible (%s)" % rule)
	_expect(rows.contains("1234 m"), "The board shows the distance record (%s)" % rows)
	_expect(bool((depot.get(&"door") as Node).get(&"is_open")), "The door is open: nothing to wait for before driving out")
	root.get_node(^"/root/EventBus").disconnect(&"depot_orders_posted", on_posted)
	(manager.get(&"leaderboard") as Array).erase(record)
	level.queue_free()
	await process_frame
	manager.call(&"reset_run")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

extends Node3D
## Offline N-950 playtest: actual truck, cargo, player and doorbells on the
## seeded street graph. Completion stays in memory; campaign scoring is pending.

const TOWN := preload("res://scenes/gameplay/town/town_prototype.tscn")
const NAVIGATION := preload("res://modules/town_gen/town_navigation.gd")
const ART := preload("res://scripts/gameplay/town/town_art.gd")
const OPEN_DISTRICTS: Array[int] = [0, 1]

@export var world_seed: int = 0

var town: Node3D
var vehicle: Node3D
var local_player: Node3D
var houses: Array[Node3D] = []
var packages: Array[Node3D] = []
var order_lots: Array[Dictionary] = []
var destinations: PackedVector2Array = PackedVector2Array()
var depot_frontage: Vector2
var center_frontage: Vector2
var exploring_center: bool = false
var selected_house: int = 0
var finished: bool = false
var gps: Node3D
var _owns_run: bool = false
var _status: Label
var _prompt: Label
var _refresh: float = 0.0


func _ready() -> void:
	if NetworkManager.is_online():
		push_warning("Town playtest requires an offline session")
		return
	_owns_run = true
	RunManager.reset_run()
	town = TOWN.instantiate()
	town.set(&"world_seed", world_seed)
	town.set(&"enable_camera", false)
	town.set(&"built_districts", PackedInt32Array(OPEN_DISTRICTS))
	add_child(town)
	world_seed = int(town.get(&"world_seed"))
	_build_center_destination()
	order_lots = delivery_lots(town.get(&"plan"))
	_build_customers()
	_build_vehicle()
	_settle_vehicle.call_deferred()
	_build_player()
	_build_overlay()
	RunManager.expected_houses = houses.size()
	_refresh_status()


## Keep the first three orders stable and add three existing center homes.
## Selection is data-only, independent of node construction or player order.
static func delivery_lots(plan: Dictionary) -> Array[Dictionary]:
	var initial: Array[Dictionary] = []
	var center: Array[Dictionary] = []
	for lot: Dictionary in plan.lots:
		if lot.district == 0 and lot.role == &"house":
			initial.append(lot)
		elif lot.district == 1 and lot.role == &"residential":
			center.append(lot)
	initial.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a.address.y < b.address.y
	)
	center.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.address.y < b.address.y)
	for index: int in range(mini(3, center.size())):
		initial.append(center[index])
	return initial


func _build_customers() -> void:
	var parcels: Dictionary = {}
	var depot: Node3D
	var depot_lot: Dictionary
	for parcel: Node in town.get_children():
		if not parcel.has_meta(&"lot"):
			continue
		var lot: Dictionary = parcel.get_meta(&"lot")
		parcels[lot.address] = parcel
		if lot.role == &"depot":
			depot_frontage = lot.frontage
			depot = parcel as Node3D
			depot_lot = lot
	for index: int in range(order_lots.size()):
		var lot: Dictionary = order_lots[index]
		_build_customer(parcels[lot.address], lot, index)
	_build_packages(depot, depot_lot)


func _build_customer(parcel: Node3D, lot: Dictionary, index: int) -> void:
	var house_script: Script = load("res://scripts/gameplay/route/delivery_house.gd")
	var variant: int = ART.customer_variant(world_seed, index)
	if lot.district == 1:
		# Retain the already fitted center model when activating its doorbell.
		variant = int(parcel.get_node(^"Building").get_meta(&"house_variant"))
	for child: Node in parcel.get_children():
		if child.name != &"Yard":
			child.free()
	var house := Node3D.new()
	house.set_script(house_script)
	house.name = "Customer_%d" % (index + 1)
	house.set(&"house_index", index)
	house.set(&"assigned_package_id", StringName("town_%d" % (index + 1)))
	house.set(&"assigned_label", "%s %s" % [tr("HUD_HANDLING_FRAGILE"), String.chr(65 + index)])
	house.set(&"visual_variant", variant)
	house.set_meta(&"district", lot.district)
	house.set_meta(&"address", lot.address)
	var direction: Vector2 = (lot.frontage - lot.position).normalized()
	var front: Vector2 = (lot.frontage - lot.position).rotated(-float(lot.angle))
	house.position = Vector3(0, .08, -signf(front.y) * float(lot.size.y) * .12)
	# Authored house fronts face local -Z, toward their street frontage.
	house.rotation.y = atan2(-direction.x, -direction.y) - parcel.rotation.y
	parcel.add_child(house)
	# Smaller city lots need compact order markers beside their porches.
	var marker: Node3D = house.get(&"waiting_marker")
	marker.get_node(^"OrderSign").scale = Vector3.ONE * .7
	var balloon: MeshInstance3D = marker.get_node(^"Balloon/BalloonBall")
	var sphere: SphereMesh = balloon.mesh
	sphere.radius *= .6
	sphere.height *= .6
	balloon.get_node(^"Knot").position.y *= .6
	house.connect(&"resolved", _on_resolved.bind(index))
	var sign_height: float = 9.2 if variant == 3 else 6.0
	town.call(&"_sign", house, tr("WORLD_HOUSE_NUMBER") % (index + 1), Vector3(0, sign_height, 0))
	houses.append(house)
	destinations.append(lot.frontage)


func _build_packages(parcel: Node3D, lot: Dictionary) -> void:
	var front: Vector2 = (lot.frontage - lot.position).rotated(-float(lot.angle))
	var z: float = signf(front.y) * float(lot.size.y) * .35
	ART.loading_rack(parcel, z)
	var package_scene: PackedScene = load("res://scenes/gameplay/package/package.tscn")
	var mount_script: Script = load("res://scripts/gameplay/interaction/package_mount_point.gd")
	for index: int in range(houses.size()):
		var marker := Marker3D.new()
		marker.name = "OrderMount_%d" % index
		var height: float = 1.515 if index < 3 else .665
		marker.position = Vector3((index % 3 - 1) * 2.0, height, z)
		if index >= 3:
			# Keep lower boxes within the deck, forward of the upper shelf's lip.
			marker.position.z += signf(front.y) * .15
		parcel.add_child(marker)
		var mount := Area3D.new()
		mount.set_script(mount_script)
		mount.name = "InteractionArea"
		mount.set(&"prompt", "HUD_PROMPT_PLACE_PACKAGE")
		mount.add_to_group(&"package_mount")
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = .5
		collision.shape = shape
		mount.add_child(collision)
		marker.add_child(mount)
		var package: Node3D = package_scene.instantiate()
		package.name = "Order_%d" % (index + 1)
		package.set(&"package_id", StringName("town_%d" % (index + 1)))
		package.set_meta(&"dispatch_code", String.chr(65 + index))
		package.set_meta(&"district", order_lots[index].district)
		add_child(package)
		mount.call(&"store", package)
		packages.append(package)
		var code := Label3D.new()
		code.text = "%d · %s" % [index + 1, String.chr(65 + index)]
		code.position = Vector3(0, .4, signf(front.y) * .7)
		code.font_size = 32
		code.pixel_size = .01
		code.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.add_child(code)


func _build_vehicle() -> void:
	var scene: PackedScene = load("res://scenes/gameplay/vehicle/vehicle.tscn")
	vehicle = scene.instantiate()
	vehicle.name = "Vehicle"
	vehicle.position = Vector3(depot_frontage.x, 2, depot_frontage.y)
	var plan: Dictionary = town.get(&"plan")
	var nearest: float = INF
	for edge: Dictionary in plan.edges:
		if edge.district != 0:
			continue
		var a: Vector2 = plan.nodes[edge.a]
		var b: Vector2 = plan.nodes[edge.b]
		var distance: float = depot_frontage.distance_to(
			Geometry2D.get_closest_point_to_segment(depot_frontage, a, b)
		)
		if distance < nearest:
			nearest = distance
			var forward: Vector2 = (b - a).normalized()
			vehicle.rotation.y = atan2(-forward.x, -forward.y)
	vehicle.set(&"controls_enabled", false)
	vehicle.set(&"freeze", true)
	add_child(vehicle)
	vehicle.call(&"set_door_open", &"cab_left", true)
	vehicle.get_node(^"CabinInterior/DriverEyePoint/InteractionArea").connect(
		&"interacted", _on_boarded
	)
	gps = vehicle.find_child("DashboardGps", true, false) as Node3D
	if gps != null:
		gps.set(&"guidance_provider", Callable(self, &"guidance"))


func _settle_vehicle() -> void:
	# Dynamically created road colliders become queryable after a physics tick.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if is_instance_valid(vehicle):
		vehicle.call(&"_snap_to_ground")
		vehicle.reset_physics_interpolation()


func _build_player() -> void:
	var scene: PackedScene = load("res://scenes/gameplay/player/player.tscn")
	local_player = scene.instantiate()
	local_player.name = "Player_1"
	local_player.position = vehicle.to_global(Vector3(-3, 0, -2))
	local_player.rotation.y = vehicle.rotation.y + PI * .5
	add_child(local_player)


func _on_boarded(_player: Node) -> void:
	if finished or RunManager.is_running:
		return
	RunManager.call(&"_begin_run", RunManager.MODE_DELIVERY)
	vehicle.set(&"freeze", false)
	vehicle.set(&"sleeping", false)
	for package: Node3D in packages:
		if is_instance_valid(package) and bool(package.call(&"is_aboard")):
			package.set(&"freeze", false)
			package.call(&"report_to_run")


func _on_resolved(outcome: StringName, package_id: StringName, index: int) -> void:
	exploring_center = false
	RunManager.register_delivery(
		index, outcome, package_id, bool(houses[index].get(&"handed_over_open"))
	)
	if selected_house == index:
		selected_house = -1
		for i: int in range(houses.size()):
			if not bool(houses[i].get(&"delivered")):
				selected_house = i
				break
	_refresh_status()


func select_house(index: int) -> void:
	if index >= 0 and index < houses.size() and not bool(houses[index].get(&"delivered")):
		exploring_center = false
		selected_house = index
		_refresh_status()


## A stop on the center's street nearest its plaza, never a route over the lawn.
func _build_center_destination() -> void:
	var plan: Dictionary = town.get(&"plan")
	var target: Vector2 = plan.districts[1].center
	for green: Dictionary in plan.green_areas:
		if green.district == 1 and green.kind == &"plaza":
			target = green.position
			break
	var nearest: float = INF
	for edge: Dictionary in plan.edges:
		if edge.district != 1:
			continue
		var at: Vector2 = Geometry2D.get_closest_point_to_segment(
			target, plan.nodes[edge.a], plan.nodes[edge.b]
		)
		if at.distance_squared_to(target) < nearest:
			nearest = at.distance_squared_to(target)
			center_frontage = at


func select_center() -> void:
	if finished or selected_house < 0:
		return
	exploring_center = true
	_refresh_status()


## Shared by the real dashboard and the on-foot order display.
func guidance() -> Dictionary:
	if vehicle == null or finished:
		return {}
	var target: Vector2 = destinations[selected_house] if selected_house >= 0 else depot_frontage
	if exploring_center:
		target = center_frontage
	var start := Vector2(vehicle.global_position.x, vehicle.global_position.z)
	var route: Dictionary = NAVIGATION.route(
		town.get(&"plan"), start, target, PackedInt32Array(OPEN_DISTRICTS)
	)
	if route.is_empty():
		return {}
	var waypoint: Vector2 = target
	for point: Vector2 in route.points:
		if start.distance_to(point) > 8:
			waypoint = point
			break
	return {
		"distance": route.distance,
		"waypoint": Vector3(waypoint.x, .2, waypoint.y),
		"house": -1 if exploring_center else selected_house,
		"label":
		(
			tr("WORLD_TOWN_DISTRICT_CENTER")
			if exploring_center
			else (
				(tr("WORLD_GPS_HOUSE_CODE") % [selected_house + 1, String.chr(65 + selected_house)])
				if selected_house >= 0
				else tr("WORLD_TOWN_DEPOT")
			)
		)
	}


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(20, 18)
	_status.add_theme_font_size_override(&"font_size", 22)
	layer.add_child(_status)
	_prompt = Label.new()
	_prompt.position = Vector2(20, 148)
	_prompt.add_theme_font_size_override(&"font_size", 20)
	layer.add_child(_prompt)
	var reticle := Label.new()
	reticle.text = "·"
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	layer.add_child(reticle)


func _refresh_status() -> void:
	if _status == null:
		return
	var guide: Dictionary = guidance()
	var orders: PackedStringArray = []
	for index: int in range(houses.size()):
		orders.append("%d: %s" % [index + 1, _order_status(index)])
	_status.text = (
		(tr("HUD_TOWN_PLAY_SEED") + "\n%s\n%s\n%s")
		% [
			world_seed,
			"  |  ".join(orders),
			(
				tr("HUD_TOWN_COMPLETE")
				if finished
				else (
					tr("HUD_TOWN_DISTANCE")
					% [guide.get("label", ""), roundi(float(guide.get("distance", 0)))]
				)
			),
			tr("HUD_TOWN_CONTROLS")
		]
	)
	if gps != null:
		gps.call(&"refresh")


func _order_status(index: int) -> String:
	if not bool(houses[index].get(&"delivered")):
		return String.chr(65 + index)
	match StringName(houses[index].get(&"outcome")):
		&"delivered_ok":
			return "✓"
		&"delivered_at_risk", &"delivered_ruined":
			return tr("HUD_TOWN_DAMAGED")
	return tr("HUD_TOWN_MISSING")


func _process(delta: float) -> void:
	if not _owns_run:
		return
	if not finished and RunManager.is_running and selected_house < 0:
		var at := Vector2(vehicle.global_position.x, vehicle.global_position.z)
		if at.distance_to(depot_frontage) <= 9 and float(vehicle.get(&"speed_kmh")) < 1:
			finished = true
			RunManager.is_running = false
			vehicle.set(&"controls_enabled", false)
	_refresh -= delta
	if _refresh <= 0:
		_refresh = .2
		_refresh_status()
		var target: Node = local_player.call(&"_closest_interactable")
		_prompt.text = "[E] " + String(target.call(&"get_prompt")) if target != null else ""


func _unhandled_input(event: InputEvent) -> void:
	if not _owns_run or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode in [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6]:
		select_house(int(event.physical_keycode) - KEY_F1)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F7:
		select_center()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _owns_run:
		RunManager.reset_run()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

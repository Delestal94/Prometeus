extends Node3D
## Handcrafted first delivery: five short sections, one metre per world unit.

signal delivery_entered
signal delivery_exited
## Fires whenever any house resolves (delivered ok/ruined/missed) -- forwards
## DeliveryHouse.resolved so level_base.gd or the HUD can react without
## walking the house list themselves.
signal house_resolved(house_index: int, outcome: StringName)

@export var route_length: float = 220.0
## How many delivery houses this run has -- one per package, per package per
## player minus the driver (docs/tareas-nacho.md: house delivery system).
## Defaults to 3 (the "4 players, 1 drives" example) since nothing wires
## live roster size into this yet -- that's the coordination point noted in
## tareas-nacho.md, not guessed at here. Call configure_houses() before this
## node enters the tree to override.
@export var house_count: int = 3
var is_vehicle_in_delivery: bool = false
var houses: Array[DeliveryHouse] = []
const HOUSE_SPACING: float = 24.0
const HOUSES_START_Z: float = -196.0
const GOAL_CLEARANCE: float = 24.0
var _goal_z: float = 0.0

const ROAD := Color("394a50")
const SHOULDER := Color("63736f")
const MARKING := Color("d4d9c2")
const WARNING := Color("e7be51")
const TEAL := Color("65b5a1")
const CONCRETE := Color("8c9791")

var _materials: Dictionary = {}
var _delivery_vehicles: Array[Node3D] = []


## Overrides house_count before the node builds itself. Call before
## add_child()-ing this into the tree -- _ready() already builds geometry
## from house_count, same convention as any other @export here.
func configure_houses(count: int) -> void:
	house_count = maxi(count, 1)


func _ready() -> void:
	_goal_z = HOUSES_START_Z - float(house_count) * HOUSE_SPACING - GOAL_CLEARANCE
	route_length = -_goal_z
	_build_ground()
	_build_road()
	_build_training()
	_build_bumps()
	_build_chicane()
	_build_bridge()
	_build_houses()
	_build_goal()
	_build_landmarks()
	_build_forest()
	_build_ambience()


func get_progress(world_position: Vector3) -> float:
	return clampf(-to_local(world_position).z / route_length, 0.0, 1.0)


func get_section_name(world_position: Vector3) -> String:
	var distance: float = -to_local(world_position).z
	if distance < 40.0:
		return "01 · Salida y práctica"
	if distance < 90.0:
		return "02 · Badenes"
	if distance < 140.0:
		return "03 · Chicana"
	if distance < 185.0:
		return "04 · Puente angosto"
	var houses_start_distance: float = -HOUSES_START_Z
	if distance < houses_start_distance + float(house_count) * HOUSE_SPACING:
		var house_index: int = clampi(int((distance - houses_start_distance) / HOUSE_SPACING), 0, house_count - 1)
		return "05 · Entregas (casa %d/%d)" % [house_index + 1, house_count]
	return "06 · Meta"


func _build_ground() -> void:
	# Long enough to cover the houses stretch + goal, whatever house_count
	# makes that add up to -- fixed 340m only fit the old, always-3-houses
	# layout, so this now derives from the same route_length the road does.
	var ground_length: float = 170.0 + route_length
	var ground_center_z: float = 50.0 - ground_length * 0.5
	_box("Ground", Vector3(180.0, 1.0, ground_length), Vector3(0.0, -0.8, ground_center_z), SHOULDER, true)
	var shoulder_length: float = route_length + 20.0
	var shoulder_center_z: float = 8.0 - shoulder_length * 0.5
	# A shallow shoulder keeps an off-road mistake recoverable in the prototype.
	_box("LeftShoulder", Vector3(8.0, 0.2, shoulder_length), Vector3(-10.0, -0.2, shoulder_center_z), Color("879182"), true)
	_box("RightShoulder", Vector3(8.0, 0.2, shoulder_length), Vector3(10.0, -0.2, shoulder_center_z), Color("879182"), true)


func _build_road() -> void:
	_box("RoadFirstThreeSections", Vector3(12.0, 0.4, 152.0), Vector3(0.0, -0.2, -64.0), ROAD, true)
	_box("BridgeDeck", Vector3(6.0, 0.4, 45.0), Vector3(0.0, -0.2, -162.5), ROAD, true)
	# Covers the houses stretch and the goal, however long house_count makes
	# that -- replaces the old fixed-length DeliveryApproach + Warehouse.
	var houses_road_length: float = route_length - 185.0
	var houses_road_center_z: float = -185.0 - houses_road_length * 0.5
	_box("HousesRoad", Vector3(12.0, 0.4, houses_road_length), Vector3(0.0, -0.2, houses_road_center_z), ROAD, true)
	for z: int in range(8, int(_goal_z) - 4, -6):
		var half_width: float = 2.65 if z <= -140 and z >= -185 else 5.7
		for side: float in [-1.0, 1.0]:
			_box("EdgeMarking", Vector3(0.12, 0.015, 4.0), Vector3(side * half_width, 0.011, float(z)), MARKING)
		if z > -95 or (z < -185 and z > int(_goal_z) + 6):
			_box("CenterMarking", Vector3(0.12, 0.012, 2.0), Vector3(0.0, 0.009, float(z)), Color("8c9994"))
	# A broad stop wall beyond the goal prevents the route simply ending in a void.
	_box("EndBarrier", Vector3(15.0, 1.0, 0.6), Vector3(0.0, 0.5, _goal_z - 10.0), CONCRETE, true)


func _build_training() -> void:
	_box("StartLine", Vector3(11.4, 0.02, 0.35), Vector3(0.0, 0.015, -4.0), TEAL)
	_sign("Salida", "01 / SALIDA\n220 m · cuidá la carga", Vector3(-7.6, 0.0, -9.0), TEAL)
	_sign("BadenesAviso", "02 / BADENES\nDESPACIO", Vector3(7.7, 0.0, -37.0), WARNING)


func _build_bumps() -> void:
	for index: int in range(3):
		var z: float = -52.0 - float(index) * 12.0
		_build_bump("SpeedBump%d" % index, z, 0.17 + float(index) * 0.025)
		for stripe: int in range(7):
			_box("BumpApproachStripe", Vector3(0.7, 0.015, 0.3), Vector3(-4.5 + float(stripe) * 1.5, 0.012, z + 3.2), WARNING)


func _build_bump(node_name: String, z: float, height: float) -> void:
	# Bevelled trapezoid: 1.45 m ramps and a 0.7 m flat crown, no vertical lip.
	var points := PackedVector3Array([
		Vector3(-5.6, 0.005, 1.8), Vector3(5.6, 0.005, 1.8),
		Vector3(-5.6, height, 0.35), Vector3(5.6, height, 0.35),
		Vector3(-5.6, height, -0.35), Vector3(5.6, height, -0.35),
		Vector3(-5.6, 0.005, -1.8), Vector3(5.6, 0.005, -1.8),
	])
	var body := StaticBody3D.new()
	body.name = node_name
	body.position.z = z
	body.collision_layer = 1
	body.collision_mask = 6
	add_child(body)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles: Array[int] = [0, 2, 1, 1, 2, 3, 2, 4, 3, 3, 4, 5, 4, 6, 5, 5, 6, 7, 0, 6, 2, 2, 6, 4, 1, 3, 7, 3, 5, 7, 0, 1, 6, 1, 7, 6]
	for vertex: int in triangles:
		surface.add_vertex(points[vertex])
	surface.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = surface.commit()
	mesh_instance.material_override = _material(WARNING)
	body.add_child(mesh_instance)


func _build_chicane() -> void:
	_sign("ChicanaAviso", "03 / CHICANA\nGIRÁ SUAVE", Vector3(-7.7, 0.0, -89.0), WARNING)
	_box("ChicaneLeft", Vector3(4.4, 0.8, 1.0), Vector3(-3.8, 0.4, -106.0), CONCRETE, true)
	_box("ChicaneLeftWarning", Vector3(4.4, 0.24, 1.02), Vector3(-3.8, 0.61, -106.0), WARNING)
	_label("PasáDerecha", ">  >  >", Vector3(-3.6, 1.6, -105.8), 0.008, WARNING)
	_box("ChicaneRight", Vector3(4.4, 0.8, 1.0), Vector3(3.8, 0.4, -126.0), CONCRETE, true)
	_box("ChicaneRightWarning", Vector3(4.4, 0.24, 1.02), Vector3(3.8, 0.61, -126.0), WARNING)
	_label("PasáIzquierda", "<  <  <", Vector3(3.6, 1.6, -125.8), 0.008, WARNING)
	_sign("PuenteAviso", "04 / PUENTE\nCENTRATE", Vector3(-7.7, 0.0, -133.0), WARNING)


func _build_bridge() -> void:
	for side: float in [-1.0, 1.0]:
		_box("BridgeGuardRail", Vector3(0.25, 0.75, 45.0), Vector3(side * 3.05, 0.7, -162.5), CONCRETE, true)
		_box("BridgeRailTop", Vector3(0.29, 0.12, 45.0), Vector3(side * 3.05, 1.15, -162.5), WARNING)
		for z: int in range(-141, -186, -4):
			_box("BridgePost", Vector3(0.35, 1.2, 0.35), Vector3(side * 3.05, 0.6, float(z)), Color("5d6b6c"), true)
		# Visual taper leads the driver to the 5.8 m clear opening.
		for step: int in range(6):
			var x: float = side * lerpf(5.5, 3.35, float(step) / 5.0)
			_box("BridgeApproachMarker", Vector3(0.16, 0.6, 0.16), Vector3(x, 0.3, -134.0 - float(step)), WARNING, true)
	_box("WaterPlaceholder", Vector3(37.0, 0.025, 33.0), Vector3(0.0, -0.27, -162.5), Color("4d7d80"))


## One house per package (docs/tareas-nacho.md house delivery system):
## alternating sides of the road like a real street, each with its own
## doorbell. house_count is currently a fixed default (see the @export
## comment) -- wiring live "players minus the driver" is the coordination
## point noted there, not guessed at here.
func _build_houses() -> void:
	_sign("EntregaAviso", "05 / ENTREGAS\nBAJATE Y TOCÁ EL TIMBRE", Vector3(7.8, 0.0, HOUSES_START_Z + 8.0), TEAL)
	houses.clear()
	for index: int in range(house_count):
		var z: float = HOUSES_START_Z - float(index) * HOUSE_SPACING
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var house := DeliveryHouse.new()
		house.name = "House%d" % index
		house.visual_variant = index
		# The house model's entrance is on local -Z. Rotate that face toward the
		# asphalt rather than along the road, so stops address the route.
		house.position = Vector3(side * 10.5, 0.0, z)
		house.rotation.y = side * PI * 0.5
		add_child(house)
		houses.append(house)
		_build_house_path(index, side, z)
		var captured_index: int = index
		house.resolved.connect(func(outcome: StringName) -> void: house_resolved.emit(captured_index, outcome))
		_label("HouseNumber%d" % index, "CASA %d" % (index + 1), Vector3(side * 10.5, 4.0, z + 2.6), 0.01, TEAL)


## A narrow worn path makes each stop feel connected to the road. It stops
## at the shoulder rather than widening the driving lane or blocking traffic.
func _build_house_path(index: int, side: float, z: float) -> void:
	_box("HousePath%d" % index, Vector3(4.0, 0.025, 1.45), Vector3(side * 7.9, 0.025, z), Color("716b54"))


func _build_goal() -> void:
	_box("GoalArchLeft", Vector3(0.5, 4.0, 0.5), Vector3(-4.5, 2.0, _goal_z), CONCRETE, true)
	_box("GoalArchRight", Vector3(0.5, 4.0, 0.5), Vector3(4.5, 2.0, _goal_z), CONCRETE, true)
	_box("GoalArchTop", Vector3(9.6, 0.5, 0.5), Vector3(0.0, 4.0, _goal_z), TEAL, true)
	_label("GoalTitle", "META", Vector3(0.0, 4.9, _goal_z), 0.014, TEAL)
	var area := Area3D.new()
	area.name = "GoalArea"
	area.position = Vector3(0.0, 2.0, _goal_z + 3.0)
	area.collision_layer = 32
	area.collision_mask = 2
	area.monitorable = false
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(9.0, 4.0, 6.0)
	collider.shape = shape
	area.add_child(collider)
	add_child(area)
	area.body_entered.connect(_on_delivery_body_entered)
	area.body_exited.connect(_on_delivery_body_exited)


func _build_landmarks() -> void:
	# A few large gray volumes give speed and scale references without final art.
	for index: int in range(10):
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var height: float = 2.5 + float(index % 3)
		_box("LandscapeBlock", Vector3(6.0 + float(index % 3), height, 7.0), Vector3(side * (19.0 + float(index % 4) * 4.0), height * 0.5 - 0.3, -18.0 - float(index) * 23.0), Color("839184"))


## Deterministic forest dressing for the first map. The GLB models deliberately
## have no collision, preserving the established route physics and readability.
func _build_forest() -> void:
	var tree_paths: Array[String] = [
		"res://assets/models/environment/forest/sm_env_forest_oak.glb",
		"res://assets/models/environment/forest/sm_env_forest_birch.glb",
		"res://assets/models/environment/forest/sm_env_forest_pine_tall.glb",
		"res://assets/models/environment/forest/sm_env_forest_maple.glb",
		"res://assets/models/environment/forest/sm_env_forest_dead.glb",
		"res://assets/models/environment/forest/sm_env_forest_pine_sapling.glb",
	]
	var ground_paths: Array[String] = [
		"res://assets/models/environment/forest/sm_env_forest_bush_round.glb",
		"res://assets/models/environment/forest/sm_env_forest_fern.glb",
		"res://assets/models/environment/forest/sm_env_forest_grass_clump.glb",
		"res://assets/models/environment/forest/sm_env_forest_wildflower.glb",
		"res://assets/models/environment/forest/sm_env_forest_mushroom.glb",
		"res://assets/models/environment/forest/sm_env_forest_fallen_log.glb",
		"res://assets/models/environment/forest/sm_env_forest_rock.glb",
	]
	var forest := Node3D.new()
	forest.name = "ForestDressing"
	add_child(forest)
	# Four irregular layers per side form a tight tree corridor. The nearest
	# trunks sit inside the shoulder instead of beyond it: the asphalt remains
	# clear, but branches and undergrowth press into the driver's peripheral
	# vision like a real narrow forest road.
	for row: int in range(96):
		for side: float in [-1.0, 1.0]:
			for layer: int in range(4):
				var index: int = row * 8 + (0 if side < 0.0 else 4) + layer
				var tree := _instantiate_dressing(tree_paths[index % tree_paths.size()])
				if tree == null:
					continue
				var lateral: float = 8.0 + float(layer) * 5.1 + float((index * 7) % 5) * 0.45
				var depth: float = -4.0 - float(row) * 3.10 - float((index * 11) % 7) * 0.24
				tree.position = Vector3(side * lateral, 0.0, depth)
				tree.rotation.y = deg_to_rad(float((index * 37) % 360))
				# Uniform scale preserves each source model's silhouette. A 0.82–1.35
				# range still yields younger and tall mature trees without stretching
				# their trunks or turning their crowns into needles.
				var tree_scale: float = 0.82 + float((index * 17) % 54) / 100.0
				tree.scale = Vector3.ONE * tree_scale
				forest.add_child(tree)
	# Low vegetation fills the gaps at the road edge, hiding the flat ground
	# plane without blocking exits from the vehicle or the delivery houses.
	for index: int in range(520):
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var plant := _instantiate_dressing(ground_paths[index % ground_paths.size()])
		if plant == null:
			continue
		plant.position = Vector3(side * (6.7 + float((index * 11) % 25)), 0.0, -4.0 - float((index * 17) % int(route_length - 8.0)))
		plant.rotation.y = deg_to_rad(float((index * 53) % 360))
		var plant_scale: float = 0.65 + float((index * 19) % 55) / 100.0
		plant.scale = Vector3.ONE * plant_scale
		forest.add_child(plant)


func _instantiate_dressing(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


## World ambience (item #45): a quiet, looping wind bed. Non-positional
## (AudioStreamPlayer, not the 3D variant) -- it's meant to sit under
## everything else no matter where the camera is, not attenuate with
## distance from some single point in space. Splitting this by interior vs.
## exterior (item #46, buses) is a separate follow-up once those buses
## exist; for now it's just always-on world presence instead of dead
## silence outside the vehicle.
func _build_ambience() -> void:
	var player := AudioStreamPlayer.new()
	player.name = "AmbientWind"
	player.stream = SynthAudio.ambient_wind()
	player.volume_db = -26.0
	player.autoplay = true
	add_child(player)


func _on_delivery_body_entered(body: Node3D) -> void:
	if body not in _delivery_vehicles:
		_delivery_vehicles.append(body)
	if not is_vehicle_in_delivery:
		is_vehicle_in_delivery = true
		delivery_entered.emit()
		# Reaching the goal is the honest ending, even for a house nobody
		# rang -- "te olvidaste un paquete, bajate a dar explicaciones,"
		# forced automatically instead of just letting it go unresolved.
		for house: DeliveryHouse in houses:
			house.force_resolve_if_missed()


func _on_delivery_body_exited(body: Node3D) -> void:
	_delivery_vehicles.erase(body)
	if _delivery_vehicles.is_empty() and is_vehicle_in_delivery:
		is_vehicle_in_delivery = false
		delivery_exited.emit()


func _box(node_name: String, size: Vector3, location: Vector3, color: Color, solid: bool = false) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root.name = node_name
	root.position = location
	add_child(root)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _material(color)
	root.add_child(mesh)
	if solid:
		var body := root as StaticBody3D
		body.collision_layer = 1
		body.collision_mask = 6
		var collider := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		collider.shape = box_shape
		body.add_child(collider)
	return root


func _sign(node_name: String, caption: String, location: Vector3, accent: Color) -> void:
	_box(node_name + "Post", Vector3(0.16, 2.4, 0.16), location + Vector3(0.0, 1.2, 0.0), CONCRETE, true)
	_box(node_name + "Board", Vector3(4.6, 1.4, 0.12), location + Vector3(0.0, 2.65, 0.0), Color("263b3e"))
	_box(node_name + "Stripe", Vector3(4.6, 0.10, 0.13), location + Vector3(0.0, 3.3, 0.0), accent)
	_label(node_name + "Text", caption, location + Vector3(0.0, 2.65, 0.08), 0.0065, MARKING)


func _label(node_name: String, caption: String, location: Vector3, pixel_size: float, color: Color) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = caption
	label.position = location
	label.font_size = 48
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 4
	label.outline_modulate = Color("1e3035")
	add_child(label)


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[color] = material
	return _materials[color] as StandardMaterial3D

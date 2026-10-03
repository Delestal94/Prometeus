extends Node3D
## N-950: inspectable geometry prototype, not the campaign/reparto level yet.
## Run town_prototype.tscn with F6. A world seed plans all six districts;
## built_districts selects geometry without regenerating the town's layout.

const PLAN := preload("res://modules/town_gen/town_plan.gd")
const WALKWAYS := preload("res://modules/town_gen/town_walkways.gd")
const NAVIGATION := preload("res://modules/town_gen/town_navigation.gd")
const ART := preload("res://scripts/gameplay/town/town_art.gd")
const DISTRICT_NAMES: Array[String] = [
	"WORLD_TOWN_DISTRICT_DEPOT",
	"WORLD_TOWN_DISTRICT_CENTER",
	"WORLD_TOWN_DISTRICT_INDUSTRIAL",
	"WORLD_TOWN_DISTRICT_COUNTRY",
	"WORLD_TOWN_DISTRICT_PORT",
	"WORLD_TOWN_DISTRICT_HILLS",
]
const ASPHALT := Color("394a50")
const GRASS := Color("71885a")
const PAVING := Color("abb0a1")
const WOOD := Color("8b6650")

@export var world_seed: int = 0
@export var enable_camera: bool = true
@export var built_districts: PackedInt32Array = PackedInt32Array([0])

var plan: Dictionary = {}
var pedestrian_plan: Dictionary = {}
var tree_positions: PackedVector2Array = PackedVector2Array()
var _materials: Dictionary = {}
var _camera: Camera3D
var _pitch: float = -.65
var _yaw: float = 0.0
var _label: Label


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--town-seed=") and arg.get_slice("=", 1).is_valid_int():
			world_seed = int(arg.get_slice("=", 1))
	if world_seed == 0:
		var network: Node = get_node_or_null(^"/root/NetworkManager")
		world_seed = int(network.get(&"world_seed")) if network != null else 0
	if world_seed == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		world_seed = rng.randi_range(1, 2147483647)
	plan = PLAN.generate(world_seed)
	_build_ground()
	_build_roads()
	pedestrian_plan = WALKWAYS.generate(plan, built_districts)
	_build_walkways()
	for lot: Dictionary in plan.lots:
		if lot.district in built_districts:
			_build_lot(lot)
	for green: Dictionary in plan.green_areas:
		if green.district in built_districts:
			_build_green(green)
	_build_trees()
	_build_lighting()
	if enable_camera:
		_build_camera()


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = .92
		_materials[color] = material
	return _materials[color]


func _box(parent: Node3D, title: String, size: Vector3, at: Vector3,
		color: Color, solid: bool = false) -> Node3D:
	var part: Node3D = StaticBody3D.new() if solid else Node3D.new()
	part.name = title
	part.position = at
	parent.add_child(part)
	var mesh := BoxMesh.new()
	mesh.size = size
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = _material(color)
	part.add_child(view)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		part.add_child(collision)
	return part


func _disc(parent: Node3D, title: String, at: Vector2, radius: float,
		color: Color, surface: float = .08, solid: bool = false) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = .08
	mesh.radial_segments = 24
	var view := MeshInstance3D.new()
	view.name = title
	view.mesh = mesh
	view.material_override = _material(color)
	view.position = Vector3(at.x, surface - .04, at.y)
	if solid:
		var body := StaticBody3D.new()
		body.name = title
		body.set_meta(&"road_surface", title == "Junction")
		parent.add_child(body)
		body.add_child(view)
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = mesh.height
		collision.shape = shape
		collision.position = view.position
		body.add_child(collision)
	else:
		parent.add_child(view)


func _build_ground() -> void:
	var center: Vector2 = plan.districts[0].center
	_box(self, "Ground", Vector3(4000, 1, 4000),
		Vector3(center.x, -.5, center.y), GRASS, true)


func _build_roads() -> void:
	var roads := Node3D.new()
	roads.name = "Roads"
	add_child(roads)
	var junctions: Dictionary = {}
	for edge: Dictionary in NAVIGATION.accessible_edges(plan, built_districts):
		_road(roads, plan.nodes[edge.a], plan.nodes[edge.b], edge.width)
		junctions[edge.a] = true
		junctions[edge.b] = true
	for node_id: int in junctions:
		_disc(roads, "Junction", plan.nodes[node_id], PLAN.ROAD_WIDTH * .5, ASPHALT, .20, true)
	var exits := Node3D.new()
	exits.name = "ClosedExits"
	add_child(exits)
	for gate: Dictionary in plan.gates:
		var pair: Vector2i = gate.districts
		var first_open: bool = pair.x in built_districts
		var second_open: bool = pair.y in built_districts
		if first_open == second_open:
			continue
		var start: Vector2 = plan.nodes[gate.a if first_open else gate.b]
		var end: Vector2 = plan.nodes[gate.b if first_open else gate.a]
		var direction: Vector2 = (end - start).normalized()
		var stop: Vector2 = start + direction * minf(35.0, start.distance_to(end) * .5)
		_road(roads, start, stop, PLAN.ROAD_WIDTH)
		var barrier := Node3D.new()
		barrier.name = "Gate_%d" % (pair.y if first_open else pair.x)
		barrier.set_meta(&"district_pair", pair)
		barrier.position = Vector3(stop.x, 0, stop.y)
		barrier.rotation.y = -direction.angle()
		exits.add_child(barrier)
		_box(
			barrier,
			"Barrier",
			Vector3(.6, 1.3, PLAN.ROAD_WIDTH),
			Vector3(0, .65, 0),
			Color("e7be51"),
			true
		)
		_sign(barrier, tr(DISTRICT_NAMES[pair.y if first_open else pair.x]), Vector3(0, 3, 0))
	# Signs sit beside the open corridor, outside the driving lane.
	for gate: Dictionary in plan.gates:
		var pair: Vector2i = gate.districts
		if pair.x not in built_districts or pair.y not in built_districts:
			continue
		var direction: Vector2 = (plan.nodes[gate.b] - plan.nodes[gate.a]).normalized()
		for endpoint: Vector2i in [Vector2i(gate.a, pair.y), Vector2i(gate.b, pair.x)]:
			var at: Vector2 = (
				plan.nodes[endpoint.x] + direction.orthogonal() * (PLAN.ROAD_WIDTH * .5 + 3)
			)
			_sign(roads, tr(DISTRICT_NAMES[endpoint.y]), Vector3(at.x, 4, at.y))


func _road(parent: Node3D, a: Vector2, b: Vector2, width: float) -> void:
	var middle: Vector2 = (a + b) * .5
	var piece: Node3D = _box(parent, "Street", Vector3(a.distance_to(b), .04, width),
		Vector3(middle.x, .18, middle.y), ASPHALT, true)
	piece.set_meta(&"road_surface", true)
	piece.rotation.y = -(b - a).angle()


func _build_lot(lot: Dictionary) -> void:
	var parcel := Node3D.new()
	parcel.name = "%s_%d" % [lot.role, lot.address.y]
	if lot.district != 0:
		parcel.name = "District_%d_%s" % [lot.district, parcel.name]
	parcel.set_meta(&"lot", lot)
	parcel.position = Vector3(lot.position.x, 0, lot.position.y)
	parcel.rotation.y = -float(lot.angle)
	add_child(parcel)
	var size: Vector2 = lot.size
	var service: bool = lot.role in [&"depot", &"workshop"]
	_box(
		parcel,
		"Yard",
		Vector3(size.x, .08, size.y),
		Vector3(0, .04, 0),
		PAVING if service else GRASS.lightened(.12)
	)
	ART.build_lot(parcel, lot, world_seed)
	if service:
		var apron := _box(
			parcel, "ApronFloor", Vector3(size.x, .08, size.y), Vector3(0, .04, 0), PAVING, true
		)
		apron.set_meta(&"pedestrian_surface", true)
	if lot.role in [&"depot", &"house", &"workshop", &"shop"]:
		var titles: Dictionary = {
			&"depot": "TAKE MY PACKAGE",
			&"workshop": tr("WORLD_DEPOT_WORKSHOP"),
			&"shop": tr("WORLD_TOWN_SHOP")
		}
		var title: String = titles.get(lot.role, tr("WORLD_HOUSE_NUMBER") % lot.address.y)
		var sign_at := Vector3(0, 7.3 if service else 6.5, 0)
		if lot.role == &"shop":
			var front: Vector2 = (lot.frontage - lot.position).rotated(-float(lot.angle))
			# Place storefront signs in the front yard, clear of the upper floor.
			sign_at = Vector3(0, 2.8, signf(front.y) * size.y * .42)
		_sign(parcel, title, sign_at)


func _sign(parent: Node3D, text: String, at: Vector3) -> void:
	var sign_node := Label3D.new()
	sign_node.text = text
	sign_node.position = at
	sign_node.font_size = 48
	sign_node.pixel_size = .02
	sign_node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_node.modulate = Color("f1edd8")
	parent.add_child(sign_node)


func _build_green(green: Dictionary) -> void:
	var area := Node3D.new()
	area.name = "Green_%s" % green.kind
	if green.district != 0:
		area.name = "District_%d_%s" % [green.district, area.name]
	area.position = Vector3(green.position.x, 0, green.position.y)
	area.set_meta(&"green_area", green)
	add_child(area)
	_disc(area, "Lawn", Vector2.ZERO, green.radius, GRASS.darkened(.08))
	var plaza: bool = green.kind == &"plaza"
	_disc(area, "Walkway", Vector2.ZERO, 10 if plaza else 5, PAVING, .20)
	_green_floor(area, "LawnFloor", green.radius, .08)
	_green_floor(area, "WalkwayFloor", 10 if plaza else 5, .20)
	var entrance_angle: float = 0.0
	for path: Dictionary in pedestrian_plan.green_paths:
		if path.district == green.district and path.kind == green.kind and path.points.size() >= 2:
			entrance_angle = (path.points[-2] - green.position).angle()
			break
	if plaza:
		_box(area, "MonumentBase", Vector3(4, .7, 4), Vector3(0, .43, 0), PAVING, true)
		_box(area, "Monument", Vector3(1.2, 4.8, 1.2), Vector3(0, 3.1, 0), Color("9f9778"), true)
		_box(area, "PackageSculpture", Vector3(2.2, 1.8, 2.2), Vector3(0, 6.2, 0), WOOD, true)
		_sign(area, tr("WORLD_TOWN_PLAZA"), Vector3(0, 9, 0))
	for i: int in range(4):
		var angle: float = entrance_angle + PI * .25 + TAU * i / 4
		var at := Vector3(cos(angle) * 12, .08, sin(angle) * 12)
		ART.model(area, "Bench", ART.BENCH, at, -angle + PI * .5, true)
		ART.model(area, "Lamp", ART.LAMP, at + Vector3(2, 0, 0), -angle, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, &"town_trees", green.kind])
	if green.district != 0:
		rng.seed = hash([world_seed, &"town_trees", green.kind, green.district])
	for i: int in range(12):
		var at: Vector2 = (
			green.position
			+ (
				Vector2.from_angle(TAU * i / 12.0 + rng.randf_range(-.1, .1))
				* rng.randf_range(green.radius - 5, green.radius - 2)
			)
		)
		if PLAN.road_clearance(plan, at) > 3 and _path_clearance(at) > 4:
			tree_positions.append(at)


func _build_walkways() -> void:
	var surfaces: Array = pedestrian_plan.surfaces.duplicate()
	for green: Dictionary in plan.green_areas:
		if green.district not in built_districts:
			continue
		var radius: float = 10 if green.kind == &"plaza" else 5
		for i: int in range(24):
			var a: Vector2 = Vector2.from_angle(TAU * i / 24.0)
			var b: Vector2 = Vector2.from_angle(TAU * (i + 1) / 24.0)
			var at: Vector2 = green.position
			surfaces.append(
				PackedVector3Array(
					[
						Vector3(at.x + a.x * radius, .20, at.y + a.y * radius),
						Vector3(at.x + b.x * radius, .20, at.y + b.y * radius),
						Vector3(at.x + b.x * (radius + .8), .08, at.y + b.y * (radius + .8)),
						Vector3(at.x + a.x * (radius + .8), .08, at.y + a.y * (radius + .8))
					]
				)
			)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for points: PackedVector3Array in surfaces:
		var polygon := PackedVector2Array()
		for point: Vector3 in points:
			polygon.append(Vector2(point.x, point.z))
		var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
		for i: int in range(0, indices.size(), 3):
			var a: Vector3 = points[indices[i]]
			var b: Vector3 = points[indices[i + 1]]
			var c: Vector3 = points[indices[i + 2]]
			if (b - a).cross(c - a).y > 0:
				var swap: Vector3 = b
				b = c
				c = swap
			for point: Vector3 in [a, b, c]:
				builder.set_normal(Vector3.UP)
				builder.add_vertex(point)
	var mesh: ArrayMesh = builder.commit()
	if mesh.get_surface_count() == 0:
		return
	var body := StaticBody3D.new()
	body.name = "PedestrianSurfaces"
	body.set_meta(&"pedestrian_surface", true)
	add_child(body)
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = _material(PAVING)
	body.add_child(view)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)


func _green_floor(area: Node3D, title: String, radius: float, surface: float) -> void:
	var body := StaticBody3D.new()
	body.name = title
	body.set_meta(&"pedestrian_surface", true)
	area.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = .08
	collision.shape = shape
	collision.position.y = surface - .04
	body.add_child(collision)


func _path_clearance(at: Vector2) -> float:
	var distance: float = INF
	for path: Dictionary in pedestrian_plan.green_paths:
		for i: int in range(1, path.points.size()):
			distance = minf(
				distance,
				at.distance_to(
					Geometry2D.get_closest_point_to_segment(at, path.points[i - 1], path.points[i])
				)
			)
	return distance


func _build_trees() -> void:
	ART.build_trees(self, tree_positions, world_seed)


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("b5cad0")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("dae4dc")
	settings.ambient_light_energy = .65
	environment.environment = settings
	add_child(environment)


func _build_camera() -> void:
	_camera = Camera3D.new()
	var center: Vector2 = plan.districts[0].center
	_camera.position = Vector3(center.x, 160, center.y + 190)
	_camera.far = 1000
	_camera.near = 1
	_camera.current = true
	add_child(_camera)
	_camera.look_at(Vector3(center.x, 0, center.y))
	_pitch = _camera.rotation.x
	_yaw = _camera.rotation.y
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.text = (tr("HUD_TOWN_INSPECT_SEED") % world_seed
		+ "\n" + tr("HUD_TOWN_INSPECT_CONTROLS"))
	overlay.add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * .003
		_pitch = clampf(_pitch - event.relative.y * .003, -1.5, 1.5)
		_camera.rotation = Vector3(_pitch, _yaw, 0)


func _process(delta: float) -> void:
	if _camera == null:
		return
	var direction := Vector3(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var speed: float = 65 if Input.is_physical_key_pressed(KEY_SHIFT) else 25
	_camera.position += (_camera.basis * direction.normalized()) * speed * delta


func _exit_tree() -> void:
	if enable_camera and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

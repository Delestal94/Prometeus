extends Node3D
## N-950: inspectable geometry prototype, not the campaign/reparto level yet.
## Run town_prototype.tscn with F6. A world seed plans all six districts;
## only the starting district and its closed exits are built in this step.

const PLAN := preload("res://modules/town_gen/town_plan.gd")
const DISTRICT_NAMES: Array[String] = [
	"WORLD_TOWN_DISTRICT_DEPOT", "WORLD_TOWN_DISTRICT_CENTER", "WORLD_TOWN_DISTRICT_INDUSTRIAL",
	"WORLD_TOWN_DISTRICT_COUNTRY", "WORLD_TOWN_DISTRICT_PORT", "WORLD_TOWN_DISTRICT_HILLS",
]
const ASPHALT := Color("394a50")
const GRASS := Color("71885a")
const PAVING := Color("abb0a1")
const WOOD := Color("8b6650")
const LEAVES := Color("4f7953")

@export var world_seed: int = 0
@export var enable_camera: bool = true

var plan: Dictionary = {}
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
	for lot: Dictionary in plan.lots:
		if lot.district == 0:
			_build_lot(lot)
	for green: Dictionary in plan.green_areas:
		if green.district == 0:
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
	_box(self, "Ground", Vector3(2000, 1, 2000),
		Vector3(center.x, -.5, center.y), GRASS, true)


func _build_roads() -> void:
	var roads := Node3D.new()
	roads.name = "Roads"
	add_child(roads)
	for edge: Dictionary in plan.edges:
		if edge.district != 0:
			continue
		_road(roads, plan.nodes[edge.a], plan.nodes[edge.b], edge.width)
	for node_id: int in plan.districts[0].node_ids:
		_disc(roads, "Junction", plan.nodes[node_id], PLAN.ROAD_WIDTH * .5, ASPHALT, .20, true)
	var exits := Node3D.new()
	exits.name = "ClosedExits"
	add_child(exits)
	for gate: Dictionary in plan.gates:
		var pair: Vector2i = gate.districts
		if pair.x != 0 and pair.y != 0:
			continue
		var start: Vector2 = plan.nodes[gate.a if pair.x == 0 else gate.b]
		var end: Vector2 = plan.nodes[gate.b if pair.x == 0 else gate.a]
		var direction: Vector2 = (end - start).normalized()
		var stop: Vector2 = start + direction * minf(35.0, start.distance_to(end) * .5)
		_road(roads, start, stop, PLAN.ROAD_WIDTH)
		var barrier := Node3D.new()
		barrier.name = "Gate_%d" % (pair.y if pair.x == 0 else pair.x)
		barrier.position = Vector3(stop.x, 0, stop.y)
		barrier.rotation.y = -direction.angle()
		exits.add_child(barrier)
		_box(barrier, "Barrier", Vector3(.6, 1.3, PLAN.ROAD_WIDTH),
			Vector3(0, .65, 0), Color("e7be51"), true)
		_sign(barrier, tr(DISTRICT_NAMES[pair.y if pair.x == 0 else pair.x]), Vector3(0, 3, 0))


func _road(parent: Node3D, a: Vector2, b: Vector2, width: float) -> void:
	var middle: Vector2 = (a + b) * .5
	var piece: Node3D = _box(parent, "Street", Vector3(a.distance_to(b), .04, width),
		Vector3(middle.x, .18, middle.y), ASPHALT, true)
	piece.rotation.y = -(b - a).angle()


func _build_lot(lot: Dictionary) -> void:
	var parcel := Node3D.new()
	parcel.name = "%s_%d" % [lot.role, lot.address.y]
	parcel.set_meta(&"lot", lot)
	parcel.position = Vector3(lot.position.x, 0, lot.position.y)
	parcel.rotation.y = -float(lot.angle)
	add_child(parcel)
	var size: Vector2 = lot.size
	var front: Vector2 = (lot.frontage - lot.position).rotated(-float(lot.angle))
	var side: float = signf(front.y)
	var service: bool = lot.role in [&"depot", &"workshop"]
	_box(parcel, "Yard", Vector3(size.x, .08, size.y), Vector3(0, .04, 0),
		PAVING if service else GRASS.lightened(.12))
	var height: float = 5.5 if service else 4.0
	var building_size := Vector3(size.x * .65, height, size.y * .45)
	var color := Color("bfc4ab")
	if lot.role == &"depot":
		color = Color("367d83")
	elif lot.role == &"shop":
		color = Color("bf9b77")
	elif lot.role == &"workshop":
		color = Color("909b93")
	var z: float = -side * size.y * .19
	_box(parcel, "Building", building_size, Vector3(0, height * .5, z), color, true)
	_box(parcel, "Roof", Vector3(building_size.x + .8, .5, building_size.z + .8),
		Vector3(0, height + .25, z), Color("735747"))
	_box(parcel, "Door", Vector3(2.2 if service else 1.2, 2.4, .1),
		Vector3(0, 1.2, z + side * (building_size.z * .5 + .06)), WOOD)
	for x: float in [-building_size.x * .3, building_size.x * .3]:
		_box(parcel, "Window", Vector3(1.3, 1.2, .1),
			Vector3(x, 2.1, z + side * (building_size.z * .5 + .07)), Color("628d99"))
	var frontage: Vector2 = lot.frontage
	var driveway_start: Vector2 = lot.position + (frontage - lot.position).normalized() * size.y * .5
	_road(self, driveway_start, frontage, 5.0 if service else 2.0)
	if lot.role in [&"depot", &"house", &"workshop", &"shop"]:
		var titles: Dictionary = {&"depot": "TAKE MY PACKAGE",
			&"workshop": tr("WORLD_DEPOT_WORKSHOP"), &"shop": tr("WORLD_TOWN_SHOP")}
		var title: String = titles.get(lot.role, tr("WORLD_HOUSE_NUMBER") % lot.address.y)
		_sign(parcel, title, Vector3(0, height + 1.2, 0))


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
	area.position = Vector3(green.position.x, 0, green.position.y)
	area.set_meta(&"green_area", green)
	add_child(area)
	_disc(area, "Lawn", Vector2.ZERO, green.radius, GRASS.darkened(.08))
	var plaza: bool = green.kind == &"plaza"
	_disc(area, "Walkway", Vector2.ZERO, 10 if plaza else 5, PAVING, .22)
	if plaza:
		_box(area, "MonumentBase", Vector3(4, .7, 4), Vector3(0, .43, 0), PAVING, true)
		_box(area, "Monument", Vector3(1.2, 4.8, 1.2), Vector3(0, 3.1, 0), Color("9f9778"), true)
		_box(area, "PackageSculpture", Vector3(2.2, 1.8, 2.2), Vector3(0, 6.2, 0), WOOD, true)
		_sign(area, tr("WORLD_TOWN_PLAZA"), Vector3(0, 9, 0))
	for i: int in range(4):
		var angle: float = TAU * i / 4
		var at := Vector3(cos(angle) * 12, .55, sin(angle) * 12)
		var bench: Node3D = _box(area, "Bench", Vector3(2.4, .25, .7), at, WOOD, true)
		bench.rotation.y = -angle + PI * .5
		_box(bench, "Back", Vector3(2.4, .75, .12), Vector3(0, .5, .3), WOOD)
		for x: float in [-.85, .85]:
			_box(bench, "Support", Vector3(.16, .4, .55), Vector3(x, -.325, 0), ASPHALT)
		_box(area, "Lamp", Vector3(.12, 4.5, .12), at + Vector3(2, 1.7, 0), ASPHALT, true)
		_box(area, "Lantern", Vector3(.6, .5, .6), at + Vector3(2, 4.1, 0), Color("e7d6a0"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, &"town_trees", green.kind])
	for i: int in range(12):
		var at: Vector2 = green.position + Vector2.from_angle(TAU * i / 12.0
			+ rng.randf_range(-.1, .1)) * rng.randf_range(green.radius - 5, green.radius - 2)
		if PLAN.road_clearance(plan, at) > 3:
			tree_positions.append(at)


func _build_trees() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = .25
	trunk_mesh.bottom_radius = .35
	trunk_mesh.height = 3
	trunk_mesh.radial_segments = 6
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 2.5
	crown_mesh.height = 5
	crown_mesh.radial_segments = 8
	crown_mesh.rings = 4
	for crown: bool in [false, true]:
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = crown_mesh if crown else trunk_mesh
		batch.instance_count = tree_positions.size()
		for i: int in range(tree_positions.size()):
			var at: Vector2 = tree_positions[i]
			batch.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(at.x, 4.4 if crown else 1.5, at.y)))
		var view := MultiMeshInstance3D.new()
		view.name = "TreeCrowns" if crown else "TreeTrunks"
		view.multimesh = batch
		view.material_override = _material(LEAVES if crown else WOOD)
		add_child(view)


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

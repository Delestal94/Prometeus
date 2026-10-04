class_name CompanyRoot
extends Node3D
## Root scene of the "Modo Empresa" (expansion D-0214, docs/arquitectura.md section 10).
##
## The first thing you can walk around in: a bare shed in the industrial park
## and the nine zones of the continuous map drawn as flat slabs with their name,
## all from data (data/zones/*.tres), nothing placed by hand. It is a stand-in
## made of boxes until the shed (D-09xx) and the district scenes exist; what is
## final here is the entry: --mode=company or the menu opens this scene, the
## company is switched on (CompanyState) and the local player stands in the shed.
##
## No vehicle, no route and no run: Delivery and Endless ignore all of this
## (level_base.gd / level_endless.gd are untouched).

const ZONE_DIR: String = "res://data/zones/"
const PLAYER_SCENE: String = "res://scenes/gameplay/player/player.tscn"
## The shed, in meters: centered on the origin, inside the industrial park.
const SHED_SIZE: Vector2 = Vector2(48.0, 32.0)
const WALL_HEIGHT: float = 6.0
const WALL_THICKNESS: float = 0.5
## Where the player appears, inside the shed, by the door.
const SPAWN: Vector3 = Vector3(0.0, 1.0, 10.0)
const ZONE_COLORS: Dictionary = {
	&"parque_industrial": Color(0.55, 0.55, 0.58),
	&"centro": Color(0.62, 0.58, 0.50),
	&"suburbio": Color(0.50, 0.62, 0.50),
	&"campo": Color(0.45, 0.62, 0.35),
	&"puerto": Color(0.40, 0.55, 0.65),
	&"islas": Color(0.35, 0.65, 0.70),
	&"montana": Color(0.55, 0.50, 0.45),
	&"nieve": Color(0.85, 0.88, 0.92),
	&"volcan": Color(0.55, 0.25, 0.20),
}

var zones: Array[ZoneDefinition] = []
var player: Node3D

var _world: Node3D


func _ready() -> void:
	var state: Node = get_node_or_null(^"/root/CompanyState")
	if state != null and not state.call(&"is_active"):
		state.call(&"new_company")
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_add_environment()
	zones = load_zones()
	for zone: ZoneDefinition in zones:
		_add_zone_slab(zone)
	_add_shed()
	_spawn_player()


## Every zone in data/zones/, in a stable order. A new .tres joins without code.
static func load_zones() -> Array[ZoneDefinition]:
	var found: Array[ZoneDefinition] = []
	var files: PackedStringArray = DirAccess.get_files_at(ZONE_DIR)
	files.sort()
	for file: String in files:
		if file.ends_with(".tres"):
			var zone := load(ZONE_DIR + file) as ZoneDefinition
			if zone != null:
				found.append(zone)
	return found


func _add_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	add_child(sun)
	var sky_material := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)


## A flat slab over the zone's rectangle, a hair under the ground line so the
## shed floor, laid on top, hides the part they share.
func _add_zone_slab(zone: ZoneDefinition) -> void:
	var color: Color = ZONE_COLORS.get(zone.id, Color(0.5, 0.5, 0.5))
	var size := Vector3(zone.bounds.size.x, 0.2, zone.bounds.size.y)
	var center := Vector3(zone.bounds.get_center().x, -0.2, zone.bounds.get_center().y)
	var slab: StaticBody3D = _box("Zone_%s" % zone.id, size, center, color)
	_world.add_child(slab)
	var label := Label3D.new()
	label.name = "Name"
	label.text = String(zone.id).to_upper()
	label.font_size = 256
	label.pixel_size = 0.5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(center.x, 40.0, center.z)
	slab.add_child(label)


func _add_shed() -> void:
	var shed := Node3D.new()
	shed.name = "Shed"
	_world.add_child(shed)
	var floor_size := Vector3(SHED_SIZE.x, 0.2, SHED_SIZE.y)
	shed.add_child(_box("Floor", floor_size, Vector3(0.0, -0.1, 0.0), Color(0.42, 0.42, 0.44)))
	var half_x: float = SHED_SIZE.x * 0.5
	var half_z: float = SHED_SIZE.y * 0.5
	var wall_color := Color(0.72, 0.68, 0.60)
	var y: float = WALL_HEIGHT * 0.5
	var across := Vector3(SHED_SIZE.x, WALL_HEIGHT, WALL_THICKNESS)
	var along := Vector3(WALL_THICKNESS, WALL_HEIGHT, SHED_SIZE.y)
	# Back and sides; the front (+Z) is left open as the door.
	shed.add_child(_box("WallBack", across, Vector3(0.0, y, -half_z), wall_color))
	shed.add_child(_box("WallLeft", along, Vector3(-half_x, y, 0.0), wall_color))
	shed.add_child(_box("WallRight", along, Vector3(half_x, y, 0.0), wall_color))


func _box(box_name: String, size: Vector3, center: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = center
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	return body


func _spawn_player() -> void:
	var id: int = multiplayer.get_unique_id()
	player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Node3D
	player.name = "Player_%d" % id
	player.position = SPAWN
	player.set_multiplayer_authority(id)
	_world.add_child(player)

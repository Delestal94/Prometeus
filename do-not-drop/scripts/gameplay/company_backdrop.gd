class_name CompanyBackdrop
extends RefCounted
## What the company world stands on before any of the business (D-0214; out of company_root.gd in D-0254): the sun
## and the sky, children of the root ("Sun", "WorldEnvironment"), and the zones of the continuous map drawn as flat
## slabs with their name (World/Zone_<id>), all from data (data/zones/*.tres). A grey-box stand-in until the district
## scenes exist; CompanyGround's backup floor and the cells' streets lie over it.

## Zone names over the map: size of a pixel of their 256 px letters, and height over the ground.
const ZONE_LABEL_PIXEL_SIZE: float = 0.06
const ZONE_LABEL_HEIGHT: float = 30.0
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


## The sun and the sky under `root`, then a slab per zone of `zones` under `world`, in that order.
static func add_to(root: Node3D, world: Node3D, zones: Array[ZoneDefinition]) -> void:
	add_environment(root)
	for zone: ZoneDefinition in zones:
		add_zone_slab(world, zone)


static func add_environment(root: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	root.add_child(sun)
	var sky_material := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)


## A flat slab over the zone's rectangle, a hair under the ground line so the
## shed floor, laid on top, hides the part they share.
static func add_zone_slab(world: Node3D, zone: ZoneDefinition) -> void:
	var color: Color = ZONE_COLORS.get(zone.id, Color(0.5, 0.5, 0.5))
	var size := Vector3(zone.bounds.size.x, 0.2, zone.bounds.size.y)
	var center := Vector3(zone.bounds.get_center().x, -0.2, zone.bounds.get_center().y)
	var slab: StaticBody3D = CompanyShed.solid_box("Zone_%s" % zone.id, size, center, color)
	world.add_child(slab)
	var label := Label3D.new()
	label.name = "Name"
	label.text = String(zone.id).to_upper()
	# Letters about 15 m tall, 30 m up: a name to read from afar. At pixel_size 0.5 they were 128 m tall
	# and the industrial park's, right over the shed, filled the player's view with a blurred stripe.
	UiTheme.label_3d(label, 256)
	label.pixel_size = ZONE_LABEL_PIXEL_SIZE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(center.x, ZONE_LABEL_HEIGHT, center.z)
	slab.add_child(label)

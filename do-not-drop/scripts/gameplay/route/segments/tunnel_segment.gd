extends RouteSegment
class_name TunnelSegment
## A short tunnel (docs/tareas-nacho.md #58): walls, a roof under a grassy
## cover and stone portals (imported art since N-131, build_route_pieces.py),
## dim inside (the roof shades it from the sun) with a few warm lights along
## the ceiling. Solid walls, so a sloppy line scrapes the truck along them.

const HALF_WIDTH: float = 4.7
const HEIGHT: float = 4.8
const PORTAL := Color("7d8784")
## Sodium-warm glow for the lenses and the light they throw.
const LAMP_GLOW := Color("ff9326")
const LAMP_LIGHT := Color("ffc07a")
const MODELS: String = "res://assets/models/environment/route/"
const BORE_MODEL: String = MODELS + "sm_env_route_tunnel_module.glb"
const PORTAL_MODEL: String = MODELS + "sm_env_route_tunnel_portal.glb"
const LAMP_MODEL: String = MODELS + "sm_env_route_tunnel_lamp.glb"
const HILL_PROPS_MODEL: String = MODELS + "sm_env_route_tunnel_hill_props.glb"
## How long the hill's rocks and bushes are authored for.
const HILL_PROPS_LENGTH: float = 44.0
## How long one bore module is authored (assets/tools/build_route_pieces.py).
const MODULE_LENGTH: float = 4.0


func _init() -> void:
	length = 44.0


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)
	var middle: float = -length * 0.5
	# What you hit is the boxes this script always built (hidden); what you
	# see is the imported bore, portals and lamps (N-131).
	for side: float in [-1.0, 1.0]:
		_hide_box_visual(_box("TunnelWall", Vector3(0.6, HEIGHT, length), Vector3(side * (HALF_WIDTH + 0.3),
				HEIGHT * 0.5, middle), CONCRETE, true))
	_hide_box_visual(_box("TunnelRoof", Vector3(HALF_WIDTH * 2.0 + 1.2, 0.5, length), Vector3(0.0, HEIGHT + 0.25,
			middle), CONCRETE, true))
	for end_z: float in [0.0, -length]:
		_hide_box_visual(_box("TunnelPortal", Vector3(HALF_WIDTH * 2.0 + 3.0, 1.6, 0.8), Vector3(0.0, HEIGHT + 0.8,
				end_z), PORTAL, true))
		for side: float in [-1.0, 1.0]:
			_hide_box_visual(_box("TunnelPortalPier", Vector3(1.2, HEIGHT, 0.8), Vector3(side * (HALF_WIDTH + 0.9),
					HEIGHT * 0.5, end_z), PORTAL, true))
	# The bore in short modules (walls, vault, kerb, grass hump on top):
	# conform_geometry() bends each onto the terrain like the boxes it replaced.
	var modules: int = maxi(1, roundi(length / MODULE_LENGTH))
	var module_length: float = length / float(modules)
	for index: int in range(modules):
		var module: Node3D = _art("TunnelBore", BORE_MODEL, Vector3(0.0, 0.0, -module_length * (float(index) + 0.5)))
		if module != null:
			module.scale.z = module_length / MODULE_LENGTH
	var props: Node3D = _art("TunnelHillProps", HILL_PROPS_MODEL, Vector3(0.0, 0.0, middle))
	if props != null:
		props.scale.z = length / HILL_PROPS_LENGTH
	# Stone headwalls, facing out of each end; their wing walls step down the
	# hill to the ground either side, solid like the piers beside the road.
	_art("TunnelMouthEntry", PORTAL_MODEL, Vector3.ZERO)
	_art("TunnelMouthExit", PORTAL_MODEL, Vector3(0.0, 0.0, -length), PI)
	for end_z: float in [0.0, -length]:
		for side: float in [-1.0, 1.0]:
			_hide_box_visual(_box("TunnelWingWall", Vector3(2.2, 2.6, 0.8), Vector3(side * 7.3, 1.3, end_z), PORTAL,
					true))
			_hide_box_visual(_box("TunnelWingWall", Vector3(1.2, 1.0, 0.8), Vector3(side * 9.0, 0.5, end_z), PORTAL,
					true))
	# The echo inside (N-402): from portal to portal, floor to roof.
	var zone := AcousticZone.new()
	zone.name = "AcousticZone"
	zone.size = Vector3(HALF_WIDTH * 2.0, HEIGHT, length)
	zone.acoustic_space = &"tunnel"
	zone.position = Vector3(0.0, HEIGHT * 0.5, middle)
	add_child(zone)
	# Warm lamps along the ceiling: an amber lens each, and each a real light.
	# The merged tunnel is one mesh, lit by at most 8 lights per object in GL
	# Compatibility: these 4 plus the truck's 2 headlights stay under it.
	var lamp_material := _material(LAMP_GLOW).duplicate() as StandardMaterial3D
	lamp_material.emission_enabled = true
	lamp_material.emission = LAMP_GLOW
	lamp_material.emission_energy_multiplier = 1.3
	for index: int in range(4):
		var z: float = -6.0 - float(index) * ((length - 12.0) / 3.0)
		# The fitting hangs from the vault's crown; its lens is the glowing strip.
		var lamp: Node3D = _model("TunnelLamp", LAMP_MODEL, Vector3(0.0, HEIGHT - 0.02, z))
		var lens := lamp.find_child("Lens", true, false) as MeshInstance3D if lamp != null else null
		if lens != null:
			lens.material_override = lamp_material
		# Spot lights, not omni: the truck's headlights are spots, so their
		# shader variants are compiled from the first frame. The first omni
		# light the renderer met stalled a frame for ~0.1-0.6 s on entry.
		var light := SpotLight3D.new()
		light.name = "TunnelLight"
		light.light_color = LAMP_LIGHT
		light.light_energy = 3.4
		light.spot_range = 11.0
		light.spot_angle = 80.0
		light.spot_attenuation = 0.7
		light.shadow_enabled = false
		light.position = Vector3(0.0, HEIGHT - 0.3, z)
		light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		add_child(light)

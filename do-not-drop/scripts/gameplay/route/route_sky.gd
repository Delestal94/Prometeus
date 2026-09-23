extends Node3D
class_name RouteSky
## Far-away scenery for the route levels: a ring of low mountains that
## travels with the camera so the world never ends in a flat line
## (docs/especificaciones-visuales.md #59), and flat painted clouds in the sky
## itself (#58).
##
## The mountains sit well inside the camera's 600 m far plane but past most
## of the level's exponential fog -- at 0.008 density a 280 m silhouette would
## come out ~90% fog colour. So their materials skip fog and get the aerial
## tint baked in instead, from whatever fog colour the level uses.
##
## Clouds used to be 3D meshes; lit by the sun they got dark bellies and read
## as floating rocks. Now the level's ProceduralSkyMaterial is swapped for
## shaders/stylized_sky.gdshader with the same gradient colours plus flat,
## two-tone clouds that drift slowly -- cheaper, and they look drawn.
##
## Pure presentation. Nothing here collides or depends on the world seed, so
## every client can build its own and follow its own camera.

const HORIZON: PackedScene = preload("res://assets/models/environment/sky/sm_env_horizon_mountains.glb")
const SKY_SHADER: Shader = preload("res://shaders/stylized_sky.gdshader")
## The GLB ring is 450 m across the middle; 0.62 brings it to ~280 m.
const HORIZON_SCALE: float = 0.62
const HORIZON_DEPTH: float = -6.0  # sinks the bases behind the forest ridge
const HORIZON_HAZE: float = 0.5
const CLOUD_WHITE := Color(0.95, 0.96, 0.93)
const CLOUD_HAZE: float = 0.08
const FALLBACK_FOG := Color(0.43, 0.55, 0.49)

var horizon: Node3D
## The level's sky after conversion, or null when there's no WorldEnvironment
## (a route built on its own in a test).
var sky_material: ShaderMaterial
## This route's weather and time of day (world_mood.gd), same on every peer.
var mood: WorldMood
var _rain: GPUParticles3D
var _rain_sound: AudioStreamPlayer
const RAIN_INNER_RADIUS: float = 3.4
const RAIN_OUTER_RADIUS: float = 24.0
const RAIN_HEIGHT: float = 9.0


func _ready() -> void:
	mood = WorldMood.pick(_session_seed())
	var world_environment: WorldEnvironment = _world_environment()
	mood.apply(world_environment, _sun())
	var environment: Environment = world_environment.environment if world_environment != null else null
	var fog: Color = environment.fog_light_color if environment != null and environment.fog_enabled else FALLBACK_FOG
	horizon = HORIZON.instantiate()
	horizon.name = "HorizonMountains"
	horizon.scale = Vector3.ONE * HORIZON_SCALE
	horizon.position.y = HORIZON_DEPTH
	add_child(horizon)
	_tint(horizon, fog, mood.horizon_haze(HORIZON_HAZE), mood.horizon_light())
	_install_sky(environment, fog)
	mood.apply_sky(sky_material, fog)
	mood.apply_ground(get_parent())
	if mood.is_raining():
		_build_rain()


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		var at: Vector3 = camera.global_position
		global_position = Vector3(at.x, global_position.y, at.z)
		if _rain != null:
			_rain.global_position = at + Vector3.UP * RAIN_HEIGHT
			var inside: bool = _inside_vehicle(camera)
			var bus: StringName = &"Interior" if inside else &"Exterior"
			if AudioServer.get_bus_index(bus) >= 0 and _rain_sound.bus != bus:
				_rain_sound.bus = bus
			# Drumming on the roof is louder than rain on open ground.
			_rain_sound.volume_db = -11.0 if inside else -17.0


## Drops fall in a ring around the camera that never reaches its middle, and
## move with it: so no rain falls through the truck's roof onto the crew,
## while the windscreen and the road ahead still show it.
func _build_rain() -> void:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_axis = Vector3.UP
	material.emission_ring_radius = RAIN_OUTER_RADIUS
	material.emission_ring_inner_radius = RAIN_INNER_RADIUS
	material.emission_ring_height = 2.0
	material.direction = Vector3.DOWN
	material.spread = 3.0
	material.initial_velocity_min = 15.0
	material.initial_velocity_max = 19.0
	material.gravity = Vector3.ZERO
	var streak := BoxMesh.new()
	streak.size = Vector3(0.012, 0.42, 0.012)
	var look := StandardMaterial3D.new()
	look.albedo_color = Color(0.72, 0.8, 0.88, 0.45)
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = look
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.top_level = true
	_rain.local_coords = true
	_rain.amount = 1400
	_rain.lifetime = 0.75
	_rain.preprocess = 0.75
	_rain.process_material = material
	_rain.draw_pass_1 = streak
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rain.visibility_aabb = AABB(Vector3(-26.0, -16.0, -26.0), Vector3(52.0, 20.0, 52.0))
	add_child(_rain)
	_rain_sound = AudioStreamPlayer.new()
	_rain_sound.name = "RainSound"
	_rain_sound.stream = SynthAudio.rain_loop()
	_rain_sound.volume_db = -17.0
	_rain_sound.autoplay = true
	add_child(_rain_sound)


func _inside_vehicle(camera: Node) -> bool:
	var node: Node = camera.get_parent()
	while node != null:
		if node is VehicleBody3D:
			return true
		node = node.get_parent()
	return false


func _world_environment() -> WorldEnvironment:
	var found: Array[Node] = get_tree().root.find_children("*", "WorldEnvironment", true, false)
	return found[0] as WorldEnvironment if not found.is_empty() else null


func _sun() -> DirectionalLight3D:
	var found: Array[Node] = get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	return found[0] as DirectionalLight3D if not found.is_empty() else null


func _session_seed() -> int:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	return int(network.get(&"world_seed")) if network != null else 0


## Swaps the level's ProceduralSkyMaterial for the stylised sky, keeping its
## colours. Idempotent: the Environment is shared by every instance of the
## level scene, so a second route in the same run finds it already converted.
func _install_sky(environment: Environment, fog: Color) -> void:
	if environment == null or environment.sky == null:
		return
	var current: Material = environment.sky.sky_material
	if current is ShaderMaterial and (current as ShaderMaterial).shader == SKY_SHADER:
		sky_material = current
		return
	var material := ShaderMaterial.new()
	material.shader = SKY_SHADER
	var top := Color(0.23, 0.37, 0.47)
	if current is ProceduralSkyMaterial:
		var procedural := current as ProceduralSkyMaterial
		top = procedural.sky_top_color
		material.set_shader_parameter(&"sky_top_color", procedural.sky_top_color)
		material.set_shader_parameter(&"sky_horizon_color", procedural.sky_horizon_color)
		material.set_shader_parameter(&"ground_horizon_color", procedural.ground_horizon_color)
		material.set_shader_parameter(&"ground_bottom_color", procedural.ground_bottom_color)
		material.set_shader_parameter(&"sky_curve", procedural.sky_curve)
	var cloud: Color = CLOUD_WHITE.lerp(fog, CLOUD_HAZE)
	material.set_shader_parameter(&"cloud_color", cloud)
	material.set_shader_parameter(&"cloud_shade_color", cloud.lerp(top, 0.18))
	environment.sky.sky_material = material
	sky_material = material


func _environment() -> Environment:
	# The level's WorldEnvironment is a sibling branch, not an ancestor, so
	# look it up from the root rather than assuming a path.
	var found: Array[Node] = get_tree().root.find_children("*", "WorldEnvironment", true, false)
	return (found[0] as WorldEnvironment).environment if not found.is_empty() else null


## Replaces each imported material with a fog-free, unshaded copy pre-blended
## toward the fog colour: at this distance the sun's shading only adds noise
## to what should read as one flat silhouette.
func _tint(root: Node, fog: Color, haze: float, light: float = 1.0) -> void:
	for mesh_instance: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mesh_instance as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface: int in range(mesh.get_surface_count()):
			var source := mesh.surface_get_material(surface) as BaseMaterial3D
			var material := StandardMaterial3D.new()
			var base: Color = source.albedo_color if source != null else Color.WHITE
			# Unshaded, so the mood's light level is baked in: a night ridge is a
			# dark silhouette, not a sunlit one.
			var tinted: Color = base.lerp(fog, haze)
			material.albedo_color = Color(tinted.r * light, tinted.g * light, tinted.b * light, tinted.a)
			material.disable_fog = true
			material.roughness = 1.0
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			(mesh_instance as MeshInstance3D).set_surface_override_material(surface, material)
		(mesh_instance as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

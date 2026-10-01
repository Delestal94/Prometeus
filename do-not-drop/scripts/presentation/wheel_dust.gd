extends Node
## Dust thrown up behind the rear wheels (docs/tareas-nacho.md N-320, #49): a
## soft, pale cloud that tells the player what they are driving on. Pure
## presentation -- every client draws its own from the synced truck, the route's
## ground and the world's mood; nothing here is replicated.
##
## What it says:
##   - on gravel and dirt the trail is full; on the verge and the fields it is
##     thin (Route.ground_roughness(): 0 asphalt, 0.25 verge, 1 gravel); on the
##     asphalt there is none;
##   - rain (and, less, fog) damps it: wet ground does not raise dust;
##   - the more speed (or skid), the thicker it is.
## Without a route to ask (the depot, a test with only a truck) the ground counts
## as flat: no dust, the same fallback player_sprint.gd uses.
##
## The look (receta del humo de escape, vehicle_effects.gd, but with a soft quad):
## a camera-facing quad with a procedural radial gradient (no texture file) that
## grows 0.5 -> 2.5 and fades from alpha 0.8 to 0, unshaded, no shadow, in a
## pale desaturated tone of the terrain's gravel (route_terrain.gdshader). A
## sphere's low-poly silhouette showed as a hard octagon in the first attempt.
##
## Two emitters, one per rear wheel, hung on the vehicle body and not on the
## wheel: a wheel spins, and the emission direction would spin with it. They
## stay quiet while the viewer's camera is within CAMERA_CLEARANCE of them, so
## no puff is ever born in the face of a passenger on the rack.
## Created by VehiclePresentation, which owns the vehicle.

const SAMPLE_SECONDS: float = 0.2
## Lighter and less saturated than the gravel's (0.48, 0.415, 0.30): it has to
## stand out against that ground (the first, darker tone vanished into it) and
## still read as the same earth lifted into the air, not as orange smoke.
const DUST_COLOR := Color(0.88, 0.83, 0.72)
## Dust is unshaded, so it is dimmed with the light: DAY, DUSK, NIGHT
## (WorldMood.TimeOfDay), like WorldMood.horizon_light() for far scenery.
const LIGHT_BY_TIME: Array[float] = [1.0, 0.75, 0.35]
## And thinner in the dark, so at night it reads as a faint haze, not a brown stain.
const ALPHA_BY_TIME: Array[float] = [1.0, 0.9, 0.75]
const FOG_WETNESS: float = 0.35
## Share of the truck's own speed the puffs keep: the trail stays dense near the
## truck instead of being left one puff per metre.
const INHERIT_VELOCITY: float = 0.35
## Fewest puffs shown when the dust is on at all: a thin trail is still a trail.
const MIN_AMOUNT_RATIO: float = 0.6
## Roughness of the verge (0.25) lands at 0.4 of the full trail.
const ROUGHNESS_TO_DUST: float = 1.6
const CAMERA_CLEARANCE: float = 1.5
const PUFFS_PER_WHEEL: int = 32
const PUFF_LIFETIME: float = 1.2

@export var min_speed_kmh: float = 6.0

## One per rear wheel, left to right of the wheels' own order.
var emitters: Array[GPUParticles3D] = []
var vehicle: VehicleBody3D
var _wheels: Array[VehicleWheel3D] = []
var _ground: Array[float] = []
var _wetness: float = 0.0
var _sample_left: float = 0.0
var _material: ParticleProcessMaterial


func _ready() -> void:
	vehicle = get_parent().get(&"vehicle")
	for wheel: Node in vehicle.get_children():
		# The rear axle: the traction wheels that do not steer.
		if wheel is VehicleWheel3D and (wheel as VehicleWheel3D).use_as_traction \
				and not (wheel as VehicleWheel3D).use_as_steering:
			_wheels.append(wheel)
	_build()


func _process(delta: float) -> void:
	update(delta)


## How much of the full trail a ground of this roughness gets: 0 on asphalt.
static func ground_factor(roughness: float) -> float:
	return clampf(roughness * ROUGHNESS_TO_DUST, 0.0, 1.0)


## 0 dry, 1 rain, a little in fog: the same wetness world_mood.gd gives the
## terrain's shader, read from the mood so no per-frame lookup of the material.
static func wetness_now() -> float:
	if bool(WorldMood.active.get("rain", false)):
		return 1.0
	return FOG_WETNESS if int(WorldMood.active.get("weather", -1)) == WorldMood.Weather.FOG else 0.0


## The ground under each wheel is asked only every SAMPLE_SECONDS; the rest of
## the frames just use the last answer.
func update(delta: float) -> void:
	_sample_left -= delta
	if _sample_left <= 0.0:
		sample_now()
	var speed_factor: float = clampf((vehicle.speed_kmh - min_speed_kmh) / 20.0, 0.0, 1.0)
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	for index: int in range(emitters.size()):
		var wheel: VehicleWheel3D = _wheels[index]
		var particles: GPUParticles3D = emitters[index]
		if not particles.is_inside_tree():
			continue  # Hung on the vehicle a frame after it was built.
		var grounded: bool = wheel.is_in_contact()
		var skid: float = (1.0 - wheel.get_skidinfo()) if grounded else 0.0
		var intensity: float = 0.0
		if grounded:
			intensity = maxf(speed_factor, skid) * _ground[index] * (1.0 - _wetness)
		var near_camera: bool = camera != null \
				and camera.global_position.distance_to(particles.global_position) < CAMERA_CLEARANCE
		particles.emitting = intensity > 0.05 and not near_camera
		particles.amount_ratio = clampf(lerpf(MIN_AMOUNT_RATIO, 1.0, intensity), 0.1, 1.0)


## Asks the route about the ground under each rear wheel and reads the mood.
func sample_now() -> void:
	_sample_left = SAMPLE_SECONDS
	var route: Node = get_tree().get_first_node_in_group(&"route") if is_inside_tree() else null
	for index: int in range(_wheels.size()):
		var roughness: float = 0.0
		if route != null and route.has_method(&"ground_roughness"):
			roughness = float(route.call(&"ground_roughness", _wheels[index].global_position))
		_ground[index] = ground_factor(roughness)
	_wetness = wetness_now()
	var time_of_day: int = int(WorldMood.active.get("time", WorldMood.TimeOfDay.DAY))
	time_of_day = clampi(time_of_day, 0, LIGHT_BY_TIME.size() - 1)
	var light: float = LIGHT_BY_TIME[time_of_day]
	_material.color = Color(DUST_COLOR.r * light, DUST_COLOR.g * light, DUST_COLOR.b * light,
			ALPHA_BY_TIME[time_of_day])


func _build() -> void:
	_material = ParticleProcessMaterial.new()
	# Behind the truck (+Z is the rear; the emitter's axes are the body's) and a
	# little up, slow: the cloud is left behind in the world as the truck moves
	# on, and must not climb into the cargo box's view.
	_material.direction = Vector3(0.0, 0.5, 1.0)
	_material.spread = 40.0
	_material.initial_velocity_min = 0.5
	_material.initial_velocity_max = 1.4
	_material.inherit_velocity_ratio = INHERIT_VELOCITY
	_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_material.emission_box_extents = Vector3(0.5, 0.1, 0.25)
	_material.gravity = Vector3(0.0, 0.25, 0.0)
	_material.damping_min = 0.5
	_material.damping_max = 1.0
	_material.scale_min = 0.8
	_material.scale_max = 1.2
	_material.angle_min = -180.0
	_material.angle_max = 180.0
	_material.color = DUST_COLOR
	var grow := Curve.new()
	grow.max_value = 3.0  # A Curve clamps its points to 0..1 unless told otherwise.
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 2.5))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	_material.scale_curve = grow_texture
	# A little denser at birth, then gone quickly: never a solid ball.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)])
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	_material.color_ramp = fade_texture
	var puff := QuadMesh.new()
	puff.size = Vector2(1.3, 1.3)
	puff.material = _puff_material()
	for wheel: VehicleWheel3D in _wheels:
		var particles := GPUParticles3D.new()
		particles.name = "DustEmitter"
		particles.emitting = false
		particles.amount = PUFFS_PER_WHEEL
		particles.lifetime = PUFF_LIFETIME
		particles.process_material = _material
		particles.draw_pass_1 = puff
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Behind the tyre and 0.75 m above the ground it touches: lower, the quads are
		# cut by the terrain and the cloud looks sliced.
		particles.position = wheel.position \
				+ Vector3(0.0, 0.75 - wheel.wheel_radius, wheel.wheel_radius + 0.15)
		# The cloud stays where it was born: the truck leaves it up to ~25 m behind.
		particles.visibility_aabb = AABB(Vector3(-3.0, -1.0, -1.0), Vector3(6.0, 4.0, 28.0))
		vehicle.add_child.call_deferred(particles)
		emitters.append(particles)
		_ground.append(0.0)


## Unshaded and without shadows (a shaded puff showed a dark core), alpha-blended
## with a radial falloff so the quad has no visible edge.
func _puff_material() -> StandardMaterial3D:
	var falloff := Gradient.new()
	falloff.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	falloff.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)])
	var disc := GradientTexture2D.new()
	disc.gradient = falloff
	disc.fill = GradientTexture2D.FILL_RADIAL
	disc.fill_from = Vector2(0.5, 0.5)
	disc.fill_to = Vector2(1.0, 0.5)
	disc.width = 64
	disc.height = 64
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.vertex_color_use_as_albedo = true
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.albedo_texture = disc
	look.disable_receive_shadows = true
	return look

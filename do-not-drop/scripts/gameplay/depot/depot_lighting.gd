class_name DepotLighting
extends RefCounted
## How the depot is lit (N-319): a handful of real lights, each with a job,
## and the cheap fakes that make them read as many. The hall has its own light:
## its lamps are always on and the ambient under the roof hardly follows the
## weather (DepotAtmosphere); the sky only shows in the skylights, the strip
## windows and the door (their glass and the shafts of daylight below, here).
##
##   - Real lights: a spot over the truck, one over the shelves, one over the
##     packing area, a spot on the order board, a fill for the middle of the
##     hall, the workshop bench lamp. Few on purpose: the GL Compatibility
##     renderer caps the lights per mesh, and the depot's meshes are big
##     batches that every light overlaps. The three big spots are ranked for
##     shadows: WorldQuality keeps as many of them as the quality level
##     allows (none on Low). Each shadowed lamp re-draws the depot's batches,
##     so the floor and the lining never cast (DepotKit.shadowless).
##   - Fakes (one batch each, no light): a soft pool on the floor under every
##     lamp, and the shafts of daylight that fall through the skylights.
##
## Everything here is static once built: no per-frame work.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")

const WARM := Color("ffe6c8")
const WARM_DEEP := Color("ffe2b4")
const NEUTRAL := Color("f0f2f2")
## The lamps' floor pools.
const POOL_RADIUS: float = 2.7
const POOL_COLOUR := Color(1.0, 0.863, 0.69, 0.22)
## Skylights (centres, x by z) and the daylight that falls through them.
const SKYLIGHT_XS: Array[float] = [-7.5, 7.5]
const SKYLIGHT_ZS: Array[float] = [5.0, 16.0, 27.0]
const SKYLIGHT_SIZE := Vector2(1.6, 7.0)
## The sun's energy in level_base.tscn: the shafts fade as the sun dims.
const SUN_ENERGY_REFERENCE: float = 0.65
## How much of the sun's strength counts as daylight by WorldMood.TimeOfDay: day, dusk, night.
const TIME_DAYLIGHT: Array[float] = [1.0, 0.65, 0.12]
## A shaft's brightest alpha by WorldMood.Weather (clear, cloudy, rain, fog) and how
## much of it each WorldMood.TimeOfDay keeps (day, dusk, night: none, the moon is no daylight).
const SHAFT_PEAK: Array[float] = [0.25, 0.12, 0.06, 0.09]
## A shaft is four faces and you often see two of them one behind the other (additive): each
## face carries this share of the peak, so the shaft as a whole reads at the peak.
const SHAFT_FACE_SHARE: float = 0.5
## Daylight is the only cool light in the hall: the shafts and their patches on the floor.
const DAYLIGHT_TINT := Color("d6e6ef")
## Dust in the shafts: per shaft, size (m), colour and brightest alpha.
const DUST_PER_SHAFT: int = 10
const DUST_SIZE: float = 0.025
const DUST_COLOUR := Color("fff4e0")
const DUST_ALPHA: float = 0.35
const SHAFT_TIME: Array[float] = [1.0, 0.7, 0.0]
## A shaft is at its strongest this far down from the skylight (share of the drop) and
## fades to nothing from there to the floor; it is also faint where it leaves the roof.
const SHAFT_PEAK_AT: float = 0.4
const SHAFT_TOP_SHARE: float = 0.5
## The daylight patch a skylight leaves on the floor, at a shaft's peak alpha.
const PATCH_SHARE: float = 0.3
## Skylight and window glass: a greyish sky blue, how bright it is by weather (clear,
## cloudy, rain, fog) and by time (day, dusk, night), and its dusk and night tints.
const GLASS_COLOUR := Color("8fb0c2")
const GLASS_DUSK := Color("c79c86")
const GLASS_NIGHT := Color("243347")
const GLASS_WEATHER: Array[float] = [1.0, 0.78, 0.56, 0.85]
const GLASS_TIME: Array[float] = [1.0, 0.7, 0.3]
const GLASS_EMISSION: float = 0.35
const SHAFT_MAX_DROP: float = 7.0
## How far inside the walls' inner faces the daylight is cut (interior()).
const WALL_INSET: float = 0.05
## Where a lamp sits on the ceiling (x, z) -- build_lights() hangs a fixture from each.
const LAMP_XS: Array[float] = [-9.0, -3.0, 3.0, 9.0]
const LAMP_ZS: Array[float] = [5.2, 13.0, 20.8, 28.0]

## The real lights: name, kind, position, the point a spot looks at, colour,
## energy, range, cone angle (spots), and its shadow rank (-1 = never casts).
const LIGHTS: Array[Dictionary] = [
	{"name": "TruckLight", "spot": true, "at": Vector3(0.0, 5.6, 6.8), "aim": Vector3(0.0, 0.0, 7.4),
		"colour": WARM, "energy": 2.1, "range": 13.0, "angle": 48.0, "rank": 0},
	{"name": "ShelfLight", "spot": true, "at": Vector3(-8.5, 5.6, 19.5), "aim": Vector3(-8.5, 0.0, 19.5),
		"colour": WARM, "energy": 1.9, "range": 12.5, "angle": 54.0, "rank": 1},
	{"name": "PackingLight", "spot": true, "at": Vector3(-2.0, 5.6, 27.3), "aim": Vector3(-2.0, 0.0, 27.6),
		"colour": WARM, "energy": 1.7, "range": 11.5, "angle": 56.0, "rank": 2},
	{"name": "BoardLight", "spot": true, "at": Vector3(-3.7, 4.7, 14.6), "aim": Vector3(-5.6, 2.1, 10.9),
		"colour": WARM_DEEP, "energy": 2.4, "range": 9.0, "angle": 36.0, "rank": -1},
	{"name": "HallFill", "spot": false, "at": Vector3(4.0, 5.3, 19.5), "aim": Vector3.ZERO,
		"colour": NEUTRAL, "energy": 0.5, "range": 17.0, "angle": 0.0, "rank": -1},
]


## Hangs the real lights from `root` (depot space).
static func build_lights(root: Node3D) -> void:
	for spec: Dictionary in LIGHTS:
		var light: Light3D
		var at: Vector3 = spec.at
		if bool(spec.spot):
			var spot := SpotLight3D.new()
			spot.spot_range = float(spec.range)
			spot.spot_angle = float(spec.angle)
			spot.spot_angle_attenuation = 0.75
			var heading: Vector3 = (spec.aim as Vector3) - at
			var up: Vector3 = Vector3.FORWARD if absf(heading.normalized().y) > 0.98 else Vector3.UP
			spot.transform = Transform3D(Basis.looking_at(heading, up), at)
			light = spot
		else:
			var omni := OmniLight3D.new()
			omni.omni_range = float(spec.range)
			omni.omni_attenuation = 0.9
			omni.position = at
			light = omni
		light.name = String(spec.name)
		light.light_color = spec.colour
		light.light_energy = float(spec.energy)
		light.shadow_bias = 0.04
		light.shadow_normal_bias = 1.2
		light.shadow_opacity = 0.85
		var rank: int = int(spec.rank)
		if rank >= 0:
			light.set_meta(WorldQuality.SHADOW_RANK_META, rank)
		root.add_child(light)
		if rank >= 0:
			WorldQuality.apply_to(light)


## A pool of warm light on the floor under every hanging lamp, and the patches
## of daylight the skylights leave where their shafts land, batched into the
## kit: it is what makes the hall read as a place lit from above.
static func build_pools(kit: DepotKit, sun: DirectionalLight3D) -> void:
	var pool := DepotKit.light_pool(POOL_COLOUR)
	for x: float in LAMP_XS:
		for z: float in LAMP_ZS:
			if not Layout.MEZZANINE.grow(0.6).has_point(Vector2(x, z)):
				kit.floor_quad(Vector2.ONE * POOL_RADIUS * 2.0, Vector3(x, Layout.FLOOR_TOP + 0.02, z), pool)
	var daylight: Dictionary = sunlight(sun)
	var tint: Color = DAYLIGHT_TINT
	var patch := DepotKit.light_pool(Color(tint.r, tint.g, tint.b, shaft_peak() * PATCH_SHARE))
	var slant: Vector3 = daylight.slant
	var size: Vector2 = SKYLIGHT_SIZE + Vector2(1.6, 2.4)
	for x: float in SKYLIGHT_XS:
		for z: float in SKYLIGHT_ZS:
			# A low sun throws the patch toward a wall: what would land past it is cut off.
			var area := Rect2(Vector2(x + slant.x, z + slant.z) - size * 0.5, size).intersection(interior())
			if area.has_area():
				kit.floor_quad(area.size, Vector3(area.get_center().x, Layout.FLOOR_TOP + 0.024,
						area.get_center().y), patch)


## The floor inside the hall (x by z), from wall to wall a hair short of their
## inner faces: the shafts, their patches and their dust never leave it, so a
## low sun does not push daylight out through a wall.
static func interior() -> Rect2:
	return Rect2(-Layout.HALF_WIDTH + WALL_INSET, WALL_INSET, (Layout.HALF_WIDTH - WALL_INSET) * 2.0,
			Layout.DEPTH - WALL_INSET * 2.0)


## The daylight that comes in through the skylights: the sun's direction
## (`heading`), how strong it is next to a clear day (`strength`: the sun's
## energy, and most of it gone at night -- the moon is no daylight), its colour
## (`tint`) and how far along the floor a ray from the roof lands (`slant`).
## `sun` may be null (a depot built alone in a test): a clear afternoon.
static func sunlight(sun: DirectionalLight3D) -> Dictionary:
	var heading := Vector3(-0.35, -1.0, 0.45).normalized()
	var strength: float = 1.0
	var tint := Color(1.0, 0.96, 0.85)
	if sun != null:
		heading = (sun.global_basis * Vector3.FORWARD).normalized()
		strength = clampf(sun.light_energy / SUN_ENERGY_REFERENCE, 0.0, 1.2)
		tint = sun.light_color
		var time: int = int((WorldMood.active as Dictionary).get("time", WorldMood.TimeOfDay.DAY))
		strength *= TIME_DAYLIGHT[clampi(time, 0, TIME_DAYLIGHT.size() - 1)]
	var drop: float = Layout.CEILING - Layout.FLOOR_TOP
	var slant := Vector3.ZERO
	var sideways := Vector3(heading.x, 0.0, heading.z)
	if heading.y < -0.05 and sideways.length() > 0.001:
		# How far the light travels along the floor while it falls `drop`.
		slant = sideways.normalized() * minf(sideways.length() / -heading.y * drop, SHAFT_MAX_DROP)
	return {"heading": heading, "strength": strength, "tint": tint, "slant": slant}


## The brightest alpha a skylight's shaft reaches now: by the weather and the
## hour of WorldMood (a clear day when none has been picked, as in a test).
static func shaft_peak() -> float:
	var weather: int = int((WorldMood.active as Dictionary).get("weather", WorldMood.Weather.CLEAR))
	var time: int = int((WorldMood.active as Dictionary).get("time", WorldMood.TimeOfDay.DAY))
	return SHAFT_PEAK[clampi(weather, 0, SHAFT_PEAK.size() - 1)] * SHAFT_TIME[clampi(time, 0, SHAFT_TIME.size() - 1)]


## What the skylights' and the windows' glass shows of the sky: {"colour",
## "energy"}, for DepotKit.glow. Greyish blue by day, dimmer in cloud, rain and
## at dusk, and nearly dark at night.
static func glass_look() -> Dictionary:
	var weather: int = int((WorldMood.active as Dictionary).get("weather", WorldMood.Weather.CLEAR))
	var time: int = int((WorldMood.active as Dictionary).get("time", WorldMood.TimeOfDay.DAY))
	time = clampi(time, 0, GLASS_TIME.size() - 1)
	var base: Color = GLASS_COLOUR
	if time == WorldMood.TimeOfDay.DUSK:
		base = GLASS_COLOUR.lerp(GLASS_DUSK, 0.55)
	elif time == WorldMood.TimeOfDay.NIGHT:
		base = GLASS_NIGHT
	var brightness: float = GLASS_WEATHER[clampi(weather, 0, GLASS_WEATHER.size() - 1)] * GLASS_TIME[time]
	return {"colour": Color(base.r * brightness, base.g * brightness, base.b * brightness), "energy": GLASS_EMISSION}


## Daylight falling through the skylights: one additive mesh of slanted shafts.
## Each face fades to nothing at its two side edges (a texture across it), is
## faint where it leaves the roof, brightest SHAFT_PEAK_AT of the way down and
## gone at the floor (vertex alpha along it), so no hard edge shows; strength by
## weather and hour (shaft_peak), none at night. Cut at the walls (interior()).
static func build_shafts(root: Node3D, sun: DirectionalLight3D) -> MeshInstance3D:
	var daylight: Dictionary = sunlight(sun)
	var tint: Color = DAYLIGHT_TINT
	var slant: Vector3 = daylight.slant
	var peak: float = shaft_peak()
	var bounds: Rect2 = interior()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top_colour := Color(tint.r, tint.g, tint.b, peak * SHAFT_FACE_SHARE * SHAFT_TOP_SHARE)
	var mid_colour := Color(tint.r, tint.g, tint.b, peak * SHAFT_FACE_SHARE)
	var foot_colour := Color(tint.r, tint.g, tint.b, 0.0)
	for x: float in SKYLIGHT_XS:
		for z: float in SKYLIGHT_ZS:
			var half := SKYLIGHT_SIZE * 0.5
			var top_y: float = Layout.CEILING - 0.05
			var corners_top: Array[Vector3] = []
			var corners_mid: Array[Vector3] = []
			var corners_foot: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var at := Vector3(x + corner.x * half.x, top_y, z + corner.y * half.y)
				corners_top.append(at)
				# The shaft widens a little as it falls.
				var foot := Vector3(at.x + corner.x * 0.5, Layout.FLOOR_TOP + 0.03, at.z + corner.y * 0.9) + slant
				corners_foot.append(foot)
				corners_mid.append(at.lerp(foot, SHAFT_PEAK_AT))
			for side: int in range(4):
				var next: int = (side + 1) % 4
				_face(tool, [corners_top[side], corners_top[next], corners_mid[next], corners_mid[side]],
						top_colour, mid_colour, bounds)
				_face(tool, [corners_mid[side], corners_mid[next], corners_foot[next], corners_foot[side]],
						mid_colour, foot_colour, bounds)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _across_texture()
	material.texture_repeat = false
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true
	var shafts := MeshInstance3D.new()
	shafts.name = "SkylightShafts"
	shafts.mesh = tool.commit()
	shafts.material_override = material
	shafts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shafts)
	return shafts


## A quad of a shaft's side (corners top-left, top-right, bottom-right, bottom-left
## as seen from outside) with `upper` colour on the first two and `lower` on the rest;
## u runs across the face for the side-edge fade. What lies outside `bounds` (x by z)
## is cut away, colour and uv carried to the cut.
static func _face(tool: SurfaceTool, corners: Array[Vector3], upper: Color, lower: Color, bounds: Rect2) -> void:
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var colours: Array[Color] = [upper, upper, lower, lower]
	var polygon: Array[Dictionary] = []
	for index: int in range(4):
		polygon.append({"at": corners[index], "colour": colours[index], "uv": uvs[index]})
	# Each wall as (normal x, normal z, offset): inside where normal . (x, z) >= offset.
	for wall: Vector3 in [Vector3(1.0, 0.0, bounds.position.x), Vector3(-1.0, 0.0, -bounds.end.x),
			Vector3(0.0, 1.0, bounds.position.y), Vector3(0.0, -1.0, -bounds.end.y)]:
		polygon = _cut(polygon, wall)
	for index: int in range(1, polygon.size() - 1):
		for vertex: Dictionary in [polygon[0], polygon[index], polygon[index + 1]]:
			tool.set_color(vertex.colour)
			tool.set_uv(vertex.uv)
			tool.add_vertex(vertex.at)


## The part of a convex `polygon` on the inner side of `wall` (see _face).
static func _cut(polygon: Array[Dictionary], wall: Vector3) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for index: int in range(polygon.size()):
		var a: Dictionary = polygon[index]
		var b: Dictionary = polygon[(index + 1) % polygon.size()]
		var depth_a: float = wall.x * (a.at as Vector3).x + wall.y * (a.at as Vector3).z - wall.z
		var depth_b: float = wall.x * (b.at as Vector3).x + wall.y * (b.at as Vector3).z - wall.z
		if depth_a >= 0.0:
			kept.append(a)
		if (depth_a >= 0.0) != (depth_b >= 0.0):
			var t: float = depth_a / (depth_a - depth_b)
			kept.append({"at": (a.at as Vector3).lerp(b.at, t), "colour": (a.colour as Color).lerp(b.colour, t),
					"uv": (a.uv as Vector2).lerp(b.uv, t)})
	return kept


## Alpha across a face: 0 at both side edges, full in the middle (smooth, no ring).
static func _across_texture() -> ImageTexture:
	var width: int = 32
	var image := Image.create(width, 2, false, Image.FORMAT_RGBA8)
	for x: int in range(width):
		var across: float = (x + 0.5) / width
		var alpha: float = pow(sin(PI * across), 1.3)
		for y: int in range(2):
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


## Motes of dust drifting inside each skylight's shaft (and nowhere else): ten per shaft, a couple
## of centimetres across, slow, additive; their brightness follows the shaft's (shaft_peak: none at
## night, so none are built then) and the Low quality level has none. Static: no per-frame script.
static func build_dust(root: Node3D, sun: DirectionalLight3D) -> void:
	var peak: float = shaft_peak()
	if peak <= 0.0 or WorldQuality.level == WorldQuality.Level.LOW:
		return
	var slant: Vector3 = sunlight(sun).slant
	var mote := QuadMesh.new()
	mote.size = Vector2(DUST_SIZE, DUST_SIZE)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.disable_fog = true
	material.albedo_color = Color(DUST_COLOUR, DUST_ALPHA * clampf(peak / SHAFT_PEAK[0], 0.2, 1.0))
	mote.material = material
	var half := SKYLIGHT_SIZE * 0.5
	var bounds: Rect2 = interior()
	var index: int = 0
	for x: float in SKYLIGHT_XS:
		for z: float in SKYLIGHT_ZS:
			var dust := CPUParticles3D.new()
			dust.name = "ShaftDust%d" % index
			index += 1
			dust.amount = DUST_PER_SHAFT
			dust.lifetime = 8.0
			dust.preprocess = 8.0
			dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			var extents := Vector3(half.x + 0.2, 1.6, half.y)
			dust.emission_box_extents = extents
			# Mid-height of the fall, carried along the slant to where the shaft is at that height,
			# and kept off the walls (the shaft is cut there).
			var centre: Vector3 = Vector3(x, 4.3, z) + slant * 0.45
			dust.position = Vector3(clampf(centre.x, bounds.position.x + extents.x, bounds.end.x - extents.x), centre.y,
					clampf(centre.z, bounds.position.y + extents.z, bounds.end.y - extents.z))
			dust.direction = Vector3.UP
			dust.spread = 180.0
			dust.gravity = Vector3.ZERO
			dust.initial_velocity_min = 0.03
			dust.initial_velocity_max = 0.08
			dust.mesh = mote
			dust.local_coords = true
			root.add_child(dust)

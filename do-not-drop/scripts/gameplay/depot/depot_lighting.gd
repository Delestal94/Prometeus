class_name DepotLighting
extends RefCounted
## How the depot is lit (N-319): a handful of real lights, each with a job,
## and the cheap fakes that make them read as many.
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

const WARM := Color("fff4e4")
const WARM_DEEP := Color("ffe2b4")
const NEUTRAL := Color("f0f2f2")
## The lamps' floor pools.
const POOL_RADIUS: float = 2.7
const POOL_COLOUR := Color(1.0, 0.9, 0.72, 0.11)
## Skylights (centres, x by z) and the daylight that falls through them.
const SKYLIGHT_XS: Array[float] = [-7.5, 7.5]
const SKYLIGHT_ZS: Array[float] = [5.0, 16.0, 27.0]
const SKYLIGHT_SIZE := Vector2(1.6, 7.0)
## The sun's energy in level_base.tscn: the shafts fade as the sun dims.
const SUN_ENERGY_REFERENCE: float = 0.65
const SHAFT_ALPHA: float = 0.15
## How much of the sun's strength counts as daylight by WorldMood.TimeOfDay: day, dusk, night.
const TIME_DAYLIGHT: Array[float] = [1.0, 0.65, 0.12]
## The daylight patch a skylight leaves on the floor.
const PATCH_ALPHA: float = 0.16
const SHAFT_MAX_DROP: float = 7.0
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
	var tint: Color = daylight.tint
	var patch := DepotKit.light_pool(Color(tint.r, tint.g, tint.b, PATCH_ALPHA * float(daylight.strength)))
	var slant: Vector3 = daylight.slant
	for x: float in SKYLIGHT_XS:
		for z: float in SKYLIGHT_ZS:
			kit.floor_quad(SKYLIGHT_SIZE + Vector2(1.6, 2.4), Vector3(x + slant.x, Layout.FLOOR_TOP + 0.024,
					z + slant.z), patch)


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


## Daylight falling through the skylights: one additive mesh of slanted shafts,
## fainter as the sun dims (a clouded sky, dusk, rain).
static func build_shafts(root: Node3D, sun: DirectionalLight3D) -> MeshInstance3D:
	var daylight: Dictionary = sunlight(sun)
	var tint: Color = daylight.tint
	var slant: Vector3 = daylight.slant
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top_colour := Color(tint.r, tint.g, tint.b, SHAFT_ALPHA * float(daylight.strength))
	var foot_colour := Color(tint.r, tint.g, tint.b, 0.0)
	for x: float in SKYLIGHT_XS:
		for z: float in SKYLIGHT_ZS:
			var half := SKYLIGHT_SIZE * 0.5
			var top_y: float = Layout.CEILING - 0.05
			var corners_top: Array[Vector3] = []
			var corners_foot: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var at := Vector3(x + corner.x * half.x, top_y, z + corner.y * half.y)
				corners_top.append(at)
				# The shaft widens a little as it falls.
				corners_foot.append(Vector3(at.x + corner.x * 0.5, Layout.FLOOR_TOP + 0.03,
						at.z + corner.y * 0.9) + slant)
			for side: int in range(4):
				var next: int = (side + 1) % 4
				_vertex(tool, corners_top[side], top_colour)
				_vertex(tool, corners_top[next], top_colour)
				_vertex(tool, corners_foot[next], foot_colour)
				_vertex(tool, corners_top[side], top_colour)
				_vertex(tool, corners_foot[next], foot_colour)
				_vertex(tool, corners_foot[side], foot_colour)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true
	var shafts := MeshInstance3D.new()
	shafts.name = "SkylightShafts"
	shafts.mesh = tool.commit()
	shafts.material_override = material
	shafts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shafts)
	return shafts


static func _vertex(tool: SurfaceTool, at: Vector3, colour: Color) -> void:
	tool.set_color(colour)
	tool.add_vertex(at)

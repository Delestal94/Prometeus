extends RefCounted
## The waterfalls at both ends of a narrow bridge's river (route_terrain.gd).
## On its own the water ended against the grass like an isolated pool
## (playtest 2026-09-28): now, wherever the channel runs out, the stream
## pours into it off a rocky outcrop -- a falling sheet (river_fall.gdshader),
## foam where it lands, stacked forest boulders forming the cliff it falls
## from and hiding its source, and rocks along the shore near it.
##
## Polish pass (2026-09-29, "más profesional"): the sheet bulges out and
## curls in at its sides instead of being a flat ribbon, and is drawn twice --
## a deep body and a faster veil of white threads in front of it -- the foam
## churns away downstream instead of sitting in a star round the impact,
## spray drifts up where the water lands (_add_mist()), and rocks settle into
## the slope under them (_at()).
##
## Built once with the terrain, never per frame. Placed purely from the
## river's fixed shape and the terrain's heights -- no RNG -- so every peer
## (and a rebuilt terrain) builds the same falls. Rocks are decoration only:
## no collision, like the forest's own rocks (route_dresser.gd).

const ROCK_PATH: String = "res://assets/models/environment/forest/sm_env_forest_rock.glb"
const MOSSY_PATH: String = "res://assets/models/environment/forest/sm_env_forest_mossy_rock_cluster.glb"
const FALL_SHADER: Shader = preload("res://shaders/river_fall.gdshader")
## sm_env_forest_rock.glb at scale 1 (its origin is at its base): used to
## scale a rock to a given height and footprint.
const ROCK_HEIGHT: float = 0.85
const ROCK_RADIUS: float = 0.75
## A boulder is never taller than this times its radius, nor flatter than
## ROCK_MIN_RATIO: a cliff is a stack of them (_add_column()), not one rock
## stretched up, and a low one is a smaller rock, not a pancake.
const ROCK_MAX_RATIO: float = 1.3
const ROCK_MIN_RATIO: float = 0.7
## Metres per step following the channel out from the road to its end.
const MARCH_STEP: float = 1.0
## How far below the water the ground has to be to count as "in the water".
const WET_DEPTH: float = 0.05
## A side of the river shorter than this (from the road) gets no fall.
const MIN_REACH: float = 10.0
## How far the stream drops into the river (metres above the water), and how
## far above the ground at the lip it always stands on its rocks.
const MIN_DROP: float = 2.6
const MAX_DROP: float = 5.0
const LIP_OVER_GROUND: float = 1.6
## How far into the water the sheet lands.
const LANDING: float = 1.2
const FALL_SEGMENTS: int = 10
## Strips across the sheet: enough for it to bulge and curl at its sides.
const SHEET_COLUMNS: int = 6
## How far the sheet bows out at its middle, and the veil stands off it.
const SHEET_BULGE: float = 0.16
const VEIL_OFFSET: float = 0.1
## The stream running over the lip before it falls.
const FEED_LENGTH: float = 2.0
const MIN_FALL_WIDTH: float = 2.4
const MAX_FALL_WIDTH: float = 4.5


static func build(terrain: Node3D, river: Dictionary, reach: float) -> void:
	var root := Node3D.new()
	root.name = "RiverFalls"
	var falls: int = 0
	for side: float in [-1.0, 1.0]:
		var end: Dictionary = find_end(terrain, river, side, reach)
		if end.is_empty():
			continue
		_build_fall(root, terrain, river, end, int(side + 1.0))
		falls += 1
	if falls == 0:
		root.free()
		return
	terrain.add_child(root)


## Where the water runs out on one `side` (-1/+1) of the road: follows the
## channel's centreline (terrain.river_centre()) out from the bridge until it
## has been dry for a few metres. {"pos": Vector2 last wet point, "out":
## Vector2 the channel's direction there, "reach": metres from the road}, or
## {} when that side's water is too short to bother.
static func find_end(terrain: Node3D, river: Dictionary, side: float, reach: float) -> Dictionary:
	var last_wet: float = -1.0
	var s: float = 0.0
	while s <= reach and s - last_wet <= 3.0 * MARCH_STEP:
		if _is_wet(terrain, river, _centre_point(terrain, river, side * s)):
			last_wet = s
		s += MARCH_STEP
	if last_wet < MIN_REACH:
		return {}
	var pos: Vector2 = _centre_point(terrain, river, side * last_wet)
	var behind: Vector2 = _centre_point(terrain, river, side * (last_wet - 2.0))
	return {"pos": pos, "out": (pos - behind).normalized(), "reach": last_wet}


static func _centre_point(terrain: Node3D, river: Dictionary, v: float) -> Vector2:
	var a: Vector2 = river.a
	var edge: Vector2 = river.b - a
	var length: float = maxf(edge.length(), 0.001)
	var dir: Vector2 = edge / length
	return a + dir * (length * 0.5 + terrain.river_centre(river, v)) + Vector2(-dir.y, dir.x) * v


static func _is_wet(terrain: Node3D, river: Dictionary, p: Vector2) -> bool:
	return terrain.river_water_height(river, p) - terrain.height_at(Vector3(p.x, 0.0, p.y)) > WET_DEPTH


## Metres from `p` across the channel (along `across`, both ways) to dry ground.
static func _shore_distance(terrain: Node3D, river: Dictionary, p: Vector2, across: Vector2) -> float:
	var d: float = 0.0
	while d < 12.0 and _is_wet(terrain, river, p + across * (d + 0.5)):
		d += 0.5
	return d


static func _build_fall(root: Node3D, terrain: Node3D, river: Dictionary, end: Dictionary, index: int) -> void:
	var out: Vector2 = end.out
	var across := Vector2(-out.y, out.x)
	var salt: float = fmod(river.a.x * 0.37 + river.a.y * 0.61, 97.0) + float(index) * 13.0
	# How wide the water is just short of its end: the sheet matches it.
	var near: Vector2 = end.pos - out * 2.0
	var width: float = clampf((_shore_distance(terrain, river, near, across)
		+ _shore_distance(terrain, river, near, -across)) * 0.9, MIN_FALL_WIDTH, MAX_FALL_WIDTH)
	var landing: Vector2 = end.pos - out * LANDING
	var water_y: float = terrain.river_water_height(river, landing)
	# A short, steep fall off the front of the outcrop: the lip stands on its
	# rocks well above the ground there, whatever the slope behind does.
	var guess_run: float = 0.6 + 0.3 * MIN_DROP
	var lip_ground: float = _ground(terrain, landing + out * guess_run)
	var drop: float = clampf(lip_ground + LIP_OVER_GROUND - water_y, MIN_DROP, MAX_DROP)
	var fall_run: float = 0.6 + 0.3 * drop
	var lip: Vector2 = landing + out * fall_run
	var top_y: float = water_y + drop
	_add_sheet(root, lip, out, across, top_y, drop, fall_run, width, false)
	_add_sheet(root, lip, out, across, top_y, drop, fall_run, width, true)
	_add_pool(root, landing, out, across, water_y, width)
	_add_mist(root, landing, out, water_y, width)
	# The cliff face right behind the sheet, its top just under the lip.
	var face: float = clampf(width * 0.45, 1.2, 2.0)
	_add_column(root, terrain, ROCK_PATH, lip + out * face * 0.95, top_y - 0.08, face, salt)
	# Framing both sides of the fall, and a lower step on each side of its foot.
	for flank_side: float in [-1.0, 1.0]:
		var flank: Vector2 = across * flank_side
		_add_column(root, terrain, ROCK_PATH, lip + out * 0.6 + flank * (width * 0.5 + 1.25), top_y + 0.5, 1.2,
			salt + 10.0 + flank_side)
		_add_column(root, terrain, MOSSY_PATH, lip - out * fall_run * 0.55 + flank * (width * 0.6 + 1.0),
			water_y + drop * 0.5, 1.0, salt + 20.0 + flank_side)
		# Boulders behind the lip, higher still, hiding where the stream
		# comes from.
		_add_column(root, terrain, ROCK_PATH, lip + out * (face * 1.9 + 0.6) + flank * width * 0.3, top_y + 1.0,
			1.4, salt + 30.0 + flank_side)
		# Stones in the pool, half under water.
		_add_rock(root, ROCK_PATH, _at(terrain, landing - out * 1.3 + flank * width * 0.7), water_y + 0.25, 0.55,
			salt + 40.0 + flank_side)
	_add_column(root, terrain, MOSSY_PATH, lip + out * (face * 2.4 + 1.6), top_y + 1.5, 1.5, salt + 50.0)
	# Scattered along the shore on the way in from the fall.
	var reach: float = end.reach
	var side: float = 1.0 if index > 0 else -1.0
	var i: int = 0
	for back: float in [4.0, 7.5, 11.0, 15.0]:
		for flank_side: float in [-1.0, 1.0]:
			i += 1
			var noise: float = _hash(salt + 60.0 + float(i))
			if noise < 0.3 or reach - back < MIN_REACH * 0.5:
				continue
			var centre: Vector2 = _centre_point(terrain, river, side * (reach - back))
			var shore: float = _shore_distance(terrain, river, centre, across * flank_side)
			var at: Vector2 = centre + across * flank_side * (shore + 0.3)
			var path: String = MOSSY_PATH if noise > 0.7 else ROCK_PATH
			var size: float = lerpf(0.5, 1.1, _hash(salt + 80.0 + float(i)))
			var ground: Vector3 = _at(terrain, at, size)
			_add_rock(root, path, ground, ground.y + 0.15 + size * 0.75, size, salt + 100.0 + float(i))


static func _ground(terrain: Node3D, p: Vector2) -> float:
	return terrain.height_at(Vector3(p.x, 0.0, p.y))


## `p` on the ground, sunk to the lowest ground under a rock `radius` across
## and a little more, so on a bank no rock shows sky under its downhill edge
## (one hung over the water's edge, playtest 2026-09-28).
static func _at(terrain: Node3D, p: Vector2, radius: float = 0.6) -> Vector3:
	var low: float = _ground(terrain, p)
	for k: int in range(6):
		var angle: float = TAU * float(k) / 6.0
		low = minf(low, _ground(terrain, p + Vector2(cos(angle), sin(angle)) * radius * 0.8))
	return Vector3(p.x, low - 0.15, p.y)


## The sheet's height `x` metres in from the lip: level at the lip, falling
## ever steeper to `drop` below it at `fall_run`.
static func _sheet_height(top_y: float, drop: float, fall_run: float, x: float) -> float:
	var f: float = clampf(x / fall_run, 0.0, 1.0)
	return top_y - drop * f * f


## The falling water, as a strip SHEET_COLUMNS wide following the centreline:
## bowed out in the middle, its sides curled back and spreading as it falls.
## `veil`: the second, thinner layer standing just in front of the body.
static func _add_sheet(root: Node3D, lip: Vector2, out: Vector2, across: Vector2, top_y: float, drop: float,
		fall_run: float, width: float, veil: bool) -> void:
	# The centreline: the feed running over the lip, then the fall, ending a
	# little under the water so it disappears into it.
	# COLOR.g marks the lip, where the shader whitens the water as it tips over.
	var points: Array[Vector3] = []
	var falls: PackedFloat32Array = []
	var lips: PackedFloat32Array = []
	for back: float in [FEED_LENGTH, 0.5]:
		var feed: Vector2 = lip + out * back
		points.append(Vector3(feed.x, top_y, feed.y))
		falls.append(0.0)
		lips.append(0.0)
	for k: int in range(FALL_SEGMENTS + 1):
		var x: float = fall_run * float(k) / float(FALL_SEGMENTS)
		var p: Vector2 = lip - out * x
		var y: float = _sheet_height(top_y, drop, fall_run, x) - (0.08 if k == FALL_SEGMENTS else 0.0)
		points.append(Vector3(p.x, y, p.y))
		falls.append(float(k) / float(FALL_SEGMENTS))
		lips.append(1.0 if k == 0 else 0.0)
	var side := Vector3(across.x, 0.0, across.y)
	# Away from the cliff: up over the feed, out toward the pool down the fall.
	var away := Vector3(-out.x, 1.0, -out.y)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var along: float = 0.0
	var row: int = SHEET_COLUMNS + 1
	for k: int in points.size():
		if k > 0:
			along += points[k].distance_to(points[k - 1])
		var tangent: Vector3 = (points[mini(k + 1, points.size() - 1)] - points[maxi(k - 1, 0)]).normalized()
		var normal: Vector3 = side.cross(tangent).normalized()
		if normal.dot(away) < 0.0:
			normal = -normal
		# Spreads a little as it falls; the veil a touch narrower than the body.
		var half: float = width * 0.5 * (1.0 + 0.1 * falls[k]) * (0.9 if veil else 1.0)
		var bulge: float = SHEET_BULGE * (0.35 + 0.65 * falls[k])
		var lift: float = VEIL_OFFSET * (0.4 + 0.6 * falls[k]) if veil else 0.0
		for c: int in range(row):
			var s: float = float(c) / float(SHEET_COLUMNS) * 2.0 - 1.0
			# Bowed out at the middle, the edges curled back toward the rock.
			var push: float = bulge * (1.0 - s * s) - 0.12 * absf(s * s * s) * falls[k] + lift
			vertices.append(points[k] + side * s * half + normal * push)
			normals.append((normal + side * s * 0.35).normalized())
			colors.append(Color(falls[k], lips[k], 0.0, 1.0))
			uvs.append(Vector2((s + 1.0) * 0.5, along))
		if k > 0:
			for c: int in range(SHEET_COLUMNS):
				var i: int = k * row + c
				indices.append_array(PackedInt32Array([i - row, i - row + 1, i, i - row + 1, i + 1, i]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material(false, 1.0 if veil else 0.0))
	var visual := MeshInstance3D.new()
	visual.name = ("FallVeil%d" if veil else "FallSheet%d") % root.get_child_count()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(visual)


## The foam where the water lands: a quad on the water reaching a little
## back under the fall and well downstream, the shader working out where the
## impact is (its "impact" UV) and carrying the foam away from it.
static func _add_pool(root: Node3D, landing: Vector2, out: Vector2, across: Vector2, water_y: float,
		width: float) -> void:
	var back: float = width * 0.55
	var ahead: float = width * 2.1
	var half: float = width
	var y: float = water_y + 0.03
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for v: float in [0.0, 1.0]:
		for u: float in [0.0, 1.0]:
			var p: Vector2 = landing + out * lerpf(back, -ahead, v) + across * lerpf(-half, half, u)
			vertices.append(Vector3(p.x, y, p.y))
			uvs.append(Vector2(u, v))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 3, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: ShaderMaterial = _material(true)
	material.set_shader_parameter(&"pool_size", Vector2(half * 2.0, back + ahead))
	material.set_shader_parameter(&"impact", Vector2(0.5, back / (back + ahead)))
	mesh.surface_set_material(0, material)
	var visual := MeshInstance3D.new()
	visual.name = "FallFoam%d" % root.get_child_count()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(visual)


## Spray drifting up and away from where the water lands: a few soft white
## puffs (CPUParticles3D, which the GL Compatibility renderer runs anywhere),
## already going when the terrain is built. Only something to look at -- each
## peer's puffs are its own.
static func _add_mist(root: Node3D, landing: Vector2, out: Vector2, water_y: float, width: float) -> void:
	var mist := CPUParticles3D.new()
	mist.name = "FallMist%d" % root.get_child_count()
	mist.position = Vector3(landing.x, water_y + 0.25, landing.y)
	mist.amount = 22
	mist.lifetime = 2.6
	mist.preprocess = 2.6
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = width * 0.4
	mist.direction = Vector3(-out.x * 0.7, 1.0, -out.y * 0.7)
	mist.spread = 35.0
	mist.initial_velocity_min = 0.5
	mist.initial_velocity_max = 1.3
	mist.gravity = Vector3(0.0, -0.18, 0.0)
	mist.damping_min = 0.25
	mist.damping_max = 0.45
	mist.scale_amount_min = 0.9
	mist.scale_amount_max = 1.6
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.45))
	grow.add_point(Vector2(1.0, 1.4))
	mist.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.2, Color(1.0, 1.0, 1.0, 0.32))
	fade.add_point(0.6, Color(1.0, 1.0, 1.0, 0.18))
	mist.color_ramp = fade
	var puff := QuadMesh.new()
	puff.size = Vector2(1.5, 1.5)
	puff.material = _mist_material()
	mist.mesh = puff
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mist)


static var _mist: StandardMaterial3D


## A soft round puff, facing the camera, tinted by the particle's colour.
static func _mist_material() -> StandardMaterial3D:
	if _mist != null:
		return _mist
	var soft := Gradient.new()
	soft.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	soft.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = soft
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	_mist = StandardMaterial3D.new()
	_mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mist.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mist.vertex_color_use_as_albedo = true
	_mist.albedo_texture = texture
	_mist.albedo_color = Color(0.92, 0.96, 1.0)
	return _mist


static func _material(pool: bool, layer: float = 0.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FALL_SHADER
	material.set_shader_parameter(&"pool", pool)
	material.set_shader_parameter(&"layer", layer)
	return material


## A pile of boulders at `p` from the ground up to `top_y`, each about
## `radius` across and in natural proportion (ROCK_MAX_RATIO), overlapping
## and a little off-centre so it reads as a rocky outcrop. Broad at the foot
## and narrower going up: same-sized stones one on another read as a cairn
## balanced there, not a crag (render_river.gd, 2026-09-29).
static func _add_column(root: Node3D, terrain: Node3D, path: String, p: Vector2, top_y: float, radius: float,
		salt: float) -> void:
	var base: Vector3 = _at(terrain, p, radius)
	var layer: int = 0
	while layer < 4:
		var r: float = radius * lerpf(0.85, 1.1, _hash(salt + float(layer) * 3.1)) * (1.3 - 0.22 * float(layer))
		var h: float = minf(top_y - base.y, r * ROCK_MAX_RATIO)
		if h <= 0.05:
			break
		var shift := Vector3(_hash(salt + float(layer) * 1.7) - 0.5, 0.0, _hash(salt + float(layer) * 2.3) - 0.5)
		_add_rock(root, path, base + shift * r * 0.3 * float(layer), base.y + h, r, salt + float(layer))
		if base.y + h >= top_y - 0.05:
			break
		base.y += h * 0.65
		layer += 1


## One boulder, its base at `base`, reaching up to `top_y`, `radius` metres
## around. Too low for its radius, it's a smaller rock instead of a flat one.
static func _add_rock(root: Node3D, path: String, base: Vector3, top_y: float, radius: float, salt: float) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var h: float = maxf(top_y - base.y, 0.1)
	var r: float = minf(radius, h / ROCK_MIN_RATIO)
	var rock := packed.instantiate() as Node3D
	LowpolyMaterials.apply(rock)
	_wet(rock)
	rock.name = "FallRock%d" % root.get_child_count()
	rock.position = base
	rock.rotation.y = _hash(salt) * TAU
	var wide: float = r / ROCK_RADIUS
	rock.scale = Vector3(wide, h / ROCK_HEIGHT, wide * lerpf(0.8, 1.2, _hash(salt + 0.5)))
	root.add_child(rock)


## Darker than the forest's dry rocks: wet stone by the water. In full sun
## the shared rock material read almost white next to the falls
## (render_river.gd, 2026-09-28); at 0.62 they went almost black against the
## light (2026-09-29). One darkened copy per source material.
const WET_TINT: float = 0.74
static var _wet_materials: Dictionary = {}


static func _wet(rock: Node3D) -> void:
	for node: Node in rock.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		for surface: int in range(instance.mesh.get_surface_count()):
			var source := instance.get_active_material(surface) as BaseMaterial3D
			if source == null:
				continue
			var key: int = source.get_instance_id()
			if not _wet_materials.has(key):
				var copy := source.duplicate() as BaseMaterial3D
				copy.albedo_color = Color(source.albedo_color * WET_TINT, source.albedo_color.a)
				copy.roughness = source.roughness * 0.8
				_wet_materials[key] = copy
			instance.set_surface_override_material(surface, _wet_materials[key])


## 0..1, a fixed function of `salt`: the same on every peer.
static func _hash(salt: float) -> float:
	return fposmod(sin(salt * 12.9898 + 78.233) * 43758.5453, 1.0)

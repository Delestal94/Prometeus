extends SceneTree
## Run without --headless. Saves a level crossing's tunnels (rail_crossing_
## segment.gd, route_terrain.gd tunnels) under user://: the train coming out
## of the near portal, the far portal, both from the road as the driver sees
## them, and from above and beside to check the hill over the bore and the
## hole the terrain leaves for it. Terrain set up the way route.gd does it.
##
## Lit like the game (N-318.3): the Sun and WorldEnvironment are the ones in
## level_base.tscn, WorldMood.apply() and RouteSky set the day and the sky the
## way a route does, and the shadow settings are WorldQuality's. The default
## mood is clear summer day; force another with `-- --mood=soleado_atardecer`.
##
## The last view, "tunnel_shadow_edge", is the hill's shadow on the road,
## asphalt against asphalt: the sun is turned to the game's dusk height (the
## same -13 degrees world_mood.gd uses) and to shine across the track, the
## script marches a ray from the road up to the sun through the terrain to find
## where the hill's shadow starts, and looks at that spot from the road. It
## prints the edge's luminance profile: lit / shade / 10-90 % width, in pixels
## and in metres on the ground. (The earlier "shadow" edge of tunnel_from_road
## was the road's shoulder: asphalt against dirt, no shadow on the road there.)
##
## To compare settings in one run each, extra user arguments (after `--`):
##   --quality=0|1|2        WorldQuality level (Low, Medium, High; default High)
##   --shadow-filter=0..5   RenderingServer.ShadowQuality, over the level's
##   --shadow-atlas=N       directional atlas side in pixels, over the level's
##   --shadow-opacity=F     the Sun's shadow_opacity, over the scene's
## e.g. the state before N-318.3: --shadow-filter=2 --shadow-atlas=4096 --shadow-opacity=1

const RouteTerrain = preload("res://scripts/gameplay/route/route_terrain.gd")
const LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"

const VIEWS: Array = [
	["tunnel_near_front", Vector3(-22.0, 4.0, -7.0), Vector3(-42.0, 3.0, -16.0)],
	["tunnel_far_front", Vector3(22.0, 3.5, -24.0), Vector3(42.0, 3.5, -16.0)],
	["tunnel_from_road", Vector3(1.5, 2.6, 6.0), Vector3(-42.0, 3.0, -16.0)],
	["tunnel_above", Vector3(-22.0, 32.0, 8.0), Vector3(-48.0, 3.0, -16.0)],
	["tunnel_side", Vector3(-38.0, 20.0, 16.0), Vector3(-47.0, 5.0, -16.0)],
]

## The sun for the shadow-edge view: the game's dusk pitch (world_mood.gd), and a
## yaw that makes it travel along +x, from the near tunnel's hill to the road.
const SHADOW_SUN_TURN := Vector3(-13.0, -90.0, 0.0)
## How far along the road, each way from the track, the hill's shadow is looked for.
const SHADOW_SCAN_HALF: float = 70.0
## Shadow edges closer to the track than this are skipped: its stop lines
## (white on the asphalt) would be measured as the edge.
const SHADOW_MIN_TRACK_GAP: float = 14.0
## How far back along the road the camera stands from the edge, and how much of
## the road on each side of the edge is measured (metres along it).
const SHADOW_CAMERA_BACK: float = 14.0
const SHADOW_WINDOW_NEAR: float = 5.0
const SHADOW_WINDOW_FAR: float = 4.0
const SHADOW_RAY_LENGTH: int = 160
const EDGE_COLUMNS: Array[int] = [600, 640, 680]
## Half width, in pixels, of the strip averaged at each row.
const EDGE_STRIP: int = 4


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var sun: DirectionalLight3D = _take_game_light(world)
	_apply_overrides(sun)
	var terrain: Node3D = RouteTerrain.new()
	world.add_child(terrain)
	terrain.add_span(Vector3(0, 0, 120), Vector3(0, 0, -120))
	var crossing := RailCrossingSegment.new()
	crossing.continuous_terrain = true
	world.add_child(crossing)
	var level: float = terrain.base_height(Vector2(0.0, crossing.track_z))
	for pad: Vector3 in crossing.track_pads():
		terrain.pads.append(Vector3(pad.x, level, pad.z))
	for mouth: Dictionary in crossing.tunnel_mouths():
		mouth["level"] = level
		terrain.tunnels.append(mouth)
	terrain.build()
	terrain.conform_geometry(crossing)
	crossing.set_meta(&"track_height", terrain.height_at(Vector3(0.0, 0.0, crossing.track_z)))
	# The route's sky, after the terrain: it picks the mood (--mood= or the
	# default), applies it to the sun and the environment, swaps in the painted
	# sky and tells the terrain's material about the wet or the night.
	var route_sky := RouteSky.new()
	route_sky.name = "RouteSky"
	world.add_child(route_sky)
	print("Lit as the game: mood %s, sun energy %.2f, shadow opacity %.2f, quality level %d" % [
		String(WorldMood.active.get("label", "?")), sun.light_energy, sun.shadow_opacity, WorldQuality.level])
	# The train halfway out of the near tunnel, frozen there.
	crossing.set_physics_process(false)
	crossing.state = RailCrossingSegment.State.TRAIN
	crossing.set(&"_train_x", -RailCrossingSegment.PORTAL_X + 5.0)
	crossing.call(&"_place_train")
	var camera := Camera3D.new()
	camera.fov = 70.0
	world.add_child(camera)
	camera.current = true
	for view: Array in VIEWS:
		camera.position = view[1]
		camera.look_at(view[2])
		for _i: int in 4:
			await process_frame
		await _shot("render_%s.png" % view[0])
	await _shadow_edge_view(camera, sun, terrain, crossing.track_z)
	world.queue_free()
	await process_frame
	await process_frame
	quit(0)


## The level scene's own Sun and WorldEnvironment, moved into `world`: the
## script lights the tunnel with the numbers the game does, not a copy of them
## that drifts. The rest of the level is never added to the tree, so none of it
## runs.
func _take_game_light(world: Node3D) -> DirectionalLight3D:
	var level_scene: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	var sun := level_scene.get_node(^"Sun") as DirectionalLight3D
	var environment := level_scene.get_node(^"WorldEnvironment") as WorldEnvironment
	level_scene.remove_child(sun)
	level_scene.remove_child(environment)
	level_scene.free()
	world.add_child(environment)
	world.add_child(sun)
	# A fixed day unless --mood= says otherwise (WorldMood.pick reads it): with
	# the world seed at 0 the mood would be drawn at random every run.
	WorldMood.forced_label = "soleado_dia_verano"
	return sun


func _apply_overrides(sun: DirectionalLight3D) -> void:
	var filter: int = int(WorldQuality.setting("shadow_filter"))
	var atlas: int = int(WorldQuality.setting("shadow_atlas"))
	var changed: bool = false
	for arg: String in OS.get_cmdline_user_args():
		var value: String = arg.get_slice("=", 1)
		if arg.begins_with("--quality="):
			WorldQuality.apply(self, int(value))
			filter = int(WorldQuality.setting("shadow_filter"))
			atlas = int(WorldQuality.setting("shadow_atlas"))
		elif arg.begins_with("--shadow-filter="):
			filter = int(value)
			changed = true
		elif arg.begins_with("--shadow-atlas="):
			atlas = int(value)
			changed = true
		elif arg.begins_with("--shadow-opacity="):
			sun.shadow_opacity = float(value)
	if changed:
		WorldQuality.apply_shadow_softness(filter, atlas)
	print("Shadows: filter %d, atlas %d px" % [filter, atlas])


## The hill's shadow across the road, seen from the road, and its edge measured.
func _shadow_edge_view(camera: Camera3D, sun: DirectionalLight3D, terrain: Node3D, track_z: float) -> void:
	sun.rotation_degrees = SHADOW_SUN_TURN
	var edge_z: float = _shadow_edge_z(terrain, sun.global_basis.z, track_z)
	if is_nan(edge_z):
		push_warning("No hill shadow crosses the road within %.0f m of the track: shadow-edge view skipped."
			% SHADOW_SCAN_HALF)
		return
	var ground: float = terrain.height_at(Vector3(0.0, 0.0, edge_z))
	camera.position = Vector3(0.0, ground + 2.6, edge_z + SHADOW_CAMERA_BACK)
	camera.look_at(Vector3(0.0, ground, edge_z - 10.0))
	for _i: int in 4:
		await process_frame
	var image: Image = await _shot("render_tunnel_shadow_edge.png")
	var row_far: int = int(camera.unproject_position(Vector3(0.0, ground, edge_z - SHADOW_WINDOW_FAR)).y)
	var row_near: int = int(camera.unproject_position(Vector3(0.0, ground, edge_z + SHADOW_WINDOW_NEAR)).y)
	var per_metre: float = absf(camera.unproject_position(Vector3(0.0, ground, edge_z + 1.0)).y
		- camera.unproject_position(Vector3(0.0, ground, edge_z - 1.0)).y) * 0.5
	print("Hill shadow crosses the road at z=%.0f (track at %.0f): rows %d-%d, %.1f px per metre of road"
		% [edge_z, track_z, row_far, row_near, per_metre])
	for column: int in EDGE_COLUMNS:
		var edge: Dictionary = _measure_edge(image, column, maxi(row_far, 0), mini(row_near, image.get_height() - 1))
		if edge.is_empty():
			print("  x=%d: window too small to measure" % column)
		elif is_nan(float(edge.width)):
			print("  x=%d: no clear edge (lit %.3f, shade %.3f)" % [column, edge.lit, edge.shade])
		else:
			print("  x=%d: edge row %d, lit %.3f, shade %.3f, ratio %.2f, 10-90 %% width %.1f px = %.2f m"
				% [column, edge.row, edge.lit, edge.shade, edge.ratio, edge.width, float(edge.width) / per_metre])


## The z, along the road (x = 0) and at least SHADOW_MIN_TRACK_GAP from the
## track, where the terrain's shadow starts or ends; NAN when the road is all
## lit or all in shadow. `to_sun` is the unit vector from the ground to the sun.
func _shadow_edge_z(terrain: Node3D, to_sun: Vector3, track_z: float) -> float:
	var previous: int = -1
	var z: float = track_z + SHADOW_SCAN_HALF
	while z >= track_z - SHADOW_SCAN_HALF:
		var shaded: int = 1 if _terrain_shades(terrain, Vector3(0.0, 0.0, z), to_sun) else 0
		if previous >= 0 and shaded != previous and absf(z - track_z) >= SHADOW_MIN_TRACK_GAP:
			return z
		previous = shaded
		z -= 1.0
	return NAN


## Whether the height field stands between the ground at `point` and the sun.
func _terrain_shades(terrain: Node3D, point: Vector3, to_sun: Vector3) -> bool:
	var origin := Vector3(point.x, terrain.height_at(point) + 0.05, point.z)
	for step: int in range(1, SHADOW_RAY_LENGTH):
		var probe: Vector3 = origin + to_sun * float(step)
		if terrain.height_at(probe) > probe.y:
			return true
	return false


## Luminance down one column of the image, between two rows (far, then near),
## as {lit, shade, ratio, row (steepest), width (10-90 %, in rows)}. The lit and
## shade levels are the medians of the window's first and last quarter; the
## width is walked out from the steepest row until each level is crossed.
func _measure_edge(image: Image, column: int, row_top: int, row_bottom: int) -> Dictionary:
	var count: int = row_bottom - row_top + 1
	if count < 40:
		return {}
	var levels := PackedFloat32Array()
	for row: int in range(row_top, row_bottom + 1):
		var total: float = 0.0
		for dx: int in range(-EDGE_STRIP, EDGE_STRIP + 1):
			total += image.get_pixel(column + dx, row).get_luminance()
		levels.append(total / float(EDGE_STRIP * 2 + 1))
	var quarter: int = count >> 2
	var top: float = _median(levels.slice(0, quarter))
	var bottom: float = _median(levels.slice(count - quarter))
	var high: float = maxf(top, bottom)
	var low: float = minf(top, bottom)
	var steepest: int = 1
	for i: int in range(1, count - 1):
		if absf(levels[i + 1] - levels[i - 1]) > absf(levels[steepest + 1] - levels[steepest - 1]):
			steepest = i
	var result: Dictionary = {"lit": high, "shade": low, "ratio": low / maxf(high, 0.0001),
		"row": row_top + steepest, "width": NAN}
	if high - low < 0.02:
		return result
	var toward_lit: int = -1 if top > bottom else 1
	var lit_row: float = _walk(levels, steepest, toward_lit, low + 0.9 * (high - low))
	var shade_row: float = _walk(levels, steepest, -toward_lit, low + 0.1 * (high - low))
	if not is_nan(lit_row) and not is_nan(shade_row):
		result["width"] = absf(lit_row - shade_row)
	return result


## Where, walking from `start` by `step` rows, the profile first crosses `level`.
func _walk(levels: PackedFloat32Array, start: int, step: int, level: float) -> float:
	var i: int = start
	while i + step >= 0 and i + step < levels.size():
		var here: float = levels[i]
		var next: float = levels[i + step]
		if (here - level) * (next - level) <= 0.0 and here != next:
			return float(i) + float(step) * (level - here) / (next - here)
		i += step
	return NAN


func _median(values: PackedFloat32Array) -> float:
	var sorted: Array = Array(values)
	sorted.sort()
	return float(sorted[sorted.size() >> 1])


func _shot(file_name: String) -> Image:
	await RenderingServer.frame_post_draw
	var path: String = "user://" + file_name
	var image: Image = root.get_texture().get_image()
	image.save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
	return image

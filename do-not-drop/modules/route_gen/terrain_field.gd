class_name TerrainField
extends Node3D
## One world-space height field, shared by rendering, physics and prop
## placement: road spans keep it flat, pads and flat zones level it, crests
## lift it, rivers carve it, tunnels bury the road in a hill. Sparse square
## tiles cannot overlap at bends, even if the road doubles back. Portable
## module (docs/modulos.md): the game hands in its shader and textures and
## decorates its rivers through the hooks at the end; without them the
## tiles get a plain built-in shader.
const TILE: float = 32.0
const STEP: float = 2.0
const HALO: float = 64.0
const CELLS: int = 16
var spans: Array[Dictionary] = []
var pads: Array[Vector3] = []
var paths: Array[Dictionary] = []
## Crests the road climbs over (HillSegment, tareas #56): {"a", "b": Vector2
## ends of that stretch of road, "height": metres at the top}. The rise
## follows the road's length as sin^2 (flat at both ends, so it joins the
## neighbouring segments smoothly) and fades out sideways, so the ground
## beside the road climbs with it.
var crests: Array[Dictionary] = []
## Riverbeds a NarrowBridgeSegment crosses: {"a", "b": Vector2 ends of that
## stretch (its own centreline, straight -- the segment never turns),
## "depth": metres the ground drops away by, "full_width": half-width of the
## flat riverbed floor, "bank_width": how far out it's still fading back to
## the ambient ground}. Unlike a crest this never touches the segment's own
## furniture (deck, rails, posts, the authored water/bank model) --
## conform_geometry() skips it for anything under a node flagged
## &"ignore_river" (see NarrowBridgeSegment._build()), so the bridge floats
## over the drop instead of sinking into it with the rest of the ground.
## Fades to nothing at both ends of the span (RIVER_TAPER) so it never leaves
## a seam against neighbouring, river-free terrain, and route.gd shrinks
## `bank_width` on its own to keep a long river from cutting into another
## stretch of road, a house or the depot yard (route_ground.gd clamp_river_reach()).
## Meanders a little (a smooth, position-seeded wobble, not the session's
## RNG) so it doesn't read as a perfectly straight ditch, and its edges
## wobble too so the shoreline is organic rather than a rectangle.
var rivers: Array[Dictionary] = []
## How far in from each end of a river's span the drop is still fading in.
## Longer than the authored bank model's own 3.2 m (build_route_pieces.py
## bridge_water()): drawn on the 2 m terrain grid, a 1.8 m drop over 3.2 m
## came out as steps and grass wedges at the bridge's ends (playtest
## 2026-09-28).
const RIVER_TAPER: float = 6.0
## The ground stays whole this far in under each end of the deck before the
## drop starts, so the deck covers the first, steepest part of the bank and
## the road meets the bridge on level ground.
const RIVER_INSET: float = 3.0
## How much of a river's depth is water: the rest is bank above it. The
## water is a surface of its own at that level (see _river_water_height()),
## so the shoreline is wherever the carved ground crosses it.
const RIVER_FILL: float = 0.45
## Defaults for a river entry that doesn't specify its own (only the tests'
## fixtures don't -- route.gd always sets both, see NarrowBridgeSegment's
## river_width/river_reach). Full depth out to RIVER_FULL_WIDTH from the
## (meandered) centreline, fading back up to the ambient ground by
## RIVER_BANK_WIDTH -- far enough to be lost in the landscape rather than
## read as a rectangular pool, but still short of the forest ridge that
## starts at 61 m (see _sample()).
const RIVER_FULL_WIDTH: float = 18.0
const RIVER_BANK_WIDTH: float = 60.0
## Level rectangles (x/z) the ground is flattened to height 0 inside of, then
## blends back out over FLAT_ZONE_BLEND -- the depot's footprint and yard
## (route.gd start_yard), so no hill ever pushes through its floor or walls.
var flat_zones: Array[Rect2] = []
## Level platforms at a height of their own, turned with the road (the goal
## lot, route_goal_lot.gd): {"centre": Vector2, "along": Vector2 (unit vector
## down the platform's length), "half": Vector2 (across, along), "height":
## metres}. Inside the rectangle the ground is exactly `height`; it blends
## back to the landscape over PLATFORM_BLEND.
var platforms: Array[Dictionary] = []
const PLATFORM_BLEND: float = 12.0
## Railway tunnels (RailCrossingSegment.tunnel_mouths(), levelled by
## route.gd): {"at": Vector2 the portal's facade on the track axis, "dir":
## Vector2 into the hill, "level": track height, "bore_half", "bore_length",
## "crown": the bore's size, "face_half": the facade's half-width, "height":
## how high the hill stands over the track}. Behind each portal the ground
## rises into a hill (_tunnel_hill()), sloping down toward the road beside the
## cutting the portal's wing walls hold back, and the terrain leaves a hole
## wherever it would cross the bore (_in_tunnel_bore()): a height field can't
## arch over a tunnel, so the bore is the model's and the ground just gets
## out of its way.
var tunnels: Array[Dictionary] = []
## The wing walls' flare (build_rail_crossing.py WING_ANGLE).
const TUNNEL_WING_ANGLE: float = deg_to_rad(25.0)
## How far above the bore's crown the hill's shelf behind a portal sits: over
## the 0.6 m _in_tunnel_bore() treats as "clears the roof", and under the
## Backfill's top (RailCrossingSegment.BACKFILL_ABOVE_CROWN).
const TUNNEL_SHELF_ABOVE_CROWN: float = 0.75
## The levelled backfill a track through a tunnel mouth stands on: how far
## in from the portal and how wide, either side of the road.
const BACKFILL_LENGTH: float = 5.4
const BACKFILL_HALF_WIDTH: float = 5.75
const FLAT_ZONE_BLEND: float = 10.0
const FLAT_ZONE_HEIGHT: float = -0.02
const HILL_FLANK: float = 55.0
var _buckets: Dictionary = {}
var _tiles: Dictionary = {}
var _samples: Dictionary = {}
const _NO_SPANS: Array = []
var _material: ShaderMaterial
## 0..1 how far build() / build_async() has got, for a loading bar.
var build_progress: float = 0.0
## What the workers are given and hand back while build_async() runs.
var _build_keys: Array = []
var _build_results: Array = []
var _build_group: int = -1
## The same for conform_all(): the meshes to warp, and the workers on them.
var conform_progress: float = 0.0
var _conform_jobs: Array = []
var _conform_group: int = -1
## True while conform_all()'s workers read _samples: it is not written to then.
var _workers_reading: bool = false


func add_span(a: Vector3, b: Vector3, gravel: bool = false, width: float = 6.0) -> void:
	var entry: Dictionary = {"a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z), "gravel": gravel, "width": width}
	spans.append(entry)
	var low := Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2.ONE * HALO
	var high := Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2.ONE * HALO
	for x: int in range(floori(low.x / TILE), floori(high.x / TILE) + 1):
		for z: int in range(floori(low.y / TILE), floori(high.y / TILE) + 1):
			var key := Vector2i(x, z)
			if not _buckets.has(key):
				_buckets[key] = []
			_buckets[key].append(entry)
			_tiles[key] = true


func nearest(p: Vector2) -> Vector3:
	var best: float = HALO * 4.0
	var gravel: float = 0.0
	var width: float = 6.0
	var key := Vector2i(floori(p.x / TILE), floori(p.y / TILE))
	var bucket: Array = _buckets.get(key, _NO_SPANS)
	if bucket.is_empty():
		bucket = []
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				bucket.append_array(_buckets.get(key + Vector2i(dx, dz), _NO_SPANS))
	for span: Dictionary in bucket:
		var a: Vector2 = span.a
		var edge: Vector2 = span.b - a
		var t: float = clampf((p - a).dot(edge) / maxf(edge.length_squared(), 0.001), 0.0, 1.0)
		var d: float = p.distance_to(a + edge * t)
		if d < best:
			best = d
			gravel = 1.0 if span.gravel else 0.0
			width = span.width
	return Vector3(best, gravel, width)


func base_height(p: Vector2) -> float:
	# Flat loading apron; long, gentle climbs with no change to the route's yaw.
	var fade: float = smoothstep(120.0, 210.0, p.length())
	return fade * (2.6 * sin(p.x * 0.014 + p.y * 0.019) + 1.4 * sin(p.y * 0.031 - p.x * 0.011)) + _hill_height(p)


func _hill_height(p: Vector2) -> float:
	var total: float = 0.0
	for hill: Dictionary in crests:
		var a: Vector2 = hill.a
		var edge: Vector2 = hill.b - a
		var t: float = clampf((p - a).dot(edge) / maxf(edge.length_squared(), 0.001), 0.0, 1.0)
		var side: float = p.distance_to(a + edge * t)
		var along: float = sin(PI * t)
		total += float(hill.height) * along * along * (1.0 - smoothstep(8.0, HILL_FLANK, side))
	return total


## The ground's height before any river carves into it -- shared by
## _sample() (the actual rendered/collidable terrain) and
## height_without_rivers() (what a bridge's own furniture and authored water
## model measure themselves against, so they float over the drop instead of
## sinking into it).
func _natural_height(p: Vector2, with_ridge: bool = true) -> float:
	return _natural_height_from(p, nearest(p), with_ridge)


## _natural_height() with the road lookup already done (`road` is nearest(p)):
## _sample() needs it for itself too, and nearest() is the costly part.
func _natural_height_from(p: Vector2, road: Vector3, with_ridge: bool = true) -> float:
	var offroad: float = smoothstep(12.0, 29.0, road.x)
	var hills: float = 1.7 + 1.4 * sin(p.x * 0.087 + p.y * 0.039) + 0.8 * cos(p.y * 0.11 - p.x * 0.043)
	var height: float = base_height(p) - smoothstep(5.5, 9.0, road.x) * 0.08 + offroad * hills
	# A rising forest ridge gives the playable corridor a visible boundary.
	# Left out of a river's water level: the water stops where the ridge
	# lifts the ground out of it, instead of climbing the slope with it.
	if with_ridge:
		height += smoothstep(38.0, 61.0, road.x) * 12.0
	for pad: Vector3 in pads:
		var weight: float = 1.0 - smoothstep(5.0, 11.0, p.distance_to(Vector2(pad.x, pad.z)))
		height = lerpf(height, pad.y, weight)
	for tunnel: Dictionary in tunnels:
		var hill: float = float(tunnel.level) + float(tunnel.height)
		height = maxf(height, lerpf(height, hill, _tunnel_hill(tunnel, p, road.x)))
		height = _tunnel_shelf(tunnel, p, height)
	for zone: Rect2 in flat_zones:
		var outside := Vector2(maxf(maxf(zone.position.x - p.x, p.x - zone.end.x), 0.0), maxf(maxf(zone.position.y - p.y, p.y - zone.end.y), 0.0))
		height = lerpf(height, FLAT_ZONE_HEIGHT, 1.0 - smoothstep(0.0, FLAT_ZONE_BLEND, outside.length()))
	for platform: Dictionary in platforms:
		var blend: float = smoothstep(0.0, PLATFORM_BLEND, _platform_gap(platform, p))
		height = lerpf(height, float(platform.height), 1.0 - blend)
	return height


## How far `p` is outside a platform's rectangle (0 anywhere inside it).
func _platform_gap(platform: Dictionary, p: Vector2) -> float:
	var along: Vector2 = platform.along
	var offset: Vector2 = p - (platform.centre as Vector2)
	var half: Vector2 = platform.half
	var local := Vector2(absf(offset.dot(Vector2(-along.y, along.x))), absf(offset.dot(along)))
	return Vector2(maxf(local.x - half.x, 0.0), maxf(local.y - half.y, 0.0)).length()


## 0..1: how much of `tunnel`'s hill stands at `p`. Nothing in front of the
## facade or inside the wing walls (the cutting), rising within a few metres
## behind them, lower toward the road so the hill's front meets the wing walls
## as they step down, fading into the landscape round about and never near
## any road.
func _tunnel_hill(tunnel: Dictionary, p: Vector2, road_distance: float) -> float:
	var dir: Vector2 = tunnel.dir
	var offset: Vector2 = p - (tunnel.at as Vector2)
	var along: float = offset.dot(dir)
	var side: float = absf(offset.dot(Vector2(-dir.y, dir.x))) - float(tunnel.face_half)
	# How far into the hill: behind the facade, or out past a wing wall.
	var inside: float = maxf(along, along * sin(TUNNEL_WING_ANGLE) + side * cos(TUNNEL_WING_ANGLE))
	return (smoothstep(0.8, 3.8, inside) * smoothstep(-10.0, 1.0, along)
		* (1.0 - smoothstep(18.0, 36.0, offset.length())) * smoothstep(16.0, 26.0, road_distance))


## `height` at `p`, held down to a shelf right behind a portal that stays no
## higher than the portal model's Backfill top (RailCrossingSegment.BACKFILL_*).
## The hill rises ~11 m within 3 m of the facade, and _in_tunnel_bore() drops
## any cell over the bore whose low corner is under the crown: on the 2 m grid
## that cell's back rim would stand at the hill's full height, above the
## Backfill, leaving a window under the ground with the sky showing through.
## The shelf is above crown + 0.6 (SHELF_ABOVE_CROWN), so it is never cut itself.
func _tunnel_shelf(tunnel: Dictionary, p: Vector2, height: float) -> float:
	var dir: Vector2 = tunnel.dir
	var offset: Vector2 = p - (tunnel.at as Vector2)
	var along: float = offset.dot(dir)
	if along <= 0.0:
		return height
	var across: float = absf(offset.dot(Vector2(-dir.y, dir.x)))
	var length: float = BACKFILL_LENGTH
	var half_width: float = BACKFILL_HALF_WIDTH
	var weight: float = ((1.0 - smoothstep(length, length + 3.6, along))
		* (1.0 - smoothstep(half_width, half_width + 3.25, across)))
	return minf(height, lerpf(height, float(tunnel.level) + float(tunnel.crown) + TUNNEL_SHELF_ABOVE_CROWN, weight))


## Whether the terrain cell whose first corner is `key` would show inside a
## tunnel's bore: some corner lies over the bore (behind the facade) and the
## cell is neither flat track bed nor high enough to clear the bore's roof.
## Those cells are left out, so the bore model shows through.
func _in_tunnel_bore(key: Vector2i, cache: Dictionary) -> bool:
	for tunnel: Dictionary in tunnels:
		var dir: Vector2 = tunnel.dir
		var over: bool = false
		var low: float = INF
		var high: float = -INF
		for corner: Vector2i in [key, key + Vector2i(1, 0), key + Vector2i(0, 1), key + Vector2i(1, 1)]:
			var offset: Vector2 = Vector2(corner) * STEP - (tunnel.at as Vector2)
			var along: float = offset.dot(dir)
			var across: float = absf(offset.dot(Vector2(-dir.y, dir.x)))
			if along >= 0.0 and along <= float(tunnel.bore_length) + 1.0 and across < float(tunnel.bore_half) + 0.4:
				over = true
			var height: float = _sample_in(corner, cache).x - float(tunnel.level)
			low = minf(low, height)
			high = maxf(high, height)
		if over and high > 0.25 and low < float(tunnel.crown) + 0.6:
			return true
	return false


## A deterministic wobble for `river`, purely a function of its own fixed
## endpoints -- no RNG, so every peer (and a rebuilt terrain) agrees, and two
## different bridges don't all meander in lockstep.
func _river_phase(river: Dictionary) -> float:
	var a: Vector2 = river.a
	return fmod(a.x * 0.037 + a.y * 0.029, TAU)


## 0..1: how much `river` affects `p`, combining the fade at both ends of its
## span (RIVER_TAPER) with the sideways fade from its (meandered) centreline
## out past its bank. Shared by _river_drop() (the actual carved ground) and
## the water mesh (_build_river_water()) so the visible water can never float
## above dry, uncarved ground or cut off in a straight line the terrain
## doesn't follow -- both read the exact same shape.
## Meander/wobble amplitudes (see _river_factor()) and their combined worst
## case -- how far a "wet" point can ever sit past a river's nominal
## `bank_width` in either direction. route_ground.gd's clamp_river_reach() has to
## clear a hazard by at least this much (its own margin on top for comfort),
## or the meander could still swing the actual carved/visible river into
## whatever it was supposed to stop short of.
const RIVER_MEANDER_MAX: float = 7.0
const RIVER_WOBBLE_MAX: float = 4.0
const RIVER_MAX_DRIFT: float = RIVER_MEANDER_MAX + RIVER_WOBBLE_MAX


func _river_factor(river: Dictionary, p: Vector2) -> float:
	var a: Vector2 = river.a
	var edge: Vector2 = river.b - a
	var length: float = maxf(edge.length(), 0.001)
	var dir: Vector2 = edge / length
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var phase: float = _river_phase(river)
	# u: along the road from the bridge's middle; v: out from the road.
	var u: float = (p - a).dot(dir) - length * 0.5
	var v: float = (p - a).dot(perp)
	var out: float = absf(v)
	# The channel crosses under the deck, narrower than it: its banks end
	# RIVER_INSET short of each end, so the road meets the bridge on whole
	# ground. Straight right under the road, it meanders and changes width
	# further out, so from the bank it reads as a river, not a canal.
	var free: float = smoothstep(8.0, 30.0, out)
	var centre: float = river_centre(river, v)
	var full_width: float = float(river.get("full_width", RIVER_FULL_WIDTH))
	var bank_width: float = maxf(float(river.get("bank_width", RIVER_BANK_WIDTH)), full_width + 1.0)
	# Where it runs out, wobbling from one side of the channel to the other,
	# so its end is never a line parallel to the road.
	var end_reach: float = bank_width - 3.0 + sin(u * 0.23 + phase) * 3.0
	# Out towards its end the channel narrows to a stream and fades: a creek
	# coming down from the hills, not a pool cut off square (playtest
	# 2026-09-28).
	var pinch: float = 1.0 - smoothstep(end_reach * 0.3, end_reach * 0.8, out)
	var half_width: float = (clampf(length * 0.5 - RIVER_INSET - RIVER_TAPER, 3.0, 14.0)
		+ (sin(v * 0.13 + phase * 2.3) * 2.0 + 2.0) * free) * lerpf(0.1, 1.0, pinch)
	var across: float = 1.0 - smoothstep(half_width, half_width + RIVER_TAPER, absf(u - centre))
	# Fades only once it's narrowed: the water ends in a point, not a bulb.
	var lengthwise: float = 1.0 - smoothstep(maxf(full_width, end_reach * 0.8), end_reach, out)
	return across * lengthwise


## Where the channel's (meandered) centreline sits along the road, measured
## from the bridge's middle, `v` metres out from the road (see
## _river_factor()). Also how RiverFalls follows the water out to its ends.
func river_centre(river: Dictionary, v: float) -> float:
	var phase: float = _river_phase(river)
	var free: float = smoothstep(8.0, 30.0, absf(v))
	return (sin(v * 0.09 + phase) * 5.5 + sin(v * 0.21 + phase * 1.7) * 1.5) * free


## How far the ground drops for a river at `p`, 0 outside every registered
## span. Smooth on every axis (see _river_factor()): never a hole, never a
## seam against untouched ground.
func _river_drop(p: Vector2) -> float:
	var total: float = 0.0
	for river: Dictionary in rivers:
		total += float(river.depth) * _river_factor(river, p)
	return total


## Public alias of _river_drop() for anything outside this script that needs
## to know "is this spot in a riverbed" without caring about the carved
## height itself -- RouteDresser's placement rules (no tree, pole, car or
## roadside prop belongs in the water or the bare bed beside it).
func river_depth_at(p: Vector2) -> float:
	return _river_drop(p)


func _sample(key: Vector2i) -> Vector3:
	if _workers_reading:
		# Workers are reading the cache: nothing may be written to it from here meanwhile.
		return _sample_reading(key, {})
	return _sample_in(key, _samples)


## _sample() through `cache`: the shared one, or a worker's own (a worker
## never touches the shared dictionary).
func _sample_in(key: Vector2i, cache: Dictionary) -> Vector3:
	var hit: Variant = cache.get(key)
	if hit != null:
		return hit
	var p := Vector2(key) * STEP
	var road: Vector3 = nearest(p)
	var drop: float = _river_drop(p)
	var height: float = _natural_height_from(p, road) - drop
	# The road's paint stops at the riverbed: the shader draws asphalt by
	# distance to the road, and the bed under the deck is not road.
	var road_mask: float = road.x - road.z + 6.0
	# 14: past the shader's shoulder (sand) and into its grass band.
	road_mask = lerpf(road_mask, maxf(road_mask, 14.0), clampf(drop / 0.6, 0.0, 1.0))
	var result := Vector3(height, road_mask, road.y)
	cache[key] = result
	return result


func height_at(p: Vector3) -> float:
	# Interpolate the actual rendered triangle, not a second approximation.
	var grid := Vector2(p.x, p.z) / STEP
	var k := Vector2i(floori(grid.x), floori(grid.y))
	var f := grid - Vector2(k)
	var a: float = _sample(k).x
	var b: float = _sample(k + Vector2i(1, 0)).x
	var c: float = _sample(k + Vector2i(0, 1)).x
	var d: float = _sample(k + Vector2i(1, 1)).x
	if f.x + f.y <= 1.0:
		return a + (b - a) * f.x + (c - a) * f.y
	return d + (c - d) * (1.0 - f.x) + (b - d) * (1.0 - f.y)


## height_at() for a worker thread: the samples the field already worked out are
## read from its cache and never written to; the ones it has to work out go in
## the worker's own `local`. The same numbers height_at() answers.
func _height_reading(p: Vector3, local: Dictionary) -> float:
	var grid := Vector2(p.x, p.z) / STEP
	var k := Vector2i(floori(grid.x), floori(grid.y))
	var f := grid - Vector2(k)
	var a: float = _sample_reading(k, local).x
	var b: float = _sample_reading(k + Vector2i(1, 0), local).x
	var c: float = _sample_reading(k + Vector2i(0, 1), local).x
	var d: float = _sample_reading(k + Vector2i(1, 1), local).x
	if f.x + f.y <= 1.0:
		return a + (b - a) * f.x + (c - a) * f.y
	return d + (c - d) * (1.0 - f.x) + (b - d) * (1.0 - f.y)


func _sample_reading(key: Vector2i, local: Dictionary) -> Vector3:
	var hit: Variant = _samples.get(key)
	if hit != null:
		return hit
	return _sample_in(key, local)


## Same interpolation as height_at(), but ignoring every river: what a
## bridge's own deck, rails and authored water model are measured against
## (see conform_geometry()'s &"ignore_river" flag) so they read as a real
## span over the drop instead of sinking into it. Not cached -- only called
## while placing a bridge's own handful of nodes, never per frame.
func height_without_rivers(p: Vector3) -> float:
	var grid := Vector2(p.x, p.z) / STEP
	var k := Vector2i(floori(grid.x), floori(grid.y))
	var f := grid - Vector2(k)
	var a: float = _natural_height(Vector2(k) * STEP)
	var b: float = _natural_height(Vector2(k + Vector2i(1, 0)) * STEP)
	var c: float = _natural_height(Vector2(k + Vector2i(0, 1)) * STEP)
	var d: float = _natural_height(Vector2(k + Vector2i(1, 1)) * STEP)
	if f.x + f.y <= 1.0:
		return a + (b - a) * f.x + (c - a) * f.y
	return d + (c - d) * (1.0 - f.x) + (b - d) * (1.0 - f.y)


## Worker threads a sliced build may take: all but one. Jolt runs its physics
## jobs on the same WorkerThreadPool and only frees each one once a pool thread
## has run it; a group holding every thread for a second or more runs its fixed
## pool of jobs dry ("Jolt Physics job system exceeded the maximum number of
## jobs") and the physics step then spins on the main thread until the group
## ends (N-917).
static func worker_tasks() -> int:
	var pool: int = OS.get_processor_count()
	var max_threads: int = int(ProjectSettings.get_setting("threading/worker_pool/max_threads", -1))
	if max_threads > 0:
		pool = mini(pool, max_threads)
	return maxi(1, pool - 1)


## Builds the whole terrain now, on the calling thread (tests, tools).
func build() -> void:
	_begin_build()
	for key: Vector2i in _tiles:
		_create_tile(key, _compute_tile(key, _samples))
	_finish_build()


## Same terrain as build(), without holding the main thread: the numbers of
## every tile (heights, normals, paint, triangles) are worked out on the worker
## threads, and what needs the scene -- meshes, bodies, shapes -- is made here
## in slices, one frame at a time (`slicer`, see FrameSlicer). The route's own
## data is only read while the workers run: build() is not to be called, and
## spans / rivers / pads... not to be changed, until this returns.
func build_async(slicer: FrameSlicer) -> void:
	if slicer == null:
		build()
		return
	_begin_build()
	var keys: Array = _tiles.keys()
	_build_keys = keys
	_build_results = []
	_build_results.resize(keys.size())
	if not keys.is_empty():
		# High priority: a low-priority task still pending when the game quits
		# deadlocks the pool (4.7.2, see SynthAudio's warm task).
		var tasks: int = worker_tasks()
		_build_group = WorkerThreadPool.add_group_task(
			_compute_tile_job, keys.size(), tasks, true, "TerrainField.tiles"
		)
		while not WorkerThreadPool.is_group_task_completed(_build_group):
			var done: int = WorkerThreadPool.get_group_processed_element_count(_build_group)
			build_progress = 0.6 * float(done) / float(keys.size())
			await slicer.frame()
		WorkerThreadPool.wait_for_group_task_completion(_build_group)
		_build_group = -1
	for index: int in range(keys.size()):
		var data: Dictionary = _build_results[index]
		_build_results[index] = null
		_samples.merge(data.samples)
		_create_tile(keys[index], data)
		build_progress = 0.6 + 0.35 * float(index + 1) / float(keys.size())
		await slicer.tick()
	_build_keys = []
	_build_results = []
	for river: Dictionary in rivers:
		_build_river_water(river)
		await slicer.tick()
		_decorate_river(river, float(river.get("bank_width", RIVER_BANK_WIDTH)) + RIVER_MAX_DRIFT)
		await slicer.tick()
	build_progress = 1.0


func _begin_build() -> void:
	build_progress = 0.0
	_material = ShaderMaterial.new()
	_material.shader = _terrain_shader()
	_configure_material(_material)


func _finish_build() -> void:
	for river: Dictionary in rivers:
		_build_river_water(river)
		_decorate_river(river, float(river.get("bank_width", RIVER_BANK_WIDTH)) + RIVER_MAX_DRIFT)
	build_progress = 1.0


## One worker's share of build_async(): the tile at `index` of _build_keys,
## into the same slot of _build_results (each worker its own slot, and its own
## sample cache: nothing shared is written).
func _compute_tile_job(index: int) -> void:
	_build_results[index] = _compute_tile(_build_keys[index], {})


## A tile still being worked out by the workers must not outlive the node.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _build_group >= 0:
			WorkerThreadPool.wait_for_group_task_completion(_build_group)
			_build_group = -1
		if _conform_group >= 0:
			WorkerThreadPool.wait_for_group_task_completion(_conform_group)
			_conform_group = -1


## The water over a carved riverbed -- one mesh per river, built once here
## (never per frame). It used to be draped over the carved ground a few
## centimetres up, wherever the carve was even slightly felt: water crept up
## the banks and the ridge, and the ground poked through it between vertices
## (playtest 2026-09-28). Now it's a surface of its own at RIVER_FILL of the
## depth below the ground's natural (ridge-less) level: smooth, gently
## following the land's long swells, and the shoreline is simply where the
## carved ground rises through it -- the terrain hides the water past it.
## Sampled on the terrain's own grid (STEP), so the two agree everywhere.
const RIVER_WATER_STEP: float = STEP
## Metres of water under which the surface fades out at the shore.
const RIVER_WATER_FADE: float = 0.35
const RIVER_WATER_COLOR := Color(0.29, 0.58, 0.74, 0.72)


func _build_river_water(river: Dictionary) -> void:
	var a: Vector2 = river.a
	var edge: Vector2 = river.b - a
	var length: float = maxf(edge.length(), 0.001)
	var dir: Vector2 = edge / length
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var reach: float = float(river.get("bank_width", RIVER_BANK_WIDTH)) + 6.0
	# Out from the road the channel meanders past the span's own ends.
	var overhang: float = RIVER_MAX_DRIFT + RIVER_TAPER
	var along_steps: int = maxi(1, ceili((length + overhang * 2.0) / RIVER_WATER_STEP))
	var side_steps: int = maxi(1, ceili((reach * 2.0) / RIVER_WATER_STEP))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var wet: Dictionary = {}
	var index_of: Dictionary = {}
	for i: int in range(along_steps + 1):
		var s: float = -overhang + float(i) * RIVER_WATER_STEP
		for j: int in range(side_steps + 1):
			var lateral: float = -reach + float(j) * RIVER_WATER_STEP
			var p: Vector2 = a + dir * s + perp * lateral
			var key := Vector2i(i, j)
			var surface: float = _river_water_height(river, p)
			var depth_below: float = surface - height_at(Vector3(p.x, 0.0, p.y))
			wet[key] = depth_below > 0.0
			index_of[key] = vertices.size()
			vertices.append(Vector3(p.x, surface, p.y))
			normals.append(Vector3.UP)
			# Fades in over the first few centimetres of depth, so the edge
			# the ground cuts through reads as a shore, not a hard line.
			colors.append(Color(1.0, 1.0, 1.0, clampf(depth_below / RIVER_WATER_FADE, 0.0, 1.0)))
	for i: int in range(along_steps):
		for j: int in range(side_steps):
			var k00 := Vector2i(i, j)
			var k10 := Vector2i(i + 1, j)
			var k01 := Vector2i(i, j + 1)
			var k11 := Vector2i(i + 1, j + 1)
			# Any wet corner: the dry ones sit under the bank, and the
			# ground's own depth test draws the shoreline between them.
			if wet.get(k00, false) or wet.get(k10, false) or wet.get(k01, false) or wet.get(k11, false):
				indices.append_array(PackedInt32Array([index_of[k00], index_of[k10], index_of[k01], index_of[k10],
						index_of[k11], index_of[k01]]))
	if indices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = RIVER_WATER_COLOR
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# A faint, tight sheen: a broad specular lobe washed the channel milky
	# and a sharp one left a white blot (render_river.gd, 2026-09-28).
	material.roughness = 0.2
	material.metallic = 0.0
	material.metallic_specular = 0.15
	# Back faces culled, same reasoning as _material(): a double-sided plane
	# right above a slope this shallow shadowed its own underside.
	mesh.surface_set_material(0, material)
	var visual := MeshInstance3D.new()
	visual.name = "RiverWater"
	visual.mesh = mesh
	add_child(visual)


## Where a river's water surface sits at `p`: RIVER_FILL of its depth below
## the ground's natural level there, ridge left out.
func _river_water_height(river: Dictionary, p: Vector2) -> float:
	return _natural_height(p, false) - float(river.depth) * RIVER_FILL


## Public alias of _river_water_height() for river decoration (_decorate_river).
func river_water_height(river: Dictionary, p: Vector2) -> float:
	return _river_water_height(river, p)


## Everything about the tile at `key` that only depends on the field's data,
## which is fixed once the build starts: vertices, normals, uv (road mask and
## gravel), vertex colours (the footpaths) and triangles. Safe on a worker
## thread as long as `cache` is the caller's own (it is filled with every
## sample the tile needed, `data.samples`).
func _compute_tile(key: Vector2i, cache: Dictionary) -> Dictionary:
	# The tile's samples plus one ring around it, for the normals.
	var side: int = CELLS + 3
	var grid := PackedVector3Array()
	grid.resize(side * side)
	var origin: Vector2i = key * CELLS
	for z: int in range(-1, CELLS + 2):
		for x: int in range(-1, CELLS + 2):
			if (x < 0 or x > CELLS) and (z < 0 or z > CELLS):
				continue  # Never read: the normals only look along the axes.
			grid[(z + 1) * side + x + 1] = _sample_in(origin + Vector2i(x, z), cache)
	var footpaths: Array[Dictionary] = _footpaths_near(key)
	var count: int = (CELLS + 1) * (CELLS + 1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	vertices.resize(count)
	normals.resize(count)
	uv.resize(count)
	colors.resize(count)
	var at: int = 0
	for z: int in range(CELLS + 1):
		for x: int in range(CELLS + 1):
			var cell: int = (z + 1) * side + x + 1
			var data: Vector3 = grid[cell]
			var p := Vector3(float(origin.x + x) * STEP, data.x, float(origin.y + z) * STEP)
			vertices[at] = p
			uv[at] = Vector2(data.y, data.z)
			var dx: float = grid[cell + 1].x - grid[cell - 1].x
			var dz: float = grid[cell + side].x - grid[cell - side].x
			normals[at] = Vector3(-dx, STEP * 2.0, -dz).normalized()
			var path_weight: float = 0.0
			var point := Vector2(p.x, p.z)
			for path: Dictionary in footpaths:
				var a: Vector2 = path.a
				var edge: Vector2 = path.b - a
				var t: float = clampf((point - a).dot(edge) / maxf(edge.length_squared(), 0.001), 0.0, 1.0)
				path_weight = maxf(path_weight, 1.0 - smoothstep(0.6, 2.1, point.distance_to(a + edge * t)))
			colors[at] = Color(path_weight, 0.0, 0.0)
			at += 1
	var indices := PackedInt32Array()
	for z: int in range(CELLS):
		for x: int in range(CELLS):
			if not tunnels.is_empty() and _in_tunnel_bore(origin + Vector2i(x, z), cache):
				continue
			var a: int = z * (CELLS + 1) + x
			indices.append_array(PackedInt32Array([a, a + 1, a + CELLS + 1, a + 1, a + CELLS + 2, a + CELLS + 1]))
	return {"vertices": vertices, "normals": normals, "uv": uv, "colors": colors, "indices": indices, "samples": cache}


## The footpaths that can colour any vertex of the tile at `key`: the paint
## fades out 2.1 m from a path, so one whose box (plus a margin) misses the
## tile cannot touch it. The other paths would only ever add zero.
func _footpaths_near(key: Vector2i) -> Array[Dictionary]:
	var near: Array[Dictionary] = []
	var low: Vector2 = Vector2(key) * TILE - Vector2.ONE * 2.5
	var high: Vector2 = low + Vector2.ONE * (TILE + 5.0)
	for path: Dictionary in paths:
		var a: Vector2 = path.a
		var b: Vector2 = path.b
		if maxf(a.x, b.x) < low.x or minf(a.x, b.x) > high.x or maxf(a.y, b.y) < low.y or minf(a.y, b.y) > high.y:
			continue
		near.append(path)
	return near


## The meshes, body and shapes of a tile whose numbers _compute_tile() made.
## Scene objects: the main thread only.
func _create_tile(key: Vector2i, data: Dictionary) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.vertices
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_TEX_UV] = data.uv
	arrays[Mesh.ARRAY_COLOR] = data.colors
	arrays[Mesh.ARRAY_INDEX] = data.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var body := StaticBody3D.new()
	body.name = "Terrain_%d_%d" % [key.x, key.y]
	body.collision_layer = 1
	body.collision_mask = 6
	add_child(body)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material
	body.add_child(visual)
	var collider := CollisionShape3D.new()
	collider.shape = mesh.create_trimesh_shape()
	body.add_child(collider)
	# Close only exterior tile edges; internal joins have no walls or seams.
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if _tiles.has(key + direction):
			continue
		var wall := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.5, 80.0, TILE) if direction.x != 0 else Vector3(TILE, 80.0, 0.5)
		wall.shape = box
		wall.position = Vector3((float(key.x) + 0.5) * TILE + float(direction.x) * TILE * 0.5, 15.0, (float(key.y) + 0.5) * TILE + float(direction.y) * TILE * 0.5)
		body.add_child(wall)


## Warp authored road furniture (including its collision) onto the height field.
## Imported props/houses instead move as rigid objects in route.gd.
## `ignore_rivers` sticks once set (a node flagged &"ignore_river", or any
## ancestor already carrying the flag down the recursion) so a whole bridge
## -- deck, rails, posts and its authored water/bank model alike -- measures
## itself against the ground as if no river had carved under it, and floats
## over the drop instead of sinking into it with everything else.
##
## With a `slicer` (see FrameSlicer) the work is cut into slices, a frame apart
## each: `await` it. Without one it runs to the end before returning.
func conform_geometry(node: Node, ignore_rivers: bool = false, slicer: FrameSlicer = null) -> void:
	ignore_rivers = ignore_rivers or (node is Node3D and (node as Node3D).has_meta(&"ignore_river"))
	if node is MeshInstance3D and node.mesh != null:
		if slicer != null:
			await slicer.tick()
		var job: Dictionary = _conform_prepare(node, ignore_rivers)
		_conform_warp(job, _samples, false)
		_conform_apply(job)
		return
	if _conform_ride(node, ignore_rivers):
		return
	for child: Node in node.get_children():
		await conform_geometry(child, ignore_rivers, slicer)


## conform_geometry() over every node of `roots` (in this order), the warping
## of the vertices -- nearly all of its cost -- on the worker threads, and what
## touches the scene (reading the meshes, building the new ones) here in slices
## a frame apart each (`slicer`, see FrameSlicer): `await` it. The meshes come
## out the same as conform_geometry() makes them. The field is only read while
## the workers run (nothing should change it meanwhile, nor ask it for heights
## from another thread).
func conform_all(roots: Array[Node], slicer: FrameSlicer) -> void:
	if slicer == null:
		for root: Node in roots:
			conform_geometry(root)
		return
	conform_progress = 0.0
	var jobs: Array = []
	for index: int in range(roots.size()):
		await _conform_collect(roots[index], false, jobs, slicer)
		conform_progress = 0.2 * float(index + 1) / float(roots.size())
	_conform_jobs = jobs
	if not jobs.is_empty():
		_workers_reading = true
		var tasks: int = worker_tasks()
		_conform_group = WorkerThreadPool.add_group_task(
			_conform_task, jobs.size(), tasks, true, "TerrainField.conform"
		)
		while not WorkerThreadPool.is_group_task_completed(_conform_group):
			var done: int = WorkerThreadPool.get_group_processed_element_count(_conform_group)
			conform_progress = 0.2 + 0.6 * float(done) / float(jobs.size())
			await slicer.frame()
		WorkerThreadPool.wait_for_group_task_completion(_conform_group)
		_conform_group = -1
		_workers_reading = false
	for index: int in range(jobs.size()):
		_conform_apply(jobs[index])
		jobs[index] = null
		conform_progress = 0.8 + 0.2 * float(index + 1) / float(jobs.size())
		await slicer.tick()
	_conform_jobs = []
	conform_progress = 1.0


## The meshes under `node` that conform_geometry() would warp, as jobs in its
## order; whatever else it moves (the rigid parts) moves right here.
func _conform_collect(node: Node, ignore_rivers: bool, jobs: Array, slicer: FrameSlicer) -> void:
	ignore_rivers = ignore_rivers or (node is Node3D and (node as Node3D).has_meta(&"ignore_river"))
	if node is MeshInstance3D and node.mesh != null:
		await slicer.tick()
		jobs.append(_conform_prepare(node, ignore_rivers))
		return
	if _conform_ride(node, ignore_rivers):
		return
	for child: Node in node.get_children():
		await _conform_collect(child, ignore_rivers, jobs, slicer)


## One worker's share of conform_all(): the job at `index` of _conform_jobs.
func _conform_task(index: int) -> void:
	_conform_warp(_conform_jobs[index], {}, true)


## Parts that move later (a barrier arm, a train car) ride the terrain as
## rigid pieces: warping their vertices would bend them out of shape. So
## does anything flagged &"rigid" (a tunnel portal and the track into it:
## the hill behind would lift the back of them). Moves `node` and says true
## when it is one of those (or an Area3D, a Label3D), false for anything else.
func _conform_ride(node: Node, ignore_rivers: bool) -> bool:
	var rigid: bool = node is Node3D and (node.has_meta(&"animated") or node.has_meta(&"rigid"))
	if node is Area3D or node is Label3D or rigid:
		var p: Vector3 = to_local(node.global_position)
		node.global_position.y += height_without_rivers(p) if ignore_rivers else height_at(p)
		return true
	return false


## What warping `node`'s mesh takes, read from the scene: the source mesh (a
## box is subdivided so it can follow the ground), each surface's arrays, and
## the four transforms between the node's space and the terrain's, once:
## to_local(node.to_global(v)) works both out again for every vertex.
func _conform_prepare(node: MeshInstance3D, ignore_rivers: bool) -> Dictionary:
	var source: Mesh = node.mesh
	if source is BoxMesh:
		source = source.duplicate()
		source.subdivide_width = maxi(0, ceili(source.size.x / STEP) - 1)
		source.subdivide_depth = maxi(0, ceili(source.size.z / STEP) - 1)
	var surfaces: Array = []
	for index: int in range(source.get_surface_count()):
		var surface := SurfaceTool.new()
		surface.create_from(source, index)
		surfaces.append(surface.commit_to_arrays())
	var node_global: Transform3D = node.global_transform
	return {"node": node, "source": source, "surfaces": surfaces, "ignore_rivers": ignore_rivers,
		"node_global": node_global, "node_inverse": node_global.affine_inverse()}


## Moves the vertices of the job's surfaces onto the ground. Reads the scene's
## data only through the job. `cache` takes the samples it has to work out;
## `shared_read` says _samples may be read but never written to (a worker).
func _conform_warp(job: Dictionary, cache: Dictionary, shared_read: bool) -> void:
	var node_global: Transform3D = job.node_global
	var node_inverse: Transform3D = job.node_inverse
	var terrain_global: Transform3D = global_transform
	var terrain_inverse: Transform3D = terrain_global.affine_inverse()
	var ignore_rivers: bool = job.ignore_rivers
	for arrays: Array in job.surfaces:
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i: int in range(vertices.size()):
			var p: Vector3 = terrain_inverse * (node_global * vertices[i])
			if ignore_rivers:
				p.y += height_without_rivers(p)
			elif shared_read:
				p.y += _height_reading(p, cache)
			else:
				p.y += height_at(p)
			vertices[i] = node_inverse * (terrain_global * p)
		# Keep the source's own normals. Regenerating them here merged every
		# vertex that shares a position, so a box's corners got averaged and
		# barriers, cones and rails shaded like soft pillows. The ground under
		# them is gentle enough that unwarped normals light them correctly.
		arrays[Mesh.ARRAY_VERTEX] = vertices


## Gives `job`'s node its warped mesh and its collision shapes. Every surface
## with its own material: rebuilt from the first surface alone and without
## materials, an imported model (the road barrier: white board, red stripes,
## orange legs) came out in the default grey -- "no textures" (playtest 2026-09-25).
func _conform_apply(job: Dictionary) -> void:
	var node: MeshInstance3D = job.node
	var source: Mesh = job.source
	var mesh := ArrayMesh.new()
	var surfaces: Array = job.surfaces
	for index: int in range(surfaces.size()):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[index])
		mesh.surface_set_material(index, source.surface_get_material(index))
	node.mesh = mesh
	var parent: Node = node.get_parent()
	if parent is StaticBody3D:
		for child: Node in parent.get_children():
			if child is CollisionShape3D:
				child.shape = mesh.create_trimesh_shape()
				child.transform = node.transform


# --- Hooks the game fills in ---------------------------------------------------

## A plain built-in shader: the vertex colour's red channel blends road
## grey over ground green. The game's shader reads the same vertex data.
static var _default_shader: Shader


func _terrain_shader() -> Shader:
	if _default_shader == null:
		_default_shader = Shader.new()
		_default_shader.code = ("shader_type spatial;\nrender_mode cull_back;\n"
			+ "uniform float wetness = 0.0;\nuniform float autumn = 0.0;\nuniform float night_road = 0.0;\n"
			+ "void fragment() { ALBEDO = mix(vec3(0.36, 0.46, 0.26), vec3(0.24, 0.26, 0.28), COLOR.r); }")
	return _default_shader


## The material every tile shares, before the tiles are built: textures and
## parameters the game's shader wants.
func _configure_material(_material_: ShaderMaterial) -> void:
	pass


## A river's water was built: what stands at its ends (a waterfall) goes
## here. `reach` is how far from the road its banks run.
func _decorate_river(_river: Dictionary, _reach: float) -> void:
	pass

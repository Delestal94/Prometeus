extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_town_terrain.gd
## town_terrain.gd: indexed city platforms match exhaustive heights at tile
## boundaries/negative coordinates; filling the envelope preserves an irregular
## outline and covers the gap between separated districts without fake roads.
## Port's seeded bay/approach avoid all parcels, parks and streets; Sierra
## retains natural relief while its rotated road/lot platforms stay level.
## Urban ground also undulates asymmetrically between reserved platforms,
## with continuous heights across irregular district boundaries.

const TERRAIN := preload("res://scripts/gameplay/town/town_terrain.gd")
const BIOMES := preload("res://scripts/gameplay/town/town_biomes.gd")
const PLAN := preload("res://modules/town_gen/town_plan.gd")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var reference: TERRAIN = TERRAIN.new()
	var indexed: TERRAIN = TERRAIN.new()
	for i: int in range(50):
		reference.platforms.append(
			{
				"centre": Vector2(-100 + i * 9, -85 + i * 3),
				"along": Vector2.from_angle(i * .31),
				"half": Vector2(6 + i % 7, 15),
				"height": float(i % 5 - 2)
			}
		)
	indexed.platforms = reference.platforms.duplicate(true)
	indexed.index_profile()
	for x: int in range(-144, 400, 16):
		for z: int in range(-128, 160, 16):
			for offset: Vector2 in [Vector2.ZERO, Vector2(-.01, .01), Vector2(.01, -.01)]:
				var at: Vector2 = Vector2(x, z) + offset
				var road := Vector3(45, 0, 6)
				var expected: float = reference._natural_height_from(at, road)
				var actual: float = indexed._natural_height_from(at, road)
				_expect(
					absf(expected - actual) < .000001,
					"Indexed city heights preserve rotated/blended platforms (at %s)" % at
				)
	indexed.city_outlines = [
		PackedVector2Array([Vector2(-130, -80), Vector2(-60, -80), Vector2(-80, 20)]),
		PackedVector2Array([Vector2(110, 80), Vector2(180, 60), Vector2(180, 130)])
	]
	indexed.complete_surface()
	_expect(indexed._tiles.has(Vector2i(0, 0)), "The space between districts has a terrain tile")
	_expect(
		not indexed._tiles.has(Vector2i(100, 100)), "Coverage remains bounded by the city envelope"
	)
	_expect(indexed.spans.is_empty(), "Coverage adds no phantom streets to terrain placement")
	reference.free()
	indexed.free()
	_test_biomes()
	if _failures == 0:
		print(
			"PASS: city platform index preserves heights and fills the irregular district envelope"
		)
	quit(_failures)


func _test_biomes() -> void:
	var seeds: Array[int] = [4242, 90210]
	for seed_value: int in range(18):
		seeds.append(seed_value)
	for seed_value: int in seeds:
		var plan: Dictionary = PLAN.generate(seed_value)
		var original: Dictionary = plan.duplicate(true)
		var terrain: TERRAIN = TERRAIN.new()
		BIOMES.configure(terrain, plan, PackedInt32Array([0, 1, 2, 3, 4, 5]))
		var coast: Dictionary = terrain.coast
		_expect(plan == original, "Biomes preserve the seeded plan (seed %d)" % seed_value)
		_expect(
			coast.access.size() >= 2, "Port has a reachable dock approach (seed %d)" % seed_value
		)
		for node: Vector2 in plan.nodes:
			var gap: float = (node - (coast.shore as Vector2)).dot(coast.direction)
			_expect(gap <= -40, "The bay stays beyond every road (gap %s)" % gap)
		for lot: Dictionary in plan.lots:
			var gap: float = (lot.position - (coast.shore as Vector2)).dot(coast.direction)
			_expect(gap < -40, "The bay stays beyond every parcel (gap %s)" % gap)
			for i: int in range(1, coast.access.size()):
				var a: Vector2 = (coast.access[i - 1] - lot.position).rotated(-lot.angle)
				var b: Vector2 = (coast.access[i] - lot.position).rotated(-lot.angle)
				var rect := Rect2(-lot.size * .5, lot.size).grow(1.5)
				var corners := PackedVector2Array(
					[
						rect.position,
						Vector2(rect.end.x, rect.position.y),
						rect.end,
						Vector2(rect.position.x, rect.end.y)
					]
				)
				var mid: Vector2 = (a + b) * .5
				_expect(
					not Geometry2D.is_point_in_polygon(mid, corners),
					"The dock approach avoids parcel footprints (seed %d)" % seed_value
				)
		var submerged: Vector2 = coast.shore + coast.direction * 40
		var clipped: PackedVector2Array = BIOMES._wet_polygon(
			terrain,
			PackedVector2Array(
				[coast.shore, submerged, submerged + (coast.direction as Vector2).orthogonal() * 2]
			)
		)
		_expect(clipped.size() == 4, "Crossing water triangles are clipped at the shore")
		for point: Vector2 in clipped:
			_expect(
				terrain.height_at(Vector3(point.x, 0, point.y)) < BIOMES.WATER_LEVEL,
				"Clipped water vertices stay over submerged ground"
			)
		_expect(
			terrain.river_depth_at(submerged) > 2, "The dresser rejects submerged harbour ground"
		)
		_expect(
			terrain.river_depth_at(coast.shore - coast.direction * 40) == 0,
			"Dry harbour approach remains available for scenery"
		)
		terrain.free()
	var mountain: TERRAIN = TERRAIN.new()
	var outline := PackedVector2Array()
	for i: int in range(7):
		outline.append(Vector2.from_angle(TAU * i / 7) * 100)
	mountain.city_outlines = [outline]
	mountain.mountain_outline = outline
	mountain.platforms.append(
		{
			"centre": Vector2.ZERO,
			"along": Vector2.from_angle(.7),
			"half": Vector2(10, 70),
			"height": 0.0
		}
	)
	mountain.index_profile()
	_expect(
		mountain._natural_height_from(Vector2(50, -40), Vector3(60, 0, 6)) > 4,
		"Sierra has real hills between its level parcels"
	)
	_expect(
		mountain._natural_height_from(Vector2.ZERO, Vector3(60, 0, 6)) == 0,
		"Sierra road and parcel platforms remain exactly level"
	)
	mountain.free()
	var urban: TERRAIN = TERRAIN.new()
	urban.city_outlines = [outline]
	var positive: float = urban._natural_height_from(Vector2(50, -40), Vector3(60, 0, 6))
	var opposite: float = urban._natural_height_from(Vector2(-50, 40), Vector3(60, 0, 6))
	_expect(
		absf(positive) > .1 and absf(positive - opposite) > .1,
		(
			"Urban relief is neither a flat plane nor a mirrored hill (got %s/%s)"
			% [positive, opposite]
		)
	)
	var edge: Vector2 = (outline[0] + outline[1]) * .5
	var outward: Vector2 = edge.normalized()
	var before: float = urban._natural_height_from(edge - outward * .01, Vector3(60, 0, 6))
	var after: float = urban._natural_height_from(edge + outward * .01, Vector3(60, 0, 6))
	_expect(absf(before - after) < .02, "Natural urban relief has no height step at its boundary")
	urban.free()
	var old: TERRAIN = TERRAIN.new()
	BIOMES.configure(old, PLAN.generate(4242), PackedInt32Array([0, 1]))
	_expect(
		old.coast.is_empty() and old.mountain_outline.is_empty(),
		"The existing two-district scene retains its terrain profile"
	)
	old.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

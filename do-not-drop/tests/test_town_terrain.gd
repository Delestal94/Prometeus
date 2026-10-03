extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_town_terrain.gd
## town_terrain.gd: indexed city platforms match exhaustive heights at tile
## boundaries/negative coordinates; filling the envelope preserves an irregular
## outline and covers the gap between separated districts without fake roads.

const TERRAIN := preload("res://scripts/gameplay/town/town_terrain.gd")
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
	if _failures == 0:
		print(
			"PASS: city platform index preserves heights and fills the irregular district envelope"
		)
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

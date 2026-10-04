extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/route_gen/tests/test_terrain_platforms.gd
## terrain_field.gd: spatial platform candidates preserve exhaustive height and
## overlapping-platform order, including rotated footprints and blend regions.
## Default selection remains exhaustive; runs without game scenes/autoloads.


class FilteredTerrain:
	extends TerrainField

	func _platform_candidates(p: Vector2) -> Array[Dictionary]:
		var selected: Array[Dictionary] = []
		for platform: Dictionary in platforms:
			if p.distance_to(platform.centre) <= platform.half.length() + PLATFORM_BLEND:
				selected.append(platform)
		return selected


var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var reference := TerrainField.new()
	var filtered := FilteredTerrain.new()
	for i: int in range(6):
		reference.platforms.append(
			{
				"centre": Vector2(-25 + i * 10, -16 + i * 7),
				"along": Vector2.from_angle(i * .47),
				"half": Vector2(8, 15),
				"height": float(i - 2)
			}
		)
	reference.platforms.append(
		{
			"centre": Vector2(1500, 1500),
			"along": Vector2.RIGHT,
			"half": Vector2(8, 10),
			"height": 30.0
		}
	)
	filtered.platforms = reference.platforms.duplicate(true)
	for x: int in range(-70, 90, 3):
		for z: int in range(-70, 90, 3):
			var at := Vector2(x, z)
			var road := Vector3(45, 0, 6)
			var expected: float = reference._natural_height_from(at, road)
			var actual: float = filtered._natural_height_from(at, road)
			_expect(
				absf(expected - actual) < .000001,
				(
					"Filtered platform heights match exhaustive sampling (at %s got %.8f expected %.8f)"
					% [at, actual, expected]
				)
			)
	_expect(
		filtered._platform_candidates(Vector2.ZERO).size() < reference.platforms.size(),
		"The candidate hook excludes remote platforms without changing local height"
	)
	reference.free()
	filtered.free()
	if _failures == 0:
		print("PASS: exhaustive and filtered rotated/overlapping platform heights are equivalent")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_river_water.gd
##
## A narrow bridge's river (route_terrain.gd, playtest 2026-09-28): the water
## is a surface of its own, not a sheet draped over the carved ground -- deep
## enough mid-channel that no ground pokes through, gone where the ridge
## lifts the land (no water climbing a slope), and the road reaches the
## bridge's ends on whole ground (no step, no wedges).

const RouteTerrain = preload("res://scripts/gameplay/route/route_terrain.gd")

var _failures: int = 0


func _initialize() -> void:
	var terrain: Node3D = RouteTerrain.new()
	root.add_child(terrain)
	# A straight road along +z, a 36 m bridge in its middle.
	terrain.add_span(Vector3(0, 0, -80), Vector3(0, 0, 80))
	var river: Dictionary = {"a": Vector2(0, -18), "b": Vector2(0, 18), "depth": 1.8, "full_width": 18.0,
		"bank_width": 60.0}
	terrain.rivers.append(river)
	terrain.build()
	var water := terrain.get_node_or_null("RiverWater") as MeshInstance3D
	_expect(water != null, "The river gets its water mesh")
	# Mid-channel, beside the bridge: water well above the bed.
	var mid := Vector2(10.0, 0.0)
	var surface: float = terrain.call(&"_river_water_height", river, mid)
	var bed: float = terrain.height_at(Vector3(mid.x, 0.0, mid.y))
	_expect(surface - bed > 0.5, "Mid-channel the water stands clear of the bed (%.2f m)" % (surface - bed))
	# Up at the ridge the land rises out of the water: no water on the slope.
	var slope := Vector2(55.0, 0.0)
	_expect(terrain.call(&"_river_water_height", river, slope) < terrain.height_at(Vector3(slope.x, 0.0, slope.y)),
		"Where the ridge lifts the ground, the water has ended")
	# The bridge's ends sit on whole ground: nothing carved under their first metres.
	for end_z: float in [-17.0, 17.0]:
		var at := Vector2(4.0, end_z)
		_expect(is_zero_approx(terrain.river_depth_at(at)), "No drop right at the bridge's end (z=%.0f)" % end_z)
	# Under the deck the bed is riverbed, not road: no asphalt under water.
	var under_deck: Vector3 = terrain.call(&"_sample", Vector2i(0, 0))
	_expect(under_deck.y >= 9.9, "The riverbed under the deck isn't painted as road (mask %.1f)" % under_deck.y)
	# The water mesh shares the terrain's grid, so the ground can't poke
	# through between its vertices.
	_expect(is_equal_approx(RouteTerrain.RIVER_WATER_STEP, RouteTerrain.STEP), "Water and ground share one grid")
	terrain.free()
	if _failures == 0:
		print("PASS: river water is its own surface, ends where the land rises, and the bridge meets whole ground")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

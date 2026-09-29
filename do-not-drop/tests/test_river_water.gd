extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_river_water.gd
##
## A narrow bridge's river (route_terrain.gd, playtest 2026-09-28): the water
## is a surface of its own, not a sheet draped over the carved ground -- deep
## enough mid-channel that no ground pokes through, gone where the ridge
## lifts the land (no water climbing a slope), and the road reaches the
## bridge's ends on whole ground (no step, no wedges).

const RouteTerrain = preload("res://scripts/gameplay/route/route_terrain.gd")
const RiverFalls = preload("res://scripts/gameplay/route/route_river_falls.gd")

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
	_check_falls(terrain, river)
	terrain.free()
	if _failures == 0:
		print("PASS: river water is its own surface, ends where the land rises, the bridge meets whole ground,"
			+ " and a rocky waterfall feeds each end")


## Both ends of the water get a waterfall (route_river_falls.gd): its sheet
## lands in the water and drops from well above it, with rocks around it --
## and the same river always builds the same falls (no RNG: every peer agrees).
func _check_falls(terrain: Node3D, river: Dictionary) -> void:
	var falls := terrain.get_node_or_null("RiverFalls") as Node3D
	_expect(falls != null, "The river gets its waterfalls")
	if falls == null:
		return
	var sheets: Array[Node] = falls.find_children("FallSheet*", "MeshInstance3D", false, false)
	_expect(sheets.size() == 2, "One waterfall at each end of the water (%d)" % sheets.size())
	_expect(falls.find_children("FallFoam*", "MeshInstance3D", false, false).size() == 2, "Foam where each one lands")
	# Polish pass (2026-09-29): a veil of white threads in front of each
	# sheet, and spray drifting up where it lands.
	_expect(falls.find_children("FallVeil*", "MeshInstance3D", false, false).size() == 2,
		"A veil in front of each sheet")
	var mists: Array[Node] = falls.find_children("FallMist*", "CPUParticles3D", false, false)
	_expect(mists.size() == 2 and (mists[0] as CPUParticles3D).emitting, "Spray rises where each one lands")
	var rocks: int = falls.find_children("FallRock*", "Node3D", false, false).size()
	_expect(rocks >= 20, "Rocks frame the falls and line the shore (%d)" % rocks)
	var reach: float = 60.0 + RouteTerrain.RIVER_MAX_DRIFT
	for side: float in [-1.0, 1.0]:
		var end: Dictionary = RiverFalls.find_end(terrain, river, side, reach)
		_expect(not end.is_empty() and float(end.reach) > 30.0, "The water runs well out on side %+.0f" % side)
	for sheet: Node in sheets:
		var vertices: PackedVector3Array = (sheet as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		# Centreline points (the middle column of each row): the water's level
		# follows the land's swells, so the sheet's edges sit over slightly
		# different water.
		var middle: int = RiverFalls.SHEET_COLUMNS / 2
		var top: Vector3 = vertices[middle]
		var foot: Vector3 = vertices[vertices.size() - 1 - middle]
		var foot_2d := Vector2(foot.x, foot.z)
		var water: float = terrain.call(&"_river_water_height", river, foot_2d)
		_expect(water - terrain.height_at(foot) > 0.0, "The fall lands in the water, not on the bank")
		_expect(top.y - water >= RiverFalls.MIN_DROP - 0.01,
			"The fall drops from above the water (%.2f m)" % (top.y - water))
	# Built again from scratch, the same river puts every rock in the same spot.
	var again: Node3D = RouteTerrain.new()
	root.add_child(again)
	again.add_span(Vector3(0, 0, -80), Vector3(0, 0, 80))
	again.rivers.append(river.duplicate())
	again.build()
	var first: Array[Node] = falls.get_children()
	var second: Array[Node] = again.get_node("RiverFalls").get_children()
	var same: bool = first.size() == second.size()
	for i: int in mini(first.size(), second.size()):
		same = same and (first[i] as Node3D).transform.is_equal_approx((second[i] as Node3D).transform)
	_expect(same, "The falls are built the same every time")
	again.free()
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

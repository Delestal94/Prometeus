extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_depot_zones.gd
##
## The depot's zones, lanes and air (N-319, docs/deposito-rediseno.md):
##   - the game didn't move: eight spawns, the truck's bay and the order board
##     that faces them, every station where its place is (the supplies window
##     on the cage, the orders at the board);
##   - the walkways are walkable: nothing stands in the middle of the green
##     paint, and the forklift's lane doesn't run through the supplies cage;
##   - the office is on a mezzanine you can climb: the stair's slope holds a
##     body up, the terrace is at the deck's height, the dispatcher works there;
##   - the air: under the roof the level's fog is next to nothing and the
##     ambient is lower, outside and after the depot leaves the tree they are
##     the level's own again;
##   - the lights: a handful of real ones, the three big spots ranked for
##     shadows, and WorldQuality keeping as many as the level allows (none on Low);
##   - the signs hang smaller over their zones; everything static is batched.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")
const Labels = preload("res://scripts/gameplay/depot/depot_labels.gd")
## Most real lights the depot may hang itself (the forklift's beacon and the
## mirror's lamp are on top): the GL Compatibility renderer caps them per mesh.
const MAX_DEPOT_LIGHTS: int = 7
## Most separate meshes the depot's root may carry: the static geometry goes
## through DepotKit, one batch per material (154 before N-319, 185 with the
## zones). A node per box would be thousands.
const MAX_ROOT_MESHES: int = 220

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	await physics_frame
	var depot: Node3D = level.get_node(^"World/Depot")
	_test_game_unchanged(depot)
	_test_walkways(depot)
	_test_mezzanine(depot)
	_test_lights(depot)
	_test_signs()
	_test_batching(depot)
	await _test_air(level, depot)
	level.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: the depot's zones hold the game in place, the lanes are clear, the office is up its stair, ",
				"the air and the lights are as planned")
	quit(_failures)


## Spawns, bay, stations and the board: what the redesign must not break.
func _test_game_unchanged(depot: Node3D) -> void:
	_expect(Layout.SPAWN_POINTS.size() == 8, "Eight spawn points (%d)" % Layout.SPAWN_POINTS.size())
	_expect(Layout.TRUCK_BAY == Vector3(0.0, 0.9, 7.5), "The truck's bay is where it was (%s)" % Layout.TRUCK_BAY)
	_expect(is_equal_approx(Layout.TRUCK_CLEAR_Z, -6.5),
			"The door's clearance is where it was (%.1f)" % Layout.TRUCK_CLEAR_Z)
	for station: StringName in [&"orders", &"garage", &"wardrobe", &"shop", &"records"]:
		_expect(depot.get_node_or_null(NodePath("Station_%s" % station)) != null, "The %s station exists" % station)
	# The orders read from the spawn: the board looks at the crew, close enough.
	var spawn := Vector3.ZERO
	for point: Vector3 in Layout.SPAWN_POINTS:
		spawn += Vector3(point.x, 0.0, point.z) / Layout.SPAWN_POINTS.size()
	var to_crew: Vector3 = (spawn - Layout.BOARD_AT).normalized()
	var facing: float = (Layout.board_basis() * Vector3.BACK).dot(to_crew)
	_expect(facing > 0.85, "The order board faces the spawn (%.2f)" % facing)
	_expect(spawn.distance_to(Layout.BOARD_AT) < 10.0,
			"The order board is near the spawn (%.1f m)" % spawn.distance_to(Layout.BOARD_AT))
	var bearing: float = rad_to_deg(Vector3.FORWARD.angle_to(Layout.BOARD_AT - spawn))
	_expect(bearing < 57.0,
			"The board is inside the game's 82 degree view from the spawn (%.0f degrees off centre)" % bearing)
	# The stations stand at their places.
	var orders := depot.get_node(^"Station_orders") as Node3D
	_expect(orders.position.distance_to(Layout.BOARD_AT + Vector3.UP * 1.6) < 1.0,
			"The orders station is at the board (%s)" % orders.position)
	var shop := (depot.get_node(^"Station_shop") as Node3D).position
	var cage: Rect2 = Layout.SHOP_CAGE
	_expect(shop.x > cage.end.x and shop.x < cage.end.x + 1.0 and shop.z > 4.3 and shop.z < 6.5,
			"The shop station is at the cage's service window (%s)" % shop)
	_expect((depot.get_node(^"Station_wardrobe") as Node3D).position == Layout.WARDROBE_STATION,
			"The wardrobe station is at the lockers")
	# The forklift's lane leaves the supplies cage alone.
	_expect(Layout.FORKLIFT_LANE_Z.x > cage.end.y,
			"The forklift's lane starts past the supplies cage (%.1f vs %.1f)" % [Layout.FORKLIFT_LANE_Z.x, cage.end.y])
	var forklift := depot.get_node(^"Forklift") as Node3D
	var in_lane: bool = absf(forklift.position.x - Layout.FORKLIFT_LANE_X) < 0.01
	_expect(in_lane and forklift.position.z > Layout.FORKLIFT_LANE_Z.x,
			"The forklift works inside its lane (%s)" % forklift.position)
	var clerk := depot.get_node(^"Clerk") as Node3D
	_expect(clerk.position.distance_to(Vector3(shop.x, clerk.position.y, shop.z)) < 3.5,
			"The clerk stands behind the cage's window (%s)" % clerk.position)


## Nothing stands in the middle of the green paint.
func _test_walkways(depot: Node3D) -> void:
	var space: PhysicsDirectSpaceState3D = depot.get_world_3d().direct_space_state
	var samples: Array[Vector3] = []
	for z: float in [15.6, 17.0, 18.6, 20.2, 21.8, 23.4]:
		samples.append(Vector3(-8.5, 0.0, z))  # the aisle between the shelves
	for x: float in [-7.0, -5.5, -4.0, 4.0, 5.5, 7.0]:
		samples.append(Vector3(x, 0.0, Layout.SPINE_Z))  # the spine
	for z: float in [5.0, 7.0, 9.0, 11.0, 13.0]:
		samples.append(Vector3(-8.5, 0.0, z))  # to the supplies window
	for z: float in [9.0, 11.0, 13.0, 16.0, 18.0]:
		samples.append(Vector3(8.5, 0.0, z))  # up the east side to the stair
	for x: float in [-6.0, -3.0, 0.0, 2.0]:
		samples.append(Vector3(x, 0.0, 25.2))  # along the back
	for at: Vector3 in samples:
		var from: Vector3 = depot.to_global(at + Vector3.UP * 3.0)
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0,
				1))
		var height: float = depot.to_local(hit.position).y if not hit.is_empty() else -1.0
		_expect(not hit.is_empty() and height < Layout.FLOOR_TOP + 0.05,
				"The walkway is clear at %s (something %.2f m high)" % [at, height])


## The deck, its stair and the office on it.
func _test_mezzanine(depot: Node3D) -> void:
	var space: PhysicsDirectSpaceState3D = depot.get_world_3d().direct_space_state
	var top: float = Layout.MEZZANINE_HEIGHT
	var run_start: float = Layout.MEZZANINE.position.y - Layout.STAIR_RUN
	# The stair holds a body up all along its slope.
	for fraction: float in [0.15, 0.5, 0.85]:
		var z: float = run_start + Layout.STAIR_RUN * fraction
		var expected: float = top * fraction
		var from: Vector3 = depot.to_global(Vector3(Layout.STAIR_X, 5.0, z))
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0,
				1))
		var height: float = depot.to_local(hit.position).y if not hit.is_empty() else -1.0
		_expect(absf(height - expected) < 0.25,
				"The stair's slope is under a foot at %.0f%% (%.2f m, wanted %.2f)" % [fraction * 100.0, height,
						expected])
	# The terrace in front of the office is at the deck's height.
	var terrace: Vector3 = depot.to_global(Vector3(11.0, 5.0, 26.2))
	var deck: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(terrace, terrace + Vector3.DOWN * 6.0,
			1))
	var deck_height: float = depot.to_local(deck.position).y if not deck.is_empty() else -1.0
	_expect(absf(deck_height - top) < 0.05, "The terrace stands at the deck's height (%.2f)" % deck_height)
	# Its open edge is fenced: a ray along the deck at chest height hits the railing.
	var rail_from: Vector3 = depot.to_global(Vector3(12.0, top + 0.6, 26.0))
	var rail: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(rail_from,
			rail_from + Vector3.FORWARD * 3.0, 1))
	_expect(not rail.is_empty(), "The deck's front edge has a railing")
	var dispatcher := depot.get_node(^"Dispatcher") as Node3D
	_expect(absf(dispatcher.position.y - (Layout.FLOOR_TOP + top)) < 0.01,
			"The dispatcher works up in the office (y %.2f)" % dispatcher.position.y)


## A handful of real lights, ranked for shadows, and the quality levels' budget.
func _test_lights(depot: Node3D) -> void:
	var lights: Array[Light3D] = []
	for child: Node in depot.get_children():
		if child is OmniLight3D or child is SpotLight3D:
			lights.append(child as Light3D)
	_expect(lights.size() <= MAX_DEPOT_LIGHTS and lights.size() >= 5,
			"The depot hangs a handful of real lights (%d)" % lights.size())
	var ranked: Array[Light3D] = lights.filter(
			func(light: Light3D) -> bool: return light.has_meta(WorldQuality.SHADOW_RANK_META))
	_expect(ranked.size() == 3, "Three big spots are ranked for shadows (%d)" % ranked.size())
	var previous: int = WorldQuality.level
	for level: int in [WorldQuality.Level.LOW, WorldQuality.Level.MEDIUM, WorldQuality.Level.HIGH]:
		WorldQuality.apply(self, level)
		var casting: int = ranked.filter(func(light: Light3D) -> bool: return light.shadow_enabled).size()
		var allowed: int = mini(int(WorldQuality.PRESETS[level]["shadowed_lights"]), ranked.size())
		_expect(casting == allowed, "%s lets %d lamps cast a shadow (%d do)" % [WorldQuality.NAMES[level], allowed,
				casting])
	_expect(int(WorldQuality.PRESETS[WorldQuality.Level.LOW]["shadowed_lights"]) == 0, "Low has no lamp shadows")
	WorldQuality.apply(self, previous)


## Zone signs hang smaller than the old ones (a fraction of SIGN_PIXEL).
func _test_signs() -> void:
	var pixel_sizes: Dictionary = {}
	for label: Node in get_nodes_in_group(&"depot_sign"):
		var caption: String = String(label.get_meta(&"sign"))
		pixel_sizes[caption] = (label as Label3D).pixel_size
	for caption: String in ["PIZARRA", "TALLER", "SUMINISTROS", "VESTUARIO", "OFICINA"]:
		var found: bool = false
		for key: String in pixel_sizes:
			if key.contains(caption):
				found = true
				_expect(float(pixel_sizes[key]) < Labels.SIGN_PIXEL - 0.0001,
						"The %s sign hangs smaller than the old ones (%.4f)" % [caption, float(pixel_sizes[key])])
		_expect(found, "A hanging sign names %s" % caption)


## Everything static goes through DepotKit: a few dozen batches, not a node per box.
func _test_batching(depot: Node3D) -> void:
	var meshes: int = 0
	for child: Node in depot.get_children():
		if child is MeshInstance3D:
			meshes += 1
	_expect(meshes <= MAX_ROOT_MESHES, "The depot's root carries its batches, not a mesh per box (%d)" % meshes)


## The air under the roof: no haze, a lower ambient; outside and once the depot
## is gone, the level's own.
func _test_air(level: Node, depot: Node3D) -> void:
	var environment: Environment = (level.get_node(^"WorldEnvironment") as WorldEnvironment).environment
	var camera := Camera3D.new()
	level.add_child(camera)
	camera.make_current()
	camera.global_position = depot.to_global(Vector3(0.0, 1.6, -9.0))
	for tick: int in range(90):
		await process_frame
	var outside_fog: float = environment.fog_density
	var outside_ambient: float = environment.ambient_light_energy
	var outside_sky: float = environment.ambient_light_sky_contribution
	var atmosphere := depot.get_node(^"Atmosphere") as DepotAtmosphere
	_expect(atmosphere.blend() < 0.01, "Outside the depot the air is the level's own (blend %.2f)" % atmosphere.blend())
	camera.global_position = depot.to_global(Vector3(0.0, 1.6, 17.0))
	for tick: int in range(90):
		await process_frame
	_expect(atmosphere.blend() > 0.99, "Under the roof the interior air is fully in (blend %.2f)" % atmosphere.blend())
	_expect(environment.fog_density < outside_fog * 0.2,
			"No distance haze under the roof (%.4f against %.4f outside)" % [environment.fog_density, outside_fog])
	_expect(environment.ambient_light_energy < outside_ambient,
			"The ambient is lower under the roof (%.2f against %.2f)" % [
					environment.ambient_light_energy, outside_ambient])
	_expect(environment.ambient_light_sky_contribution < outside_sky,
			"Less of the ambient comes from the sky under the roof (%.2f against %.2f)" % [
					environment.ambient_light_sky_contribution, outside_sky])
	camera.global_position = depot.to_global(Vector3(0.0, 1.6, -9.0))
	for tick: int in range(90):
		await process_frame
	var restored: bool = (is_equal_approx(environment.fog_density, outside_fog)
			and is_equal_approx(environment.ambient_light_energy, outside_ambient)
			and is_equal_approx(environment.ambient_light_sky_contribution, outside_sky))
	_expect(restored, "Stepping back out gives the level's fog and ambient back")
	# And if the depot leaves while the viewer is inside, the shared Environment is put back.
	camera.global_position = depot.to_global(Vector3(0.0, 1.6, 17.0))
	for tick: int in range(90):
		await process_frame
	depot.get_parent().remove_child(depot)
	var put_back: bool = (is_equal_approx(environment.fog_density, outside_fog)
			and is_equal_approx(environment.ambient_light_sky_contribution, outside_sky))
	_expect(put_back, "The Environment is put back when the depot leaves (%.4f)" % environment.fog_density)
	depot.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

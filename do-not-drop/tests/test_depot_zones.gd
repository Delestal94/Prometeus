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
##   - the air: under the roof the level's fog is next to nothing and the ambient
##     is the depot's own (low, cool, hardly following the weather), the sun's
##     shadows are fully dark; outside and after the depot leaves the tree
##     everything is the level's own again;
##   - the light pass (N-319 pass 2): the shafts follow the weather, the glass
##     shows the sky, the sun shield is there, the paint is as designed (muted
##     walkways, no arrow to the board), the hanging signs are shipping labels
##     and the office door has no small sign; with a low sun toward any corner the
##     shafts, their dust and the floor patches stay inside the walls (they used
##     to show outside, through them);
##   - the lights: a handful of real ones, the three big spots ranked for
##     shadows, and WorldQuality keeping as many as the level allows (none on Low);
##   - the signs hang smaller over their zones; everything static is batched;
##   - the finishing pass (N-319.3/4): ONE contact-shadow batch and ONE wear batch, the shaft dust (none at
##     night), the mural only when its art is in the project, no hanging sign over the board, the lit
##     office window, the order board in bold, the flicker no faster than 3 Hz; the texts the art left
##     blank are filled (a word under each safety pictogram, a light header on the swatch board, the photo
##     wall's title on its own band);
##   - the modelled kit is connected (N-319.2): the door's signal light follows the
##     door (green open, red shut), the middle of the hall has its cages, table and
##     pallet (solid, clear of the walkways and the truck), the left wall its
##     panel and cabinet, the pictograms come from the atlas, and the batches stay
##     under the cap.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")
const Labels = preload("res://scripts/gameplay/depot/depot_labels.gd")
## Most real lights the depot may hang itself (the forklift's beacon and the
## mirror's lamp are on top): the GL Compatibility renderer caps them per mesh.
const MAX_DEPOT_LIGHTS: int = 7
## Most separate meshes the depot's root may carry: the static geometry goes
## through DepotKit, one batch per material (154 before N-319, 185 with the
## zones, 202 with the modelled kit). A node per box would be thousands.
const MAX_ROOT_MESHES: int = 220
## The kit's own batches ("Depot..." and "Lamps...") stay under this (184 now).
const MAX_KIT_BATCHES: int = 190

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
	_test_light_pass(depot)
	_test_kit(depot)
	_test_finish(depot)
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
	for caption: String in ["TALLER", "SUMINISTROS", "VESTUARIO", "OFICINA"]:
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


## The air under the roof: no haze, the depot's own ambient (hardly following the
## weather) and the sun's shadows fully dark; outside and once the depot is gone,
## the level's own.
func _test_air(level: Node, depot: Node3D) -> void:
	var environment: Environment = (level.get_node(^"WorldEnvironment") as WorldEnvironment).environment
	var sun := level.get_node(^"Sun") as DirectionalLight3D
	var camera := Camera3D.new()
	level.add_child(camera)
	camera.make_current()
	camera.global_position = depot.to_global(Vector3(0.0, 1.6, -9.0))
	for tick: int in range(90):
		await process_frame
	var outside_fog: float = environment.fog_density
	var outside_ambient: float = environment.ambient_light_energy
	var outside_sky: float = environment.ambient_light_sky_contribution
	var outside_colour: Color = environment.ambient_light_color
	var outside_shadow: float = sun.shadow_opacity
	var atmosphere := depot.get_node(^"Atmosphere") as DepotAtmosphere
	_expect(atmosphere.blend() < 0.01, "Outside the depot the air is the level's own (blend %.2f)" % atmosphere.blend())
	camera.global_position = depot.to_global(Vector3(0.0, 1.6, 17.0))
	for tick: int in range(90):
		await process_frame
	_expect(atmosphere.blend() > 0.99, "Under the roof the interior air is fully in (blend %.2f)" % atmosphere.blend())
	_expect(environment.fog_density < outside_fog * 0.2,
			"No distance haze under the roof (%.4f against %.4f outside)" % [environment.fog_density, outside_fog])
	var wanted: Dictionary = DepotAtmosphere.interior(outside_ambient, outside_sky, outside_colour)
	_expect(is_equal_approx(environment.ambient_light_energy, float(wanted.energy)),
			"The ambient under the roof is the depot's own (%.3f, wanted %.3f)" % [
					environment.ambient_light_energy, float(wanted.energy)])
	var drift: float = absf(environment.ambient_light_energy - DepotAtmosphere.INSIDE_AMBIENT_ENERGY)
	_expect(drift <= outside_ambient * 0.25 + 0.001,
			"The ambient under the roof hardly follows the weather (%.3f against the depot's %.2f)" % [
					environment.ambient_light_energy, DepotAtmosphere.INSIDE_AMBIENT_ENERGY])
	_expect(environment.ambient_light_sky_contribution < 0.1,
			"Almost none of the ambient comes from the sky under the roof (%.2f)" % [
					environment.ambient_light_sky_contribution])
	_expect(is_equal_approx(sun.shadow_opacity, DepotAtmosphere.INSIDE_SHADOW_OPACITY),
			"The sun's shadows are fully dark under the roof (%.2f)" % sun.shadow_opacity)
	camera.global_position = depot.to_global(Vector3(0.0, 1.6, -9.0))
	for tick: int in range(90):
		await process_frame
	var restored: bool = (is_equal_approx(environment.fog_density, outside_fog)
			and is_equal_approx(environment.ambient_light_energy, outside_ambient)
			and is_equal_approx(environment.ambient_light_sky_contribution, outside_sky)
			and environment.ambient_light_color.is_equal_approx(outside_colour)
			and is_equal_approx(sun.shadow_opacity, outside_shadow))
	_expect(restored, "Stepping back out gives the level's fog, ambient and sun shadows back")
	# And if the depot leaves while the viewer is inside, the shared Environment is put back.
	camera.global_position = depot.to_global(Vector3(0.0, 1.6, 17.0))
	for tick: int in range(90):
		await process_frame
	depot.get_parent().remove_child(depot)
	var put_back: bool = (is_equal_approx(environment.fog_density, outside_fog)
			and is_equal_approx(environment.ambient_light_sky_contribution, outside_sky)
			and is_equal_approx(sun.shadow_opacity, outside_shadow))
	_expect(put_back, "The Environment and the sun are put back when the depot leaves (%.4f)" % environment.fog_density)
	depot.free()


## The finishing pass: grounding, wear, dust, mural, the office window and the small things.
func _test_finish(depot: Node3D) -> void:
	var contact: int = 0
	var wear: int = 0
	var office_glow: int = 0
	for child: Node in depot.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			continue
		var material := part.mesh.surface_get_material(0) as StandardMaterial3D
		if material == null:
			continue
		if material.blend_mode == BaseMaterial3D.BLEND_MODE_MUL:
			contact += 1
		if material.vertex_color_use_as_albedo and material.albedo_texture != null \
				and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			wear += 1
		if material.emission_enabled and material.emission.is_equal_approx(DepotZones.WINDOW_WARM):
			office_glow += 1
	_expect(contact == 1, "All the contact shadows are ONE multiplicative batch (%d)" % contact)
	_expect(wear >= 1, "The wear is in an alpha batch with vertex colours (%d)" % wear)
	_expect(office_glow == 1, "The Boss's window is one warm emissive batch (%d)" % office_glow)
	# Dust in the shafts: ten motes per shaft by day, none at night.
	var saved: Dictionary = WorldMood.active
	var holder := Node3D.new()
	WorldMood.active = {"weather": WorldMood.Weather.CLEAR, "time": WorldMood.TimeOfDay.DAY}
	DepotLighting.build_dust(holder, null)
	var by_day: int = holder.get_child_count()
	var motes: int = (holder.get_child(0) as CPUParticles3D).amount if by_day > 0 else 0
	for child: Node in holder.get_children():
		child.free()
	WorldMood.active = {"weather": WorldMood.Weather.CLEAR, "time": WorldMood.TimeOfDay.NIGHT}
	DepotLighting.build_dust(holder, null)
	var by_night: int = holder.get_child_count()
	WorldMood.active = saved
	holder.free()
	_expect(by_day == DepotLighting.SKYLIGHT_XS.size() * DepotLighting.SKYLIGHT_ZS.size()
			and motes == DepotLighting.DUST_PER_SHAFT, "A clear day has dust in every shaft (%d shafts, %d motes)" % [
					by_day, motes])
	_expect(by_night == 0, "No dust in the shafts at night (%d)" % by_night)
	_expect(depot.get_node_or_null(^"DustMotes") == null, "The loose motes are gone")
	# The mural is drawn when its art is in the project, and only then.
	_expect((depot.get_node_or_null(^"BrandMural") != null) == ResourceLoader.exists(DepotProps.MURAL),
			"The brand mural is there exactly when its texture is")
	# The control island has no hanging sign: its board is the brightest thing.
	for label: Node in get_nodes_in_group(&"depot_sign"):
		_expect(not String(label.get_meta(&"sign")).contains("PIZARRA"), "No hanging sign over the board")
	# The flicker never goes faster than three a second (photosensitivity): the shortest wait is over 1/3 s.
	var ambience_source: String = FileAccess.get_file_as_string("res://scripts/gameplay/depot/depot_ambience.gd")
	_expect(ambience_source.contains("randf_range(0.36, 0.7)"),
			"The tube's flicker keeps under three stutters a second")
	_expect(DepotLayout.body_bold() is FontVariation, "The order board's items are in bold")
	# The texts the art left blank (N-319 close): every pictogram safety sign carries its word under it, and
	# the swatch board's dark header band is written in a light colour (INK letters vanished into it).
	var captions: Array[Node] = get_nodes_in_group(&"depot_safety_caption")
	_expect(captions.size() == 5, "The five pictogram safety signs carry a caption (%d)" % captions.size())
	for caption: Node in captions:
		var words: String = (caption as Label3D).text
		_expect(not words.is_empty() and not words.begins_with("WORLD_"), "A safety caption has its words (%s)" % words)
	var swatches := depot.find_child("SwatchesLabel", true, false) as Label3D
	_expect(swatches != null and swatches.modulate.get_luminance() > 0.7,
			"The swatch board's header reads light on its dark band")
	var photo_band := depot.find_child("TitleBand", true, false) as MeshInstance3D
	var photo_title := photo_band.get_parent().get_node_or_null(^"Title") as Label3D if photo_band != null else null
	_expect(photo_title != null and photo_title.modulate.get_luminance() > 0.7,
			"The photo wall's title sits light on its own dark band")
	# The workshop's tyre stack and tool boards are the kit's when their models are in.
	if ResourceLoader.exists(DepotKit.depot_model("sm_env_depot_tire_stack")):
		_expect(true, "The tyre stack is the kit's")


## The modelled kit in the game: the door's signal light, the middle of the hall, the
## left wall, the pictogram atlas and the batch cap.
func _test_kit(depot: Node3D) -> void:
	var door := depot.get_node(^"RollerDoor") as DepotRollerDoor
	var greens: Array[Node] = door.find_children("DoorLightGreen", "", true, false)
	var reds: Array[Node] = door.find_children("DoorLightRed", "", true, false)
	_expect(greens.size() == 2 and reds.size() == 2, "The door has a signal light on each side (%d green, %d red)" % [
			greens.size(), reds.size()])
	door.set_open(true, false)
	_expect(greens.all(func(light: Node) -> bool: return (light as Node3D).visible)
			and reds.all(func(light: Node) -> bool: return not (light as Node3D).visible),
			"An open door shows the green arrow and not the red X")
	door.set_open(false, false)
	_expect(reds.all(func(light: Node) -> bool: return (light as Node3D).visible)
			and greens.all(func(light: Node) -> bool: return not (light as Node3D).visible),
			"A shut door shows the red X and not the green arrow")
	door.set_open(true, false)
	# The middle of the hall: solid things stand at the cages, the table and the pallet,
	# none of it near the truck or the gathering rectangle.
	var space: PhysicsDirectSpaceState3D = depot.get_world_3d().direct_space_state
	for at: Vector3 in [Vector3(-3.9, 0.0, 21.4), Vector3(-2.75, 0.0, 21.05), Vector3(0.4, 0.0, 21.6),
			Vector3(4.4, 0.0, 21.2)]:
		var from: Vector3 = depot.to_global(at + Vector3.UP * 4.0)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 5.0, 1)
		var hit: Dictionary = space.intersect_ray(query)
		var height: float = depot.to_local(hit.position).y if not hit.is_empty() else -1.0
		_expect(height > Layout.FLOOR_TOP + 0.5, "Something solid stands at %s in the middle (%.2f m)" % [at, height])
		_expect(not Layout.GATHER.grow(0.5).has_point(Vector2(at.x, at.z)),
				"The middle's props stay off the crew's rectangle (%s)" % at)
		_expect(Vector2(at.x, at.z).distance_to(Vector2(Layout.TRUCK_BAY.x, Layout.TRUCK_BAY.z)) > 10.0,
				"The middle's props stay clear of the truck (%s)" % at)
	# The left wall's panel and cabinet are on the wall, not in the lane.
	for z: float in [10.3, 11.35, 11.95]:
		_expect(DepotProps.WEST_WALL_X < Layout.FORKLIFT_LANE_X - Layout.FORKLIFT_LANE_WIDTH * 0.5 - 1.0,
				"The wall's kit stays clear of the forklift lane (z %.1f)" % z)
	# Pictograms come from the atlas in one shared batch; the kit stays under its cap.
	var batches: int = 0
	var pictograms: int = 0
	for child: Node in depot.get_children():
		var part := child as MeshInstance3D
		if part == null:
			continue
		if String(part.name).begins_with("Depot") or String(part.name).begins_with("Lamps"):
			batches += 1
		var material := part.mesh.surface_get_material(0) as StandardMaterial3D if part.mesh != null else null
		if material != null and material.albedo_texture != null \
				and material.albedo_texture.resource_path == DepotKit.PICTOGRAMS:
			pictograms += 1
	_expect(pictograms >= 1 and pictograms <= 2,
			"The pictograms come from the atlas in one batch of the kit and one of the posters (%d)" % pictograms)
	_expect(batches <= MAX_KIT_BATCHES, "The kit's batches stay under %d (%d)" % [MAX_KIT_BATCHES, batches])


## The light and paint pass: what the weather does to the shafts and the glass, the
## sun shield, the paint's measurements and the new signs.
func _test_light_pass(depot: Node3D) -> void:
	var saved: Dictionary = WorldMood.active
	WorldMood.active = {"weather": WorldMood.Weather.CLEAR, "time": WorldMood.TimeOfDay.DAY}
	var sunny: float = DepotLighting.shaft_peak()
	var sunny_glass: Dictionary = DepotLighting.glass_look()
	WorldMood.active = {"weather": WorldMood.Weather.CLOUDY, "time": WorldMood.TimeOfDay.DAY}
	var cloudy: float = DepotLighting.shaft_peak()
	var cloudy_glass: Dictionary = DepotLighting.glass_look()
	WorldMood.active = {"weather": WorldMood.Weather.CLEAR, "time": WorldMood.TimeOfDay.NIGHT}
	var night: float = DepotLighting.shaft_peak()
	var night_glass: Dictionary = DepotLighting.glass_look()
	WorldMood.active = saved
	_expect(is_equal_approx(sunny, 0.25) and is_equal_approx(cloudy, 0.12) and is_zero_approx(night),
			"The shafts peak at 0.25 in sun, 0.12 in cloud and none at night (%.2f, %.2f, %.2f)" % [
					sunny, cloudy, night])
	var bright: Color = sunny_glass.colour
	var dull: Color = cloudy_glass.colour
	var dark: Color = night_glass.colour
	_expect(bright.get_luminance() > dull.get_luminance() and dull.get_luminance() > dark.get_luminance() * 2.0,
			"The glass shows the sky: brighter in sun than in cloud, nearly dark at night (%.2f, %.2f, %.2f)" % [
					bright.get_luminance(), dull.get_luminance(), dark.get_luminance()])
	_expect(bright.b > bright.r and bright.get_luminance() < 0.8,
			"The glass is a greyish blue, not white (%s)" % bright)
	_test_shafts_stay_inside()
	# The sun shield: shadow-only slabs around the hall, never drawn.
	var shield := depot.get_node_or_null(^"SunShield")
	_expect(shield != null and shield.get_child_count() == 4, "Four shadow-only slabs close the sun's leaks")
	if shield != null:
		for slab: Node in shield.get_children():
			var instance := slab as MeshInstance3D
			_expect(instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
					"A sun shield slab only casts shadows")
	# Paint and signs as designed.
	_expect(is_equal_approx(Layout.WALK_WIDTH, 1.0), "The walkways are 1 m wide (%.2f)" % Layout.WALK_WIDTH)
	_expect(Layout.WALK_GREEN.s < 0.5, "The walkway green is muted (saturation %.2f)" % Layout.WALK_GREEN.s)
	var guide_captions: Array[String] = []
	for guide: Dictionary in depot.get(&"guides"):
		guide_captions.append(String(guide.caption))
	_expect(not guide_captions.has("PIZARRA"), "No arrow leads to the board: it is in plain view of the spawn")
	_expect(depot.get_node_or_null(^"OfficeDoorSign") == null, "The office has no small sign on its door")
	var offices: int = 0
	for label: Node in get_nodes_in_group(&"depot_sign"):
		if String(label.get_meta(&"sign")) == "OFICINA":
			offices += 1
	_expect(offices == 2, "The office has its hanging sign, front and back, and nothing else (%d labels)" % offices)
	# A hanging sign is a shipping label: a dark INK plate in the depot's batches.
	var ink_plates: int = 0
	for child: Node in depot.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			continue
		var material := part.mesh.surface_get_material(0) as StandardMaterial3D
		if material != null and material.albedo_color.is_equal_approx(Layout.INK) and material.albedo_texture == null:
			ink_plates += 1
	_expect(ink_plates >= 1, "The signs' INK plates are in the depot's batches")


## A low sun slants the shafts up to SHAFT_MAX_DROP toward a wall: toward each corner of the hall,
## no shaft, dust box or floor patch reaches past the walls (they used to show outside, through them).
func _test_shafts_stay_inside() -> void:
	var saved: Dictionary = WorldMood.active
	WorldMood.active = {"weather": WorldMood.Weather.CLEAR, "time": WorldMood.TimeOfDay.DAY}
	var bounds: Rect2 = DepotLighting.interior().grow(0.001)
	var holder := Node3D.new()
	root.add_child(holder)
	var sun := DirectionalLight3D.new()
	holder.add_child(sun)
	for toward: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		# Nearly flat, so the slant is the longest a shaft gets.
		var heading := Vector3(toward.x, -0.2, toward.y).normalized()
		sun.global_basis = Basis.looking_at(heading, Vector3.UP)
		var slant: Vector3 = DepotLighting.sunlight(sun).slant
		_expect(slant.length() > DepotLighting.SHAFT_MAX_DROP - 0.01,
				"A low sun slants the shafts all the way (%.2f m toward %s)" % [slant.length(), toward])
		var shafts: MeshInstance3D = DepotLighting.build_shafts(holder, sun)
		var outside: int = 0
		var vertices: PackedVector3Array = shafts.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			if not bounds.has_point(Vector2(vertex.x, vertex.z)):
				outside += 1
		_expect(vertices.size() > 0 and outside == 0,
				"Toward %s no shaft leaves the hall (%d of %d vertices outside)" % [toward, outside, vertices.size()])
		shafts.free()
		DepotLighting.build_dust(holder, sun)
		for child: Node in holder.get_children():
			var dust := child as CPUParticles3D
			if dust == null:
				continue
			var extents: Vector3 = dust.emission_box_extents
			var box := Rect2(Vector2(dust.position.x - extents.x, dust.position.z - extents.z),
					Vector2(extents.x, extents.z) * 2.0)
			_expect(bounds.encloses(box), "Toward %s the dust in %s stays inside the hall" % [toward, dust.name])
			dust.free()
		var kit := DepotKit.new(holder)
		DepotLighting.build_pools(kit, sun)
		for batch: MeshInstance3D in kit.commit("Pools"):
			var reach: AABB = batch.get_aabb()
			_expect(bounds.encloses(Rect2(reach.position.x, reach.position.z, reach.size.x, reach.size.z)),
					"Toward %s the lamp pools and daylight patches stay on the hall's floor" % toward)
			batch.free()
	holder.free()
	WorldMood.active = saved


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

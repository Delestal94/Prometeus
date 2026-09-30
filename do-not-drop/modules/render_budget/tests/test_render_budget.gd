extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/render_budget/tests/test_render_budget.gd
##
## The render_budget module on its own (docs/modulos.md):
## - WorldQuality: each level has its settings, apply_to() scales a sun's
##   shadow distance, a batch's draw range and a particle count from their
##   base values, and watch() catches nodes added later;
## - DetailMaterials: with the game's tables handed in, a palette material
##   gets one shared triplanar twin per (entry, colour), unknown entries stay
##   flat, autumn tints only what the tables say, night glow lights only
##   the asked-for keys and only after dark;
## - DressingBatcher: identical static pieces in a group fold into one
##   MultiMesh with their transforms, pieces with a script or a knockable
##   rule stay nodes, solid rules get a collider;
## - ContactShadow: a band solid inside the footprint and gone `margin`
##   outside, every vertex on the ground callback.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	await _test_world_quality(scene)
	_test_detail_materials()
	await _test_batcher(scene)
	_test_contact_shadow()
	scene.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: quality presets, detail materials, batching and contact shadows work without the game")
	quit(_failures)


func _test_world_quality(scene: Node3D) -> void:
	WorldQuality.apply(self, WorldQuality.Level.LOW)
	_expect(WorldQuality.level == WorldQuality.Level.LOW, "The level is kept")
	_expect(WorldQuality.setting("range_scale") < WorldQuality.PRESETS[WorldQuality.Level.HIGH]["range_scale"],
		"Low draws less far than High")
	_expect(is_equal_approx(root.scaling_3d_scale, WorldQuality.setting("render_scale")),
		"The 3D render scale follows the level")
	var sun := DirectionalLight3D.new()
	scene.add_child(sun)
	WorldQuality.apply_to(sun)
	_expect(is_equal_approx(sun.directional_shadow_max_distance, WorldQuality.setting("shadow_distance")),
		"A sun gets the level's shadow distance")
	var batch := MultiMeshInstance3D.new()
	batch.set_meta(WorldQuality.BASE_RANGE_META, 100.0)
	scene.add_child(batch)
	WorldQuality.apply_to(batch)
	_expect(is_equal_approx(batch.visibility_range_end, 100.0 * WorldQuality.setting("range_scale")),
		"A batch's draw range is its base times the level's scale")
	var particles := GPUParticles3D.new()
	particles.amount = 100
	scene.add_child(particles)
	WorldQuality.apply_to(particles)
	_expect(particles.amount == roundi(100 * WorldQuality.setting("particle_scale")),
		"Particles are scaled from their base amount (got %d)" % particles.amount)
	WorldQuality.apply(self, WorldQuality.Level.HIGH)
	_expect(particles.amount == 100, "Back on High the base amount returns (got %d)" % particles.amount)
	WorldQuality.apply(self, WorldQuality.Level.MEDIUM)
	WorldQuality.watch(self)
	var later := GPUParticles3D.new()
	later.amount = 40
	scene.add_child(later)
	await process_frame
	_expect(later.amount == roundi(40 * WorldQuality.setting("particle_scale")),
		"A node added after watch() is scaled too (got %d)" % later.amount)
	WorldQuality.apply(self, WorldQuality.Level.HIGH)


func _test_detail_materials() -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_L8)
	image.fill(Color(0.8, 0.8, 0.8))
	DetailMaterials.textures = {"planks": ImageTexture.create_from_image(image)}
	DetailMaterials.detail = {"wood": ["planks", 1.5], "leaf": ["planks", 1.0]}
	DetailMaterials.detail_gain = 1.2
	DetailMaterials.lifted = {}
	DetailMaterials.autumn = {"leaf": [Color(0.8, 0.4, 0.1), 1.0]}
	DetailMaterials.evergreen_words = ["pine"]
	DetailMaterials.night_glow = {"lamp": [Color(1.0, 0.9, 0.7), 2.0]}
	DetailMaterials.set_season(0)
	DetailMaterials.set_night_level(0.0)
	var wood := StandardMaterial3D.new()
	wood.resource_name = "wood"
	wood.albedo_color = Color(0.5, 0.3, 0.2)
	var twin: BaseMaterial3D = DetailMaterials.textured_for(wood)
	_expect(twin != null and twin.uv1_world_triplanar and twin.albedo_texture != null,
		"A listed material gets a triplanar textured twin")
	_expect(twin != null and is_equal_approx(twin.uv1_scale.x, 1.0 / 1.5),
		"Its tiling is metres per repeat (got %s)" % [twin.uv1_scale if twin else null])
	_expect(twin != null and is_equal_approx(twin.albedo_color.r, 0.5 * 1.2),
		"The gain puts the average colour back (got %s)" % [twin.albedo_color if twin else null])
	_expect(DetailMaterials.textured_for(wood) == twin, "The twin is shared per material and colour")
	_expect(twin != null and DetailMaterials.textured_for(twin) == null, "Its own twin is left alone")
	var glass := StandardMaterial3D.new()
	glass.resource_name = "glass"
	_expect(DetailMaterials.textured_for(glass) == null, "An unlisted material stays flat")
	var leaf_green := Color(0.2, 0.6, 0.2)
	_expect(DetailMaterials.seasonal_color("leaf", leaf_green) == leaf_green, "In summer the palette is as authored")
	DetailMaterials.set_season(1)
	_expect(DetailMaterials.seasonal_color("leaf", leaf_green).r > 0.7,
		"In autumn a listed leaf turns (got %s)" % DetailMaterials.seasonal_color("leaf", leaf_green))
	_expect(DetailMaterials.seasonal_color("leaf", leaf_green, true) == leaf_green, "An evergreen keeps its green")
	_expect(DetailMaterials.seasonal_color("wood", leaf_green) == leaf_green, "Unlisted entries don't turn")
	var pine: bool = DetailMaterials.is_evergreen("res://models/pine_tall.glb")
	_expect(pine and not DetailMaterials.is_evergreen("res://models/oak.glb"), "Evergreens are told by file name")
	DetailMaterials.set_season(0)
	var holder := Node3D.new()
	var lamp := MeshInstance3D.new()
	var box := BoxMesh.new()
	var lamp_material := StandardMaterial3D.new()
	lamp_material.resource_name = "lamp"
	box.material = lamp_material
	lamp.mesh = box
	holder.add_child(lamp)
	_expect(DetailMaterials.light_up(holder, ["lamp"]) == 0, "By day nothing glows")
	DetailMaterials.set_night_level(1.0)
	_expect(DetailMaterials.light_up(holder, ["window"]) == 0, "Only the asked-for keys glow")
	_expect(DetailMaterials.light_up(holder, ["lamp"]) == 1, "At night the lamp glows")
	var glow := lamp.get_surface_override_material(0) as BaseMaterial3D
	_expect(glow != null and glow.emission_enabled and is_equal_approx(glow.emission_energy_multiplier, 2.0),
		"The glow takes the table's energy at full night")
	DetailMaterials.set_night_level(0.0)
	holder.free()


func _test_batcher(scene: Node3D) -> void:
	DressingBatcher.record_instances = true
	DressingBatcher.piece_groups = ["Dressing"]
	DressingBatcher.solid_rules = [&"rock"]
	DressingBatcher.knockable_rules = [&"cone"]
	var route := Node3D.new()
	scene.add_child(route)
	var segment := Node3D.new()
	route.add_child(segment)
	var group := Node3D.new()
	group.name = "Dressing"
	segment.add_child(group)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.5, 0.5)
	# Placed pieces are scene instances in a real route: the merged model
	# mesh is cached per scene file, which is what puts three ferns (in the
	# same CELL-sized patch) into one batch.
	var fern_scene: PackedScene = load("res://modules/render_budget/tests/fern_piece.tscn")
	var placed: Array[Transform3D] = []
	for index: int in range(3):
		var piece := fern_scene.instantiate() as Node3D
		piece.position = Vector3(index * 2.0, 0.0, -10.0 - index * 3.0)
		piece.set_meta(&"rule", &"fern")
		group.add_child(piece)
		placed.append(piece.transform)
	var scripted := Node3D.new()
	scripted.name = "Animal"
	var animal_script := GDScript.new()
	animal_script.source_code = "extends Node3D\n"
	animal_script.reload()
	scripted.set_script(animal_script)
	var scripted_part := MeshInstance3D.new()
	scripted_part.mesh = mesh
	scripted.add_child(scripted_part)
	group.add_child(scripted)
	var rock := Node3D.new()
	rock.position = Vector3(10.0, 0.0, 0.0)
	rock.set_meta(&"rule", &"rock")
	var rock_part := MeshInstance3D.new()
	rock_part.mesh = mesh
	rock.add_child(rock_part)
	group.add_child(rock)
	var cone := Node3D.new()
	cone.position = Vector3(-4.0, 0.0, 0.0)
	cone.set_meta(&"rule", &"cone")
	var cone_part := MeshInstance3D.new()
	cone_part.mesh = mesh
	cone.add_child(cone_part)
	group.add_child(cone)
	await process_frame
	var baked: int = DressingBatcher.bake(route, [segment])
	_expect(baked == 4, "The three ferns and the rock fold into batches (got %d)" % baked)
	var holder: Node = route.get_node_or_null(^"BatchedDressing")
	_expect(holder != null, "The batches live under BatchedDressing")
	var batches: Array[Node] = holder.find_children("*", "MultiMeshInstance3D", true, false) if holder != null else []
	var ferns: MultiMeshInstance3D = null
	for batch: Node in batches:
		if (batch as MultiMeshInstance3D).multimesh.instance_count == 3:
			ferns = batch
	_expect(ferns != null, "One MultiMesh holds the three ferns (%d batches)" % batches.size())
	if ferns != null:
		var xforms: Array = ferns.get_meta(&"instance_transforms", [])
		var same: bool = xforms.size() == 3
		for index: int in range(mini(xforms.size(), 3)):
			same = same and (xforms[index] as Transform3D).origin.is_equal_approx(placed[index].origin)
		_expect(same, "Every fern keeps the transform it was placed with")
		_expect(ferns.has_meta(WorldQuality.BASE_RANGE_META), "A batch carries its base draw range for WorldQuality")
	_expect(is_instance_valid(scripted) and scripted.get_parent() == group, "A piece with a script stays a node")
	_expect(holder != null and holder.find_children("*",
		"StaticBody3D", true, false).size() == 1, "The solid rule got one collider body")
	var knockable: Node = null
	for child: Node in group.get_children():
		if child is RigidBody3D:
			knockable = child
	_expect(knockable != null and knockable.get_meta(&"rule", &"") == &"cone",
		"The knockable rule became a rigid body that keeps its meta")
	DressingBatcher.record_instances = false


func _test_contact_shadow() -> void:
	var flat: Callable = func(_point: Vector3) -> float: return 0.25
	var band: ArrayMesh = ContactShadow.mesh(Transform3D.IDENTITY, Vector2(4.0, 2.0), 0.5, flat)
	var arrays: Array = band.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_expect(vertices.size() == 16 and colours.size() == 16, "A 4 x 4 grid (got %d vertices)" % vertices.size())
	var on_ground: bool = true
	var widest: float = 0.0
	var solid: int = 0
	for index: int in range(vertices.size()):
		on_ground = on_ground and is_equal_approx(vertices[index].y, 0.25 + ContactShadow.LIFT)
		widest = maxf(widest, absf(vertices[index].x))
		if colours[index].a > 0.99:
			solid += 1
	_expect(on_ground, "Every vertex sits just over the ground callback")
	_expect(is_equal_approx(widest, 2.5), "The band reaches margin past the footprint (got %.2f)" % widest)
	_expect(solid == 4, "The inner ring is solid, the outer ring fades (got %d solid)" % solid)
	var patch: MeshInstance3D = ContactShadow.instance(band, 0.4)
	_expect(patch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and patch.material_override != null,
		"The patch casts no shadow and has its material")
	var shared: StandardMaterial3D = ContactShadow.material(0.4)
	_expect(shared == ContactShadow.material(0.4), "One material per strength")
	patch.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

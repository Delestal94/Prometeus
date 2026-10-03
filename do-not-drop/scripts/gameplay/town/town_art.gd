extends RefCounted
## Existing game art on the town's frontage lots. Visual selection has its own
## seeded stream and does not change the portable plan or delivery addresses.

const KIT := preload("res://scripts/gameplay/depot/depot_kit.gd")
const HOUSE_MODELS: Array[String] = [
	"res://assets/models/architecture/sm_arch_delivery_house_cottage.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_cabin.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_bungalow.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_two_story.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_farmhouse.glb",
]
const TREES: Array[String] = [
	"res://assets/models/environment/forest/sm_env_forest_oak.glb",
	"res://assets/models/environment/forest/sm_env_forest_birch.glb",
	"res://assets/models/environment/forest/sm_env_forest_maple.glb",
]
const BENCH := "res://assets/models/environment/props/sm_env_prop_bench.glb"
const LAMP := "res://assets/models/environment/props/sm_env_prop_street_lamp_refined.glb"


static func customer_variant(seed_value: int, index: int) -> int:
	# These three fit the smallest starting lots. Never repeat one in a run.
	return posmod(posmod(hash([seed_value, &"town_customers"]), 3) + index, 3)


static func build_lot(parcel: Node3D, lot: Dictionary, seed_value: int) -> void:
	var building := StaticBody3D.new()
	building.name = "Building"
	parcel.add_child(building)
	var front: Vector2 = (lot.frontage - lot.position).rotated(-float(lot.angle))
	var side: float = signf(front.y)
	building.rotation.y = PI if side > 0 else 0.0
	building.position = Vector3(0, .08, -side * float(lot.size.y) * .12)
	if lot.role in [&"depot", &"workshop"]:
		_service(building, lot)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, &"town_houses", lot.address])
	var variant: int = rng.randi_range(0, HOUSE_MODELS.size() - 1)
	if lot.role == &"house":
		variant = customer_variant(seed_value, int(lot.address.y) - 2)
	var kit := KIT.new(building, "Colliders", building)
	var bounds: AABB = kit.model_bounds(HOUSE_MODELS[variant])
	# Authored houses keep their scale. Fall back only if an asset grows beyond its lot.
	var footprint: AABB = building.transform * bounds
	var half: Vector2 = lot.size * .5 - Vector2.ONE * .2
	if (
		footprint.position.x < -half.x
		or footprint.end.x > half.x
		or footprint.position.z < -half.y
		or footprint.end.z > half.y
	):
		variant = 0
		bounds = kit.model_bounds(HOUSE_MODELS[variant])
	building.set_meta(&"house_variant", variant)
	model(building, "HouseVisual", HOUSE_MODELS[variant], Vector3.ZERO)
	kit.collider(bounds.size, Transform3D(Basis.IDENTITY, bounds.get_center()))
	if lot.role == &"shop":
		kit.box(Vector3(3.8, .12, 1.8), Vector3(0, 2.8, -4.1), KIT.flat(Color("65b5a1")))
		for x: float in [-1.75, 1.75]:
			kit.box(Vector3(.1, 2.8, .1), Vector3(x, 1.4, -4.8), KIT.flat(Color("46342a")))
	kit.commit("ShopDetail")


static func _service(building: StaticBody3D, lot: Dictionary) -> void:
	var kit := KIT.new(building, "Colliders", building)
	var width: float = float(lot.size.x) * .74
	var depth: float = float(lot.size.y) * .48
	var height: float = 6.2
	var wall := KIT.ribbed(Color("3f6f7a") if lot.role == &"depot" else Color("68777a"), .8)
	var trim := KIT.flat(Color("24363d"), .6, .3)
	var floor := KIT.detailed(Color("6f7272"), "plaster", 4, .5)
	kit.box(Vector3(width, .08, depth), Vector3(0, 0, 0), floor, true)
	for side: float in [-1, 1]:
		kit.box(Vector3(.22, height, depth), Vector3(side * width * .5, height * .5, 0), wall, true)
		var jamb: float = (width - 6.6) * .5
		kit.box(
			Vector3(jamb, height, .22),
			Vector3(side * (3.3 + jamb * .5), height * .5, -depth * .5),
			wall,
			true
		)
	kit.box(Vector3(width, height, .22), Vector3(0, height * .5, depth * .5), wall, true)
	kit.box(
		Vector3(6.6, height - 4.8, .22), Vector3(0, (height + 4.8) * .5, -depth * .5), wall, true
	)
	kit.box(Vector3(width + .4, .25, depth + .4), Vector3(0, height, 0), trim, true)
	for x: float in [-width * .5, width * .5]:
		kit.box(Vector3(.25, height, .25), Vector3(x, height * .5, depth * .5), trim)
	var sources: Array[String] = []
	var frame: String = KIT.depot_model("sm_env_depot_door_frame")
	kit.model(frame, Transform3D(Basis.IDENTITY, Vector3(0, 0, -depth * .5)))
	sources.append(frame)
	# Upper shutter slats, with the same authored door pieces as the main depot.
	var slat: String = KIT.depot_model("sm_env_depot_door_slat")
	for row: int in range(3):
		kit.model(slat, Transform3D(Basis.IDENTITY, Vector3(0, 4.65 + row * .3, -depth * .5)))
	sources.append(slat)
	if lot.role == &"workshop":
		_add_prop(kit, sources, "sm_env_depot_workbench_vise", Vector3(-width * .3, 0, depth * .25))
		_add_prop(
			kit, sources, "sm_env_depot_tool_board", Vector3(-width * .3, 1.55, depth * .5 - .2)
		)
		_add_prop(kit, sources, "sm_env_depot_tire_stack", Vector3(width * .3, 0, depth * .25))
	else:
		_add_prop(kit, sources, "sm_env_depot_pallet_wrapped", Vector3(width * .3, 0, depth * .25))
		_add_prop(
			kit, sources, "sm_env_depot_roll_cage_loaded", Vector3(-width * .3, 0, depth * .25)
		)
	building.set_meta(&"model_sources", PackedStringArray(sources))
	kit.commit("DepotArt")


static func _add_prop(kit: RefCounted, sources: Array[String], title: String, at: Vector3) -> void:
	var path: String = KIT.depot_model(title)
	kit.model_grounded(path, Transform3D(Basis.IDENTITY, at))
	var bounds: AABB = kit.model_bounds(path)
	kit.collider(
		bounds.size,
		Transform3D(Basis.IDENTITY, at + bounds.get_center() - Vector3.UP * bounds.position.y)
	)
	sources.append(path)


## Ground models by their authored bounds; expose the source for scene checks.
static func model(
	parent: Node3D, title: String, path: String, at: Vector3, yaw: float = 0.0, solid: bool = false
) -> Node3D:
	var piece := Node3D.new()
	piece.name = title
	piece.position = at
	piece.rotation.y = yaw
	piece.set_meta(&"model_source", path)
	parent.add_child(piece)
	var visual: Node3D = (load(path) as PackedScene).instantiate()
	LowpolyMaterials.apply(visual)
	LowpolyMaterials.light_up(visual, ["window", "lamp_glass"])
	piece.add_child(visual)
	var kit := KIT.new(piece)
	var bounds: AABB = kit.model_bounds(path)
	visual.position.y = -bounds.position.y
	DressingBatcher.merge_into_one(visual)
	if solid:
		kit.collider(
			bounds.size,
			Transform3D(Basis.IDENTITY, bounds.get_center() - Vector3.UP * bounds.position.y)
		)
	piece.set_meta(
		&"grounded_bounds", AABB(bounds.position - Vector3.UP * bounds.position.y, bounds.size)
	)
	return piece


static func build_trees(town: Node3D, positions: PackedVector2Array, seed_value: int) -> void:
	var forest := Node3D.new()
	forest.name = "ForestDressing"
	town.add_child(forest)
	var records: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, &"town_tree_art"])
	var kit := KIT.new(forest)
	for index: int in range(positions.size()):
		var path: String = TREES[index % TREES.size()]
		var tree: Node3D = (load(path) as PackedScene).instantiate()
		LowpolyMaterials.apply(tree)
		var scale_value: float = rng.randf_range(.8, 1.0)
		var bounds: AABB = kit.model_bounds(path)
		var at: Vector2 = positions[index]
		tree.position = Vector3(at.x, .08 - bounds.position.y * scale_value, at.y)
		tree.rotation.y = rng.randf_range(-PI, PI)
		tree.scale = Vector3.ONE * scale_value
		tree.set_meta(&"rule", &"tree")
		forest.add_child(tree)
		records.append({"model": path, "transform": tree.transform})
	town.set_meta(&"tree_art", records)
	DressingBatcher.bake(town, [], [forest])


static func loading_rack(parcel: Node3D, z: float) -> void:
	var rack := StaticBody3D.new()
	rack.name = "LoadingRack"
	rack.position = Vector3(0, .08, z)
	parcel.add_child(rack)
	var kit := KIT.new(rack, "Colliders", rack)
	var basis := Basis(Vector3.UP, PI * .5)
	var frame: String = KIT.depot_model("sm_env_depot_shelf_frame")
	var deck: String = KIT.depot_model("sm_env_depot_shelf_deck")
	for x: float in [-3, -1, 1, 3]:
		kit.model(frame, Transform3D(basis, Vector3(x, 0, 0)))
		for side: float in [-1, 1]:
			kit.collider(
				Vector3(.08, 2.7, .08), Transform3D(Basis.IDENTITY, Vector3(x, 1.35, side * .5))
			)
	for x: float in [-2, 0, 2]:
		for height: float in [.35, 1.1, 2.6]:
			kit.model(deck, Transform3D(basis, Vector3(x, height, 0)))
			kit.collider(
				Vector3(1.92, .12, 1.01), Transform3D(Basis.IDENTITY, Vector3(x, height - .06, 0))
			)
	rack.set_meta(&"model_sources", PackedStringArray([frame, deck]))
	kit.commit("ShelfArt")

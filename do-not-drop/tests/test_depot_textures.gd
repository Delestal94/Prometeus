extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_depot_textures.gd
##
## The depot's floor, walls and signs draw from textures it loads by path
## (depot_kit.gd): a file caught mid-reimport once left a white floor. Protects
## against that coming back unseen:
## - every tx_detail_*_512.png the kit can ask for and the pictogram atlas load as
##   a real Texture2D (and the ones the depot's scripts name are among them);
## - a texture that does not load leaves the flat colour on the material (not a white
##   albedo) and the pictogram atlas, when missing, draws nothing instead of white
##   squares; the warning is given once per path;
## - an arrow painted on the floor lies flat even when it is aimed at something up in the
##   air (a station): it once pitched its tip up and sank its tail into the floor and read
##   as hovering; it is opaque, in the floor's own finish;
## - DepotAtmosphere recovers the level's outdoor values from an Environment that
##   was not blended the way it expects without inflating them (clamped).

const DETAIL_DIR: String = "res://assets/textures/detail"
## The detail names the depot's scripts pass to DepotKit.detailed().
const USED: Array[String] = ["plaster", "stone", "grass", "wood_planks"]

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_textures_load()
	_test_missing_texture_falls_back()
	_test_arrows_lie_flat()
	_test_atmosphere_clamps()
	if _failures == 0:
		print("PASS: the depot's textures load, a missing one falls back to flat colour, the atmosphere stays in range")
	quit(_failures)


func _test_textures_load() -> void:
	var found: int = 0
	for entry: String in ResourceLoader.list_directory(DETAIL_DIR):
		if entry.begins_with("tx_detail_") and entry.ends_with("_512.png"):
			found += 1
			var texture := load(DETAIL_DIR.path_join(entry)) as Texture2D
			_expect(texture != null and texture.get_width() > 0, "%s loads as a texture" % entry)
	_expect(found >= USED.size(), "The detail textures are there (%d)" % found)
	for name_used: String in USED:
		var path: String = DepotKit.DETAIL_DIR % name_used
		_expect(ResourceLoader.exists(path) and load(path) is Texture2D,
			"The depot's %s detail loads (%s)" % [name_used, path])
	_expect(load(DepotKit.PICTOGRAMS) is Texture2D, "The pictogram atlas loads")
	var floor_material: StandardMaterial3D = DepotKit.detailed(Color("6f7272"), "plaster", 4.0, 0.5)
	_expect(floor_material.albedo_texture != null, "The floor's material carries its texture")
	_expect(DepotKit.pictograms().albedo_texture != null, "The pictograms' material carries the atlas")


func _test_missing_texture_falls_back() -> void:
	var tint := Color("6f7272")
	var material: StandardMaterial3D = DepotKit.detailed(tint, "res://assets/textures/detail/no_such_texture.png", 2.0)
	_expect(material.albedo_texture == null, "A texture that doesn't load leaves none on the material")
	_expect(material.albedo_color.r > 0.1 and material.albedo_color.r < 1.0 and material.albedo_color.a == 1.0,
		"...and the flat colour it was given, not white (%s)" % material.albedo_color)
	_expect(DepotKit._missing_textures.has("res://assets/textures/detail/no_such_texture.png"),
		"...which is noted so the warning is given once")
	var again: StandardMaterial3D = DepotKit.detailed(tint, "res://assets/textures/detail/no_such_texture.png", 2.0)
	_expect(again == material, "The same material comes back from the cache")
	# No file, no atlas: the loader's answer for a path that is not there is what the kit sees.
	_expect(DepotKit._texture("res://assets/textures/depot/no_such_atlas.png") == null, "A missing atlas reads as null")


func _test_arrows_lie_flat() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var kit := DepotKit.new(holder)
	# Aimed at a station a metre and a half up and away, from a point on the floor.
	var aim: Vector3 = Vector3(-2.0, 1.3, -8.0).normalized()
	var guide: Dictionary = DepotLabels.paint_arrow(kit, "x", Vector3(-8.5, 0.0, 13.1), aim, Layout.SHOP_PURPLE,
			0.007, 0.6)
	_expect(is_zero_approx((guide.direction as Vector3).y),
		"The guide's direction is along the floor (%s)" % guide.direction)
	var made: Array[MeshInstance3D] = kit.commit("Arrow")
	_expect(made.size() == 1, "One batch for one arrow (%d)" % made.size())
	var vertices: PackedVector3Array = made[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var low: float = 1.0
	var high: float = -1.0
	for vertex: Vector3 in vertices:
		low = minf(low, vertex.y)
		high = maxf(high, vertex.y)
	_expect(vertices.size() > 0 and high - low < 0.0001,
		"Every point of the arrow is at one height (%.4f to %.4f)" % [low, high])
	_expect(low > Layout.FLOOR_TOP + 0.004, "...clear of the paint under it (%.4f)" % low)
	var material := made[0].mesh.surface_get_material(0) as StandardMaterial3D
	_expect(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_texture != null,
		"It is opaque paint with the floor's grain, not a see-through wash")
	holder.free()


func _test_atmosphere_clamps() -> void:
	var atmosphere := DepotAtmosphere.new(null)
	var environment := Environment.new()
	# Values that no blend of this node could have produced, with the camera inside.
	atmosphere.set(&"_blend", 1.0)
	environment.ambient_light_sky_contribution = 1.0
	environment.ambient_light_energy = 9.0
	environment.fog_density = 0.9
	environment.ambient_light_color = Color(1.0, 1.0, 1.0)
	atmosphere.call(&"_adopt", environment)
	var sky: float = float(atmosphere.get(&"_base_sky"))
	var energy: float = float(atmosphere.get(&"_base_energy"))
	var density: float = float(atmosphere.get(&"_base_density"))
	var colour: Color = atmosphere.get(&"_base_colour")
	_expect(sky >= 0.0 and sky <= 1.0, "The recovered sky share stays within 0..1 (%.2f)" % sky)
	_expect(energy >= 0.0 and energy <= DepotAtmosphere.MAX_BASE_ENERGY,
		"The recovered ambient energy is capped (%.2f)" % energy)
	_expect(density >= 0.0 and density <= DepotAtmosphere.MAX_BASE_DENSITY,
		"The recovered fog density is capped (%.3f)" % density)
	_expect(colour.r <= 1.0 and colour.g <= 1.0 and colour.b <= 1.0 and colour.r >= 0.0,
		"The recovered colour stays in range")
	# An outdoor Environment (blend 0) comes back untouched.
	atmosphere.set(&"_blend", 0.0)
	environment.ambient_light_sky_contribution = 0.7
	environment.ambient_light_energy = 0.45
	environment.fog_density = 0.008
	atmosphere.call(&"_adopt", environment)
	_expect(is_equal_approx(float(atmosphere.get(&"_base_sky")), 0.7)
		and is_equal_approx(float(atmosphere.get(&"_base_energy")), 0.45)
		and is_equal_approx(float(atmosphere.get(&"_base_density")), 0.008), "Outdoor values are recovered as they are")
	atmosphere.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

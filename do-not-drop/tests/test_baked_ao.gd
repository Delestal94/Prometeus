extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_baked_ao.gd
##
## Ambient occlusion baked into vertex colours (N-308.1,
## assets/tools/bake_vertex_ao.py; GL Compatibility has no SSAO):
## - the houses, the parked and depot vehicles and the big props carry it,
##   on every surface, and LowpolyMaterials multiplies it into the albedo
##   (Godot's glTF importer doesn't);
## - vegetation never does: it's instanced by the thousand;
## - glass, frames and lamps stay untouched (white), and the darkest corner
##   is no darker than the bake's FLOOR;
## - the bake keeps models light: under 2x a model's own vertex budget;
## - the barn's red walls keep enough green and blue that the cold light on a
##   wall turned from the sun doesn't leave them black (N-318.2).

const BAKED: Array[String] = [
	"res://assets/models/architecture/sm_arch_delivery_house_cottage.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_cabin.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_bungalow.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_two_story.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_farmhouse.glb",
	"res://assets/models/architecture/sm_arch_barn.glb",
	"res://assets/models/vehicles/sm_vehicle_parked_hatchback.glb",
	"res://assets/models/vehicles/sm_vehicle_parked_pickup.glb",
	"res://assets/models/vehicles/sm_vehicle_parked_sedan_refined.glb",
	"res://assets/models/vehicles/sm_vehicle_competitor_van.glb",
	"res://assets/models/vehicles/sm_vehicle_tractor.glb",
	"res://assets/models/vehicles/sm_vehicle_tow_crane.glb",
	"res://assets/models/environment/props/sm_env_prop_bus_stop.glb",
	"res://assets/models/environment/landmarks/sm_env_landmark_windmill.glb",
	"res://assets/models/environment/landmarks/sm_env_landmark_water_tower.glb",
]
const NEVER: Array[String] = [
	"res://assets/models/environment/forest/sm_env_forest_oak.glb",
	"res://assets/models/environment/forest/sm_env_forest_pine_tall.glb",
	"res://assets/models/environment/forest/sm_env_forest_fern.glb",
]
const FLOOR: float = 0.62
const UNTOUCHED: Array[String] = ["window", "glass", "lamp", "lamp_glass", "trim"]
const MAX_VERTICES: int = 16000

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path: String in BAKED:
		var model: Node3D = (load(path) as PackedScene).instantiate()
		LowpolyMaterials.apply(model)
		var coloured: int = 0
		var plain: int = 0
		var vertices: int = 0
		var darkest: float = 1.0
		var untouched_dark: int = 0
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (node as MeshInstance3D).mesh
			if mesh == null:
				continue
			for surface: int in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var colours: Variant = arrays[Mesh.ARRAY_COLOR]
				if colours == null or (colours as PackedColorArray).is_empty():
					plain += 1
					continue
				coloured += 1
				var material := (node as MeshInstance3D).get_surface_override_material(surface) as BaseMaterial3D
				if material == null:
					material = mesh.surface_get_material(surface) as BaseMaterial3D
				_expect(material != null and material.vertex_color_use_as_albedo, "%s: the baked colour is used (%s)" % [path.get_file(), material.resource_name if material != null else "none"])
				var name: String = (mesh.surface_get_material(surface) as Material).resource_name.get_slice(".", 0) if mesh.surface_get_material(surface) != null else ""
				for colour: Color in colours as PackedColorArray:
					darkest = minf(darkest, colour.r)
					if name in UNTOUCHED and colour.r < 0.99:
						untouched_dark += 1
		_expect(coloured > 0 and plain == 0, "%s carries the bake on every surface (%d with, %d without)" % [path.get_file(), coloured, plain])
		_expect(darkest >= FLOOR - 0.02, "%s: no corner darker than the floor (%.2f)" % [path.get_file(), darkest])
		_expect(untouched_dark == 0, "%s: glass, frames and lamps stay clear (%d darkened corners)" % [path.get_file(), untouched_dark])
		_expect(vertices < MAX_VERTICES, "%s stays light (%d vertices)" % [path.get_file(), vertices])
		model.free()
	for path: String in NEVER:
		var plant: Node3D = (load(path) as PackedScene).instantiate()
		for node: Node in plant.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (node as MeshInstance3D).mesh
			for surface: int in range(mesh.get_surface_count() if mesh != null else 0):
				_expect((mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR) == 0, "%s is never baked (instanced by the thousand)" % path.get_file())
		plant.free()
	_expect_barn_catches_cold_light()
	if _failures == 0:
		print("PASS: houses, vehicles and big props carry baked AO, used as albedo; plants never do")
	quit(_failures)


## The barn's red walls, dressed: with the bake and the detail on, enough
## green and blue left in them that the cold light on a wall turned from the
## sun (sky ambient, moonlight) still shows it. Authored, 0.06 green and 0.04
## blue (linear) went black at night (N-318.2).
func _expect_barn_catches_cold_light() -> void:
	var barn: Node3D = (load("res://assets/models/architecture/sm_arch_barn.glb") as PackedScene).instantiate()
	LowpolyMaterials.apply(barn)
	var walls: int = 0
	var dim: int = 0
	for node: Node in barn.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		for surface: int in range(instance.mesh.get_surface_count() if instance.mesh != null else 0):
			var material := instance.get_surface_override_material(surface) as BaseMaterial3D
			if material == null or material.resource_name != "barn_red":
				continue
			walls += 1
			var linear: Color = material.albedo_color.srgb_to_linear()
			if linear.g < 0.1 or linear.b < 0.06:
				dim += 1
	_expect(walls > 0 and dim == 0,
		"The barn's red walls keep some green and blue for the cold light (%d walls, %d too dark)" % [walls, dim])
	barn.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

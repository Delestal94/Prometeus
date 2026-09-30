extends TerrainField
## Take My Package's terrain on the route_gen module's TerrainField
## (docs/modulos.md): the module carves, levels and builds the ground; this
## file is the game's terrain shader with its four detail maps, and the
## rocky waterfalls at both ends of a river (RiverFalls), so the water comes
## from somewhere and goes somewhere instead of sitting in an isolated pool.

const RiverFalls = preload("res://scripts/gameplay/route/route_river_falls.gd")
const SHADER: Shader = preload("res://shaders/route_terrain.gdshader")
const DETAIL_FORMAT: String = "res://assets/textures/detail/tx_detail_%s_512.png"


func _terrain_shader() -> Shader:
	return SHADER


func _configure_material(material: ShaderMaterial) -> void:
	for surface: String in ["asphalt", "earth", "grass", "gravel"]:
		material.set_shader_parameter(surface + "_detail", load(DETAIL_FORMAT % surface))


func _decorate_river(river: Dictionary, reach: float) -> void:
	RiverFalls.build(self, river, reach)

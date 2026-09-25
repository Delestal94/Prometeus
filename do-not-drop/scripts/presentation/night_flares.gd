extends RefCounted
class_name NightFlares
## A soft halo round every lamp after dark (tareas de Nacho N-304): the
## village's street lamps and the parked cars' lamps, whose glass already
## glows (LowpolyMaterials.light_up()). A halo is a camera-facing quad with a
## radial fade, added on top of what's behind it; all of a route's halos are
## one MultiMesh, so they cost one draw call. At dusk they're half as bright.
##
## route.gd builds it right after dressing and before the batcher folds the
## dressing into batches (the lamps are still nodes then, and can be found).

const STREET_LAMP: String = "res://assets/models/environment/props/sm_env_prop_street_lamp_refined.glb"
const LAMP_HALO_SIZE: float = 1.5
const CAR_HALO_SIZE: float = 0.55
const HALO_COLOR := Color(1.0, 0.82, 0.55)
const DRAW_DISTANCE: float = 260.0


## Where the halos go, in `route`'s space: [position, size] pairs.
static func halo_spots(route: Node3D) -> Array:
	var spots: Array = []
	var to_route: Transform3D = route.global_transform.affine_inverse()
	for node: Node in route.find_children("*", "Node3D", true, false):
		if not node.has_meta(&"rule"):
			continue
		var piece := node as Node3D
		if piece.scene_file_path == STREET_LAMP:
			for mesh: Node in piece.find_children("*", "MeshInstance3D", true, false):
				if _has_material(mesh as MeshInstance3D, "lamp_glass"):
					var box: AABB = (mesh as MeshInstance3D).get_aabb()
					spots.append([to_route * ((mesh as MeshInstance3D).global_transform * box.get_center()), LAMP_HALO_SIZE])
		elif piece.get_meta(&"rule") == &"parked_vehicle":
			for mesh: Node in piece.find_children("Light*", "MeshInstance3D", true, false):
				var box: AABB = (mesh as MeshInstance3D).get_aabb()
				spots.append([to_route * ((mesh as MeshInstance3D).global_transform * box.get_center()), CAR_HALO_SIZE])
	return spots


## The halos for the current LowpolyMaterials.night_level, or null by day or
## when there's nothing to light.
static func build(route: Node3D) -> MultiMeshInstance3D:
	var level: float = LowpolyMaterials.night_level
	var spots: Array = halo_spots(route)
	if level <= 0.0 or spots.is_empty():
		return null
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material(level)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = spots.size()
	for index: int in range(spots.size()):
		var spot: Array = spots[index]
		multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * float(spot[1])), spot[0]))
	var node := MultiMeshInstance3D.new()
	node.name = "NightFlares"
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = DRAW_DISTANCE
	return node


static func _material(level: float) -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(HALO_COLOR, 0.9))
	gradient.set_color(1, Color(HALO_COLOR, 0.0))
	gradient.add_point(0.25, Color(HALO_COLOR, 0.45))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = Color(1.0, 1.0, 1.0, level)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = false
	material.disable_fog = false
	return material


static func _has_material(mesh: MeshInstance3D, key: String) -> bool:
	if mesh.mesh == null:
		return false
	for surface: int in range(mesh.mesh.get_surface_count()):
		var material: Material = mesh.get_surface_override_material(surface)
		if material == null:
			material = mesh.mesh.surface_get_material(surface)
		if material != null and material.resource_name.begins_with(key):
			return true
	return false

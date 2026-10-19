class_name GelSkinApplier
extends RefCounted
## Copies one skin resource into per-instance shader parameters (S-311.66).


static func apply(target: GeometryInstance3D, definition: Resource) -> bool:
	if target == null or definition == null or not definition.call(&"is_valid"):
		return false
	target.set_instance_shader_parameter(&"gel_color", definition.get(&"color"))
	var surface := Vector4(
		definition.get(&"absorption"),
		definition.get(&"shine"),
		float(definition.get(&"interior_mode")),
		definition.get(&"interior_amount")
	)
	var color: Color = definition.get(&"interior_color")
	var interior := Vector4(color.r, color.g, color.b, definition.get(&"interior_scale"))
	target.set_instance_shader_parameter(&"gel_skin_surface", surface)
	target.set_instance_shader_parameter(&"gel_interior", interior)
	return true

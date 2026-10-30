class_name GelSkinApplier
extends RefCounted
## Copies one skin resource into the two packed per-instance skin parameters.

const ANIMATION_MODE_OFFSET: int = GelSkinDefinition.InteriorMode.BIG_BUBBLES


static func apply(target: GeometryInstance3D, definition: Resource) -> bool:
	if target == null or definition == null or not definition.call(&"is_valid"):
		return false
	target.set_instance_shader_parameter(&"gel_color", definition.get(&"color"))
	var mode: int = int(definition.get(&"interior_mode"))
	var animation_mode: int = int(definition.get(&"animation_mode"))
	if animation_mode != GelSkinDefinition.AnimationMode.NONE:
		mode = ANIMATION_MODE_OFFSET + animation_mode
	var current_surface: Variant = target.get_instance_shader_parameter(&"gel_skin_surface")
	var thickness_offset: float = 0.0
	if current_surface is Vector4:
		thickness_offset = clampf(
			(current_surface as Vector4).z - roundf((current_surface as Vector4).z),
			-GelBodyShaper.THICKNESS_MODE_PACK_SCALE,
			GelBodyShaper.THICKNESS_MODE_PACK_SCALE
		)
	var surface := Vector4(
		definition.get(&"absorption"),
		definition.get(&"shine"),
		float(mode) + thickness_offset,
		definition.get(&"interior_amount")
	)
	var color: Color = definition.get(&"interior_color")
	var interior := Vector4(color.r, color.g, color.b, definition.get(&"interior_scale"))
	target.set_instance_shader_parameter(&"gel_skin_surface", surface)
	target.set_instance_shader_parameter(&"gel_interior", interior)
	return true

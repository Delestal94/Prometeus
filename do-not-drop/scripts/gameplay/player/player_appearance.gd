class_name PlayerAppearance
extends RefCounted
## Helpers for the player's rigged body: finding its parts, its render layers
## and shadows, and tinting the shirt. Stateless -- the Player decides what
## colour and layers, these apply them.

const GEL_MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body.tres")
const GEL_OPAQUE_MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body_opaque.tres")
const TEAM_COLOR_STEPS: int = 31
const TEAM_COLOR_RADIX: int = TEAM_COLOR_STEPS + 1


## Every visual under `node` onto `layers` (RenderLayers.LOCAL_BODY for your
## own body, which your own cameras leave out; WORLD for everyone else's).
static func set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child: Node in node.get_children():
		set_layers(child, layers)


static func enable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child: Node in node.get_children():
		enable_shadows(child)


## Sets the three player-owned gel controls on the geometry instance. The
## ShaderMaterial remains shared, so changing one player cannot affect another.
static func set_gel_look(
	body: Node,
	color: Color,
	opacity: float = 1.0,
	brightness: float = 1.0
) -> void:
	var mesh_instance: MeshInstance3D = find_mesh_instance(body)
	if mesh_instance == null:
		return
	mesh_instance.set_instance_shader_parameter(&"gel_color", color)
	mesh_instance.set_instance_shader_parameter(&"gel_opacity", clampf(opacity, 0.0, 1.0))
	var packed: Variant = mesh_instance.get_instance_shader_parameter(&"gel_brightness")
	var team_color := unpack_gel_team_color(float(packed) if packed is float else 1.0)
	mesh_instance.set_instance_shader_parameter(
		&"gel_brightness",
		pack_gel_team_color(brightness, team_color)
	)


## Adds the player's shirt colour at the gel's Fresnel edge. The colour is
## quantized into the existing brightness slot so the shared shaders stay at
## Godot's limit of sixteen per-instance uniforms.
static func set_gel_team_accent(body: Node, color: Color) -> void:
	var mesh_instance: MeshInstance3D = find_mesh_instance(body)
	if mesh_instance == null or not _uses_gel_shader(mesh_instance):
		return
	var packed: Variant = mesh_instance.get_instance_shader_parameter(&"gel_brightness")
	var current: float = float(packed) if packed is float else 1.0
	mesh_instance.set_instance_shader_parameter(
		&"gel_brightness",
		pack_gel_team_color(unpack_gel_brightness(current), color)
	)


static func pack_gel_team_color(brightness: float, color: Color) -> float:
	var safe_brightness := clampf(brightness, 0.5, 1.5)
	if color.a <= 0.0:
		return safe_brightness
	var red := roundi(clampf(color.r, 0.0, 1.0) * TEAM_COLOR_STEPS)
	var green := roundi(clampf(color.g, 0.0, 1.0) * TEAM_COLOR_STEPS)
	var blue := roundi(clampf(color.b, 0.0, 1.0) * TEAM_COLOR_STEPS)
	var color_code := red + green * TEAM_COLOR_RADIX + blue * TEAM_COLOR_RADIX * TEAM_COLOR_RADIX
	return float((color_code + 1) * 2) + safe_brightness


static func unpack_gel_team_color(packed: float) -> Color:
	if packed < 2.0:
		return Color.TRANSPARENT
	var color_code := maxi(floori(packed * 0.5) - 1, 0)
	var red := color_code % TEAM_COLOR_RADIX
	var green := floori(float(color_code) / TEAM_COLOR_RADIX) % TEAM_COLOR_RADIX
	var blue := floori(float(color_code) / (TEAM_COLOR_RADIX * TEAM_COLOR_RADIX))
	return Color(
		float(red) / TEAM_COLOR_STEPS,
		float(green) / TEAM_COLOR_STEPS,
		float(blue) / TEAM_COLOR_STEPS,
		1.0
	)


static func unpack_gel_brightness(packed: float) -> float:
	return fmod(packed, 2.0) if packed >= 2.0 else clampf(packed, 0.5, 1.5)


static func _uses_gel_shader(mesh_instance: MeshInstance3D) -> bool:
	var material := mesh_instance.material_override as ShaderMaterial
	return material != null and material.shader != null \
		and material.shader.code.contains("instance uniform float gel_brightness")


## Swaps between two shared resources. The opaque material has no transparent
## pass or screen texture, while keeping the same per-player instance controls.
static func set_gel_material(body: Node, opaque: bool) -> void:
	var mesh_instance: MeshInstance3D = find_mesh_instance(body)
	if mesh_instance != null:
		mesh_instance.material_override = GEL_OPAQUE_MATERIAL if opaque else GEL_MATERIAL


## Tints the shirt: surface 0 is the T-shirt; its collar/hem trim follows a
## shade darker. The imported material is duplicated per instance (a surface
## override, not a mutation of the shared glTF resource), so tinting one
## player's shirt never bleeds into every other instance.
static func tint_shirt(body: Node, color: Color) -> void:
	var mesh_instance: MeshInstance3D = find_mesh_instance(body)
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	for surface: int in mesh_instance.mesh.get_surface_count():
		var source: Material = mesh_instance.mesh.surface_get_material(surface)
		var tint: Color = color
		if surface != 0:
			if source == null or source.resource_name != "ShirtTrim":
				continue
			tint = color.darkened(0.18)
		var shirt := (source.duplicate() if source != null else StandardMaterial3D.new()) as StandardMaterial3D
		shirt.albedo_color = tint
		# The GLB bakes occlusion into vertex colour, but Godot's importer
		# leaves this flag off on the first surface (the shirt) only.
		shirt.vertex_color_use_as_albedo = true
		mesh_instance.set_surface_override_material(surface, shirt)


static func find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child: Node in node.get_children():
		var found: MeshInstance3D = find_mesh_instance(child)
		if found != null:
			return found
	return null


static func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child: Node in node.get_children():
		var found: AnimationPlayer = find_animation_player(child)
		if found != null:
			return found
	return null


static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = find_skeleton(child)
		if found != null:
			return found
	return null

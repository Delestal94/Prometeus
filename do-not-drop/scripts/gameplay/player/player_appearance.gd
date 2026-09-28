class_name PlayerAppearance
extends RefCounted
## Helpers for the player's rigged body: finding its parts, its render layers
## and shadows, and tinting the shirt. Stateless -- the Player decides what
## colour and layers, these apply them.


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

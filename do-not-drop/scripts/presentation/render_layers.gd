extends RefCounted
## These are visual layers, independent of physics collision layers.
const WORLD: int = 1
const LOCAL_BODY: int = 2
const VIEWMODEL: int = 4


static func configure_first_person(camera: Camera3D) -> void:
	camera.cull_mask &= ~LOCAL_BODY
	for child: Node in camera.get_children():
		if child is MeshInstance3D:
			child.layers = VIEWMODEL
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func show_viewmodel(camera: Camera3D, enabled: bool) -> void:
	for child: Node in camera.get_children():
		if child is MeshInstance3D:
			child.visible = enabled

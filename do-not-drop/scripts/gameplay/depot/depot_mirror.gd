class_name DepotMirror
extends Node3D
## A working mirror (pedido del usuario, 2026-09-24): the full-length one in
## the lockers, so you can see your uniform. The first-person camera never
## draws your own body (RenderLayers.LOCAL_BODY), so this is the only place
## you get to look at yourself.
##
## Planar reflection that works on GL Compatibility: a second camera sits at
## the viewer's camera mirrored through the glass, looks straight out of the
## wall, and its frustum is cut to the glass rectangle with the near plane on
## the glass itself -- so nothing behind the wall gets in. It renders into a
## SubViewport shown on the glass, flipped left-right.
##
## The glass faces local +Z; its centre is this node's origin. It only
## renders while someone's camera is close and in front of it, after one
## first picture of the room (FIRST_EYE) so it never shows black from afar.

const RenderLayers = preload("res://scripts/presentation/render_layers.gd")
## The glass itself stays out of its own reflection.
const GLASS_LAYER: int = 1 << 19
const RESOLUTION: int = 900
const ACTIVE_DISTANCE: float = 9.0
## The one picture taken before anyone comes near: seen from eye height a
## couple of steps in front of the glass, once the level's light and
## weather have settled.
const FIRST_EYE := Vector3(0.0, 0.55, 2.0)
const FIRST_PICTURE_DELAY: float = 0.5

@export var glass_size := Vector2(0.9, 1.9)

var viewport: SubViewport
var reflection_camera: Camera3D
var glass: MeshInstance3D
var _drawn: bool = false
var _first_picture_in: float = FIRST_PICTURE_DELAY


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "Reflection"
	viewport.size = Vector2i(roundi(RESOLUTION * glass_size.x / glass_size.y), RESOLUTION)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	reflection_camera = Camera3D.new()
	reflection_camera.name = "ReflectionCamera"
	reflection_camera.projection = Camera3D.PROJECTION_FRUSTUM
	reflection_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	reflection_camera.far = 40.0
	# The world and your own body, which your own cameras leave out.
	reflection_camera.cull_mask = RenderLayers.WORLD | RenderLayers.LOCAL_BODY
	# Placed every frame in _process: interpolating it between physics ticks
	# would draw it where it was a tick ago (at the world origin, at first).
	reflection_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(reflection_camera)

	var quad := QuadMesh.new()
	quad.size = glass_size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	# The picture is already lit, fogged and tonemapped: skip the fog, and
	# take back the main camera's second tonemap pass (~12% too bright).
	material.disable_fog = true
	material.albedo_color = Color(0.85, 0.88, 0.89)  # with a faint cool tint of glass
	# Left-right flip: the reflection camera looks back out of the wall.
	material.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	material.uv1_offset = Vector3(1.0, 0.0, 0.0)
	glass = MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = quad
	glass.material_override = material
	glass.layers = GLASS_LAYER
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)


func _process(delta: float) -> void:
	var viewer: Camera3D = get_viewport().get_camera_3d()
	var active: bool = viewer != null and viewer != reflection_camera and update_reflection(viewer.global_position)
	if not active and not _drawn:
		# Nobody near yet: one picture of the room, so from across the depot
		# the glass isn't a black hole in the wall.
		_first_picture_in -= delta
		if _first_picture_in > 0.0:
			return
		update_reflection(to_global(FIRST_EYE))
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_drawn = true
		return
	_drawn = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED


## Puts the reflection camera where `eye` (global) appears to be behind the
## glass. Returns false -- nothing worth rendering -- when the eye is behind
## the mirror, too close to the plane or too far away.
func update_reflection(eye: Vector3) -> bool:
	var frame: Transform3D = global_transform.orthonormalized()
	var local: Vector3 = frame.affine_inverse() * eye
	if local.z < 0.05 or local.length() > ACTIVE_DISTANCE:
		return false
	# Mirrored through the glass, looking out along +Z: camera -Z is the
	# glass normal, so the camera's right is the glass's -X.
	var mirrored := Vector3(local.x, local.y, -local.z)
	reflection_camera.global_transform = frame * Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3.UP, Vector3(0.0, 0.0, -1.0)), mirrored)
	# The glass centre as seen from there: sideways flipped, down by the
	# eye height, `local.z` straight ahead -- the near plane on the glass.
	reflection_camera.set_frustum(glass_size.y, Vector2(local.x, -local.y), local.z, reflection_camera.far)
	return true

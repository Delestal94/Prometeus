class_name PressPhoto
extends RefCounted
## A small still of a 3D world, taken from an angle of its own (not through
## the player's eyes), and the halftone screen that prints it like a
## newspaper photo.
##
## framing() is pure: a three-quarter view of a subject from one side. capture()
## renders that pose once into a small SubViewport that shares the world of
## the node it is given, reads the image back and frees the viewport: one
## extra small draw per photo, nothing every frame. Where nothing is drawn
## (headless) it returns null at once instead of waiting for a frame that
## never comes.
##
## halftone.gdshader is a canvas_item shader for the TextureRect that shows
## the photo: grey, contrasty, with a dot screen at 45 degrees whose pitch is
## in pixels of the canvas it is drawn on, so any photo size prints the same.

const HALFTONE: Shader = preload("res://modules/press_photo/halftone.gdshader")
const DEFAULT_SIZE: Vector2i = Vector2i(384, 216)


## A three-quarter view of `subject` taken from the side `facing` points to
## (flattened onto the ground), turned `yaw_degrees` around the vertical,
## `distance` away on the ground and `height` above it, aimed `aim_height`
## over the subject. {at, look}.
static func framing(subject: Vector3, facing: Vector3, distance: float = 6.0, height: float = 2.0,
		yaw_degrees: float = 35.0, aim_height: float = 0.6) -> Dictionary:
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.BACK
	var direction: Vector3 = flat.normalized().rotated(Vector3.UP, deg_to_rad(yaw_degrees))
	return {"at": subject + direction * distance + Vector3.UP * height, "look": subject + Vector3.UP * aim_height}


## Whether this display draws at all: capture() returns null where it doesn't.
static func can_capture() -> bool:
	return DisplayServer.get_name() != "headless"


## The world `host` sees, from `pose` ({at, look}), as a `size` image. Await
## it; null when there is nothing to draw with or no world to draw.
static func capture(host: Node, pose: Dictionary, size: Vector2i = DEFAULT_SIZE, fov: float = 50.0,
		cull_mask: int = 0xFFFFF) -> Texture2D:
	if host == null or not host.is_inside_tree() or not can_capture():
		return null
	var world: World3D = host.get_viewport().find_world_3d()
	if world == null:
		return null
	var lens := SubViewport.new()
	lens.name = "PressPhotoLens"
	lens.size = size
	lens.world_3d = world
	lens.msaa_3d = Viewport.MSAA_2X
	lens.render_target_update_mode = SubViewport.UPDATE_ONCE
	var camera := Camera3D.new()
	camera.fov = fov
	camera.cull_mask = cull_mask
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	lens.add_child(camera)
	host.add_child(lens)
	var at: Vector3 = pose.get("at", Vector3.ZERO)
	var look: Vector3 = pose.get("look", at + Vector3.FORWARD)
	if not at.is_equal_approx(look):
		var up: Vector3 = Vector3.UP if absf((look - at).normalized().dot(Vector3.UP)) < 0.98 else Vector3.BACK
		camera.look_at_from_position(at, look, up)
	camera.make_current()
	var image: Image = null
	for _attempt: int in 2:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(lens):
			return null
		image = lens.get_texture().get_image()
		if image != null and not image.is_empty():
			break
	lens.queue_free()
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


## A material that prints a texture as a halftone photo on paper of `stock`
## colour in `ink`, with dots every `pitch` pixels of the target canvas.
static func halftone_material(stock: Color, ink: Color, pitch: float = 5.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = HALFTONE
	material.set_shader_parameter("stock", Vector3(stock.r, stock.g, stock.b))
	material.set_shader_parameter("print_ink", Vector3(ink.r, ink.g, ink.b))
	material.set_shader_parameter("pitch", pitch)
	return material

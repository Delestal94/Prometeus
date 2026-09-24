extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_depot_mirror.gd
##
## The lockers' mirror (depot_mirror.gd):
##   - the depot hangs it on the lockers' wall, glass facing into the room;
##   - the reflection camera sits at the viewer mirrored through the glass,
##     looks back out, and its frustum is exactly the glass (the corners of
##     the glass land on the corners of the picture, flipped left-right);
##   - it sees your own body but not the glass;
##   - it only renders while someone is close and in front of it, after one
##     first picture of the room so it never shows black from afar.

const RenderLayers = preload("res://scripts/presentation/render_layers.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# In the depot: on the right-hand wall, by the lockers, facing -X.
	var depot := Depot.new()
	depot.stock_extra_packages = false
	root.add_child(depot)
	await process_frame
	var hung: DepotMirror = depot.get_node_or_null(^"Mirror") as DepotMirror
	_expect(hung != null, "The depot has a working mirror")
	if hung != null:
		_expect(hung.position.x > Depot.HALF_WIDTH - 0.2 and hung.position.x < Depot.HALF_WIDTH - 0.1, "The mirror hangs on the side wall, in front of its lining (x %.2f)" % hung.position.x)
		_expect(hung.position.z - hung.glass_size.x * 0.5 > 17.95 and hung.position.z + hung.glass_size.x * 0.5 < 19.05, "The glass fits between the lockers and the column (z %.2f)" % hung.position.z)
		var facing: Vector3 = hung.transform.basis.z
		_expect(facing.distance_to(Vector3.LEFT) < 0.01, "The glass faces into the room (%s)" % facing)
		_expect(hung.position.y - hung.glass_size.y * 0.5 < 0.3 and hung.position.y + hung.glass_size.y * 0.5 > 1.9, "Full length: feet to above the head")
	depot.queue_free()

	# The reflection geometry, on a mirror at an arbitrary pose.
	var mirror := DepotMirror.new()
	mirror.position = Vector3(3.0, 1.1, -2.0)
	mirror.rotation.y = 0.7
	root.add_child(mirror)
	await process_frame
	_expect(mirror.reflection_camera.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "The reflection camera is placed every frame, not interpolated between ticks")
	# Before anyone comes near: one picture of the room, from in front of it.
	var deadline: int = Time.get_ticks_msec() + int((DepotMirror.FIRST_PICTURE_DELAY + 1.0) * 1000.0)
	var drew_once: bool = false
	while not drew_once and Time.get_ticks_msec() < deadline:
		await process_frame
		drew_once = mirror.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE
	_expect(drew_once, "Before anyone comes near, the mirror draws the room once instead of showing black")
	var first_eye: Vector3 = mirror.to_global(Vector3(DepotMirror.FIRST_EYE.x, DepotMirror.FIRST_EYE.y, -DepotMirror.FIRST_EYE.z))
	_expect(mirror.reflection_camera.global_position.distance_to(first_eye) < 0.001, "That picture is the room seen from in front of the glass")
	var eye_local := Vector3(0.3, 0.55, 2.0)
	var eye: Vector3 = mirror.to_global(eye_local)
	_expect(mirror.update_reflection(eye), "Renders for a viewer in front of the glass")
	var camera: Camera3D = mirror.reflection_camera
	var expected: Vector3 = mirror.to_global(Vector3(eye_local.x, eye_local.y, -eye_local.z))
	_expect(camera.global_position.distance_to(expected) < 0.001, "The camera sits at the viewer mirrored through the glass")
	var forward: Vector3 = -camera.global_basis.z
	_expect(forward.distance_to(mirror.global_basis.z) < 0.001, "The camera looks back out through the glass")
	_expect(absf(camera.near - eye_local.z) < 0.001, "The near plane lies on the glass, so the wall behind never shows")
	# Through the camera's own projection (unproject_position is off for a
	# frustum camera inside a SubViewport): corners at the picture's corners.
	var half: Vector2 = mirror.glass_size * 0.5
	var ndc := func(local_point: Vector3) -> Vector2:
		var in_camera: Vector3 = camera.global_transform.affine_inverse() * mirror.to_global(local_point)
		var clip: Vector4 = camera.get_camera_projection() * Vector4(in_camera.x, in_camera.y, in_camera.z, 1.0)
		return Vector2(clip.x, clip.y) / clip.w
	var top_left: Vector2 = ndc.call(Vector3(-half.x, half.y, 0.0))
	var bottom_right: Vector2 = ndc.call(Vector3(half.x, -half.y, 0.0))
	_expect(top_left.distance_to(Vector2(1.0, 1.0)) < 0.02, "The glass's top-left is the picture's top-right, flipped back by the UVs (%s)" % top_left)
	_expect(bottom_right.distance_to(Vector2(-1.0, -1.0)) < 0.02, "The glass's bottom-right is the picture's bottom-left (%s)" % bottom_right)
	var material := mirror.glass.material_override as StandardMaterial3D
	_expect(material.uv1_scale.x < 0.0, "The glass flips the picture left-right")

	# What it sees.
	_expect(camera.cull_mask & RenderLayers.LOCAL_BODY != 0, "The mirror shows your own body")
	_expect(camera.cull_mask & mirror.glass.layers == 0, "The glass stays out of its own reflection")

	# Only when it matters.
	_expect(not mirror.update_reflection(mirror.to_global(Vector3(0.0, 0.0, -1.0))), "Nothing to render from behind the wall")
	_expect(not mirror.update_reflection(mirror.to_global(Vector3(0.0, 0.0, 30.0))), "Nothing to render from across the depot")
	var viewer := Camera3D.new()
	root.add_child(viewer)
	viewer.global_position = mirror.to_global(Vector3(0.0, 0.0, 30.0))
	viewer.make_current()
	await process_frame
	_expect(mirror.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "The reflection stops rendering when nobody is near")
	viewer.global_position = eye
	await process_frame
	_expect(mirror.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "The reflection renders when someone stands in front")

	if _failures == 0:
		print("test_depot_mirror: PASS")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

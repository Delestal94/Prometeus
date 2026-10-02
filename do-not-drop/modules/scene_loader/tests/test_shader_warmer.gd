extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/scene_loader/tests/test_shader_warmer.gd
##
## ShaderWarmer on its own (N-409): collect() keeps one sample per distinct way
## of drawing -- a surface's material, a multimesh's instancing, a particle
## system, a 3D label -- hidden nodes included and repeats skipped; warm()
## draws them all in batches in front of the camera (a temporary one if there
## is none), leaves nothing behind, reports its progress and is done.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "Scene"
	root.add_child(scene)
	var red := StandardMaterial3D.new()
	var blue := StandardMaterial3D.new()
	var box := BoxMesh.new()
	# Two boxes in red (one sample), one in blue, one hidden in blue (same as
	# the visible blue one), one hidden in a material seen nowhere else.
	_mesh(scene, box, red, true)
	_mesh(scene, box, red, true)
	_mesh(scene, box, blue, true)
	_mesh(scene, box, blue, false)
	var hidden_only := StandardMaterial3D.new()
	var deep := Node3D.new()
	deep.visible = false
	scene.add_child(deep)
	_mesh(deep, SphereMesh.new(), hidden_only, true)
	# Instanced red boxes draw another way than plain red boxes.
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = 3
	var instances := MultiMeshInstance3D.new()
	instances.multimesh = multimesh
	instances.material_override = red
	scene.add_child(instances)
	var particles := GPUParticles3D.new()
	particles.process_material = ParticleProcessMaterial.new()
	particles.draw_pass_1 = box
	scene.add_child(particles)
	var label := Label3D.new()
	label.text = "A-1"
	scene.add_child(label)

	var warmer := ShaderWarmer.new()
	root.add_child(warmer)
	warmer.collect(scene)
	warmer.collect(scene)
	# red, blue, hidden_only, multimesh red, particles, label
	_expect(warmer.samples.size() == 6,
		"One sample per way of drawing, hidden included (got %d)" % warmer.samples.size())
	_expect(is_zero_approx(warmer.progress()), "Nothing warmed yet")

	warmer.per_frame = 2
	var children_before: int = warmer.get_child_count()
	warmer.warm()
	var frames: int = 0
	var most_children: int = 0
	while not warmer.done and frames < 200:
		most_children = maxi(most_children, warmer.get_child_count())
		await process_frame
		frames += 1
	_expect(warmer.done and warmer.warmed == warmer.samples.size(), "Every sample is drawn (%d frames)" % frames)
	_expect(is_equal_approx(warmer.progress(), 1.0), "Progress ends at 1")
	_expect(most_children > children_before, "The copies are drawn under the warmer")
	await process_frame
	await process_frame
	var left: int = 0
	for child: Node in warmer.get_children():
		left += 0 if child.is_queued_for_deletion() else 1
	_expect(left == 0, "No copy (or temporary camera) is left behind (%d)" % left)
	_expect(warmer.per_frame >= 1 and warmer.per_frame <= warmer.max_per_frame, "The batch stays within its bounds")

	var empty := ShaderWarmer.new()
	root.add_child(empty)
	empty.warm()
	_expect(empty.done and is_equal_approx(empty.progress(), 1.0), "Nothing to warm is done at once")

	if _failures == 0:
		print("PASS: every way of drawing is collected once and drawn behind the cover")
	quit(_failures)


func _mesh(parent: Node, mesh: Mesh, material: Material, visible: bool) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.visible = visible
	parent.add_child(instance)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

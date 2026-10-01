class_name ShaderWarmer
extends Node3D
## Draws every material of a scene once, a few per frame, so their shaders
## compile behind a loading cover instead of the first time the player sees
## them. GL Compatibility compiles a shader the first time something draws
## with it, blocking that frame (no ubershaders, no pipeline precompile): a
## level's first draw, a road coming into view, a trap's effect going off --
## each a 50-300 ms hitch, worse on integrated GPUs with weak CPUs.
##
## collect() walks a node tree, visible or not, and keeps one sample per
## distinct way of drawing: a mesh surface's material and vertex format, a
## multimesh's instancing flags, a particle system, a 3D label or sprite.
## warm() then shows tiny copies of them in a grid right in front of the
## active camera -- in the same world, under the same lights, fog and
## shadows, so the variants that compile are the ones the game will use --
## a batch per frame, growing while frames stay short and shrinking when a
## batch costs too much. The cover (a CanvasLayer) hides them.
##
## Portable module (docs/modulos.md): nothing about any game.

## Ways of drawing found by collect(), in the order they will be warmed.
var samples: Array[Dictionary] = []
## How many of them warm() has drawn so far.
var warmed: int = 0
## True once warm() is over.
var done: bool = false
## Copies shown per frame to start with; it adapts (see warm()).
var per_frame: int = 6
var max_per_frame: int = 48
## A frame longer than this halves the batch; one shorter than a third of
## it doubles it.
var frame_budget_seconds: float = 0.07
## How far in front of the camera the grid sits, and how big each copy is.
var distance: float = 1.5
var item_size: float = 0.06

var _seen: Dictionary = {}
## Off-tree copies of particles and labels, kept until this node goes.
var _kept: Array[Node] = []


## 0..1 of the samples drawn.
func progress() -> float:
	return 1.0 if samples.is_empty() else float(warmed) / float(samples.size())


## Adds one sample per distinct way of drawing found under `root` (hidden
## nodes included). Can be called for several roots; repeats are skipped.
func collect(root: Node) -> void:
	if root == null:
		return
	_collect_node(root)
	for child: Node in root.find_children("*", "", true, false):
		_collect_node(child)


## Draws every sample once, a batch per frame. Needs a current Camera3D in
## this node's viewport; without one it makes a temporary one.
func warm() -> void:
	var tree: SceneTree = get_tree()
	var camera: Camera3D = get_viewport().get_camera_3d()
	var own_camera: Camera3D = null
	if camera == null:
		own_camera = Camera3D.new()
		own_camera.name = "WarmCamera"
		add_child(own_camera)
		own_camera.make_current()
		camera = own_camera
	var last_usec: int = Time.get_ticks_usec()
	while warmed < samples.size():
		var batch: Array[Node3D] = []
		var count: int = mini(per_frame, samples.size() - warmed)
		for index: int in count:
			var copy: Node3D = _make_copy(samples[warmed + index])
			if copy == null:
				continue
			add_child(copy)
			batch.append(copy)
		_place(batch, camera)
		warmed += count
		await tree.process_frame
		for copy: Node3D in batch:
			copy.queue_free()
		var now: int = Time.get_ticks_usec()
		var seconds: float = float(now - last_usec) / 1000000.0
		last_usec = now
		if seconds > frame_budget_seconds:
			per_frame = maxi(1, per_frame / 2)
		elif seconds < frame_budget_seconds / 3.0:
			per_frame = mini(max_per_frame, per_frame * 2)
	if own_camera != null:
		own_camera.queue_free()
	done = true


func _collect_node(node: Node) -> void:
	if node is MeshInstance3D:
		_collect_mesh(node as MeshInstance3D)
	elif node is MultiMeshInstance3D:
		_collect_multimesh(node as MultiMeshInstance3D)
	elif node is GPUParticles3D or node is CPUParticles3D:
		_add_duplicate(_particles_key(node), node)
	elif node is Label3D or node is Sprite3D or node is AnimatedSprite3D:
		_add_duplicate(_sprite_key(node as GeometryInstance3D), node)


func _collect_mesh(instance: MeshInstance3D) -> void:
	var mesh: Mesh = instance.mesh
	if mesh == null:
		return
	var skinned: bool = instance.skin != null or not instance.skeleton.is_empty()
	for surface: int in mesh.get_surface_count():
		var material: Material = instance.get_active_material(surface)
		var key: String = "mesh:%d:%d:%s" % [_id(material), _format(mesh, surface), skinned]
		_add(key, {"kind": "mesh", "mesh": mesh, "material": material})
	if instance.material_overlay != null:
		_add("overlay:%d" % instance.material_overlay.get_instance_id(),
			{"kind": "mesh", "mesh": mesh, "material": instance.material_overlay})


func _collect_multimesh(instance: MultiMeshInstance3D) -> void:
	var multimesh: MultiMesh = instance.multimesh
	if multimesh == null or multimesh.mesh == null:
		return
	var mesh: Mesh = multimesh.mesh
	var flags: String = "%d:%s:%s" % [multimesh.transform_format, multimesh.use_colors, multimesh.use_custom_data]
	for surface: int in mesh.get_surface_count():
		var material: Material = instance.material_override
		if material == null:
			material = mesh.surface_get_material(surface)
		var key: String = "multi:%d:%d:%s" % [_id(material), _format(mesh, surface), flags]
		_add(key, {"kind": "multimesh", "multimesh": multimesh, "material": material})


func _particles_key(node: Node) -> String:
	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		var passes: Array[int] = []
		for draw_pass: int in particles.draw_passes:
			var pass_mesh: Mesh = particles.get_draw_pass_mesh(draw_pass)
			var has_surface: bool = pass_mesh != null and pass_mesh.get_surface_count() > 0
			passes.append(_id(pass_mesh.surface_get_material(0)) if has_surface else 0)
		return "gpu:%d:%d:%s" % [_id(particles.process_material), _id(particles.material_override), passes]
	var cpu := node as CPUParticles3D
	var cpu_material: Material = cpu.material_override
	if cpu_material == null and cpu.mesh != null and cpu.mesh.get_surface_count() > 0:
		cpu_material = cpu.mesh.surface_get_material(0)
	return "cpu:%d:%s:%s" % [_id(cpu_material), cpu.color_ramp != null, cpu.color_initial_ramp != null]


func _sprite_key(node: GeometryInstance3D) -> String:
	return "%s:%d:%s:%s:%s:%d" % [node.get_class(), _id(node.material_override), node.get(&"billboard"),
		node.get(&"shaded"), node.get(&"double_sided"), int(node.get(&"alpha_cut"))]


## Copied now, off-tree: the source may be gone by the time it's drawn (an
## effect that frees itself while a slow machine is still warming).
func _add_duplicate(key: String, node: Node) -> void:
	if _seen.has(key):
		return
	var copy: Node3D = node.duplicate(0) as Node3D
	if copy == null:
		return
	for child: Node in copy.get_children():
		copy.remove_child(child)
		child.free()
	_kept.append(copy)
	_add(key, {"kind": "duplicate", "node": copy})


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for copy: Node in _kept:
			if is_instance_valid(copy) and not copy.is_inside_tree():
				copy.free()


func _add(key: String, sample: Dictionary) -> void:
	if _seen.has(key):
		return
	_seen[key] = true
	samples.append(sample)


func _make_copy(sample: Dictionary) -> Node3D:
	match String(sample["kind"]):
		"mesh":
			var instance := MeshInstance3D.new()
			instance.mesh = sample["mesh"]
			instance.material_override = sample["material"]
			return instance
		"multimesh":
			var source: MultiMesh = sample["multimesh"]
			var multimesh := MultiMesh.new()
			multimesh.transform_format = source.transform_format
			multimesh.use_colors = source.use_colors
			multimesh.use_custom_data = source.use_custom_data
			multimesh.mesh = source.mesh
			multimesh.instance_count = 1
			multimesh.set_instance_transform(0, Transform3D.IDENTITY)
			var instance := MultiMeshInstance3D.new()
			instance.multimesh = multimesh
			instance.material_override = sample["material"]
			return instance
		"duplicate":
			var source: Variant = sample["node"]
			if not is_instance_valid(source):
				return null
			var copy: Node3D = (source as Node).duplicate(0) as Node3D
			if copy == null:
				return null
			copy.visible = true
			if copy is GPUParticles3D:
				(copy as GPUParticles3D).emitting = true
			elif copy is CPUParticles3D:
				(copy as CPUParticles3D).emitting = true
			return copy
	return null


## A small grid facing the camera, each copy shrunk to item_size.
func _place(batch: Array[Node3D], camera: Camera3D) -> void:
	var columns: int = maxi(1, ceili(sqrt(float(batch.size()))))
	var view: Transform3D = camera.global_transform
	var spacing: float = item_size * 1.4
	for index: int in batch.size():
		var copy: Node3D = batch[index]
		var column: int = index % columns
		var row: int = index / columns
		var middle: float = (columns - 1) * 0.5
		var offset := Vector3((column - middle) * spacing, (middle - row) * spacing, -distance)
		var scale: float = item_size / maxf(_extent(copy), 0.001)
		copy.global_transform = Transform3D(view.basis.scaled(Vector3.ONE * scale), view * offset)


func _extent(copy: Node3D) -> float:
	if copy is VisualInstance3D:
		var box: AABB = (copy as VisualInstance3D).get_aabb()
		return maxf(box.size.x, maxf(box.size.y, box.size.z))
	return 1.0


static func _format(mesh: Mesh, surface: int) -> int:
	return mesh.surface_get_format(surface) if mesh is ArrayMesh else 0


static func _id(object: Object) -> int:
	return object.get_instance_id() if object != null else 0

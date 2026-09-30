extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_cargo_box_textures.gd
##
## Presupuesto de las 4 cajas de carga (assets/models/cargo/sm_cargo_box_{cube,vented,tall,flat}.glb):
## - El atlas de impresion albedo de cada caja mide como maximo 512x512 (N-315 lo bajo
##   de 2048). Falla si alguien vuelve a exportar a 2048 y se come la memoria de video.
## - Cada caja tiene al menos una malla con material y textura albedo.
## - Conserva los nodos Body, FlapBack, FlapFront, FlapLeft y FlapRight y exactamente
##   84 triangulos en total, para que un reexport no rompa las solapas (animacion de
##   apertura) ni cambie la geometria.

const VARIANTS: Array[String] = ["cube", "vented", "tall", "flat"]
const MAX_TEX: int = 512
const TRIANGLES: int = 84
const NODES: Array[String] = ["Body", "FlapBack", "FlapFront", "FlapLeft", "FlapRight"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for v in VARIANTS:
		var path: String = "res://assets/models/cargo/sm_cargo_box_%s.glb" % v
		var scene: PackedScene = load(path) as PackedScene
		_expect(scene != null, "%s loads as PackedScene (got %s)" % [path, scene])
		if scene == null:
			continue
		var inst: Node = scene.instantiate()
		root.add_child(inst)

		for n in NODES:
			_expect(inst.find_child(n, true, false) != null, "%s has node %s" % [v, n])

		var tris: int = 0
		var textured: int = 0
		for mi in _meshes(inst):
			var mesh: Mesh = mi.mesh
			for s in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(s)
				var idx = arrays[Mesh.ARRAY_INDEX]
				if idx != null and idx.size() > 0:
					tris += idx.size() / 3
				else:
					tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				var mat: Material = mi.get_active_material(s)
				if mat is BaseMaterial3D:
					var tex: Texture2D = (mat as BaseMaterial3D).albedo_texture
					if tex != null:
						textured += 1
						var w: int = tex.get_width()
						var h: int = tex.get_height()
						_expect(w <= MAX_TEX and h <= MAX_TEX,
							"%s albedo texture fits %dx%d (got %dx%d)" % [v, MAX_TEX, MAX_TEX, w, h])
		_expect(textured > 0, "%s has at least one surface with an albedo texture (got %d)" % [v, textured])
		_expect(tris == TRIANGLES, "%s has %d triangles (got %d)" % [v, TRIANGLES, tris])

		inst.queue_free()

	await process_frame
	if _failures == 0:
		print("PASS: cargo box GLBs keep 512 texture budget, flap nodes and 84 triangles")
	quit(_failures)


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

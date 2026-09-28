class_name RoutePowerLines
extends RefCounted
## Power lines along the road: poles through the same placement checks as any
## prop, strung together with sagging wires.

## Power lines (docs/tareas-nacho.md #27): wooden poles every
## POWER_POLE_SPACING metres down one side of the road, strung together with
## three sagging wires. Poles go through the same checks as any prop (and
## claim their ground first, so no tree grows through one); a pole that
## can't stand leaves a gap, and the wires only span poles close enough.
## All the poles are one MultiMesh and all the wire one mesh: two draw calls.
const POWER_POLE_SPACING: float = 36.0
const POWER_POLE_LATERAL: float = 9.6
const POWER_POLE_HEIGHT: float = 7.4
const POWER_MAX_SPAN: float = 58.0
const POWER_WIRE_SAG: float = 0.9
const POWER_WIRE_SEGMENTS: int = 10
const POWER_POLE_MODEL: String = "res://assets/models/environment/route/sm_env_route_power_pole.glb"
## Where the wires leave each pole, from the cross-arm's centre: the tips of
## the model's three insulators (two on the arm, one on top of the pole).
const POWER_WIRE_ANCHORS: Array[Vector3] = [Vector3(-0.75, 0.21, 0.0), Vector3(0.0, 0.45, 0.0), Vector3(0.75, 0.21,
		0.0)]
## One pole in this many carries a transformer.
const POWER_TRANSFORMER_EVERY: int = 4


var _dresser: RouteDresser
var _placement: RoutePlacement
var _route: Node3D
var _terrain: Node
var _seed: int
var power_poles: Array[Vector3] = []


func _init(dresser: RouteDresser, placement: RoutePlacement, route: Node3D, terrain: Node, seed_value: int) -> void:
	_dresser = dresser
	_placement = placement
	_route = route
	_terrain = terrain
	_seed = seed_value


func dress(segments: Array) -> void:
	var carried: float = 0.0
	for segment: RouteSegment in segments:
		if segment is TunnelSegment:
			carried = 0.0
			continue
		for slot: Transform3D in segment.get_dressing_slots(4.0):
			carried += 4.0
			if carried < POWER_POLE_SPACING:
				continue
			var p: Vector3 = segment.transform * (slot * Vector3(POWER_POLE_LATERAL, 0.0, 0.0))
			if _placement.misfit(p, 0.35, 8.6, 1.0, true, &"power_pole", 20.0) != &"":
				continue
			carried = 0.0
			_placement.occupy(p, 0.6)
			_placement.remember_kind(&"power_pole", p)
			power_poles.append(Vector3(p.x, _terrain.height_at(p), p.z))
			_placement.count(&"power_pole")
	if power_poles.size() >= 2:
		_build()


func _build() -> void:
	var holder := Node3D.new()
	holder.name = "PowerLines"
	_route.add_child(holder)
	# The pole is imported art (N-134, build_route_pieces.py): wood, braced
	# cross-arm, insulators; a transformer on every few. Still one MultiMesh
	# (a draw per material), and the same cylinder to hit.
	var meshes: Dictionary = _pole_meshes()
	var poles := MultiMesh.new()
	poles.transform_format = MultiMesh.TRANSFORM_3D
	poles.mesh = meshes.get("PowerPole")
	poles.instance_count = power_poles.size()
	var transformers := MultiMesh.new()
	transformers.transform_format = MultiMesh.TRANSFORM_3D
	transformers.mesh = meshes.get("Transformer")
	transformers.instance_count = ceili(float(power_poles.size()) / POWER_TRANSFORMER_EVERY)
	var colliders := StaticBody3D.new()
	colliders.name = "PowerPoleColliders"
	colliders.collision_layer = 1
	var tops: Array[Transform3D] = []
	for index: int in range(power_poles.size()):
		var base: Vector3 = power_poles[index]
		# The cross-arm (the model's X) lies across the line, square to the
		# neighbouring poles, with the wires running off it toward them.
		var along: Vector3 = (power_poles[mini(index + 1, power_poles.size() - 1)] - power_poles[maxi(index - 1, 0)])
		along.y = 0.0
		var yaw: float = atan2(along.x, along.z) if along.length() > 0.1 else 0.0
		var basis := Basis(Vector3.UP, yaw)
		poles.set_instance_transform(index, Transform3D(basis, base))
		if index % POWER_TRANSFORMER_EVERY == 0:
			transformers.set_instance_transform(floori(float(index) / float(POWER_TRANSFORMER_EVERY)),
					Transform3D(basis, base))
		var top := Transform3D(basis, base + Vector3.UP * (POWER_POLE_HEIGHT - 0.6))
		tops.append(top)
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.15
		cylinder.height = POWER_POLE_HEIGHT
		shape.shape = cylinder
		shape.position = base + Vector3.UP * (POWER_POLE_HEIGHT * 0.5 - 0.3)
		colliders.add_child(shape)
	for pair: Array in [[poles, "PowerPoles"], [transformers, "PowerPoleTransformers"]]:
		if (pair[0] as MultiMesh).mesh == null:
			continue
		var instance := MultiMeshInstance3D.new()
		instance.name = pair[1]
		instance.multimesh = pair[0]
		# No draw distance: it's measured from the middle of the whole line's
		# bounds, hundreds of metres away, and hid poles right beside you.
		holder.add_child(instance)
	holder.add_child(colliders)
	holder.add_child(_wires(tops))


## The pole model's meshes by node name ("PowerPole", "Transformer"), each
## flattened into one mesh with the kit's materials, ready for a MultiMesh.
## Falls back to the old bare cylinder if the model is missing.
func _pole_meshes() -> Dictionary:
	var meshes: Dictionary = {}
	var scene := load(POWER_POLE_MODEL) as PackedScene
	if scene == null:
		push_warning("Missing power pole model: " + POWER_POLE_MODEL)
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color("6b5238")
		var pole := CylinderMesh.new()
		pole.top_radius = 0.11
		pole.bottom_radius = 0.15
		pole.height = POWER_POLE_HEIGHT
		pole.radial_segments = 6
		pole.material = wood
		var shifted := SurfaceTool.new()
		shifted.append_from(pole, 0, Transform3D(Basis.IDENTITY, Vector3.UP * (POWER_POLE_HEIGHT * 0.5 - 0.3)))
		meshes["PowerPole"] = shifted.commit()
		return meshes
	var model := scene.instantiate() as Node3D
	LowpolyMaterials.apply(model)
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		var local: Transform3D = _relative_transform(model, part)
		var mesh := ArrayMesh.new()
		for surface: int in range(part.mesh.get_surface_count()):
			var tool := SurfaceTool.new()
			tool.append_from(part.mesh, surface, local)
			tool.commit(mesh)
			var material: Material = part.get_surface_override_material(surface)
			mesh.surface_set_material(surface,
					material if material != null else part.mesh.surface_get_material(surface))
		meshes[String(part.name)] = mesh
	model.free()
	return meshes


## `node`'s transform in `root`'s space, for a tree that isn't in the scene.
static func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node3D = node
	while current != null and current != root:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result


## Three wires from arm to arm, each a chain of thin boxes hanging in a
## parabola, all in one surface.
func _wires(tops: Array[Transform3D]) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var strand := BoxMesh.new()
	strand.size = Vector3(0.05, 0.05, 1.0)
	for index: int in range(tops.size() - 1):
		var a: Transform3D = tops[index]
		var b: Transform3D = tops[index + 1]
		if a.origin.distance_to(b.origin) > POWER_MAX_SPAN:
			continue
		for anchor: Vector3 in POWER_WIRE_ANCHORS:
			var start: Vector3 = a * anchor
			var finish: Vector3 = b * anchor
			var previous: Vector3 = start
			for step: int in range(1, POWER_WIRE_SEGMENTS + 1):
				var t: float = float(step) / POWER_WIRE_SEGMENTS
				var point: Vector3 = start.lerp(finish, t) + Vector3.DOWN * POWER_WIRE_SAG * 4.0 * t * (1.0 - t)
				var span: Vector3 = point - previous
				var basis := Basis.looking_at(span.normalized(),
						Vector3.UP) if absf(span.normalized().y) < 0.99 else Basis.IDENTITY
				# Stretched along its own length (local Z), not the world's.
				basis = basis * Basis.from_scale(Vector3(1.0, 1.0, span.length()))
				surface.append_from(strand, 0, Transform3D(basis, (previous + point) * 0.5))
				previous = point
	var mesh := MeshInstance3D.new()
	mesh.name = "PowerWires"
	mesh.mesh = surface.commit()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("2b2f33")
	mesh.material_override = metal
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh

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
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("6b5238")
	wood.roughness = 0.95
	var pole := CylinderMesh.new()
	pole.top_radius = 0.11
	pole.bottom_radius = 0.15
	pole.height = POWER_POLE_HEIGHT
	pole.radial_segments = 6
	pole.material = wood
	var arm := BoxMesh.new()
	arm.size = Vector3(1.8, 0.12, 0.12)
	arm.material = wood
	var poles := MultiMesh.new()
	poles.transform_format = MultiMesh.TRANSFORM_3D
	poles.mesh = pole
	poles.instance_count = power_poles.size()
	var arms := MultiMesh.new()
	arms.transform_format = MultiMesh.TRANSFORM_3D
	arms.mesh = arm
	arms.instance_count = power_poles.size()
	var colliders := StaticBody3D.new()
	colliders.name = "PowerPoleColliders"
	colliders.collision_layer = 1
	var tops: Array[Transform3D] = []
	for index: int in range(power_poles.size()):
		var base: Vector3 = power_poles[index]
		# The cross-arm faces along the line, toward the neighbouring pole.
		var along: Vector3 = (power_poles[mini(index + 1, power_poles.size() - 1)] - power_poles[maxi(index - 1, 0)])
		along.y = 0.0
		var yaw: float = atan2(along.x, along.z) if along.length() > 0.1 else 0.0
		var basis := Basis(Vector3.UP, yaw + PI * 0.5)
		poles.set_instance_transform(index,
				Transform3D(Basis.IDENTITY, base + Vector3.UP * (POWER_POLE_HEIGHT * 0.5 - 0.3)))
		var top := Transform3D(basis, base + Vector3.UP * (POWER_POLE_HEIGHT - 0.6))
		arms.set_instance_transform(index, top)
		tops.append(top)
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.15
		cylinder.height = POWER_POLE_HEIGHT
		shape.shape = cylinder
		shape.position = base + Vector3.UP * (POWER_POLE_HEIGHT * 0.5 - 0.3)
		colliders.add_child(shape)
	for pair: Array in [[poles, "PowerPoles"], [arms, "PowerPoleArms"]]:
		var instance := MultiMeshInstance3D.new()
		instance.name = pair[1]
		instance.multimesh = pair[0]
		# No draw distance: it's measured from the middle of the whole line's
		# bounds, hundreds of metres away, and hid poles right beside you.
		holder.add_child(instance)
	holder.add_child(colliders)
	holder.add_child(_wires(tops))


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
		for offset: float in [-0.75, 0.0, 0.75]:
			var start: Vector3 = a * Vector3(offset, 0.08, 0.0)
			var finish: Vector3 = b * Vector3(offset, 0.08, 0.0)
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

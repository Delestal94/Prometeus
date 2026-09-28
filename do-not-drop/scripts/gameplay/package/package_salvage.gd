extends Node
## Recoverable pieces are stable scene children on every peer. Their poses are
## derived from the host snapshot in truck space, so they survive late joins.

class SalvagePoint extends "res://scripts/gameplay/interaction/interactable.gd":
	var package: Node
	var index: int

	func get_prompt() -> String:
		if package.care.phase == &"lost" or (package.salvage_state.get("collected", []) as Array).has(index):
			return ""
		return "Recapturar criatura" if package._trap_kind() in [&"noisy", &"hostile"] else "Recuperar pieza"

	func interact(player: Node) -> void:
		if not get_prompt().is_empty() and _within_reach(player):
			package.collect_salvage(index, player, global_position)

var package: Node3D
var points: Array[Area3D] = []
var tape_mesh: MeshInstance3D
var toy_mesh: Node3D


func _ready() -> void:
	package = get_parent() as Node3D
	tape_mesh = MeshInstance3D.new()
	tape_mesh.name = "RepairTape"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.012, 0.67)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d9ad59")
	mesh.material = material
	tape_mesh.mesh = mesh
	package.add_child.call_deferred(tape_mesh)
	toy_mesh = Node3D.new()
	toy_mesh.name = "ReplacementHen"
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.23
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color("ffca36")
	rubber.roughness = 0.25
	sphere.material = rubber
	body.mesh = sphere
	toy_mesh.add_child(body)
	var head := MeshInstance3D.new()
	head.mesh = sphere
	head.scale = Vector3.ONE * 0.55
	head.position = Vector3(0, 0.13, -0.1)
	toy_mesh.add_child(head)
	var beak := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.035
	cone.height = 0.08
	beak.mesh = cone
	beak.rotation.x = -PI / 2.0
	beak.position = Vector3(0, 0.12, -0.19)
	toy_mesh.add_child(beak)
	package.add_child.call_deferred(toy_mesh)


func _process(_delta: float) -> void:
	var half: Vector3 = package.call(&"get_half_extents")
	tape_mesh.position.y = half.y + 0.013
	tape_mesh.scale.z = half.z * 2.0 / 0.67
	tape_mesh.visible = package.care.tape > 0 and not package.is_open
	toy_mesh.visible = package.care.substituted and package.is_open
	var data: Dictionary = package.salvage_state
	var parts: Array = data.get("parts", [])
	while points.size() < parts.size():
		_build_point(points.size())
	var vehicle: Node3D = package.call(&"_find_vehicle")
	for index: int in points.size():
		var point: Area3D = points[index]
		var collected: bool = (data.get("collected", []) as Array).has(index)
		var active: bool = index < parts.size() and not collected and package.care.phase != &"lost"
		point.visible = active
		point.collision_layer = 16 if active else 0
		if not active:
			continue
		var position: Vector3 = parts[index]
		if StringName(data.get("kind", "")) in [&"noisy", &"hostile"]:
			var run: Node = get_node_or_null(^"/root/RunManager")
			var time: float = float(run.get(&"elapsed_seconds")) if run != null else 0.0
			position += Vector3(sin(time * 2.2) * 0.42, absf(sin(time * 4.0)) * 0.08, cos(time * 1.8) * 0.35)
		var in_truck: bool = bool(data.get("aboard", false)) and vehicle != null
		point.global_position = vehicle.to_global(position) if in_truck else position
		point.global_basis = vehicle.global_basis if in_truck else Basis.IDENTITY


func _build_point(index: int) -> void:
	var point := SalvagePoint.new()
	point.name = "Salvage%d" % index
	point.package = package
	point.index = index
	point.top_level = true
	add_child(point)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.23
	shape.shape = sphere
	point.add_child(shape)
	var content: Resource = package.call(&"content_definition")
	if package._trap_kind() in [&"noisy", &"hostile"] and content != null and content.model != null:
		var model: Node3D = content.model.instantiate()
		for child: Node3D in model.get_children():
			child.visible = child.name == &"Intact"
		point.add_child(model)
	else:
		var visual := MeshInstance3D.new()
		var shard := PrismMesh.new()
		shard.size = Vector3(0.19, 0.13, 0.18)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("f5e8d5")
		shard.material = material
		visual.mesh = shard
		point.add_child(visual)
	var label := Label3D.new()
	label.text = "¡RECUPERAR!"
	label.font_size = 22
	label.pixel_size = 0.004
	label.position.y = 0.3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	point.add_child(label)
	points.append(point)

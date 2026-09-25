extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_contact_shadows.gd
##
## Fake contact shadows (tareas de Nacho N-308.2, presentation/contact_shadow.gd):
##   - the band is solid from `margin` inside the footprint and gone `margin`
##     outside it, measured in metres whatever the size;
##   - every parked car along the route has one draped on the terrain (every
##     vertex just over the ground, never under it), reaching past the car
##     on every side, out of the groups DressingBatcher folds;
##   - every delivery house has one around each block of walls;
##   - the depot has them under the cars outside, the dumpster and the pallets.

const ContactShadow = preload("res://scripts/presentation/contact_shadow.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# The shape of the band.
	var band: ArrayMesh = ContactShadow.mesh(Transform3D.IDENTITY, Vector2(4.0, 2.0), 0.5)
	var vertices: PackedVector3Array = band.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = band.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var solid_ok: bool = true
	var clear_ok: bool = true
	for index: int in range(vertices.size()):
		var v: Vector3 = vertices[index]
		if absf(v.x) < 2.0 and absf(v.z) < 1.0:
			solid_ok = solid_ok and colours[index].a > 0.99 and absf(v.x) <= 1.5 + 0.001 and absf(v.z) <= 0.5 + 0.001
		else:
			clear_ok = clear_ok and colours[index].a < 0.01 and (is_equal_approx(absf(v.x), 2.5) or is_equal_approx(absf(v.z), 1.5))
	_expect(solid_ok and clear_ok, "Solid from half a metre inside the footprint, gone half a metre outside it")
	var shadow_material: StandardMaterial3D = ContactShadow.material(0.5)
	_expect(shadow_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and shadow_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and shadow_material.albedo_color.v < 0.01 and shadow_material.vertex_color_use_as_albedo,
		"Unlit, see-through, black, faded by its vertices")
	_expect(ContactShadow.material(0.5) == shadow_material, "One shared material per strength")

	# Along the route.
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 777)
	network.set(&"world_house_count", 3)
	var route: Node3D = (load("res://scenes/gameplay/route/route.tscn") as PackedScene).instantiate()
	route.set(&"batch_dressing", false)
	root.add_child(route)
	await process_frame
	var terrain: Node = route.get(&"terrain")
	var counted: Dictionary = {&"parked_vehicle": 0}
	for node: Node in route.find_children("*", "Node3D", true, false):
		var rule: StringName = StringName(node.get_meta(&"rule", &""))
		if not counted.has(rule):
			continue
		counted[rule] = int(counted[rule]) + 1
		_expect_draped_patch(route, terrain, node as Node3D, "%s %s" % [rule, node.name])
	_expect(int(counted[&"parked_vehicle"]) > 0, "The test route has parked cars to check (%s)" % str(counted))
	for house: DeliveryHouse in route.get(&"houses"):
		var patches: Array = house.get_children().filter(func(child: Node) -> bool: return child.name.begins_with("ContactShadow"))
		var volumes: Array = DeliveryHouse.HOUSE_COLLIDERS[posmod(house.visual_variant, DeliveryHouse.HOUSE_VISUALS.size())]
		_expect(patches.size() == volumes.size(), "House %d has a patch around each block of walls (%d for %d)" % [house.house_index, patches.size(), volumes.size()])
		for index: int in range(mini(patches.size(), volumes.size())):
			var size: Vector3 = (patches[index] as MeshInstance3D).mesh.get_aabb().size
			var walls: Vector3 = volumes[index][0]
			_expect(size.x > walls.x + 1.5 and size.z > walls.z + 1.5, "House %d: the band reaches past its walls (%s around %s)" % [house.house_index, size, walls])
	route.free()
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)

	# The depot.
	var depot: Node3D = (load("res://scripts/gameplay/depot/depot.gd") as GDScript).new()
	depot.set(&"stock_extra_packages", false)
	root.add_child(depot)
	await process_frame
	var holder: Node = depot.get_node_or_null(^"ContactShadows")
	_expect(holder != null and holder.get_child_count() == (depot.get_script() as Script).get_script_constant_map().CONTACT_SHADOWS.size(),
		"The depot lays a patch under each car outside, the dumpster and the pallets")
	depot.free()
	await process_frame
	if _failures == 0:
		print("PASS: contact shadows lie under parked cars, houses and the depot's heavy things")
	quit(_failures)


## `node`'s band: laid over the terrain (every vertex just above the ground
## under it), covering the node's footprint with room to spare, casting no
## shadow, and not under a group DressingBatcher folds.
func _expect_draped_patch(route: Node3D, terrain: Node, node: Node3D, what: String) -> void:
	var patch := node.get_meta(&"contact_shadow", null) as MeshInstance3D
	_expect(patch != null, "%s has a contact shadow" % what)
	if patch == null:
		return
	_expect(not DressingBatcher.GROUPS.has(String(patch.get_parent().name)), "%s: its band stays out of the batched groups (%s)" % [what, patch.get_parent().name])
	_expect(patch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: the band casts no shadow of its own" % what)
	var to_route: Transform3D = route.global_transform.affine_inverse() * patch.global_transform
	var lowest: float = INF
	var highest: float = -INF
	var covered := AABB()
	var first: bool = true
	for vertex: Vector3 in (patch.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		var in_route: Vector3 = to_route * vertex
		var over: float = in_route.y - float(terrain.call(&"height_at", in_route))
		lowest = minf(lowest, over)
		highest = maxf(highest, over)
		covered = AABB(in_route, Vector3.ZERO) if first else covered.expand(in_route)
		first = false
	_expect(lowest > 0.01 and highest < 0.06, "%s: the band lies just over the ground everywhere (%.3f to %.3f m)" % [what, lowest, highest])
	var centre: Vector3 = route.global_transform.affine_inverse() * node.global_position
	var ground_plan := Rect2(covered.position.x, covered.position.z, covered.size.x, covered.size.z)
	_expect(ground_plan.grow(-0.3).has_point(Vector2(centre.x, centre.z)), "%s: the band lies under it (%s, at %s)" % [what, ground_plan, Vector2(centre.x, centre.z)])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

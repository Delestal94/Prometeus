extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_dressing_assets.gd
##
## The batch-2 art (docs/inventario-assets.md, 2026-09-23) only helps if it
## lands where it means something: a warning in front of the hazard it warns
## about and readable from the driver's seat, a curve arrow that bends the way
## the road does, the "entrega adelante" sign on the side the house is on,
## guardrails on the outside of a bend, a yard sitting on the ground instead of
## floating off a hillside, and a sky that is actually there in both modes.
## Fixed seed, so a failure here is reproducible rather than luck of the draw.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node("NetworkManager")
	var original_seed: int = int(network.world_seed)
	network.world_seed = 4242
	# A level-like environment, so RouteSky has a sky to convert.
	var world_environment := WorldEnvironment.new()
	world_environment.environment = Environment.new()
	world_environment.environment.sky = Sky.new()
	var procedural := ProceduralSkyMaterial.new()
	procedural.sky_top_color = Color(0.2, 0.3, 0.4)
	world_environment.environment.sky.sky_material = procedural
	root.add_child(world_environment)
	var route: Node3D = load("res://scenes/gameplay/route/route.tscn").instantiate() as Node3D
	# Five houses so the deck deals every model once.
	route.set(&"house_count", 5)
	# Checks individual signs, rails and yard pieces: keep them nodes.
	route.set(&"batch_dressing", false)
	root.add_child(route)
	for _i: int in range(3):
		await process_frame
	var terrain: Node = route.get(&"terrain")

	# Houses: every model used once, each with a grounded yard.
	var variants: Array[int] = []
	var farm_has_barn: bool = true
	for house: Node3D in route.get(&"houses"):
		variants.append(int(house.get(&"visual_variant")))
		var yard: Node = house.get_node_or_null(^"Yard")
		_expect(yard != null and _count(yard, "sm_env_yard_doormat") == 1, "House %d has its doormat" % house.get(&"house_index"))
		if yard == null:
			continue
		for piece: Node3D in yard.get_children():
			if piece.get_meta(&"on_porch", false):
				continue  # rides on the porch deck, not the ground
			var gap: float = RouteDresser.ground_gap(piece, route, terrain)
			_expect(gap <= 0.005 and gap >= -RouteDresser.SINK_RANGE.y - 0.005,"Yard piece %s sits on the ground (gap %.3f)" % [piece.scene_file_path.get_file(), gap])
		if String(DeliveryHouse.HOUSE_VISUALS[int(house.get(&"visual_variant"))]).ends_with("farmhouse.glb"):
			farm_has_barn = _count(yard, "sm_arch_barn") == 1
	variants.sort()
	_expect(variants == [0, 1, 2, 3, 4], "Five houses deal all five house models (%s)" % str(variants))
	_expect(farm_has_barn, "The farmhouse gets its barn")

	# Signs and guardrails, per segment.
	var hazards: int = 0
	var hazard_signs: int = 0
	var delivery_signs: int = 0
	var curves_checked: int = 0
	for segment: Node in route.get_children():
		if not segment is RouteSegment:
			continue
		var dressing: Node = segment.get_node_or_null(^"RoadsideDressing")
		var expected: String = RouteDresser.HAZARD_SIGNS.get(segment.get_script().get_global_name(), "")
		if expected != "":
			hazards += 1
			for sign_node: Node3D in _find(dressing, "/signs/" + expected.get_basename()):
				hazard_signs += 1
				# The face is authored on -Z; the approaching driver comes from
				# the segment's +Z side.
				var toward_driver: float = (-sign_node.global_basis.z.normalized()).dot(segment.global_basis.z.normalized())
				_expect(toward_driver > 0.7, "%s faces the approaching driver (%.2f)" % [expected, toward_driver])
				if segment is CurveSegment:
					var mirrored: bool = sign_node.global_basis.determinant() < 0.0
					_expect(mirrored == (segment.exit_offset.x < 0.0), "Curve arrow bends the same way as the road")
		if segment.has_meta(&"delivery_sign_side"):
			for sign_node: Node3D in _find(dressing, "sm_env_sign_delivery_ahead"):
				delivery_signs += 1
				var local_x: float = (segment as Node3D).to_local(sign_node.global_position).x
				_expect(signf(local_x) == float(segment.get_meta(&"delivery_sign_side")), "The delivery sign stands on the house's side")
		if segment is CurveSegment:
			var rails: Array[Node3D] = _find(dressing, "sm_env_prop_guardrail")
			if not rails.is_empty():
				curves_checked += 1
			for rail: Node3D in rails:
				# Along a bend the slots rotate with the road, so a raw local x
				# drifts. What stays true for an outside rail: its reflector
				# (authored on -Z) faces the inside of the turn, i.e. toward
				# the side the road bends to (turns stay under 90 degrees).
				var front: Vector3 = (segment as Node3D).global_basis.inverse() * (-rail.global_basis.z)
				_expect(signf(front.x) == signf(segment.exit_offset.x), "Guardrail sits on the outside of the bend, facing in")
	_expect(hazards > 0 and hazard_signs >= int(ceil(hazards * 0.8)), "Hazards get their warning sign (%d of %d)" % [hazard_signs, hazards])
	_expect(delivery_signs == 5, "One 'entrega adelante' per house (%d)" % delivery_signs)
	_expect(curves_checked > 0, "At least one curve got guardrails")

	# Far landmarks, and the windmill really turns.
	var landmarks: Array[Node3D] = _find(route, "/landmarks/")
	_expect(landmarks.size() >= 2, "Landmarks stand along the route (%d)" % landmarks.size())
	var rotor: Node3D = null
	for landmark: Node3D in landmarks:
		rotor = landmark.find_child("WindmillRotor", true, false) as Node3D
		if rotor != null:
			break
	if rotor != null:
		var before: float = rotor.rotation.z
		for _i: int in range(20):
			await process_frame
		_expect(not is_equal_approx(before, rotor.rotation.z), "The windmill sails turn")
	else:
		push_warning("No windmill on this seed; spin not checked")

	# Sky on the curated route...
	var sky: Node = route.get_node_or_null(^"Sky")
	_expect(sky is RouteSky, "The route builds its sky")
	if sky is RouteSky:
		var converted: ShaderMaterial = world_environment.environment.sky.sky_material as ShaderMaterial
		_expect(converted != null and converted.shader == RouteSky.SKY_SHADER, "The level sky is converted to the painted-cloud shader")
		_expect(converted != null and converted.get_shader_parameter(&"sky_top_color") == Color(0.2, 0.3, 0.4), "The converted sky keeps the level's own colours")
		_expect(sky.find_children("*", "MeshInstance3D", true, false).size() == sky.horizon.find_children("*", "MeshInstance3D", true, false).size(), "No 3D cloud meshes anymore, only the horizon")
		var horizon_mesh: MeshInstance3D = sky.horizon.find_children("*", "MeshInstance3D", true, false)[0]
		var material := horizon_mesh.get_surface_override_material(0) as ShaderMaterial
		_expect(material != null and material.shader == RouteSky.HORIZON_SHADER and material.shader.code.contains("fog_disabled"),
			"The horizon skips fog so it doesn't vanish into it (shaders/horizon_mountains)")
		_expect(material != null and (material.get_shader_parameter(&"top_y") as float) > (material.get_shader_parameter(&"foot_y") as float) + 40.0,
			"The horizon shader knows how high the ring reaches, to light the ridges and haze the foot")
	route.free()

	# ...and in endless mode, which never builds route.gd at all.
	var streamer := RouteStreamer.new()
	root.add_child(streamer)
	await process_frame
	_expect(streamer.get_node_or_null(^"Sky") is RouteSky, "Endless mode gets the same sky")
	streamer.free()
	world_environment.free()

	network.world_seed = original_seed
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: signs warn the right way from the right side, yards sit on the ground, landmarks turn, and the sky is up in both modes")
	quit(_failures)


func _find(parent: Node, fragment: String) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if parent == null:
		return found
	for node: Node in parent.find_children("*", "Node3D", true, false):
		if node.scene_file_path.contains(fragment):
			found.append(node as Node3D)
	return found


func _count(parent: Node, fragment: String) -> int:
	return _find(parent, fragment).size()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

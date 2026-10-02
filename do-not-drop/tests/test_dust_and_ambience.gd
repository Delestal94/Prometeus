extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_dust_and_ambience.gd
## Covers items #45 (ambient exterior sound) and #49/N-320 (dust behind the
## rear wheels) of docs/tareas-nacho.md / docs/especificaciones-visuales.md:
## - the world has an ambient wind loop;
## - wheel_dust.gd: two emitters (rear wheels), quiet while parked, nothing on
##   asphalt, full on gravel, thin on the verge, none in rain, none when the
##   viewer's camera is within CAMERA_CLEARANCE, dimmed at night;
## - the look: a quad (not a cube), unshaded, alpha-blended, no shadow, a colour
##   ramp that ends at alpha 0, a growing scale curve, 0.9-1.2 s of life, at most 32 puffs a wheel;
## - N-324, the exhaust smoke (vehicle_effects.gd) made the same soft way: a
##   QuadMesh (no SphereMesh) with its own cached billboard material (unshaded, no
##   shadow, alpha-blended, a soft radial falloff), a scale curve whose max_value
##   covers its biggest point (Curve clamps to 1 otherwise), a first puff <= 0.25 m
##   and a last one >= 1 m, a colour ramp clear at birth and at death that peaks at
##   0.55-0.9 (a veil, not foam), a pale grey lighter than asphalt with a mid-grey
##   floor at night, thrown back and up (+Z and +Y, a bit of -X) with a gentle rise,
##   an amount_ratio that rises with the throttle, thinner in rain and fog, quiet
##   near the viewer's camera, and 24-32 puffs at full quality;
## - and where it is born, measured on the real truck with its ramp out and its rear
##   doors open: the pipe within 0.4 m of the tail of the box (the art without the
##   ramp and the doors), on the driver's side, 0.5-1.0 m above the road (by a ray down,
##   after the suspension settles) and under
##   the cargo floor, more than 1.5 m from the cargo camera.

const WheelDust = preload("res://scripts/presentation/wheel_dust.gd")
## Loaded at run time, not preloaded: vehicle_effects.gd preloads vehicle.gd, which names autoloads that a
## --script does not have yet when it compiles (same as trailer_shot.gd in test_trailer_shots.gd).
const VEHICLE_EFFECTS_PATH: String = "res://scripts/presentation/vehicle_effects.gd"

var _failures: int = 0


## Stands in for the route's ground query (Route.ground_roughness()).
class StubRoute:
	extends Node
	var roughness: float = 0.0

	func ground_roughness(_world_point: Vector3) -> float:
		return roughness


func _initialize() -> void:
	await process_frame
	_test_ambience()
	await _test_dust()
	if _failures == 0:
		print("PASS: the world has ambient wind, and the rear wheels kick up dust by the ground and the weather")
	quit(_failures)


func _test_ambience() -> void:
	var route: Node3D = load("res://scenes/gameplay/route/route.tscn").instantiate()
	root.add_child(route)
	var player: AudioStreamPlayer = route.get_node(^"AmbientWind")
	_expect(player != null, "The route builds itself an ambient wind player")
	_expect(player.autoplay, "Ambience starts on its own, no trigger needed")
	var stream: AudioStreamWAV = player.stream
	_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Loops seamlessly instead of restarting with a click")
	var has_signal: bool = false
	for byte: int in stream.data:
		if byte != 0:
			has_signal = true
			break
	_expect(has_signal, "Actual filtered noise, not a silent buffer")
	route.free()


func _test_dust() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	level.start_debug_delivery()
	await process_frame
	var van: VehicleBody3D = level.vehicle
	van.controls_enabled = false
	var visual: Node3D = van.get_node(^"VehiclePresentation")
	var component: Node = visual.get_node_or_null(^"WheelDust")
	_expect(component != null, "The presentation builds a WheelDust component")
	if component == null:
		return
	var dust: Array[GPUParticles3D] = component.get(&"emitters")
	_expect(dust.size() == 2, "One dust emitter per rear wheel (got %d)" % dust.size())
	if dust.size() != 2:
		return
	for particles: GPUParticles3D in dust:
		_expect(particles.get_parent() == van, "The emitter hangs on the body, so it does not spin with the wheel")
		_expect(particles.position.z > 3.0, "It sits behind the rear axle (z %.2f)" % particles.position.z)
	_check_look(dust[0])
	_check_ground_factor()

	# The mood and the ground are fixed here (the level draws a random mood and
	# the real route's ground depends on where the van is).
	for route: Node in get_nodes_in_group(&"route"):
		route.remove_from_group(&"route")
	var ground := StubRoute.new()
	ground.add_to_group(&"route")
	root.add_child(ground)
	var dry: Dictionary = {"weather": WorldMood.Weather.CLEAR, "time": WorldMood.TimeOfDay.DAY, "rain": false}
	WorldMood.active = dry
	_expect(not _any_emitting(dust), "No dust while parked")
	await _test_exhaust(van, visual.get_node_or_null(^"VehicleEffects"))

	van.set_controls(0.9, 0.0, false)
	for _i: int in range(90):
		await physics_frame
	_expect(van.speed_kmh > 8.0, "The van is moving for the dust checks (%.1f km/h)" % van.speed_kmh)

	ground.roughness = 0.0
	_refresh(component)
	_expect(not _any_emitting(dust), "Asphalt: driving kicks up no dust")

	ground.roughness = 1.0
	_refresh(component)
	_expect(_any_emitting(dust), "Gravel: driving kicks up dust from a rear wheel")
	var gravel_ratio: float = _emitting_ratio(dust)

	ground.roughness = 0.25
	_refresh(component)
	_expect(_any_emitting(dust), "The verge: a thin trail")
	_expect(_emitting_ratio(dust) < gravel_ratio, "The verge's trail is thinner than the gravel's (%.2f vs %.2f)"
			% [_emitting_ratio(dust), gravel_ratio])

	ground.roughness = 1.0
	WorldMood.active = {"weather": WorldMood.Weather.RAIN, "time": WorldMood.TimeOfDay.DAY, "rain": true}
	_refresh(component)
	_expect(not _any_emitting(dust), "Rain: wet gravel raises no dust")
	WorldMood.active = {"weather": WorldMood.Weather.FOG, "time": WorldMood.TimeOfDay.DAY, "rain": false}
	_refresh(component)
	_expect(_any_emitting(dust) and _emitting_ratio(dust) < gravel_ratio, "Fog damps the dust a little")

	WorldMood.active = {"weather": WorldMood.Weather.CLEAR, "time": WorldMood.TimeOfDay.NIGHT, "rain": false}
	_refresh(component)
	var night: Color = (dust[0].process_material as ParticleProcessMaterial).color
	_expect(night.v < WheelDust.DUST_COLOR.v * 0.5, "At night the unshaded dust is dimmed (value %.2f)" % night.v)
	WorldMood.active = dry
	_refresh(component)

	# A passenger's camera right behind the wheel never has a puff born in its face.
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.global_position = dust[0].global_position + Vector3(0.0, 0.8, 0.3)
	camera.make_current()
	_refresh(component)
	_expect(not dust[0].emitting, "No emission within %.1f m of the viewer's camera" % WheelDust.CAMERA_CLEARANCE)
	camera.global_position = dust[0].global_position + Vector3(0.0, 3.0, 0.0)
	_refresh(component)
	_expect(dust[0].emitting, "Farther than that it emits again")
	camera.free()

	van.set_controls(0.0, 0.0, true)
	van.linear_velocity = Vector3.ZERO
	for _i: int in range(30):
		await physics_frame
	_refresh(component)
	_expect(not _any_emitting(dust), "Dust stops once the van is stationary again")

	WorldMood.active = {}
	ground.free()
	level.free()
	await create_timer(0.1).timeout


## The exhaust smoke (N-324): a soft pale quad puff, thicker under throttle,
## dimmed by the hour, thinned by the weather, quiet in the face of a camera.
func _test_exhaust(van: VehicleBody3D, effects: Node) -> void:
	# Let the suspension settle first: the pipe must not follow it.
	for _i: int in range(90):
		await physics_frame
	_expect(effects != null, "The presentation builds a VehicleEffects component")
	if effects == null:
		return
	var smoke: GPUParticles3D = effects.get(&"_exhaust")
	_expect(smoke != null, "The exhaust emitter is built on the truck")
	if smoke == null:
		return
	var mesh := smoke.draw_pass_1 as PrimitiveMesh
	_expect(mesh is QuadMesh, "The smoke is a quad, not a low-poly sphere")
	_expect(not mesh is SphereMesh, "No SphereMesh left in the exhaust")
	var standard := mesh.material as StandardMaterial3D if mesh != null else null
	_expect(standard != null, "The smoke mesh has a standard material")
	if standard != null:
		_expect(standard.billboard_mode == BaseMaterial3D.BILLBOARD_PARTICLES, "The puff faces the camera")
		_expect(standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Unshaded: no dark core")
		_expect(standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "The smoke is alpha-blended")
		_expect(standard.disable_receive_shadows, "The smoke receives no shadow")
		_expect(standard.albedo_texture != null, "The radial falloff texture softens the edge")
		_expect(standard == load(VEHICLE_EFFECTS_PATH).smoke_puff_material(), "The puff material is static and cached")
		var disc := standard.albedo_texture as GradientTexture2D
		_expect(disc != null and disc.fill == GradientTexture2D.FILL_RADIAL, "A radial disc")
		if disc != null:
			var falloff: Gradient = disc.gradient
			_expect(falloff.get_color(falloff.get_point_count() - 1).a == 0.0, "The rim of the disc is clear")
			_expect(falloff.get_color(0).a >= 0.95, "Full at the centre of the disc")
			_expect(falloff.sample(0.35).a >= 0.6 and falloff.sample(0.35).a <= 0.85,
					"Thinner already at 35 %% of the radius (%.2f)" % falloff.sample(0.35).a)
			_expect(falloff.sample(0.7).a <= 0.45, "A haze, not a ball, at 70 %% (%.2f)" % falloff.sample(0.7).a)
	_expect(smoke.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "The smoke casts no shadow")
	_expect(not smoke.one_shot and smoke.amount >= 24 and smoke.amount <= 32,
			"A continuous plume of a few big puffs (%d)" % smoke.amount)
	var material := smoke.process_material as ParticleProcessMaterial
	_expect(material.direction.x < 0.0 and material.direction.x >= -0.5,
			"A touch to the driver's side, not out behind the open door: %s" % material.direction)
	_expect(material.direction.z >= 0.8 and material.direction.y > 0.0 and material.direction.y <= 0.6,
			"Mostly back and a little up, so it shows in the opening and behind the tail")
	_expect(material.initial_velocity_min >= 1.2 and material.initial_velocity_max <= 2.6,
			"Fast enough to spread out into separate puffs (%.1f-%.1f)"
			% [material.initial_velocity_min, material.initial_velocity_max])
	_expect(material.damping_max <= 0.5,
			"Light damping, so a puff travels metres instead of stopping at the pipe (%.1f)" % material.damping_max)
	_expect(material.gravity.y > 0.0 and material.gravity.y <= 0.8,
			"And rises gently (%.2f)" % material.gravity.y)
	_test_exhaust_anchor(van, smoke)
	var quad: float = (smoke.draw_pass_1 as QuadMesh).size.x
	_expect(quad >= 0.4 and quad <= 0.5, "A ~0.45 m quad that grows (%.2f)" % quad)
	_expect(not smoke.local_coords, "The smoke stays in the world once born")
	var curve: Curve = (material.scale_curve as CurveTexture).curve
	var biggest: float = 0.0
	for index: int in range(curve.point_count):
		biggest = maxf(biggest, curve.get_point_position(index).y)
	_expect(biggest > 1.0, "The curve really grows past 1 (%.2f)" % biggest)
	_expect(curve.max_value >= biggest, "The scale curve's max_value (%.1f) covers its biggest point (%.2f)"
			% [curve.max_value, biggest])
	var first_size: float = quad * material.scale_max * curve.get_point_position(0).y
	var last_size: float = quad * material.scale_min * biggest
	_expect(first_size <= 0.25, "The first puff is at most 0.25 m (%.2f)" % first_size)
	_expect(last_size >= 1.0, "The last puff is at least 1 m (%.2f)" % last_size)
	_expect(smoke.lifetime >= 2.0 and smoke.lifetime <= 2.8, "Lives about 2.4 s (%.2f)" % smoke.lifetime)
	var ramp: Gradient = (material.color_ramp as GradientTexture1D).gradient
	_expect(ramp.get_color(0).a == 0.0 and ramp.get_color(ramp.get_point_count() - 1).a == 0.0,
			"Clear at birth and at death, no hard pop")
	var peak: float = 0.0
	for index: int in range(ramp.get_point_count()):
		peak = maxf(peak, ramp.get_color(index).a)
	_expect(peak >= 0.55 and peak <= 0.9, "A veil, not a solid ball of foam (peak alpha %.2f)" % peak)
	_expect(load(VEHICLE_EFFECTS_PATH).SMOKE_COLOR.get_luminance() > 0.6, "The smoke is lighter than the asphalt (%.2f)"
			% load(VEHICLE_EFFECTS_PATH).SMOKE_COLOR.get_luminance())
	_expect(smoke.visibility_aabb.end.z >= 25.0, "The culling box reaches the cloud left behind")

	# A far camera, an idle engine, then a full throttle; the light and weather fixed.
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.global_position = smoke.global_position + Vector3(0.0, 20.0, 0.0)
	camera.make_current()
	van.presentation_engine_running = true
	van.engine_force = 0.0
	effects.call(&"update_exhaust", 0.0)
	_expect(smoke.emitting, "The engine running: it smokes")
	var idle: float = smoke.amount_ratio
	_expect(idle >= 0.65 and idle <= 0.75, "Idle keeps ~70 %% of the puffs (%.2f)" % idle)
	van.engine_force = -1700.0
	effects.call(&"update_exhaust", 0.0)
	_expect(smoke.amount_ratio > idle, "Under throttle the plume is thicker (%.2f vs %.2f)"
			% [smoke.amount_ratio, idle])
	_expect(is_equal_approx(smoke.amount_ratio, 1.0), "Full throttle: every puff")
	van.presentation_engine_running = false
	effects.call(&"update_exhaust", 0.0)
	_expect(not smoke.emitting, "Engine off: no smoke")
	van.presentation_engine_running = true

	WorldMood.active = {"weather": WorldMood.Weather.CLEAR, "time": WorldMood.TimeOfDay.DAY, "rain": false}
	effects.call(&"sample_smoke_look")
	var day: Color = material.color
	_expect(is_equal_approx(day.a, 1.0), "Dry: the ramp's own alpha rules")
	WorldMood.active = {"weather": WorldMood.Weather.CLEAR, "time": WorldMood.TimeOfDay.NIGHT, "rain": false}
	effects.call(&"sample_smoke_look")
	_expect(material.color.v < day.v and material.color.v >= 0.45,
			"At night the smoke keeps a mid-grey floor, not lost in the dark asphalt (%.2f)" % material.color.v)
	_expect(is_equal_approx(material.color.a, 1.0), "And its alpha is not lowered at night")
	WorldMood.active = {"weather": WorldMood.Weather.RAIN, "time": WorldMood.TimeOfDay.DAY, "rain": true}
	effects.call(&"sample_smoke_look")
	var wet_alpha: float = load(VEHICLE_EFFECTS_PATH).SMOKE_WET_ALPHA
	_expect(is_equal_approx(material.color.a, wet_alpha), "Rain thins the smoke (alpha %.2f)"
			% material.color.a)
	WorldMood.active = {"weather": WorldMood.Weather.FOG, "time": WorldMood.TimeOfDay.DAY, "rain": false}
	effects.call(&"sample_smoke_look")
	_expect(material.color.a < 1.0, "Fog thins it too")

	camera.global_position = smoke.global_position + Vector3(0.0, 0.8, 0.3)
	effects.call(&"update_exhaust", 0.0)
	_expect(not smoke.emitting, "No puff is born within %.1f m of the viewer's camera" % WheelDust.CAMERA_CLEARANCE)
	camera.global_position = smoke.global_position + Vector3(0.0, 3.0, 0.0)
	effects.call(&"update_exhaust", 0.0)
	_expect(smoke.emitting, "Farther than that it smokes again")
	camera.free()
	van.engine_force = 0.0
	WorldMood.active = {"weather": WorldMood.Weather.CLEAR, "time": WorldMood.TimeOfDay.DAY, "rain": false}


## The pipe's place (N-324), on the real truck with its ramp out and its rear doors
## open (their default): from the cargo floor's box alone, so neither the suspension,
## the ramp nor the open doors move it. The reference is the art's own tail with
## those nodes left out, measured in vehicle space at run time.
func _test_exhaust_anchor(van: VehicleBody3D, smoke: GPUParticles3D) -> void:
	_expect(van.rear_ramp_deployed and van.is_door_open(&"rear"), "The ramp is out and the rear doors open")
	var floor_node := van.get_node_or_null(^"FloorCollision") as CollisionShape3D
	_expect(floor_node != null, "The truck has its cargo floor box")
	if floor_node == null:
		return
	var pipe: Vector3 = van.to_local(smoke.global_position)
	var anchor: Vector3 = load(VEHICLE_EFFECTS_PATH).exhaust_anchor(van)
	_expect(pipe.distance_to(anchor) < 0.15, "The emitter sits on the anchor (%s vs %s)" % [pipe, anchor])
	var tail: Dictionary = _art_rear_extent(van)
	var box_tail: float = tail["box"]
	var all_tail: float = tail["all"]
	print("  exhaust pipe in vehicle space %s; tail of the box z %.2f; with ramp and doors z %.2f"
			% [pipe, box_tail, all_tail])
	_expect(all_tail > box_tail + 0.5, "The ramp and doors do reach past the tail (%.2f > %.2f)"
			% [all_tail, box_tail])
	_expect(absf(pipe.z - box_tail) <= 0.4, "The pipe is at the tail of the box (z %.2f, tail %.2f)"
			% [pipe.z, box_tail])
	_expect(pipe.x < 0.0 and pipe.x > floor_node.position.x - 1.2,
			"On the driver's side, inside the body (x %.2f)" % pipe.x)
	var road: Array = _road_under(van, smoke.global_position)
	var above_road: float = smoke.global_position.y - float(road[0])
	print("  pipe %.2f m above the road (measured by %s)" % [above_road, road[1]])
	_expect(above_road >= 0.5 and above_road <= 1.0, "0.5-1.0 m above the road (%.2f m)" % above_road)
	var floor_size: Vector3 = (floor_node.shape as BoxShape3D).size
	var floor_bottom: float = floor_node.position.y - floor_size.y * 0.5
	_expect(pipe.y <= floor_bottom + 0.05, "Just under the cargo floor (y %.2f, floor %.2f)" % [pipe.y, floor_bottom])
	var cargo_camera := van.get_node_or_null(^"CargoBay/RackSeat2EyePoint") as Node3D
	if cargo_camera != null:
		var apart: float = (cargo_camera.position - pipe).length()
		print("  pipe to cargo camera: %.2f m" % apart)
		_expect(apart >= 1.5, "The pipe is not within 1.5 m of the cargo camera (%.2f m)" % apart)


## The road's height under a world point, once the truck has settled: [y, how]. A ray
## straight down (the road is on layer 1, like the truck's own mask); if there is no
## road in the test world, the rear wheel's contact point; and if the wheel is in the
## air, the 0.666 m the settled body rides above the road (vehicle.tscn).
func _road_under(van: VehicleBody3D, point: Vector3) -> Array:
	var query := PhysicsRayQueryParameters3D.create(point, point + Vector3(0.0, -6.0, 0.0), 1)
	query.exclude = [van.get_rid()]
	var hit: Dictionary = van.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return [(hit["position"] as Vector3).y, "a ray down"]
	var wheel := van.get_node_or_null(^"RearLeftWheel") as VehicleWheel3D
	if wheel != null and wheel.is_in_contact():
		return [wheel.get_contact_point().y, "the wheel's contact point"]
	return [van.global_position.y - 0.666, "the settled body height"]


## Rearmost z, in vehicle space, of the truck's art: "box" without the rear door
## leaves (their *_HINGE_Z nodes) and the ramp, "all" with everything.
func _art_rear_extent(van: VehicleBody3D) -> Dictionary:
	var to_vehicle: Transform3D = van.global_transform.affine_inverse()
	var body: Node = van.get_node(^"BodyVisuals")
	var extent: Dictionary = {"box": -INF, "all": -INF}
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var local: AABB = to_vehicle * mesh.global_transform * mesh.get_aabb()
		extent["all"] = maxf(extent["all"], local.end.z)
		var moving: bool = false
		var up: Node = mesh
		while up != null and up != body:
			if up.name.contains("HINGE") or up.name == &"RampVisual":
				moving = true
				break
			up = up.get_parent()
		if not moving:
			extent["box"] = maxf(extent["box"], local.end.z)
	return extent


func _refresh(component: Node) -> void:
	component.call(&"sample_now")
	component.call(&"update", 0.0)


func _any_emitting(dust: Array[GPUParticles3D]) -> bool:
	for particles: GPUParticles3D in dust:
		if particles.emitting:
			return true
	return false


func _emitting_ratio(dust: Array[GPUParticles3D]) -> float:
	var best: float = 0.0
	for particles: GPUParticles3D in dust:
		if particles.emitting:
			best = maxf(best, particles.amount_ratio)
	return best


func _check_ground_factor() -> void:
	_expect(WheelDust.ground_factor(0.0) == 0.0, "Asphalt (roughness 0) gets no dust")
	_expect(WheelDust.ground_factor(1.0) == 1.0, "Gravel (roughness 1) gets all of it")
	var verge: float = WheelDust.ground_factor(0.25)
	_expect(verge > 0.0 and verge < 1.0, "The verge (0.25) gets some (%.2f)" % verge)


## A soft, pale, see-through blob: not a cube, not shaded, casting no shadow
## (the first attempt came out opaque, orange, with a hard edge and a dark core).
func _check_look(particles: GPUParticles3D) -> void:
	var mesh := particles.draw_pass_1 as PrimitiveMesh
	_expect(mesh != null and not mesh is BoxMesh, "The dust is not made of cubes")
	var standard := mesh.material as StandardMaterial3D if mesh != null else null
	_expect(standard != null, "The dust mesh has a standard material")
	if standard != null:
		_expect(standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "The dust is alpha-blended, not opaque")
		_expect(standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Unshaded: no dark core")
		_expect(standard.vertex_color_use_as_albedo, "The colour ramp's alpha reaches the material")
	_expect(particles.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "The dust casts no shadow")
	_expect(particles.lifetime >= 0.9 and particles.lifetime <= 1.2, "Lives 0.9-1.2 s (%.2f)" % particles.lifetime)
	_expect(not particles.one_shot, "A continuous trail, not a burst")
	_expect(particles.amount <= 32, "Cheap: at most 32 puffs a wheel (%d)" % particles.amount)
	var material := particles.process_material as ParticleProcessMaterial
	_expect(material.direction.z > 0.5, "The dust goes backwards (+Z is the rear)")
	var ramp: Gradient = (material.color_ramp as GradientTexture1D).gradient
	var last: int = ramp.get_point_count() - 1
	_expect(ramp.get_color(last).a == 0.0, "The colour ramp ends at alpha 0")
	_expect(ramp.get_color(0).a > 0.0 and ramp.get_color(0).a <= 0.85,
			"It starts light, never opaque (alpha %.2f)" % ramp.get_color(0).a)
	var grow: Curve = (material.scale_curve as CurveTexture).curve
	_expect(grow.sample(1.0) > grow.sample(0.0) * 3.0, "The puff grows as it fades")
	var base: Color = WheelDust.DUST_COLOR
	_expect(base.v > 0.5 and base.s < 0.3 and base.r - base.b < 0.2, "Pale and desaturated, not orange")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

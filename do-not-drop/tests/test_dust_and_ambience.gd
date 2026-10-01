extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_dust_and_ambience.gd
## Covers items #45 (ambient exterior sound) and #49/N-320 (dust behind the
## rear wheels) of docs/tareas-nacho.md / docs/especificaciones-visuales.md:
## - the world has an ambient wind loop;
## - wheel_dust.gd: two emitters (rear wheels), quiet while parked, nothing on
##   asphalt, full on gravel, thin on the verge, none in rain, none when the
##   viewer's camera is within CAMERA_CLEARANCE, dimmed at night;
## - the look: a quad (not a cube), unshaded, alpha-blended, no shadow, a colour
##   ramp that ends at alpha 0, a growing scale curve, 0.9-1.2 s of life.

const WheelDust = preload("res://scripts/presentation/wheel_dust.gd")

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
	var material := particles.process_material as ParticleProcessMaterial
	_expect(material.direction.z > 0.5, "The dust goes backwards (+Z is the rear)")
	var ramp: Gradient = (material.color_ramp as GradientTexture1D).gradient
	var last: int = ramp.get_point_count() - 1
	_expect(ramp.get_color(last).a == 0.0, "The colour ramp ends at alpha 0")
	_expect(ramp.get_color(0).a > 0.0 and ramp.get_color(0).a <= 0.45,
			"It starts light, never opaque (alpha %.2f)" % ramp.get_color(0).a)
	var grow: Curve = (material.scale_curve as CurveTexture).curve
	_expect(grow.sample(1.0) > grow.sample(0.0) * 3.0, "The puff grows as it fades")
	var base: Color = WheelDust.DUST_COLOR
	_expect(base.v > 0.5 and base.s < 0.3 and base.r - base.b < 0.2, "Pale and desaturated, not orange")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

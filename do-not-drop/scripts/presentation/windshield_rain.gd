extends Node3D
class_name WindshieldRain
## Rain on the windshield and the wipers that sweep it (tareas de Nacho
## N-303). A copy of the windshield's own mesh, a hair inside the cab, carries
## shaders/windshield_rain.gdshader: drops land, creep down, and are wiped off
## exactly where the two blades pass. It only shows while it rains and this
## client's camera is inside the truck (VehiclePresentation.viewer_inside());
## its faces point into the cab and the back faces are culled, so from
## outside it's never drawn anyway. The blades are posed from the same clock
## and formula as the shader clears the glass with (sweep_angle()).
##
## The same glass also carries the mud of the low-visibility event (N-113,
## low_visibility_event.gd, shaders/windshield_mud.gdshader): a second overlay
## sharing the mesh, shown only to whoever is driving (the passenger at a
## window sees the road, and guides), from inside the cab. The wipers run
## while it lasts -- with the engine on -- and thin it a little each stroke.
##
## ReferenceTruck adds it once the model is up (setup()).

const SHADER: Shader = preload("res://shaders/windshield_rain.gdshader")
const MUD_SHADER: Shader = preload("res://shaders/windshield_mud.gdshader")
const PERIOD: float = 1.6
const SWEEP: float = 1.7
## Pivots along the bottom edge (fractions of the width) and the blade's
## reach (fractions of the height). A tandem pair, as on a real truck: both
## blades rest lying the same way (toward +x, the passenger side) and sweep up
## in step, parallel -- never crossing. The first blade parks just short of
## the second's pivot, and the second just short of the glass's edge.
const PIVOTS: Array[float] = [0.18, 0.58]
const BLADE_REACH: float = 0.75
## How far inside the glass the drops sit, toward the cab.
const INSET: float = 0.012
const ARM_COLOR := Color("1d2226")
## The mud sits a hair nearer the cab than the drops.
const MUD_INSET: float = 0.004
## Mud brightness by WorldMood time of day (day, dusk, night): unshaded, it
## would glow in the dark.
const MUD_LIGHT: Array[float] = [1.0, 0.72, 0.4]

var vehicle: VehicleBody3D
var overlay: MeshInstance3D
var material: ShaderMaterial
var arms: Array[Node3D] = []
var mud_overlay: MeshInstance3D
var mud_material: ShaderMaterial
## The low-visibility event as this client last heard it (EventBus): seconds
## in, how long it lasts and how many have landed (so each looks different).
var mud_active: bool = false
var mud_elapsed: float = 0.0
var mud_duration: float = 0.0
var mud_count: int = 0
## Seconds the wipers have been running; the shader's and the arms' clock.
var wiper_time: float = 0.0
var raining: bool = false
var width: float = 1.0
var height: float = 1.0


## Builds the overlay from `windshield` (a MeshInstance3D of the truck model)
## and the two wiper arms. Everything lives in this node, which takes the
## glass's own frame: x across, y up the glass, z into the cab.
func setup(truck: VehicleBody3D, windshield: MeshInstance3D) -> void:
	vehicle = truck
	var to_frame: Transform3D = _glass_frame(windshield)
	transform = _local_frame(to_frame)
	overlay = MeshInstance3D.new()
	overlay.name = "RainOverlay"
	overlay.mesh = _overlay_mesh(windshield, to_frame)
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"wiper_period", PERIOD)
	material.set_shader_parameter(&"wiper_sweep", SWEEP)
	material.set_shader_parameter(&"pivot_a", Vector2(PIVOTS[0], 0.02))
	material.set_shader_parameter(&"pivot_b", Vector2(PIVOTS[1], 0.02))
	material.set_shader_parameter(&"blade_reach", BLADE_REACH)
	material.set_shader_parameter(&"aspect", width / maxf(height, 0.01))
	overlay.material_override = material
	add_child(overlay)
	_build_mud(overlay.mesh)
	for index: int in range(PIVOTS.size()):
		arms.append(_build_arm(index))
	_refresh(0.0)


func _build_mud(mesh: Mesh) -> void:
	mud_overlay = MeshInstance3D.new()
	mud_overlay.name = "MudOverlay"
	mud_overlay.mesh = mesh
	mud_overlay.position.z = MUD_INSET
	mud_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mud_overlay.visible = false
	mud_material = ShaderMaterial.new()
	mud_material.shader = MUD_SHADER
	for key: StringName in [&"wiper_period", &"wiper_sweep", &"pivot_a", &"pivot_b", &"blade_reach", &"aspect"]:
		mud_material.set_shader_parameter(key, material.get_shader_parameter(key))
	mud_overlay.material_override = mud_material
	add_child(mud_overlay)
	# By path, not by name: naming an autoload here would break compiling this
	# script wherever the autoloads are not up yet (the tests load it first).
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"low_visibility_changed", _on_low_visibility_changed)


## The blades' angle at time `t`: flat along the bottom edge at 0, up to SWEEP
## and back each PERIOD. The shader uses the same formula.
static func sweep_angle(t: float) -> float:
	return SWEEP * 0.5 * (1.0 - cos(TAU * t / PERIOD))


func _process(delta: float) -> void:
	_refresh(delta)


func _on_low_visibility_changed(is_starting: bool, _kind: StringName, duration: float, seconds_in: float) -> void:
	mud_active = is_starting
	mud_duration = duration
	mud_elapsed = seconds_in
	if is_starting:
		mud_count += 1
		# The wipers' clock as the mud lands: only strokes after it thin it.
		mud_material.set_shader_parameter(&"mud_since", wiper_time)
		mud_material.set_shader_parameter(&"pattern", float(mud_count) * 1.618)
		var time_of_day: int = clampi(int(WorldMood.active.get("time", 0)), 0, MUD_LIGHT.size() - 1)
		mud_material.set_shader_parameter(&"brightness", MUD_LIGHT[time_of_day])


func _local_peer_id() -> int:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	return int(network.call(&"local_id")) if network != null else 1


## Whether this client is the one at the wheel: the only one the mud is on.
func _local_is_driving() -> bool:
	return vehicle != null and int(vehicle.get(&"driver_peer_id")) == _local_peer_id()


func _refresh(delta: float) -> void:
	raining = bool(WorldMood.active.get("rain", false))
	var presentation: Node = vehicle.get_node_or_null(^"VehiclePresentation") if vehicle != null else null
	var inside: bool = presentation != null and bool(presentation.call(&"viewer_inside"))
	# The wipers work in the rain, and against mud.
	var engine_on: bool = vehicle != null and bool(vehicle.get(&"presentation_engine_running"))
	var running: bool = (raining or mud_active) and engine_on
	# The wipers run while it rains and the engine's on; parked, they rest flat.
	if running:
		wiper_time += delta
	elif sweep_angle(wiper_time) > 0.01:
		# Finish the stroke back down to rest rather than freezing mid-glass.
		wiper_time += delta
		if fmod(wiper_time, PERIOD) < delta:
			wiper_time = floorf(wiper_time / PERIOD) * PERIOD
	overlay.visible = raining and inside
	material.set_shader_parameter(&"wiper_time", wiper_time)
	material.set_shader_parameter(&"rain_amount", 0.85 if raining else 0.0)
	var angle: float = sweep_angle(wiper_time)
	for arm: Node3D in arms:
		arm.rotation.z = angle
	_refresh_mud(delta, inside)


func _refresh_mud(delta: float, inside: bool) -> void:
	if mud_active:
		mud_elapsed += delta
	var shown: bool = mud_active and inside and _local_is_driving()
	mud_overlay.visible = shown
	if not shown:
		return
	mud_material.set_shader_parameter(&"coverage", LowVisibilityPlan.coverage(mud_elapsed, mud_duration))
	mud_material.set_shader_parameter(&"wiper_time", wiper_time)
	mud_material.set_shader_parameter(&"wipers_on", 1.0)


func _build_arm(index: int) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "WiperPivot%d" % index
	pivot.position = Vector3((PIVOTS[index] - 0.5) * width, -height * 0.5 + 0.02 * height, -0.02)
	add_child(pivot)
	var length: float = BLADE_REACH * height
	var arm := MeshInstance3D.new()
	arm.name = "WiperArm"
	var box := BoxMesh.new()
	box.size = Vector3(length, 0.018, 0.012)
	var arm_material := StandardMaterial3D.new()
	arm_material.albedo_color = ARM_COLOR
	arm_material.roughness = 0.5
	box.material = arm_material
	arm.mesh = box
	# Lying along the bottom edge toward +x at rest.
	arm.position = Vector3(length * 0.5, 0.0, 0.0)
	pivot.add_child(arm)
	return pivot


## The glass's own frame, in the truck's space: origin at the glass's centre,
## x across, y up the glass (bottom edge to top edge), z its normal into the
## cab. Measures width and height on the way.
func _glass_frame(windshield: MeshInstance3D) -> Transform3D:
	var to_truck: Transform3D = vehicle.global_transform.affine_inverse() * windshield.global_transform
	var points := PackedVector3Array()
	var arrays: Array = windshield.mesh.surface_get_arrays(0)
	for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		points.append(to_truck * vertex)
	var low: float = INF
	var high: float = -INF
	for p: Vector3 in points:
		low = minf(low, p.y)
		high = maxf(high, p.y)
	var bottom := Vector3.ZERO
	var top := Vector3.ZERO
	var bottom_count: int = 0
	var top_count: int = 0
	var left: float = INF
	var right: float = -INF
	for p: Vector3 in points:
		left = minf(left, p.x)
		right = maxf(right, p.x)
		if p.y < low + (high - low) * 0.1:
			bottom += p
			bottom_count += 1
		elif p.y > high - (high - low) * 0.1:
			top += p
			top_count += 1
	bottom /= maxf(bottom_count, 1)
	top /= maxf(top_count, 1)
	var up: Vector3 = (top - bottom).normalized()
	var across := Vector3.RIGHT
	var into_cab: Vector3 = across.cross(up).normalized()
	# The truck faces -Z: the cab is behind the glass.
	if into_cab.z < 0.0:
		into_cab = -into_cab
	width = right - left
	height = top.distance_to(bottom)
	var centre: Vector3 = (top + bottom) * 0.5
	centre.x = (left + right) * 0.5
	return Transform3D(Basis(across, up, into_cab), centre + into_cab * INSET)


## This node's transform in its parent's space for a frame given in the truck's.
func _local_frame(frame_in_truck: Transform3D) -> Transform3D:
	var parent_in_truck: Transform3D = vehicle.global_transform.affine_inverse() * (get_parent() as Node3D).global_transform
	return parent_in_truck.affine_inverse() * frame_in_truck


## The windshield's triangles moved into this node's frame, with UVs across
## (x) and up (y) the glass, facing into the cab.
func _overlay_mesh(windshield: MeshInstance3D, frame: Transform3D) -> ArrayMesh:
	var to_frame: Transform3D = frame.affine_inverse() * vehicle.global_transform.affine_inverse() * windshield.global_transform
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var source := SurfaceTool.new()
	source.create_from(windshield.mesh, 0)
	var arrays: Array = source.commit_to_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var order: PackedInt32Array = indices
	if order.is_empty():
		for index: int in range(vertices.size()):
			order.append(index)
	for i: int in range(0, order.size() - 2, 3):
		var tri: Array[Vector3] = []
		for j: int in range(3):
			var p: Vector3 = to_frame * vertices[order[i + j]]
			p.z = 0.0
			tri.append(p)
		# Wind every triangle so its front faces into the cab (+z).
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).z > 0.0:
			tri = [tri[0], tri[2], tri[1]]
		for p: Vector3 in tri:
			tool.set_uv(Vector2(p.x / width + 0.5, p.y / height + 0.5))
			tool.set_normal(Vector3.BACK)
			tool.add_vertex(p)
	return tool.commit()

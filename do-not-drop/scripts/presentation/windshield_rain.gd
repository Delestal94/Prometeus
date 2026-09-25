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
## ReferenceTruck adds it once the model is up (setup()).

const SHADER: Shader = preload("res://shaders/windshield_rain.gdshader")
const PERIOD: float = 1.6
const SWEEP: float = 1.7
## Pivots along the bottom edge (fractions of the width) and the blade's
## reach (fractions of the height).
const PIVOTS: Array[float] = [0.28, 0.72]
const BLADE_REACH: float = 0.9
## How far inside the glass the drops sit, toward the cab.
const INSET: float = 0.012
const ARM_COLOR := Color("1d2226")

var vehicle: VehicleBody3D
var overlay: MeshInstance3D
var material: ShaderMaterial
var arms: Array[Node3D] = []
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
	for index: int in range(PIVOTS.size()):
		arms.append(_build_arm(index))
	_refresh(0.0)


## The blades' angle at time `t`: flat along the bottom edge at 0, up to SWEEP
## and back each PERIOD. The shader uses the same formula.
static func sweep_angle(t: float) -> float:
	return SWEEP * 0.5 * (1.0 - cos(TAU * t / PERIOD))


func _process(delta: float) -> void:
	_refresh(delta)


func _refresh(delta: float) -> void:
	raining = bool(WorldMood.active.get("rain", false))
	var presentation: Node = vehicle.get_node_or_null(^"VehiclePresentation") if vehicle != null else null
	var inside: bool = presentation != null and bool(presentation.call(&"viewer_inside"))
	var running: bool = raining and vehicle != null and bool(vehicle.get(&"presentation_engine_running"))
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
	for index: int in range(arms.size()):
		var side: float = 1.0 if PIVOTS[index] < 0.5 else -1.0
		arms[index].rotation.z = angle * side


func _build_arm(index: int) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "WiperPivot%d" % index
	pivot.position = Vector3((PIVOTS[index] - 0.5) * width, -height * 0.5 + 0.02 * height, -0.02)
	add_child(pivot)
	var side: float = 1.0 if PIVOTS[index] < 0.5 else -1.0
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
	# Lying along the bottom edge toward the middle of the glass at rest.
	arm.position = Vector3(side * length * 0.5, 0.0, 0.0)
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

class_name DashboardRouteMap
extends MeshInstance3D
## The route line of the dashboard GPS (expansion D-0308.1c): the stretch of the planned path around the vehicle,
## seen from above with the vehicle's heading up, drawn faint behind the distance and the arrow.
## Presentation only: it is handed the polyline (world x, z) of CompanyGps.guidance() and the vehicle's transform.
##
## Space: the screen's own (X to the right, Y up, the driver on -Z), like DashboardGps.

## Metres of road the screen covers ahead of the vehicle and to each side.
const RANGE_AHEAD_M: float = 120.0
const RANGE_SIDE_M: float = 100.0
## Where the vehicle sits on the screen and how large a metre is on it.
const ORIGIN := Vector2(0.0, -0.062)
const METRES_TO_SCREEN: float = 0.001
const LINE_WIDTH: float = 0.006
const LINE_COLOR := Color("ffc93c", 0.55)


func _init() -> void:
	name = "RouteMap"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = LINE_COLOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material
	# Never null: ReferenceTruck.set_paint walks every MeshInstance3D under the model.
	mesh = ArrayMesh.new()
	visible = false


## Redraws the path for a vehicle at `position` (x, z) whose right and forward directions on the ground are
## `right` and `forward`. An empty or one-point path hides the line.
func show_route(polyline: PackedVector2Array, position: Vector2, right: Vector2, forward: Vector2) -> void:
	var segments: PackedVector2Array = screen_segments(polyline, position, right, forward)
	visible = not segments.is_empty()
	if not visible:
		mesh = ArrayMesh.new()
		return
	mesh = _ribbon(segments)


## The path as pairs of screen points {a0, b0, a1, b1, ...} (metres turned into screen units), the vehicle at ORIGIN
## and its heading up, with each piece cut to the stretch the screen covers.
static func screen_segments(
	polyline: PackedVector2Array, position: Vector2, right: Vector2, forward: Vector2
) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in polyline.size() - 1:
		var a: Vector2 = _local(polyline[i], position, right, forward)
		var b: Vector2 = _local(polyline[i + 1], position, right, forward)
		var cut: PackedVector2Array = _clip(a, b)
		if cut.size() == 2:
			out.append(ORIGIN + cut[0] * METRES_TO_SCREEN)
			out.append(ORIGIN + cut[1] * METRES_TO_SCREEN)
	return out


## `point` in metres relative to the vehicle: x to its right, y ahead of it.
static func _local(point: Vector2, position: Vector2, right: Vector2, forward: Vector2) -> Vector2:
	var d: Vector2 = point - position
	return Vector2(d.dot(right), d.dot(forward))


## The part of the segment a-b inside the visible rectangle (Liang-Barsky), or an empty array when none of it is.
static func _clip(a: Vector2, b: Vector2) -> PackedVector2Array:
	var low := Vector2(-RANGE_SIDE_M, -20.0)
	var high := Vector2(RANGE_SIDE_M, RANGE_AHEAD_M)
	var d: Vector2 = b - a
	var t0: float = 0.0
	var t1: float = 1.0
	for axis in 2:
		for edge in 2:
			var p: float = -d[axis] if edge == 0 else d[axis]
			var q: float = (a[axis] - low[axis]) if edge == 0 else (high[axis] - a[axis])
			if is_zero_approx(p):
				if q < 0.0:
					return PackedVector2Array()
				continue
			var r: float = q / p
			if p < 0.0:
				t0 = maxf(t0, r)
			else:
				t1 = minf(t1, r)
			if t0 > t1:
				return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])


static func _ribbon(segments: PackedVector2Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	for i in range(0, segments.size() - 1, 2):
		var a: Vector2 = segments[i]
		var b: Vector2 = segments[i + 1]
		if a.is_equal_approx(b):
			continue
		var side: Vector2 = (b - a).normalized().orthogonal() * (LINE_WIDTH * 0.5)
		var corners: Array[Vector3] = [
			_on_screen(a - side), _on_screen(a + side), _on_screen(b + side), _on_screen(b - side),
		]
		for index: int in [0, 1, 2, 0, 2, 3]:
			vertices.append(corners[index])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var built := ArrayMesh.new()
	if not vertices.is_empty():
		built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built


## A screen point as a vertex, a hair in front of the glass (toward the driver, -Z) and behind the labels.
static func _on_screen(point: Vector2) -> Vector3:
	return Vector3(point.x, point.y, -0.001)

class_name CargoBeeMesh
extends RefCounted
## One bee as one mesh with colour per vertex (N-109.3), so a MultiMesh can draw
## the whole swarm in a single call and every bee is yellow AND black: a yellow
## body with two black stripes, a black head and sting, and two white, see-through
## wings. The nose points along +Y (cargo_animal_view.gd turns each instance to its
## heading); the wings sit on the -Z side, which is up once the instance is
## turned. About 0.1 m long: at the distance the crew sees the swarm from it is a
## cloud of small striped insects, not confetti.
##
## Built once and shared by every swarm. Unshaded, with alpha for the wings only.

const YELLOW := Color("ffcf1f")
const BLACK := Color("191510")
const WING := Color(1.0, 1.0, 1.0, 0.55)

static var _mesh: ArrayMesh
static var _material: StandardMaterial3D


static func mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = _build()
	return _mesh


static func _build() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	# Body, two stripes on it, head, sting.
	_ellipsoid(vertices, colors, indices, Vector3.ZERO, Vector3(0.03, 0.052, 0.03), YELLOW)
	_ellipsoid(vertices, colors, indices, Vector3(0.0, 0.013, 0.0), Vector3(0.0293, 0.0085, 0.0293), BLACK)
	_ellipsoid(vertices, colors, indices, Vector3(0.0, -0.017, 0.0), Vector3(0.0288, 0.0085, 0.0288), BLACK)
	_ellipsoid(vertices, colors, indices, Vector3(0.0, 0.058, 0.0), Vector3(0.015, 0.012, 0.015), BLACK)
	_ellipsoid(vertices, colors, indices, Vector3(0.0, -0.06, 0.0), Vector3(0.006, 0.012, 0.006), BLACK)
	# Wings: thin ellipses swept back and out from the shoulders.
	for side: float in [-1.0, 1.0]:
		_ellipsoid(vertices, colors, indices, Vector3(side * 0.034, 0.008, -0.026), Vector3(0.034, 0.016, 0.003),
				WING, deg_to_rad(side * 25.0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	built.surface_set_material(0, material())
	return built


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		# The body is opaque inside an alpha pass: without depth writes the black
		# far side of a bee paints over its yellow near side.
		_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	return _material


## An ellipsoid of 6 x 4 segments, turned `roll` radians about Y, appended to the arrays.
static func _ellipsoid(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array,
		centre: Vector3, radii: Vector3, colour: Color, roll: float = 0.0) -> void:
	var longitudes: int = 6
	var latitudes: int = 4
	var first: int = vertices.size()
	var turn := Basis(Vector3.BACK, roll)
	for lat: int in range(latitudes + 1):
		var polar: float = PI * float(lat) / latitudes
		for lon: int in range(longitudes):
			var azimuth: float = TAU * float(lon) / longitudes
			var unit := Vector3(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth))
			vertices.append(centre + turn * (unit * radii))
			colors.append(colour)
	for lat: int in range(latitudes):
		for lon: int in range(longitudes):
			var a: int = first + lat * longitudes + lon
			var b: int = first + lat * longitudes + (lon + 1) % longitudes
			var c: int = a + longitudes
			var d: int = b + longitudes
			indices.append_array([a, c, b, b, c, d])

extends RefCounted
## Fake contact shadows (tareas de Nacho N-308.2): GL Compatibility has no
## SSAO and no Decal nodes, so where something heavy meets the ground -- a
## parked car, a house, a stack of pallets -- a soft dark band lies around
## its base. It is a flat mesh, unlit and see-through, casting no shadow and
## never colliding, with one shared material per strength.
##
## The band is measured in metres, not as a share of the patch: full
## strength from `margin` inside the footprint's edge, fading to nothing
## `margin` outside it -- so a house and a hay bale get the same soft edge.
## Built as a 4 x 4 grid of vertices whose alpha does the fading; on uneven
## ground each vertex can sit on the terrain (`ground`), so the band neither
## floats nor sinks where the slope bends.

## Off the ground just enough not to flicker against it.
const LIFT: float = 0.03

static var _materials: Dictionary = {}  # opacity -> StandardMaterial3D


## A band around a `footprint` (x by z) centred on `centre`, on flat ground
## in `parent`'s space. Returns the new node.
static func add(parent: Node3D, centre: Vector3, footprint: Vector2, margin: float, opacity: float = 0.5) -> MeshInstance3D:
	var patch := instance(mesh(Transform3D(Basis.IDENTITY, centre), footprint, margin), opacity)
	# Readable when there are several (ContactShadow2...): a house with a wing.
	parent.add_child(patch, true)
	return patch


static func instance(band: ArrayMesh, opacity: float) -> MeshInstance3D:
	var patch := MeshInstance3D.new()
	patch.name = "ContactShadow"
	patch.mesh = band
	patch.material_override = material(opacity)
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return patch


## The band as a mesh: the footprint is laid out on `frame`'s XZ plane
## around its origin; the vertices end up in the frame's parent space. With
## `ground` (a Callable taking that space's point and returning the ground's
## height there) every vertex sits LIFT over the ground instead of on the
## frame's plane.
static func mesh(frame: Transform3D, footprint: Vector2, margin: float, ground: Callable = Callable()) -> ArrayMesh:
	var half := footprint * 0.5
	var xs: Array[float] = [-half.x - margin, -maxf(half.x - margin, 0.0), maxf(half.x - margin, 0.0), half.x + margin]
	var zs: Array[float] = [-half.y - margin, -maxf(half.y - margin, 0.0), maxf(half.y - margin, 0.0), half.y + margin]
	var vertices := PackedVector3Array()
	var colours := PackedColorArray()
	for row: int in range(4):
		for column: int in range(4):
			var point: Vector3 = frame * Vector3(xs[column], 0.0, zs[row])
			point.y = (float(ground.call(point)) if ground.is_valid() else point.y) + LIFT
			vertices.append(point)
			var inside: bool = row in [1, 2] and column in [1, 2]
			colours.append(Color(1.0, 1.0, 1.0, 1.0 if inside else 0.0))
	var indices := PackedInt32Array()
	for row: int in range(3):
		for column: int in range(3):
			var a: int = row * 4 + column
			indices.append_array([a, a + 1, a + 5, a, a + 5, a + 4])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var band := ArrayMesh.new()
	band.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return band


static func material(opacity: float = 0.5) -> StandardMaterial3D:
	var key: int = roundi(opacity * 100.0)
	if not _materials.has(key):
		var shadow := StandardMaterial3D.new()
		shadow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shadow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shadow.vertex_color_use_as_albedo = true
		shadow.albedo_color = Color(0.0, 0.0, 0.0, opacity)
		shadow.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = shadow
	return _materials[key]
